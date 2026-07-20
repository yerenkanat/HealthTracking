/// What survives the wire from the AI guardrail.
///
/// The server escalates in two different ways and they need different handling:
/// a TEXT red flag is written by the guardrail in the user's own language, while
/// a TELEMETRY emergency carries a message from the shared triage rules, which
/// are English. The triage code was already being sent and simply dropped here,
/// so the second kind reached a Russian user as English prose the app had no way
/// to translate.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/l10n/l10n.dart';

void main() {
  const ru = L10n(AppLocale.ru);

  ChatOutcome parse(Map<String, dynamic> j) => ChatOutcome.fromJson(j);

  test('a telemetry emergency keeps its triage code so the app can localize', () {
    final o = parse({
      'kind': 'emergency',
      'message': 'High blood pressure detected — a warning sign of preeclampsia.',
      'triage': {
        'findings': [
          {'code': 'PREECLAMPSIA_BP', 'severity': 'emergency'},
        ],
      },
      'callButtons': [
        {'label': 'Call ambulance', 'tel': '103'},
      ],
    });
    expect(o, isA<EmergencyChatOutcome>());
    final e = o as EmergencyChatOutcome;
    expect(e.code, 'PREECLAMPSIA_BP');
    // With the code, the Russian user gets Russian rather than the English the
    // server sent.
    expect(ru.triageMessage(e.code), isNot(e.message));
    expect(ru.triageMessage(e.code), matches(RegExp(r'[А-Яа-я]')));
  });

  test('a text red flag has no code, and its message is already localized', () {
    final e = parse({
      'kind': 'emergency',
      'message': 'То, что вы описываете, может быть серьёзным.',
      'triage': {
        'findings': [
          {'code': 'SYMPTOM_RED_FLAG', 'severity': 'emergency'},
        ],
      },
      'callButtons': const [],
    }) as EmergencyChatOutcome;
    // The code comes through, but SYMPTOM_RED_FLAG has no catalogue entry, so
    // triageMessage falls back rather than showing a raw code.
    expect(e.code, 'SYMPTOM_RED_FLAG');
    expect(ru.triageMessage(e.code), isNot(contains('SYMPTOM_RED_FLAG')));
  });

  group('a shape change upstream must not throw on the emergency path', () {
    final malformed = <String, Map<String, dynamic>>{
      'no triage at all': {},
      'triage is not a map': {'triage': 'nope'},
      'no findings': {'triage': <String, dynamic>{}},
      'findings not a list': {'triage': {'findings': 'nope'}},
      'findings empty': {'triage': {'findings': []}},
      'finding not a map': {'triage': {'findings': ['nope']}},
      'no code on the finding': {'triage': {'findings': [<String, dynamic>{}]}},
      'code is empty': {'triage': {'findings': [{'code': ''}]}},
      'code is not a string': {'triage': {'findings': [{'code': 42}]}},
    };

    for (final entry in malformed.entries) {
      test('${entry.key} → degrades to the server message', () {
        final e = parse({
          'kind': 'emergency',
          'message': 'Seek help now.',
          'callButtons': const [],
          ...entry.value,
        }) as EmergencyChatOutcome;
        expect(e.code, isNull);
        expect(e.message, 'Seek help now.');
      });
    }
  });
}
