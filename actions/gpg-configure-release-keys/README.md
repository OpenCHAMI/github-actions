<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# gpg-configure-release-keys

Creates a per-run ephemeral GPG key and certifies it with a repo-scoped
certification key, for use by downstream signing steps.

## Key Lifecycle

- **Master key**: public-only here — only `master-public-key-asc`/`master-fpr`
  are consumed, to pass through for trust-chain export. Never imported as a
  secret in this action.
- **Repo cert key**: imported from `repo-cert-key-armored-b64` (secret), used
  only to certify the ephemeral key, then deleted with
  `--delete-secret-keys` before this action returns.
- **Ephemeral key**: intentionally left in the exported `GNUPGHOME` — the
  caller's next step (e.g. `gpg-sign-rpm`) needs the secret key. The calling
  workflow, not this action, is responsible for shredding that `GNUPGHOME`
  once signing is done.

See [gpg-signing-manager](https://github.com/OpenCHAMI/gpg-signing-manager)
for key generation/rotation details.

## Secrets vs. variables

`MASTER_PUBLIC_ASC`/`MASTER_FPR` are public (a public key + fingerprint) —
stored as secrets here for consistency with the other key inputs, not
because they need confidentiality. Fine to move to repo/org variables.
