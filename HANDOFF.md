# HANDOFF

## Project intent

This repository is a clean-room reimplementation of an authorized GameStore target. Do not treat decompiler pseudocode, strings alone, inferred server behavior, or behavior from other projects as ground truth.

## Product compatibility requirement

- Minimum supported OS: **iOS 13.0**.
- Maximum/current support target: **latest iOS 26.x**.
- Legacy build validation: Xcode 15.4 / Swift 5.10 with iOS 13 deployment target.
- Modern build validation: Xcode 26.x with iOS 26 SDK.
- Keep target facts separate from product requirements: the original GameStore target declares minimum iOS `15.0`.
- Any API introduced after iOS 13 must be guarded or replaced with an iOS 13-compatible path.

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

For implementation experience, inspect:
- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Release: `v3.0.0-alphaone13`
- Commit: `76aebadd826156a1b67d175ea90c88371dc320cf`
- Artifact: `zonoe_v3.0.0-alphaone13_TrollStore.ipa`
- Reconstruction script: `HFASign/scripts/reconstruct_alphaone10.sh`
- Pinned upstream: `Nyasami/Ksign@03a3a9c86897d79f9faf8106037b9971841d56a0`

High-value reference areas:
- `Ksign/Utilities/Handlers/SigningHandler.swift`: Zsign-based signing pipeline and signature-validation integration.
- `ZsignSwift`: reference for Swift-facing signature validation.
- `IPADownloadManager`: download destination collision handling, auto-import and cleanup patterns.
- `UDIDService`: localhost service lifecycle, background task lifetime and custom URL completion.
- alphaone8 clean UDID architecture: Domain/Application/Infrastructure/Presentation separation.
- URL Scheme handling and deterministic reconstruction/build workflow.

Important: this reference is **secondary implementation evidence only**. It does not prove GameStore request formats, server behavior, certificate semantics, local-server ports, OTA manifest shape or UI behavior.

License boundary: `HFASign/LICENSE` is GPLv3. Do not copy GPL-covered implementation code into this clean-room repository without an explicit project licensing decision. Prefer independent implementation based on target evidence and general architectural lessons.

## Current architecture

`View -> AppStoreViewModel -> Service protocols -> network/download/signing/install adapters`

The v0.1 signing service intentionally does not sign. It exists to make the recovered state machine and dependency boundary explicit before a verified Zsign bridge is implemented.

## Current build state

- Development branch: `feature/gamestore-v0.1-bootstrap`
- Build-verified code commit: `0ad791c9bc1abd544ee19303684d459b0470f6c7`
- GitHub Actions Run: `35798677918`
- Job: `106983783519`
- Build result: **success**
- Verified environment: Xcode 16.4, iPhoneSimulator 18.5, deployment target iOS 15.0.
- New product requirement iOS 13.0–26.x is **recorded but not yet build-verified**.
- Runtime verification: not performed.
- Physical-device verification: not performed.

## Next implementation baseline change

Before expanding features:
1. Set project deployment target to iOS 13.0.
2. Audit all SwiftUI/Foundation/UIKit APIs for iOS 13 availability.
3. Replace or guard newer APIs.
4. Add Xcode 15.4 legacy CI.
5. Add Xcode 26.x modern SDK CI.
6. Only mark iOS 13–26 compatibility verified after both build lanes pass and representative runtime/device checks exist.

## Evidence policy

Every important conclusion must be marked as one of:
- static verified
- automated verified
- build verified
- runtime verified
- physical-device verified
- unverified/inferred

Reference-project behavior must additionally be marked as `reference-only` unless independently matched to GameStore evidence.

## Handoff rule

Before changing behavior, inspect:
1. `PROJECT_STATE.json`
2. current Git branch/HEAD
3. `git status` / diff
4. `KNOWN_ISSUES.md`
5. current CI run
6. target evidence before applying any behavior learned from UnitXP/Ksign

Update all five state files after meaningful development or verification changes.
