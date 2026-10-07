# Quota iOS: agent instructions

iOS app (SwiftUI) and WidgetKit widgets that show the remaining subscription usage published by `quota-server` from the macOS project (github.com/turinglabsorg/quota). Keep behavior and copy in sync with the macOS app and Quotax (github.com/turinglabsorg/quotax).

## Layout

- `App/`: the app (`AppModel`, account list, pairing, settings).
- `Widgets/`: the widget extension: one `UsageWidget` for `systemSmall`, `systemMedium`, `accessoryCircular`, `accessoryRectangular` and `accessoryInline`.
- `Shared/`: compiled into both targets: `QuotaClient` (pairing, usage fetch, payload cache), `TokenStore` (Keychain), styles and sample data.
- `quota/`: git submodule of the macOS project. Both targets compile `quota/Sources/QuotaCore/{Models,Formatting,JSON,UsagePayload}.swift`, `quota/Sources/Quota/ProviderGlyph.swift` and `quota/Resources/{en,it}.lproj` from it. Change those files in the quota repository, then bump the submodule here.
- `project.yml`: XcodeGen spec. The `.xcodeproj`, Info.plists and entitlements are generated: never edit or commit them.
- `DESIGN.md`: design notes for the iOS surfaces. Read it before any UI change and update it when you add patterns; shared tokens come from `quota/DESIGN.md`.

## Commands

- Simulator build: `scripts/build-ios.sh` (ad-hoc signed, so the App Group and Keychain work in the simulator).
- Device: `QUOTA_TEAM_ID=<team> scripts/build-ios.sh --device`, or `--install` to build for and install on the connected iPhone (registers it in the provisioning profile).
- If the Command Line Tools are the selected developer directory, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Screenshots: launch with `-QuotaSampleData` (`xcrun simctl launch <device> com.turinglabs.quota.ios -QuotaSampleData`) so app and widgets show sample accounts, never real ones.

## Server API (version 1)

- `POST /v1/pair` with `{"code","name"}` → `{"token"}`; 401 invalid code, 410 expired code.
- `GET /v1/usage` with `Authorization: Bearer <token>` → `UsagePayload` JSON; 401 means the device was revoked: unpair.
- Skip window kinds this app does not know (`WindowUsage.window` returns nil); the server may be newer than the app.

## Rules

- No server address is built in; the user enters it when pairing.
- The device token stays in the Keychain (access group = the App Group, `AfterFirstUnlockThisDeviceOnly`); never log, print or persist it elsewhere. Only usage numbers are cached, in the App Group container.
- The App Group id comes from `QUOTA_APP_GROUP` in `project.yml` (entitlements and the `QuotaAppGroup` Info.plist key); never hard-code it elsewhere.
- Widgets must stay light: one fetch per timeline reload (every 15 minutes), cached data on failure.
- User-facing strings are English in code (`String(localized:)` or SwiftUI literals) with Italian translations in `quota/Resources/it.lproj/Localizable.strings`. Render percentages with `Text(verbatim:)`.
- Code, comments and docs in English.
