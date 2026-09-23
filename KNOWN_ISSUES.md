# KNOWN_ISSUES

## KI-001 — App-list static contract recovered; live response semantics still unverified
**Status:** Open / Narrowed substantially  
**Evidence:** Target assembly/Swift metadata now recovers GET request construction, exact query keys (`page_number`, `sort_by`, `platform`, `_`, optional `search_query`), sort mapping (`recent -> updated_at`, `exclusive -> exclusive`, `default -> id`), target browser-style headers, response envelope (`data/current_page/total_pages`) and GameApp wire keys (`app_id`, `app_name`, `mod_description`, `icon`, `store_url`, `appstore_url`, `package_name`, `current_version`, `app_version`, `mod_update_time`, `file_size`, `screenshots`, `alist_url`, `is_permanent_vip_only`, `is_hot`). Target decoder evidence also contains `Both app_id and id are missing.`.  
**Implemented:** Protocol code commit `299c5bb94d9a7af4cff84673e8dcbd36b16971e4`, dual-CI Run `35802424891` green.  
**Remaining risk:** Static evidence does not prove current production server field types, nullability, pagination edge cases or continued header requirements. Current execution environment could not resolve `new.iosgame.vip`, so no live payload was captured.  
**Next verification:** Add deterministic fixtures from authorized traffic or a known-good payload; validate field types/nullability and pagination; then reduce flexible decoder coercions where evidence permits.

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
**Evidence:** Target Swift metadata and packaged localization drive Software/Search/Profile structure. No screenshot measurement or runtime comparison has been performed.  
**Risk:** Spacing, typography, sizing, colors, assets, animation and navigation behavior can still differ materially from the target.  
**Next verification:** Build a target screenshot inventory on matching device classes and perform screen-by-screen comparison.

## KI-006 — No runtime/device verification yet
**Status:** Open  
**Evidence:** App-list protocol code commit `299c5bb94d9a7af4cff84673e8dcbd36b16971e4` passes Legacy Job `106995546259` and Modern Job `106995546336` in Run `35802424891`. No simulator launch or physical-device validation has been recorded.  
**Risk:** Compile success does not prove UI rendering, endpoint interoperability, callback behavior, download persistence, signing or OTA installation.  
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
**Evidence:** v0.1 compatibility Run `35800817890`, v0.2 UI Run `35801743955` and protocol Run `35802424891` establish successful legacy iOS 13 and modern iOS 26 SDK builds after compatibility fixes.  
**Risk:** Building at both edges does not prove every runtime version behaves correctly.  
**Next verification:** Establish representative runtime/device coverage across legacy, middle and current OS generations.

## KI-010 — Hosted legacy CI runner lifecycle
**Status:** Open / Infrastructure risk  
**Evidence:** Legacy validation depends on GitHub-hosted `macos-14` with Xcode 15.4.  
**Risk:** Future hosted-runner/toolchain retirement can break reproducible legacy verification.  
**Mitigation:** Preserve a pinned/self-hosted legacy Xcode 15.4 environment before hosted availability disappears.

## KI-011 — v0.2 iOS 13 regression history
**Status:** Resolved for current code / Keep as regression sentinel  
**Evidence:** Initial v0.2 UI introduced `navigationBarTitle(_:displayMode:)` and `InsetGroupedListStyle`, which compile on modern SDKs but are iOS 14+. Legacy CI exposed the issue and current code uses iOS 13-compatible alternatives.  
**Risk:** Future visual-parity work may accidentally reintroduce newer SwiftUI APIs.  
**Mitigation:** Keep the Xcode 15.4/iOS 13 lane mandatory for compatibility-sensitive changes.

## KI-012 — Activation/certificate/download API contracts remain incomplete
**Status:** Open  
**Evidence:** Target strings/symbols confirm `/activation/my-games/`, `/activation/device-certificates/`, `/activation/ios-download/` and corresponding APIService methods, but their exact body/query schema and response CodingKeys have not yet been reconstructed to the same confidence as app-list.  
**Risk:** My Games, certificate import and activation-code download cannot claim target protocol compatibility yet.  
**Next verification:** Disassemble each target APIService method and recover request/response models before implementing behavior.
