class ResolverEndpointConfig {
  final String id;
  final String name;
  final Uri endpoint;
  final Set<String> mediaTypes;
  final int priority;

  const ResolverEndpointConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.mediaTypes,
    this.priority = 50,
  });

  factory ResolverEndpointConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final name = json['name']?.toString().trim();
    final endpoint = Uri.tryParse(json['endpoint']?.toString() ?? '');
    final rawTypes = json['media_types'];

    final mediaTypes = rawTypes is List
        ? rawTypes
            .map((item) => item?.toString().trim().toLowerCase())
            .whereType<String>()
            .where((item) => item == 'movie' || item == 'tv' || item == 'anime')
            .toSet()
        : <String>{};

    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        endpoint == null ||
        !endpoint.hasScheme ||
        mediaTypes.isEmpty) {
      throw const FormatException('Resolver endpoint inválido');
    }

    final priority = int.tryParse(json['priority']?.toString() ?? '') ?? 50;

    return ResolverEndpointConfig(
      id: id,
      name: name,
      endpoint: endpoint,
      mediaTypes: mediaTypes,
      priority: priority,
    );
  }
}
