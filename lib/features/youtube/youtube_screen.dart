import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/youtube_client.dart';
import 'data/youtube_library_repository.dart';
import 'data/youtube_providers.dart';
import 'data/youtube_subscription_repository.dart';
import 'domain/youtube_models.dart';
import 'widgets/youtube_video_card.dart';

class YoutubeScreen extends ConsumerStatefulWidget {
  const YoutubeScreen({super.key});

  @override
  ConsumerState<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends ConsumerState<YoutubeScreen> {
  final searchController = TextEditingController();
  Future<List<PotvYoutubeVideo>>? searchFuture;
  String currentQuery = '';

  static const quickSearches = [
    'Música',
    'Gaming',
    'Tecnología',
    'Documentales',
    'Noticias',
    'Ciencia',
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _search([String? value]) {
    final query = (value ?? searchController.text).trim();
    if (query.isEmpty) return;
    searchController.text = query;
    setState(() {
      currentQuery = query;
      searchFuture = ref.read(potvYoutubeClientProvider).search(query);
    });
  }

  Future<void> _importSubscriptions() async {
    try {
      final count = await ref.read(youtubeSubscriptionRepositoryProvider).importFromPicker();
      ref.invalidate(youtubeSubscriptionsProvider);
      ref.invalidate(youtubeSubscriptionFeedProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count == 0 ? 'No se encontraron suscripciones nuevas.' : '$count suscripciones importadas.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos importar el archivo: $error')),
      );
    }
  }

