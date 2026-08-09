/// Screen 43 — «Поддержка».
///
/// The message this composes gets pasted into a group chat, forwarded to a
/// colleague and read on a shared phone. So the test that matters most is the
/// one asserting what it does NOT carry.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/support_context.dart';

const ctx = SupportContext(
  appVersion: '0.1.0',
  phone: '+7 707 345 22 44',
  deviceId: 'TAG-0042',
  offline: true,
  lastError: 'SocketException: failed host lookup\n  at line 2\n  at line 3',
);

void main() {
  test('carries what the operator would otherwise have to ask for', () {
    final m = ctx.message('Браслет ребёнка');
    expect(m, contains('Браслет ребёнка'));
    expect(m, contains('0.1.0'));
    expect(m, contains('TAG-0042'));
    expect(m, contains('нет интернета'));
  });

  test('carries NOTHING about her health or her children', () {
    // A support message is not a place for a medical record.
    final m = ctx.message('Браслет ребёнка').toLowerCase();
    for (final forbidden in [
      'давлен', 'пульс', 'цикл', 'беремен', 'дневник',
    ]) {
      expect(m.contains(forbidden), isFalse, reason: 'leaked: $forbidden');
    }
  });

  test('truncates a stack trace to its first line', () {
    // A stack trace in a WhatsApp message is unreadable, and the first line is
    // the only part anyone acts on.
    final m = ctx.message('');
    expect(m, contains('SocketException'));
    expect(m, isNot(contains('at line 2')));
  });

  test('still says something useful with an empty complaint', () {
    expect(ctx.message('   '), contains('Здравствуйте'));
  });

  test('omits what it does not know', () {
    const bare = SupportContext(appVersion: '0.1.0');
    final m = bare.message('Вопрос');
    expect(m, contains('0.1.0'));
    expect(m, isNot(contains('Устройство')));
    expect(m, isNot(contains('Телефон')));
    expect(m, isNot(contains('нет интернета')));
  });
}
