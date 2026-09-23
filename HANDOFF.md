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

Target `fetchApps` constructs a GET `URLRequest`, sets browser-like Accept/Accept-Language/Priority/Referer/Sec-Fetch/X-Requested-With/User-Agent headers, sends it with URLSession `dataTaskPublisher`, maps response data, decodes `AppListResponse` with `JSONDecoder`, maps errors, receives on the main queue and erases to AnyPublisher.

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

`APIService` is intentionally callback-based in the clean-room implementation for iOS 13 compatibility even though the target binary uses Combine. The protocol semantics are reconstructed; the implementation mechanism is allowed to differ where necessary for the expanded OS floor.

## Current Git/build state

- Development branch: `feature/gamestore-v0.2-ui-protocol`
- Exact app-list protocol **code** commit: `299c5bb94d9a7af4cff84673e8dcbd36b16971e4`
- GitHub Actions Run: `35802424891`
- Legacy Job `106995546259`: **success** — Xcode 15.4 / iOS 13 deployment target.
- Modern Job `106995546336`: **success** — Xcode 26.6 / iOS 26 SDK.
- Runtime launch: not verified.
- Physical-device verification: not performed.
- Pixel parity: not verified.

## Failure history

Initial v0.2 UI Run `35801537255` exposed unguarded iOS 14 SwiftUI APIs (`navigationBarTitle(_:displayMode:)`, `InsetGroupedListStyle`). They were replaced with iOS 13-compatible paths. Subsequent UI and protocol runs are dual-build green.

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
2. Continue Phase 1 on `/activation/my-games/`, `/activation/device-certificates/` and `/activation/ios-download/` by recovering their exact request methods, headers, bodies/query parameters and response CodingKeys.
3. Keep both legacy and modern CI lanes green.
4. Do not upgrade static recovery claims to runtime/live-server claims without direct evidence.

## Handoff rule

Before changing behavior, inspect `PROJECT_STATE.json`, actual branch/HEAD, diff/status where available, `KNOWN_ISSUES.md`, current CI, and target evidence. Update all five long-term state files after meaningful development or verification changes.
