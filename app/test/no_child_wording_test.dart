/// What the Child tab says before she has added a child.
///
/// `childName` fell back to the English literal 'your child', dropped
/// untranslated into Russian and Kazakh sentences — so the tab greeted a
/// Russian-speaking mother with "Где your child?" and "Ожидание
/// местоположения your child…". That is the DEFAULT state for anyone who has
/// not added a child, which includes every first-time expectant mother: the
/// most likely person to have just installed a pregnancy app.
///
/// verify_ui_strings could not see it. It reads literals where they are
/// written, and this one was built at runtime three files away.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/child_tracker_state.dart';
import 'package:fcs_app/l10n/l10n.dart';

void main() {
  test('no English leaks into the generic name, in any language', () {
    for (final locale in AppLocale.values) {
      final c = AppController(locale: locale);
      addTearDown(c.dispose);
      expect(c.hasNamedChild, isFalse);
      if (locale != AppLocale.en) {
        expect(c.childName, isNot(contains('your')),
            reason: '$locale got an English fallback');
        expect(c.childName, isNot(contains('child')));
      }
    }
  });

  test('the waiting line needs no name at all', () {
    // Rather than declining a substituted noun: Russian wants the genitive
    // here and the nominative in the title, so no single word fits both.
    const status = ChildStatus(
      location: null, updatedAt: null, freshness: Freshness.stale,
      currentZone: null, distanceFromHomeM: null, headline: '',
    );
    final ru = const L10n(AppLocale.ru)
        .trackingHeadline(status, 'ignored', DateTime.utc(2026, 8, 7), named: false);

    expect(ru, 'Ожидание местоположения…');
    expect(ru, isNot(contains('ignored')));
  });

  test('a real name is still used when there is one', () {
    const status = ChildStatus(
      location: null, updatedAt: null, freshness: Freshness.stale,
      currentZone: null, distanceFromHomeM: null, headline: '',
    );
    final ru = const L10n(AppLocale.ru)
        .trackingHeadline(status, 'Сұлтан', DateTime.utc(2026, 8, 7));
    expect(ru, contains('Сұлтан'));
  });
}
