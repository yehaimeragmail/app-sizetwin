# iOS wrapper template v2 — one offline HTML app per App Store app

A minimal Flutter shell that shows one self-contained HTML file full-screen
in a WKWebView, with Pro purchases, subscriptions and in-app marketing.
No ads, no tracking, no data collection.

## What is inside

- `lib/main.dart` — full-screen `WebViewWidget` loading `assets/app.html`
  (`loadFlutterAsset`). JavaScript on, zoom off, white background.
  Local storage stays on (WKWebView default), so the HTML app's saved data
  stays on the phone. A navigation delegate blocks anything that would leave
  the bundled page (only `file:` / `about:blank` allowed). Injects the Go
  Pro panel on page load and wires the `AppBridge` JS channel.
- `lib/app_config.dart` — THE per-app file. Set `shortName`, `appName`,
  `appStoreUrl` and `proBenefits` at clone time; everything else
  (product IDs, share text, panel) is derived from it.
- `lib/store_service.dart` — in-app purchases (see below).
- `assets/pro-panel.js` + `assets/pro-panel.css` — the Go Pro panel,
  injected by the wrapper. The app's own HTML is never edited.
- `test/wrapper_v2_test.dart` — compile + product-ID law checks
  (`flutter test`).
- `pubspec.yaml` — dependencies: `webview_flutter`, `in_app_purchase`,
  `in_app_review`, `share_plus`, `shared_preferences`, `url_launcher`.
  Assets: `assets/app.html`, `assets/pro-panel.js`, `assets/pro-panel.css`.
- `ios/Runner/Info.plist` — usage descriptions in plain words for camera,
  microphone, photo library (read + add) and location (when in use), because
  apps in this set use `getUserMedia`, file input and geolocation.
- `ios/Runner/Base.lproj/LaunchScreen.storyboard` — plain white launch
  background (LaunchImage is a plain white image).
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — generic dark-teal icon
  set (replace per app; regenerate with `../make_icon.py <kind> <dir>`).
  NOTE: per the Nov 13 icons law, all 54 apps get new professional icons
  later — icons made while proving the wrapper are temporary only.
- iOS only (`--platforms ios`): no Android folder, no Android code.

## Product IDs (IAP + subscriptions) — the law

NEVER any dots or underscores in ANY product ID, for IAPs and for
subscriptions alike. One subscription group per app.

- One-time Pro (non-consumable): `<shortName>pro`
- Monthly subscription (auto-renewable): `<shortName>monthly`
- Yearly subscription (auto-renewable): `<shortName>yearly`

Examples: `stampmarkpro`, `stampmarkmonthly`, `stampmarkyearly`;
`decibelpropro`, `decibelpromonthly`, `decibelproyearly`.

The products must be created in App Store Connect with exactly these IDs.
Until they exist, the wrapper hides their buy buttons cleanly — nothing
crashes, nothing shows a broken price. The moment the products exist,
buying works with no code change. Purchases restore across devices
(`restore()`), and Pro ownership is persisted locally.

## Bundle ID scheme — SEO / ASO optimized

Bundle ID = `com.<category>.<appname>`

Rules:
- All lowercase. No dots, underscores or hyphens inside the slug.
- The CATEGORY WORD comes FIRST (one lowercase Apple category word), then the app name.
- No 'wajiha' and no 'games' anywhere in the bundle ID.

Examples:
- stampmark -> `com.photovideo.stampmark`
- decibelpro -> `com.utilities.decibelpro`
- billguard -> `com.finance.billguard`

The full 54-app mapping lives in `../WRAPPER_V2_REPORT.md`.
Bundle IDs follow the Nov 14 scheme (`com.<category>.<appname>`) — do NOT rename them by hand here.

## JS bridge (AppBridge)

The wrapper adds a JavascriptChannel named `AppBridge`. The injected
`pro-panel.js` turns it into the API the HTML app calls:

