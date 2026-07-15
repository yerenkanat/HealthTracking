/// Widget test for the Emergency Rescue screen (run with `flutter test`).
/// Verifies: the triage message renders, the primary call button shows the right
/// number and fires onCall, and dismissal requires explicit confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ui/emergency/emergency_rescue_screen.dart';

void main() {
  Widget harness({
    required Future<void> Function(EmergencyCallButton) onCall,
    required Future<void> Function() onDismiss,
  }) =>
      MaterialApp(
        home: EmergencyRescueScreen(
          message:
              'High blood pressure detected — a warning sign of preeclampsia. Contact your doctor immediately.',
          details: const ['systolicMmHg 150 ≥ 140'],
          callButtons: const [
            EmergencyCallButton('Call ambulance', '103'),
            EmergencyCallButton('Call your doctor', '+77001234567'),
          ],
          onCall: onCall,
          onDismissConfirmed: onDismiss,
        ),
      );

  testWidgets('renders message and both call buttons', (tester) async {
    await tester.pumpWidget(harness(onCall: (_) async {}, onDismiss: () async {}));
    expect(find.textContaining('preeclampsia'), findsOneWidget);
    expect(find.textContaining('103'), findsOneWidget);
    expect(find.textContaining('+77001234567'), findsOneWidget);
  });

  testWidgets('tapping the primary button calls with the ambulance number', (tester) async {
    EmergencyCallButton? called;
    await tester.pumpWidget(harness(onCall: (b) async => called = b, onDismiss: () async {}));
    await tester.tap(find.textContaining('Call ambulance'));
    await tester.pump();
    expect(called?.tel, '103');
  });

  testWidgets('dismissal requires confirmation', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(harness(onCall: (_) async {}, onDismiss: () async => dismissed = true));

    await tester.tap(find.text("This isn't an emergency"));
    await tester.pumpAndSettle();
    // Confirmation dialog is shown; nothing dismissed yet.
    expect(dismissed, isFalse);
    expect(find.text('Dismiss this alert?'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('back gesture cannot pop the screen', (tester) async {
    await tester.pumpWidget(harness(onCall: (_) async {}, onDismiss: () async {}));
    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
  });
}
