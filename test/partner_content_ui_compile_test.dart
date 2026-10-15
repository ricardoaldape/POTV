import 'package:flutter_test/flutter_test.dart';
import 'package:potv/features/home/home_screen.dart';
import 'package:potv/features/live_tv/live_tv_screen.dart';
import 'package:potv/features/sports/sports_hub_screen.dart';

void main() {
  test('dynamic content screens remain instantiable without partner access', () {
    expect(const HomeScreen(), isA<HomeScreen>());
    expect(const LiveTvScreen(), isA<LiveTvScreen>());
    expect(const SportsHubScreen(), isA<SportsHubScreen>());
  });
}
