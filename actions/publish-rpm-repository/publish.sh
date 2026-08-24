#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

normalize_bool() {
  case "${1,,}" in
    true|false) printf '%s' "${1,,}" ;;
    *) fail "expected true or false, got: $1" ;;
  esac
}

rpm_path=${INPUT_RPM_PATH:?rpm-path is required}
repository_path=${INPUT_REPOSITORY_PATH:?repository-path is required}
s3_bucket=${INPUT_S3_BUCKET:-}
distribution_id=${INPUT_CLOUDFRONT_DISTRIBUTION_ID:-}
public_base_url=${INPUT_PUBLIC_BASE_URL:-}
package_keys_path=${INPUT_PACKAGE_SIGNING_KEYS_PATH:?package-signing-keys-path is required}
package_master_public_key=${INPUT_PACKAGE_MASTER_PUBLIC_KEY_ASC:?package master public key is required}
package_master_fingerprint=${INPUT_PACKAGE_MASTER_FINGERPRINT:?package master fingerprint is required}
authorized_package_repo_fingerprints=${INPUT_AUTHORIZED_PACKAGE_REPO_FINGERPRINTS:?authorized package repo fingerprints are required}
package_key_bundle_filename=${INPUT_PACKAGE_KEY_BUNDLE_FILENAME:-RPM-GPG-KEY-OpenCHAMI-Packages}
signing_key_b64=${INPUT_METADATA_SIGNING_KEY_ARMORED_B64:?metadata signing key is required}
signing_fingerprint=${INPUT_METADATA_SIGNING_KEY_FINGERPRINT:?metadata signing fingerprint is required}
signing_passphrase=${INPUT_METADATA_SIGNING_KEY_PASSPHRASE:-}
key_filename=${INPUT_REPOSITORY_KEY_FILENAME:-RPM-GPG-KEY-OpenCHAMI}
require_signed_rpms=$(normalize_bool "${INPUT_REQUIRE_SIGNED_RPMS:-true}")
dry_run=$(normalize_bool "${INPUT_DRY_RUN:-false}")

