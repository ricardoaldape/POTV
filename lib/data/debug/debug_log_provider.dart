import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

class DebugLogController extends StateNotifier<List<String>> {
  DebugLogController() : super(const <String>[]);

  void add(String message) {
    final log = message.trim();
    if (log.isEmpty) return;

    final entry = '[${DateTime.now().toIso8601String()}] $log';
    final next = <String>[...state, entry];
    if (next.length > 200) {
      state = next.sublist(next.length - 200);
    } else {
      state = next;
    }
  }

  void clear() => state = const <String>[];

  List<String> latest(int count) {
    if (count <= 0) return const <String>[];
    final start = state.length > count ? state.length - count : 0;
    return List<String>.unmodifiable(state.sublist(start));
  }
}

final debugLogController = DebugLogController();

final debugLogProvider =
    StateNotifierProvider<DebugLogController, List<String>>(
  (ref) => debugLogController,
);

void addDebugLog(String message) {
  debugLogController.add(message);
}
