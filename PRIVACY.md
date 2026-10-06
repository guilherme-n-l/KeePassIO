# Privacy Policy

KeePassIO is a password manager for KeePass databases. It is free, open source and has no accounts, servers, analytics, advertising or tracking.

**Effective date:** October 6, 2026

## What KeePassIO collects

Nothing. The developer does not collect, receive or store any information about you or your use of the app. There is no analytics, crash reporting or advertising SDK in the app.

## Your data stays on your devices

- **Password databases** are KDBX files that you choose in the Files app. KeePassIO reads and writes them where you keep them (on your device, in iCloud Drive or in another app's storage); it never uploads them anywhere itself. Syncing, if any, is done by the storage provider you chose.
- **Copies for AutoFill:** so the AutoFill extension can work when it can't reach the original file, the app keeps an encrypted copy of each database in its own App Group storage on your device. Entries added in AutoFill while the original is unreachable are kept in a similar encrypted copy until the app merges them into the original. These copies are deleted when you remove the database from KeePassIO.
- **Face ID quick unlock:** if you turn it on, the database key is stored in the iOS Keychain on your device, protected by Face ID or Touch ID, and never leaves the device. It expires after the time you choose and becomes unusable if the enrolled faces or fingerprints change.
- **Remembered key files:** KeePassIO remembers where your key file is (a bookmark), not the key file itself.
- **App settings** (library of databases, preferences) are stored on your device only. They don't contain passwords or database contents.
- **Copied passwords** are marked local-only, so they aren't shared through Universal Clipboard, and are cleared from the clipboard after the time you choose.
- **Previews and shares** of attachments or databases use temporary copies on your device that are deleted when you close the preview or share sheet.

## Network access

KeePassIO doesn't connect to the internet unless you turn on **Allow Network Access** in Settings (off by default). With it on, the only feature that uses the network is **Download Website Icons** (also off by default): it fetches an entry's icon from that entry's own website, and the request goes directly to that website. No developer-run server is involved.

Opening a link from an entry opens it in your browser, which is then subject to the browser's and the website's own policies.

## Camera and photos

If you scan a QR code to set up a one-time code, the camera is used only to read that QR code on your device; nothing is recorded or sent. Photos you choose (for an icon, an attachment or a QR code image) are read only to do what you asked.

## Diagnostics

The Diagnostics screen in Settings shows timings of operations measured on your device. You can export them as a file and share them yourself if you choose; nothing is sent automatically, and the export contains no passwords or database contents.

## Children

KeePassIO doesn't collect data from anyone, including children.

## Changes

Changes to this policy are published in this file, in the project's public repository, with the date above updated.

## Contact

Questions about privacy: open an issue at <https://github.com/guilherme-n-l/KeePassIO/issues>. For security issues, see [SECURITY.md](SECURITY.md).
