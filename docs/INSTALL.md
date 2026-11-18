# iPhone installation and pairing

**Using Windows without a Mac?** Follow [the cloud-build and Windows installation
guide](WINDOWS.md). A GitHub-hosted Mac can compile the app; AltStore/AltServer on
Windows can perform subsequent Apple signing and installation. The v0.1.1 cloud
build, 26 unit tests and 2 interface tests passed on 2026-11-18 UTC. The unsigned IPA is ready for
Windows signing; the local-Xcode route below is optional.

## Build environment

Use a Mac with Xcode 16 or later, its iOS SDK/simulator support, and an Apple
account/team suitable for your device workflow. Deployment target is iOS 17.
The iPhone 14 Pro is supported by that target. Windows cannot run Xcode or sign
this project using an Apple signing environment that is not present.

1. Copy/extract the complete project folder onto the Mac.
2. Open `ios/TVGuardian.xcodeproj`, select the TVGuardian scheme.
3. Run Product → Test on an installed iPhone simulator. All 26 supplied XCTest
   cases passed on GitHub's cloud Mac using Xcode 26.6. Repeat after code changes
   and resolve failures before installing on a family device.
4. Select the TVGuardian target → Signing & Capabilities. Choose your Apple
   team, keep automatic signing and change `com.example.TVGuardian` to an
   identifier owned by your team. Set the test bundle identifier consistently
   if needed. No development team, signing certificate or password is bundled.
5. Connect and trust the iPhone, enable Developer Mode if iOS requests it, select
   the device destination and run. Xcode provisions the application under your
   account's current limits. Personal-team profiles can expire; Xcode will show
   the applicable restrictions and renewal requirements.
6. For an archive, choose a device destination and Product → Archive. Use only a
   distribution route supported by your team/account, such as registered-device
   development/ad hoc deployment or TestFlight after its review requirements.
   An unsigned archive cannot be turned into a usable signed IPA without the
   necessary certificates/provisioning. No signing bypass or pre-signed IPA is
   included. Other sideloading tools still require valid Apple signing.

The app has no background mode, VPN entitlement or restricted multicast entitlement.
Bonjour uses the declared service types and Local Network permission. No remote
service needs to be started for the basic iPhone-to-TV path.

## Parent setup

Create a 6–12 digit parent PIN with at least three different digits. Keep it
separate from the Samsung TV PIN. There is no unauthenticated PIN reset button.
Enable Face ID in Parental Controls after unlocking. Changing Face ID enrollment
requires the PIN to re-establish biometric access. Backgrounding the app locks
it and disconnects local control; five minutes of inactivity also locks it.

Keychain entries use `WhenUnlockedThisDeviceOnly`; they do not migrate via backup.
Rules and logs are protected local app data and excluded from backup. Reinstalling
or changing signing identity can lose local state while Keychain behavior varies;
do not treat reinstall as a supported PIN recovery strategy. Preserve the PIN or
use a separately planned, authenticated recovery feature before broader release.

## Pair locally

1. Put the iPhone and TV on a network that permits client-to-client access.
   Enable iOS Settings → TV Guardian → Local Network when prompted.
2. On the TV, find Network Status / IP Settings. Reserve that IP in the router.
   In Connected TVs, use Find TVs if advertised over Bonjour, otherwise save the
   private IP manually. AirPlay discovery results are unverified candidates.
3. Tap Pair / reconnect. TV Guardian retrieves the TLS leaf fingerprint without
   accepting it, and presents it for review. Confirm the IP from the TV itself.
   Do first pairing on a trusted home network. This step is trust on first use;
   it cannot independently detect an attacker already impersonating the TV.
4. Where possible, inspect the certificate independently on a trusted computer:

   ```sh
   openssl s_client -connect TV_PRIVATE_IP:8002 -showcerts
   ```

   Save the leaf certificate from that output and inspect it with:

   ```sh
   openssl x509 -in tv-leaf.pem -noout -fingerprint -sha256
   ```

   Compare its hex fingerprint with the app (ignoring colons/case). This proves
   consistency with the inspected network endpoint, not a Samsung-issued device
   identity. The app pins the reviewed certificate and rejects later changes.
5. Trust the reviewed fingerprint in the app, tap Pair again and allow TV Guardian
   on the TV's connection prompt. Device Connect Manager / External Device
   Manager menus vary. Keep connection notifications/approval enabled.
6. Open Installed Applications and refresh. Allow up to the displayed timeout.
   A returned list may be incomplete. Try the optional foreground companion if
   needed; a failure stays unverified rather than showing sample data.
7. Open TV Settings. Confirm the exact full model code and firmware from Support
   → About This TV if they are absent from the API. Windows metadata diagnostics
   identified `UA85M80HAUXZN`; firmware was reported as `Unknown` and still needs
   confirmation on the TV.

## Verify parental restrictions

Save a controller block for an app and try its Launch button. Then separately
set the native Samsung app lock using the in-app guided steps and test with the
physical remote. The app never reports a guided setup as a verified direct lock.
Test each child's physical remote, casting and HDMI routes. Do not rely on
Guardian-only schedules as TV-wide bedtime enforcement.

## Reconnect and revoke

While unlocked/foreground, the app pings and retries saved authorized connections
with a bounded delay. It never replays a destructive command after a disconnect.
Certificate or identity errors stop automatic attempts until reviewed. Changed
network addresses require adding/reviewing the correct private endpoint.

To reset trust, remove the local pairing and its rules after confirmation. Also
revoke the allowed controller in the TV's Device Connect Manager. Local deletion
alone cannot revoke authorization on the TV or in a cloud account.

If port 8002 is unavailable, use the compatibility diagnostics. Do not port-forward
8001/8002 or SDB. Off-LAN access requires your existing VPN; see [NETWORK.md](NETWORK.md).
