# POTV bot + account backend

This directory is the reproducible source for the POTV Telegram bot and the
account/subscription API consumed by the Flutter app.

## Included

- `app.py`: Telegram polling + HTTP API.
- `account_store.py`: local SQLite accounts, password hashing, sessions,
  password recovery, Telegram linkage and subscription synchronization.
- `potv_ops.py`: sales/support/community bot workflows.
- `content_gateway.py`: authorized M3U/Xtream catalog normalizer and credential-safe HTTPS stream proxy.
- `group_config.py`: deployment routing loaded from environment variables.
- `account_store_smoke.py`: isolated account lifecycle test.
- `qa_smoke.py`: isolated sales/support/admin authorization regression test.

No production token, database, recovery code, license token or private
credential belongs in GitHub.

## API contract used by the app

- `POST /api/v1/account/register`
- `POST /api/v1/account/login`
- `GET /api/v1/account/session`
- `POST /api/v1/account/logout`
- `POST /api/v1/account/recover`
- `POST /api/v1/account/recover/confirm`
- `POST /api/v1/link/claim`
- `GET /api/v1/license/status`
- `GET /api/v1/content/catalog`
- `GET /api/v1/content/stream/<opaque-id>` (short-lived signed proxy URL)

Recovery is intentionally non-enumerating: the request endpoint responds as
accepted even when no linked account exists. When a linked Telegram account is
available, the short-lived recovery code is sent privately through the bot.
Password changes invalidate existing account sessions.

## Local verification

```bash
cd backend/potv-bot
python3 -m py_compile app.py account_store.py potv_ops.py group_config.py content_gateway.py
python3 account_store_smoke.py
python3 qa_smoke.py
python3 content_gateway_smoke.py
POTV_DB=/tmp/potv-self-test.sqlite3 python3 app.py --self-test
```

## Deployment

Copy `.env.example` to the server's protected environment configuration,
provide the real values there, keep the SQLite database and partner source files outside version
control, and run `app.py` behind the existing HTTPS reverse proxy. Partner credentials belong only in
`POTV_CONTENT_SOURCES_FILE`; the catalog returns opaque signed POTV URLs instead of upstream secrets.
Optional `POTV_CONTENT_METADATA_FILE` supplies `now_next` and `sports_events`; events without an explicit
stream are intentionally omitted from the playable catalog.

The Flutter client contract is defined in
`lib/config/subscription_endpoint.dart`. The production base remains
`https://potv.fxqubit.com/api/v1`.

## Separate TV source aggregation

For licensed multi-provider lineups, set `POTV_CONTENT_LIVE_SOURCE_MODE=merge`.
This combines distinct live channels across sources even if
`POTV_CONTENT_SOURCE_MODE=failover` is used for VOD. It does not
repair HTTP 502 upstream outages or guarantee any particular channel,
and does not change the existing stream authorization checks.
Without this variable, live TV preserves the previous mode.

### NOVA provider interoperability (private, opt-in)

The nova_partner.py API client is compatible with paths observed in NOVA
1.2.9's Retrofit interface. Use a provider-issued POTV service account,
not an embedded APK session. Create a non-Git file such as
/opt/potv-bot/secrets/nova-service.json with JSON fields api_base_url
(HTTPS API root ending with /) and service_access_token (issued by NOVA).
Set POTV_NOVA_SERVICE_FILE to that private file and run
python3 nova_partner_smoke.py. It does not activate public playback routes
or bypass POTV customer entitlement checks.

## NOVA live catalog and VOD subscription integration

NOVA 1.2.9's authorized HTTP API has been checked against its primary and
fallback hosts. The server consumes its documented catalog interfaces through
a configurable private service file. A provider login token is used only if
the issuer supplies one; a public, unauthenticated feed is used only when
allow_anonymous_catalog is explicitly true in the service file.

A separate systemd timer runs nova_catalog_sync.py to fetch the provider
catalog into a root-readable 0600 snapshot. The API process uses the filtered
snapshot rather than parsing the 18MB+ upstream channel directory on each user
request. Selected feeds focus Mexico, LATAM and US/ES sports; Argentine and
adult channels are excluded, and non-playable rows are omitted.

Required VPS configuration:
- POTV_NOVA_SERVICE_FILE: protected JSON with api_base_url ending /api/
  and backup_api_base_url when authorized by the issuer.
- POTV_NOVA_SYNC_FILE: protected NOVA channel snapshot local path.
- POTV_NOVA_LIVE_ENABLED=true: merge channels for POTV subscribed accounts.
- POTV_NOVA_VOD_ENABLED=true: enable NOVA film/episode on-demand sources.
- POTV_NOVA_CHANNEL_LIMIT: maximum, default 4500.

The public catalog remains unchanged for unauthenticated visitors. The API
checks a valid POTV subscription/trial before exposing the enriched catalog or
paid VOD resolution. The Flutter client sends its POTV token only to the
first-party gateway. Upstream HTTP 401/402/403 is never bypassed; provider-only
premium channels without playable sources require an issuer-granted entitlement.

Playback caveat: native HLS/MPEG-TS channels have verified sample media
headers, while some VOD rows contain embedding-only sources that may still
need provider-side extraction or licensed direct streams. Real Android
decode and OTA installation are separate release acceptance gates.

Systemd timer artifacts are committed under ops/systemd. Install them at
/etc/systemd/system and enable potv-nova-sync.timer after placing the
provider settings and output snapshot in protected files on the VPS.
On upstream API outage, the last known good snapshot stays intact.
A signed subscriber stream target is rebuilt from that private snapshot
after a POTV API process restart; anonymous clients still do not receive
the premium catalog.


### Legacy OTA manifest (older Android clients)

The /api/v1/version/latest endpoint reads version.json. Newer POTV
Update Center checks official GitHub Releases directly; older clients
still need the legacy JSON endpoint. ota_manifest_sync.py reconciles
against published releases under ricardoaldape/POTV and requires a
matching APK asset, GitHub-provided SHA-256 digest, release notes with
POTV-Version-Code, canonical HTTPS URL, and versionCode strictly greater
than the installed manifest. Invalid or unavailable releases leave the
current manifest untouched. The script does not install APKs or bypass
Android's user confirmation.

Deploy ops/systemd/potv-ota-manifest.service and .timer on the VPS and
enable the timer. Before enabling, create /opt/potv-bot/ota-state and
copy the current version.json into ota-state/version.json. Replace the
legacy /opt/potv-bot/version.json file with a relative symlink pointing to
ota-state/version.json (keep a backup). This allows systemd to grant write
access only to ota-state while the public endpoint keeps reading its old
path. Do not grant the updater write access to the whole application tree.
The unit uses --allow-beta because POTV's current
official channel is prerelease; omit it for stable releases only.
Verify before enabling with:
    python3 ota_manifest_sync.py --allow-beta --dry-run
Never point apk_url to a build artifact or unsigned QA candidate.
