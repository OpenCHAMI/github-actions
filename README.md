<!--
SPDX-FileCopyrightText: 2025 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# GitHub Actions Monorepo for `OpenCHAMI`

Reusable GitHub Actions for CI/CD.

## Structure

- `actions/gpg-configure-release-keys`: **Deprecated** - use nfpm package signing in `build-release-goreleaser` instead. Generates and certifies a per-run ephemeral GPG key through the repo's release key chain
- `actions/gpg-sign-rpm`: **Deprecated** - use nfpm package signing in `build-release-goreleaser` instead. RPM signing with ephemeral keys
- `actions/gpg-check-key-expiration`: Fails CI if a signing key is expired or expiring soon
- `actions/gpg-verify-trust-chain`: **Deprecated** - use the `rpm -K` check in `validate-packages` instead. Verifies the master/repo-cert/ephemeral trust chain and optionally checksigs RPMs
- `.github/workflows/go-build-release.yml`: **Deprecated** - use `build-release-goreleaser` (build-only: `build-check-goreleaser`) instead. Reusable workflow for GoReleaser builds
- `.github/workflows/docker-build-release.yml`: **Deprecated** - use `build-release-goreleaser` (build-only: `build-check-goreleaser`) instead. Reusable workflow for multi-arch container image builds
- `.github/workflows/build-publish-container-goreleaser.yml`: **Deprecated** - use `build-release-goreleaser` (build-only: `build-check-goreleaser`) instead. Builds and publishes a container image via GoReleaser
- `.github/workflows/build-rpm-quadlet.yml`: **Deprecated** - use nfpm packages built by `build-release-goreleaser` / `build-check-goreleaser` instead. Builds a caller repo's podman quadlet RPM
- `.github/workflows/gpg-sign-artifacts.yml`: **Deprecated** - use nfpm package signing in `build-release-goreleaser` instead. Signs unsigned RPM artifacts with a per-run ephemeral key
- `.github/workflows/validate-rpm-quadlet.yml`: **Deprecated** - use `validate-packages` instead. Validates a signed quadlet RPM's installed file list
- `.github/workflows/release-signed-artifacts.yml`: **Deprecated** - use the release created by `build-release-goreleaser` instead. Publishes a GitHub Release with signed RPMs and public keys
- `.github/workflows/publish-release.yml`: Publishes the draft GitHub Release for a tag
- `.github/workflows/lint-ci.yml`: Reusable workflow that lints workflow files (actionlint + zizmor)
- `.github/workflows/lint-go.yml`: Reusable workflow that runs golangci-lint and checks go.mod/go.sum are tidy
- `.github/workflows/test-unit-go.yml`: Reusable workflow that runs Go unit tests, optionally reporting coverage to Coveralls
- `.github/workflows/reuse.yml`: Reusable workflow that checks REUSE copyright/licensing compliance
- `.github/workflows/govulncheck.yml`: Reusable workflow that scans Go modules for known CVEs
- `.github/workflows/dependency-review.yml`: Reusable workflow that gates PRs introducing CVE-flagged deps
- `.github/workflows/trivy-image-scan.yml`: Reusable workflow that scans built container images for CVEs
- `.github/workflows/scorecard.yml`: Reusable workflow that runs the OpenSSF Scorecard supply-chain analysis
- `.github/workflows/pr-registry-cleanup.yml`: Deletes the GHCR container images a PR published, once it closes
- `.github/workflows/build-check-goreleaser.yml`: Reusable workflow that builds everything in a GoReleaser config (snapshot) without publishing
- `.github/workflows/build-release-goreleaser.yml`: Reusable workflow that publishes `pr-<N>` images for PRs, or a full GoReleaser release for tags
- `.github/workflows/validate-packages.yml`: Reusable workflow that validates rpm/deb packages (file list, signature, install, lint)
- `.github/workflows/stale.yml`: Reusable workflow that marks and closes inactive issues and PRs (org-default policy)
- `.github/workflows/lint-codegen-fabrica.yml`: Reusable workflow that fails when a Fabrica project's committed generated code is out of date

### Workflow naming

`0-local-*` workflows are this repo's own CI, not reusable workflows. The `0`
just sorts them to the top.

