<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Actions

Composite actions, used with `uses: OpenCHAMI/github-actions/actions/<name>@<ref>`. Each action's README has its inputs and outputs.

## discover-ghcr-images
Finds a repo's GHCR image names from the `images` input, else the GoReleaser config, else the repo name, and verifies each one exists. Used by `trivy-image-scan` and `pr-registry-cleanup`. See the [action README](../actions/discover-ghcr-images/README.md).

## gpg-verify-trust-chain
Verifies the trust chain (the root key certifies the repo key, which certifies the release key) against a pinned root key fingerprint, and each file's signature from the release key (see [The keys](signing.md#the-keys)). Rejects revoked or expired keys. Used by `gpg-sign-artifacts`, and by anything that admits signed releases. See the [action README](../actions/gpg-verify-trust-chain/README.md).
