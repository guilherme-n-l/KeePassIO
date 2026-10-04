# KDBXKit (vendored fork)

KeePassIOS reads and writes KDBX files with [KDBXKit](https://github.com/shadone/KDBXKit) by Denis Dzyubenko, BSD 2-Clause (see `LICENSE` and `LICENSES/`). This directory is an in-tree fork: upstream sources plus the patches listed below, each meant to be sent upstream.

- Upstream commit: `e9b8839f1226b82665e1e4b7f12f13635d189deb` (2026-06-12, v1.3.0 + 41 commits)
- Included: `Sources/KDBXKit`, `Sources/CArgon2` (Argon2 reference implementation, CC0/Apache-2.0), `Sources/CZlib`, `Tests/KDBXKitTests`, licenses, README and changelog.
- Not included: the `kdbx` CLI, fuzz targets, docs tooling. `Package.swift` is ours, trimmed to the library and its tests.

Why a fork and not a dependency: see `docs/adr/0001-kdbx-library.md`.

## Local patches

Each patch is its own commit in this repository, touching only this directory; `git log -- Vendor/KDBXKit` lists them. The epoch and unknown-element fixes are also prepared for upstream (issues and a pull request to shadone/KDBXKit).

| Patch | Why |
|---|---|
| Test hygiene: find `keepassxc-cli` via `KEEPASSXC_CLI`/`PATH`; avoid a Swift 6.3 compiler crash in `StaticReaderAPITests`; discard two unused results | Interop tests only ran with the macOS app bundle; tests didn't compile with Swift 6.3.3; warnings |
| Epoch fix: the .NET epoch is the constant `-62_135_596_800` instead of a Foundation `DateComponents` date | Foundation's Gregorian calendar is Julian before 1582, so every KDBX 4 timestamp read or written was 2 days off from KeePass/KeePassXC |
| Public `KDBX.CustomDataItem.init(key:value:)` | Group and entry custom data couldn't be created outside the library |
| Public `KDBX.AutoType.Association.init(window:keystrokeSequence:)` | Auto-type associations couldn't be created outside the library |
| Preserve unknown XML elements (`KDBX.UnknownElement`, `unknownElements` on KDBX, Meta, Root, Group, Entry) and write them back | Elements written by other clients, plugins or newer format revisions were silently dropped on save. Limits: elements nested inside Times/AutoType/CustomData are still dropped; a `Protected="True"` value inside an unknown element is written back as its old ciphertext, which no longer decrypts after the inner-stream key changes on save |

## Updating

Re-copy the same paths from a newer upstream commit, re-apply the patches that upstream hasn't merged, run `swift test` here and the interop tests in `Packages/KeePassCore`, and update the commit and table above.
