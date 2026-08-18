/// The onboarding text fields must show what the app actually holds.
///
/// Found on a real device. She fills in «Aigerim» and her number, ticks
/// «Я жду ребёнка» and picks a due date, reaches the Bluetooth step and DENIES
/// the permission. The flow bounces back one step — and the name and phone are
/// blank, while the pregnancy switch and the due date are still there.
///
/// This was first written up as "onboarding clears the name". It does not. All
/// three fields were declared with `onChanged:` and no `controller:`, so each
/// [TextField] made its own private [TextEditingController], empty, on every
/// fresh [State]. The bounce built a new [_ProfilePage] state; the field painted
/// empty; [OnboardingController.displayName] still said "Aigerim" the whole
/// time.
///
/// So the defect is not lost data — it is a field that LIES about what the app
/// holds, and the other two symptoms fall straight out of that:
///
///   * «Далее» stayed ENABLED over an apparently blank required field, because
///     `canProceed` reads the model, and the model was intact. Minutes earlier
///     that same-looking empty field had greyed it out with «Напишите имя, чтобы
///     продолжить», so the app contradicted itself on the same screen.
///   * The pregnancy switch survived because it is not a TextField: it reads the
///     model on every build. Which is precisely what the fields now do.
///
/// The assertions below are therefore about what is DRAWN, and about the drawn
/// state agreeing with the button — not about the model, which was never the
/// broken half.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/data/device_location.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

