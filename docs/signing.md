<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Signing releases

Every tagged release is signed in CI, so anyone (and the repo that publishes our packages to
dnf/apt repositories) can prove it came from that repo's release workflow. Signing is
format-agnostic: packages ship unsigned, and `gpg-sign-artifacts` signs GoReleaser's
`checksums.txt`, whose hashes cover every package, archive, and binary in the release.

## The keys

Four GPG keys are involved. The first three form a chain that proves where a release came from;
the fourth is the only one end users ever import.

| Key | What it is | Where it lives | Signs | Release file |
|---|---|---|---|---|
| **Root key** | OpenCHAMI's root of trust | offline, held by a few maintainers; its public key and fingerprint are org secrets (`MASTER_PUBLIC_ASC`, `MASTER_FPR`) | repo keys | `pubkey-org.asc` |
| **Repo key** | one per service repo, named `<owner>/<repo> RPM Signing Key` | the repo's `GPG_REPO_CERT_KEY_B64` secret | release keys | `pubkey-repo.asc` |
| **Release key** | a fresh key for each release run, expiring after 1 day | only inside the signing job; never stored | `checksums.txt` | `pubkey-signing.asc` |
| **Archive key** | the key behind OpenCHAMI's dnf/apt repositories | `todo-signing-repo` (see [Distribution](distribution.md)) | packages and repository metadata | (shipped in a keyring package) |

Read it bottom-up: the release key signed `checksums.txt`, the repo key vouches for the release
key, and the root key vouches for the repo key. Why split it this way:

- **The root key never touches CI.** Leaking a CI secret can't forge the root of trust.
- **A repo key can only speak for its own repo.** Its certified name binds it to one repository,
  so a leaked repo key can't publish as another repo, and it can be revoked without touching the
  others.
- **A release key is worthless after the run.** It's generated, used, and shredded inside one job,
  and it expires within a day even if it somehow escaped.

End users don't deal with any of this: they trust the archive key, and `todo-signing-repo` checks
the chain before it signs anything with it.

Keys are created, renewed, and revoked with the scripts in
[gpg-signing-manager](https://github.com/OpenCHAMI/gpg-signing-manager) (`create-repo-key.sh`
names the repo key correctly). Repo keys expire yearly; signing fails within 30 days of expiry.
Whether a repo key is renewed (same key, new expiry) or rotated (a new key certified by the root
key) is a key-holder decision; either way, update the repo's `GPG_REPO_CERT_KEY_B64` secret. The
older signing-subkey secret (`GPG_REPO_KEY_B64`) isn't used.

## The release flow

A `v*` tag push runs, in order:

1. `build-release-goreleaser` creates a **draft** release with `checksums.txt`.
2. `gpg-sign-artifacts` creates the release key, certifies it with the repo key, signs
   `checksums.txt`, checks the chain, and uploads `checksums.txt.asc` and the three
   `pubkey-*.asc` files as an artifact.
3. `release-modify` attaches them to the draft and appends verification instructions to the
   release notes.
4. `release-publish` publishes the release.

The release stays a draft until it's signed: `release-modify` and `release-publish` fail if it's
already public. See the [README's combined example](../README.md#example-workflow-combined) for
the workflow file.

### What a repo needs

- The repo key as the `GPG_REPO_CERT_KEY_B64` repo secret, and the org secrets
  `MASTER_PUBLIC_ASC` and `MASTER_FPR` passed to `gpg-sign-artifacts`.
- A static checksums file name in `.goreleaser.yaml`, so every release has the same files:

  ```yaml
  checksum:
    name_template: checksums.txt
  ```

- Package names that start with the repo name (`<repo>` or `<repo>-*`), or `todo-signing-repo`
  won't publish them (see [Distribution](distribution.md)).

## Verifying a release by hand

The release notes carry the exact commands. In short: import the three `pubkey-*.asc` files into a
scratch keyring, check that `pubkey-org.asc` matches OpenCHAMI's published root key fingerprint,
check the certifications with `gpg --check-sigs`, then
`gpg --verify checksums.txt.asc checksums.txt` and `sha256sum --check --ignore-missing checksums.txt`.
Never trust `pubkey-org.asc` on its own: anyone who can edit a release can replace it. The
`gpg-verify-trust-chain` action does all of this against a pinned root key.
