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
- Target request headers in `fetchApps`: Accept, Accept-Language, Priority, Referer, Sec-Fetch-Dest/Mode/Site, X-Requested-With and target browser User-Agent.

### Exact app-list model recovery
Target response envelope: `data/current_page/total_pages`.

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

Target custom decoder contains `Both app_id and id are missing.`, so the clean-room decoder preserves `id` as an observed fallback for identifier recovery.

### Repository changes
- `GameStore/Networking/APIService.swift`: exact target query/header reconstruction and response result shape.
- `GameStore/Models/AppItem.swift`: target wire schema and normalized UI-facing properties.
- `GameStore/ViewModels/AppStoreViewModel.swift`: sort/pagination state and recovered response envelope.

### Verification status
- Request construction: **static verified from target assembly**.
- Sort mapping: **static verified from enum reflection + buildURL assembly**.
- Model keys/envelope: **static verified from target strings/Swift metadata/decoder evidence**.
- Repository changes: **committed and dual-toolchain build verified**.
- Live server response/content types: **not verified**; current execution environment could not resolve the API hostname.
- Simulator runtime launch: not verified.
- Physical-device UI/network verification: not verified.
- Pixel-perfect visual parity: not verified.

---

## 2026-09-23 — v0.2 unsigned IPA artifact pipeline

### CI packaging implementation
Workflow commit: `76908490c063b7ce6926352bd6e06ab0fcd09cf5`.

Legacy/Xcode 15.4 lane now performs, in addition to the existing iOS 13 simulator build:
- `iphoneos` Debug build with `IPHONEOS_DEPLOYMENT_TARGET=13.0`;
- signing disabled for deterministic CI packaging;
- output collected from `DerivedDataDevice/Build/Products/Debug-iphoneos/GameStore.app`;
- app wrapped as `Payload/GameStore.app`;
- archive created as `GameStore-v0.2-dev-unsigned.ipa`;
- IPA and build logs uploaded as GitHub Actions artifacts.

### Artifact verification
GitHub Actions Run `35823288195`:
- Legacy Job `107059542027`: **success**.
  - iOS 13 simulator build: success.
  - unsigned `iphoneos` device build: success.
  - IPA packaging: success.
  - IPA artifact upload: success.
- Modern Job `107059542322`: **success** — Xcode 26.6 / iOS 26 SDK build.

Artifact:
- Artifact name: `GameStore-v0.2-dev-unsigned-ipa`
- Artifact ID: `10734730203`
- Artifact ZIP digest: `sha256:7e1d9801a9ce8c4d0c64395d5fd7a5f6918f0f848bca9202bdbbbf804950e66d`
- Contained IPA: `GameStore-v0.2-dev-unsigned.ipa`
- IPA SHA-256 after extraction: `df3562b30177a1e379c2a239be5725a56d8cac82412dd713542e81769f210e75`
- Verified IPA contents include `Payload/GameStore.app/GameStore` and `Payload/GameStore.app/Info.plist`.

### Important limitation
The produced package is an **unsigned development IPA**. It is a real `iphoneos` application package suitable for subsequent signing/testing workflows, but it is not a claim that stock iOS devices can install it directly. A signed distribution/development/TrollStore-compatible path remains separate future work.