## Versioning & Usage

Pin a release tag:

```yaml
# For actions
- uses: OpenCHAMI/github-actions/actions/gpg-check-key-expiration@v4.0

# For reusable workflows
jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/build-release-goreleaser.yml@v4.0
```

Pin a commit SHA instead for maximum supply-chain safety if desired.

## Workflows

### Building and releasing with GoReleaser

`build-check-goreleaser` (build only), `build-release-goreleaser` (PR images or tag release), and `validate-packages` share the caller's `.goreleaser.yaml`. A release chains build-release → validate-packages → `publish-release`, so the draft goes public only after validation.

The build workflows export `IS_PR_BUILD` and `GPG_KEY_PATH` (empty when unsigned) for the config, e.g. `release.disable` on `IS_PR_BUILD` and nfpm `key_file: '{{ .Env.GPG_KEY_PATH }}'`. For nfpm packages, list every directory too (`type: dir`) and use one entry per format (rpm/deb).

### build-check-goreleaser (Reusable Workflow)
Runs `goreleaser release --snapshot --clean`: builds binaries, archives, packages, and images, and publishes nothing. Read-only and secret-free, so it is safe for fork PRs. Uploads the packages, archives, and checksums as an artifact for `validate-packages`.

**Usage:**
```yaml
name: Build Check
on:
  pull_request:

jobs:
  build-check:
    uses: OpenCHAMI/github-actions/.github/workflows/build-check-goreleaser.yml@v4.0
    # Optional overrides:
    # with:
    #   go-version: stable          # mutually exclusive with go-version-file
    #   go-version-file: go.mod
    #   goreleaser-version: v2.18.2
    #   build-deps: gcc-aarch64-linux-gnu libc6-dev-arm64-cross
    #   cgo-enabled: 1
    #   skip: docker                # GoReleaser pipes to skip
    #   dist-artifact-name: goreleaser-dist   # empty skips the upload
```

### build-release-goreleaser (Reusable Workflow)
Runs the caller's GoReleaser config in one of two modes, chosen from the triggering event (no manual override; any other trigger fails):

- **PR** (`pull_request` event): tags HEAD locally as `pr-<PR number>` and pushes the resulting images (e.g. `:pr-12`). No GitHub release, no signing, no attestation, and no packages: nfpm is skipped because a `pr-<N>` version isn't a valid deb version, so validate PR packages with `build-check-goreleaser` (snapshot) instead. Fork PRs build but publish nothing.
- **Release** (`v*` tag push): semver images, packages (signed when the `gpg-key` secret is passed and the nfpm config uses `GPG_KEY_PATH`), a GitHub release (draft by default) with GitHub-generated notes, and build provenance attestations for the release files and the image digest. When signing, the public key is derived from `gpg-key` and attached to the release (and the dist artifact) as `gpg-public-key.asc`.

Outputs `version` and `digest` (the image manifest digest, for `trivy-image-scan`). Uploads the packages, archives, and checksums as an artifact for `validate-packages`.

**Usage:**
```yaml
name: Release
on:
  pull_request:       # pr-<N> images
  push:
    tags: ['v*']      # release

jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/build-release-goreleaser.yml@v4.0
    permissions:
      contents: write
      packages: write
      id-token: write
      attestations: write
    with:
      registry-subject-name: ghcr.io/openchami/foo
    secrets:
      gpg-key: ${{ secrets.GPG_KEY }}
      gpg-key-passphrase: ${{ secrets.GPG_KEY_PASSPHRASE }}
    # Optional overrides:
    # with:
    #   go-version: stable          # mutually exclusive with go-version-file
    #   go-version-file: go.mod
    #   goreleaser-version: v2.18.2
    #   build-deps: gcc-aarch64-linux-gnu libc6-dev-arm64-cross
    #   cgo-enabled: 1
    #   release-draft: false        # default true; publish later with publish-release
    #   generate-release-notes: false
    #   attestation-subject-path: dist/**
    #   goreleaser-args: --timeout 60m
    #   dist-artifact-name: goreleaser-dist
```

### validate-packages (Reusable Workflow)
Validates the rpm/deb packages from either build workflow's artifact, one job per package, in a matching container (`rockylinux:9` for `.rpm`, `debian:13` for `.deb`):

