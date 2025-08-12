# 📦 RPM Signing Action

Signs an RPM file using a GPG key fingerprint (typically an ephemeral key produced by the `gpg-ephemeral-key` action). Designed to pair with ephemeral, short‑lived keys to reduce long‑term key exposure in CI.

## 🔧 How It Works

1. Assumes the GPG key (secret) is already present in the GNUPGHOME (e.g. from `gpg-ephemeral-key`).
2. Configures RPM macros to use GPG (sets `%_signature`, `%_gpg_name`, `%__gpg`, and SHA‑256 digest).
3. Signs the RPM with `rpmsign --addsign` (or re‑signs if `resign: true`).
4. Verifies the signature and exposes the verification output.

Notes:
- The action supports Ubuntu and Fedora runners (installs via `apt-get` or `dnf`).
- Verification may show `NOKEY` if the rpm database doesn’t have the public key; the signature is still valid, but rpm cannot confirm it without the public key imported.

## 📥 Inputs

| Name | Required | Description |
|------|----------|-------------|
| `rpm-path` | ✅ | Path to the RPM file to sign |
| `gpg-fingerprint` | ✅ | Fingerprint of the (secret) GPG key to use |
| `gnupg-home` | ❌ | GNUPGHOME directory produced by previous step (optional) |
| `resign` | ❌ | If `true`, remove existing signature before adding new one (default: `false`) |

## 📤 Outputs

| Name | Description |
|------|-------------|
| `verification` | Raw output of `rpm --checksig` after signing |

## 🚀 Example Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate ephemeral key
        id: gpg
        uses: OpenCHAMI/github-actions/actions/gpg-ephemeral-key@v1
        with:
          subkey-armored: ${{ secrets.GPG_SUBKEY_B64 }}
          comment: build:${{ github.run_id }}

      - name: Build RPM
        run: ./scripts/build-rpm.sh

      - name: Sign RPM
        id: sign
        uses: OpenCHAMI/github-actions/actions/sign-rpm@v1
        with:
          rpm-path: dist/my.rpm
          gpg-fingerprint: ${{ steps.gpg.outputs.ephemeral-fingerprint }}
          gnupg-home: ${{ steps.gpg.outputs.gnupg-home }}

      - name: Show verification
        run: echo "${{ steps.sign.outputs.verification }}"
```

Optional: Import the public key into rpmdb to avoid `NOKEY` in verification output:

```yaml
      - name: Import public key for rpm verification
        run: |
          GNUPGHOME="${{ steps.gpg.outputs.gnupg-home }}"; export GNUPGHOME
          gpg --armor --export "${{ steps.gpg.outputs.ephemeral-fingerprint }}" > signer.pub
          sudo rpm --import signer.pub
          rm -f signer.pub
```

## 🔐 Security Notes

- Prefer ephemeral keys: generate -> sign -> (optionally) cleanup.
- Provide `gnupg-home` explicitly to avoid leaking into default `~/.gnupg`.
- Set `resign: true` only if you intentionally need to replace a signature.

## ♻️ Key Lifecycle

Combine with the ephemeral key action and set `cleanup: true` unless later steps need the secret key.

## 🛠 Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No such file or directory` | Wrong `rpm-path` | Check artifact path and build step |
| `NOKEY` in verification output | rpmdb missing public key | Import the exported public key into rpmdb |
| `BAD` in verification output | Signature mismatch or corruption | Rebuild and re‑sign; ensure correct key |
| Already signed message | Existing signature and `resign` not set | Set `resign: true` |

## 📝 License
MIT
