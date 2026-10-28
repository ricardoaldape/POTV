import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/catalog/partner_content_repository.dart';
import 'package:potv/domain/models/media_item.dart';
import 'package:potv/features/browse/partner_media_browse_screen.dart';

class _FlakyMediaRepository extends PartnerContentRepository {
  _FlakyMediaRepository()
      : super(
          Dio(),
          endpoint: Uri.parse('https://potv.fxqubit.com/api/v1/content/catalog'),
        );

  int calls = 0;

  @override
  Future<PartnerMediaPage> loadMediaPage(
    MediaType type, {
    int offset = 0,
    int limit = 200,
  }) async {
    calls++;
    if (calls == 1) throw StateError('Temporary network failure');
    return PartnerMediaPage(
      type: type,
      revision: 'fixture',
      total: 1,
      offset: offset,
      limit: limit,
      hasMore: false,
      items: const [
        MediaItem(id: 42, type: MediaType.movie, title: 'Película recuperada'),
      ],
    );
  }
}

void main() {
  testWidgets('first VOD page failure offers a working retry', (tester) async {
    final repository = _FlakyMediaRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partnerContentRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const MaterialApp(
          home: PartnerMediaBrowseScreen(
            type: MediaType.movie,
            title: 'Películas',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('No se pudo cargar el catálogo'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Película recuperada'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('1 de 1 títulos'), findsOneWidget);
  });
}
