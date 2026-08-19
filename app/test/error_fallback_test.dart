/// Does a screen that throws actually show something usable?
///
/// The unit tests cover the log. This covers the part the user sees, by
/// building a widget that genuinely throws and asserting on what ends up on
/// screen — the only way to know ErrorWidget.builder is wired at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/widgets/error_fallback.dart';

/// A widget whose build always fails, standing in for any screen bug.
class _Exploding extends StatelessWidget {
  const _Exploding({super.key});
  @override
  Widget build(BuildContext context) => throw StateError('bad state in build');
}

/// A first route that can push a screen which then throws — the shape almost
/// every failure in this app actually has, since nearly everything past the
/// home shell is pushed.
class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const _Exploding())),
            child: const Text('home screen'),
          ),
        ),
      );
}

Widget _wrap(Widget child, {AppLocale locale = AppLocale.ru}) => L10nScope(
      l10n: L10n(locale),
      child: MaterialApp(home: child),
    );

void main() {
  // flutter_test asserts ErrorWidget.builder is back to the framework's own by
  // the time a test body returns, so the override is scoped to each test
  // rather than done in setUp.
  Future<void> withFallbackBuilder(WidgetTester t, Future<void> Function() body) async {
    final original = ErrorWidget.builder;
    ErrorWidget.builder = (details) => const ErrorFallback();
    try {
      await body();
    } finally {
      ErrorWidget.builder = original;
    }
  }

  testWidgets('a screen that throws shows an explanation, not a grey box', (t) async {
    await withFallbackBuilder(t, () async {
      await t.pumpWidget(_wrap(const _Exploding()));
      // Consuming the exception both keeps the test from failing on it and
      // proves the widget really did throw — without this the test could pass
      // against a widget that quietly rendered nothing.
      expect(t.takeException(), isA<StateError>());
      expect(find.text(const L10n(AppLocale.ru).t('err_title')), findsOneWidget);
      // The FIRST route threw, so there is nowhere to pop back to and the copy
      // is the one that does not send her to a button that isn't there.
      expect(find.text(const L10n(AppLocale.ru).t('err_body_restart')), findsOneWidget);
    });
  });

  testWidgets('a pushed screen that throws offers a way back that really goes back', (t) async {
    await withFallbackBuilder(t, () async {
      await t.pumpWidget(_wrap(const _Home()));
      await t.tap(find.text('home screen'));
      await t.pump();
      expect(t.takeException(), isA<StateError>());
      await t.pumpAndSettle();

      // The fallback is up, and NOW the body's instruction is backed by a
      // control: this is the case «Вернитесь на главный экран» was written for.
      expect(find.text(const L10n(AppLocale.ru).t('err_body')), findsOneWidget);
      final back = find.text(const L10n(AppLocale.ru).t('err_back'));
      expect(back, findsOneWidget);

      await t.tap(back);
      await t.pumpAndSettle();

      // And it recovered rather than rebuilding into the same exception: the
      // home screen is on screen, the error screen is gone, and — the part that
      // separates a real way out from a redraw — nothing threw a second time.
      expect(find.text('home screen'), findsOneWidget);
      expect(find.text(const L10n(AppLocale.ru).t('err_title')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('the way back survives more than one push', (t) async {
    // popUntil(isFirst), not pop(): two screens deep, one pop would land her on
    // the intermediate screen, which is not «главный экран».
    await withFallbackBuilder(t, () async {
      await t.pumpWidget(_wrap(const _Home()));
      final nav = t.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('middle'))));
      await t.pumpAndSettle();
      nav.push(MaterialPageRoute(builder: (_) => const _Exploding()));
      await t.pump();
      expect(t.takeException(), isA<StateError>());
      await t.pumpAndSettle();

      await t.tap(find.text(const L10n(AppLocale.ru).t('err_back')));
      await t.pumpAndSettle();
      expect(find.text('home screen'), findsOneWidget);
      expect(find.text('middle'), findsNothing);
    });
  });

  testWidgets('the fallback speaks the app language', (t) async {
    await withFallbackBuilder(t, () async {
      for (final locale in AppLocale.values) {
        // A distinct key per locale forces a fresh element: without it the
        // second and third iterations reuse the already-failed subtree, never
        // rebuild, and never throw — the assertion below caught that.
        await t.pumpWidget(_wrap(_Exploding(key: ValueKey(locale)), locale: locale));
        expect(t.takeException(), isA<StateError>());
        expect(
          find.text(L10n(locale).t('err_title')),
          findsOneWidget,
          reason: 'error title should be localized for $locale',
        );
      }
    });
  });

  testWidgets('offers a way out when one is available', (t) async {
    var restarted = false;
    await t.pumpWidget(_wrap(ErrorFallback(onRestart: () => restarted = true)));
    final button = find.text(const L10n(AppLocale.ru).t('err_back'));
    expect(button, findsOneWidget);
    await t.tap(button);
    await t.pump();
    expect(restarted, isTrue);
  });

  testWidgets('shows no action when there is nowhere to go', (t) async {
    // On the FIRST route, popping cannot dispose the broken subtree, so a
    // button offering to would do nothing.
    //
    // This asserted `find.byType(FilledButton), findsNothing` and could not
    // fail: the CTA is a DsPrimaryButton, which is an InkWell on a Material and
    // has never been a FilledButton. It passed with the button on screen. Assert
    // the type that is actually built, AND its label.
    await t.pumpWidget(_wrap(const ErrorFallback()));
    expect(find.byType(DsPrimaryButton), findsNothing);
    expect(find.text(const L10n(AppLocale.ru).t('err_back')), findsNothing);
    // …and the copy does not tell her to press it anyway.
    expect(find.text(const L10n(AppLocale.ru).t('err_body_restart')), findsOneWidget);
    expect(find.text(const L10n(AppLocale.ru).t('err_body')), findsNothing);
  });

  testWidgets('hides technical detail unless it is given', (t) async {
    await t.pumpWidget(_wrap(const ErrorFallback()));
    expect(find.text(const L10n(AppLocale.ru).t('err_details')), findsNothing);

    await t.pumpWidget(_wrap(const ErrorFallback(details: 'StateError: bad state')));
    expect(find.text(const L10n(AppLocale.ru).t('err_details')), findsOneWidget);
  });

  testWidgets('renders without an L10nScope above it', (t) async {
    // The fallback exists because something above it broke, so it must not
    // depend on the scope still being there.
    await t.pumpWidget(const MaterialApp(home: ErrorFallback()));
    expect(find.text(const L10n(AppLocale.ru).t('err_title')), findsOneWidget);
  });

  testWidgets('fits a small screen at large text without overflowing', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: _wrap(const ErrorFallback(details: 'StateError: something went wrong in build')),
    ));
    expect(t.takeException(), isNull);
  });
}

