# Third-party notices

KeePassIOS is MIT-licensed. It includes or depends on the following third-party work.

## Bundled data

### EFF large wordlist

`Packages/KeePassCore/Sources/KPGenerator/Resources/eff_large_wordlist.txt` is the EFF large wordlist for passphrases by the Electronic Frontier Foundation, licensed under [Creative Commons Attribution 3.0 United States](https://creativecommons.org/licenses/by/3.0/us/). Source: <https://www.eff.org/dice>. It is included unmodified.

## Swift package dependencies

| Package | License | Used for |
|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | `kpbench` command-line interface |
| [swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | HMAC for one-time passwords (CryptoKit's API on every platform) |

## Development-only

The Claude skills in `.claude/skills/` are listed with their licenses in [.claude/skills/README.md](.claude/skills/README.md). They are not part of the app.
