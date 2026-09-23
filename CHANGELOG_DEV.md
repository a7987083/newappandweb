# CHANGELOG_DEV

## 2026-09-23 — v0.1 bootstrap

### Repository / compatibility baseline
- Repository: `a7987083/newappandweb`
- Baseline branch: `main`
- Initial development branch: `feature/gamestore-v0.1-bootstrap`
- iOS 13–26 compatibility build-verified commit: `10cebcfd3e240b0dc7b802f3ef521c688703cc55`
- Dual-CI Run `35800817890`: Legacy Job `106990507365` success; Modern Job `106990507207` success.
- Product support baseline: iOS 13.0 through latest iOS 26.x.
- Runtime/device verification remains open.

### Reference baseline
- `a7987083/UnitXP_SP3-Moonstone` release `v3.0.0-alphaone13`, commit `76aebadd826156a1b67d175ea90c88371dc320cf` is secondary implementation reference only.
- `HFASign/LICENSE` is GPLv3; no GPL-covered implementation code is copied into GameStore without an explicit license decision.

---

## 2026-09-23 — v0.2 target-driven UI / app-list recovery

### Branch
- Development branch: `feature/gamestore-v0.2-ui-protocol`
- Branch created from v0.1 documentation HEAD `6afa2aae7aea564ec2e00ab22243fe49d9f3bf66`.
- Build-verified v0.2 code commit: `d48147b9a91475d955395ca4fd43f061e1006119`.

### Target evidence recovered
Static inspection of the target GameStore binary and packaged localization confirmed:
- `GameStore.APIService.fetchApps(page:sortBy:searchQuery:)`
- `GameStore.SortOption`
- `SoftwareView.featuredSection`
- `SoftwareView.appListSection`
- `AppRowView`
- `FeaturedCardView`
- `SectionHeader`
- `AppDetailView`
- `AppListResponse`
- localized UI strings such as `精品软件`, `热门推荐`, `全部软件`, `获取`, `游戏、应用、开发者`, `未找到相关内容`, `个人中心`, `我的证书`, `我的游戏`.
- raw protocol/model strings include `items`, `current_page`, `total_pages`, `results`, `data`, `page`, `query`, `limit`, `offset`, plus item-field candidates such as `app_id`, `bundle_id`, `description`, `download_url`, `exclusive`, `icon`, `iconUrl`, `name`, `screenshots`, `size`, `summary`, `title`, `version`.

These are static facts/candidates only. Exact HTTP method, headers, sort query key/wire values and complete `App` CodingKeys are not yet runtime-verified.

### UI implementation
Changed `SoftwareView.swift`, `SearchView.swift`, `ProfileView.swift`, and `AppStoreViewModel.swift`:
- Rebuilt Software home from a plain list to a target-structure first pass with horizontal featured cards plus all-app rows.
- Added `FeaturedCardView`, `AppRowView`, `SectionHeader` and richer `AppDetailView` boundaries matching preserved target type names.
- Added iOS 13-compatible remote icon loading and UIKit activity indicator.
- Rebuilt Search with packaged target placeholder/empty-state copy while avoiding `.searchable`.
- Rebuilt Profile sections from packaged target localization: authentication state, certificate/game/settings/about rows.
- Added `featuredApps` derivation in the view model and expanded local search matching to summary/developer.

### Protocol implementation
Changed `AppItem.swift`:
- `AppListResponse` now accepts target-observed `items` and pagination fields `current_page` / `total_pages`.
- Existing `apps` / `results` / `data` fallbacks are retained temporarily because exact decoder behavior has not yet been recovered.
- No claim is made that the current `AppItem` field mapping is exact.

### CI failure and root-cause repair
Initial v0.2 UI Run `35801537255` had:
- Modern iOS 26 lane: build succeeded.
- Legacy iOS 13 lane Job `106992759519`: failed.

First real legacy errors from Xcode 15.4 were:
- `SoftwareView.swift`: `navigationBarTitle(_:displayMode:)` requires iOS 14+.
- `ProfileView.swift`: `InsetGroupedListStyle` requires iOS 14+.
- `ProfileView.swift`: additional `navigationBarTitle(_:displayMode:)` usage requires iOS 14+.

Root-cause fix:
- Removed `displayMode:` title overloads from new screens.
- Replaced `InsetGroupedListStyle` with iOS 13-compatible `GroupedListStyle`.
- Audited Search title path at the same time instead of waiting for a second compiler failure.

### v0.2 build verification
GitHub Actions Run `35801743955` on code commit `d48147b9a91475d955395ca4fd43f061e1006119`:
- Modern Job `106993416655`: **Build GameStore against iOS 26 SDK — success**.
- Legacy Job `106993416990`: **Build GameStore for iOS 13 deployment target — success**.

### Verification status
- Target UI/type/localization evidence: static verified.
- v0.2 source modifications: committed.
- iOS 13 compile: build verified in CI.
- iOS 26 SDK compile: build verified in CI.
- App-list network contract: partially recovered / static only.
- Simulator runtime launch: not verified.
- Physical-device UI parity: not verified.
- Pixel-perfect visual parity: not verified.
- Full regression matrix: not verified.
