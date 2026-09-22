class StremioAddonConfig {
  final String id;
  final String name;
  final Uri manifestUri;
  final bool enabled;

  const StremioAddonConfig({
    required this.id,
    required this.name,
    required this.manifestUri,
    this.enabled = true,
  });

  Uri get baseUri {
    final segments = [...manifestUri.pathSegments];
    if (segments.isNotEmpty && segments.last == 'manifest.json') {
      segments.removeLast();
    }
    return manifestUri.replace(
      pathSegments: segments,
      query: null,
      fragment: null,
    );
  }

  StremioAddonConfig copyWith({
    String? name,
    Uri? manifestUri,
    bool? enabled,
  }) {
    return StremioAddonConfig(
      id: id,
      name: name ?? this.name,
      manifestUri: manifestUri ?? this.manifestUri,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'manifest_uri': manifestUri.toString(),
        'enabled': enabled,
      };

  factory StremioAddonConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final name = json['name']?.toString().trim();
    final manifest = Uri.tryParse(json['manifest_uri']?.toString() ?? '');

    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        manifest == null ||
        (manifest.scheme != 'http' && manifest.scheme != 'https')) {
      throw const FormatException('Addon Stremio/Nuvio inválido');
    }

    return StremioAddonConfig(
      id: id,
      name: name,
      manifestUri: manifest,
      enabled: json['enabled'] != false,
    );
  }
}
