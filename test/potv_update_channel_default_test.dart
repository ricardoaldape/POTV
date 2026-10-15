import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/updates/potv_update_catalog.dart';
import 'package:potv/data/updates/potv_update_center.dart';

void main() {
  test('new beta installs subscribe to beta update channel by default', () {
    expect(
      PotvUpdateCenter.defaultChannelForVersionName('1.0.0-beta.1'),
      PotvUpdateChannel.beta,
    );
    expect(
      PotvUpdateCenter.defaultChannelForVersionName('1.0.0-beta.2'),
      PotvUpdateChannel.beta,
    );
    expect(
      PotvUpdateCenter.defaultChannelForVersionName('1.0.0'),
      PotvUpdateChannel.stable,
    );
    expect(
      PotvUpdateCenter.defaultChannelForVersionName('0.8.0'),
      PotvUpdateChannel.stable,
    );
  });
}
