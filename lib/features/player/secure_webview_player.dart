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
      )
      ..loadRequest(
        widget.stream.uri,
        headers: widget.stream.headers,
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setGeolocationEnabled(false);
      platform.setAllowContentAccess(false);
      platform.setOnShowFileSelector((params) async => const <String>[]);
    }
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
