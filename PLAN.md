# KeePassIOS — Product & Engineering Plan

A native SwiftUI KeePass client for iOS/iPadOS/macOS that matches KeePassium's feature set with **no paywall**, fast entry creation, first-class database merge, and built-in performance observability.

Status: planning only. The repo currently holds LICENSE and README.

## 1. Goals / non-goals

**Goals**
- Full KDBX 3.1 + 4.x read/write (KDBX 4.1 included); KDB (1.x) read-only import.
- Everything free: no subscription, no feature gating, no "premium" code paths. Sustain via donations/GitHub Sponsors.
- Quick create: a new entry in <3 taps / <5 s from anywhere in the system.
- Safe, deterministic, user-visible database merge (not just "conflicted copy").
- AutoFill (passwords, passkeys, TOTP) that is fast under the extension memory limit (~120 MB).
- Observability built in from day 1 (section 6).

**Non-goals (v1)**: own sync server, browser extension, Android, telemetry that leaves the device by default.

## 2. Reference-repo takeaways

| Repo | Borrow | Avoid |
|---|---|---|
| KeePassium (Swift, GPL-3) | Feature checklist, AutoFill UX, file-provider/Files integration, Argon2 memory handling in extensions. Read for behavior only; **license is GPL-3 — do not copy code** unless we license GPL-3 too. Decide license early (see §9). | Paywall tiers |
| KeePassXC (C++) | Reference merge logic (`Merger`), KDBX test vectors, TOTP/passkey handling, browser-integration ideas | — |
| KeePassDX (Kotlin) | Quick-add UX, templates, UI ideas | — |

Use all three as **test oracles**: generate databases with KeePassXC CLI (`keepassxc-cli`), open in our parser; write with ours, open in theirs. This runs in CI on Linux.

## 3. Architecture

Modular Swift Package, UI-free core so it builds and tests on **Linux** (fast CI, and enables the Linux profiling in §6).

```
KeePassIOS/
  Packages/
    KPCrypto/      (thin; mostly dependencies, see 9b) AES-256, ChaCha20, Salsa20, Twofish (legacy), SHA/HMAC, AES-KDF, Argon2d/2id (vendored C reference impl), key-file/composite-key derivation
    KPFormat/      KDBX3/4 reader+writer, HMAC block stream, gzip, XML (streaming, not DOM), inner-header protected values, KDB import
    KPModel/       Database, Group, Entry, History, DeletedObjects, CustomData, Attachments (binary pool, dedup), Templates
    KPMerge/       3-way/2-way merge engine, conflict model, dry-run diff
    KPSearch/      Indexed search (tokenized, in-memory, built after unlock), TOTP, password generator, breach check (k-anonymity HIBP, opt-in)
    KPStorage/     Storage abstraction: Files/iCloud Drive, local, WebDAV, SFTP(opt), Dropbox/OneDrive/GDrive (via Files providers first)
    KPKeychain/    Secure Enclave / Keychain wrapping of quick-unlock key, biometrics
    KPObservability/ signposts, metrics, tracing (see §6) — no dependency on the others except a tiny protocol
  Apps/
    iOS App (SwiftUI)          iPad split-view, macOS (Catalyst-free native SwiftUI later)
    AutoFillExtension          ASCredentialProviderViewController (passwords, passkeys, OTP)
    ShareExtension             quick create from Safari/any app
    WidgetsAndIntents          App Intents, Control Center control, Lock Screen widget, Action Button
  Tools/
    kpbench/       CLI that opens/merges/saves DBs and emits traces (Linux+macOS)
    kpfuzz/        parser fuzzers (libFuzzer via SwiftPM)
```