- **File list**: must match `files` exactly. rpm lists include every owned directory; deb lists contain regular files and symlinks only, since dpkg owns parent directories implicitly.
- **Signature**: when the artifact contains `gpg-public-key.asc` (a signed release from `build-release-goreleaser`), rpm signatures must verify (`rpm -K`). Skipped for unsigned builds; deb packages are not signature-checked.
- **Install**: `dnf install` / `apt-get install` of the package, which resolves dependencies and runs scriptlets; every expected path must exist afterward (catches dangling symlinks).
- **Lint**: rpmlint / lintian, report-only.

**Usage:**
```yaml
jobs:
  validate:
    needs: release
    uses: OpenCHAMI/github-actions/.github/workflows/validate-packages.yml@v4.0
    with:
      packages: |
        - name: foo-quadlet*.rpm
          files:
            - /etc/openchami
            - /etc/openchami/configs
            - /etc/openchami/configs/foo.yaml
            - /usr/share/containers/systemd/foo.container
            - /usr/share/licenses/foo-quadlet
            - /usr/share/licenses/foo-quadlet/MIT.txt
        - name: foo-quadlet*.deb
          files:
            - /etc/openchami/configs/foo.yaml
            - /usr/share/containers/systemd/foo.container
            - /usr/share/doc/foo-quadlet/copyright
      # Optional overrides:
      # dist-artifact-name: goreleaser-dist
      # rpm-image: docker.io/library/rockylinux:9
      # deb-image: docker.io/library/debian:13
      # lint: false
```


### go-build-release (Reusable Workflow, Deprecated)

> [!CAUTION]
> **Deprecated.** Use `build-release-goreleaser` (build-only: `build-check-goreleaser`) instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Standardized GoReleaser workflow for building and releasing Go applications with:
- Multi-architecture builds (linux/amd64, linux/arm64)
- Flexible pre-build setup steps
- Wraps `goreleaser-action` action with all .goreleaser.yaml configurations
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
    uses: OpenCHAMI/github-actions/.github/workflows/go-build-release.yml@v4.0
    with:
      pre-build-commands: |
        go install github.com/swaggo/swag/cmd/swag@latest
      attestation-binary-path: "dist/cloud-init*"
      registry-name: ghcr.io/openchami/cloud-init

```

See the [workflow](.github/workflows/go-build-release.yml) for additional input parameters.

### lint-ci (Reusable Workflow)
Lints the caller repo's GitHub Actions workflow files.

- **actionlint** - syntax validation, shellcheck on `run:` steps, deprecated-action checks.
- **zizmor** - security-focused static analysis (script injection, excessive permissions, unpinned third-party actions). Uploads SARIF findings to the caller's GitHub Advanced Security tab.

**Usage:**
```yaml
name: Lint CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  lint:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-ci.yml@v4.0
```

### lint-go (Reusable Workflow)
Lints the caller's Go module. Runs `golangci-lint`, and separately verifies `go.mod`/`go.sum` are tidy by running the tidy command and failing on a dirty diff. Uses Go `stable` unless the caller sets `go-version` or `go-version-file`. `golangci-lint` tracks `latest` unless pinned.

**Usage:**
```yaml
name: Lint
on:
  pull_request:
  push:
    branches: [main]

jobs:
  lint:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-go.yml@v4.0
    # Optional overrides:
    # with:
    #   golangci-lint-version: v2.13.2
    #   go-version-file: go.mod
```

### test-unit-go (Reusable Workflow)
Runs `go test` with `test-args`, one argument per line without shell quotes (default `-race` and `./...`). Fetches tags so tests asserting on `git describe` version metadata behave as they do locally.

With `coverage: true`, it also writes a coverage profile, reports the total in the job summary, and uploads the profile to Coveralls using the automatically-provided `GITHUB_TOKEN`. The caller repo must be enrolled in Coveralls.

**Usage:**
```yaml
name: Test
on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    uses: OpenCHAMI/github-actions/.github/workflows/test-unit-go.yml@v4.0
    # Optional overrides:
    # with:
    #   go-version: stable          # mutually exclusive with go-version-file
    #   go-version-file: go.mod
    #   test-args: |-
    #     -race
    #     -short
    #     ./...
    #   coverage: true
    #   coverage-file: coverage.out
