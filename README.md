<!--
SPDX-FileCopyrightText: 2025 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# GitHub Actions Monorepo for `OpenCHAMI`

Reusable GitHub Actions for CI/CD.

## Structure

- `actions/gpg-ephemeral-key`: Ephemeral key generation for RPM/GPG signing
- `actions/sign-rpm`: RPM signing with ephemeral keys
- `.github/workflows/go-build-release.yml`: Reusable workflow for GoReleaser builds
- `.github/workflows/docker-build-release.yml`: Reusable workflow for multi-arch container image builds
- `.github/workflows/lint-workflows.yml`: Reusable workflow that lints workflow files (actionlint + zizmor)
- `.github/workflows/govulncheck.yml`: Reusable workflow that scans Go modules for known CVEs
- `.github/workflows/dependency-review.yml`: Reusable workflow that gates PRs introducing CVE-flagged deps
- `.github/workflows/trivy-image-scan.yml`: Reusable workflow that scans built container images for CVEs

## Versioning & Usage

Use major version tags for stability:

```yaml
# For actions
- uses: OpenCHAMI/github-actions/actions/gpg-ephemeral-key@v1
- uses: OpenCHAMI/github-actions/actions/sign-rpm@v1

# For reusable workflows
jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/go-build-release.yml@v3.3
```

Pin a commit SHA internally for maximum supply‑chain safety if desired.

## Actions and Workflows Overview

### go-build-release (Reusable Workflow)
Standardized GoReleaser workflow for building and releasing Go applications with:
- Multi-architecture builds (linux/amd64, linux/arm64)
- Flexible pre-build setup steps
- Wraps `goreleaser-action` action with all .gorelease.yaml configurations
- Container image builds and publishing
- Binary and container attestation/signing
- Snapshot builds on pull requests

**Usage:**
```yaml
name: GoReleaser
run-name: GoReleaser ${{ startsWith(github.ref, 'refs/tags/v') && 'Release' || 'Snapshot' }}

on:
  workflow_dispatch:
  pull_request:
  push:
    tags:
      - v*

jobs:
  goreleaser:
    name: GoReleaser ${{ startsWith(github.ref, 'refs/tags/v') && 'Release' || 'Snapshot' }}
    uses: OpenCHAMI/github-actions/.github/workflows/go-build-release.yml@v3.3
    with:
      pre-build-commands: |
        go install github.com/swaggo/swag/cmd/swag@latest
      attestation-binary-path: "dist/cloud-init*"
      registry-name: ghcr.io/openchami/cloud-init

```

See the [workflow](.github/workflows/go-build-release.yml) for additional input parameters.

### lint-workflows (Reusable Workflow)
Lints the caller repo's GitHub Actions workflow files.

- **actionlint** — syntax validation, shellcheck on `run:` steps, deprecated-action checks.
- **zizmor** — security-focused static analysis (script injection, excessive permissions, unpinned third-party actions). Uploads SARIF findings to the caller's GitHub Advanced Security tab.

**Usage:**
```yaml
name: Lint Workflows
on:
  pull_request:
  push:
    branches: [main]

jobs:
  lint:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-workflows.yml@v3.4
```

### govulncheck (Reusable Workflow)
Runs the Go team's vulnerability scanner against the caller's module. Detects known CVEs in the import graph (direct and transitive). Reads the Go version from the caller's `go.mod` by default.

**Usage:**
```yaml
name: govulncheck
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'  # weekly catch-up for newly-disclosed CVEs

jobs:
  govulncheck:
    uses: OpenCHAMI/github-actions/.github/workflows/govulncheck.yml@v3.4
```

### dependency-review (Reusable Workflow)
PR gate that compares the dependency changes between the PR head and base against GitHub's vulnerability database. Fails the check when the PR introduces a dependency at or above `fail-on-severity` (default: `high`). Optionally enforces license policy and posts a summary comment on the PR.

**Usage:**
```yaml
name: Dependency Review
on:
  pull_request:

jobs:
  dependency-review:
    uses: OpenCHAMI/github-actions/.github/workflows/dependency-review.yml@v3.4
    # Optional overrides:
    # with:
    #   fail-on-severity: moderate
    #   deny-licenses: GPL-3.0,AGPL-3.0
```

### trivy-image-scan (Reusable Workflow)
Scans an already-pushed container image with Trivy and uploads SARIF findings to GitHub Advanced Security. Designed to chain after `docker-build-release` with a digest-pinned image reference.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/docker-build-release.yml@v3.4
    with:
      registry-name: ghcr.io/openchami/foo

  scan:
    needs: build
    uses: OpenCHAMI/github-actions/.github/workflows/trivy-image-scan.yml@v3.4
    with:
      image-ref: ghcr.io/openchami/foo:${{ github.sha }}
```

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
