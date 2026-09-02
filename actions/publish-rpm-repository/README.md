<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Publish RPM Repository Action

Builds DNF/YUM repository metadata for signed RPMs, signs `repomd.xml` with a
durable repository metadata key, and safely publishes the repository to S3.

Each service repository signs its RPMs with a certified per-run ephemeral key
before the release workflow aggregates them. This action authenticates every
ephemeral key through the trusted master and repository certification-key chain,
then verifies every incoming and previously published RPM before signing the
repository metadata.

## Publication model

The action restores previously published immutable RPMs, adds the incoming RPMs,
and regenerates metadata for the complete package set. It never deletes packages
or metadata from S3. Publication occurs in this order:

1. Immutable RPMs under `Packages/`.
2. Content-addressed files under `repodata/`.
3. Immutable authenticated package-key archives.
4. Rotating package-key bundle and durable metadata signing public key.
5. `repodata/repomd.xml.asc`.
6. `repodata/repomd.xml` as the final metadata pointer.
7. A CloudFront invalidation limited to metadata and rotating public keys.

S3 cannot atomically replace `repomd.xml` and its detached signature. Publishing
the signature first makes the short update interval fail closed: a client may
temporarily reject mismatched metadata and retry, but it cannot accept unsigned
or partially published metadata.

The reusable workflow serializes publishers for a repository path. Production
publication should only be invoked by the central `OpenCHAMI/release` repository
so publishers in separate repositories cannot race.

## Inputs

| Input | Required | Default | Description |
|---|---:|---|---|
| `rpm-path` | Yes | | File or directory containing signed RPMs |
| `repository-path` | Yes | | Bucket prefix such as `stable/el9/x86_64` |
| `s3-bucket` | For publication | | Destination bucket |
| `cloudfront-distribution-id` | No | | Distribution to invalidate |
| `public-base-url` | No | | Public base URL such as `https://rpm.openchami.org` |
| `package-signing-keys-path` | Yes | | Directory containing paired `repo-cert.pub.asc` and `ephemeral.pub.asc` files |
| `package-master-public-key-asc` | Yes | | Trusted package-signing master public key |
| `package-master-fingerprint` | Yes | | Full trusted package-signing master fingerprint |
| `authorized-package-repo-fingerprints` | Yes | | Current repo-cert fingerprints allowed to certify new ephemeral keys |
| `package-key-bundle-filename` | No | `RPM-GPG-KEY-OpenCHAMI-Packages` | Rotating authenticated package-key bundle |
| `metadata-signing-key-armored-b64` | Yes | | Base64-encoded armored durable secret key |
| `metadata-signing-key-fingerprint` | Yes | | Full durable signing-key fingerprint |
| `metadata-signing-key-passphrase` | No | | Secret-key passphrase |
| `repository-key-filename` | No | `RPM-GPG-KEY-OpenCHAMI` | Public key filename |
| `require-signed-rpms` | No | `true` | Reject RPMs without package signatures |
| `dry-run` | No | `false` | Build and verify locally without AWS |

## Outputs

| Output | Description |
|---|---|
| `repository-directory` | Local complete repository directory |
| `repository-url` | Public URL, S3 URL, or dry-run file URL |
| `package-count` | Number of RPMs in the generated repository |
| `repomd-sha256` | SHA-256 digest of `repomd.xml` |
| `invalidation-id` | CloudFront invalidation ID when requested |

## Direct usage

The caller must configure short-lived AWS credentials before invoking the action.

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - uses: aws-actions/configure-aws-credentials@v6.2.3
    with:
      aws-region: us-east-1
      role-to-assume: ${{ vars.RPM_REPOSITORY_PUBLISHER_ROLE_ARN }}
      allowed-account-ids: ${{ vars.AWS_ACCOUNT_ID }}

  - uses: OpenCHAMI/github-actions/actions/publish-rpm-repository@v3.6
    with:
      rpm-path: dist/rpms
      repository-path: stable/el9/x86_64
      s3-bucket: ${{ vars.RPM_REPOSITORY_BUCKET }}
      cloudfront-distribution-id: ${{ vars.RPM_REPOSITORY_DISTRIBUTION_ID }}
      public-base-url: https://rpm.openchami.org
      package-signing-keys-path: dist/package-keys
      package-master-public-key-asc: ${{ secrets.MASTER_PUBLIC_ASC }}
      package-master-fingerprint: ${{ vars.MASTER_FPR }}
      authorized-package-repo-fingerprints: ${{ vars.PACKAGE_REPO_CERT_FINGERPRINTS }}
      metadata-signing-key-armored-b64: ${{ secrets.RPM_REPOSITORY_SIGNING_KEY_B64 }}
      metadata-signing-key-fingerprint: ${{ vars.RPM_REPOSITORY_SIGNING_KEY_FINGERPRINT }}
      metadata-signing-key-passphrase: ${{ secrets.RPM_REPOSITORY_SIGNING_KEY_PASSPHRASE }}
```

For production, prefer the repository's `publish-rpm-repository.yml` reusable
workflow, which supplies OIDC permissions, GitHub Environment protections, and
concurrency controls.

## Durable key handling

Store these secrets in the protected `rpm-publish` GitHub Environment of the
calling repository:

- `RPM_REPOSITORY_SIGNING_KEY_B64`
- `RPM_REPOSITORY_SIGNING_KEY_PASSPHRASE`
- `MASTER_PUBLIC_ASC`

Store the non-secret fingerprint and AWS identifiers as environment variables.
The action imports the durable secret key into an isolated temporary
`GNUPGHOME`, exports only its public key into the repository, and shreds the
temporary keyring at exit.

`PACKAGE_REPO_CERT_FINGERPRINTS` is a comma, whitespace, or newline-separated
allowlist maintained in the protected environment. Historical repo-cert keys
remain archived so old RPM signatures can be verified, but only keys in this
current allowlist may certify newly submitted ephemeral package keys. Remove a
retired or compromised repo-cert fingerprint before the next publication.

Clients should configure both `gpgcheck=1` for ephemeral package signatures and
`repo_gpgcheck=1` for the durable `repomd.xml` signature. The `.repo` file must
list both published keys:

```ini
gpgkey=https://rpm.openchami.org/stable/el9/x86_64/RPM-GPG-KEY-OpenCHAMI-Packages
        https://rpm.openchami.org/stable/el9/x86_64/RPM-GPG-KEY-OpenCHAMI
```

The package bundle contains only ephemeral public keys whose certification
chains were verified during publication. DNF imports those concrete keys rather
than being expected to discover the OpenPGP certification chain itself.

## License

MIT
