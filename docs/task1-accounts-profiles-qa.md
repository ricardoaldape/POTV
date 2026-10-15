# POTV Task 1 QA — accounts, profiles and UX

Scope gate before Task 2:

- Account register/login uses email + password through the POTV API.
- Account session tokens are stored with Flutter secure storage.
- Password recovery uses a private Telegram recovery code when the account is linked.
- Telegram linking updates subscription state and expiry for the signed-in account.
- Up to five local profiles are retained per account.
- Each profile persists avatar, kids flag, audio/subtitle preference and autoplay preference.
- VOD history, VOD favorites and Live TV favorites are namespaced by active profile.
- Main navigation is Inicio, Películas, Series, Anime, TV and Deportes.
- Technical source/setup/settings routes are removed from normal navigation.
- Android build, analyze and test are required before Task 2 begins.
