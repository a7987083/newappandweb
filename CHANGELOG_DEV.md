# CHANGELOG_DEV

## 2026-09-23 — v0.1 bootstrap

### Repository
- Repository: `a7987083/newappandweb`
- Baseline branch: `main`
- Development branch: `feature/gamestore-v0.1-bootstrap`
- Initial main commit: `d065d3d70d5aa6d91e282598d8b1dcebbe90e601`

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

### Verification
- Static target identification: completed.
- Source written: completed.
- Git commit: pending at time this entry was authored.
- Compile: not yet verified.
- CI: not yet verified.
- Runtime: not verified.
- Physical device: not verified.
- Regression: not verified.
