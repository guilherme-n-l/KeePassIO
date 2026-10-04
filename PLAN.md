# KeePassIOS: Product & Engineering Plan

A native SwiftUI KeePass client for iPhone and iPad (iOS/iPadOS only) that matches KeePassium's feature set with **no paywall**, fast entry creation, first-class database merge, and built-in performance observability.

**Status:** planning. `main` holds the Xcode template project (`keepassios.xcodeproj`, SwiftData sample code). No product code yet.

---

## 1. Goals and non-goals

### Goals

- Read and write **KDBX 4.0/4.1 only**. Older formats (KDBX 3.1, KDB 1.x, Twofish cipher) are not supported: opening one shows a clear message explaining how to convert it with KeePassXC (Database Settings → Security → Encryption → Database format: KDBX 4, and pick AES-256 or ChaCha20 instead of Twofish).
- Everything free: no subscription, no feature gating, no "premium" code paths. Funding by donations or GitHub Sponsors only.
- **Quick create:** a new entry in under 3 taps and 5 seconds, from anywhere in the system. Creating an entry always requires unlocking (biometric quick unlock keeps that to one Face ID glance); nothing is ever written to a vault without an unlock.
- **Merge:** safe, deterministic and visible to the user, never just "conflicted copy".
- **AutoFill** for passwords, passkeys and TOTP codes, fast and within the extension memory limit (about 120 MB).
- **Observability** built in from the first commit (section 6).
- **Privacy:** no network access by default, no analytics SDKs, App Store privacy label "Data Not Collected".

### Non-goals for v1

- Cloud storage SDKs, WebDAV or SFTP. Files are local, opened through the Files app (section 9).
- A sync server, browser extension, Android, macOS or Apple Watch app.
- KDBX 3.1, KDB (KeePass 1.x) and Twofish databases, in any version (not deferred: out of scope).
- Any operation on vault contents without unlocking first, including a locked-state quick-create inbox.

## 2. Reference repos (behavior only, no code)

All three are GPL. We are MIT, so we read them for behavior and UX and never copy code (section 9).

