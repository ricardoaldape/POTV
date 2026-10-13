import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/accounts/user_profile.dart';
import '../../data/history/media_favorites_repository.dart';
import '../../data/history/playback_history_repository.dart';
import '../../data/live_tv/live_tv_favorites.dart';
import '../../providers/user_providers.dart';
import '../../ui/account/account_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _avatars = <String, _AvatarSpec>{
    'ocean': _AvatarSpec('Marea', Color(0xFF2F80ED), Color(0xFF56CCF2), 0),
    'rocket': _AvatarSpec('Nova', Color(0xFF6C5CE7), Color(0xFFA29BFE), 1),
    'star': _AvatarSpec('Sol', Color(0xFFF2994A), Color(0xFFF2C94C), 2),
    'game': _AvatarSpec('Pixel', Color(0xFF00B894), Color(0xFF55EFC4), 3),
    'film': _AvatarSpec('Noir', Color(0xFF2D3436), Color(0xFF636E72), 4),
    'smile': _AvatarSpec('Luna', Color(0xFFE84393), Color(0xFFFF7675), 5),
  };

  Future<void> _activate(WidgetRef ref, String id) async {
    await ref.read(currentProfileIdProvider.notifier).set(id);
    ref.invalidate(playbackHistoryProvider);
    ref.invalidate(mediaFavoritesProvider);
    ref.invalidate(liveTvFavoritesProvider);
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref, {
    UserProfile? profile,
  }) async {
    final name = TextEditingController(text: profile?.name ?? '');
    var avatar = profile?.avatarId ?? 'ocean';
    var kids = profile?.isKids ?? false;
    var audio = profile?.preferences.audioLanguage ?? 'es-419';
    var subtitles = profile?.preferences.subtitleLanguage ?? 'es';
    var autoplay = profile?.preferences.autoplayNext ?? true;

    final result = await showDialog<UserProfile?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(profile == null ? 'Nuevo perfil' : 'Editar perfil'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 24,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Avatar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final item in _avatars.entries)
                        ChoiceChip(
                          selected: avatar == item.key,
                          avatar: _ProfileAvatar(
                            avatarId: item.key,
                            size: 28,
                          ),
                          label: Text(item.value.label),
                          onSelected: (_) =>
                              setState(() => avatar = item.key),
                        ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Perfil infantil'),
                    subtitle: const Text('Mantiene preferencias separadas'),
                    value: kids,
                    onChanged: (value) => setState(() => kids = value),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: audio,
                    decoration:
                        const InputDecoration(labelText: 'Audio preferido'),
                    items: const [
                      DropdownMenuItem(
                        value: 'es-419',
                        child: Text('Español latino'),
                      ),
                      DropdownMenuItem(
                        value: 'es',
                        child: Text('Español'),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text('Inglés'),
                      ),
                      DropdownMenuItem(
                        value: 'original',
                        child: Text('Idioma original'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => audio = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: subtitles,
                    decoration:
                        const InputDecoration(labelText: 'Subtítulos preferidos'),
                    items: const [
                      DropdownMenuItem(
                        value: 'es',
                        child: Text('Español'),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text('Inglés'),
                      ),
                      DropdownMenuItem(
                        value: 'off',
                        child: Text('Desactivados'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => subtitles = value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reproducir siguiente episodio'),
                    value: autoplay,
                    onChanged: (value) =>
                        setState(() => autoplay = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final cleanName = name.text.trim();
                if (cleanName.isEmpty) return;
                final base = profile ??
                    UserProfile(
                      id: '',
                      accountId: '',
                      name: cleanName,
                    );
                Navigator.of(dialogContext).pop(
                  base.copyWith(
                    name: cleanName,
                    avatarId: avatar,
                    isKids: kids,
                    preferences: base.preferences.copyWith(
                      audioLanguage: audio,
                      subtitleLanguage: subtitles,
                      autoplayNext: autoplay,
                    ),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    if (result == null) return;

    if (profile == null) {
      final created = await ref.read(userProfilesProvider.notifier).addProfile(
            result.name,
            avatarId: result.avatarId,
            isKids: result.isKids,
          );
      if (created != null) {
        await ref.read(userProfilesProvider.notifier).updateProfile(
              created.copyWith(preferences: result.preferences),
            );
        await _activate(ref, created.id);
      }
    } else {
      await ref.read(userProfilesProvider.notifier).updateProfile(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(userProfilesProvider);
    final active = ref.watch(activeProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfiles'),
        actions: [
          IconButton(
            tooltip: 'Mi cuenta',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (active != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    _ProfileAvatar(
                      avatarId: active.avatarId,
                      size: 64,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            active.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            active.isKids
                                ? 'Perfil infantil'
                                : 'Perfil personal',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar perfil',
                      onPressed: () =>
                          _editProfile(context, ref, profile: active),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: profiles.length + (profiles.length < 5 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == profiles.length) {
                  return _AddProfile(
                    onTap: () => _editProfile(context, ref),
                  );
                }
                final profile = profiles[index];
                final selected = profile.id == active?.id;
                return _ProfileChoice(
                  profile: profile,
                  selected: selected,
                  onTap: () => _activate(ref, profile.id),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          ListTile(
            leading: const Icon(Icons.favorite_outline_rounded),
            title: const Text('Mi lista e historial'),
            subtitle: const Text('Favoritos y continuar viendo'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/library'),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Mi cuenta'),
            subtitle: const Text('Suscripción, Telegram y acceso'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text('Actualizar POTV'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/update-center'),
          ),
          if (active != null && profiles.length > 1) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () async {
                await ref
                    .read(userProfilesProvider.notifier)
                    .deleteProfile(active.id);
                ref.invalidate(playbackHistoryProvider);
                ref.invalidate(mediaFavoritesProvider);
                ref.invalidate(liveTvFavoritesProvider);
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Eliminar este perfil'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileChoice extends StatelessWidget {
  final UserProfile profile;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileChoice({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 82,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.all(selected ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: _ProfileAvatar(
                  avatarId: profile.avatarId,
                  size: selected ? 58 : 54,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}

class _AvatarSpec {
  final String label;
  final Color start;
  final Color end;
  final int face;

  const _AvatarSpec(this.label, this.start, this.end, this.face);
}

class _ProfileAvatar extends StatelessWidget {
  final String avatarId;
  final double size;

  const _ProfileAvatar({
    required this.avatarId,
    required this.size,
  });

  static const _specs = ProfileScreen._avatars;

  @override
  Widget build(BuildContext context) {
    final spec = _specs[avatarId] ?? _specs['ocean']!;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _AvatarPainter(spec),
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final _AvatarSpec spec;

  const _AvatarPainter(this.spec);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [spec.start, spec.end],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final center = Offset(size.width * .5, size.height * .54);
    final faceRadius = size.width * .28;
    final skin = Paint()..color = const Color(0xFFFFD7B5);
    final shadow = Paint()..color = const Color(0x22000000);
    canvas.drawCircle(
      Offset(center.dx + size.width * .025, center.dy + size.height * .035),
      faceRadius,
      shadow,
    );
    canvas.drawCircle(center, faceRadius, skin);

    final hair = Paint()..color = _hairColor(spec.face);
    final hairRect = Rect.fromCircle(center: center, radius: faceRadius);
    canvas.save();
    canvas.clipPath(Path()..addOval(hairRect));
    switch (spec.face) {
      case 1:
        canvas.drawArc(
          Rect.fromLTWH(
            center.dx - faceRadius,
            center.dy - faceRadius * 1.18,
            faceRadius * 2,
            faceRadius * 1.35,
          ),
          3.05,
          3.4,
          true,
          hair,
        );
        break;
      case 2:
        for (var i = 0; i < 5; i++) {
          final x = center.dx - faceRadius + (i * faceRadius * .48);
          canvas.drawCircle(
            Offset(x, center.dy - faceRadius * .82),
            faceRadius * .42,
            hair,
          );
        }
        break;
      case 3:
        canvas.drawRect(
          Rect.fromLTWH(
            center.dx - faceRadius,
            center.dy - faceRadius,
            faceRadius * 2,
            faceRadius * .72,
          ),
          hair,
        );
        break;
      case 4:
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: faceRadius * 1.08),
          3.12,
          3.15,
          true,
          hair,
        );
        break;
      case 5:
        canvas.drawOval(
          Rect.fromLTWH(
            center.dx - faceRadius * 1.05,
            center.dy - faceRadius * 1.08,
            faceRadius * 2.1,
            faceRadius * .95,
          ),
          hair,
        );
        break;
      default:
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: faceRadius * 1.05),
          3.0,
          3.3,
          true,
          hair,
        );
    }
    canvas.restore();

    final eye = Paint()..color = const Color(0xFF1B1B1B);
    final eyeY = center.dy - faceRadius * .04;
    canvas.drawCircle(
      Offset(center.dx - faceRadius * .36, eyeY),
      faceRadius * .075,
      eye,
    );
    canvas.drawCircle(
      Offset(center.dx + faceRadius * .36, eyeY),
      faceRadius * .075,
      eye,
    );

    final smile = Paint()
      ..color = const Color(0xFF8D4B3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * .025).clamp(1.4, 3.0)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + faceRadius * .23),
        width: faceRadius * .78,
        height: faceRadius * .48,
      ),
      .2,
      2.7,
      false,
      smile,
    );

    final shoulder = Paint()..color = const Color(0xEEFFFFFF);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * 1.02),
        width: size.width * .78,
        height: size.height * .58,
      ),
      shoulder,
    );
  }

  Color _hairColor(int face) {
    return const [
      Color(0xFF15324A),
      Color(0xFF3D2B56),
      Color(0xFF7A4D20),
      Color(0xFF263238),
      Color(0xFF101010),
      Color(0xFF5A2A4A),
    ][face.clamp(0, 5)];
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) =>
      oldDelegate.spec != spec;
}

class _AddProfile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddProfile({required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 82,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 27,
                child: Icon(Icons.add_rounded),
              ),
              SizedBox(height: 6),
              Text('Añadir'),
            ],
          ),
        ),
      );
}