```

### reuse (Reusable Workflow)
Runs the [`reuse`](https://reuse.software) tool over the caller repo via `pipx` to check REUSE compliance: every file carries a copyright notice and an SPDX license identifier, and every referenced license is present under `LICENSES/`. Pins `reuse` 6.2.0.

**Usage:**
```yaml
name: REUSE
on:
  pull_request:
  push:
    branches: [main]

jobs:
  reuse:
    uses: OpenCHAMI/github-actions/.github/workflows/reuse.yml@v4.0
    # Optional overrides:
    # with:
    #   reuse-version: 6.2.0
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
    uses: OpenCHAMI/github-actions/.github/workflows/govulncheck.yml@v4.0
    # Optional overrides:
    # with:
    #   go-version: 1.26.7  # default: read from go.mod
    #   go-package: ./cmd/...
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
    uses: OpenCHAMI/github-actions/.github/workflows/dependency-review.yml@v4.0
    # Optional overrides:
    # with:
    #   fail-on-severity: moderate
    #   deny-licenses: GPL-3.0,AGPL-3.0
    #   allow-licenses: MIT,Apache-2.0
    #   comment-summary-in-pr: always  # always | on-failure | never
```

### trivy-image-scan (Reusable Workflow)
Scans an already-pushed container image with Trivy and uploads SARIF findings to GitHub Advanced Security. Designed to chain after `build-release-goreleaser`, scanning the image by the digest it outputs.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-release-goreleaser.yml@v4.0
    with:
      registry-subject-name: ghcr.io/openchami/foo

  scan:
    needs: build
    uses: OpenCHAMI/github-actions/.github/workflows/trivy-image-scan.yml@v4.0
    with:
      image-ref: ghcr.io/openchami/foo@${{ needs.build.outputs.digest }}
      # Optional overrides:
      # severity: CRITICAL
      # ignore-unfixed: true
      # exit-code: '0'  # report only
```

### scorecard (Reusable Workflow)
Runs the OpenSSF Scorecard supply-chain analysis and uploads SARIF findings to GitHub Advanced Security. Outside of `pull_request` runs it also publishes to the public OpenSSF dashboard, which is what backs the Scorecard badge. Trigger it on the default branch, on PRs, and on a schedule — running it on other branches scores an incomplete tree.

**Usage:**
```yaml
name: Scorecard
on:
  branch_protection_rule:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '39 5 * * 1'

permissions:
  contents: read
  security-events: write
  id-token: write

jobs:
  scorecard:
    uses: OpenCHAMI/github-actions/.github/workflows/scorecard.yml@v4.0
```

### build-publish-container-goreleaser (Reusable Workflow, Deprecated)

> [!CAUTION]
> **Deprecated.** Use `build-release-goreleaser` (build-only: `build-check-goreleaser`) instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Builds and publishes a container image via GoReleaser, with multi-arch builds, build provenance attestation, and PR snapshot support. Release builds (`is-pr-build: false`) pass GitHub's auto-generated release notes for the pushed tag to GoReleaser via `--release-notes`.

Optional `build-deps` is a space-separated list of apt packages installed before the build, for cases such as CGO cross-compilation that need a toolchain not present on the runner.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-publish-container-goreleaser.yml@v4.0
    with:
      registry-subject-name: ghcr.io/openchami/foo
      release-draft: false
      cgo-enabled: 1
      build-deps: gcc-aarch64-linux-gnu libc6-dev-arm64-cross
```

### build-rpm-quadlet (Reusable Workflow, Deprecated)

> [!CAUTION]
> **Deprecated.** Use nfpm packages built by `build-release-goreleaser` / `build-check-goreleaser` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Builds the caller repo's podman quadlet RPM and uploads it as an unsigned artifact for downstream signing.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-rpm-quadlet.yml@v4.0
    # Optional overrides:
    # with:
    #   artifact-name-unsigned-rpms: rpms-unsigned
```

### gpg-sign-artifacts (Reusable Workflow, Deprecated)

