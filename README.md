# KeePassIO

A free, open-source KeePass password manager for iPhone and iPad, written in SwiftUI. No paywall, no tracking, no network access unless you turn it on.

> Status: early development. Not on the App Store yet.

## Features

- Opens and saves **KDBX 4** databases (KeePassXC, KeePass, KeePassDX compatible), with password and/or key file.
- **Merging that doesn't lose data**: if the file changed elsewhere (another device, a sync client, KeePassXC), saving merges both versions three-way; the other version of a changed entry is kept in its history, and a review screen lists what changed.
- Search across the whole database, TOTP and Steam codes, password and passphrase generator, password audit (weak, reused, old), entry history and recycle bin.
- **Quick create** from Shortcuts, Siri and the Action Button (after unlocking).
- Copied passwords stay on the device (no Universal Clipboard) and expire.
- **Built-in observability**: every operation is traced with signposts (Instruments), on-device latency histograms you can export, and real eBPF probes when the core runs on Linux (see [Tools/bpf](Tools/bpf/README.md)).

## Layout

| Path | What |
|---|---|
| `keepassios/` | The SwiftUI app |
| `Packages/KeePassCore/` | Platform-independent core: model, merge, search, OTP, generator, sessions, KDBX codec, tracing; builds and tests on Linux |
| `Vendor/KDBXKit/` | Patched fork of [KDBXKit](https://github.com/shadone/KDBXKit) (BSD-2), see [VENDORED.md](Vendor/KDBXKit/VENDORED.md) |
| `Tools/bpf/` | bpftrace scripts for the core's probes |
| `docs/adr/` | Architecture decisions |
| [PLAN.md](PLAN.md) | Product and engineering plan |

## Building

- **App:** open `keepassios.xcodeproj` in Xcode 26 and run the `keepassios` scheme (iOS 18 or later).
- **Flash to a phone without opening Xcode:** connect the device (paired, Developer Mode on) and run `scripts/flash.sh`. It builds with `xcodebuild`, installs with `xcrun devicectl` and launches the app; `--release`, `--device NAME`, `--no-launch` and `--list` are available. Xcode must be installed (it provides these tools) and signed in to the project's development team once.
- **Core:** `swift test --package-path Packages/KeePassCore` (macOS or Linux). Interop tests run when `keepassxc-cli` is installed.
- **Tools:** `nix develop` (or direnv with the included `.envrc`) gives a shell with every linter and test tool and turns on the git hooks; Xcode supplies Swift. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. Third-party code and data are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
