import 'dart:async';
// dart:convert intentionally left out; not currently needed
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

class StreamResult {
  final String url;
  final String quality;
  final Map<String, String> headers;
  final String serverName;

  StreamResult({
    required this.url,
    this.quality = 'HD',
    this.headers = const {},
    this.serverName = 'native',
  });
}

/// Minimal native resolvers implementation.
/// Exposes `NativeResolvers.resolve(url)` -> `Future<StreamResult?>`
const _kUserAgent =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

class NativeResolvers {

  static Future<StreamResult?> resolve(String url,
      {Duration timeout = const Duration(seconds: 8)}) async {
    try {
      // Quick attempt: if url points directly to m3u8 or mp4, return it
      final lower = url.toLowerCase();
      if (lower.contains('.m3u8') || lower.endsWith('.mp4')) {
        return StreamResult(url: url, headers: {'User-Agent': _kUserAgent});
      }

      // Otherwise try a simple HTTP GET and search body for m3u8/link
        final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': _kUserAgent}).timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = res.body;

                final m3u8 = RegExp(r"""https?://[^\s"']+\.m3u8[^\s"']*""",
                    caseSensitive: false)
                  .firstMatch(body);
      if (m3u8 != null) return StreamResult(url: m3u8.group(0)!, headers: {'User-Agent': _kUserAgent});

                final mp4 = RegExp(r"""https?://[^\s"']+\.mp4[^\s"']*""",
                    caseSensitive: false)
                  .firstMatch(body);
      if (mp4 != null) return StreamResult(url: mp4.group(0)!, headers: {'User-Agent': _kUserAgent});

      return null;
    } catch (_) {
      return null;
    }
  }
}

class NativeResolverService {
  NativeResolverService._();

  static Future<String?> buscarFuente(BuildContext context, String servidorUrl,
      {Duration timeout = const Duration(seconds: 10)}) async {
    // 1) Try fast native resolver
    final native = await NativeResolvers.resolve(servidorUrl,
        timeout: const Duration(seconds: 6));
    if (native != null && native.url.isNotEmpty) return native.url;

    // 2) Guard mounted before proceeding to overlay/webview (after await)
    if (!context.mounted) return null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;

    final completer = Completer<String?>();
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -5,
        top: -5,
        width: 1,
        height: 1,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.0,
            child: _HiddenProbe(
              servidorUrl: servidorUrl,
              timeout: timeout,
              onResult: (u) {
                try {
                  entry.remove();
                } catch (_) {}
                if (!completer.isCompleted) completer.complete(u);
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

class _HiddenProbe extends StatefulWidget {
  final String servidorUrl;
  final Duration timeout;
  final ValueChanged<String?> onResult;

  const _HiddenProbe({
    required this.servidorUrl,
    required this.timeout,
    required this.onResult,
  });

  @override
  State<_HiddenProbe> createState() => _HiddenProbeState();
}

class _HiddenProbeState extends State<_HiddenProbe> {
  late final WebViewController _controller;
  Timer? _t;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_kUserAgent)
      ..addJavaScriptChannel('MD', onMessageReceived: (m) {
        if (_done) return;
        final url = m.message.trim();
        if (url.isNotEmpty) _finish(url);
      })
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        if (_done) return;
        _controller.runJavaScript('''
          (function(){
            try {
              document.querySelectorAll('video, source').forEach(v=>{
                if (v.src) window.MD.postMessage(v.src);
              });
              performance.getEntriesByType('resource').forEach(r=>{
                if (r.name && (r.name.includes('.m3u8')||r.name.includes('.mp4'))) window.MD.postMessage(r.name);
              });
            } catch(e){}
          })();
        ''');
      }))
      ..loadRequest(Uri.parse(widget.servidorUrl));

    _t = Timer(widget.timeout, () {
      if (!_done) _finish(null);
    });
  }

  void _finish(String? url) {
    if (_done) return;
    _done = true;
    _t?.cancel();
    widget.onResult(url);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 1, height: 1, child: WebViewWidget(controller: _controller));
  }
}
