<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# gpg-verify-trust-chain

Verifies OpenCHAMI's release trust chain and the files it signs:

1. The master public key matches `master-fingerprint`.
2. The master certified the repo-cert key (`pubkey-repo.asc`), on the user ID
   `<owner>/<repo> RPM Signing Key` when `repo` is set.
3. The repo-cert key certified the per-run signing key (`pubkey-signing.asc`).
4. Each file in `files` has a good signature at `<file>.asc` from the signing
   key.

No key may be revoked or expired, so a signature whose 1-day signing key has
expired fails. Each key file must hold exactly one key. Every failure is
reported before the step fails. Format-agnostic: it verifies files such as
`checksums.txt`, not packages. Pass the master public key from a trusted
source (the `MASTER_PUBLIC_ASC` org secret), never the `pubkey-org.asc`
attached to a release.

Used by `gpg-sign-artifacts` to check its own output, and by anything that
admits signed releases.

```yaml
- uses: OpenCHAMI/github-actions/actions/gpg-verify-trust-chain@<sha>
  with:
    master-public-key: ${{ secrets.MASTER_PUBLIC_ASC }}
    master-fingerprint: ${{ secrets.MASTER_FPR }}
    repo: OpenCHAMI/foo
    # repo-public-key-file: pubkey-repo.asc
    # signing-public-key-file: pubkey-signing.asc
    # files: checksums.txt
```

Outputs `master-fingerprint`, `repo-fingerprint`, and `signing-fingerprint`.
