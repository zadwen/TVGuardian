# Verification record

Date: 2026-11-18. Local host: Windows, Node.js v26.13.1. Cloud host:
GitHub macOS 26 ARM64, Xcode 26.6 (17F113), iPhone 17 Pro / iOS 26.4.1 simulator.

| Check | Observed result |
|---|---|
| Node bridge, companion mocks and structural suite | **34 passed, 0 failed** |
| Production JavaScript syntax | Checked through parsing/executed imports and `node --check` |
| Xcode project parse | Passed Apache `xcode` 4.0.0 parser; 2 native targets |
| Swift grammar | 29 files, 0 syntax errors with tree-sitter Swift grammar |
| Info.plist, privacy manifest, Tizen XML | Parsed as XML |
| iOS Xcode build/type checking | **Passed on GitHub's Mac, Xcode 26.6** |
| iOS XCTest | **26 passed, 0 failed** in the iPhone simulator |
| Native SwiftUI visual/accessibility QA | **Not run** |
| Tizen Studio package/sign/install | **Not run** |
| Real Samsung TV / iPhone 14 Pro | **Not connected or tested** |
| Live AdGuard / Pi-hole / NextDNS / SmartThings | **Not connected or tested** |
| Bridge TLS | Loopback production entry point tested with a generated fixture certificate |
| Home certificate chain/firewall/VPN deployment | **Not performed** |
| Cloud IPA packaging workflow | **Passed**; unsigned iPhoneOS Release IPA downloaded and checksummed |
| Windows signing / AltStore installation | **Not performed** |

Grammar/project parsing was followed by a real Xcode build and XCTest run.
Those passes do not establish signing, UI/accessibility quality or hardware
support. No simulated result is called a real-device success. Tests use generated
fixture tokens and explicitly named mock hardware. No default/demo TV or sample
inventory appears in the app.

Observed [successful cloud run](https://github.com/zadwen/TVGuardian/actions/runs/44339943672),
source revision `5725c3720063b64b2d27a210652f41e57c87dce4`:
34 Node tests passed on the cloud runner, then 26 XCTest cases passed,
`TEST SUCCEEDED` and `ARCHIVE SUCCEEDED`. The unsigned device IPA is 500,589 bytes;
SHA-256 `38cd4f6525fd430e284f68ab06731d70014c0f27b078ffa6ef89b0f577510913`.
The artifact ZIP hash and nested IPA checksum were verified after downloading.
There is a nonblocking source deprecation warning for `SecTrustGetCertificateAtIndex`;
Xcode also reports standard XCTest binary-stripping/AppIntents metadata warnings.

## Executed contract coverage

The 34 tests include 15 real loopback handler tests, 4 persistence tests, 2 TLS
startup/transport tests, 9 mocked Tizen inventory tests and 4 structural artifact tests. They cover authentication
separation, code expiry/replay/rate limits/concurrent redemption, token hashes,
revocation, missing heartbeats, unsupported command routes, invalid claims and
IDs, CORS restrictions, log redaction, persistence failure/serialization/corruption,
public API permissions, hardware absence and non-use of privileged methods.

Handler fixtures use HTTP solely inside the tests. The production entry point
requires TLS files and creates only an HTTPS server. Separate tests exercise
that entry point with generated, ephemeral X.509 material: untrusted certificate
rejection, explicitly trusted TLS 1.2/1.3 negotiation, parent bearer checks and
startup refusal without TLS. These are not a deployed certificate-chain test.

Reproduce from the root:

```sh
node --test bridge/test/*.test.mjs companion/test/*.test.mjs tools/test/*.test.mjs
```

Optional non-macOS grammar/project QA (dependencies remain under ignored `.build`):

```sh
npm install --prefix .build/qa --ignore-scripts --no-audit --no-fund xcode@4.0.0 web-tree-sitter@0.25.10 tree-sitter-wasms@0.1.13 yaml@2.9.1
node tools/validate-source.mjs
```

## Supplied XCTest coverage

- Nine rule-engine tests: fixed home zone, start/end boundaries, overnight
  ownership, weekend rollover, equal times, disabled/invalid schedules, repeated
  DST hour, TV/app scoping and age behavior without/with a profile.
- Ten security/persistence tests: private-address/domain/origin/ID validation,
  independently computed PBKDF2 vector, saved-rule round trip, fail-closed corrupt
  state, invalid persisted policy, credential origin/account binding and privilege boundaries.
- Four HTTP contract tests using URLProtocol hardware/service isolation: provider
  error within HTTP 200, token expiry, plaintext rejection and malformed JSON.
- Three Samsung message tests: exact reported IDs, unknown system status,
  string-encoded envelopes and malformed events that cannot become empty success.

Use Product → Test in Xcode or the README command. The GitHub workflow selects an
available iPhone simulator dynamically. The observed run and source revision above
are the validation reference; record new results after application code changes.

## Required real-device acceptance

Record full model code, region, firmware, iOS version, Xcode version and date.
Perform tests on a consenting adult's TV with a disposable user-installed test
app. Keep native TV PIN and actual tokens out of reports.

1. Install on the iPhone, enroll parent PIN, test wrong PIN/backoff across process
   restart, Face ID enablement/enrollment change, background and idle locking.
   Verify Keychain errors fail closed and no sensitive task survives locking.
2. Discover advertised TV candidates; test manual IP, denied Local Network
   permission, Wi-Fi client isolation, unavailable TV and a VPN route.
3. Review the correct certificate, approve the TV pairing prompt and reconnect
   after a network interruption. Confirm changed TLS/identity blocks credentials.
4. Refresh apps; compare names/IDs with the TV. Record missing entries and icon
   availability. Never infer protected status from app names or incomplete lists.
5. Launch a permitted test app, then block it in Guardian and verify Launch is
   rejected. Test age profiles and a schedule around midnight in the home zone.
   Confirm a physical remote remains outside those rules.
6. Attempt close only after confirming the viewing interruption. Verify logs
   distinguish requested/submitted/observed; an HTTP acknowledgement alone must
   not report success. Confirm the app remains installed afterward.
7. Follow the native lock guide and verify the PIN on the TV itself. Test casting,
   alternate controllers, store reinstallation, HDMI and administrator settings.
   Record bypasses; do not mark programmatic management supported.
8. Sign/install this companion, pair over a genuinely trusted HTTPS bridge,
   inspect permission failures, import a fresh report, leave the companion and
   confirm it becomes stale after 90 seconds. Revoke its token and reject reports.
9. Use a dedicated resolver client/group/profile. Add one harmless test domain,
   verify the provider result and an actual uncached TV lookup. Check removal
   scope and unrelated-client policy. Record encrypted-DNS/alternate-network
   bypasses and provider logging/retention limits.
10. With an authorized short-lived cloud token, select the exact TV, inspect its
    advertised capabilities, send only deliberate commands and refresh status.
    Confirm expiry produces an authorization error without discarding rules.

Do not perform firmware modification, protected-package removal or privilege
escalation as an acceptance step. Do not mark exact TV compatibility verified
until these observations exist.
