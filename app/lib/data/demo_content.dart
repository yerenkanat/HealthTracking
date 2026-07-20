/// Seeded timeline content — TEST DATA until the real catalogue and endpoints
/// exist. Same shape the backend will serve, so swapping it out is a one-line
/// change at the call site and nothing else moves.
///
/// Coverage is the point: every pregnancy week 1..40 and every child month
/// 0..60 has entries, so the whole timeline can be walked and reviewed now.
/// The wording is real enough to judge layout in all three languages; the URLs
/// are placeholders and are marked as such.
library;

import '../domain/timeline_content.dart';

/// Topic used to give each stage plausible, distinct wording.
class _Topic {
  final String ru, kk, en;
  const _Topic(this.ru, this.kk, this.en);
}

// Pregnancy themes by trimester, so week 8 and week 32 don't read identically.
const _pregnancyTopics = <_Topic>[
  _Topic('первый триместр', 'бірінші триместр', 'the first trimester'),
  _Topic('второй триместр', 'екінші триместр', 'the second trimester'),
  _Topic('третий триместр', 'үшінші триместр', 'the third trimester'),
];

const _pregnancyLesson = <_Topic>[
  _Topic('Питание и самочувствие', 'Тамақтану және көңіл-күй', 'Nutrition and wellbeing'),
  _Topic('Что происходит с малышом', 'Балаға не болып жатыр', "What's happening with your baby"),
  _Topic('Дыхание и отдых', 'Тыныс алу және демалыс', 'Breathing and rest'),
];

const _pregnancyProduct = <_Topic>[
  _Topic('Витамины для беременных', 'Жүкті әйелдерге витаминдер', 'Prenatal vitamins'),
  _Topic('Подушка для беременных', 'Жүктілерге арналған жастық', 'Pregnancy pillow'),
  _Topic('Крем от растяжек', 'Созылу іздеріне қарсы крем', 'Stretch-mark cream'),
];

const _childLesson = <_Topic>[
  _Topic('Сон и режим', 'Ұйқы және режим', 'Sleep and routine'),
  _Topic('Кормление', 'Тамақтандыру', 'Feeding'),
  _Topic('Развитие и игры', 'Даму және ойындар', 'Development and play'),
];

const _childProduct = <_Topic>[
  _Topic('Набор для купания', 'Шомылдыру жинағы', 'Bath set'),
  _Topic('Развивающий коврик', 'Дамытушы кілемше', 'Play mat'),
  _Topic('Бутылочки и соски', 'Бөтелкелер мен емізіктер', 'Bottles and teats'),
];

LocalizedText _t(String ru, String kk, String en) =>
    LocalizedText({'ru': ru, 'kk': kk, 'en': en});

/// Deterministic pick so the same stage always shows the same items — content
/// that shuffled between launches would look broken.
_Topic _pick(List<_Topic> from, int seed) => from[seed % from.length];

List<ContentItem> _pregnancyItems(int week) {
  final tri = week <= 13 ? 0 : (week <= 27 ? 1 : 2);
  final phase = _pregnancyTopics[tri];
  final l1 = _pick(_pregnancyLesson, week);
  final l2 = _pick(_pregnancyLesson, week + 1);
  final p1 = _pick(_pregnancyProduct, week);
  return [
    ContentItem(
      id: 'w$week-l1',
      kind: ContentKind.lesson,
      title: _t('${l1.ru} · $week-я неделя', '${l1.kk} · $week-апта', '${l1.en} · week $week'),
      summary: _t(
        'Урок о том, как проходит ${phase.ru} и что важно на этой неделе.',
        '${phase.kk} қалай өтетіні және осы аптада не маңызды екені туралы сабақ.',
        'A lesson on ${phase.en} and what matters this week.',
      ),
      url: '', // TODO: real video URL when the catalogue is supplied
      durationMin: 6 + (week % 5),
    ),
    ContentItem(
      id: 'w$week-l2',
      kind: ContentKind.lesson,
      title: _t('${l2.ru} · $week-я неделя', '${l2.kk} · $week-апта', '${l2.en} · week $week'),
      summary: _t(
        'Короткий видеоурок для $week-й недели беременности.',
        'Жүктіліктің $week-аптасына арналған қысқа бейнесабақ.',
        'A short video lesson for week $week of pregnancy.',
      ),
      url: '',
      durationMin: 4 + (week % 4),
    ),
    ContentItem(
      id: 'w$week-p1',
      kind: ContentKind.product,
      title: _t(p1.ru, p1.kk, p1.en),
      summary: _t(
        'Подобрано для $week-й недели.',
        '$week-аптаға таңдалған.',
        'Chosen for week $week.',
      ),
      url: '',
      priceMinor: 690000 + (week % 7) * 50000,
      currency: 'KZT',
    ),
  ];
}

List<ContentItem> _childItems(int month) {
  final l1 = _pick(_childLesson, month);
  final l2 = _pick(_childLesson, month + 2);
  final p1 = _pick(_childProduct, month);
  final p2 = _pick(_childProduct, month + 1);
  final ageRu = month == 0 ? 'новорождённого' : '$month мес.';
  final ageKk = month == 0 ? 'жаңа туған нәресте' : '$month ай';
  final ageEn = month == 0 ? 'a newborn' : '$month months';
  return [
    ContentItem(
      id: 'm$month-l1',
      kind: ContentKind.lesson,
      title: _t('${l1.ru} · $ageRu', '${l1.kk} · $ageKk', '${l1.en} · $ageEn'),
      summary: _t(
        'Что важно знать в этом возрасте.',
        'Осы жаста нені білу маңызды.',
        'What matters at this age.',
      ),
      url: '',
      durationMin: 5 + (month % 6),
    ),
    ContentItem(
      id: 'm$month-l2',
      kind: ContentKind.lesson,
      title: _t('${l2.ru} · $ageRu', '${l2.kk} · $ageKk', '${l2.en} · $ageEn'),
      summary: _t(
        'Практический видеоурок для родителей.',
        'Ата-аналарға арналған практикалық бейнесабақ.',
        'A practical video lesson for parents.',
      ),
      url: '',
      durationMin: 7 + (month % 3),
    ),
    ContentItem(
      id: 'm$month-p1',
      kind: ContentKind.product,
      title: _t(p1.ru, p1.kk, p1.en),
      summary: _t('Подходит для возраста $ageRu.', '$ageKk жасына сәйкес келеді.',
          'Suits $ageEn.'),
      url: '',
      priceMinor: 450000 + (month % 9) * 40000,
      currency: 'KZT',
    ),
    ContentItem(
      id: 'm$month-p2',
      kind: ContentKind.product,
      title: _t(p2.ru, p2.kk, p2.en),
      summary: _t('Часто покупают в этом возрасте.', 'Осы жаста жиі сатып алады.',
          'Often bought at this age.'),
      url: '',
      priceMinor: 320000 + (month % 5) * 35000,
      currency: 'KZT',
    ),
  ];
}

/// A catalogue covering the entire timeline. Replace with backend data by
/// passing a different [ContentCatalog] — nothing else needs to change.
ContentCatalog demoContentCatalog() => ContentCatalog({
      for (var w = minPregnancyWeek; w <= maxPregnancyWeek; w++) 'w$w': _pregnancyItems(w),
      for (var m = minChildMonth; m <= maxChildMonth; m++) 'm$m': _childItems(m),
    });
