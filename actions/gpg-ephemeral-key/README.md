# 🛡️ GPG Ephemeral Key Generator

This GitHub composite action generates a new ephemeral GPG key on every build, signs it using a repo‑scoped subkey, and exports the fingerprint and public key. It’s designed for use in CI pipelines where artifacts need secure signing without long‑lived keys in GitHub Actions.

---

## 🔧 How It Works

- Generates a short‑lived RSA key (default RSA‑3072, expiration 1 day)
- Signs it with your repo‑specific subkey (stored as `GPG_SUBKEY_B64`)
- Returns:
  - `ephemeral-fingerprint` → use to sign artifacts
  - `ephemeral-public-key` → base64-encoded armored public key
  - `gnupg-home` → isolated GNUPGHOME path for downstream steps

---

## 📦 Inputs

| Name             | Required | Description |
|------------------|----------|-------------|
| `subkey-armored` | ✅       | Base64‑encoded ASCII‑armored GPG subkey (secret) used to sign the ephemeral key |
| `name`           | ❌       | Name for the ephemeral key (default: Ephemeral Key) |
| `comment`        | ❌       | Metadata like build ID, ref, etc. A random suffix is appended |
| `email`          | ❌       | Email for ephemeral key (default: ci@build.local) |
| `key-length`     | ❌       | RSA key length (default: 3072) |
| `expire-days`    | ❌       | Expiration in days (default: 1) |
| `cleanup`        | ❌       | If `true`, remove GNUPGHOME after export (default: false) |

---

## 🔑 Outputs

| Name                    | Description |
|-------------------------|-------------|
| `ephemeral-fingerprint` | Fingerprint of the generated ephemeral key |
| `ephemeral-public-key`  | Base64‑encoded ASCII‑armored public key |
| `gnupg-home`            | Path to isolated GNUPGHOME for subsequent actions |

---

## 🛠️ Setup (Per Repo)

1. Create a GPG subkey tied to this repository, signed by your org's offline master key.
2. Export it (subkey only):
   ```bash
   gpg --export-secret-subkeys --armor > repo-subkey.asc
   base64 < repo-subkey.asc | tr -d '\n' > subkey.b64
   ```
3. Store as a GitHub Secret in your repo:
   `GPG_SUBKEY_B64` = contents of `subkey.b64`

## ✅ Example: Prove Signing Works

```yaml
jobs:
  test-ephemeral-signing:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate ephemeral key
        id: gpg
        uses: OpenCHAMI/github-actions/actions/gpg-ephemeral-key@v1
        with:
          subkey-armored: ${{ secrets.GPG_SUBKEY_B64 }}
          comment: "build:${{ github.run_id }}"
          key-length: '3072'
          expire-days: '1'
          cleanup: false

      - name: Sign and verify a test file
        run: |
          GNUPGHOME="${{ steps.gpg.outputs.gnupg-home }}"; export GNUPGHOME
          echo "hello" > test.txt
          gpg --batch --yes --local-user "${{ steps.gpg.outputs.ephemeral-fingerprint }}" --detach-sign --output test.txt.sig test.txt
          gpg --verify test.txt.sig test.txt

      - name: Show trust chain
        run: |
          GNUPGHOME="${{ steps.gpg.outputs.gnupg-home }}"; export GNUPGHOME
          echo "Ephemeral: ${{ steps.gpg.outputs.ephemeral-fingerprint }}"
          gpg --list-keys --with-colons
          gpg --list-sigs "${{ steps.gpg.outputs.ephemeral-fingerprint }}"

      - name: Cleanup
        if: always()
        run: rm -rf "${{ steps.gpg.outputs.gnupg-home }}"
```

## 🔐 Security Notes

- Ephemeral key is short‑lived; expiration limits future signing, not validation of past signatures.
- Subkey is repo‑scoped, easy to rotate/revoke.
- Use the isolated `GNUPGHOME` to avoid polluting runner defaults; set `cleanup: true` when possible.
- Trust chain: `Ephemeral key ← Repo subkey ← Offline master key`.

## 📝 License

MIT