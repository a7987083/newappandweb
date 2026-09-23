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
- [x] CI device packaging lane builds `iphoneos` with Xcode 15.4 and creates `GameStore-v0.2-dev-unsigned.ipa`.
- [x] Artifact pipeline verified on workflow commit `76908490c063b7ce6926352bd6e06ab0fcd09cf5`, Run `35823288195`.
- [x] Verified IPA structure contains `Payload/GameStore.app`; IPA SHA-256 `df3562b30177a1e379c2a239be5725a56d8cac82412dd713542e81769f210e75`.
- [ ] Add a signed/release packaging path after the certificate/signing policy is defined; current artifact is intentionally unsigned.

### Phase 1 — Protocol recovery
- [~] Recover `/apps/api/app-list/` contract.
  - [x] Exact function signature recovered: `fetchApps(page:sortBy:searchQuery:)`.
  - [x] Request method recovered as `GET` using `URLRequest` + `URLSession.DataTaskPublisher` in the target.
  - [x] Exact query keys recovered from `buildURL`: `page_number`, `sort_by`, `platform=ios`, `_` millisecond timestamp, optional `search_query`.
  - [x] `SortOption` enum order and transport mapping recovered: `recent -> updated_at`, `exclusive -> exclusive`, `default -> id`.
  - [x] Target fetch headers recovered: Accept, Accept-Language, Priority, Referer, Sec-Fetch-Dest/Mode/Site, X-Requested-With and User-Agent.
  - [x] Response envelope recovered as `data/current_page/total_pages`.
  - [x] Target app wire keys recovered: `app_id`, `app_name`, `mod_description`, `icon`, `store_url`, `appstore_url`, `package_name`, `current_version`, `app_version`, `mod_update_time`, `file_size`, `screenshots`, `alist_url`, `is_permanent_vip_only`, `is_hot`, with target fallback evidence for `id`.
  - [x] Repository implementation updated to these static-verified request/model contracts.
  - [x] Dual CI green on protocol code commit `299c5bb94d9a7af4cff84673e8dcbd36b16971e4`, Run `35802424891`.
  - [ ] Validate live server response types/semantics against authorized traffic or fixtures; current environment could not resolve the public API hostname.
  - [ ] Add protocol fixture tests.
- [ ] Reconstruct activation-code workflow.
- [ ] Reconstruct device-certificate workflow.

### Phase 2 — Downloads and persistence
- [ ] Background URLSession transfer.
- [ ] Pause/resume/retry/delete.
- [ ] Persistent task recovery.
- [ ] Cache accounting.

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
- [x] Software home contains target-observed featured section, all-app list, app row, featured card and detail view boundaries.
- [x] Search copy/empty states and profile copy/sections use packaged target localization evidence.
- [x] First-pass UI remains build-compatible with iOS 13 and iOS 26 SDK lanes.
- [ ] Extract visual measurements/assets and perform screenshot comparison.
- [ ] Rebuild activation/certificate/signing-log screens from stronger evidence.
- [ ] Simplified/Traditional Chinese parity.
- [ ] Physical-device screenshot regression comparisons.

## Next Task

Add deterministic app-list protocol fixtures and then continue Phase 1 with `/activation/my-games/`, `/activation/device-certificates/` and `/activation/ios-download/`, using the same rule: static assembly/CodingKeys first, runtime confirmation second, and keep both iOS 13 and iOS 26 CI lanes green. The downloadable CI IPA remains an unsigned development artifact until signing is implemented and verified.
