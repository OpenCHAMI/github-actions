<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# gpg-check-key-expiration

Fails the job if a provided secret key is expired or expires within
`warn-days`. Imports into an isolated `GNUPGHOME` that's shredded on exit;
never touches the runner's default keyring.

Expiry check itself is fetched at runtime, pinned to a commit SHA, from
[gpg-signing-manager](https://github.com/OpenCHAMI/gpg-signing-manager)'s
`check-key-expiry.sh`.
