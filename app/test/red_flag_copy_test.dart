/// Advice that names a red-flag symptom must also say who to call.
///
/// The defect this locks out: `ADV_TEMP_ELEVATED_b` fired at
/// `TriageThresholds.feverWarningC` (37.8 °C) and answered «Отдых и питьё;
/// следите за динамикой», while the app's own pregnancy warning-signs list
/// (`preg_warn_fever`, under «Свяжитесь с консультацией или скорой») names a
/// high temperature as a reason to call. Same app, same woman, opposite
/// instruction — and the reassuring one was the one attached to her reading.
/// `pp_note_lochia_fading` did the same for bright-red bleeding returning,
/// which is secondary postpartum haemorrhage until proven otherwise.
///
/// So: any advisor body (`ADV_*_b`) or recovery note (`pp_note_*`) whose text
/// names one of the symptoms the app itself lists as a red flag must carry a
/// seek-help clause, in all three languages. The next such string cannot be
/// written without one.
///
/// Scope note: this checks the copy, not the trigger. It cannot know that a
/// card *should* have mentioned a red flag — only that one that does mention
/// it does not stop at "rest and watch".
///
/// Keys are read from source (the catalogue is private, and enumerating it is
/// the point); the text itself is read through `L10n.t` so the assertion runs
/// against exactly what a screen renders.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';

/// Keys under review: advisory bodies and postpartum recovery notes.
final _key = RegExp(r"^\s*'(ADV_[A-Z0-9_]+_b|pp_note_[a-z0-9_]+)'\s*:", multiLine: true);

/// Symptoms the app's own warning lists (`preg_warn_*`, `pp_warn_*`) say to
/// call about. Each pattern names the *abnormal* direction — "температура
/// ровная" is not a red flag, "температура повышена" is.
///
/// `\p{L}`, never `\w`: Dart's `\w` is ASCII-only, so `температур\w*` matches
/// nothing in the language most of these users read. A first draft of this file
/// used `\w` and passed with the defective Russian copy still in place — the
/// guard was live and blind at the same time. Every pattern here is compiled
/// with `unicode: true`. `\b` is out for the same reason.
const _redFlags = <AppLocale, Map<String, String>>{
  AppLocale.ru: {
    'raised temperature': r'температур\p{L}* (повышен|выше нормы)|повышенн\p{L}+ температур|высок\p{L}+ температур|озноб',
    'bleeding': r'кровотечен|ярко-красн|крупн\p{L}+ сгустк|обильн\p{L}+ кров',
    'raised blood pressure': r'давление повышено|повышенн\p{L}+ давлени|высок\p{L}+ давлени',
    'oxygen dip': r'кислород\p{L}* (опускал|ниже|низк)',
    'blood sugar out of range': r'сахар в крови (повышен|низкий)|низкий сахар|высокий сахар',
    'headache or vision change': r'сильн\p{L}+ головн\p{L}+ бол|нарушени\p{L}+ зрения',
    'reduced fetal movement': r'шевел\p{L}* (стало )?меньше|меньше шевел',
  },
  AppLocale.kk: {
    'raised temperature': r'қызу\p{L}* жоғар|жоғары температура|температура қалыптыдан жоғары|қалтырау',
    'bleeding': r'қан кету|ашық қызыл|ірі ұйынды|мол бөлініс',
    'raised blood pressure': r'қысым жоғар|жоғары қысым',
    'oxygen dip': r'оттегі[^.]*төмен',
    'blood sugar out of range': r'қант жоғары|қант төмен',
    'headache or vision change': r'қатты бас ауыруы|көру бұзылыс',
    'reduced fetal movement': r'аз қимылда',
  },
  AppLocale.en: {
    'raised temperature': r'temperature is (elevated|above normal|high)|high temperature|fever|chills',
    'bleeding': r'bright red|heavy bleeding|bleeding is heavy|large clots|soaks a pad',
    'raised blood pressure': r'blood pressure is elevated|high blood pressure|pressure is high',
    'oxygen dip': r'oxygen (dipped|dropped|is low)|oxygen[^.]*below',
    'blood sugar out of range': r'blood sugar looks (high|low)|high blood sugar|low blood sugar',
    'headache or vision change': r'severe headache|vision changes',
    'reduced fetal movement': r'moving (noticeably )?less',
  },
};

/// "Tell someone who can act." A doctor, the antenatal clinic, the polyclinic,
/// a midwife, or the ambulance — the vocabulary the warning lists already use.
const _seekHelp = <AppLocale, String>{
  AppLocale.ru: r'врач|скор(ая|ую|ой|ой помощ)|консультаци|поликлиник|103|112',
  AppLocale.kk: r'дәрігер|жедел жәрдем|емхана|консультация|103|112',
  AppLocale.en: r'doctor|clinic|midwife|emergency|nurse|103|112',
};

