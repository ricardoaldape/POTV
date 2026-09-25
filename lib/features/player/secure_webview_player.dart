import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../domain/models/stream_candidate.dart';

const _adBlockingPreferenceKey = 'webview_ad_blocking_enabled';

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
  WebViewController? controller;
  late final Set<String> allowedHosts;
  bool? adBlockingEnabled;

  @override
  void initState() {
    super.initState();

    allowedHosts = {
      widget.stream.uri.host.toLowerCase(),
      ...widget.stream.allowedHosts.map((host) => host.toLowerCase()),
    }..removeWhere((host) => host.isEmpty);

    _loadPreference();

    if (!Platform.isAndroid) {
      _configureFlutterWebView();
    }
  }

  Future<void> _loadPreference() async {
    final preferences = await SharedPreferences.getInstance();
    final enabled = preferences.getBool(_adBlockingPreferenceKey) ?? true;
    if (!mounted) return;
    setState(() => adBlockingEnabled = enabled);
  }

  void _configureFlutterWebView() {
    final nextController = WebViewController(
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

            if (!_hostAllowed(uri.host)) {
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageFinished: (_) => _hardenPage(),
        ),
      );

    final platform = nextController.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setGeolocationEnabled(false);
      platform.setAllowContentAccess(false);
      platform.setOnShowFileSelector((params) async => const <String>[]);
    }

    controller = nextController;

    if (!widget.stream.directWebView && widget.stream.headers.isEmpty) {
      nextController.loadHtmlString(_sandboxHtml(widget.stream.uri));
    } else {
      nextController.loadRequest(
        widget.stream.uri,
        headers: widget.stream.headers,
      );
    }
  }

  bool _hostAllowed(String host) {
    final normalized = host.toLowerCase();
    return allowedHosts.any(
      (allowed) => normalized == allowed || normalized.endsWith('.$allowed'),
    );
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
<iframe src="$escaped"
  sandbox="allow-scripts allow-same-origin allow-presentation"
  allow="autoplay; fullscreen; picture-in-picture"
  allowfullscreen></iframe>
</body>
</html>''';
  }

  Future<void> _hardenPage() async {
    if (adBlockingEnabled == false) return;
    final activeController = controller;
    if (activeController == null) return;

    final mainHost = widget.stream.uri.host.toLowerCase();
    final script = '''
      (() => {
        try {
          const MAIN_HOST = ${jsonEncode(mainHost)};

          const samePlayerDomain = (src) => {
            try {
              const host = new URL(src, location.href).hostname.toLowerCase();
              return host === MAIN_HOST || host.endsWith('.' + MAIN_HOST);
            } catch (_) {
              return false;
            }
          };

          const ensurePotvStyles = () => {
            try {
              if (document.getElementById('potv-menu-guard-style')) return;
              const style = document.createElement('style');
              style.id = 'potv-menu-guard-style';
              style.textContent = `
                .potv-hidden-menu {
                  display: none !important;
                  visibility: hidden !important;
                  pointer-events: none !important;
                }
                .potv-compact-menu {
                  display: block !important;
                  position: fixed !important;
                  top: auto !important;
                  left: auto !important;
                  bottom: 10px !important;
                  right: 10px !important;
                  width: auto !important;
                  height: auto !important;
                  max-width: 42vw !important;
                  max-height: 34vh !important;
                  overflow: auto !important;
                  opacity: 0.5 !important;
                  z-index: 2147483646 !important;
                  pointer-events: auto !important;
                }
              `;
              (document.head || document.documentElement).appendChild(style);
            } catch (_) {}
          };

          const hideNode = (node) => {
            try {
              ensurePotvStyles();
              node.classList.remove('potv-compact-menu');
              node.classList.add('potv-hidden-menu');
            } catch (_) {}
          };

          const compactNode = (node) => {
            try {
              ensurePotvStyles();
              node.classList.remove('potv-hidden-menu');
              node.classList.add('potv-compact-menu');
            } catch (_) {}
          };

          const classifyInjectedMenu = (node) => {
            try {
              if (!(node instanceof HTMLElement)) return;
              if (node.querySelector('video')) return;

              const signature = [
                node.id || '',
                node.className || '',
                node.getAttribute('role') || '',
                node.getAttribute('aria-label') || ''
              ].join(' ').toLowerCase();

              if (!/(menu|controls?|settings?|overlay)/i.test(signature)) {
                return;
              }

              const text = (node.innerText || '').toLowerCase();
              const hasPlaybackOptions =
                /(server|servidor|source|fuente|quality|calidad|resolution|resoluci[oó]n)/i.test(text);

              if (hasPlaybackOptions) {
                compactNode(node);
              } else {
                hideNode(node);
              }
            } catch (_) {}
          };

          const sweep = () => {
            try {
              const viewportArea = Math.max(
                1,
                window.innerWidth * window.innerHeight
              );

              document.querySelectorAll('div').forEach((div) => {
                try {
                  if (div.querySelector('video')) return;
                  if (getComputedStyle(div).position !== 'fixed') return;

                  const rect = div.getBoundingClientRect();
                  const area =
                    Math.max(0, rect.width) * Math.max(0, rect.height);

                  if (area >= viewportArea * 0.80) {
                    hideNode(div);
                  }
                } catch (_) {}
              });

              document.querySelectorAll(
                '[class*="menu" i], [id*="menu" i], ' +
                '[class*="control" i], [id*="control" i], ' +
                '[class*="setting" i], [id*="setting" i], ' +
                '[class*="overlay" i], [id*="overlay" i], ' +
                '[role="menu"], [aria-label*="menu" i]'
              ).forEach(classifyInjectedMenu);

              document.querySelectorAll('iframe[src]').forEach((frame) => {
                try {
                  if (!samePlayerDomain(frame.src)) {
                    hideNode(frame);
                  }
                } catch (_) {}
              });

              document.querySelectorAll('a[target]').forEach(
                (a) => a.removeAttribute('target')
              );
            } catch (_) {}
          };

          try { window.open = () => null; } catch (_) {}
          ensurePotvStyles();
          sweep();

          new MutationObserver(sweep).observe(
            document.documentElement || document.body,
            {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ['src', 'style', 'class', 'target']
            }
          );
        } catch (_) {}
      })();
    ''';

    await activeController.runJavaScript(script);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = adBlockingEnabled;
    if (enabled == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (Platform.isAndroid) {
      return ColoredBox(
        color: Colors.black,
        child: AndroidView(
          viewType: 'potv/secure_webview',
          creationParams: <String, Object?>{
            'url': widget.stream.uri.toString(),
            'mainHost': widget.stream.uri.host.toLowerCase(),
            'allowedHosts': allowedHosts.toList(growable: false),
            'headers': widget.stream.headers,
            'directWebView': widget.stream.directWebView,
            'adBlockingEnabled': enabled,
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
      );
    }

    final activeController = controller;
    if (activeController == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: WebViewWidget(controller: activeController),
    );
  }
}