> [!CAUTION]
> **Deprecated.** Use nfpm package signing in `build-release-goreleaser` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Signs unsigned RPM artifacts with a per-run ephemeral key certified through the repo's release key chain, verifies the chain, and uploads the signed RPMs and public keys. Intended as the common entry point for signing all release artifact types (RPMs today; other formats later).

**Usage:**
```yaml
jobs:
  sign:
    uses: OpenCHAMI/github-actions/.github/workflows/gpg-sign-artifacts.yml@v4.0
    secrets: inherit
```

### validate-rpm-quadlet (Reusable Workflow, Deprecated)

> [!CAUTION]
> **Deprecated.** Use `validate-packages` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Validates a signed quadlet RPM's installed file list against the set of files the caller expects it to ship.

**Usage:**
```yaml
jobs:
  validate:
    uses: OpenCHAMI/github-actions/.github/workflows/validate-rpm-quadlet.yml@v4.0
    with:
      # artifact-name-signed-rpms: rpms-signed  # optional
      rpms: |
        - name: foo-*.rpm
          files:
            - /etc/containers/systemd/foo.container
```

### release-signed-artifacts (Reusable Workflow, Deprecated)

> [!CAUTION]
> **Deprecated.** Use the release created by `build-release-goreleaser` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Publishes a GitHub Release for a tag, attaching signed RPMs and public keys, with trust-chain verification instructions in the release body.

**Usage:**
```yaml
jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/release-signed-artifacts.yml@v4.0
    with:
      release-draft: false
```

### publish-release (Reusable Workflow)
Publishes the draft GitHub Release for a tag, for pipelines that set `release-draft: true` upstream so the release only appears once every artifact is attached.

**Usage:**
```yaml
jobs:
  publish:
    needs: release
    uses: OpenCHAMI/github-actions/.github/workflows/publish-release.yml@v4.0
    # Optional overrides:
    # with:
    #   make-latest: true  # true | false | legacy (default)
    #   draft: true
```

### pr-registry-cleanup (Reusable Workflow)
Deletes the GHCR container image versions a pull request published, once that pull request closes. Matches the PR's base tag and any separated qualifier (`pr-12`, `pr-12-amd64`, `pr-12-dirty-abc123`).

**Usage:**
```yaml
name: Cleanup
on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    uses: OpenCHAMI/github-actions/.github/workflows/pr-registry-cleanup.yml@v4.0
    permissions:
      packages: write
    # Optional overrides:
    # with:
    #   pr-number: 123
    #   tag-prefix: pr-
```

### stale (Reusable Workflow)
Marks issues and PRs stale after a period of inactivity and closes them if nothing changes, using the org-default `actions/stale` policy (stale after 35 days, closed 7 days later; `pinned`/`security` items exempt). Updating an item removes the stale label. The caller owns the schedule.

**Usage:**
```yaml
name: Stale
on:
  schedule:
    - cron: '23 3 * * *'  # daily at 03:23 UTC
  workflow_dispatch:

jobs:
  stale:
    uses: OpenCHAMI/github-actions/.github/workflows/stale.yml@v4.0
    permissions:
      issues: write
      pull-requests: write
    # Optional overrides:
    # with:
    #   days-before-stale: 35
    #   days-before-close: 7
    #   stale-issue-label: stale
    #   stale-pr-label: stale
    #   exempt-issue-labels: pinned,security,help wanted
    #   exempt-pr-labels: pinned,security
    #   operations-per-run: 500
    #   stale-issue-message: ...
    #   close-issue-message: ...
    #   stale-pr-message: ...
    #   close-pr-message: ...
```

### lint-codegen-fabrica (Reusable Workflow)
Fails when a Fabrica project's committed generated code is out of date by running the caller's `make generate-check` with Fabrica built from source (passed as `LOCAL_FABRICA`), at the version pinned in `go.mod` unless `fabrica-ref` (tag, branch, or commit SHA) is set. A source build is required: Fabrica stamps its version into generated code, and a `go run` build reports `dev` instead.

