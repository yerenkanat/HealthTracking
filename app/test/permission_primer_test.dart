/// The permission primer sheet: it explains before the OS prompt and returns
/// whether to proceed. "Continue" resolves true, "Not now" / dismiss resolves
/// false — so a soft no never fires the one-shot OS request.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/widgets/permission_primer.dart';

const _en = L10n(AppLocale.en);

/// Pump a button that opens the primer and records its boolean result.
Future<bool?> _open(WidgetTester tester, PermissionKind kind) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: _en,
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await showPermissionPrimer(context, kind),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('location primer shows the rationale before any OS prompt', (tester) async {
    await _open(tester, PermissionKind.location);
    expect(find.text(_en.t('prime_loc_title')), findsOneWidget);
    expect(find.textContaining('safe zones'), findsOneWidget); // the "why"
    expect(find.text(_en.t('prime_continue')), findsOneWidget);
    expect(find.text(_en.t('prime_not_now')), findsOneWidget);
  });

  testWidgets('Continue returns true and Not now returns false', (tester) async {
    // Continue → true
    var proceed = await _openAndTap(tester, PermissionKind.location, _en.t('prime_continue'));
    expect(proceed, isTrue);
    // Not now → false
    proceed = await _openAndTap(tester, PermissionKind.notifications, _en.t('prime_not_now'));
    expect(proceed, isFalse);
  });

  testWidgets('notifications primer uses its own copy', (tester) async {
    await _open(tester, PermissionKind.notifications);
    expect(find.text(_en.t('prime_notif_title')), findsOneWidget);
  });
}

/// Open the primer and tap [label], returning the resolved proceed value.
Future<bool?> _openAndTap(WidgetTester tester, PermissionKind kind, String label) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: _en,
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await showPermissionPrimer(context, kind),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  return result;
}
