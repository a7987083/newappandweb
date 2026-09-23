# HANDOFF

## Project intent

This repository is a clean-room reimplementation of an authorized GameStore target. Do not treat decompiler pseudocode, strings alone, inferred server behavior, or behavior from other projects as ground truth.

## Product compatibility requirement

- Minimum supported OS: **iOS 13.0**.
- Maximum/current support target: **latest iOS 26.x**.
- Original target minimum remains a separate fact: iOS `15.0`.
- Legacy compile validation: Xcode 15.4 / deployment target iOS 13.0.
- Modern SDK validation: Xcode 26.6 / iOS 26 SDK.

## Verified target baseline

- Main executable SHA-256: `ea4947e192da53ceae434e51108c9af49f6a99d80c9d5e6e7e0d2ac5e6324e4e`
- Bundle id: `com.GameStore.maicha`
- Version: `1.2 (1)`
- URL scheme: `gamestore`
- API base: `https://new.iosgame.vip`
- Known endpoints include `/apps/api/app-list/`, activation/certificate/download/manifest paths and device UDID paths.
- Install prefix: `itms-services://?action=download-manifest&url=`.

## v0.2 UI evidence

Static binary + packaged localization evidence confirms `SoftwareView.featuredSection`, `SoftwareView.appListSection`, `AppRowView`, `FeaturedCardView`, `SectionHeader`, `AppDetailView`, plus the first-pass Software/Search/Profile labels/states. The current UI implements this structure but is not yet pixel/runtime verified.

## app-list protocol — current exact static recovery

Target function:
`APIService.fetchApps(page:sortBy:searchQuery:) -> AnyPublisher<AppListResponse, Error>`

Target private URL builder uses:
- `/apps/api/app-list/`
- `page_number=<page>`
- `sort_by=<mapped sort>`
- `platform=ios`
- `_` = Unix epoch milliseconds
- optional `search_query=<query>`

`SortOption` case order and backend values:
- `recent -> updated_at`
- `exclusive -> exclusive`
- `default -> id`

Target `fetchApps` constructs a GET `URLRequest`, sets browser-like headers, sends with URLSession, and decodes `AppListResponse`.

Recovered response envelope:
- `data: [GameApp]`
- `current_page`
- `total_pages`

Recovered GameApp wire keys:
`app_id`, `app_name`, `mod_description`, `icon`, `store_url`, `appstore_url`, `package_name`, `current_version`, `app_version`, `mod_update_time`, `file_size`, `screenshots`, `alist_url`, `is_permanent_vip_only`, `is_hot`.

Target decoder also contains `Both app_id and id are missing.`, establishing an observed identifier fallback to `id`.

Important limitation: the request/model reconstruction is **static verified**, not live-server verified. The current execution environment could not resolve `new.iosgame.vip`, so do not claim network interoperability until traffic/fixtures or device runtime confirms it.

## Current architecture

`UIApplicationDelegate -> UIHostingController -> SwiftUI Views -> AppStoreViewModel -> Service protocols/adapters`

`APIService` is intentionally callback-based in the clean-room implementation for iOS 13 compatibility even though the target binary uses Combine. The protocol semantics are reconstructed; the implementation mechanism may differ where necessary for the expanded OS floor.

## Current Git/build/artifact state

- Development branch: `feature/gamestore-v0.2-ui-protocol`
- Exact app-list protocol **code** commit: `299c5bb94d9a7af4cff84673e8dcbd36b16971e4`
- IPA packaging workflow commit: `76908490c063b7ce6926352bd6e06ab0fcd09cf5`
- Artifact CI Run: `35823288195`
- Legacy Job `107059542027`: **success**.
  - iOS 13 simulator build: success.
  - Xcode 15.4 `iphoneos` unsigned device build: success.
  - IPA package/upload: success.
- Modern Job `107059542322`: **success** — Xcode 26.6 / iOS 26 SDK.
- GitHub Artifact: `GameStore-v0.2-dev-unsigned-ipa`, ID `10734730203`.
- Contained file: `GameStore-v0.2-dev-unsigned.ipa`.
- IPA SHA-256: `df3562b30177a1e379c2a239be5725a56d8cac82412dd713542e81769f210e75`.
- Verified archive structure: `Payload/GameStore.app` with main executable and `Info.plist`.
- Signing state: **unsigned**.
- Runtime launch: not verified.
- Physical-device verification: not performed.
- Pixel parity: not verified.

Do not describe the unsigned IPA as directly installable on stock iOS. It is a real device-architecture IPA artifact intended for subsequent signing/testing. Signing/distribution policy remains separate from packaging success.

## Failure history

Initial v0.2 UI Run `35801537255` exposed unguarded iOS 14 SwiftUI APIs (`navigationBarTitle(_:displayMode:)`, `InsetGroupedListStyle`). They were replaced with iOS 13-compatible paths. Subsequent UI, protocol and packaging runs are green.

## Vetted internal reference project

- `a7987083/UnitXP_SP3-Moonstone`
- Release `v3.0.0-alphaone13`
- Commit `76aebadd826156a1b67d175ea90c88371dc320cf`
- Reference-only areas: signing, download/import, UDID local server/callback, URL Scheme, deterministic reconstruction.
- `HFASign/LICENSE` is GPLv3. Do not directly copy GPL-covered implementation code without an explicit licensing decision.

## Evidence policy

Every important conclusion must be marked as one of:
- static verified
- automated verified
- build verified
- runtime verified
- physical-device verified
- unverified/inferred

Reference-project behavior is `reference-only` unless independently matched to GameStore evidence.

## Next task

1. Add deterministic protocol fixtures for the recovered app-list schema/request mapping.
2. Continue Phase 1 on `/activation/my-games/`, `/activation/device-certificates/` and `/activation/ios-download/`.
3. Keep both legacy and modern CI lanes green.
4. Preserve the unsigned IPA artifact pipeline on each meaningful build.
5. Add a signed installation path only after certificate/signing behavior and distribution expectations are explicitly defined and verified.

## Handoff rule

Before changing behavior, inspect `PROJECT_STATE.json`, actual branch/HEAD, diff/status where available, `KNOWN_ISSUES.md`, current CI, and target evidence. Update all five long-term state files after meaningful development or verification changes.
