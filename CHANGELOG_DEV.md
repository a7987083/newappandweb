# CHANGELOG_DEV

## 2026-09-23 — v0.1 bootstrap

### Repository
- Repository: `a7987083/newappandweb`
- Baseline branch: `main`
- Development branch: `feature/gamestore-v0.1-bootstrap`
- Initial main commit: `d065d3d70d5aa6d91e282598d8b1dcebbe90e601`
- Initial implementation commit: `48324eac325213cd9a998d21c6049fdedbda68ee`
- Previous iOS 15 build-verified commit: `0ad791c9bc1abd544ee19303684d459b0470f6c7`
- iOS 13–26 compatibility build-verified commit: `10cebcfd3e240b0dc7b802f3ef521c688703cc55`

### Initial implementation
- SwiftUI shell with Software, Search, Downloads and Profile tabs.
- Initial `AppStoreViewModel`, API/UDID/download/signing/OTA service boundaries.
- Target-derived API base/endpoints and signing state names recorded.
- Five long-term project state files established.

### Reference analysis — UnitXP / zonoe alphaone13
- Secondary implementation reference: `a7987083/UnitXP_SP3-Moonstone` release `v3.0.0-alphaone13`, commit `76aebadd826156a1b67d175ea90c88371dc320cf`.
- Reconstruction pins `Nyasami/Ksign@03a3a9c86897d79f9faf8106037b9971841d56a0` and applies a canonical patch series.
- Useful reference areas: SigningHandler/Zsign/ZsignSwift, download/import, UDID localhost service/callback, URL Scheme routing and deterministic CI reconstruction.
- License boundary: `HFASign/LICENSE` is GPLv3; no GPL-covered implementation code was copied into GameStore.

### iOS 13–26 compatibility conversion
Product requirement is now minimum iOS `13.0` through latest iOS `26.x`. The target GameStore's own minimum remains a separate verified fact at iOS `15.0`.

Implemented compatibility changes:
- Replaced SwiftUI `App` / `@StateObject` bootstrap with iOS 13-compatible `UIApplicationDelegate + UIWindow + UIHostingController`.
- Converted `APIService` async URLSession calls to callback-based `URLSessionDataTask` APIs.
- Converted `AppStoreViewModel` reload flow to callback-based networking with main-queue state updates.
- Replaced higher-version SwiftUI APIs in the initial shell: `Label`, `ProgressView`, `.searchable`, `.refreshable`, `.task`, newer alert syntax, `@AppStorage`, newer button roles and newer style APIs.
- Replaced search with an iOS 13-compatible `TextField` implementation.
- Replaced download `ProgressView` with a custom GeometryReader progress bar.
- Removed Swift concurrency/actor requirements from `UDIDService`, `DownloadCenter`, `OTAInstallService` and the current signing interface.
- Set project and target `IPHONEOS_DEPLOYMENT_TARGET = 13.0`.

### Dual CI
Workflow now contains:
- `Legacy iOS 13 / Xcode 15.4` on `macos-14`, compiling with `IPHONEOS_DEPLOYMENT_TARGET=13.0`.
- `Modern iOS 26 SDK / Xcode 26.6` on `macos-26`, validating the source against the current iOS 26 SDK/toolchain.

First dual-CI run on commit `90f9c9e086ada4727064db7e37c6c2d2cca0333e` failed in both lanes. The first real legacy compiler error was:
- `AppStoreViewModel.swift`: synchronous construction of `DownloadCenter()` attempted to call a `@MainActor`-isolated initializer.
- The same audit also exposed `UDIDService.shared` actor isolation as a Swift 6 future error.

Root-cause fix:
- Removed unnecessary actor isolation from the state-only/bootstrap services and removed remaining concurrency-only interfaces rather than bypassing the error.

Final compatibility verification:
- Commit: `10cebcfd3e240b0dc7b802f3ef521c688703cc55`
- GitHub Actions Run: `35800817890`
- Legacy Job `106990507365`: **success** — Xcode 15.4, iOS Simulator SDK 17.5, deployment target iOS 13.0.
- Modern Job `106990507207`: **success** — Xcode 26.6 / iOS 26 SDK lane.

### Verification status
- Static target identification: completed.
- Reference-source analysis: completed for selected UnitXP alphaone13 paths.
- Source changes for initial iOS 13 compatibility: completed and committed.
- iOS 13 compile: **verified successful in CI**.
- iOS 26 SDK compile: **verified successful in CI**.
- Runtime launch on iOS 13: not verified.
- Physical-device verification: not verified.
- Full iOS 13–26 runtime regression matrix: not verified.
