import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../domain/models/stream_candidate.dart';

class SecureWebViewPlayer extends StatefulWidget {
  final StreamCandidate stream;

  const SecureWebViewPlayer({
    super.key,
    required this.stream,
  });

  @override
  State<SecureWebViewPlayer> createState() => _SecureWebViewPlayerState();
}

class _SecureWebViewPlayerState extends State<SecureWebViewPlayer> {
  late final WebViewController controller;
  late final Set<String> allowedHosts;

  @override
  void initState() {
    super.initState();

    allowedHosts = {
      widget.stream.uri.host.toLowerCase(),
      ...widget.stream.allowedHosts.map((host) => host.toLowerCase()),
    }..removeWhere((host) => host.isEmpty);

    controller = WebViewController(
      onPermissionRequest: (request) => request.deny(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            if (uri.scheme == 'about' || uri.scheme == 'data') {
              return NavigationDecision.navigate;
            }

            if (uri.scheme != 'http' && uri.scheme != 'https') {
              return NavigationDecision.prevent;
            }

            if (!allowedHosts.contains(uri.host.toLowerCase())) {
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageFinished: (_) => _hardenPage(),
        ),
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setGeolocationEnabled(false);
      platform.setAllowContentAccess(false);
      platform.setOnShowFileSelector((params) async => const <String>[]);
    }

    if (!widget.stream.directWebView && widget.stream.headers.isEmpty) {
      controller.loadHtmlString(_sandboxHtml(widget.stream.uri));
    } else {
      controller.loadRequest(
        widget.stream.uri,
        headers: widget.stream.headers,
      );
    }
  }

  String _sandboxHtml(Uri uri) {
    final escaped = const HtmlEscape(HtmlEscapeMode.attribute)
        .convert(uri.toString());
    return '''<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body,iframe{margin:0;padding:0;width:100%;height:100%;background:#000;border:0;overflow:hidden}
</style>
</head>
<body>
<iframe src="''' + escaped + '''"
  sandbox="allow-scripts allow-same-origin allow-presentation"
  allow="autoplay; fullscreen; picture-in-picture"
  allowfullscreen></iframe>
</body>
</html>''';
  }

  Future<void> _hardenPage() async {
    const script = r'''
      (() => {
        try {
          window.open = () => null;

          const stripTargets = () => {
            document.querySelectorAll('a[target]').forEach(
              (a) => a.removeAttribute('target')
            );
          };

          stripTargets();

          new MutationObserver(stripTargets).observe(
            document.documentElement,
            {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ['target']
            }
          );
        } catch (_) {}
      })();
    ''';

    await controller.runJavaScript(script);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: WebViewWidget(controller: controller),
    );
  }
}