  void _openVideo(PotvYoutubeVideo video) {
    context.push('/youtube/video', extra: video);
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = ref.watch(youtubeSubscriptionsProvider);
    final feed = ref.watch(youtubeSubscriptionFeedProvider);
    final bookmarks = ref.watch(youtubeBookmarksProvider);
    final history = ref.watch(youtubeHistoryProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('POTV YT', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              tooltip: 'Importar suscripciones',
              onPressed: _importSubscriptions,
              icon: const Icon(Icons.file_upload_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.explore_outlined), text: 'Explorar'),
              Tab(icon: Icon(Icons.subscriptions_outlined), text: 'Suscripciones'),
              Tab(icon: Icon(Icons.video_library_outlined), text: 'Biblioteca'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ExploreTab(
              controller: searchController,
              future: searchFuture,
              query: currentQuery,
              quickSearches: quickSearches,
              onSearch: _search,
              onOpen: _openVideo,
            ),
            _SubscriptionsTab(
              subscriptions: subscriptions,
              feed: feed,
              onImport: _importSubscriptions,
              onRefresh: () async {
                ref.invalidate(youtubeSubscriptionFeedProvider);
                await ref.read(youtubeSubscriptionFeedProvider.future);
              },
              onOpen: _openVideo,
              onOpenChannel: (item) => context.push('/youtube/channel', extra: item.channelId),
            ),
            _LibraryTab(
              bookmarks: bookmarks,
              history: history,
              onOpen: _openVideo,
              onClearHistory: () async {
                await ref.read(youtubeLibraryRepositoryProvider).clearHistory();
                ref.invalidate(youtubeHistoryProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreTab extends StatelessWidget {
  final TextEditingController controller;
  final Future<List<PotvYoutubeVideo>>? future;
  final String query;
  final List<String> quickSearches;
  final ValueChanged<String> onSearch;
  final ValueChanged<PotvYoutubeVideo> onOpen;

  const _ExploreTab({
    required this.controller,
    required this.future,
    required this.query,
    required this.quickSearches,
    required this.onSearch,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: SearchBar(
            controller: controller,
            hintText: 'Buscar en YouTube',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              IconButton(
                onPressed: () => onSearch(controller.text),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
            onSubmitted: onSearch,
          ),
        ),
        if (future == null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in quickSearches)
                  ActionChip(label: Text(item), onPressed: () => onSearch(item)),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 72),
                    SizedBox(height: 16),
                    Text('YouTube dentro de POTV', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    SizedBox(height: 8),
                    Text(
                      'Busca videos y reprodúcelos con el player de POTV. Tus suscripciones se guardan localmente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else
          Expanded(
            child: FutureBuilder<List<PotvYoutubeVideo>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _Message(icon: Icons.error_outline_rounded, title: 'No pudimos buscar', body: '${snapshot.error}');
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return _Message(icon: Icons.search_off_rounded, title: 'Sin resultados', body: 'No encontramos resultados para “$query”.');
                }
                return _VideoGrid(items: items, onOpen: onOpen);
              },
            ),
          ),
      ],
    );
  }
}

class _SubscriptionsTab extends StatelessWidget {
  final AsyncValue<List<PotvYoutubeSubscription>> subscriptions;
  final AsyncValue<List<PotvYoutubeVideo>> feed;
  final Future<void> Function() onImport;
  final Future<void> Function() onRefresh;
  final ValueChanged<PotvYoutubeVideo> onOpen;
  final ValueChanged<PotvYoutubeSubscription> onOpenChannel;

  const _SubscriptionsTab({
    required this.subscriptions,
    required this.feed,
    required this.onImport,
    required this.onRefresh,
    required this.onOpen,
    required this.onOpenChannel,
  });

  @override
  Widget build(BuildContext context) {
    final subs = subscriptions.asData?.value ?? const <PotvYoutubeSubscription>[];
    if (subscriptions.isLoading) return const Center(child: CircularProgressIndicator());
    if (subs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.subscriptions_outlined, size: 64),
              const SizedBox(height: 14),
              const Text('Tus canales, sin iniciar sesión', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Suscríbete desde POTV o importa subscriptions.csv/json desde Google Takeout.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.file_upload_outlined), label: const Text('Importar suscripciones')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 104,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                scrollDirection: Axis.horizontal,
                itemCount: subs.length,
                separatorBuilder: (_, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = subs[index];
                  return InkWell(
                    onTap: () => onOpenChannel(item),
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 78,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundImage: item.logoUrl == null ? null : NetworkImage(item.logoUrl!),
                            child: item.logoUrl == null ? const Icon(Icons.person_rounded) : null,
                          ),
                          const SizedBox(height: 5),
                          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          feed.when(
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (error, stack) => SliverFillRemaining(child: _Message(icon: Icons.error_outline_rounded, title: 'No pudimos actualizar el feed', body: '$error')),
            data: (items) => items.isEmpty
                ? const SliverFillRemaining(child: _Message(icon: Icons.video_library_outlined, title: 'Sin videos recientes', body: 'Tus canales no devolvieron videos recientes.'))
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.sizeOf(context).width >= 1100 ? 4 : MediaQuery.sizeOf(context).width >= 700 ? 3 : 1,
                        childAspectRatio: MediaQuery.sizeOf(context).width >= 700 ? 1.15 : 1.45,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => YoutubeVideoCard(video: items[index], onTap: () => onOpen(items[index])),
                        childCount: items.length,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTab extends StatelessWidget {
  final AsyncValue<List<PotvYoutubeVideo>> bookmarks;
  final AsyncValue<List<PotvYoutubeVideo>> history;
  final ValueChanged<PotvYoutubeVideo> onOpen;
  final Future<void> Function() onClearHistory;

  const _LibraryTab({
    required this.bookmarks,
    required this.history,
    required this.onOpen,
    required this.onClearHistory,
  });

  @override
  Widget build(BuildContext context) {
    final saved = bookmarks.asData?.value ?? const <PotvYoutubeVideo>[];
    final watched = history.asData?.value ?? const <PotvYoutubeVideo>[];
    if (bookmarks.isLoading || history.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Guardados', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                Text('${saved.length}', style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
        if (saved.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text('Guarda videos desde su ficha para encontrarlos aquí.', style: TextStyle(color: Colors.white60)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 1100 ? 4 : MediaQuery.sizeOf(context).width >= 700 ? 3 : 1,
                childAspectRatio: MediaQuery.sizeOf(context).width >= 700 ? 1.15 : 1.45,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => YoutubeVideoCard(video: saved[index], onTap: () => onOpen(saved[index])),
                childCount: saved.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Historial', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                if (watched.isNotEmpty)
                  TextButton.icon(
                    onPressed: onClearHistory,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpiar'),
                  ),
              ],
            ),
          ),
        ),
        if (watched.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Text('Los videos que reproduzcas aparecerán aquí.', style: TextStyle(color: Colors.white60)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 1100 ? 4 : MediaQuery.sizeOf(context).width >= 700 ? 3 : 1,
                childAspectRatio: MediaQuery.sizeOf(context).width >= 700 ? 1.15 : 1.45,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => YoutubeVideoCard(video: watched[index], onTap: () => onOpen(watched[index])),
                childCount: watched.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoGrid extends StatelessWidget {
  final List<PotvYoutubeVideo> items;
  final ValueChanged<PotvYoutubeVideo> onOpen;

  const _VideoGrid({required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 4 : width >= 700 ? 3 : 1;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: columns == 1 ? 1.45 : 1.15,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => YoutubeVideoCard(video: items[index], onTap: () => onOpen(items[index])),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
            const SizedBox(height: 7),
            Text(body, style: const TextStyle(color: Colors.white60), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