- `AppBridge.isPro()` -> Promise<boolean> (current Pro status)
- `AppBridge.buyPro()` -> start the one-time Pro purchase
- `AppBridge.buyMonthly()` -> start the monthly subscription
- `AppBridge.buyYearly()` -> start the yearly subscription
- `AppBridge.restore()` -> restore past purchases
- `AppBridge.rateApp()` -> native review prompt
- `AppBridge.shareApp()` -> native share sheet (App Store link)
- `AppBridge.moreApps()` -> open https://wajiha.fun in the system browser
- `AppBridge.showProPanel()` / `AppBridge.hideProPanel()`
- `AppBridge.pro` -> cached boolean (sync read, updated on every push)

Native -> HTML: the wrapper calls `window.onProStatusChanged(true/false)`
whenever Pro status changes (and once after page load), so the HTML can
unlock/lock Pro features live. If the HTML already defines its own
`onProStatusChanged`, it still runs (the injected one chains to it).
Native also calls `window.onStoreProducts({...})` after the store query,
with each product's real price and availability.

## In-app marketing (in every app, via the template)

- **Go Pro panel**: a neutral dark bottom sheet (never garish, system font
  only) injected by the wrapper — `assets/pro-panel.js` + `pro-panel.css`.
  Shows the app's Pro benefits (from `AppConfig.proBenefits`), Go Pro /
  Monthly / Yearly buttons with real store prices, Restore, Share and
  More apps, and a close button. A small floating "★ Pro" pill opens it;
  the pill hides once the user is Pro. Products that do not exist yet
  have no button at all.
- **Rate prompt**: after the 3rd launch, the native review prompt shows
  once (launches counted locally; never again after that).
- **Share**: the panel's Share button opens the native share sheet with
  the app's App Store link.
- **More apps cross-promo**: the panel's More apps button opens
  https://wajiha.fun in the system browser. No placeholder links.

## How to make a new app from this template

1. Copy this whole folder to `../ios/<slug>/`.
2. In the copy:
   - `lib/app_config.dart`: set `shortName`, `appName`, `appStoreUrl`
     (update once the App Store ID is known) and `proBenefits`.
   - `pubspec.yaml`: set `name:` to the slug, set `version:` (e.g. `1.0.0+1`).
   - `assets/app.html`: replace with the app's fixed HTML from `../fixed/`.
   - `ios/Runner/Info.plist`: set `CFBundleDisplayName` to the app name.
   - `ios/Runner.xcodeproj/project.pbxproj`: set `PRODUCT_BUNDLE_IDENTIFIER`
     to the app's bundle ID (`com.<category>.<shortName>`) in all
     three build configurations (Debug / Release / Profile).
   - Icons: draw the app's 1024x1024 master and regenerate the set with
     `../make_icon.py` (add a `draw_<slug>` function to the script first).
3. Run `flutter pub get`, `flutter analyze` (must be 0 issues) and
   `flutter test` (must pass — it proves the Dart compiles and the
   product IDs follow the law).
4. Prove it compiles: `flutter build bundle --release` exits 0. The real
   iOS compile proof is the signed GitHub Actions build (`flutter build
   ios` needs a Mac or the runner — it cannot run on this Linux machine).
5. Signing (needs the owner's steps, per app): create the App ID +
   provisioning profile in App Store Connect, create the GitHub repo, save
   the 7 secrets, copy `.github/workflows/signed-ios-build.yml` from
   `~/workspace/boardgames100/apple-ready/_shared/` into the repo, trigger
   the workflow. It builds the signed IPA and uploads it to TestFlight.
6. Store products (needs the owner's steps, per app): in App Store
   Connect create the one-time Pro product (`<shortName>pro`) and the
   subscription group with monthly (`<shortName>monthly`) and yearly
   (`<shortName>yearly`). IDs must match this file exactly, no dots,
   no underscores.

## Honest limits

- A real StoreKit purchase can only be proven on a real device or
  TestFlight. This Linux machine cannot run StoreKit: the flow here is
  verified by `flutter analyze` (0 issues), `flutter test` (compiles all
  Dart, checks the product-ID law) and a line-by-line code review of the
  purchase flow. The first real buy/restore test must happen on her
  iPhone via TestFlight.
- There is no server-side receipt verification; Pro ownership is the
  local purchase record (same level as the board games).
