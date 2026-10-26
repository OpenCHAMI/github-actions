<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# gpg-verify-trust-chain

Verifies OpenCHAMI's release trust chain and the files it signs (key names as in
[Signing releases](../../docs/signing.md#the-keys)):

1. The root public key matches `fingerprint-master`.
2. The root key certified the repo key (`pubkey-repo.asc`), on the user ID
   `<owner>/<repo> RPM Signing Key` when `repo` is set.
3. The repo key certified the release key (`pubkey-signing.asc`).
4. Each file in `files` has a good signature at `<file>.asc` from the release
   key.

No key may be revoked or expired, so a signature whose 1-day release key has
expired fails. Each key file must hold exactly one key. Every failure is
reported before the step fails. Format-agnostic: it verifies files such as
`checksums.txt`, not packages. Pass the root public key from a trusted
source (the `MASTER_PUBLIC_ASC` org secret), never the `pubkey-org.asc`
attached to a release.

Used by `gpg-sign-artifacts` to check its own output, and by anything that
admits signed releases.

```yaml
- uses: OpenCHAMI/github-actions/actions/gpg-verify-trust-chain@<sha>
  with:
    public-key-master: ${{ secrets.MASTER_PUBLIC_ASC }}
    fingerprint-master: ${{ secrets.MASTER_FPR }}
    repo: OpenCHAMI/foo
    # public-key-file-repo: pubkey-repo.asc
    # public-key-file-signing: pubkey-signing.asc
    # files: checksums.txt
```

Outputs `fingerprint-master`, `fingerprint-repo`, and `fingerprint-signing`.

The checks live in [`scripts/gpg-verify-trust-chain.sh`](../../scripts/gpg-verify-trust-chain.sh),
so they can also run outside this action (e.g. fetched by commit SHA). It takes
the inputs as environment variables and needs `gpg`; see its header.
