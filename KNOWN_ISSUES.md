# KNOWN_ISSUES

## KI-001 — Exact API schema not recovered
**Status:** Open  
**Evidence:** Static endpoint strings only; v0.1 decoder accepts several common envelope keys.  
**Risk:** Server payload may use different keys/types or methods/headers.  
**Next verification:** Recover Swift `CodingKeys`/decoder call sites or capture authorized traffic.

## KI-002 — Signing implementation intentionally absent
**Status:** Open  
**Evidence:** Target contains Zsign/signing state evidence, but v0.1 only defines the interface/state machine. UnitXP alphaone13 provides a vetted secondary implementation reference for Ksign/Zsign and ZsignSwift integration.  
**Risk:** No IPA can be signed by this build; copying UnitXP/Ksign behavior without target verification could also produce a functionally different pipeline.  
**Next verification:** Recover exact GameStore bridge ABI and packaging pipeline, then compare invariants against UnitXP alphaone13 before independent implementation.

## KI-003 — Download center is state-only
**Status:** Open  
**Evidence:** v0.1 has queue models but no background `URLSession` transfer. UnitXP alphaone13 demonstrates filename-collision handling, auto-import and optional post-import deletion.  
**Risk:** Download UI does not perform target behavior yet; UnitXP behavior is reference-only and may differ from GameStore persistence/session semantics.  
**Next verification:** Recover target session configuration and persistence semantics, then reuse only compatible design patterns.

## KI-004 — OTA local HTTP server absent
**Status:** Open  
**Evidence:** Target contains localhost/127.0.0.1 and `itms-services` evidence. UnitXP alphaone13 has a validated local HTTP/UDID service lifecycle and custom URL callback design, but this does not prove GameStore OTA server behavior.  
**Risk:** OTA launcher can only consume an already-hosted manifest.  
**Next verification:** Recover target manifest format, port selection and local-server lifetime; compare lifecycle mechanics with UnitXP as secondary reference.

## KI-005 — UI is architectural parity, not pixel parity
**Status:** Open  
**Evidence:** Text/navigation names are based on packaged localization and module names; detailed visual measurements have not been reproduced.  
**Risk:** v0.1 appearance differs from target.  
**Next verification:** Build screenshot inventory and compare each screen on the same device class.

## KI-006 — No runtime/device verification yet
**Status:** Open  
**Evidence:** CI successfully compiles implementation commit `0ad791c9bc1abd544ee19303684d459b0470f6c7`; no simulator launch or physical-device test has been recorded.  
**Risk:** Compile success does not prove endpoint compatibility, URL callback behavior, signing, download persistence or OTA installation.  
**Next verification:** Add a simulator smoke test for app launch, then perform authorized physical-device verification for UDID and OTA flows when those implementations are complete.

## KI-007 — GPL boundary for UnitXP/Ksign reference
**Status:** Open / Controlled  
**Evidence:** `UnitXP_SP3-Moonstone/HFASign/LICENSE` is GNU GPL v3.  
**Risk:** Directly copying GPL-covered implementation code into GameStore can impose GPL distribution/source obligations on the derivative work.  
**Mitigation:** Treat UnitXP alphaone13 as a secondary architectural/behavioral reference; independently implement GameStore modules from target evidence unless the project explicitly chooses GPL-compatible licensing. Record any future direct code reuse with file-level provenance and license review.

## KI-008 — Reference-project behavior can be mistaken for GameStore evidence
**Status:** Open / Controlled  
**Evidence:** UnitXP alphaone13 contains useful signing, download, UDID and URL Scheme implementations, but it is a different application based on Ksign.  
**Risk:** Porting constants, ports, callback formats, persistence keys or UI behavior blindly could create false parity.  
**Mitigation:** Mark all UnitXP-derived conclusions `reference-only` until independently matched against GameStore static/runtime evidence.

## KI-009 — iOS 13–26 product compatibility is not yet verified
**Status:** Open  
**Evidence:** Product requirement is minimum iOS 13.0 through latest iOS 26.x. The only successful GameStore build so far used Xcode 16.4 with deployment target iOS 15.0. Apple lists Xcode 15.4 as supporting deployment targets down to iOS 12, while Xcode 26.x targets iOS 15+ and provides iOS 26 SDK coverage.  
**Risk:** Current source may use APIs unavailable on iOS 13, and a single modern toolchain cannot validate both the legacy deployment floor and latest iOS 26 SDK behavior.  
**Next verification:** Lower project deployment target to 13.0, run an availability audit, add Xcode 15.4 legacy CI plus Xcode 26.x modern CI, then perform representative runtime/device checks across legacy and modern systems.
