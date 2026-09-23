# KNOWN_ISSUES

## KI-001 — Exact API schema not recovered
**Status:** Open  
**Evidence:** Static endpoint strings only; v0.1 decoder still accepts several common envelope keys.  
**Risk:** Server payload may use different keys/types or methods/headers.  
**Next verification:** Recover Swift `CodingKeys`/decoder call sites or capture authorized traffic.

## KI-002 — Signing implementation intentionally absent
**Status:** Open  
**Evidence:** Target contains Zsign/signing state evidence, but v0.1 only defines the interface/state machine. UnitXP alphaone13 provides a vetted secondary implementation reference for Ksign/Zsign and ZsignSwift integration.  
**Risk:** No IPA can be signed by this build; blindly copying UnitXP/Ksign behavior could produce a functionally different pipeline.  
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
**Evidence:** Commit `10cebcfd3e240b0dc7b802f3ef521c688703cc55` compiles successfully in both the iOS 13/Xcode 15.4 and iOS 26/Xcode 26.6 CI lanes. No simulator launch on a legacy runtime or physical-device test has been recorded.  
**Risk:** Compile success does not prove endpoint compatibility, URL callback behavior, signing, download persistence or OTA installation.  
**Next verification:** Add representative simulator/runtime smoke tests and later perform authorized physical-device verification for UDID, signing and OTA flows.

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

## KI-009 — iOS 13–26 build compatibility vs runtime compatibility
**Status:** Build baseline verified / Runtime open  
**Evidence:** GitHub Actions Run `35800817890` passed both Legacy Job `106990507365` (Xcode 15.4, deployment target 13.0) and Modern Job `106990507207` (Xcode 26.6/iOS 26 SDK lane) on commit `10cebcfd3e240b0dc7b802f3ef521c688703cc55`.  
**Risk:** Building at the iOS 13 floor and against the latest SDK does not prove every runtime version from iOS 13 through iOS 26 behaves correctly.  
**Next verification:** Establish representative runtime/device coverage across legacy, middle and current OS generations as functionality becomes real.

## KI-010 — Hosted legacy CI runner lifecycle
**Status:** Open / Infrastructure risk  
**Evidence:** The legacy lane currently depends on GitHub-hosted `macos-14` to obtain Xcode 15.4. GitHub runner images evolve and older images/toolchains are eventually retired.  
**Risk:** A future hosted-runner retirement can break legacy build verification even when source compatibility is unchanged.  
**Mitigation:** Before hosted `macos-14` becomes unavailable, move the Xcode 15.4 lane to a pinned/self-hosted macOS runner or another reproducible legacy toolchain environment.
