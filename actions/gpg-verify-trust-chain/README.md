<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# gpg-verify-trust-chain

Verifies the release trust chain (master certifies repo key, repo key
certifies ephemeral key) and optionally checksigs any RPMs found under
`rpm-dir`. Standalone: installs its own deps, no prior GPG state assumed.

Verification itself is fetched at runtime, pinned to a commit SHA, from
[gpg-signing-manager](https://github.com/OpenCHAMI/gpg-signing-manager)'s
`verify-chain.sh`.
