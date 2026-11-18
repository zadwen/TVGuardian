# TV Guardian

Native SwiftUI iPhone controller for Samsung Tizen TVs, with direct app discovery,
launch requests, observed app-close verification, parent authentication, honest
capability reporting and optional DNS/foreground-companion integrations.

**v0.1.1 fixes the Save TV flow.** The GitHub cloud Mac passed 26 unit tests,
2 interface tests and a Release device archive on 2026-11-18 UTC. Saving a TV,
reopening with its saved entry and requiring the parent PIN after backgrounding
were verified in the simulator. The unsigned device IPA needs the documented
[Windows signing/install workflow](docs/WINDOWS.md).
The user installed v0.1.0; v0.1.1 phone pairing and TV app operations still need
real-device verification. [Successful build](https://github.com/zadwen/TVGuardian/actions/runs/44392060961).

## The most important limitation

A normal Samsung developer certificate cannot remotely uninstall retail TV apps
through the documented Package API: that operation requires platform privileges.
This build does not expose an uninstall endpoint. Native app locks, TV PIN changes,
installation prevention and system-wide usage enforcement have no verified public
management interface here. They have explicit unsupported status and guided
TV-side setup. The REST **close** operation is never called uninstall.

Guardian rules, age thresholds and schedules restrict launches **through this app**.
They do not stop a physical remote, SmartThings, casting, another controller, HDMI
or an app that is already running. Native locks and router controls remain
necessary. Read [feasibility](docs/FEASIBILITY.md) and [compatibility](docs/COMPATIBILITY.md).

## Included functionality

- All ten requested screens, plus companion, cloud-capability and compatibility views.
- Bonjour discovery of advertised candidates, manual private IPv4 connection,
  explicit TV certificate review, encrypted Samsung token pairing, saved TVs,
  foreground reconnect and device-identity checks.
- Actual community-observed app inventory and launch messages. A launch is first
  logged as submitted; a compatible REST response may establish a running state.
  Close is observed only when running changes to stopped after the request.
- Per-app controller blocks, parent-assigned age thresholds, child profiles,
  overnight/time-zone-aware bedtime and school-time schedules, protected storage.
- Separate parent PIN using salted PBKDF2-HMAC-SHA256, persistent retry backoff,
  optional Face ID with enrollment-change detection, background/idle locking,
  Keychain secrets and HMAC-chained audit export.
- Optional public Tizen app inventory companion over a TLS-only home bridge.
  One-use pairing, separate parent/TV tokens, revocation, bounded messages and
  heartbeat staleness; no hidden or privileged operations.
- AdGuard Home client-scoped custom deny rules; Pi-hole v6 exact deny rules with
  explicit group assignment; NextDNS profile denylist addition/removal and
  response verification; recent DNS logs. Pi-hole removal requires dashboard
  review to preserve shared group policy.
- Optional authorized SmartThings device/status/capability inspection and
  acknowledged power, volume and reported standard input-source requests.
- Local remote commands and documentation for existing Tailscale/WireGuard routing.

## Open and install

**No Mac required at home:** use the prepared [cloud-build → Windows install
route](docs/WINDOWS.md). GitHub runs Xcode on its Mac runner; a successful run
produces an unsigned device IPA for subsequent signing with AltServer/AltStore
on Windows. Install v0.1.1 over the existing app with the same account and bundle
identifier to preserve local data.

If you have access to a Mac, use the local route:

1. Copy this folder to a Mac with Xcode 16 or later and a compatible iOS SDK.
2. Open **`ios/TVGuardian.xcodeproj`**, choose the **TVGuardian** scheme and run the
   simulator tests. Select your signing team and unique bundle ID for a device.
3. Connect the iPhone 14 Pro, enable its Developer Mode when requested, select it
   as the destination and run. Create the parent PIN on first launch.
4. Add the TV under Connected TVs, review the certificate, pair on the TV and
   refresh Installed Applications. Save exact model/firmware under TV Settings.

Detailed [installation and pairing](docs/INSTALL.md),
[companion deployment](docs/COMPANION.md), [network filtering](docs/NETWORK.md)
and [test results/acceptance steps](docs/TESTING.md) are included.

## Source map

| Path | Purpose |
|---|---|
| `ios/TVGuardian/App` | App composition, session gate, operation coordination |
| `ios/TVGuardian/Core` | Typed state, rule evaluation, validation, protected persistence |
| `ios/TVGuardian/Networking` | Samsung TLS/WebSocket/REST, Bonjour, cloud and bridge clients |
| `ios/TVGuardian/Security` | Keychain, PIN derivation, retry limits, Face ID |
| `ios/TVGuardian/Filtering` | Provider-specific DNS contracts and verified rule changes |
| `ios/TVGuardian/Views` | SwiftUI management screens |
| `ios/TVGuardianTests` | 26 XCTest cases; passed on the GitHub cloud Mac |
| `ios/TVGuardianUITests` | Save/reopen and background PIN regression checks; passed in the simulator |
| `companion` | Public Tizen Web app and hardware-mock inventory tests |
| `bridge` | Dependency-free Node.js HTTPS inventory bridge and contract tests |
| `tools` | Reproducible project/icons, structural checks, optional grammar QA |
| `.github/workflows/verify.yml` | Node checks on pushes; simulator checks when dispatched |
| `.github/workflows/build-iphone.yml` | Tested cloud simulator + unsigned iPhone IPA workflow |

## Run available tests

Node.js 22 or later; there are no production npm dependencies or install scripts.
From the repository root:

```sh
node --test bridge/test/*.test.mjs companion/test/*.test.mjs tools/test/*.test.mjs
```

From `bridge`, `npm test` runs the same suite. Current observed result: **34 passed**.
These include real loopback HTTP/HTTPS tests and mocked Tizen hardware. TLS tests
use a freshly generated fixture certificate; they are not tests against a TV or
a deployed home certificate chain.

On macOS:

```sh
xcodebuild test -project ios/TVGuardian.xcodeproj -scheme TVGuardian \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator if that device is unavailable. The project has no
external Swift packages. Regenerate it after adding Swift files with
`node tools/generate-project.mjs`; icons with `node tools/generate-icons.mjs`.

See [security architecture](docs/SECURITY.md), [sources](docs/SOURCES.md) and
[known limitations](docs/COMPATIBILITY.md) before relying on this engineering build.
