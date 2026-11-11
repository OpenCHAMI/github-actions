<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# GoReleaser

Every OpenCHAMI repo builds and releases through one file: its `.goreleaser.yaml`. This page covers
why, what that means for your repo, and the decisions baked into the workflows that run it. For a
config to copy, start from the annotated [`.goreleaser.example.yml`](../.goreleaser.example.yml).
For a working repo, see [OpenCHAMI/github-actions-testbed](https://github.com/OpenCHAMI/github-actions-testbed):
its `.goreleaser.yaml` and workflows exercise everything on this page.

## Why GoReleaser

OpenCHAMI is a Go org. Before v4.0, each repo assembled its own release from bespoke pieces:
GoReleaser in some repos, hand-written `docker build` jobs and rpm spec files in others, and
release jobs that each worked slightly differently. GoReleaser replaces all of that with one
declarative config that produces, in one run:

- cross-compiled binaries, with build metadata in the ldflags
- tarballs and a `checksums.txt` covering every release file
- multi-arch container images
- rpm and deb packages (via nfpm: no spec files, no rpmbuild)
- the GitHub release itself

Standardizing on it means one mental model across repos, one example config to maintain, and
reusable workflows that stay small because GoReleaser does the work. The same config also runs
locally (`make release-snapshot`, `make build-packages` from [Makefile.common](makefile-common.md)),
so what you build on your machine is what CI builds. We use the open-source edition only; nothing
depends on GoReleaser Pro.

## What it means for a Go repo

Add a `.goreleaser.yaml` (start from the example) and call three workflows:

| Workflow | Trigger | What happens |
|---|---|---|
| `build-check-goreleaser` | PRs | `--snapshot` build of everything; publishes nothing, needs no secrets, safe for fork PRs |
| `build-release-goreleaser` | PRs | pushes `pr-<N>` images only |
| `build-release-goreleaser` | `v*` tag | full release: semver images, binaries, archives, packages, draft GitHub release, attestations |
| `validate-packages` | after either build | installs each rpm/deb in a matching container and checks its exact file list |

A tag release then goes through signing and `release-publish` (see [Signing releases](signing.md)).
The [README's combined example](../README.md#example-workflow-combined) shows the whole chain.

## Design decisions

- **The event picks the mode; there are no mode inputs.** A PR builds PR images, a `v*` tag builds
  a release, and any other trigger fails. CI/CD that needs a human to pick the right switch isn't
  CI/CD.
- **PR images are tagged `pr-<N>`.** `trivy-image-scan` scans them and `pr-registry-cleanup`
  deletes them when the PR closes. PR builds skip packages and archives, since `pr-<N>` isn't a
  valid package version; `build-check-goreleaser` covers packages on PRs instead. Fork PRs build but
  publish nothing.
- **Releases start as drafts.** Nothing goes public until validation and signing have finished
  and `release-publish` runs; `release-modify` and `release-publish` refuse a release that's
  already public.
- **GoReleaser doesn't sign.** Packages ship unsigned; `gpg-sign-artifacts` signs
  `checksums.txt`, whose hashes cover every package, archive, and binary. That's why the checksums
  file has one static name everywhere (`checksum.name_template: checksums.txt`).
- **No Go module cache on release builds.** Published artifacts must not come from a cache that a
  PR could have poisoned.
- **A fixed environment contract.** The workflows always set `IS_PR_BUILD`, `GIT_STATE`,
  `BUILD_HOST`, `GO_VERSION`, and `BUILD_USER`, and `Makefile.common` exports the same names, so
  one config works in CI and locally.
- **Provenance comes for free.** Release builds attest the binaries and every published image.
- **Publishing to dnf/apt repositories is out of scope.** GoReleaser only attaches packages to the
  GitHub release; a separate central repo verifies, re-signs, and publishes them.

## Non-Go repos

Repos that only ship files (podman quadlets, configs, scripts) still use GoReleaser. It's a bit of
a shoehorn, but they get the same PR checks, draft release, signing, and validation as every other
repo:

```yaml
builds:
  - skip: true            # nothing to compile
nfpms:
  - id: foo-quadlet
    meta: true            # a package of files, no binaries
    contents:
      - src: build/quadlet/foo.container
        dst: /usr/share/containers/systemd/foo.container
```

- Render templated files (e.g. a quadlet's image tag) in a `before` hook, write them outside
  `dist/`, and gitignore them: GoReleaser refuses to release from a dirty tree.
- GoReleaser only compiles Go. Anything else has to be built in a `before` hook or ahead of the
  workflow.
- The workflows still install a Go toolchain; it's unused, just a few seconds of setup.

## Caveats

- **One package per format per nfpm entry.** Packages for several distro releases (e.g. per-EL
  rpms) need one entry each, and cgo binaries need a build per target glibc. The example config
  explains the pattern.
- **nfpm's `release` is a literal string**: no templates and no rpm macros, so set suffixes like
  `1.el9` yourself.
- **`overrides.<format>.contents` replaces the whole list**, so keep `contents` at the top level and
  mark single-format files with `packager:`.
- **`validate-packages` checks the exact file list**, so list every directory your package creates
  (`type: dir`) as well as its files.