Key decisions
- **Swift 6 strict concurrency**; core is `Sendable` value-ish types, database held in an `actor`.
- **Secrets hygiene**: protected values stored as `SecureBytes` (mlock'd/zeroed on dealloc), decrypted lazily per field, never in `String` longer than needed; clipboard with expiry + `UIPasteboard` local-only/expiring flags; screenshot/app-switcher obscuring.
- **Crypto**: CryptoKit where available; on Linux use swift-crypto (same API). Argon2 via vendored C (BSD/CC0 reference), compiled with NEON; memory capped adaptively in extensions.
- **Streaming XML**: avoid building a full DOM for large DBs (memory in AutoFill). Target: 10k entries / 50 MB attachments unlock under budgets in §7.
- **Atomic saves**: write temp → fsync → coordinated replace via `NSFileCoordinator`; keep rolling local backups; detect external change before save (triggers merge, never silent overwrite).
- **UI**: SwiftUI + `@Observable`, `NavigationSplitView`, full Dynamic Type/VoiceOver, no UIKit except where AutoFill forces it.

## 4. Feature roadmap

**M0 – Foundations (wk 1–3)**: repo/CI, packages scaffolding, KDBX4 read (AES-KDF, Argon2, ChaCha20), test vectors from KeePassXC, `kpbench open`.
**M1 – Read-only app (wk 4–7)**: file picker/Files integration, composite key (password + key file + hardware-key challenge-response via YubiKey NFC/Lightning in M3), browse, search, TOTP, attachments view, biometric quick unlock.
**M2 – Write + quick create (wk 8–11)**: KDBX4 writer (round-trip fidelity incl. unknown XML preserved, custom data, history), edit/create/move/delete, recycle bin, password generator, templates, **quick create** (below).
**M3 – AutoFill + merge (wk 12–16)**: AutoFill extension (passwords, TOTP, passkeys), **DB merge** (below), KDBX3 write, YubiKey.
**M4 – Polish/beta (wk 17–20)**: iPad/macOS layouts, widgets, localization, accessibility audit, TestFlight.

### Quick create (differentiator)
- App Intent + Siri/Shortcuts/Action Button/Control Center: "New KeePass entry" opens a minimal sheet already focused on title; password pre-generated per saved profile.
- AutoFill **"Save password"** flow: when iOS offers to save a new credential, write it directly to the default DB (iOS 18+ credential provider save API) without opening the app.
- Share extension: share a URL/text → entry with title, URL, favicon prefilled.
- Entry **templates** (login, card, wifi, SSH key, note) and a "quick-add" default group per DB.
- Works while DB is locked: new entries are queued in an encrypted **inbox** (encrypted to a public key stored in Keychain; private key released on unlock) and merged in at next unlock. No plaintext on disk, no need for master password at capture time.

### Database merge (differentiator)
Based on KeePass semantics (UUID identity + `LastModificationTime` + `History` + `DeletedObjects` + `LocationChanged`), implemented in `KPMerge`:
- Pure function `merge(local, remote, base?) -> MergeResult { merged, report }`; **dry-run first**, user sees a diff UI (added / modified / moved / deleted / conflicting), per-item override.
- Entry conflicts: newer wins, loser pushed into `History` (never lost); if both changed same field since `base`, surface as conflict with field-level pick.
- Deletions honored via DeletedObjects only when not modified after deletion time; otherwise resurrect + report.
- Groups: move/rename/reorder, custom icons, custom data, attachments (content-hash dedup), settings (recycle bin, history limits).
- Automatic trigger: on external-change detection and when opening a file that has an iCloud/Dropbox "conflicted copy" sibling; manual "Merge with…" action for any other file.
- Property tests: merge is idempotent, commutative on content, and associative (for the non-conflict subset); cross-check against KeePassXC `Merger` on generated corpora.

### Everything else on the checklist
Passkeys, TOTP (RFC 6238, Steam), search w/ filters, tags, custom fields, attachments, entry history/restore, auto-lock/timeouts, offline-first, read-only mode, multiple DBs, app lock, emergency-kit export, CSV/1PIF import, **no ads, no analytics SDKs, no network by default**.

## 5. Security plan
- Threat model doc (`docs/threat-model.md`): stolen device, hostile extension memory pressure, malicious DB file (parser fuzzing), clipboard sniffing, sync-provider tampering.
- Fuzzing (libFuzzer) for KDBX header/XML/inner stream; corpus from real DBs; run nightly.
- Argon2 parameter bounds validated before allocation (reject DoS DBs; extension memory ceiling with a clear "open in app" fallback).
- Reproducible builds where feasible, SBOM, dependency pinning, external audit budget before 1.0.

## 6. Observability / profiling (the "eBPF-like" part)

Honest constraint: **eBPF does not exist on iOS/macOS** (no Linux kernel, and Apple blocks kernel instrumentation on devices). The Apple-native equivalents are DTrace-lineage tooling and Instruments. So we do a layered approach — same *goals* as eBPF (low-overhead, always-available, production-safe tracing with in-kernel-style aggregation), different mechanisms:

| Layer | Tool | What it gives us |
|---|---|---|
| **A. Static probes in our code (our "tracepoints")** | `os_signpost` / `OSSignposter` intervals & events in `KPObservability`, e.g. `kdf.argon2`, `kdbx.decrypt`, `xml.parse`, `index.build`, `merge.plan`, `merge.apply`, `save.fsync`, `autofill.unlock→first-result` | Near-zero-cost when not recording; shows up in Instruments (os_signpost, Points of Interest), `xctrace`, and CI traces |
| **B. Dynamic profiling** | Instruments: Time Profiler, Allocations, VM Tracker, File Activity, Hangs, Energy, **Swift Concurrency** instrument; `xctrace record` scripted in CI/nightly on a device farm or simulator | Sampling CPU, allocation call trees, leaked secrets-in-memory checks, extension memory peaks |
| **C. Production-safe field metrics (opt-in, local-first)** | **MetricKit** (`MXMetricPayload`, `MXDiagnosticPayload`: hangs, crashes, CPU/disk exceptions, launch time) + our own ring-buffer of signpost-derived histograms (unlock time, merge time, DB size buckets), viewable in an in-app **"Diagnostics"** screen and exportable as a file the user can attach to an issue. Never auto-uploaded. | The eBPF-style "always-on aggregated histograms", privacy-safe (no entry data, only sizes/timings) |
| **D. Regression gates** | `XCTMetric`s (`XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTStorageMetric`, `XCTOSSignpostMetric`) with committed baselines; `kpbench` outputs JSON; CI fails on >10% regression | Performance can't silently rot |
| **E. Linux deep-dive (real eBPF)** | Because `KP*` packages are UI-free, run `kpbench` on a Linux CI runner under **`perf`, `bpftrace`, `bcc`/`offcputime`, `strace -T`, `valgrind --tool=massif`, heaptrack** with USDT probes (`sdt.h` shim) mirroring the signpost names → flamegraphs, off-CPU time, page-fault/syscall profiles for KDF, crypto and parsing | Genuine eBPF-grade insight into algorithmic hot spots; results transfer because the code is shared. Apple-specific costs are then verified with layers A/B on real devices |
| **F. Tracing abstraction** | `KPObservability.Probe` protocol: one call site `Trace.span("kdbx.decrypt") { … }` fans out to `OSSignposter` on Apple, USDT/`swift-log` ring buffer on Linux, and no-op in release if disabled | Single instrumentation, multiple backends |

Also: `os.Logger` with privacy annotations (`.private` default; lint rule bans interpolating field values), `swift-metrics`-style counters/histograms in-process, and `kpbench --trace out.json` emitting Chrome-trace/Perfetto format so any run is viewable in ui.perfetto.dev.

## 7. Performance budgets (enforced in CI via D)

| Scenario (iPhone 12 class) | Budget |
|---|---|
| Argon2id default params (64 MiB, t=2..3) | ≤ 1 s (user-tunable target) |
| Unlock 5k-entry / 10 MB DB after KDF | ≤ 300 ms |
| AutoFill: tap → candidates shown (warm file, quick unlock) | ≤ 700 ms, peak RSS ≤ 80 MB |
| Search keystroke → results (10k entries) | ≤ 16 ms |
| Merge two 5k-entry DBs | ≤ 500 ms |
| Save (encrypt+write) 10 MB DB | ≤ 400 ms, atomic |
| Cold launch → file list | ≤ 400 ms |

## 8. Testing & CI
- **Linux CI (GitHub Actions)**: `swift test` for all `KP*` packages, KeePassXC interop corpus, property tests (merge), fuzz smoke run, `kpbench` perf + bpftrace/perf artifacts.
- **macOS CI**: build apps, XCUITest smoke flows, XCTMetric baselines on simulator (+ nightly on a physical device if available), `xctrace` trace artifacts.
- Golden-file KDBX corpora (KDBX3/4, all ciphers/KDFs, key files, history-heavy, attachment-heavy, corrupted).
- Snapshot tests for SwiftUI (light/dark, Dynamic Type XXL, iPad).

## 9. Decisions (resolved)
1. **License: MIT.** Clean-room only: KeePassium/KeePassDX/KeePassXC are GPL, so we read specs (KDBX format docs) and observe behavior, never copy their code. Third-party deps must be MIT/BSD/Apache/CC0 compatible (Argon2 reference impl is CC0/Apache).
2. **Minimum iOS: 18** (raised from 17 so KDBXKit, whose floor is iOS 18 / Swift 6.1, can be used without forking; also unlocks the AutoFill save-password and passkey provider APIs as baseline, not enhancements).
3. **Storage: local files only, via the Files app** (document picker, security-scoped bookmarks, `UIDocumentPickerViewController`/`fileImporter`, Files-provider locations work transparently). No cloud SDKs, no WebDAV/SFTP. `KPStorage` shrinks to a local-file + bookmark layer.
4. **Build env:** see Section 10.
5. **Name: KeePasIOS** (repo `keepassios`). Bundle ID TBD.

## 9b. Build vs. buy: handroll only when necessary
Rule: use a maintained MIT/BSD/Apache/CC0 dependency unless it fails a hard requirement (license, security, extension memory, iOS 18, correctness). Every handrolled component needs a one-line justification in this table.

| Need | Use (don't handroll) | Handroll? |
|---|---|---|
| AES, ChaCha20, SHA, HMAC, HKDF | CryptoKit / [swift-crypto](https://github.com/apple/swift-crypto) | No |
| Argon2 | Vendored reference C impl (CC0/Apache) first, Rust `argon2` crate if profiling demands (section 9c), or [Argon2Kit](https://github.com/dnrops/Argon2Kit)-style wrapper | No (wrapper only) |
| Twofish / Salsa20 (legacy) | Small vetted C impl, only if needed for old DBs | Defer; skip until a user needs it |
| gzip | zlib (system) / `Compression` framework | No |
| KDBX 3.1/4.x parse+write, SecureBytes | **[KDBXKit](https://github.com/shadone/KDBXKit)** (BSD-2, KeePassXC-tested, streaming attachments, mlock'd secrets) as the base | Evaluate first (spike below); fork if gaps |
| KDBX parser alt. | KeePassKit is GPL-3 (incompatible with MIT) | No |
| XML | Foundation `XMLParser` (SAX) | No |
| Logging / metrics / CLI | swift-log, swift-metrics, swift-argument-parser | No |
| Tracing | `OSSignposter` (Apple) + thin `Trace.span` wrapper | Thin wrapper only |
| Biometrics, Keychain, Secure Enclave | LocalAuthentication / Security / CryptoKit | No |
| Passkeys, AutoFill, TOTP codes | AuthenticationServices; TOTP via CryptoKit HMAC (~30 lines) | Tiny TOTP only |
| Files access | `fileImporter` / `UIDocumentPickerViewController`, bookmarks, `NSFileCoordinator` | No |
| Fuzzing / property tests | SwiftPM libFuzzer, swift-testing, [SwiftCheck](https://github.com/typelift/SwiftCheck) | No |
| **Merge engine** | Nothing usable exists (KDBXKit lists no merge/history) | **Yes, core differentiator** |
| **Encrypted quick-create inbox** | CryptoKit primitives (HPKE / Curve25519) | Protocol glue only |
| **Diff/merge UI, quick-create flows, diagnostics screen** | SwiftUI | Yes (product code) |

**KDBXKit spike (first task):** with the min iOS now 18, its deployment floor no longer blocks us. It is still single-maintainer with very low adoption and has no merge or history API. The spike checks: KDBX3 write need, round-trip fidelity of unknown XML/custom data/history, extension memory use, and API access needed for merge. Outcomes: (a) depend on it as-is (expected), (b) fork under BSD-2 with attribution and upstream patches, (c) as a last resort handroll only the reader/writer on top of CryptoKit + vendored Argon2.

## 9c. Lower-level languages (only when measured)
- Default is Swift. Drop to a lower-level language only when a profile (section 6, budgets in section 7) shows a Swift hot path missing its budget after normal optimization, and the gain justifies the FFI and build cost.
- **Preference order: Rust over C over assembly.** C only for an existing vetted dependency we don't rewrite (e.g. the Argon2 reference impl) or when Rust genuinely can't do it. Assembly/intrinsics: last resort, only inside an already-chosen Rust/C library, never handwritten by us.
- Rust candidates, in order of likelihood: Argon2 (the RustCrypto `argon2` crate, replacing the vendored C), streaming XML/KDBX parse, search indexing, merge diff of very large DBs. Rejected unless profiling says otherwise: everything else.
- Integration: Rust crate built as a static lib for `aarch64-apple-ios`, simulator and macOS (XCFramework via `cargo` + a build script or SwiftPM binary target), C ABI via `cbindgen`/UniFFI, `#![forbid(unsafe_code)]` where possible, secrets zeroized (`zeroize`), and a Swift reference implementation kept beside it as a correctness oracle plus a differential/fuzz test. Rust crates must be MIT/Apache; `cargo-deny` and `cargo-audit` in CI.
- Each use needs a benchmark showing the win (via `kpbench` and XCTMetric baselines) recorded in the PR; if the gain is under about 20%, keep Swift.
- Observability applies equally: Rust spans emit through the same `Trace.span` backends (signpost on Apple, USDT on Linux), so the profile stays end to end.

## 10. Immediate next steps
1. Confirm §9 decisions.
2. Scaffold `Package.swift` workspace with `KPCrypto`, `KPFormat`, `KPModel`, `KPObservability`, and CI for Linux.
3. Implement KDBX4 reader against KeePassXC-generated vectors, with signposts + `kpbench` from the first commit.
4. Then writer → merge → app shell.
