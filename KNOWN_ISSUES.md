# KNOWN_ISSUES

## KI-001 — Exact app-list API contract not fully recovered
**Status:** Open / Partially recovered  
**Evidence:** Target static evidence confirms `APIService.fetchApps(page:sortBy:searchQuery:)`, `SortOption`, `AppListResponse`, and raw response/model strings including `items`, `current_page`, `total_pages`, `results`, `data`, `page`, `query`, `limit`, `offset` plus multiple item-field candidates. v0.2 decoder now supports `items/current_page/total_pages` while retaining fallback envelopes.  
**Risk:** Current HTTP method, headers, exact query key names, sort wire values and `AppItem` CodingKeys/types may differ from the target.  
**Next verification:** Recover call sites/CodingKeys or capture authorized traffic; then add exact protocol fixtures and remove unsupported fallback assumptions.

## KI-002 — Signing implementation intentionally absent
**Status:** Open  
**Evidence:** Target contains Zsign/signing state evidence, but current code only defines the interface/state machine. UnitXP alphaone13 is reference-only.  
**Risk:** No IPA can be signed by this build.  
**Next verification:** Recover exact GameStore bridge ABI and packaging pipeline before independent implementation.

## KI-003 — Download center is state-only
**Status:** Open  
**Evidence:** Current code has queue models but no target-compatible background transfer/persistence.  
**Risk:** Download UI does not perform target behavior yet.  
**Next verification:** Recover target session configuration/persistence semantics; use UnitXP only as secondary architectural reference.

## KI-004 — OTA local HTTP server absent
**Status:** Open  
**Evidence:** Target contains localhost/127.0.0.1 and `itms-services` evidence, but local server/manifest generation are not implemented.  
**Risk:** OTA launcher cannot reproduce the full target install path.  
**Next verification:** Recover manifest format, port selection and server lifetime.

## KI-005 — UI structural parity is not pixel parity
**Status:** Open / Improved in v0.2  
**Evidence:** Target Swift metadata and packaged localization now drive Software/Search/Profile structure. v0.2 implements target-observed featured section, all-app section, app row, featured card, detail view and localized profile/search copy. No screenshot measurement or runtime comparison has been performed.  
**Risk:** Spacing, typography, sizing, colors, assets, animation and navigation behavior can still differ materially from the target.  
**Next verification:** Build a target screenshot inventory on matching device classes and perform screen-by-screen comparison.

## KI-006 — No runtime/device verification yet
**Status:** Open  
**Evidence:** v0.2 code commit `d48147b9a91475d955395ca4fd43f061e1006119` successfully completes both modern iOS 26 SDK and legacy iOS 13 build steps in Run `35801743955`. No simulator launch or physical-device validation has been recorded.  
**Risk:** Compile success does not prove UI rendering, endpoint compatibility, callback behavior, download persistence, signing or OTA installation.  
**Next verification:** Add simulator smoke launch coverage and later physical-device verification.

## KI-007 — GPL boundary for UnitXP/Ksign reference
**Status:** Open / Controlled  
**Evidence:** `UnitXP_SP3-Moonstone/HFASign/LICENSE` is GNU GPL v3.  
**Risk:** Direct reuse can impose GPL obligations.  
**Mitigation:** Treat UnitXP as secondary architecture/behavior reference and implement GameStore modules independently unless an explicit GPL-compatible licensing decision is made.

## KI-008 — Reference-project behavior can be mistaken for GameStore evidence
**Status:** Open / Controlled  
**Evidence:** UnitXP alphaone13 is a different Ksign-based application.  
**Risk:** Blindly ported constants, ports, callbacks, persistence keys or UI behavior can create false parity.  
**Mitigation:** Mark all UnitXP-derived conclusions `reference-only` until independently matched to GameStore evidence.

## KI-009 — iOS 13–26 build compatibility vs runtime compatibility
**Status:** Build baseline verified / Runtime open  
**Evidence:** v0.1 compatibility Run `35800817890` and v0.2 UI Run `35801743955` both establish successful legacy iOS 13 and modern iOS 26 SDK build steps after compatibility fixes.  
**Risk:** Building at both edges does not prove every runtime version behaves correctly.  
**Next verification:** Establish representative runtime/device coverage across legacy, middle and current OS generations.

## KI-010 — Hosted legacy CI runner lifecycle
**Status:** Open / Infrastructure risk  
**Evidence:** Legacy validation depends on GitHub-hosted `macos-14` with Xcode 15.4.  
**Risk:** Future hosted-runner/toolchain retirement can break reproducible legacy verification.  
**Mitigation:** Preserve a pinned/self-hosted legacy Xcode 15.4 environment before hosted availability disappears.

## KI-011 — v0.2 iOS 13 regression history
**Status:** Resolved for current code / Keep as regression sentinel  
**Evidence:** Initial v0.2 UI introduced `navigationBarTitle(_:displayMode:)` and `InsetGroupedListStyle`, which compile on modern SDKs but are iOS 14+. Legacy Job `106992759519` exposed the issue. Commit chain ending at `d48147b9a91475d955395ca4fd43f061e1006119` replaced these with iOS 13-compatible APIs and the Legacy build step succeeded.  
**Risk:** Future visual-parity work may accidentally reintroduce newer SwiftUI APIs.  
**Mitigation:** Keep the Xcode 15.4/iOS 13 lane mandatory for compatibility-sensitive changes.
