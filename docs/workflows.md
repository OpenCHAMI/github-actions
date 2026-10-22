<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Workflows

Reusable workflows, called with `uses: OpenCHAMI/github-actions/.github/workflows/<name>.yml@<ref>` (see [Versioning & Usage](../README.md#versioning--usage)). For the GoReleaser config contract see [GoReleaser](goreleaser.md); for the signing flow and key model see [Signing releases](signing.md).

## Building and releasing

### build-check-goreleaser
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

### build-release-goreleaser
Runs the caller's GoReleaser config in one of two modes, chosen from the triggering event (no manual override; any other trigger fails):

- **PR** (`pull_request` event): tags HEAD locally as `pr-<PR number>` and pushes the resulting images (e.g. `:pr-12`). No GitHub release, no signing, no attestation, and no packages: nfpm is skipped because a `pr-<N>` version isn't a valid deb version, so validate PR packages with `build-check-goreleaser` (snapshot) instead. Fork PRs build but publish nothing.
- **Release** (`v*` tag push): semver images, unsigned packages, a GitHub release (draft by default) with GitHub-generated notes, and build provenance attestations for the release files and every published image. Sign the release with `gpg-sign-artifacts` (see [Signing releases](signing.md)).

Outputs `version` and `images` (published images as a JSON array of `{name, digest}`, `[]` on fork PRs). Uploads the packages, archives, and checksums as an artifact for `validate-packages`.

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
    # Optional overrides:
    # with:
    #   go-version: stable          # mutually exclusive with go-version-file
    #   go-version-file: go.mod
    #   goreleaser-version: v2.18.2
    #   build-deps: gcc-aarch64-linux-gnu libc6-dev-arm64-cross
    #   cgo-enabled: 1
    #   release-draft: false        # default true; publish later with release-publish
    #   generate-release-notes: false
    #   attestation-subject-path: dist/**
    #   goreleaser-args: --timeout 60m
    #   dist-artifact-name: goreleaser-dist
```

### validate-packages
Validates the rpm/deb packages from either build workflow's artifact, one job per package, in a matching container (`rockylinux:9` for `.rpm`, `debian:13` for `.deb`):

- **File list**: must match `files` exactly. rpm lists include every owned directory; deb lists contain regular files and symlinks only, since dpkg owns parent directories implicitly.
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
        - name: foo-quadlet*
          files:
            - /etc/openchami/configs/foo.yaml
            - /usr/share/containers/systemd/foo.container
          rpm-files:
            - /usr/share/licenses/foo-quadlet/MIT.txt
          deb-files:
            - /usr/share/doc/foo-quadlet/copyright
      # Optional overrides:
      # dist-artifact-name: goreleaser-dist
      # rpm-image: docker.io/library/rockylinux:9
      # deb-image: docker.io/library/debian:13
      # lint: false
```

## Signing and publishing releases

### gpg-sign-artifacts
Signs release files with a per-run release key, in one job so the private key never leaves it: imports the repo key (the `repo-cert-key` secret; fails if it expires within `key-expiry-warn-days`), generates an ed25519 release key with a 1-day expiry, certifies it with the repo key, signs each file to `<file>.asc`, verifies the chain with `gpg-verify-trust-chain`, and shreds the keyring. Uploads the signatures and the three `pubkey-*.asc` public keys as an artifact, and outputs `release-notes`, Markdown verification instructions for `release-modify`. Runs only on a `v*` tag push.

**Usage:**
```yaml
jobs:
  sign:
    needs: release
    uses: OpenCHAMI/github-actions/.github/workflows/gpg-sign-artifacts.yml@v4.0
    secrets:
      repo-cert-key: ${{ secrets.GPG_REPO_CERT_KEY_B64 }}
      master-public-key: ${{ secrets.MASTER_PUBLIC_ASC }}
      master-fingerprint: ${{ secrets.MASTER_FPR }}
    # Optional overrides:
    # with:
    #   dist-artifact-name: goreleaser-dist
    #   files: checksums.txt                  # file names at the artifact root
    #   signatures-artifact-name: release-signatures
    #   key-expiry-warn-days: 30
```

### release-modify
Edits the draft GitHub Release for the triggering tag before `release-publish` makes it public: appends to or replaces its notes, and adds or replaces release files from an artifact. Fails unless the release is still a draft. `files-mode: add` fails if a release file already has the name; `replace` overwrites it.

**Usage:**
```yaml
jobs:
  release-modify:
    needs: sign
    uses: OpenCHAMI/github-actions/.github/workflows/release-modify.yml@v4.0
    permissions:
      contents: write
    with:
      notes: ${{ needs.sign.outputs.release-notes }}
      files-artifact-name: release-signatures
      # Optional overrides:
      # notes-mode: replace   # default append
      # files-mode: replace   # default add
```

### release-publish
Publishes the draft GitHub Release for a tag, for pipelines that set `release-draft: true` upstream so the release only appears once every artifact is attached. Fails if the release is already published.

**Usage:**
```yaml
jobs:
  publish:
    needs: release
    uses: OpenCHAMI/github-actions/.github/workflows/release-publish.yml@v4.0
    # Optional overrides:
    # with:
    #   make-latest: true  # true | false | legacy (default)
    #   draft: true
```

## Linting

### lint-ci
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

### lint-go
Lints the caller's Go module. Runs `golangci-lint`, and separately verifies `go.mod`/`go.sum` are tidy by running the tidy command and failing on a dirty diff. Uses Go `stable` unless the caller sets `go-version` or `go-version-file`. `golangci-lint` is pinned (Renovate-managed); override with `golangci-lint-version`.

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
    #   golangci-lint-version: v2.14.0
    #   go-version-file: go.mod
    #   runner: ubuntu-latest
```

### lint-codegen-fabrica
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
    #   runner: ubuntu-latest
```

### lint-renovate
Validates the caller's Renovate config with `renovate-config-validator` (as repository config). With no `config-file`, it checks every Renovate config file it finds (`renovate.json`, `.github/renovate.json`, `renovate.json5`, `.renovaterc`, ...).

**Usage:**
```yaml
name: Lint Renovate
on:
  pull_request:
    paths:
      - renovate.json
      - .github/workflows/lint-renovate.yml

jobs:
  lint-renovate:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-renovate.yml@v4.0
    # Optional overrides:
    # with:
    #   renovate-version: 44.115.13
    #   config-file: renovate.json
```

### lint-docs
Checks the caller's docs for broken links with [lychee](https://github.com/lycheeverse/lychee). It reports broken links rather than failing:

- **Pull requests** that change docs (`.md`, `.html`, `.rst`): findings go to code scanning (category `lint-docs`), so the PR is annotated like `lint-ci`'s zizmor findings, and each alert closes once a later commit fixes the link. Broken links fail the code scanning check, timeouts only warn. PRs that change no docs skip the check. Fork PRs can't upload, so they only get the job summary. Private repos need GitHub Code Security for the upload; public repos need no setup.
- **Default branch** (push, schedule, or dispatch): keeps one open issue (`issue-title`) with the report, created or updated on each run and closed once the links are fixed. Timeouts alone don't open it.

Checks every `.md`, `.html`, and `.rst` file (lychee-action's defaults). Configure lychee with a [`lychee.toml`](https://lychee.cli.rs/guides/config/) at the repository root, e.g. `exclude_path` to skip files; see [Excluding links](https://lychee.cli.rs/recipes/excluding-links/) for `.lycheeignore`. The job fails only when lychee itself errors. A schedule catches external links that break between pushes.

**Usage:**
```yaml
name: Lint Docs
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'   # catch external links that rot

jobs:
  lint-docs:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-docs.yml@v4.0
    permissions:
      contents: read          # baseline for checkout
      pull-requests: read     # list the PR's changed files
      security-events: write  # SARIF upload to GHAS
      issues: write           # broken-links issue on the default branch
    # Optional overrides:
    # with:
    #   issue-title: Docs link check found broken links
```

### lint-makefile-common
Fails when the repo's vendored `Makefile.common` differs from the copy in the latest release of this repository (read at the release's commit SHA), and prints the diff. Takes no inputs. Make it a required check only if drift should block merging.

**Usage:**
```yaml
name: Lint Makefile.common
on:
  pull_request:
  schedule:
    - cron: '0 6 * * 1'   # catch new releases

jobs:
  lint-makefile-common:
    uses: OpenCHAMI/github-actions/.github/workflows/lint-makefile-common.yml@v4.0
```

## Testing and security

### test-unit-go
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
    #   runner: ubuntu-latest
```

### reuse
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

### govulncheck
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
    permissions:
      contents: read
      security-events: write  # SARIF upload to GHAS
    # Optional overrides:
    # with:
    #   go-version: 1.26.7  # default: read from go.mod
    #   go-package: ./cmd/...
    #   runner: ubuntu-latest
```

### dependency-review
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

### trivy-image-scan
Scans already-pushed container images with Trivy and uploads SARIF findings to GitHub Advanced Security. It scans each image at the build's tag (the pushed tag, or `pr-<N>` on pull requests; also when run from `workflow_run`), one job per image, by digest. Fork PRs publish no images and are skipped. GitHub doesn't let `GITHUB_TOKEN` list packages, so image names come from `images`, else the `ghcr.io` entries in the GoReleaser config (`dockers_v2[].images`), else the repository name (see `discover-ghcr-images`). Every name must be an existing package; all bad names are reported, then the run fails. Run it after `build-release-goreleaser`.

**Usage:**
```yaml
jobs:
  build:
    uses: OpenCHAMI/github-actions/.github/workflows/build-release-goreleaser.yml@v4.0

  scan:
    needs: build
    uses: OpenCHAMI/github-actions/.github/workflows/trivy-image-scan.yml@v4.0
    permissions:
      contents: read
      packages: read
      security-events: write
    # Optional overrides:
    # with:
    #   images: foo foo-init   # default: from the GoReleaser config, else the repo name
    #   severity: CRITICAL
    #   ignore-unfixed: true
    #   exit-code: '0'  # report only
    #   runner: ubuntu-latest
```

### scorecard
Runs the OpenSSF Scorecard supply-chain analysis and uploads SARIF findings to GitHub Advanced Security. Outside of `pull_request` runs it also publishes to the public OpenSSF dashboard, which is what backs the Scorecard badge. Trigger it on the default branch, on PRs, and on a schedule: running it on other branches scores an incomplete tree.

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

## Maintenance

### pr-registry-cleanup
Deletes the GHCR container image versions a pull request published, once that pull request closes. Matches the PR's base tag and any separated qualifier (`pr-12`, `pr-12-amd64`, `pr-12-dirty-abc123`) in each image, one job per image. Image names come from `images`, else the GoReleaser config, else the repository name (see `discover-ghcr-images`). Fork PRs are skipped, since they publish nothing. Every name must be an existing package; all failed lookups and deletes are reported, then the run fails.

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
      contents: read
      packages: write
    # Optional overrides:
    # with:
    #   images: foo foo-init   # default: from the GoReleaser config, else the repo name
```

### stale
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
