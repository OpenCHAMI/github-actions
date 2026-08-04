<!--
SPDX-FileCopyrightText: 2025 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# RPM Signing Action

Signs an RPM file using a GPG key fingerprint (typically an ephemeral key produced by the `gpg-configure-release-keys` action). Designed to pair with ephemeral, short-lived keys to reduce long-term key exposure in CI.

## How It Works

1. Assumes the GPG key (secret) is already present in the GNUPGHOME (e.g. from `gpg-configure-release-keys`).
2. Configures RPM macros to use GPG (sets `%_signature`, `%_gpg_name`, `%__gpg`, and SHA-256 digest).
3. Signs the RPM with `rpmsign --addsign` (or re-signs if `resign: true`).
4. Verifies the signature and exposes the verification output.

Notes:
- The action supports Ubuntu and Fedora runners (installs via `apt-get` or `dnf`).
- This action imports the signer's public key into rpmdb immediately before its own verify step, so its `verification` output won't normally show `NOKEY`. Downstream consumers who checksig the RPM without importing that public key first will see `NOKEY` there; the signature is still valid, they just haven't imported the key locally.

## Inputs

| Name | Required | Description |
|------|----------|-------------|
| `gpg-fingerprint` | Yes | Fingerprint of the (secret) GPG key to use |
| `gnupg-home` | No | GNUPGHOME directory produced by previous step (optional) |
| `resign` | No | If `true`, remove existing signature before adding new one (default: `false`) |

## Outputs

| Name | Description |
|------|-------------|
| `verification` | Raw output of `rpm --checksig` after signing |

## Example Usage

See [`gpg-sign-artifacts.yml`](../../.github/workflows/gpg-sign-artifacts.yml) in this repo for a real usage example.

## Security Notes

- Prefer ephemeral keys: generate -> sign -> cleanup (see Key Lifecycle below; cleanup is the calling workflow's responsibility, not optional).
- Provide `gnupg-home` explicitly to avoid leaking into default `~/.gnupg`.
- Set `resign: true` only if you intentionally need to replace a signature.

## Key Lifecycle

Combine with `gpg-configure-release-keys`. That action leaves the ephemeral secret key in `GNUPGHOME` for this step to use and does not clean it up itself. The calling workflow is responsible for shredding `GNUPGHOME` once signing is done.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `no RPMs found under $(pwd)` | No `*.rpm` files under the working directory | Check the build step produced RPMs before this action runs |
| `NOKEY` when a consumer checksigs the RPM elsewhere | They haven't imported the signer's public key into their own rpmdb | Import the exported public key into rpmdb before checking |
| `BAD` in verification output | Signature mismatch or corruption | Rebuild and re-sign; ensure correct key |
| Already signed message | Existing signature and `resign` not set | Set `resign: true` |

## License
MIT
