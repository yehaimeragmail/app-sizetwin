/// Per-app constants. Set these at clone time — everything else in the
/// wrapper (product IDs, bundle ID, share text, Pro panel) is derived
/// from the values here, so a clone only ever edits this one file plus
/// the asset and the icon.
///
/// RULES (Nov 13 laws, updated Nov 14 — do not break them):
/// - `shortName`: all lowercase, letters and digits only. NEVER dots,
///   underscores or hyphens. It is the first part of every product ID.
/// - Product IDs are `<shortName>pro` (one-time Pro),
///   `<shortName>monthly` (monthly subscription) and
///   `<shortName>yearly` (yearly subscription). No dots, no underscores.
/// - Bundle ID is `com.<category>.<shortName>` — one lowercase Apple
///   category word FIRST, then the short name. No 'wajiha' and no
///   'games' anywhere in any bundle ID. Examples:
///   stampmark -> com.photovideo.stampmark
///   decibelpro -> com.utilities.decibelpro
///   billguard -> com.finance.billguard
class AppConfig {
  /// Short name, all lowercase, no dots/underscores/hyphens.
  /// Example: 'stampmark'.
  static const String shortName = 'sizetwin';

  /// Display name shown on the home screen and in the share text.
  /// Example: 'Stamp Mark'.
  static const String appName = 'Size Twin';

  /// The app's App Store URL, used by the native share sheet.
  /// Until the app is live, this is the future URL pattern — update it
  /// at clone time once the App Store ID is known.
  static const String appStoreUrl =
      'https://apps.apple.com/app/id0000000000';

  /// URL for the "More apps" cross-promo button. Always wajiha.fun.
  static const String moreAppsUrl = 'https://wajiha.fun';

  /// Benefits shown in the Go Pro panel. Edit at clone time so they fit
  /// this app. Keep them short, in plain words, one benefit per line.
  static const List<String> proBenefits = [
    'Unlimited brands and size charts',
    'Save all your fits in one place',
    'No limits, forever',
  ];
}
