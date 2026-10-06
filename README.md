<h1 align="center">
  <img src="docs/media/icon.png" width="128" alt="KeePassIO app icon: a key shaped like an apple"><br>
  KeePassIO
</h1>

<p align="center">
  A free, open-source KeePass password manager for iPhone and iPad, written in SwiftUI.<br>
  No paywall, no tracking, no network access unless you turn it on.
</p>

<p align="center">
  <a href="https://github.com/guilherme-n-l/KeePassIO/actions/workflows/macos.yml"><img src="https://github.com/guilherme-n-l/KeePassIO/actions/workflows/macos.yml/badge.svg" alt="macOS CI"></a>
  <a href="https://github.com/guilherme-n-l/KeePassIO/actions/workflows/linux.yml"><img src="https://github.com/guilherme-n-l/KeePassIO/actions/workflows/linux.yml/badge.svg" alt="Linux CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4FA34F" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/iOS-18%2B-4FA34F" alt="iOS 18 or later">
  <a href="https://github.com/sponsors/guilherme-n-l"><img src="https://img.shields.io/badge/sponsor-%E2%99%A5-4FA34F" alt="Sponsor"></a>
</p>

> **Status:** early development. Not on the App Store yet.

## Features

### Your databases

- Opens and saves **KDBX 4** databases from the Files app: KeePassXC, KeePass and KeePassDX compatible, with a master password, a key file or both. Key files can be remembered.
- **Face ID** unlock, and auto-lock (immediately or after a delay) that saves your changes first.
- **Merging that doesn't lose data**: if the file changed elsewhere (another device, a sync client, KeePassXC), saving merges both versions three-way, and a review screen lists what changed.
- Aliases for databases ("Default" instead of `Database.kdbx`).

### Finding and organizing

- **Search like KeePassXC**: words match anywhere, with `field:` prefixes, `-exclusions`, `"phrases"`, wildcards, regular expressions, and paths like `mail/acc`, in the current group or the whole database.
- **Drag and drop** entries and groups into groups, onto the path bar to move them up, or onto another entry to make a new group.
- Entry and group **icons**: KeePassXC's standard set, favicons stored in the database, photos, or (opt-in) the website's own icon.
- Long-press menus for copying, opening, moving, renaming and more.

### Filling and creating

- **AutoFill** for passwords and one-time codes in Safari and other apps, including adding a new entry right from the login form.
- **TOTP** and Steam codes, a **password and passphrase generator** with KeePassXC's options, and a password audit (weak, reused, old).
- **Quick create** from Shortcuts, Siri and the Action Button (after unlocking).
- Copied passwords stay on the device (no Universal Clipboard) and expire.

### Built-in observability

Every operation is traced with signposts (Instruments), with on-device latency histograms you can export, and real eBPF probes when the core runs on Linux (see [Tools/bpf](Tools/bpf/README.md)).

## Layout

| Path | What |
|---|---|
| `keepassios/` | The SwiftUI app |
| `KeePassIOSAutoFill/` | The AutoFill credential provider extension |
| `Packages/KeePassCore/` | Core: model, merge, search, OTP, generator, sessions, KDBX codec, tracing; builds and tests on Linux |
| `Vendor/KDBXKit/` | Patched fork of [KDBXKit](https://github.com/shadone/KDBXKit) (BSD-2), see [VENDORED.md](Vendor/KDBXKit/VENDORED.md) |
| `Design/` | The app icon source (`scripts/make-app-icon.sh` renders it) |
| `Tools/bpf/` | bpftrace scripts for the core's probes |
| `docs/adr/` | Architecture decisions |
| [PLAN.md](PLAN.md) | Product and engineering plan |

## Building

- **App:** open `keepassios.xcodeproj` in Xcode 26 and run the `keepassios` scheme (iOS 18 or later).
- **Flash to a phone without opening Xcode:** connect the device (paired, Developer Mode on) and run `scripts/flash.sh`. It builds with `xcodebuild`, installs with `xcrun devicectl` and launches the app; `--release`, `--device NAME`, `--no-launch` and `--list` are available. Xcode must be installed (it provides these tools) and signed in to the project's development team once.
- **AutoFill:** after installing, tap **Turn On AutoFill** in the app (library or Settings).
- **App Store / TestFlight:** `scripts/release.sh` archives a Release build (build number = commit count), signs it with the team's account in Xcode and uploads it to App Store Connect; `--no-upload` only exports the `.ipa`. CI builds the same Release archive unsigned on every push.
- **Core:** `swift test --package-path Packages/KeePassCore` (macOS or Linux). Interop tests run when `keepassxc-cli` is installed.
- **Tools:** `nix develop` (or direnv with the included `.envrc`) gives a shell with every linter and test tool and turns on the git hooks; Xcode supplies Swift. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy

KeePassIO collects no data. See [PRIVACY.md](PRIVACY.md).

## License

MIT. Third-party code, data and artwork are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
