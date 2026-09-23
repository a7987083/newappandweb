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
- Target Swift metadata confirms `SoftwareView.featuredSection`, `SoftwareView.appListSection`, `AppRowView`, `FeaturedCardView`, `SectionHeader`, `AppDetailView`, `APIService.fetchApps(page:sortBy:searchQuery:)` and `SortOption`.
- Packaged Simplified Chinese localization confirms first-pass UI labels including `精品软件`, `热门推荐`, `全部软件`, `获取`, `游戏、应用、开发者`, `个人中心`, `我的证书`, `我的游戏` and related empty/authentication states.
- Runtime/device behavior is not yet verified.

## Internal reference baseline

The user's existing project is an implementation reference for reusable engineering patterns, not authoritative evidence for GameStore behavior:

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Release: `v3.0.0-alphaone13`
- Release commit: `76aebadd826156a1b67d175ea90c88371dc320cf`
- Relevant areas: Ksign/Zsign signing integration, `SigningHandler`, `ZsignSwift`, download/import handling, UDID local HTTP service and callback architecture, URL Scheme routing, build/reconstruction CI.
- Reconstruction pins `Nyasami/Ksign@03a3a9c86897d79f9faf8106037b9971841d56a0` plus a canonical patch stack.
- `HFASign/LICENSE` is GPLv3. Do not copy GPL-covered implementation code into this clean-room project without an explicit license decision.

## Phases

### Phase 0 — Bootstrap and compatibility baseline
- [x] Repository initialized and five long-term state documents established.
- [x] Xcode project skeleton and four primary tabs.
- [x] API/UDID/download/signing/OTA service boundaries.
- [x] Product compatibility fixed at iOS 13.0 through iOS 26.x.
- [x] UIKit application bootstrap for iOS 13.
- [x] Dual CI: Xcode 15.4 legacy lane plus Xcode 26.6 modern lane.
- [x] Compatibility baseline green on `10cebcfd3e240b0dc7b802f3ef521c688703cc55`, Run `35800817890`.

### Phase 1 — Protocol recovery
- [~] Recover `/apps/api/app-list/` contract.
  - [x] Target static evidence confirms `fetchApps(page:sortBy:searchQuery:)` and `SortOption`.
  - [x] Target raw strings expose response candidates `items`, `current_page`, `total_pages` plus compatibility candidates `results` / `data`.
  - [x] Decoder now models `items/current_page/total_pages` while retaining fallback envelopes until exact decoder call-site recovery is complete.
  - [ ] Recover exact HTTP method/headers/query key names and exact `App` CodingKeys/types.
  - [ ] Recover exact sort transport values for default/recent/exclusive.
  - [ ] Validate against authorized runtime traffic or fixtures.
- [ ] Reconstruct activation-code workflow.
- [ ] Reconstruct device-certificate workflow.
- [ ] Add protocol fixture tests.

### Phase 2 — Downloads and persistence
- [ ] Background URLSession transfer.
- [ ] Pause/resume/retry/delete.
- [ ] Persistent task recovery.
- [ ] Cache accounting.
- [ ] Use UnitXP alphaone13 `IPADownloadManager` only as a secondary architectural reference.

### Phase 3 — Signing
- [ ] IPA inspector/archive implementation.
- [ ] Certificate import/storage.
- [ ] Zsign bridge.
- [ ] Signature validation.
- [ ] Repack artifact.

### Phase 4 — OTA install
- [ ] Local IPA HTTP server.
- [ ] Manifest generation.
- [ ] localhost/LAN strategy matching verified target behavior.
- [ ] `itms-services` launch and install-progress observation.

### Phase 5 — UI parity
- [x] First target-evidence-driven structural pass for Software, Search and Profile.
- [x] Software home now contains target-observed featured section, all-app list, app row, featured card and detail view boundaries.
- [x] Search copy/empty states and profile copy/sections use packaged target localization evidence.
- [x] First-pass UI remains build-compatible with iOS 13 and iOS 26 SDK lanes on `d48147b9a91475d955395ca4fd43f061e1006119`, Run `35801743955`.
- [ ] Extract visual measurements/assets and perform screenshot comparison.
- [ ] Rebuild activation/certificate/signing-log screens from stronger evidence.
- [ ] Simplified/Traditional Chinese parity.
- [ ] Physical-device screenshot regression comparisons.

## Next Task

Continue Phase 1: recover the exact `/apps/api/app-list/` HTTP method, headers, query parameter names, `SortOption` wire values and `App` model CodingKeys/types from target evidence. In parallel, keep the v0.2 target-driven UI structure compiling in both iOS 13 and iOS 26 lanes. Do not mark visual 1:1 parity until screenshot/runtime comparison exists.
