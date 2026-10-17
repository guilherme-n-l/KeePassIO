# App Store material

- `metadata/`: the listing text (name, subtitle, promotional text,
  description, keywords, URLs, copyright, categories), one file per
  App Store Connect field, in fastlane deliver's layout.
- `KeePassIO Review Sample.kdbx`: a small demo database to attach for App
  Review (App Review Information > Attachment). Password:
  `review-KeePassIO-2026`. It has three made-up entries, one with a
  one-time code, and uses KDBX 4 with Argon2id (32 MB), so it also
  unlocks in the AutoFill extension. It contains no real data.

## Screenshots

`screenshots/en-US/` holds the 6.9" iPhone screenshots (1320 × 2868), taken from the demo database by `keepassiosUITests/ScreenshotTests.swift`. The Screenshots workflow retakes them when the app changes and commits them to the `app-store-screenshots` branch, one folder per commit; copy the new ones here when they change.

## Uploading

The App Store workflow (Actions > App Store > Run workflow) uploads `metadata/` and `screenshots/` to the App Store Connect version with fastlane deliver, through the App Store Connect API. It doesn't upload builds or submit for review. It needs an API key in three repository secrets:

1. In App Store Connect, open Users and Access > Integrations > App Store Connect API > Team Keys and generate a key with the App Manager role. Download the `.p8` file (Apple offers it only once) and note the key ID and the issuer ID.
2. In GitHub, open Settings > Secrets and variables > Actions and add `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_API_KEY` (the whole `.p8` file, including the BEGIN and END lines).

App Review contact details and notes, the age rating, pricing and the privacy questionnaire stay in App Store Connect's web pages.
