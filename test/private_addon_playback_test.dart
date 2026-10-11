import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:potv/data/addons/stremio_addon_repository.dart';
import 'package:potv/data/addons/stremio_subtitle_service.dart';
import 'package:potv/domain/models/playback_session.dart';
import 'package:potv/domain/services/playback_language_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecrets implements AddonSecretStore {
  final values = <String, String>{};

  @override
  Future<void> write(String key, String value) async { values[key] = value; }
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async { values.remove(key); }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('private addon URI is encrypted by storage adapter, not preferences',
      () async {
    final secrets = _MemorySecrets();
    final repository = StremioAddonRepository(secrets: secrets);
    final uri = Uri.parse(
      'https://addon.example/hidden-config/manifest.json',
    );
    final item = await repository.add(name: 'Private addon', manifestUri: uri);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('potv_stremio_addons')!;
    expect(saved, isNot(contains('auth_token')));
    expect(saved, isNot(contains('manifest.json')));
    expect(saved, isNot(contains('hidden-config')));
    expect(secrets.values.values.single, uri.toString());
    expect((await repository.load()).single.manifestUri, uri);
    await repository.update(item.copyWith(enabled: false));
    expect((await repository.load()).single.enabled, isFalse);
    await repository.remove(item.id);
    expect(await repository.load(), isEmpty);
    expect(secrets.values, isEmpty);
  });

  test('legacy URLs migrate to encrypted secret store before scrubbing prefs',
      () async {
    final legacy = Uri.parse('https://old-addon.example/private/manifest.json');
    SharedPreferences.setMockInitialValues({
      'potv_stremio_addons': jsonEncode([
        {'id':'legacy-1','name':'Legacy','enabled':true,
         'manifest_uri':legacy.toString()}
      ]),
    });
    final secrets = _MemorySecrets();
    final repository = StremioAddonRepository(secrets: secrets);
    final addons = await repository.load();
    expect(addons, hasLength(1));
    expect(addons.single.manifestUri, legacy);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('potv_stremio_addons'), isNot(contains('manifest_uri')));
    expect(secrets.values.values.single, legacy.toString());
  });

  test('subtitle parser selects valid HTTPS Spanish files first', () {
    final captions = StremioSubtitle.parse({
      'subtitles': [
        {'id':'a','url':'https://subs.example/english.vtt','lang':'eng'},
        {'id':'b','url':'https://subs.example/es.srt','lang':'es-MX'},
        {'id':'c','url':'http://subs.example/nope.srt','lang':'es'},
        {'id':'d','url':'https://subs.example/castellano.srt','lang':'spa'}
      ]
    });
    expect(captions, hasLength(3));
    expect(captions.first.isSpanish, isTrue);
    expect(captions.last.language, 'eng');
  });

  test('subtitle service only calls addon with subtitle manifest resource',
      () async {
    final secrets = _MemorySecrets();
    final repository = StremioAddonRepository(secrets: secrets);
    await repository.add(
      name: 'Demo',
      manifestUri: Uri.parse('https://addon.example/config/manifest.json'),
    );
    final dio = Dio();
    final fetched = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      fetched.add(options.uri.path);
      if (options.uri.path.endsWith('manifest.json')) {
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
          'id': 'demo', 'name': 'Demo','resources':['stream','subtitles'],
          'types':['movie','series'],
        }));
      } else {
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
          'subtitles':[
            {'id':'spanish','lang':'es','url':'https://captions.example/movie.srt'}
          ]
        }));
      }
    }));
    final subtitles = await StremioSubtitleService(repository, dio)
        .forPlayback(const PlaybackContext(
          mediaId: 123,
          mediaType: 'movie',
          title: 'Sample',
          externalId: 'tt1254207',
        ));
    expect(subtitles, hasLength(1));
    expect(subtitles.single.isSpanish, isTrue);
    expect(fetched.last, '/config/subtitles/movie/tt1254207.json');
  });

  test('Latino audio outranks Spanish and English; Spanish captions fallback',
      () {
    const selector = PlaybackLanguageSelector();
    final tracks = [
      const AudioTrack('1','Original','en'),
      const AudioTrack('2','Español latino','es-MX'),
      const AudioTrack('3','Castellano','es'),
    ];
    expect(selector.preferredAudio(tracks)?.id, '2');
    expect(selector.preferredAudio([tracks.first]), isNull);
    expect(selector.preferredEmbeddedSubtitle([
      const SubtitleTrack('2','English','en'),
      const SubtitleTrack('3','Spanish','spa'),
    ])?.id, '3');
    expect(selector.isSpanishAudio(track: tracks[1]), isTrue);
    expect(selector.isSpanishAudio(streamLanguage: 'es-MX'), isTrue);
    expect(selector.isSpanishAudio(track: tracks.first), isFalse);
  });
}
