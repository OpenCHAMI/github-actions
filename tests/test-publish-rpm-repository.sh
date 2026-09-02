#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

set -euo pipefail

dnf install -y -q createrepo_c rpm-build rpm-sign gnupg2

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
export HOME="$work_dir/home"
mkdir -p "$HOME" "$HOME/rpmbuild"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

package_gnupg="$work_dir/package-gnupg"
metadata_gnupg="$work_dir/metadata-gnupg"
mkdir -m 700 "$package_gnupg" "$metadata_gnupg"

fingerprint_for_uid() {
  GNUPGHOME="$package_gnupg" gpg --batch --with-colons --list-secret-keys |
    awk -F: -v marker="$1" '/^fpr:/ {fpr=$10} /^uid:/ && index($10, marker) {print fpr; exit}'
}

GNUPGHOME="$package_gnupg" gpg --batch --passphrase '' --quick-generate-key \
  'OpenCHAMI Test Master <test-master@openchami.org>' rsa2048 cert 0
package_master_fingerprint=$(fingerprint_for_uid 'test-master@openchami.org')
GNUPGHOME="$package_gnupg" gpg --batch --passphrase '' --quick-generate-key \
  'OpenCHAMI Test Repository <test-repo@openchami.org>' rsa2048 cert 0
package_repo_fingerprint=$(fingerprint_for_uid 'test-repo@openchami.org')
GNUPGHOME="$package_gnupg" gpg --batch --yes --quick-sign-key \
  --local-user "$package_master_fingerprint" "$package_repo_fingerprint"
GNUPGHOME="$package_gnupg" gpg --batch --passphrase '' --quick-generate-key \
  'OpenCHAMI Test Package <test-package@openchami.org>' rsa2048 sign 1d
package_fingerprint=$(fingerprint_for_uid 'test-package@openchami.org')
GNUPGHOME="$package_gnupg" gpg --batch --yes --quick-sign-key \
  --local-user "$package_repo_fingerprint" "$package_fingerprint"

package_keys_dir="$work_dir/package-keys/test-package"
mkdir -p "$package_keys_dir"
GNUPGHOME="$package_gnupg" gpg --batch --armor \
  --export "${package_repo_fingerprint}!" > "$package_keys_dir/repo-cert.pub.asc"
GNUPGHOME="$package_gnupg" gpg --batch --armor \
  --export "${package_fingerprint}!" > "$package_keys_dir/ephemeral.pub.asc"
package_master_public_key=$(GNUPGHOME="$package_gnupg" gpg --batch --armor \
  --export "${package_master_fingerprint}!")

cat > "$HOME/rpmbuild/SPECS/openchami-publisher-test.spec" <<'SPEC'
Name: openchami-publisher-test
Version: 1.0.0
Release: 1%{?dist}
Summary: Test package for the RPM repository publisher
License: MIT
BuildArch: noarch

%description
Test package for the OpenCHAMI RPM repository publisher action.

%install
mkdir -p %{buildroot}/usr/share/openchami-publisher-test
printf 'publisher test\n' > %{buildroot}/usr/share/openchami-publisher-test/result

%files
/usr/share/openchami-publisher-test/result
SPEC

rpmbuild -bb "$HOME/rpmbuild/SPECS/openchami-publisher-test.spec"
test_rpm=$(find "$HOME/rpmbuild/RPMS" -type f -name '*.rpm' -print -quit)

cat > "$HOME/.rpmmacros" <<MACROS
%_signature gpg
%_gpg_name $package_fingerprint
%__gpg /usr/bin/gpg
%_gpg_digest_algo sha256
MACROS
GNUPGHOME="$package_gnupg" rpmsign --addsign "$test_rpm"
rpm --checksig "$test_rpm" 2>&1 | grep -Eqi '(pgp|rsa).*signature'

GNUPGHOME="$metadata_gnupg" gpg --batch --pinentry-mode loopback \
  --passphrase 'metadata-test-passphrase' --quick-generate-key \
  'OpenCHAMI Test Repository Metadata <test-repository@openchami.org>' rsa2048 sign 0
metadata_fingerprint=$(GNUPGHOME="$metadata_gnupg" gpg --batch --with-colons --list-secret-keys |
  awk -F: '/^fpr:/ {print $10; exit}')
metadata_key_b64=$(GNUPGHOME="$metadata_gnupg" gpg --batch --pinentry-mode loopback \
  --passphrase 'metadata-test-passphrase' --armor --export-secret-keys "$metadata_fingerprint" |
  base64 -w0)

