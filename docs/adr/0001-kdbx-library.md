# ADR 0001: Read and write KDBX with a patched fork of KDBXKit

- Status: accepted
- Date: 2026-10-04

## Context

KeePassIO needs to read and write KDBX 4.x, be MIT-licensed, target iOS 18, and avoid handwritten code where a maintained library exists (PLAN.md section 9b). [KeePassKit](https://github.com/MacPass/KeePassKit) is GPL-3 and can't be used. [KDBXKit](https://github.com/shadone/KDBXKit) (BSD 2-Clause, Swift, iOS 18 / macOS 15 / Linux) was evaluated on Linux with Swift 6.3.3 against KeePassXC 2.7.6 and pykeepass 4.2.0.

## Findings

What it gets right:

- KDBX 4.0/4.1 envelope, HMAC block stream, AES-256 and ChaCha20, Argon2d/Argon2id and AES-KDF, inner-stream ciphers, all key-file formats.
- Interop: databases written by KeePassXC (Argon2id + AES, Argon2d + ChaCha20, AES-KDF, password + key file) open correctly, including custom fields, TOTP, history and attachments. After editing and saving with KDBXKit, KeePassXC reads the new values, history and TOTP.
- Safety: bounds-checked parsing, typed errors, KDF limits enforced before the KDF runs (crafted 4 GiB and 1 TiB Argon2 headers rejected in 10 ms), a 256 MiB decompression cap, constant-time comparisons, secrets in `mlock`ed memory zeroed on release.
- Swift 6 strict concurrency clean; every public model type is a `Sendable` value type exposing UUIDs, all timestamps, history, deleted objects and previous parent groups, which is everything our merge needs.
- 473 tests; all 14 KeePassXC interop tests pass once pointed at the Linux `keepassxc-cli`.

What's wrong:

1. **Every timestamp is off by 2 days.** The .NET epoch (0001-01-01) is built with Foundation's Gregorian calendar, which switches to Julian before 1582. Dates from other clients read 2 days early, dates it writes show 2 days in the future in KeePassXC. Plain round trips hide it, so the test suite doesn't catch it. Fatal for merging and expiry.
2. **XML over about 10 MB fails on Linux** (roughly 4-5k entries with history), even for files it wrote itself: it parses the whole document with Foundation's `XMLParser`, which on Linux refuses larger documents. Whether Apple's parser has the same limit is untested. Peak memory is about 13-15x the XML size.
3. Unknown XML elements are dropped on save (reported in `parserWarnings`).
4. `CustomDataItem` has no public initializer.
5. No cancellation or progress during key derivation; AES-KDF is about 7x slower than KeePassXC.
6. One maintainer, one star, no commits since June 2026.

## Decision

Use KDBXKit as an **in-tree fork** in `Vendor/KDBXKit`, pinned to upstream `e9b8839`, with our patches as separate commits (listed in `Vendor/KDBXKit/VENDORED.md`) and offered upstream. Writing our own reader/writer would cost an estimated 10-14k lines to reach the same level; the patches are small and contained.

Patches, in priority order:

1. Fix the epoch (`Date(timeIntervalSince1970: -62_135_596_800)`) with a test that decodes a known KeePassXC timestamp.
2. Public initializer for `CustomDataItem`.
3. Keep unknown XML elements and write them back.
4. Stream XML parsing into the model instead of building a DOM, after checking Apple's `XMLParser` limit on a device.
5. KDF cancellation/progress and a faster AES-KDF loop, if profiling on device justifies it.
6. Test hygiene: find `keepassxc-cli` via `PATH`, work around the Swift 6.3 compiler crash in one test, silence two unused-result warnings.

App policy on top of the library:

- Reject KDBX 3.x (check `parseHeader(...).formatVersion.isLegacy3x` before decrypting) with the conversion message.
- Pass tighter `KDFParameterLimits`, especially in the AutoFill extension.
- Map KDBXKit's model to `KPModel` in a separate `KPKDBX` module, so merge, search and the UI never depend on the library's types and the library stays replaceable.

## Consequences

- We own keeping the fork current; `VENDORED.md` documents the update procedure.
- Until patch 4 lands, Linux tests stay below about 3,500 entries; large-database performance is measured on Apple platforms.
- The BSD-2 notice must appear in the app's acknowledgements (added to `THIRD_PARTY_NOTICES.md`).