**Usage:**
```yaml
name: Lint Codegen
on:
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  lint-codegen:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-codegen-fabrica.yml@v4.0
    # Optional overrides:
    # with:
    #   go-version: stable          # mutually exclusive with go-version-file
    #   go-version-file: go.mod
    #   fabrica-ref: v0.4.5         # tag, branch, or SHA; default: version in go.mod
```

## Actions

### gpg-configure-release-keys (Deprecated)

> [!CAUTION]
> **Deprecated.** Use nfpm package signing in `build-release-goreleaser` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Generates a per-run ephemeral GPG key, certified through the repo's release key chain (master certifies a repo cert key, which certifies the ephemeral key). See the [action README](actions/gpg-configure-release-keys/README.md).

### gpg-sign-rpm (Deprecated)

> [!CAUTION]
> **Deprecated.** Use nfpm package signing in `build-release-goreleaser` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Signs an RPM using a provided GPG fingerprint (works with the ephemeral key output from `gpg-configure-release-keys`) and exposes signature verification output. See the [action README](actions/gpg-sign-rpm/README.md).

### gpg-check-key-expiration
Fails CI if the provided signing key is expired or expiring within a threshold. See the [action README](actions/gpg-check-key-expiration/README.md).

### gpg-verify-trust-chain (Deprecated)

> [!CAUTION]
> **Deprecated.** Use the `rpm -K` check in `validate-packages` instead. Kept only for callers pinned to older refs; it will be removed in a future major release.

Verifies the master/repo-cert/ephemeral trust chain and optionally checksigs RPMs. See the [action README](actions/gpg-verify-trust-chain/README.md).

## Security Model

> [!CAUTION]
> **Deprecated.** The ephemeral-key trust chain below is being retired in favor of a single signing key used by `build-release-goreleaser`. It applies only to the deprecated signing workflows and actions.

Trust chain: `Ephemeral Key <- Repo Cert Key <- Offline Master Key`.

Design principles:
- Ephemeral keys reduce exposure window.
- Repo cert keys are easily revocable & rotated.
- Isolated `GNUPGHOME` avoids polluting runner defaults.
- GNUPGHOME cleanup is the calling workflow's responsibility, not optional.

Key expiration limits future signing only; existing signatures remain valid if the trust chain remains intact.

## Example Workflow (Combined)

> [!CAUTION]
> **Deprecated.** This example uses deprecated workflows. New pipelines should use `build-release-goreleaser` + `validate-packages`.

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
        pr-number:
          description: 'PR Number to build (optional, for manual PR builds)'
          required: false
          type: string

permissions:
  contents: read   # baseline; jobs that need more request it below
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
    uses: OpenCHAMI/github-actions/.github/workflows/build-publish-container-goreleaser.yml@v4.0
    secrets: inherit
    permissions:
      contents: write      # release creation, uploading assets
      packages: write      # image push, container provenance
      id-token: write      # Sigstore signing (attest-build-provenance)
      attestations: write  # build provenance attestations
    with:
      cgo-enabled: 0
      registry-subject-name: ghcr.io/openchami/metadata-service
      is-pr-build: true
      pr-number: ${{ inputs.pr-number || github.event.pull_request.number || 0 }}

  rpm-build:
    needs: [config, build]
    uses: OpenCHAMI/github-actions/.github/workflows/build-rpm-quadlet.yml@v4.0
    secrets: inherit
    with:
      artifact-name-unsigned-rpms: ${{ needs.config.outputs.rpm-unsigned }}

  rpm-sign:
    needs: [config, rpm-build]
    uses: OpenCHAMI/github-actions/.github/workflows/gpg-sign-artifacts.yml@v4.0
    secrets: inherit
    with:
      artifact-name-unsigned-rpms: ${{ needs.config.outputs.rpm-unsigned }}
      artifact-name-signed-rpms:   ${{ needs.config.outputs.rpm-signed }}
      artifact-name-public-keys:   ${{ needs.config.outputs.keys-public }}

  rpm-validate:
    needs: [config, rpm-sign]
    uses: OpenCHAMI/github-actions/.github/workflows/validate-rpm-quadlet.yml@v4.0
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

- Workflow files are linted via `0-local-ci.yml`, which calls `lint-ci.yml` (actionlint + zizmor).
- Packages built by the GoReleaser workflows are validated via `validate-packages.yml`.
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