/// Notes whose whole job is to say a frightening-looking sign is the normal
/// phase — heavy bright-red lochia in the first days is expected, and telling
/// her to call about it would send every woman to the clinic in week one.
/// `postpartum_screen.dart` renders the permanent `pp_warn_*` panel (soaking a
/// pad an hour, large clots) below these notes on the same screen, so the
/// boundary is never absent from view.
///
/// An exemption is not enough on its own: the text must also say, in that
/// language, that the sign is normal. A rewrite that drops the reassurance and
/// keeps the exemption fails.
const _saysThisIsNormal = <String>{'pp_note_lochia_early'};

const _normality = <AppLocale, String>{
  AppLocale.ru: r'это нормально|это норма|нормальн',
  AppLocale.kk: r'бұл қалыпты|қалыпты',
  AppLocale.en: r'is normal|are normal',
};

RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false, unicode: true);

void main() {
  final source = File('lib/l10n/l10n.dart').readAsStringSync().replaceAll('\r\n', '\n');
  final keys = _key.allMatches(source).map((m) => m.group(1)!).toSet().toList()..sort();

  test('the patterns can see Cyrillic at all', () {
    // The failure that nearly shipped this guard useless: ASCII `\w`. Assert on
    // known text so a pattern that matches only English cannot pass quietly.
    expect(_re(_redFlags[AppLocale.ru]!['raised temperature']!).hasMatch('Температура повышена.'), isTrue);
    expect(_re(_redFlags[AppLocale.ru]!['raised temperature']!).hasMatch('Температура выше нормы.'), isTrue);
    expect(_re(_redFlags[AppLocale.ru]!['raised temperature']!).hasMatch('Температура по браслету держится ровно.'), isFalse);
    expect(_re(_redFlags[AppLocale.ru]!['bleeding']!).hasMatch('возврат ярко-красной крови'), isTrue);
    expect(_re(_redFlags[AppLocale.kk]!['raised temperature']!).hasMatch('Дене қызуы жоғарылаған.'), isTrue);
    expect(_re(_redFlags[AppLocale.kk]!['raised temperature']!).hasMatch('Дене қызуы біркелкі.'), isFalse);
    expect(_re(_seekHelp[AppLocale.ru]!).hasMatch('обратитесь к врачу'), isTrue);
    expect(_re(_seekHelp[AppLocale.kk]!).hasMatch('дәрігерге жүгініңіз'), isTrue);
    expect(_re(_seekHelp[AppLocale.ru]!).hasMatch('следите за динамикой'), isFalse);
  });

  test('the key scan actually found the advice strings', () {
    // A scan that matches nothing passes every assertion below, which is the
    // most comfortable way to ship "rest and watch" over a red flag again.
    final advisories = keys.where((k) => k.startsWith('ADV_')).length;
    final notes = keys.where((k) => k.startsWith('pp_note_')).length;
    expect(advisories, greaterThanOrEqualTo(19),
        reason: 'found $advisories ADV_*_b keys — the regex has stopped matching');
    expect(notes, greaterThanOrEqualTo(10),
        reason: 'found $notes pp_note_* keys — the regex has stopped matching');
  });

  test('every red-flag symptom named in advice also says who to call', () {
    final offenders = <String>[];

    for (final locale in AppLocale.values) {
      final l = L10n(locale);
      final flags = _redFlags[locale]!;
      final seekHelp = _re(_seekHelp[locale]!);

      for (final key in keys) {
        final text = l.t(key);
        final named = [
          for (final e in flags.entries)
            if (_re(e.value).hasMatch(text)) e.key,
        ];
        if (named.isEmpty) continue;
        if (seekHelp.hasMatch(text)) continue;
        if (_saysThisIsNormal.contains(key) &&
            _re(_normality[locale]!).hasMatch(text)) {
          continue;
        }
        offenders.add('$key [${locale.name}] names ${named.join(', ')} '
            'but never says who to call:\n    $text');
      }
    }

    expect(offenders, isEmpty,
        reason: 'advice that names a symptom the app tells her to call about, '
            'and then tells her to sit with it:\n${offenders.join('\n')}');
  });

  test('the two strings this test was written for say it in all three languages', () {
    // Named explicitly so a future rewrite that drops the clause fails with the
    // history attached, not just as one row in a list.
    for (final locale in AppLocale.values) {
      final seekHelp = _re(_seekHelp[locale]!);
      for (final key in const ['ADV_TEMP_ELEVATED_b', 'pp_note_lochia_fading']) {
        expect(seekHelp.hasMatch(L10n(locale).t(key)), isTrue,
            reason: '$key (${locale.name}) lost its seek-help clause');
      }
    }
  });
}
