# KNOWN_ISSUES

## KI-001 — Exact API schema not recovered
**Status:** Open  
**Evidence:** Static endpoint strings only; v0.1 decoder accepts several common envelope keys.  
**Risk:** Server payload may use different keys/types or methods/headers.  
**Next verification:** Recover Swift `CodingKeys`/decoder call sites or capture authorized traffic.

## KI-002 — Signing implementation intentionally absent
**Status:** Open  
**Evidence:** Target contains Zsign/signing state evidence, but v0.1 only defines the interface/state machine.  
**Risk:** No IPA can be signed by this build.  
**Next verification:** Recover exact bridge ABI and packaging pipeline before implementation.

## KI-003 — Download center is state-only
**Status:** Open  
**Evidence:** v0.1 has queue models but no background `URLSession` transfer.  
**Risk:** Download UI does not perform target behavior yet.  
**Next verification:** Recover target session configuration and persistence semantics.

## KI-004 — OTA local HTTP server absent
**Status:** Open  
**Evidence:** Target contains localhost/127.0.0.1 and `itms-services` evidence.  
**Risk:** OTA launcher can only consume an already-hosted manifest.  
**Next verification:** Recover target manifest format, port selection and local-server lifetime.

## KI-005 — UI is architectural parity, not pixel parity
**Status:** Open  
**Evidence:** Text/navigation names are based on packaged localization and module names; detailed visual measurements have not been reproduced.  
**Risk:** v0.1 appearance differs from target.  
**Next verification:** Build screenshot inventory and compare each screen on the same device class.
