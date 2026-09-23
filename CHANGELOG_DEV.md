# CHANGELOG_DEV

## 2026-09-23 — v0.1 bootstrap

### Repository / compatibility baseline
- Repository: `a7987083/newappandweb`
- Baseline branch: `main`
- Initial development branch: `feature/gamestore-v0.1-bootstrap`
- iOS 13–26 compatibility build-verified commit: `10cebcfd3e240b0dc7b802f3ef521c688703cc55`
- Dual-CI Run `35800817890`: Legacy Job `106990507365` success; Modern Job `106990507207` success.
- Product support baseline: iOS 13.0 through latest iOS 26.x.

---

## 2026-09-23 — v0.2 target-driven UI / app-list recovery

### Branch / build
- Development branch: `feature/gamestore-v0.2-ui-protocol`
- First UI build-verified code commit: `d48147b9a91475d955395ca4fd43f061e1006119`.
- Exact app-list protocol implementation code commit: `299c5bb94d9a7af4cff84673e8dcbd36b16971e4`.
- Protocol CI Run `35802424891`:
  - Legacy Job `106995546259`: **success** — Xcode 15.4 / iOS 13 deployment target.
  - Modern Job `106995546336`: **success** — Xcode 26.6 / iOS 26 SDK lane.

### Target UI evidence / implementation
Static inspection and packaged localization confirmed `SoftwareView.featuredSection`, `SoftwareView.appListSection`, `AppRowView`, `FeaturedCardView`, `SectionHeader`, `AppDetailView`, plus the first-pass Software/Search/Profile labels and states. The repository implements the corresponding structural UI while retaining iOS 13-compatible SwiftUI APIs.

### Exact app-list request recovery
Disassembly of target `APIService.fetchApps(page:sortBy:searchQuery:)` and private `buildURL` recovered:
- HTTP method: `GET`.
- Endpoint: `/apps/api/app-list/` on `https://new.iosgame.vip`.
- Query keys: `page_number`, `sort_by`, `platform`, `_`, optional `search_query`.
- `platform` value: `ios`.
- `_` value: integer Unix epoch milliseconds generated from `Date().timeIntervalSince1970 * 1000`.
- `SortOption` reflected enum order: `recent`, `exclusive`, `default`.
- Backend sort mapping in `buildURL`:
  - `recent -> updated_at`
  - `exclusive -> exclusive`
  - `default -> id`
- Target request headers in `fetchApps`:
  - `Accept: application/json, text/javascript, */*; q=0.01`
  - `Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6`
  - `Priority: u=1, i`
  - `Referer: https://www.iosgame.tech/apps/applist/`
  - `Sec-Fetch-Dest: empty`
  - `Sec-Fetch-Mode: cors`
  - `Sec-Fetch-Site: same-origin`
  - `X-Requested-With: XMLHttpRequest`
  - Chrome/macOS User-Agent preserved by the target.

### Exact app-list model recovery
Target wire-key region and Swift metadata recover the response envelope as:
- `data`
- `current_page`
- `total_pages`

Target GameApp wire keys recovered:
- `app_id`
- `app_name`
- `mod_description`
- `icon`
- `store_url`
- `appstore_url`
- `package_name`
- `current_version`
- `app_version`
- `mod_update_time`
- `file_size`
- `screenshots`
- `alist_url`
- `is_permanent_vip_only`
- `is_hot`

Target custom decoder contains the diagnostic `Both app_id and id are missing.`, so the clean-room decoder preserves `id` as an observed fallback for identifier recovery.

### Repository changes
- `GameStore/Networking/APIService.swift`
  - added `SortOption` and exact target query/header reconstruction;
  - changed app-list client result from bare array to `AppListResponse`;
  - removed guessed direct-array/fallback-envelope behavior for this endpoint.
- `GameStore/Models/AppItem.swift`
  - replaced guessed generic app keys with target wire schema;
  - added normalized UI-facing computed properties to avoid leaking wire names into views;
  - response envelope now uses `data/current_page/total_pages`.
- `GameStore/ViewModels/AppStoreViewModel.swift`
  - now tracks sort and pagination state;
  - consumes the recovered response envelope;
  - prefers `is_hot` items for the featured strip when present.

### Verification status
- Request construction: **static verified from target assembly**.
- Sort mapping: **static verified from enum reflection + buildURL assembly**.
- Model keys/envelope: **static verified from target strings/Swift metadata/decoder evidence**.
- Repository changes: **committed and dual-toolchain build verified**.
- Live server response/content types: **not verified**; the current execution environment could not resolve the API hostname.
- Simulator runtime launch: not verified.
- Physical-device UI/network verification: not verified.
- Pixel-perfect visual parity: not verified.
