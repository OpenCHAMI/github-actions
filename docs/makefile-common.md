<!--
SPDX-FileCopyrightText: 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Makefile.common

Shared Makefile targets for OpenCHAMI repositories. Copy [`Makefile.common`](../Makefile.common) from the latest release to your repo root, don't edit it, and include it from your `Makefile`:

```make
BINARIES := foo-server:./cmd/server   # overrides go before the include
include Makefile.common

migrate:                              # repo-only targets go below
	./scripts/migrate.sh
```

- `make help` lists every target, including your own (give them a `## description`).
- Covers Go (build, test, lint, vuln), Fabrica codegen, containers, GoReleaser packages, and REUSE.
- `lint-ci` runs actionlint and zizmor from containers (`ACTIONLINT_IMAGE`, `ZIZMOR_IMAGE`) with podman or docker; nothing is installed. Passes `GH_TOKEN` through for zizmor's online audits. Not part of `all`.
- `all`, `deps`, `build`, `run`, `install`, and `uninstall` are double-colon rules: add your own `deps::` (etc.) and both recipes run.
- `install` / `uninstall` put already-built `BINARIES` (`make build` first) in `$(DESTDIR)$(bindir)` (default `/usr/local/bin`; override `prefix`, `bindir`, `DESTDIR`).
- Pass extra arguments with `ARGS` (`make test ARGS="-run TestFoo"`).
- Targets that don't apply skip: Go targets without `go.mod`, `generate` without Fabrica, container targets without a `Containerfile` or `Dockerfile`. `release-snapshot` and `build-packages` fail without a GoReleaser config.
- Tools beyond coreutils and POSIX utilities are checked before use; the file installs nothing.
- GNU make 3.81 or newer (macOS's `/usr/bin/make` works).

Common overrides: `BINARIES` (default: one `name:./cmd/name` per `cmd/` directory), `CONTAINERFILE`, `CONTAINER_IMAGE_FQCN`, `TEST_TIMEOUT`, `CLEANFILES` (append with `+=`), `GO_LDFLAGS` (append with `+=`; default sets `$(GO_MODULE)/internal/version.*` build info), `GO_VERSION_PACKAGE`. See the variables section at the top of the file for the rest.

Release binaries get their build info from GoReleaser, not `make build`. Set the same `internal/version` variables in your GoReleaser config so both match:

```yaml
builds:
  - ldflags:
      - -X {{ .ModulePath }}/internal/version.Version={{ .Version }}
      - -X {{ .ModulePath }}/internal/version.Tag={{ .Tag }}
      - -X {{ .ModulePath }}/internal/version.Branch={{ .Branch }}
      - -X {{ .ModulePath }}/internal/version.Commit={{ .FullCommit }}
      - -X {{ .ModulePath }}/internal/version.Date={{ .Date }}
      - -X {{ .ModulePath }}/internal/version.GoVersion={{ envOrDefault "GO_VERSION" "unknown" }}
      - -X {{ .ModulePath }}/internal/version.GitState={{ envOrDefault "GIT_STATE" "unknown" }}
      - -X {{ .ModulePath }}/internal/version.BuildHost={{ envOrDefault "BUILD_HOST" "unknown" }}
      - -X {{ .ModulePath }}/internal/version.BuildUser={{ envOrDefault "BUILD_USER" "unknown" }}
```

`build-release-goreleaser` and `Makefile.common` export `GO_VERSION`, `GIT_STATE`, `BUILD_HOST`, and `BUILD_USER`.

Add [`lint-makefile-common`](workflows.md#lint-makefile-common) to catch drift.
