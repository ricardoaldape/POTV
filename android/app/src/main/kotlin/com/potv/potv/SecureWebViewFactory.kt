package com.potv.potv

import android.content.Context
import android.graphics.Bitmap
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream

class SecureWebViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return SecureWebViewPlatformView(context, params)
    }
}

private class SecureWebViewPlatformView(
    context: Context,
    params: Map<String, Any?>,
) : PlatformView {
    private val webView = WebView(context)
    private val mainHost = params["mainHost"]?.toString()?.lowercase().orEmpty()
    private val allowedHosts =
        ((params["allowedHosts"] as? List<*>) ?: emptyList<Any?>())
            .map { it.toString().lowercase() }
            .filter { it.isNotBlank() }
            .toMutableSet()
            .apply { if (mainHost.isNotBlank()) add(mainHost) }
    private val headers =
        (params["headers"] as? Map<*, *>)
            ?.entries
            ?.associate { it.key.toString() to it.value.toString() }
            ?: emptyMap()
    private val adBlockingEnabled = params["adBlockingEnabled"] != false
    private val directWebView = params["directWebView"] == true
    private val initialUrl = params["url"]?.toString().orEmpty()

    init {
        webView.setBackgroundColor(android.graphics.Color.BLACK)

        with(webView.settings) {
            javaScriptEnabled = true
            mediaPlaybackRequiresUserGesture = false
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowContentAccess = false
            allowFileAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }

        webView.webViewClient = FilteringWebViewClient()

        if (initialUrl.isNotBlank()) {
            if (!directWebView && headers.isEmpty()) {
                webView.loadDataWithBaseURL(
                    initialUrl,
                    sandboxHtml(initialUrl),
                    "text/html",
                    "UTF-8",
                    null,
                )
            } else {
                webView.loadUrl(initialUrl, headers)
            }
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        webView.stopLoading()
        webView.webViewClient = WebViewClient()
        webView.removeAllViews()
        webView.destroy()
    }

    private fun hostAllowed(host: String?): Boolean {
        val value = host?.lowercase().orEmpty()
        if (value.isBlank()) return false
        return allowedHosts.any { allowed ->
            value == allowed || value.endsWith(".$allowed")
        }
    }

    private fun isAdHost(host: String?): Boolean {
        if (!adBlockingEnabled) return false
        val value = host?.lowercase().orEmpty()
        if (value.isBlank()) return false

        return AD_HOST_PATTERNS.any { pattern ->
            value == pattern || value.endsWith(".$pattern") || value.contains(pattern)
        }
    }

    private fun empty204(): WebResourceResponse =
        WebResourceResponse(
            "text/plain",
            "UTF-8",
            204,
            "No Content",
            emptyMap(),
            ByteArrayInputStream(ByteArray(0)),
        )

    private inner class FilteringWebViewClient : WebViewClient() {
        override fun shouldInterceptRequest(
            view: WebView?,
            request: WebResourceRequest?,
        ): WebResourceResponse? {
            val uri = request?.url ?: return null
            if (isAdHost(uri.host)) {
                return empty204()
            }
            return super.shouldInterceptRequest(view, request)
        }

        override fun shouldOverrideUrlLoading(
            view: WebView?,
            request: WebResourceRequest?,
        ): Boolean {
            val uri = request?.url ?: return true

            if (uri.scheme == "about" || uri.scheme == "data") return false
            if (uri.scheme != "http" && uri.scheme != "https") return true

            if (!hostAllowed(uri.host)) {
                return true
            }

            return false
        }

        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            super.onPageFinished(view, url)
            if (!adBlockingEnabled) return
            view?.evaluateJavascript(hardeningScript(), null)
        }
    }

    private fun hardeningScript(): String {
        val escapedHost = mainHost.replace("\\", "\\\\").replace("'", "\\'")
        return """
            (() => {
              try {
                const MAIN_HOST = '$escapedHost';

                const samePlayerDomain = (src) => {
                  try {
                    const host = new URL(src, location.href).hostname.toLowerCase();
                    return host === MAIN_HOST || host.endsWith('.' + MAIN_HOST);
                  } catch (_) {
                    return false;
                  }
                };

                const hideNode = (node) => {
                  try {
                    node.style.setProperty('display', 'none', 'important');
                    node.style.setProperty('visibility', 'hidden', 'important');
                    node.style.setProperty('pointer-events', 'none', 'important');
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
                        const style = getComputedStyle(div);
                        if (style.position !== 'fixed') return;

                        const rect = div.getBoundingClientRect();
                        const area =
                          Math.max(0, rect.width) * Math.max(0, rect.height);

                        if (area >= viewportArea * 0.80) {
                          hideNode(div);
                        }
                      } catch (_) {}
                    });

                    document.querySelectorAll('iframe[src]').forEach((frame) => {
                      try {
                        if (!samePlayerDomain(frame.src)) {
                          hideNode(frame);
                        }
                      } catch (_) {}
                    });

                    document.querySelectorAll('a[target]').forEach((a) => {
                      try { a.removeAttribute('target'); } catch (_) {}
                    });
                  } catch (_) {}
                };

                try { window.open = () => null; } catch (_) {}

                sweep();

                const observer = new MutationObserver(() => sweep());
                observer.observe(document.documentElement || document.body, {
                  childList: true,
                  subtree: true,
                  attributes: true,
                  attributeFilter: ['src', 'style', 'class', 'target']
                });
              } catch (_) {}
            })();
        """.trimIndent()
    }

    private fun sandboxHtml(url: String): String {
        val escaped =
            url.replace("&", "&amp;")
                .replace("\"", "&quot;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")

        return """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport"
                content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
              <style>
                html,body,iframe{
                  margin:0;
                  padding:0;
                  width:100%;
                  height:100%;
                  background:#000;
                  border:0;
                  overflow:hidden
                }
              </style>
            </head>
            <body>
              <iframe
                src="$escaped"
                sandbox="allow-scripts allow-same-origin allow-presentation"
                allow="autoplay; fullscreen; picture-in-picture"
                allowfullscreen>
              </iframe>
            </body>
            </html>
        """.trimIndent()
    }

    companion object {
        private val AD_HOST_PATTERNS =
            setOf(
                "doubleclick.net",
                "googlesyndication.com",
                "googleadservices.com",
                "adservice.google.com",
                "adservice.google",
                "popads.net",
                "popcash.net",
                "propellerads.com",
                "adsterra.com",
                "exoclick.com",
                "trafficjunky.net",
                "taboola.com",
                "outbrain.com",
                "mgid.com",
                "adskeeper.com",
                "onclicka.com",
                "onclickmax.com",
                "adnxs.com",
                "criteo.com",
                "criteo.net",
                "scorecardresearch.com",
            )
    }
}
