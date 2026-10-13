<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# discover-ghcr-images

Finds and verifies the caller's GHCR package names. `GITHUB_TOKEN` can't list an
organization's packages, so names come from exactly one source:

1. the `images` input, if set
2. else the `ghcr.io` entries in the GoReleaser config's `dockers_v2[].images`
   (found the same way GoReleaser finds it)
3. else the repository name, lowercased

Every name must be an existing package; all bad names are reported, then the
step fails. Check out the repository first, and grant the job `packages: read`.

```yaml
- uses: actions/checkout@<sha>
  with:
    persist-credentials: false
- id: discover
  uses: OpenCHAMI/github-actions/actions/discover-ghcr-images@<sha>
  # with:
  #   images: foo foo-init
- run: echo "${{ steps.discover.outputs.names }} (from ${{ steps.discover.outputs.source }})"
```

Outputs `names` (space-separated, without registry or owner) and `source`
(`input`, `goreleaser`, or `repo`).
