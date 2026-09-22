# ROADMAP

## Goal

Build a clean-room GameStore implementation whose UI, public request protocol, download workflow, certificate workflow, signing state machine and OTA installation behavior are compatible with the verified target build.

## Baseline evidence

- Target main executable SHA-256: `ea4947e192da53ceae434e51108c9af49f6a99d80c9d5e6e7e0d2ac5e6324e4e`
- Target bundle id: `com.GameStore.maicha`
- Target version: `1.2 (1)`
- Minimum iOS: `15.0`
- Static evidence confirms SwiftUI/UIKit, `gamestore://`, API base `https://new.iosgame.vip`, download/signing/OTA state strings.
- Runtime/device behavior is not yet verified.

## Phases

### Phase 0 — Bootstrap
- [x] Repository initialized.
- [x] Long-term state documents established.
- [x] Xcode project skeleton.
- [x] Four primary tabs.
- [x] API/UDID/download/signing/OTA service boundaries.
- [ ] macOS CI build green.

### Phase 1 — Protocol recovery
- [ ] Recover exact JSON schemas and HTTP methods/headers.
- [ ] Reconstruct activation-code workflow.
- [ ] Reconstruct device-certificate workflow.
- [ ] Add protocol fixture tests.

### Phase 2 — Downloads and persistence
- [ ] Background URLSession transfer.
- [ ] Pause/resume/retry/delete.
- [ ] Persistent task recovery.
- [ ] Cache accounting.

### Phase 3 — Signing
- [ ] IPA inspector/archive implementation.
- [ ] Certificate import/storage.
- [ ] Zsign bridge.
- [ ] Signature validation.
- [ ] Repack artifact.

### Phase 4 — OTA install
- [ ] Local IPA HTTP server.
- [ ] Manifest generation.
- [ ] localhost/LAN strategy matching verified target behavior.
- [ ] `itms-services` launch and install-progress observation.

### Phase 5 — UI parity
- [ ] Extract visual measurements/assets legally available from target package.
- [ ] Rebuild detail/activation/certificate/signing-log screens.
- [ ] Simplified/Traditional Chinese parity.
- [ ] Device screenshot regression comparisons.

## Next Task

Make Phase 0 CI green, then recover exact `/apps/api/app-list/` response schema from captured/authorized traffic or static decoder evidence.
