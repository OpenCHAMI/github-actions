#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Verifies the release trust chain (offline org master certifies the repo-cert
# key, which certifies the per-run signing key) and each file's detached
# signature by the signing key. Used by the gpg-verify-trust-chain action, and
# runnable on its own (e.g. fetched by commit SHA) wherever gpg is installed.
#
# Environment:
#   MASTER_PUBLIC_KEY   ASCII-armored org master public key (required); never
#                       the copy attached to a release
#   MASTER_FINGERPRINT  full fingerprint of the org master key (required)
#   REPO_KEY_FILE       repo-cert public key (default, when unset: pubkey-repo.asc)
#   SIGNING_KEY_FILE    per-run signing public key (default, when unset:
#                       pubkey-signing.asc)
#   FILES               space- or newline-separated files to verify, each with
#                       a detached signature at <file>.asc (default, when
#                       unset: checksums.txt)
#   REPO                expected owner/repo; when set, the master must have
#                       certified the user ID "<owner>/<repo> RPM Signing Key"
#   OUTPUT_FILE         where to append fingerprint-{master,repo,signing}=<fpr>
#                       on success (default stdout)
#
# Exits non-zero if any check fails, after reporting every failure.

set -euo pipefail

: "${MASTER_PUBLIC_KEY:?MASTER_PUBLIC_KEY is required}"
: "${MASTER_FINGERPRINT:?MASTER_FINGERPRINT is required}"
REPO_KEY_FILE=${REPO_KEY_FILE-pubkey-repo.asc}
SIGNING_KEY_FILE=${SIGNING_KEY_FILE-pubkey-signing.asc}
FILES=${FILES-checksums.txt}
REPO=${REPO:-}
OUTPUT_FILE=${OUTPUT_FILE:-/dev/stdout}

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
chmod 700 "$GNUPGHOME"
trap 'rm -rf "$GNUPGHOME"' EXIT

# Every check runs and reports; the script fails at the end.
failed=false
fail() { echo "::error::$*"; failed=true; }

# Fingerprint of the single primary key in an armored file; fails if
# the file holds zero or several keys (no smuggled extra keys).
key_fpr() {
  gpg --batch --with-colons --import-options show-only --import "$1" 2>/dev/null \
    | awk -F: '$1=="pub" {n++} n==1 && $1=="fpr" && !f {f=$10} END {if (n==1) print f; else exit 1}'
}

# 0 when SIGNER made a verified certification on SUBJECT, on a user ID
# named PREFIX (any user ID when PREFIX is empty).
certified_by() {
  local signer_id="${1: -16}" subject="$2" prefix="$3"
  gpg --batch --with-colons --check-sigs "$subject" 2>/dev/null \
    | awk -F: -v id="${signer_id^^}" -v prefix="${prefix,,}" '
        $1=="uid" { name=tolower($10); ok=(prefix=="" || name==prefix || index(name, prefix " ")==1) }
        $1=="sig" && $2=="!" && ok && toupper($5)==id { found=1 }
        END { exit !found }'
}

# On a failed certification check, print what the subject key does
# carry: its user IDs and who certified each (all public data).
show_certs() {
  echo "Expected certifier key ID: ${1: -16}"
  echo "User IDs and certifications on ${2} (! good, ? certifier not the expected key, - bad):"
  gpg --batch --with-colons --check-sigs "$2" 2>/dev/null \
    | awk -F: '$1=="uid" {print "  uid: " $10} $1=="sig" {print "    sig " $2 " by " $5}'
}

# 0 when the key is neither revoked nor expired.
usable() {
  gpg --batch --with-colons --list-keys "$1" 2>/dev/null \
    | awk -F: '$1=="pub" { exit ($2=="r" || $2=="e") }'
}

master_key="$GNUPGHOME/master.asc"
printf '%s\n' "$MASTER_PUBLIC_KEY" > "$master_key"
for f in "$REPO_KEY_FILE" "$SIGNING_KEY_FILE"; do
  [[ -f "$f" ]] || { echo "::error::Key file not found: $f"; exit 1; }
done

master_fpr=$(key_fpr "$master_key") || { echo "::error::MASTER_PUBLIC_KEY must hold exactly one public key"; exit 1; }
repo_fpr=$(key_fpr "$REPO_KEY_FILE") || { echo "::error::${REPO_KEY_FILE} must hold exactly one public key"; exit 1; }
signing_fpr=$(key_fpr "$SIGNING_KEY_FILE") || { echo "::error::${SIGNING_KEY_FILE} must hold exactly one public key"; exit 1; }
echo "Master:  ${master_fpr}"
echo "Repo:    ${repo_fpr}"
echo "Signing: ${signing_fpr}"

expected=$(tr -d '[:space:]' <<< "$MASTER_FINGERPRINT")
[[ "${expected^^}" == "${master_fpr^^}" ]] || fail "Master public key ${master_fpr} doesn't match MASTER_FINGERPRINT."

for f in "$master_key" "$REPO_KEY_FILE" "$SIGNING_KEY_FILE"; do
  gpg --batch --quiet --import "$f" 2>/dev/null
done

usable "$master_fpr" || fail "Master key ${master_fpr} is revoked or expired."
usable "$repo_fpr" || fail "Repo-cert key ${repo_fpr} is revoked or expired."
usable "$signing_fpr" || fail "Signing key ${signing_fpr} is revoked or expired."

identity=''
[[ -n "$REPO" ]] && identity="${REPO} RPM Signing Key"
if ! certified_by "$master_fpr" "$repo_fpr" "$identity"; then
  fail "Master ${master_fpr} hasn't certified repo-cert key ${repo_fpr}${identity:+ as '${identity}'}."
  show_certs "$master_fpr" "$repo_fpr"
fi
if ! certified_by "$repo_fpr" "$signing_fpr" ''; then
  fail "Repo-cert key ${repo_fpr} hasn't certified signing key ${signing_fpr}."
  show_certs "$repo_fpr" "$signing_fpr"
fi

# shellcheck disable=SC2086 # intentional word splitting
set -- $FILES
[[ $# -gt 0 ]] || fail "No files to verify."
for f in "$@"; do
  if [[ ! -f "$f" || ! -f "$f.asc" ]]; then
    fail "Missing ${f} or its signature ${f}.asc."
    continue
  fi
  # GOODSIG excludes expired (EXPKEYSIG) and revoked (REVKEYSIG) keys;
  # VALIDSIG's last field is the signer's primary key fingerprint.
  status=$(gpg --batch --status-fd 1 --verify "$f.asc" "$f" 2>/dev/null || true)
  signer=$(awk '$2=="VALIDSIG" {print $NF}' <<< "$status")
  if grep -q '^\[GNUPG:\] GOODSIG ' <<< "$status" && [[ "${signer^^}" == "${signing_fpr^^}" ]]; then
    echo "Verified ${f}"
  else
    fail "Signature ${f}.asc doesn't verify against signing key ${signing_fpr}."
  fi
done

[[ "$failed" == false ]] || exit 1
{
  echo "fingerprint-master=${master_fpr}"
  echo "fingerprint-repo=${repo_fpr}"
  echo "fingerprint-signing=${signing_fpr}"
} >> "$OUTPUT_FILE"
echo "Trust chain and signatures verified."