| Repo | What to learn from it | What to avoid |
|---|---|---|
| [KeePassium](https://github.com/keepassium/keepassium) (Swift) | Feature checklist, AutoFill UX, how it caches Files-provider files for the AutoFill extension, Argon2 memory limits in extensions | Paywall tiers |
| [KeePassXC](https://github.com/keepassxreboot/keepassxc) (C++) | Merge semantics (its `Merger` behaviour), TOTP/passkey storage conventions, KDBX edge cases | n/a |
| [KeePassDX](https://github.com/Kunzisoft/KeePassDX) (Kotlin) | Quick-add flows, entry templates, UI ideas | n/a |

**Interop oracle:** CI generates databases with `keepassxc-cli` and opens them with our code, then writes with ours and opens with `keepassxc-cli`. Using its binary as a test tool is not copying its code.

## 3. Architecture

UI-free core packages build and test on **Linux** (fast CI, and real eBPF profiling, section 6). Apple-only code lives in the app and extension targets.

```text
keepassios/                         (repo root)
  keepassios.xcodeproj              existing project; targets below are added to it
  Packages/KeePassCore/              one SwiftPM package, several targets:
    KPModel        thin domain layer over KDBXKit: Database, Group, Entry, History, DeletedObjects, Templates, Tags
    KPMerge        merge engine, conflict model, dry-run diff        (handrolled: nothing exists)
    KPSearch       in-memory index built after unlock, filters, password audit (weak/reused, local only)
    KPOTP          TOTP/Steam codes, otpauth:// parsing             (~100 lines on CryptoKit HMAC)
    KPGenerator    password and passphrase generator (wordlist: EFF, CC-BY)
    KPObservability  Trace.span, metrics, probe backends (section 6)
  Packages/KeePassApple/             Apple-only package
    KPAppState     Codable JSON store for non-secret app state in the App Group (replaces SwiftData)
    KPFiles        security-scoped bookmarks, NSFileCoordinator, atomic save, local backups, App Group cache
    KPKeychain     biometric quick unlock (Secure Enclave-wrapped key), Keychain access groups
    KPDiagnostics  MetricKit subscriber, on-device histogram store, export
  App targets (in the Xcode project):
    keepassios                  SwiftUI app (iPhone, iPad)
    AutoFill                    ASCredentialProviderViewController: passwords, passkeys, OTP codes, saving credentials
    QuickCreateShare            share extension: URL/text into a new entry
    Widgets                     App Intents, Control Center control, Lock Screen widget, Action Button
  Tools/
    kpbench        CLI (swift-argument-parser): open/search/merge/save a DB, emit Perfetto traces (Linux + macOS)
    kpfuzz         libFuzzer harnesses for KDBX input and merge
    bpf/           bpftrace scripts for the Linux profiling layer (section 6)
  .github/workflows/  linux.yml, macos.yml, nightly.yml
```

Dependencies (all MIT/BSD/Apache/CC0, pinned by exact version):
[KDBXKit](https://github.com/shadone/KDBXKit) (format, crypto, SecureBytes), swift-crypto, swift-log, swift-metrics, swift-argument-parser, swift-testing, [YubiKit](https://github.com/Yubico/yubikit-ios) (Apache-2, for hardware keys).

### Key design decisions

- **Swift 6 language mode, strict concurrency.** An open database lives in a `DatabaseSession` actor. Views get `@Observable` snapshots and never touch secrets directly.
- **No SwiftData (or Core Data) anywhere.** The `.kdbx` file *is* the database: KDBXKit loads it into memory, `DatabaseSession` edits it, and saves rewrite it atomically. A second persistent store would duplicate that and risk writing secrets into unencrypted SQLite.
  - Views bind to `@Observable` snapshots of the open database, not `@Query`.
  - Non-secret app state (recent files, bookmarks, per-database settings, pending-sync flags, diagnostics histograms) is a few KB. It lives in `KPAppState`: `Codable` structs saved as JSON files in the App Group container, written atomically, with a schema version field for migrations. Extensions read the same files.
  - Nothing secret is ever written outside an encrypted KDBX file.
  - Revisit only if profiling shows we need a large persistent search index; even then the index would have to be encrypted.
- **Secrets hygiene:**
  - Protected fields stay in KDBXKit's `SecureBytes` (locked in memory, zeroed on release) and are decrypted only when shown or copied.
  - Clipboard copies are local-only (no Universal Clipboard) and expire.
  - The UI is obscured in the app switcher and blurred during screen recording.
  - The app auto-locks on timeout or backgrounding, and locks on memory warnings in extensions.
- **Files:**
  - The user picks a `.kdbx` with `fileImporter`, and the app keeps a security-scoped bookmark.
  - All reads and writes go through `NSFileCoordinator`.
  - Saves are atomic: write a temp file, fsync, then do a coordinated replace.
  - Before every save the app checks the file's modification date and size. If someone else changed it, it opens the merge flow instead of overwriting.
  - The app keeps rolling local backups (last N saves, encrypted, since they are just KDBX copies).
  - **AutoFill access:** extensions can't reliably resolve bookmarks to third-party File Provider locations, so the app keeps a read-only cached copy of each database in the App Group container. It is refreshed on every app open and save.
  - **Writes from extensions** (AutoFill save-credential, share extension, App Intents running in the background): after unlock, the extension first tries a coordinated write to the original file through its bookmark. If the original isn't reachable from the extension, it saves to the App Group working copy (still a full encrypted KDBX) and sets a pending-sync flag. The next time the app opens that database it merges the working copy into the original with `KPMerge` and clears the flag. The new entry is usable in AutoFill immediately, from the working copy.
- **UI:** SwiftUI with `NavigationSplitView`, built with the current SDK (iOS 26 design language) but deploying to iOS 18. Full Dynamic Type, VoiceOver and keyboard support on iPad. UIKit only where AutoFill requires it.

## 4. Features

### 4.1 Quick create (differentiator)

- **Entry points:**
  - App Intent "New KeePass entry", available through Siri, Shortcuts, the Action Button, a Control Center control and a Lock Screen widget.
  - The share extension (from Safari or any app; prefills title and URL).
  - AutoFill's save-credential flow, which iOS 18+ offers to credential providers.
- **Minimal sheet:** title focused, password pre-generated from the default profile, username remembered per domain, template picker (login, card, Wi-Fi, SSH key, secure note), "Advanced" collapsed.
- **Unlock is always required (no zero-unlock operations):**
  - Every entry point unlocks the database before the sheet can be saved. With biometric quick unlock on, that's one Face ID/Touch ID check, done in parallel with showing the sheet so it costs no extra time.
  - Without quick unlock (or after it expires), the sheet asks for the master password/key file. In extensions, an Argon2 setting too heavy for the memory limit shows "Open in app" (section 10) and hands the draft to the app.
  - Drafts typed before unlock are held in memory only and discarded if unlock is cancelled; nothing is written to disk before unlock.
  - Saving follows the extension write path in section 3 (direct write, else working copy + pending sync).
- **Target group:** a "Quick add" group per database, configurable.

### 4.2 Database merge (differentiator)

Built on KeePass semantics: UUID identity, `LastModificationTime`, `History`, `DeletedObjects`, `LocationChanged`.

- **Pure function:** `merge(local, remote, base?) -> MergePlan`, then `apply(plan)`.
  - `base` is the last version this device saved, kept in local backups, so we get a real three-way merge most of the time.
  - Without a base, it falls back to a two-way merge by timestamps, the same way KeePassXC does.
- **Dry run first.** A review screen lists added, modified, moved, deleted and conflicting items. The user can override per item and see a field-level diff.
- **Entries:** newest wins and the loser goes into `History`, so nothing is ever lost. When both sides changed the same field since `base`, it's a conflict and the user picks per field.
- **Deletions:** honored only if the item wasn't modified after its deletion time. Otherwise the item is restored and flagged in the report.
- **Groups and other data:** moves, renames, ordering, icons, custom data, attachments (deduplicated by content hash), and database settings (recycle bin, history limits) are all merged.
- **Triggers:**
  - A file changed externally when saving.
  - A Files-provider "conflicted copy" sibling found next to the database.
  - A pending-sync working copy written by an extension (section 3).
  - "Merge with…" on any file.
- **Tests:**
  - Property-based: idempotent, the same content regardless of order, and nothing lost (every input entry version exists in the output or its history).
  - Golden cases cross-checked against `keepassxc-cli merge` output.
  - A fuzzed merge harness.

### 4.3 Core feature checklist (all free)

- **Unlocking:**
  - Password, key file, YubiKey challenge-response (NFC and USB-C via YubiKit), or any combination.
  - Biometric quick unlock with a configurable expiry.
- **Browsing:** groups, tags, search with filters, entry history and restore, recycle bin, custom fields, attachments (preview with Quick Look), custom icons.
- **OTP and passkeys:** TOTP (RFC 6238, Steam) with otpauth:// QR scan, and passkeys stored in KeePassXC-compatible fields.
- **Security tools:** password generator (character sets, passphrases), and a password audit that flags weak, reused and old passwords, entirely on device.
- **Databases:** multiple databases, read-only mode, a lock screen for the app itself, auto-lock and clipboard timeouts.
- **Import and export:** CSV import (generic, Bitwarden, 1Password, Chrome); export to KDBX, and to CSV behind an unlock plus an "unencrypted file" warning. Diagnostics export (section 6) is a separate, secret-free file.
- **Network (off by default, opt-in):** favicon download and a breached-password check via the Have I Been Pwned k-anonymity API. A global "never use network" switch defaults to on. Both confirmed (decision 10).

## 5. Roadmap

Each milestone ends with a TestFlight build (from M1) plus green CI and passing performance gates.

| Milestone | Weeks | Scope | Done when |
|---|---|---|---|
| **M0 Foundations** | 1–2 | Clean up template project (iOS 18, Swift 6, no SwiftData), add packages, CI (Linux + macOS), `Trace.span`, `kpbench open`, **KDBXKit spike**, KeePassXC interop corpus | Spike verdict written; `kpbench open` traced on Linux under bpftrace and on macOS in Instruments |
| **M1 Read-only app** | 3–6 | File picker + bookmarks, unlock (password + key file), browse, search, TOTP, attachments, biometric quick unlock, auto-lock | Opens every corpus database; meets the unlock and search budgets |
| **M2 Editing + quick create** | 7–10 | Create/edit/move/delete, history, recycle bin, generator, templates, atomic save + backups, external-change detection, App Intents, share extension, extension write path + pending sync | Edit, save and re-open round-trips losslessly in KeePassXC |
| **M3 AutoFill + merge** | 11–15 | AutoFill (passwords, OTP, passkeys, save credential), App Group cache, `KPMerge` + review UI, YubiKey | Property tests green; AutoFill within memory and latency budgets |
| **M4 Polish + beta** | 16–19 | iPad layout and keyboard shortcuts, widgets, password audit, CSV import, localization infrastructure check (pseudo-locale pass; English only), accessibility audit, threat model review | Public TestFlight |
| **M5 1.0** | 20+ | App Store release, external security review | Shipped |

## 6. Observability and profiling (the "eBPF-like" part)

**Constraint:** eBPF doesn't exist on iOS or macOS. There's no Linux kernel, and Apple doesn't allow kernel instrumentation on devices. So the plan reaches eBPF's goals (low-overhead, always-available tracing with aggregation) through layers:

| Layer | Mechanism | Gives us |
|---|---|---|
| **A. Static probes ("tracepoints")** | `OSSignposter` intervals and events behind `Trace.span(.kdbxDecrypt) { … }` | Near-zero cost when not recording; visible in Instruments, `xctrace` and CI |
| **B. Sampling and allocation profiling** | Instruments: Time Profiler, Allocations, VM Tracker, Hangs, File Activity, Swift Concurrency; `xctrace record` scripted in macOS CI | CPU flame graphs, allocation call trees, extension memory peaks |
| **C. Always-on field metrics (local, never uploaded)** | MetricKit payloads (hangs, crashes, launch, CPU/disk exceptions) + our own fixed-bucket histograms fed by the same spans, stored on device | eBPF-style aggregated histograms; shown on a Diagnostics screen; the user can export it as a file (share sheet) to attach to an issue. The app never uploads anything itself |
| **D. Regression gates** | `XCTMetric` (clock, CPU, memory, storage, signpost) with committed baselines; `kpbench --json` | CI fails on a regression over 10% versus baseline |
| **E. Real eBPF on Linux** | Core packages run on Linux under `bpftrace`, `perf`, `offcputime`, heaptrack | Flame graphs, off-CPU time, syscall and page-fault profiles for KDF, crypto, parse, merge |
| **F. One instrumentation API** | `KPObservability` routes each span to the platform's backend | One call site, every tool |

### 6.1 How the Linux eBPF probes work (no C needed)

- On Linux, each `Trace.span` begin and end calls one of two tiny exported functions, `kp_probe_begin(id, arg)` and `kp_probe_end(id, arg)`. They are pure Swift, `@_cdecl`, and `@inline(never)`.
- bpftrace attaches **uprobes** to those stable symbols. The span ID is a small integer from a generated enum, so the mapping is stable and readable.
- `Tools/bpf/` ships ready scripts:
  - `spans.bt`: latency histograms per span.
  - `kdf.bt`: Argon2 time and RSS growth.
  - `alloc.bt`: malloc/free counts inside a span.
  - `io.bt`: syscalls during save, including fsync latency.
  - `offcpu.bt`: blocking inside the merge and save paths.
- The nightly CI job runs `kpbench` over the corpus under each script and uploads histograms and flame graphs as artifacts.
- If uprobes on Swift symbols prove unreliable, fall back to USDT via the Rust `usdt` crate, following the Rust-over-C policy in 9c.

### 6.2 Span catalog (initial)

- **Unlock:** `unlock.total`, `kdf.argon2`, `kdf.aes`, `kdbx.header`, `kdbx.decrypt`, `kdbx.inflate`, `kdbx.xml`
- **Search:** `index.build`, `search.query`
- **Merge:** `merge.plan`, `merge.apply`
- **Save:** `save.serialize`, `save.encrypt`, `save.fsync`, `save.replace`
- **Quick create:** `quick.sheetShown`, `quick.unlock`, `quick.save`, `sync.pendingMerge`
- **AutoFill:** `autofill.launch`, `autofill.unlock`, `autofill.firstResult`
- **App:** `app.launch`, `ui.firstFrame`

### 6.3 Privacy rules for telemetry

- Spans carry only sizes, counts and durations, never titles, URLs, usernames or field contents.
- `os.Logger` interpolations default to `.private`. A CI lint (SwiftLint custom rule) fails the build if entry fields are logged.
- `kpbench --trace out.json` writes Perfetto/Chrome trace format, viewable at ui.perfetto.dev.

## 7. Performance budgets (gated in CI via layer D)

| Scenario (iPhone 12 class device) | Budget |
|---|---|
| Argon2id default params (64 MiB, 2–3 iterations) | ≤ 1 s (user-tunable target) |
| Unlock 5k entries / 10 MB DB, excluding KDF | ≤ 300 ms |
| AutoFill: open → candidates shown (quick unlock, cached DB) | ≤ 700 ms, peak memory ≤ 80 MB |
| Search keystroke → results (10k entries) | ≤ 16 ms |
| Merge two 5k-entry databases (plan + apply) | ≤ 500 ms |
| Save 10 MB database (encrypt + atomic write) | ≤ 400 ms |
| Quick-create sheet visible from App Intent | ≤ 500 ms |
| Quick create: biometric unlock done → entry saved (5k-entry DB) | ≤ 600 ms |
| Cold launch → file list | ≤ 400 ms |

Linux CI enforces the core-only rows (KDF, parse, search, merge, serialize) through `kpbench` baselines. macOS CI enforces the rest on the simulator, and an optional nightly job runs on a real device.

## 8. Testing and CI

- **Unit and property tests:** swift-testing for all core targets. Property tests for merge, the generator and OTP. RFC test vectors for TOTP.
- **Interop corpus:** KDBX 4.0/4.1 files covering each supported cipher (AES-256, ChaCha20) and KDF (AES-KDF, Argon2d, Argon2id), plus KDBX 3.1/KDB/Twofish files to check they are rejected with the right message, key files, history-heavy and attachment-heavy files, 10k+ entries, and corrupted or truncated files. Generated by script with `keepassxc-cli`, not hand-committed binaries.
- **Fuzzing:** libFuzzer on Linux for KDBX input and merge. Short runs on each PR, 1 hour nightly.
- **UI tests:** XCUITest smoke flows (open, unlock, search, copy, create, save, merge review), plus snapshot tests across light/dark, the largest Dynamic Type size and iPad.
- **GitHub Actions:**
  - `linux.yml` on each PR: build, test, a short fuzz run, `kpbench` gates.
  - `macos.yml` on each PR: Xcode build of all targets, unit and UI tests, `XCTMetric` gates.
  - `nightly.yml`: long fuzz run, bpftrace profiling artifacts, `xctrace` traces, `cargo-deny` once Rust exists.
  - The repo is public, so standard GitHub-hosted runners (Linux and macOS) are free: both `linux.yml` and `macos.yml` run on every PR and push to `main`.
  - **Public-repo safety:** CI never signs or needs secrets. App builds use the simulator with `CODE_SIGNING_ALLOWED=NO`, so PRs from forks run the full suite safely. Workflows use `pull_request` (never `pull_request_target`), least-privilege `permissions: contents: read`, and actions pinned by commit SHA. TestFlight uploads are done from the owner's Mac (Xcode Organizer) until a protected release workflow is worth adding.
- **Static checks:** SwiftLint, swift-format, dependency license check.

## 9. Decisions (resolved)

1. **License: MIT.** The work is clean-room. We read specs and observe the GPL apps' behaviour, never copy their code. Dependencies must be MIT/BSD/Apache/CC0.
2. **Minimum iOS: 18.** This lets us use KDBXKit without forking, and the AutoFill save-credential and passkey APIs become baseline.
3. **Storage: local files through the Files app only.**
   - Files are opened with the system picker and kept with bookmarks.
   - Whatever location the user picks in Files, including another app's File Provider, works transparently.
   - We ship no cloud SDKs.
4. **Name: KeePassIOS** (display name), repo `keepassios`. Bundle ID `dev.guilhermenl.keepassios` (from the existing project); App Group `group.dev.guilhermenl.keepassios`; extensions use `dev.guilhermenl.keepassios.<Extension>`. Paid Apple Developer account available; the team ID is set in Xcode by the owner, never committed in plain text beyond the project's `DEVELOPMENT_TEAM`.
   - App Store review sometimes rejects names that lean on another product's name; "KeePass" is used by KeePassium, KeePassXC and KeePassDX, so risk is low, but have a fallback name ready before submission.
5. **Build environment:**
   - Xcode on the owner's Mac is the primary build and the place for device profiling (Instruments).
   - GitHub Actions runs Linux CI for the core packages and macOS CI for the apps. The repo is public, so both run on every PR at no cost (section 8).
   - The Claude cloud container is Linux with no Swift toolchain and blocked downloads, so it can only write code, not build it.
6. **No SwiftData.** Vault data stays in the KDBX file; non-secret app state uses `KPAppState` (section 3).
7. **Platforms: iOS and iPadOS only.** No macOS, Mac Catalyst, "Designed for iPad" on Mac, visionOS or watchOS targets. (iPad apps can run on Apple silicon Macs; we opt out in App Store Connect to avoid supporting an untested platform.)
8. **Language: English only at launch, built for easy expansion.**
   - All user-facing text in String Catalogs (`Localizable.xcstrings`, one per target, and `AppShortcuts.xcstrings` for App Intents); no hardcoded strings. SwiftUI `Text("…")` literals and `LocalizedStringResource`/`String(localized:)` everywhere else, with comments for translators.
   - Formatting via `FormatStyle` (dates, numbers, relative times) and plurals via the catalog's plural variants, never string concatenation.
   - Layouts use leading/trailing and tolerate 40% longer text; right-to-left checked once with the pseudo-locale.
   - CI runs the UI smoke tests with a pseudo-language (accented and lengthened strings) and a lint that flags non-localized `Text` literals in non-test code, so adding a language later is translation work only.
   - Password generator wordlists are per-locale resources (English EFF list first).
9. **Formats: KDBX 4.x only.** No KDBX 3.1, KDB 1.x or Twofish support at all; these files get a conversion message.
10. **Opt-in network features: yes.** Favicon download and the breached-password check ship, off by default.
11. **No zero-unlock operations.** Every quick-create path unlocks first; there is no locked-state inbox.
12. **Telemetry: nothing is ever uploaded.** Users can export diagnostics files (and their databases) themselves through the share sheet.
13. **Funding: GitHub Sponsors link in Settings**, shown once in About, never as a prompt or nag.
14. **Repo: public.** Adds `SECURITY.md` (private vulnerability reporting through GitHub security advisories, not public issues), `CONTRIBUTING.md` (clean-room rule: no code from GPL KeePass clients), issue templates that tell reporters to attach diagnostics exports and never real databases or passwords, and Dependabot for Swift packages and GitHub Actions.

## 9b. Build vs. buy: handroll only when necessary

**Rule:** use a maintained MIT/BSD/Apache/CC0 dependency unless it fails a hard requirement (license, security, extension memory, iOS 18, correctness). Every handrolled component needs a justification in this table.

| Need | Use | Handroll? |
|---|---|---|
| KDBX 4.x read and write, Argon2, AES-KDF, ChaCha20 inner stream, SecureBytes | **[KDBXKit](https://github.com/shadone/KDBXKit)** (BSD-2, vendored Argon2 reference implementation, streaming attachments) | No; fork only if the spike finds gaps |
| AES, ChaCha20, SHA, HMAC, HKDF | CryptoKit / swift-crypto | No |
| KDBX 3.1, KDB 1.x, Twofish | Not supported (decision 9); detect and show a conversion message | No |
| gzip, XML | zlib / Foundation (inside KDBXKit) | No |
| YubiKey challenge-response | YubiKit (Apache-2) | No |
| QR scanning | VisionKit `DataScannerViewController` | No |
| App state persistence | `Codable` + `FileManager` (no SwiftData/Core Data, see section 3) | No |
| Logging, metrics, CLI | swift-log, swift-metrics, swift-argument-parser | No |
| Tracing | `OSSignposter` + `Trace.span` wrapper + uprobe markers | Thin wrapper only |
| Biometrics, Keychain, Secure Enclave | LocalAuthentication / Security / CryptoKit | No |
| AutoFill, passkeys | AuthenticationServices | No |
| TOTP | about 100 lines on CryptoKit HMAC (libraries exist but are tiny and not worth a dependency) | Yes, trivial |
| Files access, atomic save | `fileImporter`, bookmarks, `NSFileCoordinator`, `FileManager.replaceItemAt` | No |
| Testing, fuzzing | swift-testing, libFuzzer via SwiftPM, [SwiftCheck](https://github.com/typelift/SwiftCheck) | No |
| CSV import | [swift-csv](https://github.com/swiftcsv/SwiftCSV) (MIT) | Mapping only |
| **Merge engine** | Nothing usable exists | **Yes: core differentiator** |
| **Merge review UI, quick-create flows, diagnostics** | SwiftUI | Yes (product code) |

**KDBXKit spike (M0, first task).** KDBXKit has a single maintainer and low adoption, and it has no merge or history API. The spike checks seven things:

1. Lossless round-trip of unknown XML, custom data, history and attachments.
2. Memory and latency against the AutoFill budgets.
3. Whether its model exposes enough for merge (timestamps, `LocationChanged`, `DeletedObjects`, history).
4. Whether it can be cancelled during Argon2 and reports progress.
5. Whether it builds under Swift 6 strict concurrency.
6. Interop with the KeePassXC corpus.
7. Code quality and test coverage, since we're betting on it.

There are three possible verdicts:

- **(a)** Depend on a pinned version (expected).
- **(b)** Fork it under BSD-2 with attribution and send patches upstream.
- **(c)** Last resort: write our own reader and writer on CryptoKit plus the Argon2 reference C.

## 9c. Lower-level languages (only when profiling demands it)

- **When:** Swift is the default. Drop lower only when a profile from section 6 shows a hot path missing its section 7 budget after normal Swift optimization.
- **Order of preference: Rust, then C, then assembly.**
  - C is only for vetted existing code we don't rewrite, such as the Argon2 reference implementation inside KDBXKit.
  - Assembly or intrinsics only come from inside an already-chosen library. We never write them by hand.
- **Likely candidates:** Argon2 (the RustCrypto `argon2` crate, if the C version underperforms on device), search indexing at large scale, and merge diffing of very large databases.
- **Integration:**
  - Build a static XCFramework for iOS device and simulator (plus Linux static lib for CI), and expose it through UniFFI (or cbindgen and a C ABI).
  - Zeroize secrets with the `zeroize` crate, and keep unsafe code to a minimum.
  - Keep a Swift reference implementation alongside as a differential-test oracle.
  - Rust crates must be MIT or Apache. `cargo-deny` and `cargo-audit` run in CI.
- **Bar:** the PR must show the gain with `kpbench` and `XCTMetric`. If it's under about 20%, keep Swift.
- **Observability:** Rust code emits the same spans, through a callback into `Trace` or the `usdt` crate on Linux.

## 10. Security plan

- **Threat model** in `docs/threat-model.md`, covering:
  - a stolen locked or unlocked device
  - a malicious database file
  - memory pressure and memory dumps in extensions
  - clipboard snooping
  - tampering with the file by a File Provider
  - App Group container exposure
  - the App Group working copy and pending-sync flag being tampered with by another process (the copy is a normal encrypted KDBX with HMAC integrity; merge only ever adds or versions data, never deletes without a `DeletedObjects` record)
- **Parser hardening:**
  - Argon2 parameters, header sizes and decompression ratios are bounded before any allocation.
  - In extensions, a too-expensive KDF shows "Open in app" instead of being killed by the system.
- **Clipboard:** copying OTP codes and passwords never syncs to other devices.
- **Supply chain:** pinned dependencies, an SBOM, and reproducible build notes.
- **Before 1.0:** an external security review.
- **App Store:** password managers use standard cryptography, so the export compliance answer is "exempt". Set `ITSAppUsesNonExemptEncryption = NO`, and confirm with Apple's guidance at submission.

## 11. Risks

| Risk | Mitigation |
|---|---|
| KDBXKit is abandoned or has bugs | Pin the version; the spike's verdict (b) is to fork it; the interop corpus catches regressions |
| Extensions can't reach files in another app's File Provider | App Group working copy, pending-sync flag, merge on next app open (section 3) |
| Argon2 with large memory settings exceeds the extension memory limit | Bounded parameters; "Open in app" fallback; suggest lowering settings on the Diagnostics screen |
| Merge loses data | Three-way merge with base, losing versions kept in history, dry-run review, property tests plus a nothing-lost invariant, backups before every merge |
| uprobes on Swift symbols are brittle | `@_cdecl` stable markers; `usdt` crate fallback |
| Building only through CI is slow | Develop on a Mac; keep Linux core tests fast |

## 12. Immediate next steps (M0)

1. Add issue templates and Dependabot config (decision 14). `SECURITY.md`, `CONTRIBUTING.md`, the lint script and git hooks are already in place.
2. Clean up the template project:
   - Set the deployment target to 18.0 (currently 26.5) and Swift to 6 (currently 5.0).
   - Remove SwiftData entirely: delete `Item.swift`, the `ModelContainer` in `keepassiosApp.swift`, and the `@Query`/`modelContext` use in `ContentView.swift`.
   - Add an App Group and Keychain access group.
3. Add `Packages/KeePassCore` (KPModel, KPObservability, kpbench) with KDBXKit as a dependency, plus `linux.yml` and `macos.yml`.
4. Run the KDBXKit spike (9b) and record the verdict in `docs/adr/0001-kdbx-library.md`.
5. Add `Trace.span`, the uprobe markers and `Tools/bpf/spans.bt`, then profile `kpbench open` on the corpus under bpftrace (Linux) and Instruments (Mac).
6. Start M1.
