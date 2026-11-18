# Feature compatibility matrix

Target supplied: **SmartThings label `85" Mini LED`**. Full model/region/firmware
were not in the supplied picture. Exact-model support is **unverified**.
No hardware was contacted during development. All device operations below need
real-device acceptance; “implemented” does not mean “tested on your TV.”

| Feature | Implemented path | Default / requirement | Actual enforcement scope |
|---|---|---|---|
| Automatic discovery | Bonjour `_samsungmsf._tcp`, `_airplay._tcp` | Unverified; TV must advertise; AirPlay devices are candidates | Local network only; not exhaustive |
| Manual connect | Private IPv4 and encrypted port 8002 | Unverified until reviewed metadata/pairing response | No plaintext fallback |
| Pair/reconnect | Reviewed certificate, Samsung token in Keychain | TV must issue a token; foreground unlocked parent session | Trust on first use; changes block access; tokenless channels rejected |
| App names and launch IDs | `ed.installedApp.get` | Unverified until a valid response | Potentially partial installed/launchable list |
| Public Tizen app IDs/package IDs | Companion `getAppsInfo`; public package probe | Companion must be foreground and permitted | May omit protected apps; IDs not guessed into other namespaces |
| Icons | Explicitly reported same-TV HTTPS icon URL | Unverified; absent/insecure/cross-host URL uses local fallback | Companion file paths are metadata only |
| System/user-installed status | Typed unknown unless actually known | Unknown on these implemented public contracts | No inference from IDs/names or deletability |
| Launch | Authenticated `ed.apps.launch` | Unverified until response evidence | Request submitted first; optional REST running observation |
| Close | REST DELETE applications/ID, before/after status | Unverified; manual attempt confirmation required | Success only after running → stopped; not package removal |
| Direct uninstall | None | **Unsupported** in normal public companion/controller | TV Package API needs platform privileges |
| Remove protected/system apps | None | **Unsupported** | No service menu, firmware or privilege bypass |
| Native app lock/unlock | TV-side guide | **Unsupported programmatically** | Native lock must be set and tested on TV |
| TV PIN change | TV-side guide | **Unsupported programmatically** | Separate from parent PIN; not stored on phone |
| Guardian app block/unblock | Persisted rule before direct Launch | Implemented controller behavior | Other launch paths bypass it |
| Parent-assigned age profiles | Guardian rule engine | Implemented; no official ratings feed | Active Guardian profile only |
| Bedtime / school-time | Fixed IANA zone, selected days, app/all-app scope | Implemented; midnight and DST tests supplied | Denies new Guardian launches; never stops current viewing |
| Daily TV usage / daily limit | None | **Unsupported** reliable TV-wide measurement/enforcement | Audit entries are not screen time |
| Prevent reinstall / store lock | None | **Unsupported** | Native lock, account/router review; no guarantee |
| Lock network/settings changes | Guide | **Unsupported** through these APIs | Physical/admin access can bypass restrictions |
| Parent PIN / Face ID | Keychain, PBKDF2, LocalAuthentication | Implemented; device tests pending | Protects iPhone controller, not TV menus |
| Persistent rules | Protected atomic local JSON | Implemented; XCTest supplied | Local data survives restarts, not app/data erasure |
| AdGuard Home rules | Published `/control` API; explicit client IP | Requires HTTPS trust and credentials | DNS requests using that resolver/client only |
| Pi-hole v6 rules | Session API; exact deny; explicit group ID | Requires authorized application password | Group clients; no automatic group membership or safe shared removal |
| NextDNS rules | API key, selected profile denylist | Provider API is beta; pagination bounded | All profile users; routing not verified |
| DNS events | Provider query APIs; latest 100 | Provider logging/retention and credential scope | Can include other devices; not TV app activity |
| Router API policy writes | None | **Unsupported** without a specified supported adapter | Configure using router's own supported tools |
| SmartThings settings | Advertised standard switch/audioVolume/mediaInputSource | Optional user token; exact device selection | Cloud acknowledgement; refresh status; no arbitrary capability commands |
| Remote navigation | Authenticated key messages | Unverified physical effects | Can navigate outside Guardian launch rules |
| Off-LAN access | Existing Tailscale subnet router / WireGuard route | External VPN configuration required | Manual saved private IP; no public TV ports |
| Audit | HMAC chain, bounded 5,000 entries, export | Implemented; secure storage required | Controller/provider activity; whole-file rollback not detectable |

## Evidence and invalidation

In-app capability rows are `supported`, `unsupported` or `unverified`, with a
reason, route and observation date where applicable. A timeout does not establish
unsupported status. A generic HTTP success does not establish a stopped TV app.
Firmware/model changes clear cached response evidence when detected or recorded.
Many TVs do not report firmware over the local API: record it manually after an
update. The parent-provided source is labeled. App close evidence is per app;
a response for one ID does not establish support for every app.

## Remaining release limitations

- Apple SDK builds and all 26 XCTest cases passed on a GitHub Mac with Xcode 26.6.
  UI/accessibility/device QA, Apple signing and phone installation remain pending.
  The generated device IPA is unsigned; this is not an App Store release.
- No exact TV manual or firmware-specific regression result is available yet.
- Bonjour can miss TVs; raw SSDP is not shipped. A raw multicast implementation
  would require Apple's restricted entitlement and additional device testing.
- TLS 1.2+ is required. TVs exposing only plaintext/older TLS are intentionally
  not silently downgraded. Certificate renewal requires explicit re-pairing.
- Local REST status/close and WebSocket events are community-observed and may
  disappear in firmware updates. REST authorization behavior can vary and must
  be checked on the target; application-level authorization cannot be added to
  a TV interface that does not enforce it itself.
- The public companion is foreground reporting only. Restarting it requires
  fresh pairing; no token is written to browser storage.
- No turnkey OAuth backend, vendor router adapter, embedded VPN entitlement,
  notification-based TV watchdog, push enforcement or reliable usage meter is
  claimed. Adding a UI toggle cannot create those missing platform permissions.
