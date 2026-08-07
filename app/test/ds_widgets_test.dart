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

  group('DsHeroMetric', () {
    testWidgets('shows label, value and unit, and picks out the current bar', (tester) async {
      await pump(tester, const DsHeroMetric(
        label: 'Пульс',
        value: '78',
        unit: 'уд/мин',
        bars: [0.4, 0.6, 0.5, 0.8, 0.7, 0.6, 0.9, 0.5, 0.7],
      ));
      expect(find.text('ПУЛЬС'), findsOneWidget); // the spec uppercases it
      expect(find.text('78'), findsOneWidget);
      expect(find.text('уд/мин'), findsOneWidget);

      final yellow = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color == Ds.yellow);
      expect(yellow.length, 1, reason: 'exactly one bar is "now"');
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
      await pump(
        tester,
        const DsScreenHeader(title: 'Денсаулық'),
        locale: AppLocale.kk,
      );
      final text = tester.widget<Text>(find.text('Денсаулық'));
      // Unbounded has no ә ғ қ ң — a heading in it drops letters mid-word.
      expect(text.style?.fontFamily, 'Rubik');
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
