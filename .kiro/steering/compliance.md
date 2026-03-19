---
inclusion: auto
---

# Compliance Requirements

This project has mandatory compliance constraints that must be respected in all code changes, build configurations, and distribution decisions.

## Encryption Standards

- Only standard, well-known encryption mechanisms are permitted. This means:
  - iOS: Apple Keychain (via `flutter_secure_storage`) — uses AES-256 under the hood
  - Android: Android Keystore (via `flutter_secure_storage`) — uses AES-256-GCM
  - Web: Browser-native `SubtleCrypto` (Web Crypto API) with AES-GCM for any client-side encryption; plain `localStorage` must NOT store sensitive data without encryption
  - TLS 1.2+ for all network communication (no custom TLS implementations)
- Do NOT introduce custom or proprietary encryption algorithms
- Do NOT use deprecated ciphers (DES, 3DES, RC4, MD5 for hashing, SHA-1 for signatures)
- All cryptographic operations must rely on platform-provided or widely audited libraries

## Geographic Distribution Restrictions

- This application must NOT be published or distributed in France
- When configuring app store listings:
  - Google Play: Exclude France (FR) from target countries
  - Apple App Store: Exclude France (FR) from availability
  - Web deployment: Implement geo-restriction or display an unavailability notice for users in France
- Any CI/CD pipeline or release automation must enforce this exclusion

## General Compliance Notes

- Do not add export-controlled encryption beyond what the platform provides by default
- Ensure App Store / Play Store encryption declarations (e.g., Apple's ITSAppUsesNonExemptEncryption) are set correctly — this app uses standard HTTPS and platform keychain only, so it qualifies for the encryption exemption
- Keep compliance documentation up to date when adding new dependencies that involve cryptography
