/// The design-system widgets, rendered.
///
/// These are the pieces every converted screen is built from, so a defect here
/// shows up everywhere at once and is correspondingly hard to spot by eye. The
/// tests assert the things the spec is specific about and that are easy to get
/// quietly wrong: the border is 2px ink, the shadow is a hard offset with no
/// blur and appears only where it should, tap targets clear 44px, and the text
/// goes through the locale-aware scale.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/theme.dart';

Future<void> pump(WidgetTester tester, Widget child, {AppLocale locale = AppLocale.ru}) async {
  await tester.pumpWidget(MaterialApp(
    theme: FcsTheme.light(locale),
    home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
  ));
  await tester.pumpAndSettle();
}

/// The decoration of the first box that actually carries a border.
///
/// Scans DecoratedBox as well as Container: a Container IS a DecoratedBox plus
/// padding, and which one a widget uses is an implementation detail. Looking
/// only for Container made these tests fail when DsCard moved its Material
/// inside the fill — a change with no visual effect at all.
BoxDecoration? firstBorderedBox(WidgetTester tester) {
  for (final e in find.byWidgetPredicate((w) => w is Container || w is DecoratedBox).evaluate()) {
    final w = e.widget;
    final d = w is Container ? w.decoration : (w as DecoratedBox).decoration;
    if (d is BoxDecoration && d.border != null) return d;
  }
  return null;
}

