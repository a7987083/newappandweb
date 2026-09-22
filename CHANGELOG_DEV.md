# CHANGELOG_DEV

## 2026-09-23 — v0.1 bootstrap

### Repository
- Repository: `a7987083/newappandweb`
- Baseline branch: `main`
- Development branch: `feature/gamestore-v0.1-bootstrap`
- Initial main commit: `d065d3d70d5aa6d91e282598d8b1dcebbe90e601`
- Initial implementation commit: `48324eac325213cd9a998d21c6049fdedbda68ee`
- iOS 15 compatibility fix commit: `0ad791c9bc1abd544ee19303684d459b0470f6c7`

### Added
- SwiftUI application bootstrap and custom URL callback handling.
- Four-tab shell: Software, Search, Downloads, Profile.
- Initial `AppStoreViewModel`.
- `APIService` with the statically verified API base and app-list/device-check paths.
- `UDIDService` with the statically verified configuration path and `gamestore://` callback boundary.
- Download queue state model.
- Signing protocol and statically observed signing state names.
- OTA `itms-services` URL launcher.
- Xcode project and GitHub Actions build workflow.
- Five project-state files required for long-term handoff.

### Compile-preflight corrections
- Added explicit `Combine` imports for files using `ObservableObject` / `@Published`.
- Removed `LabeledContent` from the iOS 15 code path and replaced it with an iOS 15-compatible row.
- Routed URL callback state mutation back to the main actor.

### CI / Build verification
- Run `35798589265`: failed.
- First real compiler error: `SoftwareView.swift` used `LabeledContent`, which is iOS 16+ while the target baseline is iOS 15.0.
- Fix landed in `0ad791c9bc1abd544ee19303684d459b0470f6c7`.
- Run `35798677918`, Job `106983783519`: **success**.
- Environment: macOS 15.7.9 runner, Xcode 16.4, iPhoneSimulator 18.5 SDK.
- Build command: `xcodebuild -project GameStore.xcodeproj -scheme GameStore -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`.

### Verification status
- Static target identification: completed.
- Source written: completed.
- Git commit: completed.
- Compile: **verified successful in CI**.
- CI: **green for `0ad791c9...`**.
- Runtime: not verified.
- Physical device: not verified.
- Regression: not verified.
