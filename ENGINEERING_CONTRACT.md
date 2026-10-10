# GameStore Engineering Contract

## Mandatory iOS 13 API ceiling (non-negotiable)

1. **iOS 13.0 is the maximum allowed minimum availability for every API and code path in GameStore's application code.** Do not introduce, call, reference, or depend on APIs, SwiftUI modifiers, UIKit methods, frameworks, symbols, or language/runtime features that require **iOS 14.0 or later**.
2. This prohibition includes APIs hidden behind `if #available(iOS 14, *)`, `@available(iOS 14, *)`, fallback branches, dynamic selectors, wrappers, conditional compilation, or SDK-dependent extensions. Availability guards **do not make an API permissible** under this project's contract.
3. New functionality must use an implementation available on **iOS 13.0**. If no equivalent exists, do not implement it until the user explicitly approves a contract change; explain the constraint instead.
4. Check each newly introduced Apple API's official availability and third-party dependency deployment requirements **before coding**. Also review copied/reference-project code against the same ceiling.
5. Before declaring a change complete, run the legacy **Xcode 15.4 / iOS 13.0 deployment target simulator and iPhoneOS builds** and the modern **Xcode 26.6 SDK build**. Both jobs must pass; CI success is not a substitute for audit of availability-guarded higher-version calls.
6. Do not change `IPHONEOS_DEPLOYMENT_TARGET` above `13.0` to work around build failures. Newer-SDK builds must retain the iOS 13.0 deployment target.
7. Treat violations as **release-blocking defects**. Record the offending symbol and minimum OS version, replace with an iOS 13-compatible design, and re-run both CI jobs.

This contract applies to all future GameStore changes, including signing, icon handling, navigation, download, UDID callback, and installation work. Existing higher-iOS API usage, if found, must be audited and eliminated rather than used as a precedent.

## Change isolation

Preserve the existing working signing and callback behavior when changing UI or packaging. Do not claim runtime or device validation based solely on compilation.
