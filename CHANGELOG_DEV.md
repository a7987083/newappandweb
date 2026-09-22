# CHANGELOG_DEV

## 2026-09-23 — v0.1 bootstrap

### Repository
- Repository: `a7987083/newappandweb`
- Baseline branch: `main`
- Development branch: `feature/gamestore-v0.1-bootstrap`
- Initial main commit: `d065d3d70d5aa6d91e282598d8b1dcebbe90e601`
- Initial implementation commit: `48324eac325213cd9a998d21c6049fdedbda68ee`

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

### Verification
- Static target identification: completed.
- Source written: completed.
- Git implementation commit: completed.
- Compile: not yet verified.
- CI: trigger pending.
- Runtime: not verified.
- Physical device: not verified.
- Regression: not verified.
