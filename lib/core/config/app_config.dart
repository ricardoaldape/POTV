class AppConfig {
  static const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

  static const controlBaseUrl = String.fromEnvironment(
    'POTV_CONTROL_URL',
    defaultValue: 'https://control.invalid',
  );

  // HTTPS endpoint for a POTV-operated, authorized content gateway.
  // The endpoint is public; partner secrets must stay on the server.
  static const partnerCatalogUrl = String.fromEnvironment(
    'POTV_PARTNER_CATALOG_URL',
    defaultValue: '',
  );

  static const resolverEndpointsJson = String.fromEnvironment(
    'POTV_RESOLVER_ENDPOINTS_JSON',
    defaultValue: '[]',
  );
}
