# App Store material

- `listing.md`: the text for App Store Connect's fields.
- `KeePassIO Review Sample.kdbx`: a small demo database to attach for App
  Review (App Review Information > Attachment). Password:
  `review-KeePassIO-2026`. It has three made-up entries, one with a
  one-time code, and uses KDBX 4 with Argon2id (32 MB), so it also
  unlocks in the AutoFill extension. It contains no real data.

## Screenshots

`screenshots/` holds the 6.9" iPhone screenshots (1320 × 2868) for App Store Connect, taken from the demo database by `keepassiosUITests/ScreenshotTests.swift`. The Screenshots workflow retakes them when the app changes and commits them to the `app-store-screenshots` branch, one folder per commit; copy the new ones here when they change.
