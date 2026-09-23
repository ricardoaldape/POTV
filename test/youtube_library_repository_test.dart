import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potv/features/youtube/data/youtube_library_repository.dart';
import 'package:potv/features/youtube/domain/youtube_models.dart';

void main() {
  const repository = YoutubeLibraryRepository();
  const first = PotvYoutubeVideo(
    id: 'video-1',
    title: 'Video uno',
    author: 'Canal',
    channelId: 'UC1234567890123456789012',
    thumbnailUrl: 'https://example.test/one.jpg',
    viewCount: 10,
  );
  const second = PotvYoutubeVideo(
    id: 'video-2',
    title: 'Video dos',
    author: 'Canal',
    channelId: 'UC1234567890123456789012',
    thumbnailUrl: 'https://example.test/two.jpg',
    viewCount: 20,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bookmarks persist and toggle', () async {
    expect(await repository.bookmarks(), isEmpty);

    await repository.toggleBookmark(first);
    expect((await repository.bookmarks()).single.id, first.id);
    expect(await repository.isBookmarked(first.id), isTrue);

    await repository.toggleBookmark(first);
    expect(await repository.bookmarks(), isEmpty);
  });

  test('history keeps most recent video first without duplicates', () async {
    await repository.addToHistory(first);
    await repository.addToHistory(second);
    await repository.addToHistory(first);

    final history = await repository.history();
    expect(history.map((item) => item.id).toList(), ['video-1', 'video-2']);
  });

  test('clearHistory removes youtube history', () async {
    await repository.addToHistory(first);
    await repository.clearHistory();
    expect(await repository.history(), isEmpty);
  });
}
