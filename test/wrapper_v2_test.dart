import 'package:sizetwin/app_config.dart';
import 'package:sizetwin/main.dart' as app_main;
import 'package:sizetwin/store_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compile + law checks for wrapper v2.
///
/// `flutter test` compiles every imported file, so this is the real
/// compile proof on this Linux machine (flutter build ios needs a Mac).
/// It does NOT test real StoreKit — that can only be proven on a real
/// device / TestFlight.
void main() {
  test('product IDs follow the no-dots no-underscores law', () {
    expect(AppStore.proId, 'sizetwinpro');
    expect(AppStore.monthlyId, 'sizetwinmonthly');
    expect(AppStore.yearlyId, 'sizetwinyearly');
    for (final id in AppStore.productIds) {
      expect(id.contains('.'), isFalse, reason: 'dot in $id');
      expect(id.contains('_'), isFalse, reason: 'underscore in $id');
    }
  });

  test('main.dart compiles and AppShell exists', () {
    expect(app_main.AppShell, isNotNull);
    expect(AppConfig.appStoreUrl, startsWith('https://'));
    expect(AppConfig.moreAppsUrl, 'https://wajiha.fun');
  });
}
