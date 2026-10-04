# Third-party notices

KeePassIOS is MIT-licensed. It includes or depends on the following third-party work.

## Bundled data

### EFF large wordlist

`Packages/KeePassCore/Sources/KPGenerator/Resources/eff_large_wordlist.txt` is the EFF large wordlist for passphrases by the Electronic Frontier Foundation, licensed under [Creative Commons Attribution 3.0 United States](https://creativecommons.org/licenses/by/3.0/us/). Source: <https://www.eff.org/dice>. It is included unmodified.

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
