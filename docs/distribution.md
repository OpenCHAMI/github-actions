<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Distribution

> [!WARNING]
> **Planned.** `todo-signing-repo` doesn't exist yet; its name is a placeholder. This page records
> the agreed design (#43, option A2) so service repos can be built for it now.

Signed releases (see [Signing releases](signing.md)) end up on GitHub. Getting their packages into
dnf/apt repositories is the job of one central repo, `todo-signing-repo`. Service repos don't know
it exists and need no extra credentials: it pulls from them.

## How it works

On a schedule (about every 10 minutes), `todo-signing-repo`:

1. **Polls** a fixed list of service repos for new published releases. Drafts are invisible to it,
   so it never sees a half-finished release. Prereleases (e.g. `v1.2.3-rc1`) are skipped: we only
   publish stable releases.
2. **Admits** each new release, independently and in parallel:
   - the trust chain verifies against its pinned root key (see [The keys](signing.md#the-keys))
   - `checksums.txt.asc` is a good signature, and every file it lists matches its hash
   - every package name is `<repo>` or `<repo>-*`, or on a small allowlist (e.g.
     `OpenCHAMI/release` may publish `openchami`)

   Any failure rejects the release; nothing from it is published. `checksums.txt` is the manifest:
   files not listed in it are ignored.
3. **Groups** the admitted packages by target repository (format, and later distro version), so
   each repository's metadata is rebuilt once per batch rather than once per package.
4. **Signs and publishes** each batch with the archive key: rpm packages are signed individually
   plus a signed `repomd.xml`; apt signs one `Release` file over all package hashes. Publishes to
   the same repository never run at the same time.

The admission checks reuse `gpg-verify-trust-chain` from this repo.

## Publishing rules

- **Semver.** A new patch release replaces the previous patch of the same major.minor (publishing
  1.2.4 removes 1.2.3). Older major/minor lines stay until EOL (see [Not decided yet](#not-decided-yet)).
- **Published versions are immutable.** A version is never re-published with different contents;
  a fix ships as a new version.
- **Rejected releases are re-released.** If a release fails admission (e.g. it was processed
  after its 1-day release key expired), push a new patch release rather than repairing the old
  one.

## The archive key

The archive key is the only key end users import. `todo-signing-repo` holds it as a secret that a
small set of maintainers administer, and rotates it yearly. It also builds and signs an
`openchami-archive-keyring` rpm and deb: during a rotation the keyring ships both the current and
the next public key, so clients move to the new key through normal upgrades. First-time setup
fetches the key from the distribution server over HTTPS.

## Not decided yet

> [!TODO]
> 
> - Which formats get repositories (releases carry rpm, deb, apk, and pacman packages), and whether
>   packages are built per distro version (e.g. per-EL rpms).
> - Hosting details (S3-backed, domain, account owner) and the exact polling interval.
> - Whether archive key rotation is manual or automated.
> - When to EOL (stop publishing) older major and minor lines; standard semver EOL semantics
>   probably hold, but the group decides.
