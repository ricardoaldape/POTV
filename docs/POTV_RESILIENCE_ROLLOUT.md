# POTV: rollout and recovery control plane (task 4)

## Implemented in this branch
- Typed, explicit feature switches with safe defaults.
- Reject unknown/non-boolean flags, malformed payloads and non-increasing versions.
- Persist the last validated configuration, retaining it if a new payload is invalid.
- Unit tests for defaults, updates and bad configurations.

## Important security boundary
A remote manifest must be authenticated using a pinned HTTPS origin and a signature (or equivalent trusted authentication) **before** calling `applyVerifiedManifest`. This branch intentionally does **not** fetch remote JSON or trust arbitrary external input.

## Follow-up integration required
1. Wire the store at application boot and read relevant switches in the actual route, TV, sports, resolver and player layers.
2. Build a signed, versioned configuration publisher with staged rollout, a rollback procedure, and last-known-good fallback.
3. Replace individual failing channel/event catalog providers without altering user identities, preferences or subscriptions.
4. For streaming sources, retain health metrics (timeouts, startup latency, stalls, language availability) and respect authorized-provider contracts.
5. Keep the app operable with cached metadata during an outage; show a clear message if playback is unavailable rather than silently sending users to unrelated events.
6. Validate cold start, airplane mode, corrupted settings, source outage and returning connection on Android/Android TV using CI and device QA.

Feature flags update *behavior already shipped in the installed binary*. They cannot silently ship arbitrary new application code. Binary and security updates require a standard release mechanism.

## Signed remote flags (implemented in this branch)
- `POTV_SIGNED_FLAGS_URL`: HTTPS URL to an operator-controlled JSON envelope.
- `POTV_FLAGS_ED25519_PUBLIC_KEY`: base64 of the 32-byte Ed25519 public key.
- The corresponding **private signing key must remain outside the APK and Git repository**. Use protected deployment secrets or an offline release workstation.
- Set the values using Flutter compile-time `--dart-define` options; without BOTH values, remote requests are disabled.
- Format:
  ```json
  {
    "payload": "BASE64_OF_EXACT_UTF8_JSON",
    "signature": "BASE64_OF_ED25519_SIGNATURE_OF_DECODED_PAYLOAD"
  }
  ```
- Signed payload example before base64 encoding: `{"version":7,"flags":{"sports_calendar":true,"sports_event_matching":false}}`.
- Signature verification is performed over the **exact raw bytes** of the decoded payload; do not reformat the JSON after signing.
- HTTPS only, no redirect following, capped at 64 KiB, 8-second request timeout, fail-closed on any invalid response. Version must increase monotonically.
- Revert a bad release by publishing the **previously known safe flag values with a NEW higher version number**, signing that payload, and replacing the envelope on the same trusted endpoint.
- Changes are checked on app launch and on return to foreground after a six-hour cooldown; no background polling.
- Only built-in switches can change remotely. No remote code execution, credential distribution or third-party streaming endpoints.
- The sports calendar and strict EPG event matching are wired to these flags. Other defined switches still need wiring to their respective modules.
- Do **not** put a private key or production endpoint into a public issue or PR description.

### Production activation checklist
1. Generate an Ed25519 key pair using a vetted crypto tool; keep the private key secured and backed up separately.
2. Sign a minimal safe flag payload and publish its envelope under an operator-controlled HTTPS endpoint.
3. Verify signatures, wrong-key failure, invalid manifest, HTTP redirect, offline startup, corrupt cache and increasing-version rollback in staging.
4. Deploy a build with only the public key + endpoint embedded.
5. Start with an internal cohort; monitor startup, source resolution and event matching; gradually roll out.
6. For any incident, publish a higher-version signed safe configuration. Binary/security patches still require an APK update.

## GitHub-hosted control plane (provisioned as an optional workflow)
- The manual workflow `.github/workflows/potv-publish-flags.yml` signs only allowlisted boolean switches.
- Create the Actions repository secret `POTV_FLAGS_ED25519_PRIVATE_SEED` containing base64 of **32 random private seed bytes**; never store it in code, PR bodies, artifacts, or logs.
- It commits the signed JSON envelope to a dedicated `potv-runtime-config` branch, **never main**.
- The raw HTTPS manifest URL (once the first successful publication exists) is `https://raw.githubusercontent.com/ricardoaldape/POTV/potv-runtime-config/config/signed-flags.json`.
- Embed that URL using `--dart-define=POTV_SIGNED_FLAGS_URL=...` and the matching 32-byte verification public key using `--dart-define=POTV_FLAGS_ED25519_PUBLIC_KEY=...` in the Android build.
- Run workflow_dispatch with `version` strictly greater than the published version and `flags_json` containing only supported booleans. A rollback requires a **new higher version** with the previous safe values.
- The workflow is only available after this PR merges and the repository permits Actions to write to the dedicated configuration branch.
- For emergency recovery when GitHub raw content is unreachable, POTV continues using its last verified on-device flags. This does not guarantee uninterrupted streaming if third-party services fail.
- Never use a runtime flag to grant subscriptions or authorize payments; those decisions must remain server-side.
