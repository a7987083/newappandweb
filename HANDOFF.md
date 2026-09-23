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

## v0.2 target UI / protocol evidence

Static binary + packaged localization evidence now additionally confirms:
- `APIService.fetchApps(page:sortBy:searchQuery:)`
- `SortOption`
- `SoftwareView.featuredSection`
- `SoftwareView.appListSection`
- `AppRowView`, `FeaturedCardView`, `SectionHeader`, `AppDetailView`
- `AppListResponse`
- response/model string candidates including `items`, `current_page`, `total_pages`, `results`, `data`, `page`, `query`, `limit`, `offset`, `app_id`, `bundle_id`, `description`, `download_url`, `exclusive`, `icon`, `iconUrl`, `name`, `screenshots`, `size`, `summary`, `title`, `version`.
- packaged Simplified Chinese copy for featured/all-app/search/profile/auth/certificate/game/settings/about states.

Do **not** infer the exact sort query key or exact `App` model mapping from these strings alone. Runtime traffic or stronger call-site/CodingKeys evidence is still required.

## Current architecture

`UIApplicationDelegate -> UIHostingController -> SwiftUI Views -> AppStoreViewModel -> Service protocols/adapters`

Current v0.2 UI first pass:
- Software home: featured horizontal cards + all-app rows + detail view.
- Search: iOS 13-compatible search field using target packaged copy/empty states.
- Profile: authentication/certificate/games/settings/about sections using target packaged copy.
- Remote app icons use callback-based URLSession and are not a claim of target cache semantics.

Signing remains intentionally unimplemented beyond the recovered interface/state boundary.

## Current Git/build state

- Development branch: `feature/gamestore-v0.2-ui-protocol`
- v0.2 build-verified **code** commit: `d48147b9a91475d955395ca4fd43f061e1006119`
- GitHub Actions Run: `35801743955`
- Modern Job `106993416655`: build against iOS 26 SDK **success**.
- Legacy Job `106993416990`: iOS 13 deployment-target build **success**.
- Runtime launch: not verified.
- Physical-device verification: not performed.
- Pixel parity: not verified.

## v0.2 failure history

Run `35801537255` showed Modern build success but Legacy failure. The first real iOS 13 compiler errors were unguarded iOS 14 SwiftUI APIs introduced in the new UI: `navigationBarTitle(_:displayMode:)` and `InsetGroupedListStyle`. These were removed/replaced with iOS 13-compatible APIs. Subsequent Run `35801743955` successfully compiled both modern and legacy build steps.

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

Continue exact `/apps/api/app-list/` recovery: HTTP method, headers, query key names, `SortOption` wire values, pagination behavior and exact `App` CodingKeys/types. Then add fixture tests. Keep both CI lanes green after compatibility-sensitive changes.

## Handoff rule

Before changing behavior, inspect `PROJECT_STATE.json`, actual branch/HEAD, diff/status where available, `KNOWN_ISSUES.md`, current CI, and target evidence. Update all five long-term state files after meaningful development or verification changes.
