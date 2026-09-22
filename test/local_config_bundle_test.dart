import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/local/local_config_bundle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports and imports local TV configuration', () async {
    SharedPreferences.setMockInitialValues({
      'live_tv_m3u_url': 'https://example.com/list.m3u',
      'live_tv_xmltv_url': 'https://example.com/guide.xml',
      'potv_stremio_addons': '[{"id":"a1","name":"Demo","manifest_uri":"https://example.com/manifest.json","enabled":true}]',
    });

    final exported = await LocalConfigBundle.exportJson();

    SharedPreferences.setMockInitialValues({});
    await LocalConfigBundle.importJson(exported);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('live_tv_m3u_url'),
      'https://example.com/list.m3u',
    );
    expect(
      prefs.getString('live_tv_xmltv_url'),
      'https://example.com/guide.xml',
    );
    expect(
      prefs.getString('potv_stremio_addons'),
      contains('https://example.com/manifest.json'),
    );
  });

  test('rejects another configuration format', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      () => LocalConfigBundle.importJson(
        '{"format":"not-potv","version":1}',
      ),
      throwsFormatException,
    );
  });
}
