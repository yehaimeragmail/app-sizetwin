/* Go Pro panel + AppBridge helper for the iOS wrapper.
 *
 * This file is INJECTED by the native wrapper (lib/main.dart) after the
 * bundled app page loads. The app's own HTML is never edited.
 *
 * It does three things:
 *  1. Defines window.AppBridge — the JS API the HTML app calls:
 *       AppBridge.isPro()       -> Promise<boolean>
 *       AppBridge.buyPro()      -> start the one-time Pro purchase
 *       AppBridge.buyMonthly()  -> start the monthly subscription
 *       AppBridge.buyYearly()   -> start the yearly subscription
 *       AppBridge.restore()     -> restore past purchases
 *       AppBridge.rateApp()     -> native review prompt
 *       AppBridge.shareApp()    -> native share sheet
 *       AppBridge.moreApps()    -> open wajiha.fun in the system browser
 *       AppBridge.showProPanel() / AppBridge.hideProPanel()
 *     (AppBridge.pro is a cached boolean, updated whenever native pushes
 *     the status. isPro() asks native and resolves from the next push,
 *     with a 2s fallback to the cached value.)
 *  2. Chains window.onProStatusChanged: if the HTML app already defines
 *     one, it still runs. Native calls it whenever Pro status changes.
 *  3. Builds the Go Pro panel (floating "Pro" pill + bottom sheet) with
 *     benefits, prices and buttons. Prices come from native via
 *     window.onStoreProducts(...); a product that does not exist in the
 *     store yet simply has no button — nothing broken, nothing fake.
 *
 * Config comes from native in window.__w2proConfig (set before this file
 * is evaluated): { appName, benefits: [..], moreAppsUrl }.
 */
