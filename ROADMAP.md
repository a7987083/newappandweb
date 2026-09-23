# ROADMAP

## Goal

Build a clean-room GameStore implementation whose UI, public request protocol, download workflow, certificate workflow, signing state machine and OTA installation behavior are compatible with the verified target build, while extending runtime compatibility below the target's original minimum OS.

## Compatibility target

- Product minimum iOS: `13.0`.
- Product maximum/support ceiling: latest `iOS 26.x` available in the iOS 26 generation.
- Target-app fact remains separate: the verified GameStore target declares minimum iOS `15.0`.
- Legacy build validation: Xcode 15.4 / Swift 5.10 / iOS 13 deployment target.
- Modern build/SDK validation: Xcode 26.6 / iOS 26 SDK.
- Do not rely on iOS 14+ / 15+ SwiftUI APIs without availability handling or compatible alternatives.

## Baseline evidence

- Target main executable SHA-256: `ea4947e192da53ceae434e51108c9af49f6a99d80c9d5e6e7e0d2ac5e6324e4e`
- Target bundle id: `com.GameStore.maicha`
- Target version: `1.2 (1)`
- Target minimum iOS: `15.0`
- Static evidence confirms SwiftUI/UIKit, `gamestore://`, API base `https://new.iosgame.vip`, download/signing/OTA state strings.
- Runtime/device behavior is not yet verified.

## Internal reference baseline

The user's existing project is an implementation reference for reusable engineering patterns, not authoritative evidence for GameStore behavior:

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Release: `v3.0.0-alphaone13`
- Release commit: `76aebadd826156a1b67d175ea90c88371dc320cf`
- Release artifact: `zonoe_v3.0.0-alphaone13_TrollStore.ipa`
- Relevant areas: Ksign/Zsign signing integration, `SigningHandler`, `ZsignSwift`, download/import handling, UDID local HTTP service and callback architecture, URL Scheme routing, build/reconstruction CI.
- Reconstruction pins `Nyasami/Ksign@03a3a9c86897d79f9faf8106037b9971841d56a0` plus a canonical patch stack.
- `HFASign/LICENSE` is GPLv3. Do not copy GPL-covered implementation code into this clean-room project without an explicit license decision.

## Phases

### Phase 0 — Bootstrap and compatibility baseline
- [x] Repository initialized.
- [x] Long-term state documents established.
- [x] Xcode project skeleton.
- [x] Four primary tabs.
- [x] API/UDID/download/signing/OTA service boundaries.
- [x] Internal reference baseline `UnitXP_SP3-Moonstone@v3.0.0-alphaone13` recorded.
- [x] Product compatibility requirement fixed at iOS 13.0 through iOS 26.x.
- [x] Project deployment target converted from iOS 15.0 to iOS 13.0.
- [x] SwiftUI app lifecycle replaced with iOS 13-compatible `UIApplicationDelegate + UIHostingController` bootstrap.
- [x] iOS 14/15+ bootstrap APIs removed or replaced in the initial UI/network/service shell.
- [x] Dual CI added: Xcode 15.4 legacy build plus Xcode 26.6 modern SDK build.
- [x] Dual CI green on commit `10cebcfd3e240b0dc7b802f3ef521c688703cc55`, Run `35800817890`.

### Phase 1 — Protocol recovery
- [ ] Recover exact JSON schemas and HTTP methods/headers.
- [ ] Reconstruct activation-code workflow.
- [ ] Reconstruct device-certificate workflow.
- [ ] Add protocol fixture tests.

### Phase 2 — Downloads and persistence
- [ ] Background URLSession transfer.
- [ ] Pause/resume/retry/delete.
- [ ] Persistent task recovery.
- [ ] Cache accounting.
- [ ] Use UnitXP alphaone13 `IPADownloadManager` behavior as a secondary reference for collision-safe naming, auto-import and post-import cleanup; independently implement GameStore-compatible behavior.

### Phase 3 — Signing
- [ ] IPA inspector/archive implementation.
- [ ] Certificate import/storage.
- [ ] Zsign bridge.
- [ ] Signature validation.
- [ ] Repack artifact.
- [ ] Compare target-derived signing state machine against UnitXP alphaone13 `SigningHandler` / `ZsignSwift` integration before implementing the bridge.

### Phase 4 — OTA install
- [ ] Local IPA HTTP server.
- [ ] Manifest generation.
- [ ] localhost/LAN strategy matching verified target behavior.
- [ ] `itms-services` launch and install-progress observation.
- [ ] Reuse lessons from UnitXP alphaone13 local HTTP/UDID server lifecycle and URL callback handling, but verify GameStore's manifest/install protocol independently.

### Phase 5 — UI parity
- [ ] Extract visual measurements/assets legally available from target package.
- [ ] Rebuild detail/activation/certificate/signing-log screens.
- [ ] Simplified/Traditional Chinese parity.
- [ ] Device screenshot regression comparisons.
- [ ] Maintain iOS 13-compatible UI fallbacks while allowing newer-system enhancements behind availability checks.

## Next Task

Resume Phase 1: recover the exact `/apps/api/app-list/` request method, headers, response envelope and model/CodingKeys from target evidence. Keep the dual iOS 13 / iOS 26 build lanes green while feature code grows.
