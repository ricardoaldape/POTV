import 'stremio_addon_config.dart';

class AddonSportsItem {
  final StremioAddonConfig addon;
  final String id;
  final String type;
  final String name;
  final String? description;
  final Uri? poster;
  final String? genre;
  final bool isLive;

  const AddonSportsItem({
    required this.addon,
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.poster,
    this.genre,
    this.isLive = false,
  });
}
