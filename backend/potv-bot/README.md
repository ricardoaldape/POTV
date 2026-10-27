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
