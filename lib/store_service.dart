import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Store for one wrapper app: one-time Pro unlock + monthly/yearly
/// auto-renewable subscriptions, all in ONE subscription group per app.
///
/// Product IDs (NO dots, NO underscores — Nov 13 law):
///   `<shortName>pro`      — one-time NON-consumable Pro unlock
///   `<shortName>monthly`  — auto-renewable monthly subscription
///   `<shortName>yearly`   — auto-renewable yearly subscription
/// Example (Stamp Mark): stampmarkpro, stampmarkmonthly, stampmarkyearly.
///
/// The products must be created in App Store Connect. Until then (or on
/// any store error) the service degrades gracefully: a missing product
/// simply has no buy button anywhere — nothing crashes, nothing shows a
/// broken price. The purchase flow is fully wired, so the moment the
/// products exist in App Store Connect, buying works with no code change.
///
/// Honest limit: there is no server-side receipt verification here, so
/// Pro ownership is the local purchase record (same level as the board
/// games). A real StoreKit purchase can only be proven on a real device
/// or TestFlight — this Linux machine cannot run StoreKit.
class AppStore {
  /// One-time Pro unlock.
  static String get proId => '${AppConfig.shortName}pro';

  /// Monthly auto-renewable subscription.
  static String get monthlyId => '${AppConfig.shortName}monthly';

  /// Yearly auto-renewable subscription.
  static String get yearlyId => '${AppConfig.shortName}yearly';

  static Set<String> get productIds => {proId, monthlyId, yearlyId};

  static const String _kProOwned = 'pro_owned';

  final InAppPurchase _iap = InAppPurchase.instance;

  /// True when the store answered on this device.
  bool available = false;

  /// Products the store actually knows about, by product ID.
  /// A product missing from this map was not created in App Store
  /// Connect yet (or the query failed) — the UI hides its buy button.
  Map<String, ProductDetails> products = {};

  /// Product IDs the store said it could not find.
  Set<String> missingProductIds = {};

  /// Human-readable store problem, if any. Null when all is well.
  String? error;

  /// Current Pro status. True when the user owns Pro (one-time) or has
  /// an active monthly/yearly subscription. Persisted locally, and also
  /// updated live from the purchase stream (buy / restore).
  final ValueNotifier<bool> isPro = ValueNotifier(false);

  /// Called whenever [isPro] changes, so the web view can be told
  /// (window.onProStatusChanged) and the HTML can unlock/lock live.
  void Function(bool isPro)? onProStatusChanged;

  /// Called whenever the product list changes (after the store query),
  /// so the web view can be told which products exist and their prices.
  void Function()? onProductsChanged;

  bool _initialized = false;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  SharedPreferences? _prefs;

  ProductDetails? get proProduct => products[proId];
  ProductDetails? get monthlyProduct => products[monthlyId];
  ProductDetails? get yearlyProduct => products[yearlyId];

  /// True when the store answered and at least one product is configured.
  bool get storeReady => available && products.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      _setPro(_prefs?.getBool(_kProOwned) ?? false, notify: false);

      available = await _iap.isAvailable();
      if (!available) {
        error = 'Store unavailable on this device';
        return;
      }
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
        cancelOnError: false,
      );
      final resp = await _iap.queryProductDetails(productIds);
      if (resp.error != null) {
        error = 'Could not load products';
        return;
      }
      products = {for (final p in resp.productDetails) p.id: p};
      missingProductIds = resp.notFoundIDs.toSet();
      if (missingProductIds.isNotEmpty) {
        // Products not created in App Store Connect yet — normal before
        // release. Their buy buttons stay hidden, nothing breaks.
        error = 'Some products are not set up in the store yet';
      }
      onProductsChanged?.call();
    } catch (_) {
      available = false;
      error = 'Store error';
    }
  }

  void _setPro(bool value, {bool notify = true}) {
    if (isPro.value == value) return;
    isPro.value = value;
    if (notify) onProStatusChanged?.call(value);
  }

  Future<void> _persistPro(bool value) async {
    await _prefs?.setBool(_kProOwned, value);
  }

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (p.productID == proId ||
            p.productID == monthlyId ||
            p.productID == yearlyId) {
          // Pro unlock (one-time) or an active subscription — either one
          // makes the user Pro.
          _setPro(true);
          _persistPro(true);
        }
      }
      if (p.pendingCompletePurchase) {
        _iap.completePurchase(p).catchError((_) {});
      }
    }
  }

  /// One-time Pro unlock. Returns false when the product is not
  /// configured in the store yet — the caller hides the button instead
  /// of showing an error.
  Future<bool> buyPro() async {
    final product = proProduct;
    if (product == null) return false;
    try {
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      return false;
    }
  }

  /// Monthly auto-renewable subscription. Same graceful-false rule.
  /// (The plugin buys subscriptions with buyNonConsumable — the product
  /// type in App Store Connect is what makes it a subscription.)
  Future<bool> buyMonthly() async {
    final product = monthlyProduct;
    if (product == null) return false;
    try {
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      return false;
    }
  }

  /// Yearly auto-renewable subscription. Same graceful-false rule.
  Future<bool> buyYearly() async {
    final product = yearlyProduct;
    if (product == null) return false;
    try {
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      return false;
    }
  }

  /// Re-delivers past purchases (e.g. Pro bought on another device).
  /// Results arrive through the purchase stream and update [isPro].
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    isPro.dispose();
  }
}
