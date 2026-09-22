import 'package:flutter_test/flutter_test.dart';
import 'package:potv/core/local/local_config_bundle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports and imports local TV configuration', () async {
    SharedPreferences.setMockInitialValues({
      'live_tv_m3u_url': 'https://example.com/list.m3u',
      'live_tv_xmltv_url': 'https://example.com/guide.xml',
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
