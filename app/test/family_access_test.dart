/// Screen 40 — «Семейный доступ».
///
/// The assertions that matter are about the green banner and about the link
/// being shown once: the first is a promise the screen must stop making if it
/// stops being true, and the second is the only chance the mother gets to copy
/// something the server cannot give back.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/family_access.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/profile/family_access_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);
final now = DateTime(2026, 8, 8, 12);

FamilyAccess access({
  List<FamilyMember>? members,
  List<FamilyInvite>? invites,
  List<FamilyMembership>? memberships,
  List<String>? shareable,
}) =>
    FamilyAccess(
      members: members ?? const [],
      invites: invites ?? const [],
      memberships: memberships ?? const [],
      shareable: shareable ??
          const ['child_location', 'child_zones', 'child_alerts', 'child_device'],
    );

final father = FamilyMember(
  memberUserId: 'f1',
  label: 'Папа',
  displayName: 'Ерлан',
  level: AccessLevel.viewer,
  since: now,
);

final openInvite = FamilyInvite(
  tokenHash: 'h1',
  level: AccessLevel.guardian,
  label: 'Бабушка',
  expiresAt: now.add(const Duration(hours: 20)),
);

Future<({List<String> removed, List<String> revoked, List<String> invited})> pump(
  WidgetTester tester, {
  FamilyAccess? data,
  bool fail = false,
  String? token = 'TOKEN-123',
  bool removeWorks = true,
  bool revokeWorks = true,
}) async {
  final removed = <String>[];
  final revoked = <String>[];
  final invited = <String>[];
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp, as lib/app/app.dart builds it. A modal sheet
  // lives in the Navigator's overlay, so a scope placed at `home:` is BELOW it
  // and the sheet falls through to the English default — which is how the
  // first version of this test found the invite sheet rendering in English on
  // a Russian screen, and it was the harness that was wrong, not the app.
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: FamilyAccessScreen(
        now: now,
        load: () async {
          if (fail) throw Exception('offline');
          return data ?? access();
        },
        onInvite: (level, label) async {
          invited.add('${level.wire}|$label');
          return token;
        },
        onRemove: (m) async {
          removed.add(m.memberUserId);
          return removeWorks;
        },
        onRevoke: (i) async {
          revoked.add(i.tokenHash);
          return revokeWorks;
        },
        linkFor: (t) => 'https://ana-bala.kz/join/$t',
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (removed: removed, revoked: revoked, invited: invited);
}

void main() {
  group('the model', () {
    test('drops a level this build does not know', () {
      // A server newer than the app. Guessing at what somebody can see is the
      // one thing this screen must not do.
      final a = FamilyAccess.fromJson({
        'members': [
          {'memberUserId': 'x', 'level': 'superuser', 'label': 'X'},
          {'memberUserId': 'y', 'level': 'viewer', 'label': 'Y'},
        ],
      });
      expect(a.members, hasLength(1));
      expect(a.members.single.memberUserId, 'y');
    });

    test('her label wins over their profile name', () {
      // She wrote «Папа». It is more use to her at a glance than «Ерлан Ж.».
      expect(father.title, 'Папа');
      expect(
        const FamilyMember(
          memberUserId: 'z', label: '  ', displayName: 'Ерлан',
          level: AccessLevel.viewer,
        ).title,
        'Ерлан',
      );
    });

    test('the banner condition is about the server\'s list, not a sentence', () {
      expect(access().sharesOnlyChildData, isTrue);
      // If the server ever said it would share something of hers, this is
      // false and the banner comes off the screen.
      expect(
        access(shareable: ['child_location', 'maternal_health']).sharesOnlyChildData,
        isFalse,
      );
      // An empty list is not a promise either — it means we do not know.
      expect(access(shareable: []).sharesOnlyChildData, isFalse);
    });

    test('counts the hours left, and never below zero', () {
      expect(openInvite.hoursLeft(now), 20);
      expect(
        FamilyInvite(
          tokenHash: 'h', level: AccessLevel.viewer, label: '',
          expiresAt: now.subtract(const Duration(hours: 5)),
        ).hoursLeft(now),
        0,
      );
    });

    test('each refusal has its own words', () {
      final keys = ['expired', 'already_used', 'revoked', 'own_invite', null]
          .map(inviteRefusalKey)
          .toSet();
      expect(keys, hasLength(5));
    });
  });

  testWidgets('shows the green banner when nothing of hers is shared',
      (tester) async {
    await pump(tester);
    expect(find.text(l.t('fam_privacy')), findsOneWidget);
    expect(find.text(l.t('fam_privacy_body')), findsOneWidget);
  });

  testWidgets('takes the banner down if the server starts sharing her data',
      (tester) async {
    // The promise must stop being made the moment it stops being true. A
    // hard-coded banner would keep making it.
    await pump(tester, data: access(shareable: ['child_location', 'maternal_health']));
    expect(find.text(l.t('fam_privacy')), findsNothing);
  });

  testWidgets('with nobody invited it says what an invitation would do',
      (tester) async {
    await pump(tester);
    expect(find.text(l.t('fam_nobody')), findsOneWidget);
    expect(find.text(l.t('fam_nobody_why')), findsOneWidget);
  });

  testWidgets('lists a relative with the level in words', (tester) async {
    await pump(tester, data: access(members: [father]));
    expect(find.text('Папа'), findsOneWidget);
    // «Только смотрит», not «viewer».
    expect(find.text(l.t('fam_level_viewer')), findsOneWidget);
  });

  group('the link', () {
    testWidgets('is shown once, with the warning that it cannot be shown again',
        (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.text(l.t('fam_invite')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('fam_level_guardian')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l.t('fam_invite')));
      await tester.pumpAndSettle();

      expect(calls.invited, ['guardian|']);
      expect(find.text('https://ana-bala.kz/join/TOKEN-123'), findsOneWidget);
      expect(find.text(l.t('fam_invite_once', {'n': 24})), findsOneWidget);
    });

    testWidgets('copies to the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(call.arguments['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pump(tester);
      await tester.tap(find.text(l.t('fam_invite')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l.t('fam_invite')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('fam_copy')));
      await tester.pumpAndSettle();

      expect(copied, ['https://ana-bala.kz/join/TOKEN-123']);
      expect(find.text(l.t('fam_copied')), findsOneWidget);
    });

    testWidgets('says so when the link could not be made', (tester) async {
      // Silence here leaves her waiting for a link that was never created.
      await pump(tester, token: null);
      await tester.tap(find.text(l.t('fam_invite')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l.t('fam_invite')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('fam_invite_failed')), findsOneWidget);
    });

    testWidgets('shows an open invitation with its countdown', (tester) async {
      await pump(tester, data: access(invites: [openInvite]));
      expect(find.text('Бабушка'), findsOneWidget);
      expect(find.text(l.t('fam_expires_in', {'n': 20})), findsOneWidget);
    });
  });

  group('taking access away', () {
    testWidgets('asks first', (tester) async {
      // docs/UI_REVIEW_CHECKLIST: every destructive action confirms.
      final calls = await pump(tester, data: access(members: [father]));
      await tester.tap(find.text(l.t('fam_remove')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('fam_remove_confirm', {'name': 'Папа'})), findsOneWidget);
      expect(calls.removed, isEmpty);
    });

    testWidgets('cancelling removes nothing', (tester) async {
      // The test above only proves the dialog APPEARS — with the `if (!ok)`
      // guard deleted it still passes, because the handler is suspended on the
      // dialog when the assertion runs. This is the one that catches a
      // confirmation that is shown and then ignored.
      final calls = await pump(tester, data: access(members: [father]));
      await tester.tap(find.text(l.t('fam_remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('act_cancel')));
      await tester.pumpAndSettle();
      expect(calls.removed, isEmpty);
      expect(find.text(l.t('fam_removed')), findsNothing);
      // Still on the list.
      expect(find.text('Папа'), findsOneWidget);
    });

    testWidgets('removes only after she confirms', (tester) async {
      final calls = await pump(tester, data: access(members: [father]));
      await tester.tap(find.text(l.t('fam_remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l.t('fam_remove')).last);
      await tester.pumpAndSettle();
      expect(calls.removed, ['f1']);
      expect(find.text(l.t('fam_removed')), findsOneWidget);
    });

    testWidgets('says so when the removal failed', (tester) async {
      // A cheerful «Доступ убран» over a request that failed leaves her
      // believing somebody has been shut out who has not.
      await pump(tester, data: access(members: [father]), removeWorks: false);
      await tester.tap(find.text(l.t('fam_remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l.t('fam_remove')).last);
      await tester.pumpAndSettle();
      expect(find.text(l.t('fam_failed')), findsOneWidget);
      expect(find.text(l.t('fam_removed')), findsNothing);
    });

    testWidgets('revoking a link confirms too', (tester) async {
      final calls = await pump(tester, data: access(invites: [openInvite]));
      await tester.tap(find.text(l.t('fam_revoke')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('fam_revoke_confirm')), findsOneWidget);
      expect(calls.revoked, isEmpty);
    });
  });

  testWidgets('a failed load says so instead of showing an empty family',
      (tester) async {
    // «Пока никого нет» over a request that failed reads as "nobody has
    // access", which is exactly the wrong thing to believe.
    await pump(tester, fail: true);
    expect(find.text(l.t('fam_failed')), findsOneWidget);
    expect(find.text(l.t('fam_nobody')), findsNothing);
    // And no invite button over a screen that could not load.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('tells the father whose children he can see', (tester) async {
    await pump(tester, data: access(memberships: [
      const FamilyMembership(ownerUserId: 'm1', level: AccessLevel.viewer),
    ]));
    expect(find.text(l.t('fam_i_see')), findsOneWidget);
  });
}
