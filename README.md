<!--
SPDX-FileCopyrightText: 2025 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# GitHub Actions Monorepo for `OpenCHAMI`

Reusable GitHub Actions for CI/CD.

## Structure

- `actions/gpg-ephemeral-key`: **Deprecated** - use `actions/gpg-configure-release-keys` instead
- `actions/gpg-configure-release-keys`: Generates and certifies a per-run ephemeral GPG key through the repo's release key chain
- `actions/gpg-sign-rpm`: RPM signing with ephemeral keys
- `actions/gpg-check-key-expiration`: Fails CI if a signing key is expired or expiring soon
- `actions/gpg-verify-trust-chain`: Verifies the master/repo-cert/ephemeral trust chain and optionally checksigs RPMs
- `actions/publish-rpm-repository`: Generates durable-key-signed repository metadata and safely publishes RPM repositories to S3
- `.github/workflows/go-build-release.yml`: Reusable workflow for GoReleaser builds
- `.github/workflows/docker-build-release.yml`: Reusable workflow for multi-arch container image builds
- `.github/workflows/build-publish-container-goreleaser.yml`: Builds and publishes a container image via GoReleaser
- `.github/workflows/build-rpm-quadlet.yml`: Builds a caller repo's podman quadlet RPM
- `.github/workflows/gpg-sign-artifacts.yml`: Signs unsigned RPM artifacts with a per-run ephemeral key
- `.github/workflows/validate-rpm-quadlet.yml`: Validates a signed quadlet RPM's installed file list
- `.github/workflows/release-signed-artifacts.yml`: Publishes a GitHub Release with signed RPMs and public keys
- `.github/workflows/publish-rpm-repository.yml`: Publishes aggregated RPMs through S3 and CloudFront using GitHub OIDC
- `.github/workflows/lint-workflows.yml`: Reusable workflow that lints workflow files (actionlint + zizmor)
- `.github/workflows/govulncheck.yml`: Reusable workflow that scans Go modules for known CVEs
- `.github/workflows/dependency-review.yml`: Reusable workflow that gates PRs introducing CVE-flagged deps
- `.github/workflows/trivy-image-scan.yml`: Reusable workflow that scans built container images for CVEs

## Versioning & Usage

Use major version tags for stability:

```yaml
# For actions
- uses: OpenCHAMI/github-actions/actions/gpg-configure-release-keys@v1
- uses: OpenCHAMI/github-actions/actions/gpg-sign-rpm@v1

# For reusable workflows
jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/go-build-release.yml@v3.3
```

Pin a commit SHA internally for maximum supply-chain safety if desired.

## Workflows

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

- **actionlint** - syntax validation, shellcheck on `run:` steps, deprecated-action checks.
- **zizmor** - security-focused static analysis (script injection, excessive permissions, unpinned third-party actions). Uploads SARIF findings to the caller's GitHub Advanced Security tab.

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

### build-publish-container-goreleaser (Reusable Workflow)
Builds and publishes a container image via GoReleaser, with multi-arch builds, build provenance attestation, and PR snapshot support.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-publish-container-goreleaser.yml@v3.5
    with:
      registry_subject_name: ghcr.io/openchami/foo
```

### build-rpm-quadlet (Reusable Workflow)
Builds the caller repo's podman quadlet RPM and uploads it as an unsigned artifact for downstream signing.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-rpm-quadlet.yml@v3.5
```

### gpg-sign-artifacts (Reusable Workflow)
Signs unsigned RPM artifacts with a per-run ephemeral key certified through the repo's release key chain, verifies the chain, and uploads the signed RPMs and public keys. Intended as the common entry point for signing all release artifact types (RPMs today; other formats later).

**Usage:**
```yaml
jobs:
  sign:
    uses: OpenCHAMI/github-actions/.github/workflows/gpg-sign-artifacts.yml@v3.5
    secrets: inherit
```

### validate-rpm-quadlet (Reusable Workflow)
Validates a signed quadlet RPM's installed file list against the set of files the caller expects it to ship.

**Usage:**
```yaml
jobs:
  validate:
    uses: OpenCHAMI/github-actions/.github/workflows/validate-rpm-quadlet.yml@v3.5
    with:
      rpms: |
        - name: foo-*.rpm
          files:
            - /etc/containers/systemd/foo.container
```

### release-signed-artifacts (Reusable Workflow)
Publishes a GitHub Release for a tag, attaching signed RPMs and public keys, with trust-chain verification instructions in the release body.

**Usage:**
```yaml
jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/release-signed-artifacts.yml@v3.5
```

### publish-rpm-repository (Reusable Workflow)

Aggregates signed RPM artifacts into a DNF/YUM repository, signs `repomd.xml`
with a durable repository metadata key, publishes to S3 using GitHub OIDC, and
invalidates only mutable CloudFront metadata paths. The calling repository's
`rpm-publish` GitHub Environment supplies the durable signing-key secrets and
can enforce required reviewers.

```yaml
jobs:
  publish:
    uses: OpenCHAMI/github-actions/.github/workflows/publish-rpm-repository.yml@v3.6
    with:
      repository-path: stable/el9/x86_64
      s3-bucket: ${{ vars.RPM_REPOSITORY_BUCKET }}
      aws-region: us-east-1
      aws-role-arn: ${{ vars.RPM_REPOSITORY_PUBLISHER_ROLE_ARN }}
      aws-account-id: ${{ vars.AWS_ACCOUNT_ID }}
      cloudfront-distribution-id: ${{ vars.RPM_REPOSITORY_DISTRIBUTION_ID }}
      public-base-url: https://rpm.openchami.org
      package-master-fingerprint: ${{ vars.MASTER_FPR }}
      metadata-signing-key-fingerprint: ${{ vars.RPM_REPOSITORY_SIGNING_KEY_FINGERPRINT }}
```

