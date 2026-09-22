class HttpSourceConfig {
  final String id;
  final String name;
  final Uri endpoint;
  final bool enabled;

  const HttpSourceConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    this.enabled = true,
  });

  HttpSourceConfig copyWith({
    String? name,
    Uri? endpoint,
    bool? enabled,
  }) {
    return HttpSourceConfig(
      id: id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'endpoint': endpoint.toString(),
        'enabled': enabled,
      };

  factory HttpSourceConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final name = json['name']?.toString().trim();
    final endpoint = Uri.tryParse(json['endpoint']?.toString() ?? '');
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        endpoint == null ||
        !endpoint.hasScheme) {
      throw const FormatException('Fuente HTTP inválida');
    }

    return HttpSourceConfig(
      id: id,
      name: name,
      endpoint: endpoint,
      enabled: json['enabled'] != false,
    );
  }
}
