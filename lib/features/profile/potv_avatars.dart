import 'package:flutter/material.dart';

/// Built-in, offline and license-free avatar collection using Material icons.
/// No user uploads, image tracking or server storage.
class PotvAvatars {
  static const icons = <String, IconData>{
    'default': Icons.person_rounded,
    'pirate': Icons.sailing_rounded,
    'robot': Icons.smart_toy_rounded,
    'cat': Icons.pets_rounded,
    'star': Icons.star_rounded,
    'rocket': Icons.rocket_launch_rounded,
    'game': Icons.sports_esports_rounded,
    'music': Icons.music_note_rounded,
    'planet': Icons.public_rounded,
    'heart': Icons.favorite_rounded,
    'sun': Icons.wb_sunny_rounded,
    'moon': Icons.nightlight_rounded,
    'bolt': Icons.bolt_rounded,
    'leaf': Icons.eco_rounded,
    'diamond': Icons.diamond_rounded,
    'mask': Icons.theater_comedy_rounded,
  };

  static IconData iconFor(String id) => icons[id] ?? icons['default']!;

  static Color backgroundFor(String id) {
    final index = icons.keys.toList().indexOf(id);
    return Colors.primaries[(index < 0 ? 0 : index) % Colors.primaries.length]
        .shade700;
  }
}

class PotvAvatar extends StatelessWidget {
  const PotvAvatar({super.key, required this.avatarId, this.radius = 28});

  final String avatarId;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: PotvAvatars.backgroundFor(avatarId),
        child: Icon(PotvAvatars.iconFor(avatarId),
            size: radius * 1.1, color: Colors.white),
      );
}
