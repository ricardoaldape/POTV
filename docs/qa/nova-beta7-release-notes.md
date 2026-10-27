# POTV beta 7 – 27 October 2026

- NOVA 1.2.9: server-side authorized catalog integration through first-party POTV gateway.
- Added separately synchronized NOVA catalog of films, series and up to 4,500 selected non-adult live channels to customers with active POTV trial/subscription.
- NFL Network channel available as a signed POTV stream from the provider's publicly listed URL with verified MPEG-TS/HLS headers; runtime Android playback is not yet certified.
- M3U, Xtream, existing servers, account system, trial and notifications preserved.
- NOVA data synchronization with private snapshot runs independently of the APK (systemd).
- Provider-restricted premium-only entries returning HTTP 402 remain unavailable until entitlement is supplied for the POTV service account. This beta is not a full commercial release.

OTA QA: require signed APK preserving package com.potv.potv and certificate, new versionCode 20, no bypass of paid-subscription controls, and Android confirmation.
