# Optional Tizen companion and HTTPS bridge

The basic local iPhone connection does not need this component. Use it when the
TV's direct app list is missing/partial and public Tizen inventory is useful.
It is a foreground reporter, not a privileged device-management service.

## 1. Prepare a home bridge

Use an always-on home computer with Node.js 22 or later. The bridge has zero
production package dependencies. From `bridge`:

```sh
npm run setup
```

This creates, without starting a server:

- `guardian.local.json`: listen address, TLS file paths, token hash, state path,
  explicit allowed browser origins.
- `parent-token.local.txt`: randomly generated high-entropy parent token.
- `data/tls/`: initially empty; place your TLS files there.

The command refuses to overwrite an existing configuration. Generated secret,
state and certificate paths are ignored by Git. Protect them with filesystem
permissions; on Windows, review NTFS permissions for the service account because
POSIX `0600` alone does not establish the same ACL guarantees. Never commit them.
Transfer the parent token privately into the iPhone's TV Companion form and clear
unneeded transfer copies. The token is separate from both PINs.

Configure a **hostname with a certificate trusted by both the iPhone and TV**.
Retail TVs may not support installing a private CA. A publicly trusted certificate
for a domain you control, with private DNS pointing that hostname to the LAN
bridge, is a practical option. DNS-based issuance can avoid opening inbound HTTP
ports. Do not assume a `.local` name or a self-signed certificate will work on
the TV. Do not disable TLS verification or certificate errors.

Place the full chain and private key in the configured paths. Edit `host` from
the safe default `127.0.0.1` to the bridge's specific LAN address and keep the
firewall limited to the intended TV/parent devices or VPN. No plaintext server
or proxy-trust fallback exists. Only then run:

```sh
npm start
```

Use a service supervisor under a dedicated unprivileged account for continued
operation. Back up configuration/state securely if needed. Parent-token rotation
requires generating a new random token and changing its SHA-256 hash in config;
restart the service and update the iPhone. Existing companion sessions are
separate and can be revoked from the phone. No automatic update daemon is bundled.

## 2. Configure and sign the TV app

Install Samsung's TV SDK/Tizen Studio and TV extension using the official
instructions. Enable TV developer mode using the documented procedure for the
actual model, authorize the development computer, and connect only on the home
network. The mode does not grant partner/platform privileges.

1. Replace `https://guardian.home.example:8443` in **both** `companion/config.xml`
   (`access`) and `companion/index.html` (`connect-src`) with the exact bridge
   origin. Keep the allowlist narrow and use HTTPS.
2. Generate a Samsung **public** TV certificate profile in Certificate Manager.
   Add the target TV's DUID to its distributor certificate using Samsung's
   supported workflow. Keep the author certificate and passwords private.
3. The companion requests only `internet`, `application.info` and `package.info`.
   It has no uninstall/install, kill, system-manager, key-manager or background
   service privilege. Do not add restricted privileges to suppress permission
   errors; record those errors as evidence of the TV's boundary.
4. Import/build the project in Tizen Studio, or use the CLI from the repository
   root. Substitute your own public certificate profile:

   ```sh
   tizen build-web -- companion
   tizen package -t wgt -s YOUR_PUBLIC_CERT_PROFILE -- companion/.buildResult
   ```

5. Connect with Device Manager or SDB. Only the project's own signed widget is
   installed. Substitute the TV's actual private IP and the actual generated
   widget filename (it can contain spaces):

   ```sh
   sdb connect TV_PRIVATE_IP:26101
   sdb devices
   tizen install -s TV_PRIVATE_IP:26101 --name "ACTUAL_WIDGET_NAME.wgt" -- companion/.buildResult
   tizen run -s TV_PRIVATE_IP:26101 -p TvGuardian.Companion
   ```

   The application ID is `TvGuardian.Companion`, package ID `TvGuardian`. If the
   SDK assigns a new valid package identifier, update both consistently before
   signing. This source has not been packaged, signed or installed in this
   session; the TV's firmware may reject it. Follow SDK permission/deployment
   diagnostics without bypassing them.

Sources: [certificate workflow](https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/creating-certificates.html),
[TV connection](https://developer.samsung.com/smarttv/develop/getting-started/using-sdk/tv-device.html),
[official CLI syntax](https://developer.samsung.com/smarttv/develop/getting-started/using-sdk/command-line-interface.html).

## 3. Pair and collect evidence

1. Save the bridge HTTPS origin and parent token in the iPhone's TV Companion
   screen. Choose Create one-time pairing code.
2. On the TV app, enter that same HTTPS origin, a recognizable label and the
   12-digit code. The code expires after 120 seconds, is single-use and has
   attempt limits. A new code invalidates its predecessor.
3. The TV receives its own high-entropy bearer token over validated TLS. It stays
   in memory, expires within eight hours and cannot read parent endpoints or
   access another companion's session. Restarting requires pairing again.
4. Public inventory is reported every 30 seconds while visible. The iPhone
   refreshes reports explicitly. Reports older than 90 seconds, missing reports
   and expired sessions are stale. Every report says enforcement is **none**.
5. Explicitly associate the report with the selected TV after confirming the TV
   label. No automatic identity matching or Tizen-to-Samsung ID translation is
   invented. Imported local icon paths are not downloadable icon URLs.
6. Use Stop & erase session on the TV, or revoke it on the iPhone. Simply closing
   the companion stops reporting; a token already issued remains usable until
   expiry or revocation. Revoke old sessions when re-pairing (maximum 20).

Tizen widget CORS commonly uses origin `null`; this is the default exact allowed
origin. If your SDK/runtime sends another origin, inspect it with the supported
Web Inspector and configure that exact value. Do not use `*`. No cookie-based
authentication is used. CSP and Tizen access policy must both permit the bridge.

## Bridge contract (our API, not Samsung's)

| Method / route | Authorization | Effect |
|---|---|---|
| POST `/v1/pairing/open` | Parent bearer | Issue one-use code |
| POST `/v1/pairing/redeem` | Valid short-lived code | Issue restricted companion token |
| POST `/v1/companion/report` | Companion bearer | Store bounded public inventory |
| GET `/v1/companions` | Parent bearer | Return reports and staleness, no token hashes |
| DELETE `/v1/companions/{id}` | Parent bearer | Revoke/remove that session/report |
| DELETE `/v1/companion/session` | Companion bearer | Revoke its own session |

There is no remote command queue, shell, package manager, app lock, uninstall or
launch-interception route. Unknown routes fail. Snapshot schema version 1 always
uses `complete: false`, and permission failures remain unverified/unsupported.
The bridge stores token hashes, timestamps and app metadata; protect its disk.

## Remove development access

Use Tizen Studio to uninstall **this widget only** when no longer needed. Revoke
companion sessions, stop the bridge if unused, disconnect SDB and disable developer
mode according to Samsung's instructions. Do not expose SDB or TV ports publicly.
