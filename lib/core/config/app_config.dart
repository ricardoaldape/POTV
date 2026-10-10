class AppConfig {
  static const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

  static const controlBaseUrl = String.fromEnvironment(
    'POTV_CONTROL_URL',
    defaultValue: 'https://control.invalid',
  );

  // HTTPS endpoint for a POTV-operated, authorized content gateway.
  // The endpoint is public; partner secrets must stay on the server.
  // Normalized source resolver served by the authorized POTV gateway.
  // New source servers are delivered as data; no rebuild needed.
  // Authorized provider API base, no tokens embedded.
  static const partnerApiBaseUrl = String.fromEnvironment(
    'POTV_PARTNER_API_BASE_URL',
    defaultValue: '',
  );

  static const partnerSourcesUrl = String.fromEnvironment(
    'POTV_PARTNER_SOURCES_URL',
    defaultValue: '',
  );

  static const partnerCatalogUrl = String.fromEnvironment(
    'POTV_PARTNER_CATALOG_URL',
    defaultValue: '',
  );

  static const resolverEndpointsJson = String.fromEnvironment(
    'POTV_RESOLVER_ENDPOINTS_JSON',
    defaultValue: '[]',
  );
}