The service repositories continue signing RPM packages with certified ephemeral
keys. Publication verifies those chains and emits a rotating DNF package-key
bundle. Only repository metadata uses the durable key. See the
[action documentation](actions/publish-rpm-repository/README.md) for publication
ordering, key handling, and client trust requirements.

## Actions

### gpg-ephemeral-key (Deprecated - use gpg-configure-release-keys)
Generates a short-lived RSA key and signs it with a repo-scoped subkey. See the [action README](actions/gpg-ephemeral-key/README.md).

### gpg-configure-release-keys
Generates a per-run ephemeral GPG key, certified through the repo's release key chain (master certifies a repo cert key, which certifies the ephemeral key). See the [action README](actions/gpg-configure-release-keys/README.md).

### gpg-sign-rpm
Signs an RPM using a provided GPG fingerprint (works with the ephemeral key output from `gpg-configure-release-keys`) and exposes signature verification output. See the [action README](actions/gpg-sign-rpm/README.md).

### gpg-check-key-expiration
Fails CI if the provided signing key is expired or expiring within a threshold. See the [action README](actions/gpg-check-key-expiration/README.md).

### gpg-verify-trust-chain
Verifies the master/repo-cert/ephemeral trust chain and optionally checksigs RPMs. See the [action README](actions/gpg-verify-trust-chain/README.md).

### publish-rpm-repository

Builds repository metadata from signed RPMs, signs `repomd.xml` with the durable
repository metadata key, and publishes immutable packages before the metadata
commit point. See the [action README](actions/publish-rpm-repository/README.md).

## Security Model

Trust chain: `Ephemeral Key <- Repo Cert Key <- Offline Master Key`.

Design principles:
- Ephemeral keys reduce exposure window.
- Repo cert keys are easily revocable & rotated.
- Isolated `GNUPGHOME` avoids polluting runner defaults.
- GNUPGHOME cleanup is the calling workflow's responsibility, not optional.

Key expiration limits future signing only; existing signatures remain valid if the trust chain remains intact.

## Example Workflow (Combined)

Adapted from metadata-service's PR build workflow, chaining container build, RPM build, signing, and validation:

```yaml
name: Build each PR for testing and validation
on:
    pull_request:
        branches:
            - main
        types: [opened, synchronize, reopened, edited]
    workflow_dispatch:
      inputs:
        pr_number:
          description: 'PR Number to build (optional, for manual PR builds)'
          required: false
          type: string

permissions: write-all # Necessary for the generate-build-provenance action with containers
jobs:

  config:
    runs-on: ubuntu-latest
    outputs:
      rpm-unsigned: ${{ steps.names.outputs.rpm-unsigned }}
      rpm-signed:   ${{ steps.names.outputs.rpm-signed }}
      keys-public:  ${{ steps.names.outputs.keys-public }}
    steps:
      - id: names
        run: |
          {
            echo "rpm-unsigned=rpms-unsigned"
            echo "rpm-signed=rpms-signed"
            echo "keys-public=public-keys"
          } >> "$GITHUB_OUTPUT"

  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-publish-container-goreleaser.yml@v3.5
    secrets: inherit
    with:
      cgo_enabled: 0
      registry_subject_name: ghcr.io/openchami/metadata-service
      is_pr_build: true
      pr_number: ${{ inputs.pr_number || github.event.pull_request.number || 0 }}

  rpmbuild:
    needs: [config, build]
    uses: OpenCHAMI/github-actions/.github/workflows/build-rpm-quadlet.yml@v3.5
    secrets: inherit
    with:
      artifact-name-unsigned-rpms: ${{ needs.config.outputs.rpm-unsigned }}

  rpmsign:
    needs: [config, rpmbuild]
    uses: OpenCHAMI/github-actions/.github/workflows/gpg-sign-artifacts.yml@v3.5
    secrets: inherit
    with:
      artifact-name-unsigned-rpms: ${{ needs.config.outputs.rpm-unsigned }}
      artifact-name-signed-rpms:   ${{ needs.config.outputs.rpm-signed }}
      artifact-name-public-keys:   ${{ needs.config.outputs.keys-public }}

  rpmvalidate:
    needs: [config, rpmsign]
    uses: OpenCHAMI/github-actions/.github/workflows/validate-rpm-quadlet.yml@v3.5
    secrets: inherit
    with:
      artifact-name-signed-rpms:   ${{ needs.config.outputs.rpm-signed }}
      rpms: |
        - name: metadata-service-*.rpm
          files:
            - /usr/share/containers/systemd/metadata-data.volume
            - /usr/share/containers/systemd/metadata-service.container
            - /usr/share/licenses/metadata-service
            - /usr/share/licenses/metadata-service/MIT.txt
```

## Continuous Integration

- Workflow files are linted via `lint-workflows.yml` (actionlint + zizmor).
- RPM/quadlet output is validated via `validate-rpm-quadlet.yml`.
- TODO: matrix test invoking each action directly.

## Rotation & Revocation

Repo cert key and master key rotation/revocation procedures live in
[gpg-signing-manager](https://github.com/OpenCHAMI/gpg-signing-manager). Tag
a new release here if this repo's actions or workflows change as a result.

## Contributing

- Open issues for feature requests.
- Submit PRs with accompanying test workflow updates.

## License

MIT
