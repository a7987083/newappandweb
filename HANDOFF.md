# HANDOFF

## Project intent

This repository is a clean-room reimplementation of an authorized GameStore target. Do not treat decompiler pseudocode, strings alone, inferred server behavior, or behavior from other projects as ground truth.

## Product compatibility requirement

- Minimum supported OS: **iOS 13.0**.
- Maximum/current support target: **latest iOS 26.x**.
- Target-app fact remains separate: original GameStore declares minimum iOS `15.0`.
- Legacy compile validation: Xcode 15.4 with deployment target iOS 13.0.
- Modern SDK validation: Xcode 26.6 with iOS 26 SDK.
- APIs introduced after iOS 13 must be guarded or replaced with an iOS 13-compatible path.

## Verified target facts

Target main executable SHA-256:
`ea4947e192da53ceae434e51108c9af49f6a99d80c9d5e6e7e0d2ac5e6324e4e`

Static facts:
- arm64 Mach-O
- bundle id `com.GameStore.maicha`
- version `1.2 (1)`
- target minimum iOS `15.0`
- URL scheme `gamestore`
- base URL `https://new.iosgame.vip`
- observed paths:
  - `/apps/api/app-list/`
  - `/activation/device-certificates/`
  - `/activation/my-games/`
  - `/activation/ios-download/`
  - `/activation/remote-manifest/`
  - `/device/check-udid/`
  - `/device/udid/config/`
- observed install prefix: `itms-services://?action=download-manifest&url=`
- observed module/object names include APIService, AppSigningService, DownloadCenter, IPAArchive, IPAInspector, KeychainService, PersistenceService, PostSignInstallService, UDIDService, AppStoreViewModel and SwiftUI views.

## Vetted internal reference project

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Release: `v3.0.0-alphaone13`
- Commit: `76aebadd826156a1b67d175ea90c88371dc320cf`
- Pinned upstream: `Nyasami/Ksign@03a3a9c86897d79f9faf8106037b9971841d56a0`
- Reference areas: SigningHandler/Zsign/ZsignSwift, IPADownloadManager, UDID localhost service/callback, URL Scheme routing and deterministic reconstruction/build workflow.

This reference is secondary implementation evidence only. It does not prove GameStore protocol/constants/ports/UI behavior. `HFASign/LICENSE` is GPLv3; do not directly copy GPL-covered code without an explicit licensing decision.

## Current architecture

`UIApplicationDelegate -> UIHostingController -> SwiftUI Views -> AppStoreViewModel -> Service protocols/adapters`

The UIKit bootstrap is intentional: SwiftUI `App` and `@StateObject` require iOS 14+, while product compatibility begins at iOS 13.

Initial compatibility shell rules:
- callback-based networking instead of iOS 15 async URLSession convenience APIs;
- no unguarded iOS 14+ SwiftUI APIs;
- state/service boundaries avoid unnecessary Swift-concurrency actor requirements;
- modern-system enhancements may be added behind availability checks.

The v0.1 signing service still intentionally does not sign. It defines the target-derived state-machine/service boundary before a verified Zsign bridge is implemented.

## Current Git/build state

- Development branch: `feature/gamestore-v0.1-bootstrap`
- Build-verified compatibility commit: `10cebcfd3e240b0dc7b802f3ef521c688703cc55`
- GitHub Actions Run: `35800817890`
- Legacy Job: `106990507365` — **success**
  - Xcode 15.4
  - iPhoneSimulator SDK 17.5
  - `IPHONEOS_DEPLOYMENT_TARGET=13.0`
- Modern Job: `106990507207` — **success**
  - Xcode 26.6
  - current iOS 26 SDK lane
- Runtime verification: not performed.
- Physical-device verification: not performed.
- Full iOS 13–26 runtime matrix: not performed.

## Compatibility failure history

First dual-CI attempt failed because `DownloadCenter` and `UDIDService` retained `@MainActor` isolation while `AppStoreViewModel` was synchronously initialized. The fix removed unnecessary actor isolation/concurrency-only interfaces rather than masking the compiler error. The subsequent dual-CI run is green.

## Evidence policy

Every important conclusion must be marked as one of:
- static verified
- automated verified
- build verified
- runtime verified
- physical-device verified
- unverified/inferred

Reference-project behavior must additionally be marked `reference-only` unless independently matched to GameStore evidence.

## Next task

Resume Phase 1 and recover the exact `/apps/api/app-list/` request/response contract from target evidence. Keep both legacy and modern build lanes green after every meaningful compatibility-sensitive change.

## Handoff rule

Before changing behavior, inspect:
1. `PROJECT_STATE.json`
2. current Git branch/HEAD
3. `git status` / diff
4. `KNOWN_ISSUES.md`
5. current CI run
6. target evidence before applying behavior learned from UnitXP/Ksign

Update all five state files after meaningful development or verification changes.
