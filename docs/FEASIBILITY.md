# TV Guardian feasibility record

Research date: 2026-11-18. Target phone: iPhone 14 Pro, iOS 17 or later.
The initial photo identified only the SmartThings label `85" Mini LED`.
Subsequent read-only local metadata diagnostics reported model `UA85M80HAUXZN`,
family `26_PTM_MD`, token authentication support and firmware `Unknown`.
The encrypted control port was reachable from the Windows PC. The user installed
v0.1.0 on the iPhone and reported an unresponsive Save TV button. Authenticated
TV pairing, app management and exact firmware compatibility remain unverified.
Apple signing credentials are not stored in this workspace; Xcode runs on GitHub's Mac.

## Management boundary

Samsung's TV Web Package API documents `uninstall(packageId, ...)` at **platform**
privilege level (`http://tizen.org/privilege/packagemanager.install`). Some preloaded
packages cannot be removed. Ordinary developer signing does not confer platform
access. This project does not request that privilege or expose an uninstall API.
It provides a TV-side deletion guide and never calls close or key navigation an
uninstall. The generic Tizen native `packagemanager.admin` name is not evidence of
authorization on a retail Samsung TV.

Source: [Samsung TV Package API](https://developer.samsung.com/smarttv/develop/api-references/tizen-web-device-api-references/package-api.html).

The TV Application API provides installed-app information. Its `kill` operation
requires **partner** privileges in Samsung's TV Web reference. Usage-history
methods on that page are explicitly mobile-only. Public inventory does not grant
control over another app's execution or installation.

Source: [Samsung TV Application API](https://developer.samsung.com/smarttv/develop/api-references/tizen-web-device-api-references/application-api.html).

## Local control

The maintained upstream Samsung TV WebSocket project implements token pairing,
`ed.installedApp.get` and `ed.apps.launch`. These are community-observed interfaces,
not a supported Samsung public management contract. Its REST `DELETE
/api/v2/applications/{id}` means **close**, not uninstall. Availability varies.
TV Guardian uses encrypted port 8002, explicit certificate trust, per-device token
storage and response-based evidence. A sent launch command alone is not proof of
launch. Inventory may be incomplete. Timeout is unverified, not unsupported.

Sources: [upstream project](https://github.com/xchwarze/samsung-tv-ws-api),
[remote implementation](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/remote.py),
[REST implementation](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/rest.py).

## SmartThings

The official cloud API exposes devices, status, capabilities and capability
commands. It is not a general Tizen package manager. This app inspects the selected
device and offers a small allowlist of commands only when advertised. No app-lock,
PIN-setting or uninstall endpoints are assumed. A user-supplied access token is
optional; production distribution needs the developer's registered integration
and OAuth lifecycle. Current documentation says new PATs last 24 hours. Account
plans and access policies must be checked in the user's developer console.

Sources: [control devices](https://developer.smartthings.com/docs/service-integrations/control-devices),
[capabilities](https://developer.smartthings.com/docs/devices/capabilities),
[authorization](https://developer.smartthings.com/docs/getting-started/authorization-and-permissions).

## Companion and signing

A foreground Tizen Web companion can attempt public application/package inventory
and report permission errors. It sends data outbound over normal validated HTTPS
to an optional home bridge; it is not a privileged daemon. Leaving or suspending
the app can stop reports. Missing heartbeats produce stale diagnostics.
No background watchdog, launch interception, app-store lock or persistent system
enforcement is claimed. Public, partner and platform signing are distinct.
Developer mode and SDB are deployment tools, not a way to grant restricted
privileges. Only the project's own signed widget is deployed with SDB.

Sources: [privileges FAQ](https://developer.samsung.com/smarttv/develop/faq/privileges.html),
[certificate creation](https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/creating-certificates.html),
[TV development connection](https://developer.samsung.com/smarttv/develop/getting-started/using-sdk/tv-device.html).

## Parental enforcement

No verified public API was found for remotely changing the native Samsung app
lock, Samsung PIN, installer policy, network settings lock or firmware policy.
These features are unsupported through the implemented public interfaces.
Native locks use a separate TV PIN and require TV-side setup. TV Guardian's PIN,
Face ID, age profiles and schedules protect this controller and its launch path.
They cannot constrain a physical remote, casting, HDMI devices or other clients.
Daily TV-wide usage cannot be measured reliably with these interfaces; no invented
timer is presented. Reinstallation prevention remains unsupported.

Source: [Samsung's app management and lock instructions](https://www.samsung.com/uk/support/tv-audio-video/how-do-i-manage-apps-on-my-smart-tv/).

## DNS and remote access

AdGuard Home, Pi-hole v6 and NextDNS adapters use their published APIs. DNS rules
have provider/client/profile scope and can affect other devices. They do not
uninstall apps or reliably block encrypted DNS, IP literals, VPNs, cached or
offline content. Router administrator controls and egress policy are external
requirements; no universal router API is invented. NextDNS labels its API beta.

Sources: [AdGuard Home OpenAPI](https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml),
[Pi-hole API](https://docs.pi-hole.net/api/),
[NextDNS API](https://nextdns.github.io/api/).

Use an existing Tailscale subnet router or WireGuard route for off-LAN access.
Discovery is local; connect to the saved private IP across the tunnel. No TV port
forwarding, embedded VPN provider or unprotected control port is implemented.

Sources: [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers),
[WireGuard](https://www.wireguard.com/quickstart/).

## Build and verification boundary

The initial deliverable was source and an Xcode project. After a GitHub repository
was supplied, the cloud Mac build passed on 2026-11-18 with Xcode 26.6. The v0.1.1
update passed 26 unit tests, 2 interface regressions and a Release iPhone archive.
The generated IPA is unsigned and can be signed using the documented Windows
workflow. The user installed v0.1.0; v0.1.1 phone pairing, TV app management and
full device/accessibility QA remain pending. Hardware management starts unverified.
