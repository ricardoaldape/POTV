class AppConfig {
  static const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

  static const controlBaseUrl = String.fromEnvironment(
    'POTV_CONTROL_URL',
    defaultValue: 'https://control.invalid',
  );

  static const resolverEndpointsJson = String.fromEnvironment(
    'POTV_RESOLVER_ENDPOINTS_JSON',
    defaultValue: '[]',
  );
}
