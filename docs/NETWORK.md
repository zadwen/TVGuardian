# DNS filtering and secure remote access

## Supported provider contracts

All service calls use HTTPS with ordinary iOS certificate validation. Redirects
are refused to prevent forwarding credentials. Secrets live in Keychain. Save
the configuration before previewing a change. Every write has a scope preview
and explicit confirmation; a provider rule is never represented as a Tizen lock.

| Provider | Authentication | Reads | Writes |
|---|---|---|---|
| AdGuard Home | HTTPS Basic, dedicated account where supported | `/control/filtering/status`, `/control/querylog` | `/control/filtering/set_rules` |
| Pi-hole v6 | POST `/api/auth` with application password; ephemeral `X-FTL-SID`; DELETE session afterward | `/api/queries` | POST `/api/domains/deny/exact` with explicit groups |
| NextDNS | `X-Api-Key`, selected six-character profile ID | `/profiles/{id}/denylist`, `/profiles/{id}/logs` | POST denylist entry / DELETE exact denylist entry |

Provider docs: [AdGuard OpenAPI](https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml),
[Pi-hole API](https://docs.pi-hole.net/api/),
[NextDNS API](https://nextdns.github.io/api/).

AdGuard rules are exactly `||DOMAIN^$client=TV_PRIVATE_IP`. Existing custom rules
are preserved in a full-list update. The list is re-read and compared with the
preview immediately before saving, then read back after writing. AdGuard has no
verified conditional compare-and-swap contract here: a simultaneous external
editor can still race this sequence. Use a single editor during the operation.
Removal deletes only that exact generated rule and does not create an allowlist.
Do not use an unreserved IP shared later by another device.

Pi-hole rules are **exact domains**; subdomains require their own rules. Assign
the TV to a deliberate group in Pi-hole; group 0 can include many devices. This
app never invents group membership or overwrites an existing entry. Removing a
shared entry could weaken another group's policy, so review removals in Pi-hole's
dashboard. Its API modification settings/application password must authorize the
write. The app checks the `processed` result, not just HTTP 2xx. v5 is unsupported.

NextDNS rules affect every device using that profile. Prefer a dedicated TV
profile. HTTP 200 can contain provider errors; those are rejected. Denylist
read-back follows bounded cursor pagination. Removing one deny entry does not
override a parental category, blocklist or other rule. NextDNS calls its API beta.

Recent query displays read at most 100 records. AdGuard/Pi-hole can filter by the
configured client IP; NextDNS displays profile-wide records. Logs are not proof
that every TV request went through that provider, and they do not identify all
native app activity. Disabled logging, retention/privacy settings and cached DNS
answers change what appears. No provider integration was tested live here.

## Router enforcement

No router model/API was supplied and no universal router adapter is claimed.
Use the router's supported administration tools to reserve the TV address,
assign resolvers, place the TV in an appropriate network and protect administrator
settings. Decide how to handle IPv6 DNS and alternate networks as well as IPv4.
Resolver assignment by DHCP alone does not guarantee enforcement.

An appropriate router policy may restrict direct external DNS and unauthorized
egress. Ordinary port rules alone cannot reliably identify all HTTPS-based DNS,
VPNs, IP-literal connections or application tunneling. Blocking shared domains can
break unrelated services. Test a narrow domain with the TV before changing broad
policies. Cached/offline/HDMI content is outside DNS enforcement.

## Outside the home

TV Guardian works with an existing OS-level VPN; it does not install or manage
Network Extension tunnels. For Tailscale, use an always-on home subnet router,
advertise/approve the TV subnet and restrict access to parent identities. Connect
the iPhone to the same tailnet and use the TV's saved private address. The TV
does not need a Tailscale client for inbound routed access.

For WireGuard, configure a supported home VPN endpoint and a narrow route to the
TV/home services in the iPhone tunnel. Follow your router's guidance for the VPN
itself. Bonjour normally will not cross these routed boundaries; manual IP
connection is expected. Certificates remain verified/pinned through the tunnel.

Do not forward TV control ports 8001/8002, SDB 26101 or an unprotected bridge to
the public internet. Tailscale/WireGuard setup, firewall policy and reachability
must be tested on the actual home network.

Sources: [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers),
[WireGuard](https://www.wireguard.com/quickstart/).
