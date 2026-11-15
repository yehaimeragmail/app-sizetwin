import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_config.dart';
import 'store_service.dart';

/// Thin iOS shell for one self-contained offline HTML app (wrapper v2).
///
/// The app's HTML lives in this project as `assets/app.html` (bundled, so it
/// works with no internet). It is shown full-screen in a WKWebView with
/// JavaScript on. Local storage works (WKWebView keeps it on by default), so
/// the HTML app's saved data stays on the phone between launches.
///
/// No ads, no tracking, no data collection. Any tap that would leave the
/// bundled page is blocked; the only way out is the "More apps" button,
/// which opens wajiha.fun in the system browser.
///
/// v2 adds, on top of the plain shell:
///  * In-app purchases (one-time Pro + monthly/yearly subscriptions) with
///    product IDs `<shortName>pro` / `<shortName>monthly` /
///    `<shortName>yearly` — no dots, no underscores. Missing products
///    (not created in App Store Connect yet) simply hide their buy button.
///  * A JS bridge (`AppBridge`) so the HTML app can ask for Pro status,
///    buy, restore, rate and share. Native pushes Pro status and product
///    prices into the page whenever they change.
///  * In-app marketing: an injected Go Pro panel (assets/pro-panel.js +
///    pro-panel.css — the app HTML is never edited), a native review
///    prompt once after the 3rd launch, a native share sheet, and a
///    "More apps" cross-promo to wajiha.fun.
void main() {
  runApp(const AppShell());
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  final AppStore _store = AppStore();

  String _panelCss = '';
  String _panelJs = '';

  @override
  void initState() {
    super.initState();
    _store.onProStatusChanged = (_) => _pushProStatus();
    _store.onProductsChanged = () => _pushProducts();
    _store.init();
    _loadPanelAssets();
    _maybeRequestReview();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectMarketingPanel(),
          // The bundled page loads from a file:// URL. Block anything that
          // would take the user out to the internet (the HTML apps have no
          // external links, this is just a safety net).
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('file:') ||
                request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'AppBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..loadFlutterAsset('assets/app.html');
  }

  /// Loads the Go Pro panel files once, so injection on page load is fast.
  Future<void> _loadPanelAssets() async {
    try {
      _panelCss = await rootBundle.loadString('assets/pro-panel.css');
      _panelJs = await rootBundle.loadString('assets/pro-panel.js');
    } catch (_) {
      _panelCss = '';
      _panelJs = '';
    }
  }

  /// Injects the Go Pro panel (CSS + config + JS) into the loaded page,
  /// then pushes the current product list and Pro status so the panel
  /// shows real prices and hides products that do not exist yet.
  Future<void> _injectMarketingPanel() async {
    if (_panelJs.isEmpty) return;
    try {
      if (_panelCss.isNotEmpty) {
        await _controller.runJavaScript(
          'var w2s=document.createElement("style");'
          'w2s.textContent=${jsonEncode(_panelCss)};'
          'document.head.appendChild(w2s);',
        );
      }
      await _controller.runJavaScript(
        'window.__w2proConfig=${jsonEncode({
          'appName': AppConfig.appName,
          'benefits': AppConfig.proBenefits,
          'moreAppsUrl': AppConfig.moreAppsUrl,
        })};',
      );
      await _controller.runJavaScript(_panelJs);
      await _pushProducts();
      await _pushProStatus();
    } catch (_) {
      // The panel is marketing, not the app itself: if injection fails,
      // the HTML app still works exactly as before.
    }
  }

  /// Tells the page which products exist and their real store prices.
  /// The panel hides any product that is missing.
  Future<void> _pushProducts() async {
    try {
      final data = <String, Map<String, Object>>{
        'pro': _productInfo(_store.proProduct),
        'monthly': _productInfo(_store.monthlyProduct),
        'yearly': _productInfo(_store.yearlyProduct),
      };
      await _controller.runJavaScript(
        'window.onStoreProducts && window.onStoreProducts(${jsonEncode(data)});',
      );
    } catch (_) {}
  }

  Map<String, Object> _productInfo(dynamic product) {
    if (product == null) return {'available': false};
    return {'available': true, 'price': product.price as String};
  }

  /// Tells the page the current Pro status, so the HTML can unlock or
  /// lock Pro features live.
  Future<void> _pushProStatus() async {
    try {
      await _controller.runJavaScript(
        'window.onProStatusChanged && '
        'window.onProStatusChanged(${_store.isPro.value});',
      );
    } catch (_) {}
  }

  /// Messages from the page, via AppBridge.postMessage('...').
  /// Every call is safe when its product does not exist yet: the buy
  /// methods simply return false and nothing happens on screen.
  Future<void> _handleBridgeMessage(String message) async {
    switch (message) {
      case 'getPro':
        await _pushProStatus();
      case 'buyPro':
        await _store.buyPro();
      case 'buyMonthly':
        await _store.buyMonthly();
      case 'buyYearly':
        await _store.buyYearly();
      case 'restore':
        await _store.restore();
      case 'rateApp':
        await _requestReview();
      case 'shareApp':
        await _shareApp();
      case 'moreApps':
        await _openMoreApps();
    }
  }

  /// Native review prompt, once, after the 3rd launch. The flag is set
  /// before asking, so it can only ever fire once.
  Future<void> _maybeRequestReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final launches = (prefs.getInt('launch_count') ?? 0) + 1;
      await prefs.setInt('launch_count', launches);
      if (launches != 3) return;
      if (prefs.getBool('rate_prompt_shown') ?? false) return;
      await prefs.setBool('rate_prompt_shown', true);
      await Future<void>.delayed(const Duration(seconds: 3));
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (_) {}
  }

  /// Review prompt on demand (from the bridge). Still only ever once:
  /// the store prompt itself is rate-limited by iOS, and this is only
  /// reachable from a deliberate tap.
  Future<void> _requestReview() async {
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (_) {}
  }

  /// Native share sheet with the app's App Store link.
  Future<void> _shareApp() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Check out ${AppConfig.appName}: ${AppConfig.appStoreUrl}',
          subject: AppConfig.appName,
        ),
      );
    } catch (_) {}
  }

  /// "More apps" cross-promo: opens wajiha.fun in the system browser.
  Future<void> _openMoreApps() async {
    try {
      await launchUrl(
        Uri.parse(AppConfig.moreAppsUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // The web view MUST be inset by the native safe area (status bar
        // on top, home indicator at the bottom). The HTML apps cannot do
        // this themselves: env(safe-area-inset-*) reads as 0 inside this
        // WKWebView, so an app that relies on it draws its header under
        // the status bar and its bottom sheet under the home indicator
        // (seen on a real iPhone 12, Stamp Mark, 15 Nov 2026). With the
        // web view already inset, env() inside reads 0, so the apps'
        // own safe-area paddings add nothing extra — no double padding.
        top: true,
        bottom: true,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
