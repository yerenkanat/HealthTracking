/// The language she picked survives an interrupted signup.
///
/// Found by running the app, not by a test: select «Қазақша» on step 2, get as
/// far as step 4, background the app, come back — and the whole of onboarding is
/// in Russian again. No test saw it because no test relaunches a half-finished
/// onboarding, and the mechanism was one line:
///
///     final cfg = await _persistStore?.load();
///     if (cfg == null || !cfg.onboarded) return;   // ← the language died here
///
/// `setLocale` persisted her choice correctly. `restore()` then discarded the
/// whole config because she had not finished, and the language went with it.
///
/// A language is a device preference, not onboarding data. It is the one field
/// that is true about her before she has told us anything else, and the only one
/// whose loss makes the app unreadable rather than merely empty — a Kazakh
/// speaker is handed a Russian app after one phone call.
///
/// The narrowness is deliberate and is asserted below: the profile still
/// requires a completed onboarding. Resuming a partial signup is a design
/// question about what she is shown when she returns, and this is not that
/// change.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/app_store.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

void main() {
  test('a language chosen before onboarding finished is still there on return', () async {
    final store = InMemoryAppStore();

    // Session one: she reaches the language step and picks Kazakh, then never
    // finishes. `onboarded` stays false.
    final first = AppController(persistStore: store);
    addTearDown(first.dispose);
    first.setLocale(AppLocale.kk);
    first.flushPendingSave();
    await Future<void>.delayed(Duration.zero);

    final saved = await store.load();
    expect(saved, isNotNull, reason: 'setLocale did not persist at all');
    expect(saved!.onboarded, isFalse,
        reason: 'the fixture must model an UNFINISHED onboarding, or this test '
            'is about the ordinary restore path and proves nothing');

    // Session two: she reopens the app.
    final second = AppController(persistStore: store);
    addTearDown(second.dispose);
    await second.restore();

    expect(second.locale, AppLocale.kk,
        reason: 'she is reading a Russian app after choosing Kazakh');
  });

  test('and the profile is NOT restored from an unfinished onboarding', () async {
    // The blast radius. This fix is one field wide on purpose: resuming a
    // partial signup is a different decision, and quietly restoring a name
    // would make this change something nobody reviewed.
    final store = InMemoryAppStore();
    final first = AppController(persistStore: store);
    addTearDown(first.dispose);
    first.setLocale(AppLocale.kk);
    first.updateProfile(const UserProfile(displayName: 'Aigerim'));
    first.flushPendingSave();
    await Future<void>.delayed(Duration.zero);
    expect((await store.load())!.onboarded, isFalse);

    final second = AppController(persistStore: store);
    addTearDown(second.dispose);
    await second.restore();

    expect(second.locale, AppLocale.kk);
    expect(second.profile.displayName, isNot('Aigerim'),
        reason: 'the name came back from an unfinished onboarding — a wider '
            'change than the one this file guards');
  });

  test('a completed onboarding still restores everything', () async {
    // The regression guard: the narrow early-return must not swallow the
    // ordinary path, which is the only one that existed before.
    final store = InMemoryAppStore();
    final first = AppController(persistStore: store);
    addTearDown(first.dispose);
    first.setLocale(AppLocale.kk);
    first.updateProfile(const UserProfile(displayName: 'Aigerim'));
    first.debugMarkOnboarded();
    first.flushPendingSave();
    await Future<void>.delayed(Duration.zero);
    expect((await store.load())!.onboarded, isTrue);

    final second = AppController(persistStore: store);
    addTearDown(second.dispose);
    await second.restore();

    expect(second.locale, AppLocale.kk);
    expect(second.profile.displayName, 'Aigerim');
  });
}
