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

### Reference analysis — UnitXP / zonoe alphaone13
- Added secondary implementation reference: `a7987083/UnitXP_SP3-Moonstone` release `v3.0.0-alphaone13`, commit `76aebadd826156a1b67d175ea90c88371dc320cf`.
- Verified its reconstruction pipeline pins `Nyasami/Ksign` at `03a3a9c86897d79f9faf8106037b9971841d56a0` and applies a canonical patch series plus additive alphaone11/12/13 transforms.
- Identified high-value reference areas: `SigningHandler`, Zsign/ZsignSwift integration, download/import behavior, UDID localhost service/callback, URL Scheme routing and deterministic CI reconstruction.
- Verified the alphaone8 clean UDID callback patch separates Domain/Application/Infrastructure/Presentation responsibilities; useful architectural precedent for GameStore service boundaries.
- Verified the alpha18 UDID local-server patch keeps the server alive via an iOS background task and completes through a custom URL redirect.
- Verified alphaone12 download logic contains collision-safe rename, auto-import and optional post-import deletion behavior.
- License boundary recorded: `HFASign/LICENSE` is GPLv3. No GPL-covered implementation code has been copied into GameStore in this change.

### Compatibility decision — iOS 13 through iOS 26
- Product requirement changed from the bootstrap's iOS 15 deployment target to **minimum iOS 13.0**.
- Product support ceiling is the latest **iOS 26.x** generation.
- The target GameStore's own minimum iOS remains a verified target fact at `15.0`; it is not rewritten as product evidence.
- Apple toolchain validation strategy: Xcode 15.4 for iOS 13 deployment-target compatibility; Xcode 26.x for iOS 26 SDK/latest-system compatibility.
- Current source/project has **not yet been converted** to iOS 13 in this documentation-only change; the last successful build remains the iOS 15/Xcode 16.4 build.
- Required follow-up: lower deployment target, audit SwiftUI/API availability, add compatibility fallbacks, and introduce dual CI.

### Verification status
- Static target identification: completed.
- Reference-source analysis: completed for selected UnitXP alphaone13 signing/download/UDID paths.
- Product compatibility requirement: recorded as iOS 13.0–26.x.
- Source written: completed for v0.1 bootstrap; iOS 13 conversion not yet implemented.
- Git commit: completed for documentation changes.
- Compile: **verified successful in CI only for the prior iOS 15 implementation commit** `0ad791c9bc1abd544ee19303684d459b0470f6c7`.
- iOS 13 build: not yet verified.
- iOS 26 SDK build: not yet verified.
- Runtime: not verified.
- Physical device: not verified.
- Regression: not verified.
