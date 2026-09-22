# HANDOFF

## Project intent

This repository is a clean-room reimplementation of an authorized GameStore target. Do not treat decompiler pseudocode, strings alone, or inferred server behavior as ground truth.

## Verified target facts

Target main executable SHA-256:
`ea4947e192da53ceae434e51108c9af49f6a99d80c9d5e6e7e0d2ac5e6324e4e`

Static facts:
- arm64 Mach-O
- bundle id `com.GameStore.maicha`
- version `1.2 (1)`
- minimum iOS `15.0`
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

## Current architecture

`View -> AppStoreViewModel -> Service protocols -> network/download/signing/install adapters`

The v0.1 signing service intentionally does not sign. It exists to make the recovered state machine and dependency boundary explicit before a verified Zsign bridge is implemented.

## Current build state

- Development branch: `feature/gamestore-v0.1-bootstrap`
- Build-verified code commit: `0ad791c9bc1abd544ee19303684d459b0470f6c7`
- GitHub Actions Run: `35798677918`
- Job: `106983783519`
- Build result: **success**
- Environment: Xcode 16.4, iPhoneSimulator 18.5, deployment target iOS 15.0.
- Runtime verification: not performed.
- Physical-device verification: not performed.

## Evidence policy

Every important conclusion must be marked as one of:
- static verified
- automated verified
- build verified
- runtime verified
- physical-device verified
- unverified/inferred

## Handoff rule

Before changing behavior, inspect:
1. `PROJECT_STATE.json`
2. current Git branch/HEAD
3. `git status` / diff
4. `KNOWN_ISSUES.md`
5. current CI run

Update all five state files after meaningful development or verification changes.
