import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../data/catalog/anilist_repository.dart';
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

  static const movieGenres = <_GenreSpec>[
    _GenreSpec(title: 'Acción', tmdbId: 28),
    _GenreSpec(title: 'Comedia', tmdbId: 35),
    _GenreSpec(title: 'Terror', tmdbId: 27),
  ];

  static const tvGenres = <_GenreSpec>[
    _GenreSpec(title: 'Drama', tmdbId: 18),
    _GenreSpec(title: 'Comedia', tmdbId: 35),
    _GenreSpec(title: 'Ciencia ficción y fantasía', tmdbId: 10765),
  ];

  static const animeGenres = <_GenreSpec>[
    _GenreSpec(title: 'Acción', anilistGenre: 'Action'),
    _GenreSpec(title: 'Aventura', anilistGenre: 'Adventure'),
    _GenreSpec(title: 'Comedia', anilistGenre: 'Comedy'),
  ];

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MediaItem>> trending =
        selectedType == MediaType.anime
            ? ref.watch(animeTrendingProvider)
            : ref.watch(homeTrendingProvider(selectedType));
    final AsyncValue<List<MediaItem>> popular =
        selectedType == MediaType.anime
            ? ref.watch(animePopularProvider)
            : ref.watch(homePopularProvider(selectedType));
    final genres = switch (selectedType) {
      MediaType.movie => movieGenres,
      MediaType.tv => tvGenres,
      MediaType.anime => animeGenres,
    };

    final trendingItems = trending.asData?.value ?? const <MediaItem>[];
    final popularItems = popular.asData?.value ?? const <MediaItem>[];
    final hero = trendingItems.isEmpty ? null : trendingItems.first;
    final wideHeader = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            backgroundColor: PotvTheme.background.withValues(alpha: 0.96),
            titleSpacing: 24,
            title: wideHeader
                ? Row(
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
                  )
                : const Text(
                    'POTV',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
            actions: [
              IconButton(
                tooltip: 'Buscar',
                onPressed: () => context.go('/search'),
                icon: const Icon(Icons.search_rounded),
              ),
              if (wideHeader)
                IconButton(
                  tooltip: 'Live TV',
                  onPressed: () => context.go('/live'),
                  icon: const Icon(Icons.live_tv_rounded),
                ),
              if (wideHeader)
                IconButton(
                  tooltip: 'Deportes',
                  onPressed: () => context.go('/sports'),
                  icon: const Icon(Icons.sports_soccer_rounded),
                ),
              const SizedBox(width: 8),
            ],
          ),
          if (!wideHeader)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: _MediaTypeSwitch(
                  selected: selectedType,
                  onChanged: (type) =>
                      setState(() => selectedType = type),
                ),
              ),
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
                title: switch (selectedType) {
                  MediaType.movie => 'Películas',
                  MediaType.tv => 'Series',
                  MediaType.anime => 'Anime',
                },
                subtitle: switch (selectedType) {
                  MediaType.movie =>
                    'Elige una película y POTV buscará en tus fuentes locales.',
                  MediaType.tv =>
                    'Explora series sin salir de la misma pantalla.',
                  MediaType.anime =>
                    'AniList organiza el catálogo; los episodios se resuelven localmente.',
                },
              ),
            ),
          ),
          if (popularItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: TopTenRail(
                  title: switch (selectedType) {
                    MediaType.movie => 'Top 10 películas populares',
                    MediaType.tv => 'Top 10 series populares',
                    MediaType.anime => 'Top 10 anime popular',
                  },
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
                genre: genre,
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
        ButtonSegment(
          value: MediaType.anime,
          label: Text('Anime'),
          icon: Icon(Icons.auto_awesome_outlined, size: 18),
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

class _GenreSpec {
  final String title;
  final int? tmdbId;
  final String? anilistGenre;

  const _GenreSpec({
    required this.title,
    this.tmdbId,
    this.anilistGenre,
  });
}

class _GenreSection extends ConsumerWidget {
  final MediaType type;
  final _GenreSpec genre;

  const _GenreSection({
    required this.type,
    required this.genre,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MediaItem>> state;

    if (type == MediaType.anime) {
      final name = genre.anilistGenre;
      if (name == null) return const SizedBox.shrink();
      state = ref.watch(animeGenreProvider(name));
    } else {
      final id = genre.tmdbId;
      if (id == null) return const SizedBox.shrink();
      state = ref.watch(
        homeGenreProvider((type: type, genreId: id)),
      );
    }

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
        title: genre.title,
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