repository_path=${repository_path#/}
repository_path=${repository_path%/}
[[ -n "$repository_path" ]] || fail 'repository-path cannot be empty'
[[ "$repository_path" != *'..'* ]] || fail 'repository-path cannot contain ..'
[[ "$repository_path" =~ ^[A-Za-z0-9._/-]+$ ]] || fail 'repository-path contains unsupported characters'
[[ "$key_filename" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'repository-key-filename contains unsupported characters'
[[ "$package_key_bundle_filename" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'package-key-bundle-filename contains unsupported characters'
[[ "$package_master_fingerprint" =~ ^[A-Fa-f0-9]{40,64}$ ]] || fail 'package master fingerprint must be a full fingerprint'
[[ "$signing_fingerprint" =~ ^[A-Fa-f0-9]{40,64}$ ]] || fail 'metadata signing fingerprint must be a full fingerprint'
[[ -d "$package_keys_path" ]] || fail "package-signing-keys-path does not exist: $package_keys_path"
if [[ "$dry_run" == 'false' ]]; then
  [[ -n "$s3_bucket" ]] || fail 's3-bucket is required unless dry-run is true'
  [[ "$s3_bucket" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || fail 'invalid S3 bucket name'
  command -v aws >/dev/null 2>&1 || fail 'aws CLI is required for publication'
fi

for command in createrepo_c rpm gpg base64 sha256sum; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

work_root=$(mktemp -d "${RUNNER_TEMP:-/tmp}/openchami-rpm-repo.XXXXXX")
repository_dir="$work_root/repository"
packages_dir="$repository_dir/Packages"
package_keys_dir="$repository_dir/keys/packages"
repo_keys_dir="$package_keys_dir/repository"
ephemeral_keys_dir="$package_keys_dir/ephemeral"
package_key_bundle="$repository_dir/$package_key_bundle_filename"
gnupg_home="$work_root/gnupg"
package_trust_gnupg="$work_root/package-trust-gnupg"
package_rpm_db="$work_root/package-rpmdb"
package_master_key_file="$work_root/package-master.pub.asc"
signing_key_file="$work_root/metadata-signing-key.asc"
mkdir -p "$packages_dir" "$repo_keys_dir" "$ephemeral_keys_dir" \
  "$gnupg_home" "$package_trust_gnupg" "$package_rpm_db"
chmod 700 "$gnupg_home" "$package_trust_gnupg" "$package_rpm_db"

cleanup() {
  if [[ -f "$signing_key_file" ]]; then
    shred -u "$signing_key_file" 2>/dev/null || rm -f "$signing_key_file"
  fi
  if [[ -d "$gnupg_home" ]]; then
    find "$gnupg_home" -type f -exec shred -u {} + 2>/dev/null || true
    rm -rf "$gnupg_home"
  fi
  rm -rf "$package_trust_gnupg" "$package_rpm_db"
  rm -f "$package_master_key_file"
}
trap cleanup EXIT

export GNUPGHOME=$gnupg_home

if [[ "$dry_run" == 'false' ]]; then
  echo 'Restoring existing immutable packages from S3...'
  aws s3 sync "s3://$s3_bucket/$repository_path/Packages/" "$packages_dir/" \
    --exclude '*' --include '*.rpm' --only-show-errors
  aws s3 sync "s3://$s3_bucket/$repository_path/keys/packages/" "$package_keys_dir/" \
    --exclude '*' --include '*.asc' --only-show-errors
fi

mapfile -d '' incoming_rpms < <(
  if [[ -f "$rpm_path" ]]; then
    [[ "$rpm_path" == *.rpm ]] && printf '%s\0' "$rpm_path"
  elif [[ -d "$rpm_path" ]]; then
    find "$rpm_path" -type f -name '*.rpm' -print0
  else
    fail "rpm-path does not exist: $rpm_path"
  fi
)
(( ${#incoming_rpms[@]} > 0 )) || fail "no RPMs found at $rpm_path"

for rpm_file in "${incoming_rpms[@]}"; do
  destination="$packages_dir/$(basename "$rpm_file")"
  if [[ -e "$destination" ]]; then
    cmp -s "$rpm_file" "$destination" || fail "immutable RPM collision: $(basename "$rpm_file")"
    continue
  fi
  cp "$rpm_file" "$destination"
done

public_key_fingerprint() {
  local key_file=$1
  local fingerprints
  fingerprints=$(gpg --batch --with-colons --import-options show-only --import "$key_file" 2>/dev/null |
    awk -F: '$1 == "pub" {want=1; count++} want && $1 == "fpr" {print $10; want=0} END {if (count != 1) exit 1}') ||
    fail "expected exactly one public key in $key_file"
  printf '%s' "$fingerprints"
}

archive_public_key() {
  local source_file=$1
  local destination_file=$2
  if [[ -e "$destination_file" ]]; then
    cmp -s "$source_file" "$destination_file" || fail "public-key collision: $(basename "$destination_file")"
    return
  fi
  cp "$source_file" "$destination_file"
}

check_certification() {
  local signer_id=${1: -16}
  local subject_fingerprint=$2
  gpg --batch --check-sigs --with-colons "$subject_fingerprint" 2>/dev/null |
    awk -F: -v signer_id="${signer_id^^}" \
      '$1 == "sig" && $2 == "!" && toupper($5) == signer_id {found=1} END {exit !found}'
}

printf '%s\n' "$package_master_public_key" > "$package_master_key_file"
actual_package_master_fingerprint=$(public_key_fingerprint "$package_master_key_file")
[[ "${actual_package_master_fingerprint^^}" == "${package_master_fingerprint^^}" ]] ||
  fail 'package master public key does not match package-master-fingerprint'

declare -A authorized_repo_fingerprints=()
while IFS= read -r authorized_fingerprint; do
  [[ -n "$authorized_fingerprint" ]] || continue
  [[ "$authorized_fingerprint" =~ ^[A-Fa-f0-9]{40,64}$ ]] ||
    fail "invalid authorized package repository fingerprint: $authorized_fingerprint"
  authorized_repo_fingerprints["${authorized_fingerprint^^}"]=1
done < <(tr ',[:space:]' '\n' <<<"$authorized_package_repo_fingerprints")
(( ${#authorized_repo_fingerprints[@]} > 0 )) || fail 'authorized package repository fingerprint allowlist is empty'

mapfile -d '' incoming_ephemeral_keys < <(find "$package_keys_path" -type f -name 'ephemeral.pub.asc' -print0)
(( ${#incoming_ephemeral_keys[@]} > 0 )) || fail 'no ephemeral.pub.asc package signing keys found'
for ephemeral_key in "${incoming_ephemeral_keys[@]}"; do
  repo_key="$(dirname "$ephemeral_key")/repo-cert.pub.asc"
  [[ -f "$repo_key" ]] || fail "repo-cert.pub.asc not found beside $ephemeral_key"
  repo_fingerprint=$(public_key_fingerprint "$repo_key")
  ephemeral_fingerprint=$(public_key_fingerprint "$ephemeral_key")
  [[ -n "${authorized_repo_fingerprints[${repo_fingerprint^^}]:-}" ]] ||
    fail "package repository key is not authorized for new ephemeral keys: $repo_fingerprint"

  pair_gnupg=$(mktemp -d "$work_root/package-key-pair.XXXXXX")
  chmod 700 "$pair_gnupg"
  GNUPGHOME="$pair_gnupg" gpg --batch --import \
    "$package_master_key_file" "$repo_key" "$ephemeral_key" >/dev/null 2>&1
  GNUPGHOME="$pair_gnupg" check_certification "$package_master_fingerprint" "$repo_fingerprint" ||
    fail "incoming package repository key is not certified by the trusted master: $repo_fingerprint"
  GNUPGHOME="$pair_gnupg" check_certification "$repo_fingerprint" "$ephemeral_fingerprint" ||
    fail "incoming ephemeral package key is not certified by its authorized repository key: $ephemeral_fingerprint"
  rm -rf "$pair_gnupg"

  archive_public_key "$repo_key" "$repo_keys_dir/${repo_fingerprint^^}.asc"
  archive_public_key "$ephemeral_key" "$ephemeral_keys_dir/${ephemeral_fingerprint^^}.asc"
done

export GNUPGHOME=$package_trust_gnupg
gpg --batch --import "$package_master_key_file" >/dev/null 2>&1

mapfile -d '' repo_key_files < <(find "$repo_keys_dir" -type f -name '*.asc' -print0)
mapfile -d '' ephemeral_key_files < <(find "$ephemeral_keys_dir" -type f -name '*.asc' -print0)
(( ${#repo_key_files[@]} > 0 )) || fail 'no authenticated package repository keys available'
(( ${#ephemeral_key_files[@]} > 0 )) || fail 'no authenticated ephemeral package keys available'

repo_fingerprints=()
for repo_key_file in "${repo_key_files[@]}"; do
  repo_fingerprints+=("$(public_key_fingerprint "$repo_key_file")")
  gpg --batch --import "$repo_key_file" >/dev/null 2>&1
done

ephemeral_fingerprints=()
for ephemeral_key_file in "${ephemeral_key_files[@]}"; do
  ephemeral_fingerprints+=("$(public_key_fingerprint "$ephemeral_key_file")")
  gpg --batch --import "$ephemeral_key_file" >/dev/null 2>&1
done

for repo_fingerprint in "${repo_fingerprints[@]}"; do
  check_certification "$package_master_fingerprint" "$repo_fingerprint" ||
    fail "package repository key is not certified by the trusted master: $repo_fingerprint"
done

for ephemeral_fingerprint in "${ephemeral_fingerprints[@]}"; do
  certified=false
  for repo_fingerprint in "${repo_fingerprints[@]}"; do
    if check_certification "$repo_fingerprint" "$ephemeral_fingerprint"; then
      certified=true
      break
    fi
  done
  [[ "$certified" == 'true' ]] || fail "ephemeral package key is not certified by a trusted repository key: $ephemeral_fingerprint"
done

gpg --batch --armor --export "${ephemeral_fingerprints[@]}" > "$package_key_bundle"
[[ -s "$package_key_bundle" ]] || fail 'package signing public-key bundle was empty'

if [[ "$require_signed_rpms" == 'true' ]]; then
  rpm --dbpath "$package_rpm_db" --initdb
  rpm --dbpath "$package_rpm_db" --import "$package_key_bundle"
  while IFS= read -r -d '' rpm_file; do
    signature_result=$(rpm --dbpath "$package_rpm_db" -K "$rpm_file" 2>&1) ||
      fail "RPM signature verification failed: $rpm_file: $signature_result"
    grep -Eqi 'digests signatures OK|signatures OK' <<<"$signature_result" ||
      fail "RPM signature verification was not trusted: $rpm_file: $signature_result"
  done < <(find "$packages_dir" -type f -name '*.rpm' -print0)
fi

export GNUPGHOME=$gnupg_home

printf '%s' "$signing_key_b64" | base64 --decode > "$signing_key_file"
gpg --batch --import "$signing_key_file"
shred -u "$signing_key_file" 2>/dev/null || rm -f "$signing_key_file"

gpg --batch --with-colons --list-secret-keys "$signing_fingerprint" |
  awk -F: -v expected="${signing_fingerprint^^}" \
    '/^fpr:/ && toupper($10) == expected {found=1} END {exit !found}' ||
  fail 'requested metadata signing secret key was not imported'

gpg --batch --armor --export "$signing_fingerprint" > "$repository_dir/$key_filename"
[[ -s "$repository_dir/$key_filename" ]] || fail 'metadata public-key export was empty'

createrepo_c --update "$repository_dir"
repomd="$repository_dir/repodata/repomd.xml"
[[ -s "$repomd" ]] || fail 'createrepo_c did not produce repomd.xml'
rm -f "$repomd.asc"

gpg_args=(
  --batch
  --yes
  --armor
  --detach-sign
  --local-user "${signing_fingerprint}!"
  --output "$repomd.asc"
)
if [[ -n "$signing_passphrase" ]]; then
  printf '%s' "$signing_passphrase" |
    gpg "${gpg_args[@]}" --pinentry-mode loopback --passphrase-fd 0 "$repomd"
else
  gpg "${gpg_args[@]}" "$repomd"
fi
gpg --batch --verify "$repomd.asc" "$repomd"

package_count=$(find "$packages_dir" -type f -name '*.rpm' | wc -l | tr -d ' ')
repomd_sha256=$(sha256sum "$repomd" | awk '{print $1}')
invalidation_id=''

if [[ "$dry_run" == 'false' ]]; then
  destination="s3://$s3_bucket/$repository_path"
  echo 'Uploading immutable RPMs...'
  aws s3 sync "$packages_dir/" "$destination/Packages/" \
    --exclude '*' --include '*.rpm' \
    --cache-control 'public,max-age=31536000,immutable' \
    --only-show-errors

  aws s3 sync "$package_keys_dir/" "$destination/keys/packages/" \
    --exclude '*' --include '*.asc' \
    --cache-control 'public,max-age=31536000,immutable' \
    --only-show-errors

  echo 'Uploading content-addressed repository metadata...'
  while IFS= read -r -d '' metadata_file; do
    relative_path=${metadata_file#"$repository_dir/"}
    aws s3 cp "$metadata_file" "$destination/$relative_path" \
      --cache-control 'public,max-age=300,must-revalidate' \
      --only-show-errors
  done < <(find "$repository_dir/repodata" -type f \
    ! -name 'repomd.xml' ! -name 'repomd.xml.asc' -print0)

  aws s3 cp "$repository_dir/$key_filename" "$destination/$key_filename" \
    --cache-control 'public,max-age=300,must-revalidate' \
    --content-type 'application/pgp-keys' \
    --only-show-errors
  aws s3 cp "$package_key_bundle" "$destination/$package_key_bundle_filename" \
    --cache-control 'public,max-age=300,must-revalidate' \
    --content-type 'application/pgp-keys' \
    --only-show-errors
  aws s3 cp "$repomd.asc" "$destination/repodata/repomd.xml.asc" \
    --cache-control 'public,max-age=300,must-revalidate' \
    --content-type 'application/pgp-signature' \
    --only-show-errors

  echo 'Publishing repomd.xml commit point...'
  aws s3 cp "$repomd" "$destination/repodata/repomd.xml" \
    --cache-control 'public,max-age=300,must-revalidate' \
    --content-type 'application/xml' \
    --only-show-errors

  if [[ -n "$distribution_id" ]]; then
    invalidation_id=$(aws cloudfront create-invalidation \
      --distribution-id "$distribution_id" \
      --paths "/$repository_path/repodata/*" "/$repository_path/$key_filename" \
        "/$repository_path/$package_key_bundle_filename" \
      --query 'Invalidation.Id' --output text)
  fi
fi

if [[ -n "$public_base_url" ]]; then
  repository_url="${public_base_url%/}/$repository_path"
elif [[ -n "$s3_bucket" ]]; then
  repository_url="s3://$s3_bucket/$repository_path"
else
  repository_url="file://$repository_dir"
fi

{
  echo "repository-directory=$repository_dir"
  echo "repository-url=$repository_url"
  echo "package-count=$package_count"
  echo "repomd-sha256=$repomd_sha256"
  echo "invalidation-id=$invalidation_id"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

echo "Generated repository with $package_count package(s): $repository_url"
