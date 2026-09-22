class NuvioPluginConfig {
  final String id;
  final String repositoryName;
  final Uri repositoryUri;
  final String name;
  final String version;
  final Uri scriptUri;
  final Set<String> supportedMediaTypes;
  final bool enabled;

  const NuvioPluginConfig({
    required this.id,
    required this.repositoryName,
    required this.repositoryUri,
    required this.name,
    required this.version,
    required this.scriptUri,
    required this.supportedMediaTypes,
    this.enabled = true,
  });

  bool supports(String mediaType) => supportedMediaTypes.contains(mediaType);

  NuvioPluginConfig copyWith({bool? enabled}) => NuvioPluginConfig(
        id: id,
        repositoryName: repositoryName,
        repositoryUri: repositoryUri,
        name: name,
        version: version,
        scriptUri: scriptUri,
        supportedMediaTypes: supportedMediaTypes,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'repository_name': repositoryName,
        'repository_uri': repositoryUri.toString(),
        'name': name,
        'version': version,
        'script_uri': scriptUri.toString(),
        'supported_media_types': supportedMediaTypes.toList()..sort(),
        'enabled': enabled,
      };

  factory NuvioPluginConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final repoName = json['repository_name']?.toString().trim();
    final repoUri = Uri.tryParse(json['repository_uri']?.toString() ?? '');
    final name = json['name']?.toString().trim();
    final version = json['version']?.toString().trim() ?? '0';
    final scriptUri = Uri.tryParse(json['script_uri']?.toString() ?? '');
    final types = (json['supported_media_types'] as List?)
        ?.map((value) => _normalizeType(value.toString()))
        .where((value) => value.isNotEmpty)
        .toSet();
    if (id == null || id.isEmpty || repoName == null || repoName.isEmpty ||
        repoUri == null || !repoUri.hasScheme || name == null || name.isEmpty ||
        scriptUri == null || !scriptUri.hasScheme || types == null || types.isEmpty) {
      throw const FormatException('Plugin Nuvio inválido');
    }
    return NuvioPluginConfig(
      id: id,
      repositoryName: repoName,
      repositoryUri: repoUri,
      name: name,
      version: version,
      scriptUri: scriptUri,
      supportedMediaTypes: types,
      enabled: json['enabled'] != false,
    );
  }

  static String normalizeType(String value) => _normalizeType(value);

  static String _normalizeType(String value) {
    switch (value.toLowerCase().trim()) {
      case 'series':
      case 'show':
        return 'tv';
      default:
        return value.toLowerCase().trim();
    }
  }
}
