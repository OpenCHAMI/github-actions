# GitHub Actions Monorepo for `OpenCHAMI`

Reusable GitHub Actions for CI/CD.

## Structure

- `actions/gpg-ephemeral-key`: Ephemeral key generation for RPM/GPG signing
- `actions/sign-rpm`: RPM signing with ephemeral keys

## Versioning & Usage

Use major version tags for stability:

```yaml
- uses: OpenCHAMI/github-actions/actions/gpg-ephemeral-key@v1
- uses: OpenCHAMI/github-actions/actions/sign-rpm@v1
```

Pin a commit SHA internally for maximum supply‑chain safety if desired.

## Actions Overview

### gpg-ephemeral-key
Generates a short‑lived RSA key (default 3072‑bit, 1 day) using an isolated `GNUPGHOME`, signs it with a repo‑scoped subkey you provide, and outputs:
- `ephemeral-fingerprint`
- `ephemeral-public-key` (base64 of armored)
- `gnupg-home` (path for downstream steps)

### sign-rpm
Signs an RPM using a provided GPG fingerprint (works with the ephemeral key output) and exposes signature verification output.

## Security Model

Trust chain: `Ephemeral Key ← Repo Subkey ← Offline Master Key`.

Design principles:
- Ephemeral keys reduce exposure window.
- Repo subkeys are easily revocable & rotated.
- Isolated `GNUPGHOME` avoids polluting runner defaults.
- Optional cleanup to remove secrets post‑sign.

Key expiration limits future signing only; existing signatures remain valid if the trust chain remains intact.

## Example Workflow (Combined)

```yaml
jobs:
  build-and-sign:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Generate ephemeral key
        id: gpg
        uses: OpenCHAMI/github-actions/actions/gpg-ephemeral-key@v1
        with:
          subkey-armored: ${{ secrets.GPG_SUBKEY_B64 }}
          comment: build:${{ github.run_id }}
          cleanup: false # keep for subsequent signing
      - name: Build RPM
        run: ./scripts/build-rpm.sh
      - name: Sign RPM
        id: sign
        uses: OpenCHAMI/github-actions/actions/sign-rpm@v1
        with:
          rpm-path: dist/my.rpm
          gpg-fingerprint: ${{ steps.gpg.outputs.ephemeral-fingerprint }}
          gnupg-home: ${{ steps.gpg.outputs.gnupg-home }}
      - name: (Optional) Cleanup GNUPGHOME
        if: always()
        run: rm -rf "${{ steps.gpg.outputs.gnupg-home }}"
```

## Continuous Integration

A future CI workflow will:
- Lint action metadata (actionlint)
- Perform a matrix test invoking each action
- Validate RPM signing round‑trip

## Rotation & Revocation

1. Revoke and replace repo subkeys periodically.
2. Update `GPG_SUBKEY_B64` secret.
3. Tag a new release if behavior changes.

## Contributing

- Open issues for feature requests.
- Submit PRs with accompanying test workflow updates.

## License

MIT
