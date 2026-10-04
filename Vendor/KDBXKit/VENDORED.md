# KDBXKit (vendored fork)

KeePassIOS reads and writes KDBX files with [KDBXKit](https://github.com/shadone/KDBXKit) by Denis Dzyubenko, BSD 2-Clause (see `LICENSE` and `LICENSES/`). This directory is an in-tree fork: upstream sources plus the patches listed below, each meant to be sent upstream.

- Upstream commit: `e9b8839f1226b82665e1e4b7f12f13635d189deb` (2026-06-12, v1.3.0 + 41 commits)
- Included: `Sources/KDBXKit`, `Sources/CArgon2` (Argon2 reference implementation, CC0/Apache-2.0), `Sources/CZlib`, `Tests/KDBXKitTests`, licenses, README and changelog.
- Not included: the `kdbx` CLI, fuzz targets, docs tooling. `Package.swift` is ours, trimmed to the library and its tests.

Why a fork and not a dependency: see `docs/adr/0001-kdbx-library.md`.

## Local patches

Each patch is its own commit in this repository, touching only this directory; `git log -- Vendor/KDBXKit` lists them.

| Patch | Why |
|---|---|
| _(none yet)_ | |

## Updating

Re-copy the same paths from a newer upstream commit, re-apply the patches that upstream hasn't merged, run `swift test` here and the interop tests in `Packages/KeePassCore`, and update the commit and table above.
