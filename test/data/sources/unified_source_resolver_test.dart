import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/resolution/source_aggregator.dart';
import 'package:potv/data/sources/unified_source_resolver.dart';
import 'package:potv/domain/models/stream_candidate.dart';
import 'package:potv/domain/resolution/provider_resolver.dart';

class _CountingProvider extends ProviderResolver {
  int calls = 0;
  @override
  String get id => 'authorized-fixture';
  @override
  String get displayName => 'Authorized fixture';
  @override
  int get priority => 1;
  @override
  Set<String> get supportedMediaTypes => const {'movie'};

  @override
  bool supports(ProviderResolveRequest request) => request.mediaType == 'movie';

  @override
  Future<List<StreamCandidate>> resolve(ProviderResolveRequest request) async {
    calls++;
    return [
      StreamCandidate(
        id: 'fixture-$calls',
        label: 'Test',
        uri: Uri.parse('https://example.org/fixture-$calls.m3u8'),
      ),
    ];
  }
}

void main() {
  test('detail pre-resolution is reused when Play follows', () async {
    final provider = _CountingProvider();
    final resolver = UnifiedSourceResolver(SourceAggregator([provider]));
    final first = await resolver.resolve(mediaType: 'movie', mediaId: '42');
    final second = await resolver.resolve(mediaType: 'movie', mediaId: '42');
    expect(first.first.id, 'fixture-1');
    expect(second.first.id, 'fixture-1');
    expect(provider.calls, 1);
  });

  test('changing episode or media identity must not reuse a response', () async {
    final provider = _CountingProvider();
    final resolver = UnifiedSourceResolver(SourceAggregator([provider]));
    await resolver.resolve(mediaType: 'movie', mediaId: '42');
    await resolver.resolve(mediaType: 'movie', mediaId: '43');
    expect(provider.calls, 2);
  });

  test('invalidate clears both layers of resolution cache', () async {
    final provider = _CountingProvider();
    final resolver = UnifiedSourceResolver(SourceAggregator([provider]));
    await resolver.resolve(mediaType: 'movie', mediaId: '42');
    resolver.invalidate();
    final refreshed = await resolver.resolve(mediaType: 'movie', mediaId: '42');
    expect(provider.calls, 2);
    expect(refreshed.first.id, 'fixture-2');
  });
}
