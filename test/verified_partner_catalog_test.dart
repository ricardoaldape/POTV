import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:potv/data/addons/verified_partner_catalog.dart';

void main() {
  test('Verified partner addon catalog enforces HTTPS, resource labels', () {
    final entries = VerifiedPartnerAddon.parseCatalog('''
    {
      "schema": 1,
      "addons": [
        {"id": "catalog", "name": "Catalog only", "manifest": "https://meta.example/manifest.json",
         "resources": ["catalog", "meta"], "types": ["movie"], "categories": ["movies"]},
        {"id": "sub", "name": "Subtitles", "manifest": "https://sub.example/manifest.json",
         "resources": ["subtitles"], "types": ["movie", "series"], "categories": ["subtitles"]},
        {"id": "stream", "name": "Provider TV", "manifest": "https://live.example/manifest.json",
         "resources": ["stream", "catalog"], "types": ["tv"], "categories": ["live"]},
        {"id": "bad", "name": "Embedded userinfo", "manifest": "https://alice:secret@bad.example/manifest.json",
         "resources": ["stream"], "types": ["movie"]},
        {"id": "bad2", "name": "Unsafe path", "manifest": "https://bad.example/private",
         "resources": ["stream"], "types": ["movie"]},
        {"id": "catalog", "name": "Duplicate", "manifest": "https://duplicate.example/manifest.json",
         "resources": ["stream"], "types": ["movie"]}
      ]
    }''');

    expect(entries, hasLength(3));
    expect(entries[0].offersCatalog, isTrue);
    expect(entries[0].offersStreams, isFalse);
    expect(entries[0].supportsCurrentPlayback, isFalse);
    expect(entries[0].capabilityLabel, contains('sin video'));
    expect(entries[1].offersSubtitles, isTrue);
    expect(entries[1].capabilityLabel, 'Subtítulos');
    expect(entries[2].offersStreams, isTrue);
    expect(entries[2].types, contains('tv'));
    expect(entries.every((e) => e.manifestUri.scheme == 'https'), isTrue);
  });

  test('invalid schema does not silently authorize arbitrary manifests', () {
    expect(
      () => VerifiedPartnerAddon.parseCatalog('{"schema":9,"addons":[]}'),
      throwsFormatException,
    );
  });

  test('partner manifest asset includes independently verified entries',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final entries = VerifiedPartnerAddon.parseCatalog(
      await loadVerifiedCatalogForTest(),
    );
    expect(entries, hasLength(21));
    expect(entries.where((a) => a.offersStreams), hasLength(2));
    expect(entries.where((a) => a.offersSubtitles), hasLength(5));
    expect(entries.every((a) => a.manifestUri.userInfo.isEmpty), isTrue);
  });
}

Future<String> loadVerifiedCatalogForTest() async {
  return rootBundle.loadString('assets/partner_compatible_addons_kino.json');
}
