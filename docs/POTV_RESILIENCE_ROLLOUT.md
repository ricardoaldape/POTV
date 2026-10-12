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