output_file="$work_dir/action-output"
touch "$output_file"
GITHUB_OUTPUT="$output_file" \
RUNNER_TEMP="$work_dir" \
INPUT_RPM_PATH="$test_rpm" \
INPUT_REPOSITORY_PATH='stable/el9/x86_64' \
INPUT_PACKAGE_SIGNING_KEYS_PATH="$work_dir/package-keys" \
INPUT_PACKAGE_MASTER_PUBLIC_KEY_ASC="$package_master_public_key" \
INPUT_PACKAGE_MASTER_FINGERPRINT="$package_master_fingerprint" \
INPUT_AUTHORIZED_PACKAGE_REPO_FINGERPRINTS="$package_repo_fingerprint" \
INPUT_METADATA_SIGNING_KEY_ARMORED_B64="$metadata_key_b64" \
INPUT_METADATA_SIGNING_KEY_FINGERPRINT="$metadata_fingerprint" \
INPUT_METADATA_SIGNING_KEY_PASSPHRASE='metadata-test-passphrase' \
INPUT_REQUIRE_SIGNED_RPMS='true' \
INPUT_DRY_RUN='true' \
  ./actions/publish-rpm-repository/publish.sh

repository_dir=$(awk -F= '$1 == "repository-directory" {print substr($0, index($0, "=") + 1)}' "$output_file")
package_count=$(awk -F= '$1 == "package-count" {print $2}' "$output_file")
[[ "$package_count" == '1' ]]
[[ -s "$repository_dir/repodata/repomd.xml" ]]
[[ -s "$repository_dir/repodata/repomd.xml.asc" ]]
[[ -s "$repository_dir/RPM-GPG-KEY-OpenCHAMI" ]]
[[ -s "$repository_dir/RPM-GPG-KEY-OpenCHAMI-Packages" ]]

verify_gnupg="$work_dir/verify-gnupg"
mkdir -m 700 "$verify_gnupg"
GNUPGHOME="$verify_gnupg" gpg --batch --import "$repository_dir/RPM-GPG-KEY-OpenCHAMI"
GNUPGHOME="$verify_gnupg" gpg --batch --verify \
  "$repository_dir/repodata/repomd.xml.asc" \
  "$repository_dir/repodata/repomd.xml"

GNUPGHOME="$package_gnupg" gpg --batch --passphrase '' --quick-generate-key \
  'OpenCHAMI Retired Repository <retired-repo@openchami.org>' rsa2048 cert 0
retired_repo_fingerprint=$(fingerprint_for_uid 'retired-repo@openchami.org')
GNUPGHOME="$package_gnupg" gpg --batch --yes --quick-sign-key \
  --local-user "$package_master_fingerprint" "$retired_repo_fingerprint"
GNUPGHOME="$package_gnupg" gpg --batch --passphrase '' --quick-generate-key \
  'OpenCHAMI Rejected Package <rejected-package@openchami.org>' rsa2048 sign 1d
rejected_package_fingerprint=$(fingerprint_for_uid 'rejected-package@openchami.org')
GNUPGHOME="$package_gnupg" gpg --batch --yes --quick-sign-key \
  --local-user "$retired_repo_fingerprint" "$rejected_package_fingerprint"

rejected_keys_dir="$work_dir/rejected-keys/test-package"
mkdir -p "$rejected_keys_dir"
GNUPGHOME="$package_gnupg" gpg --batch --armor \
  --export "${retired_repo_fingerprint}!" > "$rejected_keys_dir/repo-cert.pub.asc"
GNUPGHOME="$package_gnupg" gpg --batch --armor \
  --export "${rejected_package_fingerprint}!" > "$rejected_keys_dir/ephemeral.pub.asc"

rejected_output="$work_dir/rejected-output"
touch "$rejected_output"
if GITHUB_OUTPUT="$rejected_output" \
  RUNNER_TEMP="$work_dir" \
  INPUT_RPM_PATH="$test_rpm" \
  INPUT_REPOSITORY_PATH='stable/el9/x86_64' \
  INPUT_PACKAGE_SIGNING_KEYS_PATH="$work_dir/rejected-keys" \
  INPUT_PACKAGE_MASTER_PUBLIC_KEY_ASC="$package_master_public_key" \
  INPUT_PACKAGE_MASTER_FINGERPRINT="$package_master_fingerprint" \
  INPUT_AUTHORIZED_PACKAGE_REPO_FINGERPRINTS="$package_repo_fingerprint" \
  INPUT_METADATA_SIGNING_KEY_ARMORED_B64="$metadata_key_b64" \
  INPUT_METADATA_SIGNING_KEY_FINGERPRINT="$metadata_fingerprint" \
  INPUT_METADATA_SIGNING_KEY_PASSPHRASE='metadata-test-passphrase' \
  INPUT_REQUIRE_SIGNED_RPMS='true' \
  INPUT_DRY_RUN='true' \
    ./actions/publish-rpm-repository/publish.sh; then
  echo 'retired package repository key was unexpectedly accepted' >&2
  exit 1
fi

echo 'RPM repository publisher dry-run passed'
