<!--
SPDX-FileCopyrightText: 2025 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# GitHub Actions Monorepo for `OpenCHAMI`

Reusable GitHub Actions for CI/CD.

## Structure

- [`actions/discover-ghcr-images`](docs/actions.md#discover-ghcr-images): Finds and verifies a repo's GHCR image names (`images` input, GoReleaser config, or repo name)
- [`actions/gpg-verify-trust-chain`](docs/actions.md#gpg-verify-trust-chain): Verifies the root/repo/release key trust chain and the release key's file signatures
- [`.github/workflows/gpg-sign-artifacts.yml`](docs/workflows.md#gpg-sign-artifacts): Signs release files (e.g. `checksums.txt`) with a per-run release key certified through the key chain
- [`.github/workflows/release-modify.yml`](docs/workflows.md#release-modify): Edits a draft GitHub Release: appends or replaces notes, adds or replaces files
- [`.github/workflows/release-publish.yml`](docs/workflows.md#release-publish): Publishes the draft GitHub Release for a tag
- [`.github/workflows/lint-ci.yml`](docs/workflows.md#lint-ci): Reusable workflow that lints workflow files (actionlint + zizmor)
- [`.github/workflows/lint-go.yml`](docs/workflows.md#lint-go): Reusable workflow that runs golangci-lint and checks go.mod/go.sum are tidy
- [`.github/workflows/test-unit-go.yml`](docs/workflows.md#test-unit-go): Reusable workflow that runs Go unit tests, optionally reporting coverage to Coveralls
- [`.github/workflows/reuse.yml`](docs/workflows.md#reuse): Reusable workflow that checks REUSE copyright/licensing compliance
- [`.github/workflows/govulncheck.yml`](docs/workflows.md#govulncheck): Reusable workflow that scans Go modules for known CVEs (govulncheck), reporting on PRs and in an issue
- [`.github/workflows/dependency-review.yml`](docs/workflows.md#dependency-review): Reusable workflow that gates PRs introducing CVE-flagged deps
- [`.github/workflows/trivy-image-scan.yml`](docs/workflows.md#trivy-image-scan): Reusable workflow that scans built container images for CVEs
- [`.github/workflows/scorecard.yml`](docs/workflows.md#scorecard): Reusable workflow that runs the OpenSSF Scorecard supply-chain analysis
- [`.github/workflows/pr-registry-cleanup.yml`](docs/workflows.md#pr-registry-cleanup): Deletes the GHCR container images a PR published, once it closes
- [`.github/workflows/build-check-goreleaser.yml`](docs/workflows.md#build-check-goreleaser): Reusable workflow that builds everything in a GoReleaser config (snapshot) without publishing
- [`.github/workflows/build-release-goreleaser.yml`](docs/workflows.md#build-release-goreleaser): Reusable workflow that publishes `pr-<N>` images for PRs, or a full GoReleaser release for tags
- [`.github/workflows/validate-packages.yml`](docs/workflows.md#validate-packages): Reusable workflow that validates rpm/deb packages (file list, install, lint)
- [`.github/workflows/stale.yml`](docs/workflows.md#stale): Reusable workflow that marks and closes inactive issues and PRs (org-default policy)
- [`.github/workflows/lint-codegen-fabrica.yml`](docs/workflows.md#lint-codegen-fabrica): Reusable workflow that fails when a Fabrica project's committed generated code is out of date
- [`.github/workflows/lint-renovate.yml`](docs/workflows.md#lint-renovate): Reusable workflow that validates the caller's Renovate config
- [`.github/workflows/lint-docs.yml`](docs/workflows.md#lint-docs): Reusable workflow that checks docs for broken links (lychee), reporting on PRs and in an issue
- [`.github/workflows/lint-makefile-common.yml`](docs/workflows.md#lint-makefile-common): Reusable workflow that fails when a repo's vendored `Makefile.common` differs from the latest release
- [`Makefile.common`](docs/makefile-common.md): Shared Makefile targets that OpenCHAMI repos vendor and include

### Workflow naming

`0-local-*` workflows are this repo's own CI, not reusable workflows. The `0`
just sorts them to the top.

## Documentation

- [Workflows](docs/workflows.md): every reusable workflow's behavior, inputs, and usage
- [Actions](docs/actions.md): the composite actions
- [GoReleaser](docs/goreleaser.md): how the GoReleaser workflows use your `.goreleaser.yaml`
- [Signing releases](docs/signing.md): the keys, the signing flow, and verifying a release
- [Distribution](docs/distribution.md): how signed packages reach dnf/apt repositories (planned)
- [Makefile.common](docs/makefile-common.md): the shared Makefile and its drift check

> [!WARNING]
> **TODO:** the central signing repo doesn't have a name yet. The docs call it `todo-signing-repo`;
> replace that placeholder (in `docs/signing.md` and `docs/distribution.md`) once the repo exists.

## GoReleaser

OpenCHAMI is a Go org, so builds, packages, images, and releases standardize on [GoReleaser](https://goreleaser.com): one `.goreleaser.yaml` per repo drives every build and release workflow here. See [GoReleaser](docs/goreleaser.md) and the annotated [`.goreleaser.example.yml`](.goreleaser.example.yml).

## Versioning & Usage

Pin a release tag:

```yaml
# For actions
- uses: OpenCHAMI/github-actions/actions/discover-ghcr-images@v4.0

# For reusable workflows
jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/build-release-goreleaser.yml@v4.0
```

Pin a commit SHA instead for maximum supply-chain safety if desired.

Workflows with a `runner` input run on `ubuntu-slim` by default, which has 1 CPU and a 15-minute job limit; set `runner: ubuntu-latest` for longer jobs.

## Example Workflow (Combined)

A release pipeline on `v*` tags: build, validate and sign in parallel, attach the signatures, then publish (see [Signing releases](docs/signing.md)):

```yaml
name: Release
on:
  push:
    tags: ['v*']

permissions:
  contents: read   # baseline; jobs that need more request it below

jobs:
  release:
    uses: OpenCHAMI/github-actions/.github/workflows/build-release-goreleaser.yml@v4.0
    permissions:
      contents: write
      packages: write
      id-token: write
      attestations: write

  validate:
    needs: release
    uses: OpenCHAMI/github-actions/.github/workflows/validate-packages.yml@v4.0
    with:
      packages: |
        - name: foo*
          files:
            - /usr/bin/foo

  sign:
    needs: release
    uses: OpenCHAMI/github-actions/.github/workflows/gpg-sign-artifacts.yml@v4.0
    secrets:
      repo-cert-key: ${{ secrets.GPG_REPO_CERT_KEY_B64 }}
      master-public-key: ${{ secrets.MASTER_PUBLIC_ASC }}
      master-fingerprint: ${{ secrets.MASTER_FPR }}

  release-modify:
    needs: sign
    uses: OpenCHAMI/github-actions/.github/workflows/release-modify.yml@v4.0
    permissions:
      contents: write
    with:
      notes: ${{ needs.sign.outputs.release-notes }}
      files-artifact-name: release-signatures

  publish:
    needs: [validate, release-modify]
    uses: OpenCHAMI/github-actions/.github/workflows/release-publish.yml@v4.0
    permissions:
      contents: write
```

## Continuous Integration

- Workflow files are linted via `0-local-ci.yml`, which calls `lint-ci.yml` (actionlint + zizmor).
- Packages built by the GoReleaser workflows are validated via `validate-packages.yml`.
- Real testing happens in [OpenCHAMI/github-actions-testbed](https://github.com/OpenCHAMI/github-actions-testbed), which calls these workflows and actions the way a service repo would. It's also the reference caller: new projects should copy from it.

## Contributing

- Open issues for feature requests.
- Submit PRs with accompanying test workflow updates.

## License

MIT