(function () {
  'use strict';

  var cfg = window.__w2proConfig || {};
  var appName = cfg.appName || 'this app';
  var benefits = cfg.benefits || ['Unlock everything in the app'];

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* ---- native channel ------------------------------------------------ */
  // webview_flutter injects a global AppBridge object with postMessage.
  // If it is missing (plain browser preview), use a silent stub so the
  // HTML app's calls never crash.
  var channel = window.AppBridge && window.AppBridge.postMessage
    ? window.AppBridge
    : { postMessage: function () {} };

  function post(msg) {
    try { channel.postMessage(msg); } catch (e) { /* no native side */ }
  }

  /* ---- Pro status ---------------------------------------------------- */
  var cachedPro = false;
  var pendingIsPro = [];

  function pushProStatus(value) {
    cachedPro = !!value;
    var list = pendingIsPro;
    pendingIsPro = [];
    for (var i = 0; i < list.length; i++) {
      try { list[i](cachedPro); } catch (e) {}
    }
    updateProUI();
  }

  // Chain: if the HTML app already defines onProStatusChanged, keep it.
  var prevStatusHandler = window.onProStatusChanged;
  window.onProStatusChanged = function (value) {
    if (typeof prevStatusHandler === 'function') {
      try { prevStatusHandler(value); } catch (e) {}
    }
    pushProStatus(value);
  };

  /* ---- store products (prices + availability) ------------------------ */
  // Native calls this after the store query:
  //   { pro: {price: "$4.99", available: true},
  //     monthly: {price: "$0.99", available: true},
  //     yearly: {price: "$9.99", available: false} }
  window.onStoreProducts = function (data) {
    updateProductButtons(data || {});
  };

  /* ---- AppBridge API -------------------------------------------------- */
  var api = {
    // Current Pro status. Returns a Promise<boolean>.
    isPro: function () {
      return new Promise(function (resolve) {
        pendingIsPro.push(resolve);
        post('getPro');
        setTimeout(function () {
          var idx = pendingIsPro.indexOf(resolve);
          if (idx !== -1) {
            pendingIsPro.splice(idx, 1);
            resolve(cachedPro);
          }
        }, 2000);
      });
    },
    // Cached status, updated on every native push. Sync read.
    pro: false,
    buyPro: function () { post('buyPro'); },
    buyMonthly: function () { post('buyMonthly'); },
    buyYearly: function () { post('buyYearly'); },
    restore: function () { post('restore'); },
    rateApp: function () { post('rateApp'); },
    shareApp: function () { post('shareApp'); },
    moreApps: function () { post('moreApps'); },
    showProPanel: function () { showPanel(); },
    hideProPanel: function () { hidePanel(); }
  };

  // Keep the native channel's postMessage and add the API methods on top.
  for (var k in api) { channel[k] = api[k]; }
  Object.defineProperty(channel, 'pro', {
    get: function () { return cachedPro; },
    configurable: true
  });
  window.AppBridge = channel;

  /* ---- Go Pro panel --------------------------------------------------- */
  var panel = null;
  var pill = null;

  function benefitItems() {
    var out = '';
    for (var i = 0; i < benefits.length; i++) {
      out += '<li class="w2pro-benefit">' + esc(benefits[i]) + '</li>';
    }
    return out;
  }

  function buildPanel() {
    if (panel) return;

    pill = document.createElement('button');
    pill.id = 'w2pro-pill';
    pill.className = 'w2pro-pill';
    pill.textContent = '\u2605 Pro';
    pill.addEventListener('click', showPanel);
    document.body.appendChild(pill);

    panel = document.createElement('div');
    panel.id = 'w2pro-panel';
    panel.className = 'w2pro-panel';
    panel.innerHTML =
      '<div class="w2pro-sheet">' +
        '<button class="w2pro-close" id="w2pro-close" aria-label="Close">\u00d7</button>' +
        '<div class="w2pro-title">Go Pro</div>' +
        '<div class="w2pro-sub">' + esc(appName) + ' Pro</div>' +
        '<ul class="w2pro-benefits">' + benefitItems() + '</ul>' +
        '<div class="w2pro-prices" id="w2pro-prices">' +
          '<button class="w2pro-buy w2pro-buy-primary" id="w2pro-buy-pro">Go Pro</button>' +
          '<button class="w2pro-buy" id="w2pro-buy-monthly">Monthly</button>' +
          '<button class="w2pro-buy" id="w2pro-buy-yearly">Yearly</button>' +
          '<div class="w2pro-coming" id="w2pro-coming" style="display:none">Pro is coming soon.</div>' +
        '</div>' +
        '<div class="w2pro-row">' +
          '<button class="w2pro-link" id="w2pro-restore">Restore purchases</button>' +
          '<button class="w2pro-link" id="w2pro-share">Share this app</button>' +
          '<button class="w2pro-link" id="w2pro-more">More apps</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(panel);

    document.getElementById('w2pro-close').addEventListener('click', hidePanel);
    document.getElementById('w2pro-buy-pro').addEventListener('click', function () { post('buyPro'); });
    document.getElementById('w2pro-buy-monthly').addEventListener('click', function () { post('buyMonthly'); });
    document.getElementById('w2pro-buy-yearly').addEventListener('click', function () { post('buyYearly'); });
    document.getElementById('w2pro-restore').addEventListener('click', function () { post('restore'); });
    document.getElementById('w2pro-share').addEventListener('click', function () { post('shareApp'); });
    document.getElementById('w2pro-more').addEventListener('click', function () { post('moreApps'); });
    panel.addEventListener('click', function (e) {
      if (e.target === panel) hidePanel();
    });
  }

  function updateProductButtons(data) {
    if (!panel) return;
    var any = false;
    var map = {
      'w2pro-buy-pro': data.pro,
      'w2pro-buy-monthly': data.monthly,
      'w2pro-buy-yearly': data.yearly
    };
    for (var id in map) {
      var btn = document.getElementById(id);
      if (!btn) continue;
      var info = map[id];
      if (info && info.available) {
        any = true;
        btn.style.display = '';
        var label = btn.id === 'w2pro-buy-pro' ? 'Go Pro' :
          btn.id === 'w2pro-buy-monthly' ? 'Monthly' : 'Yearly';
        btn.textContent = info.price ? label + ' \u00b7 ' + info.price : label;
      } else {
        btn.style.display = 'none';
      }
    }
    var coming = document.getElementById('w2pro-coming');
    if (coming) coming.style.display = any ? 'none' : '';
  }

  function updateProUI() {
    // Pro owners do not need the upsell pill.
    if (pill) pill.style.display = cachedPro ? 'none' : '';
    if (cachedPro) hidePanel();
  }

  function showPanel() {
    buildPanel();
    panel.classList.add('w2pro-open');
  }

  function hidePanel() {
    if (panel) panel.classList.remove('w2pro-open');
  }

  // Build the (hidden) panel and pill once the page is ready, so the
  // floating button is there from the start.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', buildPanel);
  } else {
    buildPanel();
  }
  updateProUI();
})();
