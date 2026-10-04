# Third-party notices

KeePassIOS is MIT-licensed. It includes or depends on the following third-party work.

## Bundled data

### EFF large wordlist

`Packages/KeePassCore/Sources/KPGenerator/Resources/eff_large_wordlist.txt` is the EFF large wordlist for passphrases by the Electronic Frontier Foundation, licensed under [Creative Commons Attribution 3.0 United States](https://creativecommons.org/licenses/by/3.0/us/). Source: <https://www.eff.org/dice>. It is included unmodified.

### KeePassXC database icons

`keepassios/Assets.xcassets/DatabaseIcons` holds the standard entry and group icons from [KeePassXC](https://github.com/keepassxreboot/keepassxc) (`share/icons/database`, commit `9e0f57a`), unmodified, so entries look the same as on the desktop. Per KeePassXC's `COPYING`:

- Most icons come from [icons8 flat-color-icons](https://github.com/icons8/flat-color-icons), MIT License.
- C07, C17, C18, C26, C27, C35, C38, C44, C51, C52, C54 and C66 come from [paomedia small-n-flat](https://github.com/paomedia/small-n-flat), CC0 1.0.
- C37, C45, C46, C53 and C61 are Copyright (c) 2022 KeePassXC Team, MIT License.

KeePassXC's C64 (Apple logo) is GPL-2.0-or-later and is not included; that icon is drawn with an SF Symbol.

### App icon

`Design/AppIcon.svg`, from which `scripts/make-app-icon.sh` renders the app icon, is the project owner's adaptation of an apple icon from [SVG Repo](https://www.svgrepo.com/), licensed under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## Vendored code

### KDBXKit

`Vendor/KDBXKit` is a fork of [KDBXKit](https://github.com/shadone/KDBXKit), Copyright (c) 2025-2026 Denis Dzyubenko, licensed under the BSD 2-Clause License (`Vendor/KDBXKit/LICENSE`). Local changes are listed in `Vendor/KDBXKit/VENDORED.md`. It bundles the Argon2 reference implementation (CC0 1.0 / Apache-2.0).

## Swift package dependencies

| Package | License | Used for |
|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | `kpbench` command-line interface |
| [swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | Cryptography (CryptoKit's API on every platform) |
| [swift-log](https://github.com/apple/swift-log) | Apache-2.0 | Logging inside KDBXKit |

## Development-only

The Claude skills in `.claude/skills/` are listed with their licenses in [.claude/skills/README.md](.claude/skills/README.md). They are not part of the app.