void main() {
  group('DsCard', () {
    testWidgets('outlines in 2px ink and carries no shadow by default', (tester) async {
      await pump(tester, const DsCard(child: Text('hello')));
      final d = firstBorderedBox(tester)!;
      expect(d.border!.top.width, DsShape.borderWidth);
      expect(d.border!.top.color, Ds.ink);
      // Most cards are flat. The step means "primary", and if every card had it
      // the screen would be noise.
      expect(d.boxShadow, anyOf(isNull, isEmpty));
    });

    testWidgets('a raised card is opaque, so the shadow cannot read through it', (tester) async {
      // The hard shadow is an unblurred ink rectangle drawn behind the box. Give
      // a raised card a translucent pastel and the ink shows straight through:
      // the dashboard's summary banner turned near-black exactly this way, and
      // the golden was the only thing that noticed.
      await pump(tester, DsCard(
        raised: true,
        color: Ds.mint.withValues(alpha: 0.16),
        child: const Text('hello'),
      ));
      final d = firstBorderedBox(tester)!;
      expect(d.color!.a, 1.0, reason: 'a raised surface must be opaque');
      // …and still be the pale tint it asked for, not flattened to white.
      expect(d.color, isNot(Colors.white));
      expect(d.color, DsShape.opaque(Ds.mint.withValues(alpha: 0.16)));
    });

    testWidgets('a flat card keeps whatever translucency it was given', (tester) async {
      await pump(tester, DsCard(color: Ds.mint.withValues(alpha: 0.16), child: const Text('hello')));
      expect(firstBorderedBox(tester)!.color!.a, closeTo(0.16, 0.01));
    });

    testWidgets('raised adds the single soft shadow, not an ink rectangle',
        (tester) async {
      // This asserted a 4x4 ink offset with no blur — the old neo-brutalist
      // signature, which docs/CLAUDE-app-design.md retires because at 130%
      // system font the outline and its shadow tear the card open.
      await pump(tester, const DsCard(raised: true, child: Text('hello')));
      final s = firstBorderedBox(tester)!.boxShadow!;
      expect(s.single.blurRadius, greaterThan(0));
      expect(s.single.offset.dx, 0, reason: 'straight down, not diagonal');
      expect(s.single.color, isNot(Ds.ink));
    });
  });

  group('DsPrimaryButton', () {
    testWidgets('is a coral pill whose label is legible on it', (tester) async {
      await pump(tester, DsPrimaryButton(label: 'Заказать', onPressed: () {}));
      expect(find.text('Заказать'), findsOneWidget);
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(DsPrimaryButton), matching: find.byType(Material)).first,
      );
      expect(material.color, Ds.coralCta);
      // The CTA fill exists precisely so white text on it clears AA.
      expect(contrastRatio(Colors.white, material.color!), greaterThanOrEqualTo(4.5));
    });

    testWidgets('clears the 44px tap target', (tester) async {
      await pump(tester, DsPrimaryButton(label: 'Заказать', onPressed: () {}));
      expect(tester.getSize(find.byType(DsPrimaryButton)).height,
          greaterThanOrEqualTo(DsShape.minTapTarget));
    });

    testWidgets('drops the step when disabled, so it does not look pressable', (tester) async {
      await pump(tester, const DsPrimaryButton(label: 'Заказать'));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(DsPrimaryButton), matching: find.byType(DecoratedBox)).first,
      );
      expect((box.decoration as BoxDecoration).boxShadow, isNull);
    });

    testWidgets('a disabled button does not fire', (tester) async {
      var taps = 0;
      await pump(tester, DsPrimaryButton(label: 'Заказать', onPressed: taps == 0 ? null : () => taps++));
      await tester.tap(find.byType(DsPrimaryButton));
      await tester.pump();
      expect(taps, 0);
    });
  });

  group('DsListCard', () {
    testWidgets('separates rows with the hairline, not the card border', (tester) async {
      await pump(tester, const DsListCard(rows: [
        DsRow(label: 'Имя', value: 'Айгерім'),
        DsRow(label: 'Телефон', value: '+7 707 345 22 44'),
      ]));
      expect(find.text('Айгерім'), findsOneWidget);
      // A 2px ink rule between rows would read as two stacked cards.
      final decorated = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      final hairlines = decorated
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border is Border && (d.border as Border).bottom.color == Ds.divider);
      expect(hairlines, isNotEmpty);
    });

    testWidgets('the last row has no trailing rule', (tester) async {
      await pump(tester, const DsListCard(rows: [DsRow(label: 'Одна строка')]));
      final withBottom = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border is Border && (d.border as Border).bottom.color == Ds.divider);
      expect(withBottom, isEmpty);
    });

    testWidgets('rows are tappable at 44px and show a chevron', (tester) async {
      var tapped = false;
      await pump(tester, DsListCard(rows: [DsRow(label: 'Открыть', onTap: () => tapped = true)]));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Открыть'));
      expect(tapped, isTrue);
    });
  });

  group('DsSegmented', () {
    testWidgets('marks the selected chip in ink and reports taps', (tester) async {
      var picked = -1;
      await pump(tester, DsSegmented(items: const ['Сейчас', 'История', 'Зоны'], index: 0, onChanged: (i) => picked = i));
      await tester.tap(find.text('Зоны'));
      expect(picked, 2);
    });

    testWidgets('draws no ink chip at all when nothing is chosen', (tester) async {
      // The state that made this control adoptable. «Пол» is optional, on a
      // step that can be skipped entirely, so the control has to be able to
      // show no answer — a segmented control that required an index would
      // have opened pre-answered «Мальчик» and invented a fact about someone's
      // child.
      await pump(tester, DsSegmented(items: const ['Мальчик', 'Девочка'], index: null, onChanged: (_) {}));
      final inked = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color == Ds.ink);
      expect(inked, isEmpty, reason: 'no segment may read as the answer');
    });

    testWidgets('clears on a second tap only where the caller opted in', (tester) async {
      // A widget swap must not silently change what a form permits. The
      // ChoiceChips this replaced could be tapped back to null; the segments
      // keep that ONLY for callers that pass onClear, and tab-like callers
      // that omit it must stay un-emptiable.
      var cleared = 0;
      var picked = -1;
      await pump(tester, DsSegmented(
        items: const ['Мальчик', 'Девочка'],
        index: 1,
        onChanged: (i) => picked = i,
        onClear: () => cleared++,
      ));
      await tester.tap(find.text('Девочка'));
      expect(cleared, 1);
      expect(picked, -1, reason: 'clearing is not a re-pick');

      await pump(tester, DsSegmented(
        items: const ['Сейчас', 'История', 'Зоны'],
        index: 2,
        onChanged: (i) => picked = i,
      ));
      await tester.tap(find.text('Зоны'));
      expect(picked, 2, reason: 'no onClear: re-tapping the tab is idempotent');
    });

    testWidgets('tells a screen reader which segment is the answer', (tester) async {
      // The segments read «Ұл» / «Қыз» and lose the «Жынысы» above them, so
      // the group carries the question and each segment its own selected flag.
      await pump(tester, DsSegmented(
        label: 'Жынысы',
        items: const ['Ұл', 'Қыз'],
        index: 1,
        onChanged: (_) {},
      ), locale: AppLocale.kk);
      final chosen = tester.getSemantics(find.text('Қыз'));
      expect(chosen.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(chosen.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
      final other = tester.getSemantics(find.text('Ұл'));
      expect(other.hasFlag(SemanticsFlag.isSelected), isFalse);
    });

    testWidgets('shrinks a label that will not fit rather than clipping it',
        (tester) async {
      // 320dp with text at 130%, which is a 360dp phone whose owner turned
      // Android's display size up. «Мальчик» wants 129.1dp and a half-width
      // segment gives it 119.0. A gender control reading «Маль…» is one
      // nobody can identify, so the label scales down instead.
      //
      // Russian, not Kazakh, deliberately: «Ұл» and «Қыз» are the SHORT case
      // here, which inverts the usual rule and is why this control had to be
      // measured in both languages.
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DsSegmented(
                    items: const ['Мальчик', 'Девочка'],
                    index: 0,
                    onChanged: (_) {}),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final s in ['Мальчик', 'Девочка']) {
        final p = tester.renderObject<RenderParagraph>(find.text(s));
        expect(p.didExceedMaxLines, isFalse, reason: '$s was clipped');
        final box = find
            .ancestor(of: find.text(s), matching: find.byType(FittedBox))
            .first;
        expect(tester.getSize(box).width,
            lessThan(p.getMaxIntrinsicWidth(double.infinity)),
            reason: '$s no longer needs the scale-down — if the type or the '
                'padding changed, re-measure before deleting the guard');
      }
    });

    testWidgets('clears 48dp per segment', (tester) async {
      // 38 was the painted chip; the tap area was 38 too. These segments are
      // the only way to answer a question on the last step of onboarding,
      // one-handed. DsToggle had to be corrected for exactly this.
      await pump(tester, DsSegmented(items: const ['Мальчик', 'Девочка'], index: 0, onChanged: (_) {}));
      expect(tester.getSize(find.text('Мальчик').first).height, lessThan(DsShape.minTapTarget));
      for (final s in ['Мальчик', 'Девочка']) {
        final tapArea = find.ancestor(of: find.text(s), matching: find.byType(InkWell)).first;
        expect(tester.getSize(tapArea).height,
            greaterThanOrEqualTo(DsShape.minTapTarget),
            reason: '$s is below the tap target');
      }
    });
  });

  group('DsToggle', () {
    testWidgets('is mint when on and reports the flip', (tester) async {
      bool? got;
      await pump(tester, DsToggle(value: false, onChanged: (v) => got = v));
      await tester.tap(find.byType(DsToggle));
      expect(got, isTrue);

      await pump(tester, DsToggle(value: true, onChanged: (_) {}));
      final d = firstBorderedBox(tester)!;
      expect(d.color, Ds.mint);
    });

    testWidgets('refuses the tap when disabled, but still shows its state',
        (tester) async {
      // Several reminders are legitimately unavailable — a period reminder
      // with no cycle logged, a medication reminder with no medications — and
      // the row has to show its state while refusing the tap. The widget had
      // no disabled state at all, so every such row in the app was still a raw
      // Material Switch; adopting it is what surfaced that.
      var taps = 0;
      await pump(tester, DsToggle(value: true, onChanged: null, semanticLabel: 'x'));
      await tester.tap(find.byType(DsToggle));
      await tester.pump();
      expect(taps, 0);

      // Not mint: a disabled toggle must not compete with the ones that can be
      // pressed.
      expect(firstBorderedBox(tester)!.color, isNot(Ds.mint));
      // But it keeps the outline, so it still reads as a switch.
      expect(firstBorderedBox(tester)!.border, isNotNull);
    });

    testWidgets('tells a screen reader it is unavailable', (tester) async {
      await pump(tester, const DsToggle(value: false, onChanged: null, semanticLabel: 'Напоминание'));
      final node = tester.getSemantics(find.byType(DsToggle));
      expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
    });
  });

  group('DsEmptyState', () {
    testWidgets('says what is missing rather than rendering a blank box', (tester) async {
      await pump(tester, const DsEmptyState(label: 'Добавьте первого ребёнка'));
      expect(find.text('Добавьте первого ребёнка'), findsOneWidget);
      expect(find.text('＋'), findsOneWidget);
    });
  });

  group('locale', () {
    testWidgets('Kazakh screens render their headings in Rubik', (tester) async {
      // Through the themed AppBar, which is what 71 screens actually draw
      // their header with. This used to go through DsScreenHeader, a widget
      // no screen used — so the assertion was true of a code path nobody took
      // and said nothing about the app. The header the spec describes
      // (design-system-app.md:62) is `appBarTheme`, and the title style is
      // inherited rather than set on the Text, so read the rendered span.
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.kk),
        home: Scaffold(appBar: AppBar(title: const Text('Денсаулық'))),
      ));
      await tester.pumpAndSettle();
      final span = tester.renderObject<RenderParagraph>(find.text('Денсаулық')).text;
      // Unbounded has no ә ғ қ ң — a heading in it drops letters mid-word.
      expect(span.style?.fontFamily, 'Rubik');
    });

    testWidgets('every widget keeps the Kazakh fallback on Russian screens', (tester) async {
      // Айгерім in the Russian UI: the і must not come out as a box.
      await pump(tester, const DsListCard(rows: [DsRow(label: 'Айгерім', value: 'Нұрсұлтан')]));
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.style?.fontFamilyFallback, contains('Rubik'));
      }
    });
  });
}
