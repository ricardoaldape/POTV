import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/source_aggregator.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/resolution/provider_resolver.dart';

class _FakeProvider extends ProviderResolver {
  @override
  final String id;

  @override
  final String displayName;

  @override
  final int priority;

  @override
  final Set<String> supportedMediaTypes;

  final Future<List<StreamCandidate>> Function(ProviderResolveRequest request)
      handler;

  const _FakeProvider({
    required this.id,
    required this.displayName,
    required this.priority,
    required this.supportedMediaTypes,
    required this.handler,
  });

  @override
  bool supports(ProviderResolveRequest request) {
    return supportedMediaTypes.contains(request.mediaType);
  }

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) {
    return handler(request);
  }
}

void main() {
  test('queries every eligible provider and merges candidates', () async {
    final aggregator = SourceAggregator([
      _FakeProvider(
        id: 'movie-a',
        displayName: 'Movie A',
        priority: 10,
        supportedMediaTypes: const {'movie'},
        handler: (_) async => [
          StreamCandidate(
            id: 'a',
            label: 'A',
            uri: Uri.parse('https://example.com/a.m3u8'),
          ),
        ],
      ),
      _FakeProvider(
        id: 'movie-b',
        displayName: 'Movie B',
        priority: 20,
        supportedMediaTypes: const {'movie'},
        handler: (_) async => [
          StreamCandidate(
            id: 'b',
            label: 'B',
            uri: Uri.parse('https://example.com/b.m3u8'),
          ),
        ],
      ),
      _FakeProvider(
        id: 'anime-only',
        displayName: 'Anime',
        priority: 30,
        supportedMediaTypes: const {'anime'},
        handler: (_) async => throw StateError('should not run'),
      ),
    ]);

    final result = await aggregator.resolve(
      const ProviderResolveRequest(
        mediaType: 'movie',
        mediaId: '123',
        title: 'Demo',
      ),
    );

    expect(result.providersEligible, 2);
    expect(result.providersCompleted, 2);
    expect(result.providersFailed, 0);
    expect(result.candidates.map((item) => item.id), ['a', 'b']);
  });

  test('one provider failure does not stop the remaining providers', () async {
    final aggregator = SourceAggregator([
      _FakeProvider(
        id: 'broken',
        displayName: 'Broken',
        priority: 10,
        supportedMediaTypes: const {'tv'},
        handler: (_) async => throw StateError('offline'),
      ),
      _FakeProvider(
        id: 'working',
        displayName: 'Working',
        priority: 20,
        supportedMediaTypes: const {'tv'},
        handler: (_) async => [
          StreamCandidate(
            id: 'working-stream',
            label: 'Working',
            uri: Uri.parse('https://example.com/episode.mp4'),
          ),
        ],
      ),
    ]);

    final result = await aggregator.resolve(
      const ProviderResolveRequest(
        mediaType: 'tv',
        mediaId: '456',
        season: 2,
        episode: 4,
      ),
    );

    expect(result.providersEligible, 2);
    expect(result.providersCompleted, 1);
    expect(result.providersFailed, 1);
    expect(result.candidates.single.id, 'working-stream');
  });

  test('provider timeout is isolated from successful providers', () async {
    final aggregator = SourceAggregator(
      [
        _FakeProvider(
          id: 'slow',
          displayName: 'Slow',
          priority: 10,
          supportedMediaTypes: const {'anime'},
          handler: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const [];
          },
        ),
        _FakeProvider(
          id: 'fast',
          displayName: 'Fast',
          priority: 20,
          supportedMediaTypes: const {'anime'},
          handler: (_) async => [
            StreamCandidate(
              id: 'anime-stream',
              label: 'Fast',
              uri: Uri.parse('https://example.com/anime.m3u8'),
            ),
          ],
        ),
      ],
      providerTimeout: const Duration(milliseconds: 20),
    );

    final result = await aggregator.resolve(
      const ProviderResolveRequest(
        mediaType: 'anime',
        mediaId: '20',
        episode: 53,
      ),
    );

    expect(result.providersEligible, 2);
    expect(result.providersCompleted, 2);
    expect(result.providersFailed, 0);
    expect(result.candidates.single.id, 'anime-stream');
  });

  test('reuses cached resolution for the same media identity', () async {
    var calls = 0;
    final aggregator = SourceAggregator([
      _FakeProvider(
        id: 'cached',
        displayName: 'Cached',
        priority: 10,
        supportedMediaTypes: const {'movie'},
        handler: (_) async {
          calls++;
          return [
            StreamCandidate(
              id: 'cached-stream',
              label: 'Cached',
              uri: Uri.parse('https://example.com/cached.m3u8'),
            ),
          ];
        },
      ),
    ]);

    const request = ProviderResolveRequest(
      mediaType: 'movie',
      mediaId: '42',
    );

    final first = await aggregator.resolve(request);
    final second = await aggregator.resolve(request);

    expect(first.candidates.single.id, 'cached-stream');
    expect(second.candidates.single.id, 'cached-stream');
    expect(calls, 1);
  });

  test('deduplicates simultaneous resolution requests', () async {
    var calls = 0;
    final aggregator = SourceAggregator([
      _FakeProvider(
        id: 'shared',
        displayName: 'Shared',
        priority: 10,
        supportedMediaTypes: const {'tv'},
        handler: (_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return [
            StreamCandidate(
              id: 'shared-stream',
              label: 'Shared',
              uri: Uri.parse('https://example.com/shared.m3u8'),
            ),
          ];
        },
      ),
    ]);

    const request = ProviderResolveRequest(
      mediaType: 'tv',
      mediaId: '99',
      season: 1,
      episode: 2,
    );

    final results = await Future.wait([
      aggregator.resolve(request),
      aggregator.resolve(request),
      aggregator.resolve(request),
    ]);

    expect(results, hasLength(3));
    expect(calls, 1);
  });

}