void main() {
  // The zone tiles really ask the device where it is; a widget test has no
  // platform channel to answer with.
  setUp(() => debugLocationOverride =
      () async => const LocationResult.ok(Coordinates(43.238949, 76.889709)));
  tearDown(() => debugLocationOverride = null);

  // L10nScope ABOVE MaterialApp: below the Navigator it would leave anything
  // pushed in English, silently.
  Widget flow(OnboardingController c) => L10nScope(
        l10n: const L10n(AppLocale.en),
        child: MaterialApp(
          home: OnboardingFlow(controller: c, onComplete: (_) {}),
        ),
      );

  Finder nameField() => find.byType(TextField).first;
  Finder phoneField() => find.byType(TextField).last;

  /// The controller the field is really editing — the one whose text is on
  /// screen, whoever created it.
  TextEditingController editing(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)))
      .controller;

  String drawn(WidgetTester tester, Finder field) => editing(tester, field).text;

  FilledButton primary(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  /// Welcome → language → profile, the way she gets there.
  Future<void> toProfile(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // language
    await tester.pumpAndSettle();
    expect(find.text("What's your name?"), findsOneWidget);
  }

  testWidgets('a step she is bounced back to still shows her name and number',
      (tester) async {
    // The device report, reproduced: forward off the profile step, then back
    // onto it. Back is what the denied-permission bounce does, and it is also
    // the ordinary AppBar arrow, so this is the path she takes either way.
    final c = OnboardingController(initialLocale: AppLocale.en);
    addTearDown(c.dispose);
    await tester.pumpWidget(flow(c));
    await tester.pumpAndSettle();
    await toProfile(tester);

    await tester.enterText(nameField(), 'Aigerim');
    await tester.enterText(phoneField(), '7001234567');
    await tester.pumpAndSettle();
    // She also ticks the pregnancy switch. It is here as the control group: it
    // survived the bounce when the fields did not, and it must keep surviving.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Pair your band'), findsOneWidget);

    // The bounce.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text("What's your name?"), findsOneWidget);

    expect(drawn(tester, nameField()), 'Aigerim',
        reason: 'the name field is blank over a controller that still holds '
            '"${c.displayName}" — the field is lying about what the app has');
    expect(drawn(tester, phoneField()), '700 123 45 67',
        reason: 'same for the number, grouped as she typed it');
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue,
        reason: 'the switch reads the model on every build and always did');
  });

  testWidgets('a blank-looking name never sits under an enabled «Next»',
      (tester) async {
    // The contradiction, pinned on its own. Whatever is drawn in the name field
    // and whatever the button does must be two halves of the same fact: an
    // empty field disables «Next», a filled one enables it. It cannot be empty
    // AND enabled, which is what she saw — and she then tapped it, and finished
    // signup with a name she never saw confirmed.
    final c = OnboardingController(initialLocale: AppLocale.en);
    addTearDown(c.dispose);
    await tester.pumpWidget(flow(c));
    await tester.pumpAndSettle();
    await toProfile(tester);

    // Empty and gated, with the reason said out loud.
    expect(drawn(tester, nameField()), isEmpty);
    expect(primary(tester).onPressed, isNull);
    expect(find.text('Enter your name to continue'), findsOneWidget);

    await tester.enterText(nameField(), 'Aigerim');
    await tester.enterText(phoneField(), '7001234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(primary(tester).onPressed, isNotNull); // the model is intact
    expect(drawn(tester, nameField()), isNotEmpty,
        reason: '«Next» is enabled over a field that looks empty — the app is '
            'saying two different things about the same required answer');
  });

  testWidgets('a page built fresh over a filled-in model shows what it holds',
      (tester) async {
    // The mechanism underneath the bounce, with no navigation at all: a brand
    // new State for a model that already knows her. Nothing but a seeded
    // controller can make this pass.
    final c = OnboardingController(initialLocale: AppLocale.en)
      ..setDisplayName('Aigerim')
      ..setPhoneNumber('700 123 45 67');
    addTearDown(c.dispose);
    for (var guard = 0; c.step != OnboardingStep.profile && guard < 10; guard++) {
      c.next();
    }
    expect(c.step, OnboardingStep.profile);

    await tester.pumpWidget(flow(c));
    await tester.pumpAndSettle();

    expect(drawn(tester, nameField()), 'Aigerim');
    expect(drawn(tester, phoneField()), '700 123 45 67');
    // Drawn, not merely held: find.text reads the painted EditableText.
    expect(find.text('Aigerim'), findsOneWidget);
  });

  testWidgets('typing still reaches the model', (tester) async {
    // The other direction. A controller that displays the model but no longer
    // records what she types would pass every assertion above and break signup
    // completely.
    final c = OnboardingController(initialLocale: AppLocale.en);
    addTearDown(c.dispose);
    await tester.pumpWidget(flow(c));
    await tester.pumpAndSettle();
    await toProfile(tester);

    await tester.enterText(nameField(), 'Aigerim');
    await tester.pumpAndSettle();
    expect(c.displayName, 'Aigerim');

    await tester.enterText(phoneField(), '7001234567');
    await tester.pumpAndSettle();
    expect(c.phoneNumber, '700 123 45 67');
    expect(c.build().profile.e164, '+77001234567');
  });

  testWidgets('the caret stays where she left it while the page rebuilds',
      (tester) async {
    // The regression the fix could easily introduce. Syncing the field from the
    // model unconditionally on every build reassigns `.text`, which drops the
    // selection — so the caret jumps out of the word mid-keystroke and she gets
    // her own name backwards. Assign ONLY when the two genuinely differ.
    final c = OnboardingController(initialLocale: AppLocale.en);
    addTearDown(c.dispose);
    await tester.pumpWidget(flow(c));
    await tester.pumpAndSettle();
    await toProfile(tester);

    await tester.enterText(nameField(), 'Aigerim');
    await tester.pumpAndSettle();
    final field = editing(tester, nameField());
    expect(field.selection.baseOffset, 'Aigerim'.length,
        reason: 'the caret is not at the end of what she just typed');

    // She taps back into the middle of the word to fix a letter, and something
    // else on the page publishes a change — here the pregnancy switch, which
    // rebuilds the whole flow through its StreamBuilder.
    field.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(editing(tester, nameField()).text, 'Aigerim');
    expect(editing(tester, nameField()).selection.baseOffset, 3,
        reason: 'the caret was thrown back to the start of the field by a '
            'rebuild she did not cause');
  });

  testWidgets('the child name field keeps its value too', (tester) async {
    // Same defect, third field. Reached by stepping back off the child page and
    // forward onto it again — which is exactly what she does after tapping
    // «Использовать текущее» and being told the location failed.
    final c = OnboardingController(initialLocale: AppLocale.en)
      ..setDisplayName('Aigerim')
      ..setPhoneNumber('700 123 45 67');
    addTearDown(c.dispose);
    for (var guard = 0; c.step != OnboardingStep.child && guard < 10; guard++) {
      c.next();
    }
    expect(c.step, OnboardingStep.child);

    await tester.pumpWidget(flow(c));
    await tester.pumpAndSettle();
    expect(find.text('Add your child'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Sultan');
    await tester.pumpAndSettle();
    expect(c.childName, 'Sultan');

    await tester.tap(find.byIcon(Icons.arrow_back)); // back to pairing
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // and forward again
    await tester.pumpAndSettle();

    expect(find.text('Add your child'), findsOneWidget);
    expect(drawn(tester, find.byType(TextField).first), 'Sultan',
        reason: 'the child page shows an empty name while offering «Finish» '
            'for a child it still has');
  });
}
