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

  static const _avatars = <String, IconData>{
    'ocean': Icons.waves_rounded,
    'rocket': Icons.rocket_launch_rounded,
    'star': Icons.star_rounded,
    'game': Icons.sports_esports_rounded,
    'film': Icons.movie_rounded,
    'smile': Icons.sentiment_satisfied_alt_rounded,
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
                          avatar: Icon(item.value, size: 18),
                          label: const Text(''),
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
                    CircleAvatar(
                      radius: 32,
                      child: Icon(
                        _avatars[active.avatarId] ?? Icons.person_rounded,
                        size: 32,
                      ),
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
                  icon: _avatars[profile.avatarId] ?? Icons.person_rounded,
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
  final IconData icon;
  final VoidCallback onTap;

  const _ProfileChoice({
    required this.profile,
    required this.selected,
    required this.icon,
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
              CircleAvatar(
                radius: selected ? 30 : 27,
                child: Icon(icon),
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
