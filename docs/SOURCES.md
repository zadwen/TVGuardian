# Research sources

Reviewed 2026-11-18. Samsung/Apple/provider documentation is authoritative for
documented privileges and API contracts; community software is evidence of
observed local protocol behavior, not a Samsung support guarantee.

| Source | Used for |
|---|---|
| [Samsung Smart TV developer portal](https://developer.samsung.com/smarttv/) | Platform documentation starting point |
| [SmartThings developer portal](https://developer.smartthings.com/) | Current official cloud integration route |
| [Samsung TV Package API](https://developer.samsung.com/smarttv/develop/api-references/tizen-web-device-api-references/package-api.html) | Platform-level uninstall, public package information, preloaded restrictions |
| [Samsung TV Application API](https://developer.samsung.com/smarttv/develop/api-references/tizen-web-device-api-references/application-api.html) | Public inventory, partner kill requirement, mobile-only usage history |
| [Privileges FAQ](https://developer.samsung.com/smarttv/develop/faq/privileges.html) | Signing/authorization boundary |
| [Configuring TV apps](https://developer.samsung.com/smarttv/develop/guides/fundamentals/configuring-tv-applications.html) | Tizen privileges and manifest |
| [Certificate creation](https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/creating-certificates.html) | Author/distributor certificates and target DUID |
| [TV SDK connection](https://developer.samsung.com/smarttv/develop/getting-started/using-sdk/tv-device.html) | Developer mode and supported target deployment |
| [Samsung CLI](https://developer.samsung.com/smarttv/develop/getting-started/using-sdk/command-line-interface.html) | Widget build/package/install/run syntax |
| [Samsung app management support](https://www.samsung.com/uk/support/tv-audio-video/how-do-i-manage-apps-on-my-smart-tv/) | TV-side deletion/lock guides; menu variation remains model-dependent |
| [SmartThings capabilities](https://developer.smartthings.com/docs/devices/capabilities) | Advertised commands/attributes rather than invented operations |
| [Production capability reference](https://developer.smartthings.com/docs/devices/capabilities/capabilities-reference) | Standard volume/input contracts |
| [Control devices](https://developer.smartthings.com/docs/service-integrations/control-devices) | Device commands endpoint and acknowledgement semantics |
| [Query/list devices](https://developer.smartthings.com/docs/service-integrations/query-and-list-devices) | Device and capability status endpoints |
| [API request patterns](https://developer.smartthings.com/docs/service-integrations/api-overview) | Device-list pagination |
| [Authorization](https://developer.smartthings.com/docs/getting-started/authorization-and-permissions) | PAT expiry and service integration choice |
| [samsung-tv-ws-api](https://github.com/xchwarze/samsung-tv-ws-api) | Maintained open-source local control implementation |
| [Its connection implementation](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/connection.py) | Port 8002 WSS/HTTPS, query token, channel pairing |
| [Its remote implementation](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/remote.py) | App inventory and launch messages, model limitations |
| [Its REST implementation](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/rest.py) | Status/run/close semantics; close is not uninstall |
| [Home Assistant Samsung TV integration](https://www.home-assistant.io/integrations/samsungtv/) | Independent established implementation and local reachability/compatibility limits |
| [Home Assistant integration source](https://github.com/home-assistant/core/blob/dev/homeassistant/components/samsungtv/media_player.py) | Secondary implementation comparison; no privilege grant inferred |
| [AdGuard Home OpenAPI](https://github.com/AdguardTeam/AdGuardHome/blob/master/openapi/openapi.yaml) | Basic auth, filtering status/rules, query log |
| [Pi-hole API](https://docs.pi-hole.net/api/) | v6 API and version-specific documentation |
| [Pi-hole auth schema](https://github.com/pi-hole/FTL/blob/master/src/api/docs/content/specs/auth.yaml) | Sessions/application passwords/header authentication |
| [Pi-hole domains schema](https://github.com/pi-hole/FTL/blob/master/src/api/docs/content/specs/domains.yaml) | Exact deny entries, groups and processed errors |
| [Pi-hole queries schema](https://github.com/pi-hole/FTL/blob/master/src/api/docs/content/specs/queries.yaml) | Query logs and client filter |
| [NextDNS API](https://nextdns.github.io/api/) | API key, profile denylist, cursor pagination, logs, HTTP 200 errors, beta status |
| [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) | Local Network permission, Bonjour declarations, restricted raw multicast |
| [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers) | Secure routed access to non-Tailscale devices |
| [WireGuard](https://www.wireguard.com/quickstart/) | Existing VPN route approach |

Source code was written for this project. No third-party Python wrapper or Home
Assistant code is bundled. Observed protocol field names are interoperability
facts. Research downloads and optional QA dependencies are excluded from delivery.
No claim of Samsung certification, partner privilege approval or exact-model
verification follows from this research.
