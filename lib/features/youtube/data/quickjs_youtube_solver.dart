import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:youtube_explode_dart/js_challenge.dart';

class QuickJsYoutubeSolver extends BaseEJSSolver {
  final dynamic _runtime = getJavascriptRuntime(
    xhr: false,
    extraArgs: const {'stackSize': 8 * 1024 * 1024},
  );

  Future<void>? _initializing;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> _ensureInitialized() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_disposed) {
      throw StateError('QuickJS runtime is already disposed.');
    }

    final modules = await EJSBuilder.getJSModules();
    final result = _runtime.evaluate(modules);
    if (result.isError == true) {
      throw StateError(
        'No se pudo inicializar el solver JavaScript de YouTube: '
        '${result.stringResult}',
      );
    }
    _initialized = true;
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    await _ensureInitialized();
    if (_disposed) {
      throw StateError('QuickJS runtime is already disposed.');
    }

    final result = _runtime.evaluate(jsCode);
    if (result.isError == true) {
      throw StateError(
        'Falló el challenge JavaScript de YouTube: ${result.stringResult}',
      );
    }

    final value = result.stringResult?.toString() ?? '';
    if (value.isEmpty) {
      throw StateError('El challenge JavaScript de YouTube devolvió vacío.');
    }
    return value;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime.dispose();
  }
}
