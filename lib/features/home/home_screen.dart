import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../data/catalog/tmdb_repository.dart';
import '../../domain/models/media_item.dart';
import 'widgets/home_hero.dart';
import 'widgets/media_rail.dart';
import 'widgets/top_ten_rail.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  MediaType selectedType = MediaType.movie;

  static const movieGenres = <({String title, int id})>[
    (title: 'Acción', id: 28),
    (title: 'Comedia', id: 35),
    (title: 'Terror', id: 27),
  ];

  static const tvGenres = <({String title, int id})>[
    (title: 'Drama', id: 18),
    (title: 'Comedia', id: 35),
    (title: 'Ciencia ficción y fantasía', id: 10765),
  ];

  @override
  Widget build(BuildContext context) {
    final trending = ref.watch(homeTrendingProvider(selectedType));
    final popular = ref.watch(homePopularProvider(selectedType));
    final genres = selectedType == MediaType.movie ? movieGenres : tvGenres;

    final trendingItems = trending.asData?.value ?? const <MediaItem>[];
    final popularItems = popular.asData?.value ?? const <MediaItem>[];
    final hero = trendingItems.isEmpty ? null : trendingItems.first;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            backgroundColor: PotvTheme.background.withValues(alpha: 0.96),
            titleSpacing: 24,
            title: Row(
              children: [
                const Text(
                  'POTV',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(width: 18),
                _MediaTypeSwitch(
                  selected: selectedType,
                  onChanged: (type) =>
                      setState(() => selectedType = type),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Buscar',
                onPressed: () => context.go('/search'),
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Live TV',
                onPressed: () => context.go('/live'),
                icon: const Icon(Icons.live_tv_rounded),
              ),
              IconButton(
                tooltip: 'Deportes',
                onPressed: () => context.go('/sports'),
                icon: const Icon(Icons.sports_soccer_rounded),
              ),
              const SizedBox(width: 12),
            ],
          ),
          if (hero != null)
            SliverToBoxAdapter(
              child: HomeHero(item: hero),
            )
          else
            SliverToBoxAdapter(
              child: _HeroFallback(
                loading: trending.isLoading,
                error: trending.hasError ? trending.error : null,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _SectionHeading(
                title: selectedType == MediaType.movie
                    ? 'Películas'
                    : 'Series',
                subtitle: selectedType == MediaType.movie
                    ? 'Elige una película y POTV buscará en tus fuentes locales.'
                    : 'Explora series sin salir de la misma pantalla.',
              ),
            ),
          ),
          if (popularItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: TopTenRail(
                  title: selectedType == MediaType.movie
                      ? 'Top 10 películas populares'
                      : 'Top 10 series populares',
                  items: popularItems,
                ),
              ),
            ),
          if (trendingItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: MediaRail(
                  title: 'Tendencias ahora',
                  items: trendingItems.skip(1).toList(growable: false),
                ),
              ),
            ),
          for (final genre in genres)
            SliverToBoxAdapter(
              child: _GenreSection(
                type: selectedType,
                genreId: genre.id,
                title: genre.title,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 34, 24, 56),
              child: _UtilityStrip(
                onTv: () => context.go('/live'),
                onSports: () => context.go('/sports'),
                onSearch: () => context.go('/search'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTypeSwitch extends StatelessWidget {
  final MediaType selected;
  final ValueChanged<MediaType> onChanged;

  const _MediaTypeSwitch({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MediaType>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: MediaType.movie,
          label: Text('Películas'),
          icon: Icon(Icons.movie_outlined, size: 18),
        ),
        ButtonSegment(
          value: MediaType.tv,
          label: Text('Series'),
          icon: Icon(Icons.tv_outlined, size: 18),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PotvTheme.background
              : Colors.white70,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PotvTheme.cyan
              : PotvTheme.surface,
        ),
        side: WidgetStateProperty.all(
          const BorderSide(color: Colors.white12),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenreSection extends ConsumerWidget {
  final MediaType type;
  final int genreId;
  final String title;

  const _GenreSection({
    required this.type,
    required this.genreId,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      homeGenreProvider((type: type, genreId: genreId)),
    );
    final items = state.asData?.value ?? const <MediaItem>[];

    if (state.isLoading && items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: MediaRail(
        title: title,
        items: items,
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  final bool loading;
  final Object? error;

  const _HeroFallback({
    required this.loading,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).width >= 900 ? 420 : 320,
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PotvTheme.surfaceAlt,
            PotvTheme.background,
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'POTV',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                loading
                    ? 'Preparando tu catálogo…'
                    : error == null
                        ? 'Tu catálogo aparecerá aquí.'
                        : 'Falta configurar TMDB para cargar metadatos.',
                style: const TextStyle(
                  fontSize: 17,
                  color: Colors.white70,
                ),
              ),
              if (loading) ...[
                const SizedBox(height: 18),
                const SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityStrip extends StatelessWidget {
  final VoidCallback onTv;
  final VoidCallback onSports;
  final VoidCallback onSearch;

  const _UtilityStrip({
    required this.onTv,
    required this.onSports,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _UtilityButton(
          icon: Icons.live_tv_rounded,
          label: 'Live TV',
          onTap: onTv,
        ),
        _UtilityButton(
          icon: Icons.sports_soccer_rounded,
          label: 'Sports Hub',
          onTap: onSports,
        ),
        _UtilityButton(
          icon: Icons.search_rounded,
          label: 'Buscar',
          onTap: onSearch,
        ),
      ],
    );
  }
}

class _UtilityButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UtilityButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
