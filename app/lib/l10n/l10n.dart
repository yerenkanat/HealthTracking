/// Localization core — PURE Dart (no Flutter import) so the catalog + lookups are
/// unit-testable. Russian is the default on install; Kazakh and English are also
/// supported. The Flutter glue (InheritedWidget + delegate) lives in l10n_scope.dart.
///
/// Safety note: medical triage returns CODES, never baked-in language. This layer
/// maps a code → localized message. English strings are kept identical to the
/// original literals so existing widget tests stay valid under the English locale.
///
/// ⚠ Translation review: Russian/Kazakh medical strings need a native + clinical
/// review before production (tracked in STATUS.md risks).
library;

import '../domain/child_tracker_state.dart';
import '../domain/sleep.dart';

enum AppLocale { ru, kk, en }

AppLocale? appLocaleFromCode(String? code) {
  switch (code) {
    case 'ru':
      return AppLocale.ru;
    case 'kk':
      return AppLocale.kk;
    case 'en':
      return AppLocale.en;
    default:
      return null;
  }
}

/// Default on install is RUSSIAN, regardless of device locale, per product spec.
/// A previously saved preference wins if present.
AppLocale resolveInitialLocale(String? savedPref) =>
    appLocaleFromCode(savedPref) ?? AppLocale.ru;

/// key → { locale → string }. Missing (locale) falls back to en, then to the key.
const Map<String, Map<AppLocale, String>> _catalog = {
  // Navigation
  // The first tab. docs/CLAUDE-app-design.md names the four: «Сегодня ·
  // Календарь · Ребёнок · Профиль». It was «Здоровье», which describes the
  // data the screen holds rather than what a woman opens the app for — she
  // opens it to find out what today needs, and the screen already answers that.
  'nav_today': {AppLocale.ru: 'Сегодня', AppLocale.kk: 'Бүгін', AppLocale.en: 'Today'},
  'nav_assistant': {AppLocale.ru: 'Помощник', AppLocale.kk: 'Көмекші', AppLocale.en: 'Assistant'},
  'nav_child': {AppLocale.ru: 'Ребёнок', AppLocale.kk: 'Бала', AppLocale.en: 'Child'},
  'nav_profile': {AppLocale.ru: 'Профиль', AppLocale.kk: 'Профиль', AppLocale.en: 'Profile'},

  // Assistant chat
  'chat_title': {AppLocale.ru: 'Ana-Bala — помощник', AppLocale.kk: 'Ana-Bala — көмекші', AppLocale.en: 'Ana-Bala — assistant'},
  'chat_hint': {AppLocale.ru: 'Спросите о самочувствии…', AppLocale.kk: 'Хал-жағдайыңызды сұраңыз…', AppLocale.en: 'Ask about how you feel…'},
  'link_open_failed': {
    AppLocale.ru: 'Не удалось открыть ссылку',
    AppLocale.kk: 'Сілтемені ашу мүмкін болмады',
    AppLocale.en: 'Could not open the link'
  },
  'chat_retry': {
    AppLocale.ru: 'Отправить ещё раз',
    AppLocale.kk: 'Қайта жіберу',
    AppLocale.en: 'Send again'
  },
  'chat_empty_title': {AppLocale.ru: 'Чем могу помочь?', AppLocale.kk: 'Немен көмектесе аламын?', AppLocale.en: 'How can I help?'},
  'chat_empty_body': {
    AppLocale.ru: 'Задайте вопрос о беременности, самочувствии, сне или питании. Я не заменяю врача.',
    AppLocale.kk: 'Жүктілік, хал-жағдай, ұйқы немесе тамақтану туралы сұрақ қойыңыз. Мен дәрігердің орнын баса алмаймын.',
    AppLocale.en: "Ask about pregnancy, how you feel, sleep, or nutrition. I don't replace your doctor."
  },
  'chat_disclaimer': {AppLocale.ru: 'Общие советы, не медицинский диагноз.', AppLocale.kk: 'Жалпы кеңес, медициналық диагноз емес.', AppLocale.en: 'General guidance, not a medical diagnosis.'},
  'chat_error': {
    AppLocale.ru: 'Не удалось связаться с помощником. Если это о вашем самочувствии, обратитесь к врачу.',
    AppLocale.kk: 'Көмекшіге қосыла алмадық. Егер бұл сіздің хал-жағдайыңызға қатысты болса, дәрігерге жүгініңіз.',
    AppLocale.en: "Couldn't reach the assistant. If this is about how you feel, contact your clinician."
  },
  'chat_emergency_note': {AppLocale.ru: 'Открываю экран экстренной помощи.', AppLocale.kk: 'Шұғыл көмек экранын ашып жатырмын.', AppLocale.en: 'Opening the emergency screen.'},
  'chat_send': {AppLocale.ru: 'Отправить', AppLocale.kk: 'Жіберу', AppLocale.en: 'Send'},

  // Health advisor (data-driven advice from band telemetry)
  'nav_advisor': {AppLocale.ru: 'Советник', AppLocale.kk: 'Кеңесші', AppLocale.en: 'Advisor'},
  'adv_title': {AppLocale.ru: 'Советник здоровья', AppLocale.kk: 'Денсаулық кеңесшісі', AppLocale.en: 'Health advisor'},
  'adv_intro': {AppLocale.ru: 'На основе данных вашего браслета', AppLocale.kk: 'Білезік деректері негізінде', AppLocale.en: 'Based on your band data'},
  'adv_ask_sub': {AppLocale.ru: 'Задайте вопрос ассистенту Ana-Bala', AppLocale.kk: 'Ana-Bala ассистентіне сұрақ қойыңыз', AppLocale.en: 'Ask the Ana-Bala assistant a question'},
  'ADV_GATHERING': {AppLocale.ru: 'Собираем данные', AppLocale.kk: 'Деректер жиналуда', AppLocale.en: 'Gathering data'},
  'ADV_GATHERING_b': {AppLocale.ru: 'Наденьте браслет — советы появятся после нескольких измерений.', AppLocale.kk: 'Білезікті тағыңыз — бірнеше өлшеуден кейін кеңестер пайда болады.', AppLocale.en: 'Wear your band — advice appears after a few readings.'},
  // The absorber. `ADV_ALL_STEADY` / «Всё стабильно» was deleted rather than
  // reworded, together with db_peace_stable*, so that no call site can keep
  // rendering an approved-looking old sentence: a NEW key makes a missed call
  // site fail visibly. Approved copy, 2026-08-14 — do not rewrite, and in
  // particular do not trim the third sentence. It is the clinically
  // load-bearing one: it stops the reassurance outranking her own symptoms,
  // which is the specific harm a green banner does to a woman who feels wrong
  // and decides not to call. No instrument is named because this card is
  // reachable from typed readings too. See docs/CLINICAL-REVIEW-WATCH.md,
  // refused sentence #21 and "The absorber rule".
  'ADV_NOTHING_UNUSUAL': {AppLocale.ru: 'Ничего необычного в показаниях', AppLocale.kk: 'Көрсеткіштерде ерекше ештеңе жоқ', AppLocale.en: 'Nothing unusual in the readings'},
  'ADV_NOTHING_UNUSUAL_b': {AppLocale.ru: 'В этих показаниях нет ничего необычного. Это не проверка здоровья: приложение видит только то, что измерено, а часть чисел — приблизительные оценки с датчика. Если вы плохо себя чувствуете, скажите об этом врачу, что бы ни показывали цифры.', AppLocale.kk: 'Бұл көрсеткіштерде ерекше ештеңе жоқ. Бұл — денсаулықты тексеру емес: қолданба тек өлшенгенді ғана көреді, ал кейбір сандар — датчиктің шамалас болжамы. Өзіңізді нашар сезінсеңіз, сандар не көрсетсе де, дәрігерге айтыңыз.', AppLocale.en: 'There is nothing unusual in these readings. This is not a health check: the app sees only what was measured, and some of the numbers are rough sensor estimates. If you feel unwell, tell your doctor, whatever the numbers show.'},
  'ADV_BP_STEADY': {AppLocale.ru: 'Давление ровное', AppLocale.kk: 'Қысым біркелкі', AppLocale.en: 'Blood pressure steady'},
  'ADV_BP_STEADY_b': {AppLocale.ru: 'Давление по браслету держится ровно, без скачков.', AppLocale.kk: 'Білезік бойынша қысым секірмей, біркелкі.', AppLocale.en: 'Your blood-pressure readings have held steady, without spikes.'},
  // ---- The raised blood-pressure cards, one per instrument ------------------
  // Approved copy, 2026-08-14. Do not rewrite: a rewrite voids the approval.
  //
  // The title is UNCHANGED and the body is replaced entirely. What went, and
  // why (docs/CLINICAL-REVIEW-WATCH.md, refused sentences #17 and #18):
  //   * «Давление повышено» asserted the reading as fact;
  //   * «выпейте воды» is not a treatment for hypertension and no cited source
  //     offers it — beside «при стойком повышении» it produced wait-and-see on
  //     the one condition this product exists to catch;
  //   * «измерьте снова» never named an instrument.
  //
  // 140/90 MAY be stated here and only here: it is attributed to ACOG in
  // packages/shared/src/triage.ts, pinned in packages/contract/
  // triage_thresholds.json, and it is the threshold the product acts on, so it
  // gives her a checkable rule instead of an adjective. Numeric permission
  // follows the SOURCE, not the metric — the device card below may not carry
  // it. 135 and 85 may never appear in any locale of either card: they fire the
  // card and appear in no cited source.
  'ADV_BP_ELEVATED': {AppLocale.ru: 'Следите за давлением', AppLocale.kk: 'Қысымды қадағалаңыз', AppLocale.en: 'Watch your blood pressure'},
  'ADV_BP_ELEVATED_b': {AppLocale.ru: 'Ваши показания близки к 140/90 — уровню, при котором нужно связаться с врачом. Отдохните, через несколько часов спокойно посидите и снова измерьте давление тонометром, а результат введите в приложении. Если тонометр покажет 140/90 или выше — немедленно свяжитесь с врачом. Скажите о повышенных показаниях на ближайшем приёме. Если появились сильная головная боль, нарушения зрения или внезапный отёк лица и рук — звоните 103 и назовите срок беременности, не дожидаясь повторного измерения.', AppLocale.kk: 'Сіздің көрсеткіштеріңіз 140/90-ға жақын — бұл дәрігерге хабарласу қажет деңгей. Демалыңыз, бірнеше сағаттан кейін тыныш отырып қысымды тонометрмен қайта өлшеңіз де, нәтижесін қолданбаға енгізіңіз. Егер тонометр 140/90 немесе одан жоғары көрсетсе — дереу дәрігерге хабарласыңыз. Жақын арадағы қабылдауда жоғары көрсеткіштер туралы айтыңыз. Егер қатты бас ауыруы, көру бұзылысы немесе беттің, қолдың кенеттен ісінуі пайда болса — қайта өлшеуді күтпей, 103-ке қоңырау шалып, жүктілік мерзімін айтыңыз.', AppLocale.en: 'Your readings are close to 140/90 — the level at which you must contact a doctor. Rest, then after a few hours sit quietly, measure your blood pressure again with a cuff, and enter the result in the app. If the cuff shows 140/90 or higher, contact your doctor immediately. Tell your doctor about the raised readings at your next visit. If you get a severe headache, vision changes, or sudden swelling of the face and hands, call 103 and say how many weeks pregnant you are, without waiting to re-measure.'},
  // The device card. Three rules are carried by the wording rather than by a
  // comment, so read before editing:
  //   * the subject is the SENSOR, never her blood pressure. The card's firing
  //     window sits entirely inside the ±10–15 mmHg a wrist estimate carries.
  //   * NO number, and specifically not 140/90 — not a citation gap this time
  //     but a validity one: a cuff threshold beside a wrist estimate invites
  //     exactly the comparison the estimate cannot support (refused #20).
  //   * «измерьте тонометром» was approved only as one branch of three. A cuff
  //     is not as common in a Kazakh household as a thermometer, so the copy
  //     also names the route that needs no equipment — blood pressure is
  //     measured at every antenatal visit, per the protocol — and,
  //     unconditionally for both, the reviewed preeclampsia red flags and 103.
  //     That last branch is the only part that helps the woman whose wrist
  //     reads 137 while her true pressure is 160.
  //
  // The title names the sensor because the clipboard export sends TITLES ONLY:
  // it ships without the body, out of the app, to an unknown reader.
  'ADV_BP_DEVICE_HIGH': {AppLocale.ru: 'Датчик показывает повышенное давление', AppLocale.kk: 'Датчик жоғары қан қысымын көрсетіп тұр', AppLocale.en: 'The sensor is reading a raised blood pressure'},
  'ADV_BP_DEVICE_HIGH_b': {AppLocale.ru: 'Это оценка датчика на запястье, а не измерение: она может заметно отличаться от того, что покажет тонометр. Измерьте давление тонометром, спокойно посидев несколько минут, и введите результат в приложении. Если тонометра нет — давление измеряют на каждом приёме в женской консультации; скажите там, что видели повышенные показания. Если появились сильная головная боль, нарушения зрения или внезапный отёк лица и рук — звоните 103 и назовите срок беременности.', AppLocale.kk: 'Бұл — білезіктегі датчиктің болжамы, өлшем емес: ол тонометр көрсететін мәннен айтарлықтай өзгеше болуы мүмкін. Бірнеше минут тыныш отырып, қысымды тонометрмен өлшеңіз де, нәтижесін қолданбаға енгізіңіз. Тонометр болмаса — қысым әйелдер консультациясындағы әр қабылдауда өлшенеді; сонда жоғары көрсеткіш байқағаныңызды айтыңыз. Егер қатты бас ауыруы, көру бұзылысы немесе беттің, қолдың кенеттен ісінуі пайда болса — 103-ке қоңырау шалып, жүктілік мерзімін айтыңыз.', AppLocale.en: 'This is a wrist-sensor estimate, not a measurement: it can differ noticeably from what a cuff would show. Sit quietly for a few minutes, measure your blood pressure with a cuff, and enter the result in the app. If you do not have a cuff, your blood pressure is measured at every antenatal visit — tell them there that you have seen raised readings. If you get a severe headache, vision changes, or sudden swelling of the face and hands, call 103 and say how many weeks pregnant you are.'},
  'ADV_HR_STEADY': {AppLocale.ru: 'Пульс ровный', AppLocale.kk: 'Тамыр соғысы тұрақты', AppLocale.en: 'Heart rate steady'},
  'ADV_HR_STEADY_b': {AppLocale.ru: 'Частота сердечных сокращений стабильна.', AppLocale.kk: 'Жүрек соғу жиілігі тұрақты.', AppLocale.en: 'Your heart rate is stable.'},
  'ADV_HR_RISING': {AppLocale.ru: 'Пульс растёт', AppLocale.kk: 'Тамыр соғысы артып барады', AppLocale.en: 'Heart rate rising'},
  'ADV_HR_RISING_b': {AppLocale.ru: 'Средний пульс вырос за последнее время. Отдохните; при беспокойстве обратитесь к врачу.', AppLocale.kk: 'Соңғы кезде орташа тамыр соғысы өсті. Демалыңыз; алаңдасаңыз дәрігерге жүгініңіз.', AppLocale.en: 'Your average heart rate has risen recently. Rest; if concerned, see your doctor.'},
  'ADV_SPO2_SLEEP_DIP': {AppLocale.ru: 'Кислород во сне', AppLocale.kk: 'Ұйқыдағы оттегі', AppLocale.en: 'Oxygen during sleep'},
  'ADV_SPO2_SLEEP_DIP_b': {AppLocale.ru: 'Во сне уровень кислорода опускался ниже 95%. Если повторяется — обсудите с врачом.', AppLocale.kk: 'Ұйқы кезінде оттегі деңгейі 95%-дан төмендеді. Қайталанса, дәрігермен ақылдасыңыз.', AppLocale.en: 'Your blood oxygen dipped below 95% during sleep. If it recurs, discuss with your doctor.'},
  'ADV_TEMP_ELEVATED': {AppLocale.ru: 'Повышенная температура', AppLocale.kk: 'Дене қызуы жоғары', AppLocale.en: 'Elevated temperature'},
  // A raised temperature is on the pregnancy warning-signs list (`preg_warn_fever`),
  // so this card must not stop at "rest and watch" — it says the same thing the
  // list says, on the ADV_BP_ELEVATED_b model. No number here: the threshold that
  // fired it is TriageThresholds.feverWarningC.
  'ADV_TEMP_ELEVATED_b': {AppLocale.ru: 'Температура повышена. Отдохните, пейте больше жидкости и измерьте снова. Если температура держится или растёт — обратитесь к врачу: при беременности высокая температура требует осмотра.', AppLocale.kk: 'Дене қызуы жоғарылаған. Демалыңыз, көбірек сұйықтық ішіңіз және қайта өлшеңіз. Қызу басылмаса немесе өссе — дәрігерге жүгініңіз: жүктілік кезінде жоғары температура тексеруді қажет етеді.', AppLocale.en: 'Your temperature is elevated. Rest, drink fluids, and re-measure. If it stays up or climbs, contact your doctor — a high temperature in pregnancy needs to be checked.'},
  'ADV_TEMP_STEADY': {AppLocale.ru: 'Температура ровная', AppLocale.kk: 'Дене қызуы біркелкі', AppLocale.en: 'Temperature steady'},
  'ADV_TEMP_STEADY_b': {AppLocale.ru: 'Температура по браслету держится ровно.', AppLocale.kk: 'Білезік бойынша дене қызуы біркелкі.', AppLocale.en: 'Your temperature readings have held steady.'},
  // BOTH glucose cards are now MANUAL-ONLY — a glucometer reading she typed in.
  // The device path says nothing at all (health_advisor.dart carries the
  // reasoning), so the bodies had to change with the gate:
  //
  //   * HIGH said «Это оценка по браслету, не диагноз». True while the card
  //     could fire off the wrist, FALSE the moment it cannot — a card
  //     misdescribing its own source is this review's defect in reverse. It now
  //     names the instrument the reading actually came from, and points AT the
  //     OGTT window instead of substituting for it (refused item #6): 24–28
  //     недель is the ONE number permitted here, and it is permitted because it
  //     is cited — packages/contract/antenatal_protocol.json, item `ogtt`.
  //   * LOW never said what would make it urgent. It now names the reviewed
  //     hypoglycaemia red flags and 103, on the emergency_help.json pattern,
  //     and asks for a re-measurement BY THE GLUCOMETER — «измерьте снова» with
  //     no instrument named is refused sentence #16's mistake.
  //
  // No threshold numbers: GlucoseThresholds is uncited here, exactly as 37.8 /
  // 38.5 are for fever. What fired the card may not be printed on it.
  'ADV_GLUCOSE_HIGH': {AppLocale.ru: 'Следите за сахаром', AppLocale.kk: 'Қантты қадағалаңыз', AppLocale.en: 'Watch your blood sugar'},
  'ADV_GLUCOSE_HIGH_b': {AppLocale.ru: 'Показание глюкометра высокое. Это не диагноз: гестационный диабет подтверждают лабораторным тестом. Обсудите с врачом тест на толерантность к глюкозе — по плану наблюдения его делают в 24–28 недель.', AppLocale.kk: 'Глюкометр көрсеткіші жоғары. Бұл — диагноз емес: гестациялық диабет зертханалық тестпен расталады. Дәрігермен глюкозаға төзімділік тесті туралы сөйлесіңіз — бақылау жоспары бойынша ол 24–28 аптада жасалады.', AppLocale.en: 'Your glucometer reading is high. This is not a diagnosis: gestational diabetes is confirmed by a laboratory test. Ask your doctor about the glucose tolerance test — your antenatal plan schedules it at 24–28 weeks.'},
  'ADV_GLUCOSE_LOW': {AppLocale.ru: 'Низкий сахар', AppLocale.kk: 'Қант төмен', AppLocale.en: 'Low blood sugar'},
  'ADV_GLUCOSE_LOW_b': {AppLocale.ru: 'Показание глюкометра низкое. Съешьте или выпейте что-нибудь сладкое, немного подождите и измерьте глюкометром ещё раз, а результат введите в приложении. Если появились сильная слабость, дрожь, холодный пот или спутанность сознания — звоните 103. Скажите врачу о низких показаниях на ближайшем приёме.', AppLocale.kk: 'Глюкометр көрсеткіші төмен. Тәтті бірдеңе жеп немесе ішіп, аздап күте тұрып, глюкометрмен қайта өлшеңіз де, нәтижесін қолданбаға енгізіңіз. Егер қатты әлсіздік, дірілдеу, суық тер немесе сананың шатасуы пайда болса — 103-ке қоңырау шалыңыз. Жақын арадағы қабылдауда төмен көрсеткіштер туралы дәрігерге айтыңыз.', AppLocale.en: 'Your glucometer reading is low. Eat or drink something sweet, wait a little, measure again with the glucometer, and enter the result in the app. If you get severe weakness, shaking, cold sweat or confusion, call 103. Tell your doctor about the low readings at your next visit.'},
  // ADV_GLUCOSE_STEADY / _b are DELETED, not reworded. «Сахар в норме» was
  // refused sentence #5 in docs/CLINICAL-REVIEW-WATCH.md and shipped word for
  // word — a normality verdict on a diabetes number, from an optical wrist
  // estimate in a unit the vendor never states anywhere in 3,248 pages. The
  // same metric was withdrawn from the admin panel on 2026-08-13 for exactly
  // this reason; the app kept saying it for another day.
  //
  // Deleted rather than reworded so no call site can keep rendering an
  // approved-looking string, and so a replacement has to go through the gate
  // rather than inherit this key's history. Pinned by
  // test/refused_sentences_test.dart, which fails the build if it returns.
  'ADV_HYDRATED': {AppLocale.ru: 'Водный баланс в норме', AppLocale.kk: 'Су балансы қалыпты', AppLocale.en: 'Well hydrated'},
  'ADV_HYDRATED_b': {AppLocale.ru: 'Вы выполнили дневную норму воды. Так держать!', AppLocale.kk: 'Күнделікті су нормасын орындадыңыз. Жалғастыра беріңіз!', AppLocale.en: "You've met today's water goal. Keep it up!"},
  'ADV_HYDRATE_LOW': {AppLocale.ru: 'Пора выпить воды', AppLocale.kk: 'Су ішетін кез', AppLocale.en: 'Time to hydrate'},
  'ADV_HYDRATE_LOW_b': {AppLocale.ru: 'До вечера выпито мало воды. Сделайте пару глотков.', AppLocale.kk: 'Кешке дейін су аз ішілді. Бірнеше жұтым жасаңыз.', AppLocale.en: "You're behind on water for today — have a glass or two."},
  'ADV_SPO2_STEADY': {AppLocale.ru: 'Кислород ровный', AppLocale.kk: 'Оттегі біркелкі', AppLocale.en: 'Oxygen steady'},
  'ADV_SPO2_STEADY_b': {AppLocale.ru: 'Кислород по браслету держится ровно.', AppLocale.kk: 'Білезік бойынша оттегі біркелкі.', AppLocale.en: 'Your oxygen readings have held steady.'},
  'ADV_SLEEP_OK': {AppLocale.ru: 'Спокойный сон', AppLocale.kk: 'Тыныш ұйқы', AppLocale.en: 'Restful sleep'},
  'ADV_SLEEP_OK_b': {AppLocale.ru: 'Во сне показатели были стабильны — хороший отдых.', AppLocale.kk: 'Ұйқы кезінде көрсеткіштер тұрақты болды — жақсы демалыс.', AppLocale.en: 'Your readings were stable during sleep — a good rest.'},

  // Onboarding
  'onb_welcome_title': {AppLocale.ru: 'Добро пожаловать в Ana-Bala', AppLocale.kk: 'Ana-Balaға қош келдіңіз', AppLocale.en: 'Welcome to Ana-Bala'},
  'onb_welcome_body': {AppLocale.ru: 'Спокойный уход за беременностью и безопасность ребёнка в одном приложении.', AppLocale.kk: 'Жүктілікке қамқорлық пен бала қауіпсіздігі бір қолданбада.', AppLocale.en: 'Calm pregnancy care and child safety in one app.'},
  'offline_banner': {AppLocale.ru: 'Нет подключения к интернету', AppLocale.kk: 'Интернет байланысы жоқ', AppLocale.en: 'No internet connection'},
  'onb_consent_label': {
    AppLocale.ru: 'Я принимаю политику конфиденциальности и условия использования.',
    AppLocale.kk: 'Құпиялылық саясаты мен пайдалану шарттарын қабылдаймын.',
    AppLocale.en: 'I accept the privacy policy and the terms of use.',
  },

  // ---- Phone-OTP sign-in (auth_*) ----
  'auth_title': {AppLocale.ru: 'Вход', AppLocale.kk: 'Кіру', AppLocale.en: 'Sign in'},
  'auth_back': {AppLocale.ru: 'Назад', AppLocale.kk: 'Артқа', AppLocale.en: 'Back'},
  'auth_phone_intro': {
    AppLocale.ru: 'Введите номер телефона — мы отправим код подтверждения.',
    AppLocale.kk: 'Телефон нөмірін енгізіңіз — растау кодын жібереміз.',
    AppLocale.en: 'Enter your phone number — we’ll send a confirmation code.',
  },
  'auth_phone_label': {AppLocale.ru: 'Номер телефона', AppLocale.kk: 'Телефон нөмірі', AppLocale.en: 'Phone number'},
  'auth_send_code': {AppLocale.ru: 'Отправить код', AppLocale.kk: 'Код жіберу', AppLocale.en: 'Send code'},
  // What this build actually does. There is no SMS gateway: the number is
  // claimed, not verified, and the code screen is skipped entirely. The screen
  // still said «мы отправим код подтверждения» over a button reading
  // «Отправить код», so she signed in instantly and then sat waiting for a
  // message that was never sent — and the next thing she does is retype her
  // number, thinking she got it wrong.
  'auth_phone_intro_nocode': {
    AppLocale.ru: 'Введите номер телефона — по нему сохраняются ваши данные. Код подтверждения не нужен.',
    AppLocale.kk: 'Телефон нөмірін енгізіңіз — деректеріңіз осы нөмірге сақталады. Растау коды қажет емес.',
    AppLocale.en: 'Enter your phone number — your data is kept against it. No confirmation code needed.',
  },
  'auth_continue': {AppLocale.ru: 'Продолжить', AppLocale.kk: 'Жалғастыру', AppLocale.en: 'Continue'},
  'auth_code_intro': {
    AppLocale.ru: 'Введите код, отправленный на {phone}.',
    AppLocale.kk: '{phone} нөміріне жіберілген кодты енгізіңіз.',
    AppLocale.en: 'Enter the code sent to {phone}.',
  },
  'auth_code_label': {AppLocale.ru: 'Код из SMS', AppLocale.kk: 'SMS коды', AppLocale.en: 'Code from SMS'},
  'auth_no_code': {AppLocale.ru: 'Не пришёл код?', AppLocale.kk: 'Код келмеді ме?', AppLocale.en: 'No code?'},
  'auth_resend': {AppLocale.ru: 'Отправить снова', AppLocale.kk: 'Қайта жіберу', AppLocale.en: 'Resend'},
  'auth_resend_in': {AppLocale.ru: 'Повтор через {sec} c', AppLocale.kk: '{sec} с кейін', AppLocale.en: 'Resend in {sec}s'},
  'auth_verify': {AppLocale.ru: 'Подтвердить', AppLocale.kk: 'Растау', AppLocale.en: 'Verify'},
  'auth_signed_in_as': {AppLocale.ru: 'Вход выполнен: {phone}', AppLocale.kk: 'Кіру орындалды: {phone}', AppLocale.en: 'Signed in: {phone}'},
  'auth_sign_in_cta': {AppLocale.ru: 'Войти по номеру телефона', AppLocale.kk: 'Телефон нөмірімен кіру', AppLocale.en: 'Sign in with your phone'},
  'auth_sign_out': {AppLocale.ru: 'Выйти', AppLocale.kk: 'Шығу', AppLocale.en: 'Sign out'},
  'auth_err_invalid-phone': {AppLocale.ru: 'Проверьте номер телефона.', AppLocale.kk: 'Телефон нөмірін тексеріңіз.', AppLocale.en: 'Please check the phone number.'},
  'auth_err_invalid-code': {AppLocale.ru: 'Неверный код. Попробуйте ещё раз.', AppLocale.kk: 'Код қате. Қайталап көріңіз.', AppLocale.en: 'Wrong code. Please try again.'},
  'auth_err_network': {AppLocale.ru: 'Нет связи. Проверьте интернет.', AppLocale.kk: 'Байланыс жоқ. Интернетті тексеріңіз.', AppLocale.en: 'No connection. Check your internet.'},
  'onb_get_started': {AppLocale.ru: 'Начать', AppLocale.kk: 'Бастау', AppLocale.en: 'Get started'},
  'onb_language_title': {AppLocale.ru: 'Выберите язык', AppLocale.kk: 'Тілді таңдаңыз', AppLocale.en: 'Choose your language'},
  'onb_profile_title': {AppLocale.ru: 'Как вас зовут?', AppLocale.kk: 'Атыңыз кім?', AppLocale.en: "What's your name?"},
  'onb_name_hint': {AppLocale.ru: 'Ваше имя', AppLocale.kk: 'Атыңыз', AppLocale.en: 'Your name'},
  'onb_pair_title': {AppLocale.ru: 'Подключите браслет', AppLocale.kk: 'Білезікті қосыңыз', AppLocale.en: 'Pair your band'},
  'onb_pair_body': {AppLocale.ru: 'Выберите ваш браслет из списка. Можно подключить позже.', AppLocale.kk: 'Тізімнен білезігіңізді таңдаңыз. Кейінірек те қосуға болады.', AppLocale.en: 'Pick your band from the list. You can do this later.'},
  'onb_pair_skip': {AppLocale.ru: 'Пропустить', AppLocale.kk: 'Өткізіп жіберу', AppLocale.en: 'Skip for now'},
  'onb_pair_scanning': {AppLocale.ru: 'Поиск устройств…', AppLocale.kk: 'Құрылғыларды іздеу…', AppLocale.en: 'Scanning for devices…'},
  'onb_child_title': {AppLocale.ru: 'Добавьте ребёнка', AppLocale.kk: 'Бала қосыңыз', AppLocale.en: 'Add your child'},
  'onb_child_name_hint': {AppLocale.ru: 'Имя ребёнка', AppLocale.kk: 'Баланың аты', AppLocale.en: "Child's name"},
  'onb_home_label': {AppLocale.ru: 'Дом', AppLocale.kk: 'Үй', AppLocale.en: 'Home'},
  'onb_school_label': {AppLocale.ru: 'Школа', AppLocale.kk: 'Мектеп', AppLocale.en: 'School'},
  'onb_use_current': {AppLocale.ru: 'Использовать текущее место', AppLocale.kk: 'Қазіргі орынды пайдалану', AppLocale.en: 'Use current location'},
  'onb_zone_set': {AppLocale.ru: 'Зона задана', AppLocale.kk: 'Аймақ белгіленді', AppLocale.en: 'Zone set'},
  'onb_phone_hint': {AppLocale.ru: 'Номер телефона', AppLocale.kk: 'Телефон нөмірі', AppLocale.en: 'Phone number'},
  'onb_expecting': {AppLocale.ru: 'Ждёте ребёнка?', AppLocale.kk: 'Бала күтудесіз бе?', AppLocale.en: 'Are you expecting a baby?'},
  'onb_expecting_sub': {AppLocale.ru: 'Включим отслеживание беременности. Иначе — календарь цикла.', AppLocale.kk: 'Жүктілікті бақылауды қосамыз. Әйтпесе — цикл күнтізбесі.', AppLocale.en: "We'll set up pregnancy tracking. Otherwise, cycle tracking."},
  'onb_due_date_set': {AppLocale.ru: 'Дата родов: {date}', AppLocale.kk: 'Босану күні: {date}', AppLocale.en: 'Due date: {date}'},
  'prof_doctor_hint': {AppLocale.ru: 'Телефон врача (для экстренных случаев)', AppLocale.kk: 'Дәрігердің телефоны (төтенше жағдайға)', AppLocale.en: "Doctor's phone (emergency)"},
  'onb_country': {AppLocale.ru: 'Страна', AppLocale.kk: 'Ел', AppLocale.en: 'Country'},
  'tr_add_child': {AppLocale.ru: 'Добавить ребёнка', AppLocale.kk: 'Бала қосу', AppLocale.en: 'Add child'},
  'tr_add_device': {AppLocale.ru: 'Добавить устройство', AppLocale.kk: 'Құрылғы қосу', AppLocale.en: 'Add device'},
  'tr_no_tracker_hint': {
    AppLocale.ru: 'Трекер ещё не привязан. Добавьте устройство, чтобы видеть местоположение на карте.',
    AppLocale.kk: 'Трекер әлі байланбаған. Картадан орналасуын көру үшін құрылғы қосыңыз.',
    AppLocale.en: 'No tracker linked yet. Add a device to see the location on the map.',
  },
  'tr_manage_zones': {AppLocale.ru: 'Зоны безопасности', AppLocale.kk: 'Қауіпсіздік аймақтары', AppLocale.en: 'Safe zones'},
  // The child's card — the whole child-care hub (медкарта, прививки, рост и
  // вес, развитие, дневник, плач, прикорм, безопасность, болезни). It hung off
  // Settings and nothing else until the «Бала» tab grew this entry.
  'tr_child_card': {AppLocale.ru: 'Карточка ребёнка', AppLocale.kk: 'Бала картасы', AppLocale.en: "Child's card"},
  'tr_pick_child': {AppLocale.ru: 'Чья карточка?', AppLocale.kk: 'Кімнің картасы?', AppLocale.en: 'Whose card?'},
  // Screen 15a — the tools list on the «Ребёнок» tab. The label a parent reads
  // before she taps, so it names what is behind it (care, not "tools").
  'tr_tools': {
    AppLocale.ru: 'Уход и здоровье',
    AppLocale.kk: 'Күтім және денсаулық',
    AppLocale.en: 'Care & health'
  },
  // Said rather than silently hidden: five of the nine tools are keyed on the
  // child's age, and a parent who skipped the birthday would otherwise never
  // learn прививки and развитие are in the app at all.
  'tools_needs_dob': {
    AppLocale.ru: 'Укажите её — откроются прививки, развитие, прикорм и болезни',
    AppLocale.kk: 'Оны көрсетіңіз — егулер, даму, қосымша тамақ және аурулар ашылады',
    AppLocale.en: 'Add it to unlock vaccinations, development, solids and illness'
  },

  // Safety alerts (zone enter/exit feed)
  'alerts_title': {AppLocale.ru: 'Оповещения', AppLocale.kk: 'Хабарламалар', AppLocale.en: 'Alerts'},
  'alerts_empty': {AppLocale.ru: 'Пока нет оповещений. Здесь появятся входы и выходы из зон.', AppLocale.kk: 'Әзірге хабарлама жоқ. Мұнда аймаққа кіру мен шығу пайда болады.', AppLocale.en: 'No alerts yet. Zone entries and exits will appear here.'},
  'alerts_clear': {AppLocale.ru: 'Очистить', AppLocale.kk: 'Тазалау', AppLocale.en: 'Clear'},
  'confirm_clear_alerts_title': {
    AppLocale.ru: 'Очистить все уведомления?',
    AppLocale.kk: 'Барлық хабарламаларды тазалау керек пе?',
    AppLocale.en: 'Clear all alerts?',
  },
  'confirm_clear_alerts_body': {
    AppLocale.ru: 'Вся история будет удалена, включая сигналы SOS и отметки о прибытии. Это действие нельзя отменить.',
    AppLocale.kk: 'Бүкіл тарих жойылады, соның ішінде SOS сигналдары мен тіркелулер. Бұл әрекетті кері қайтару мүмкін емес.',
    AppLocale.en: 'The whole history will be deleted, including SOS signals and check-ins. This cannot be undone.',
  },
  'alert_entered': {AppLocale.ru: 'Вход в «{zone}»', AppLocale.kk: '«{zone}» аймағына кіру', AppLocale.en: 'Entered {zone}'},
  'alert_left': {AppLocale.ru: 'Выход из «{zone}»', AppLocale.kk: '«{zone}» аймағынан шығу', AppLocale.en: 'Left {zone}'},
  'alert_checkin': {AppLocale.ru: 'Отметка «Всё хорошо»', AppLocale.kk: '«Бәрі жақсы» белгісі', AppLocale.en: 'Checked in — all good'},
  'alert_sos': {AppLocale.ru: 'SOS — сигнал тревоги', AppLocale.kk: 'SOS — дабыл сигналы', AppLocale.en: 'SOS — emergency signal'},
  'alert_low_battery': {AppLocale.ru: 'Низкий заряд трекера ({pct}%)', AppLocale.kk: 'Трекер заряды төмен ({pct}%)', AppLocale.en: 'Tracker battery low ({pct}%)'},
  'alerts_filter_all': {AppLocale.ru: 'Все', AppLocale.kk: 'Барлығы', AppLocale.en: 'All'},
  'alerts_child_all': {AppLocale.ru: 'Все дети', AppLocale.kk: 'Барлық бала', AppLocale.en: 'All children'},
  'alerts_filter_zones': {AppLocale.ru: 'Зоны', AppLocale.kk: 'Аймақтар', AppLocale.en: 'Zones'},
  'alerts_filter_sos': {AppLocale.ru: 'SOS', AppLocale.kk: 'SOS', AppLocale.en: 'SOS'},
  'alerts_filter_checkins': {AppLocale.ru: 'Отметки', AppLocale.kk: 'Белгілер', AppLocale.en: 'Check-ins'},
  'alerts_filter_battery': {AppLocale.ru: 'Заряд', AppLocale.kk: 'Қуат', AppLocale.en: 'Battery'},
  'alerts_dismiss': {AppLocale.ru: 'Убрать', AppLocale.kk: 'Жою', AppLocale.en: 'Dismiss'},
  'alerts_dismiss_title': {AppLocale.ru: 'Убрать это оповещение?', AppLocale.kk: 'Бұл ескертуді жою керек пе?', AppLocale.en: 'Dismiss this alert?'},
  'alerts_dismiss_body': {AppLocale.ru: 'Оно исчезнет из ленты. Отменить это действие нельзя.', AppLocale.kk: 'Ол таспадан жоғалады. Бұл әрекетті қайтару мүмкін емес.', AppLocale.en: 'It will disappear from the feed. This cannot be undone.'},
  'sos_days_clear': {AppLocale.ru: '{n} дн. без сигналов SOS', AppLocale.kk: 'SOS сигналсыз {n} күн', AppLocale.en: '{n} days without an SOS'},
  'today_title': {AppLocale.ru: 'Сегодня', AppLocale.kk: 'Бүгін', AppLocale.en: 'Today'},
  'today_zone_events': {AppLocale.ru: 'событий в зонах', AppLocale.kk: 'аймақ оқиғасы', AppLocale.en: 'zone events'},
  'today_checkins': {AppLocale.ru: 'отметок', AppLocale.kk: 'белгі', AppLocale.en: 'check-ins'},
  'today_sos': {AppLocale.ru: 'SOS', AppLocale.kk: 'SOS', AppLocale.en: 'SOS'},
  'today_battery': {AppLocale.ru: 'о заряде', AppLocale.kk: 'заряд туралы', AppLocale.en: 'battery'},
  'child_checkin': {AppLocale.ru: 'Всё хорошо', AppLocale.kk: 'Бәрі жақсы', AppLocale.en: 'Check in'},
  'child_checkin_done': {AppLocale.ru: 'Отметка отправлена', AppLocale.kk: 'Белгі жіберілді', AppLocale.en: 'Check-in recorded'},
  'child_sos': {AppLocale.ru: 'SOS', AppLocale.kk: 'SOS', AppLocale.en: 'SOS'},
  'sos_confirm_title': {AppLocale.ru: 'Отправить сигнал SOS?', AppLocale.kk: 'SOS сигналын жіберу керек пе?', AppLocale.en: 'Send an SOS signal?'},
  'sos_confirm_body': {AppLocale.ru: 'Это отметит экстренную ситуацию в ленте безопасности.', AppLocale.kk: 'Бұл қауіпсіздік лентасында төтенше жағдайды белгілейді.', AppLocale.en: 'This flags an emergency in the safety feed.'},
  'sos_confirm_send': {AppLocale.ru: 'Отправить SOS', AppLocale.kk: 'SOS жіберу', AppLocale.en: 'Send SOS'},
  'sos_sent': {AppLocale.ru: 'Сигнал SOS отправлен', AppLocale.kk: 'SOS сигналы жіберілді', AppLocale.en: 'SOS signal sent'},

  // --- Screen 21 · «Сигнал SOS» — the one red screen in the app -------------
  //
  // Two of the spec's three buttons are here. The third, «Позвонить Алие», is
  // not: nothing in the schema holds a number for a child or for the tracker
  // she wears, and this is the last screen in the app on which to display a
  // plausible-looking number nobody answers. It says so, and offers 103.
  'sos21_label': {AppLocale.ru: 'Сигнал SOS', AppLocale.kk: 'SOS сигналы', AppLocale.en: 'SOS signal'},
  'sos21_title': {AppLocale.ru: '{name} нажала кнопку SOS', AppLocale.kk: '{name} SOS түймесін басты', AppLocale.en: '{name} pressed the SOS button'},
  'sos21_title_noname': {AppLocale.ru: 'Нажата кнопка SOS', AppLocale.kk: 'SOS түймесі басылды', AppLocale.en: 'The SOS button was pressed'},
  'sos21_when': {AppLocale.ru: 'в {time} · {ago}', AppLocale.kk: '{time} · {ago}', AppLocale.en: 'at {time} · {ago}'},
  'sos21_where': {AppLocale.ru: 'Последнее известное место', AppLocale.kk: 'Соңғы белгілі орын', AppLocale.en: 'Last known position'},
  'sos21_where_unknown': {
    AppLocale.ru: 'Приложение не получало координат — где она сейчас, оно не знает.',
    AppLocale.kk: 'Қолданба координат алмады — оның қазір қайда екенін білмейді.',
    AppLocale.en: 'No position has reached the app, so it does not know where she is now.'
  },
  'sos21_where_at': {AppLocale.ru: 'Место от {time} · {ago}', AppLocale.kk: 'Орын {time} · {ago}', AppLocale.en: 'Position from {time} · {ago}'},
  'sos21_open_map': {AppLocale.ru: 'Открыть карту', AppLocale.kk: 'Картаны ашу', AppLocale.en: 'Open the map'},
  'sos21_call_contact': {AppLocale.ru: 'Позвонить: {name}', AppLocale.kk: 'Қоңырау шалу: {name}', AppLocale.en: 'Call: {name}'},
  'sos21_no_contact_title': {AppLocale.ru: 'Кому сообщить — не указано', AppLocale.kk: 'Кімге хабарлау — көрсетілмеген', AppLocale.en: 'Nobody is listed to call'},
  'sos21_no_contact_body': {
    AppLocale.ru: 'В медкарте ребёнка не заполнен контакт для экстренной связи. Приложение не подставит номер, которого у него нет.',
    AppLocale.kk: 'Баланың медициналық картасында шұғыл байланыс толтырылмаған. Қолданба өзінде жоқ нөмірді қоя алмайды.',
    AppLocale.en: 'The child’s medical card has no emergency contact. The app will not fill in a number it does not have.'
  },
  'sos21_no_child_phone': {
    AppLocale.ru: 'Позвонить ребёнку из приложения нельзя: номера брелока в карточке нет.',
    AppLocale.kk: 'Қолданбадан балаға қоңырау шалу мүмкін емес: картада брелок нөмірі жоқ.',
    AppLocale.en: 'The app cannot call your child: there is no tracker number on the card.'
  },
  'sos21_dismiss': {AppLocale.ru: 'Закрыть сигнал', AppLocale.kk: 'Сигналды жабу', AppLocale.en: 'Close the alert'},
  'sos21_dismiss_title': {AppLocale.ru: 'Закрыть экран SOS?', AppLocale.kk: 'SOS экранын жабу керек пе?', AppLocale.en: 'Close the SOS screen?'},
  'sos21_dismiss_body': {
    AppLocale.ru: 'Сигнал останется в ленте безопасности, но этот экран больше не откроется сам.',
    AppLocale.kk: 'Сигнал қауіпсіздік лентасында қалады, бірақ бұл экран қайта өздігінен ашылмайды.',
    AppLocale.en: 'The alert stays in the safety feed, but this screen will not open by itself again.'
  },
  'sos21_dismiss_confirm': {AppLocale.ru: 'Закрыть', AppLocale.kk: 'Жабу', AppLocale.en: 'Close'},

  // --- Screen 43 · «Поддержка» ---------------------------------------------
  'sup_title': {AppLocale.ru: 'Поддержка', AppLocale.kk: 'Қолдау', AppLocale.en: 'Support'},
  'sup_self_help': {AppLocale.ru: 'Попробуйте сами — это решает чаще всего', AppLocale.kk: 'Өзіңіз көріңіз — көбіне осы көмектеседі', AppLocale.en: 'Try this first — it usually helps'},
  'sup_act_refresh': {AppLocale.ru: 'Обновить положение ребёнка', AppLocale.kk: 'Баланың орнын жаңарту', AppLocale.en: 'Refresh the child’s position'},
  'sup_act_refresh_b': {AppLocale.ru: 'Если на карте старые данные — спросим сервер заново', AppLocale.kk: 'Картада ескі дерек болса — серверден қайта сұраймыз', AppLocale.en: 'If the map is stale, we ask the server again'},
  'sup_act_repair': {AppLocale.ru: 'Привязать браслет заново', AppLocale.kk: 'Білезікті қайта байланыстыру', AppLocale.en: 'Pair the tracker again'},
  'sup_act_repair_b': {AppLocale.ru: 'Если браслет не отвечает', AppLocale.kk: 'Білезік жауап бермесе', AppLocale.en: 'If the tracker is not answering'},
  'sup_act_order': {AppLocale.ru: 'Посмотреть мой заказ', AppLocale.kk: 'Тапсырысымды көру', AppLocale.en: 'See my order'},
  'sup_act_order_b': {AppLocale.ru: 'Статус доставки и состав заказа', AppLocale.kk: 'Жеткізу күйі және тапсырыс құрамы', AppLocale.en: 'Delivery status and contents'},
  'sup_write': {AppLocale.ru: 'Написать в поддержку', AppLocale.kk: 'Қолдауға жазу', AppLocale.en: 'Message support'},
  'sup_topic': {AppLocale.ru: 'С чем помочь?', AppLocale.kk: 'Немен көмектесейік?', AppLocale.en: 'What can we help with?'},
  'sup_topic_tracker': {AppLocale.ru: 'Браслет ребёнка', AppLocale.kk: 'Баланың білезігі', AppLocale.en: 'The child’s tracker'},
  'sup_topic_band': {AppLocale.ru: 'Мои часы', AppLocale.kk: 'Менің сағатым', AppLocale.en: 'My watch'},
  'sup_topic_order': {AppLocale.ru: 'Заказ и доставка', AppLocale.kk: 'Тапсырыс және жеткізу', AppLocale.en: 'Order and delivery'},
  'sup_topic_course': {AppLocale.ru: 'Курс Ма!Ма!', AppLocale.kk: 'Ма!Ма! курсы', AppLocale.en: 'The Ма!Ма! course'},
  'sup_topic_account': {AppLocale.ru: 'Вход и аккаунт', AppLocale.kk: 'Кіру және аккаунт', AppLocale.en: 'Sign-in and account'},
  'sup_hours': {AppLocale.ru: 'Отвечаем в WhatsApp ежедневно с 9:00 до 21:00', AppLocale.kk: 'WhatsApp-та күн сайын 9:00–21:00 жауап береміз', AppLocale.en: 'We answer on WhatsApp daily, 9:00–21:00'},
  // Said out loud, because a message that quietly carries diagnostics is a
  // message she did not know she was sending.
  'sup_context_note': {AppLocale.ru: 'К сообщению добавим версию приложения и номер устройства — чтобы не спрашивать. Ничего о здоровье и детях не отправляем.', AppLocale.kk: 'Хабарламаға қолданба нұсқасы мен құрылғы нөмірін қосамыз — сұрамау үшін. Денсаулық пен балалар туралы ештеңе жіберілмейді.', AppLocale.en: 'We attach your app version and device id so we do not have to ask. Nothing about health or children is sent.'},
  'sup_unavailable': {AppLocale.ru: 'Номер поддержки не настроен. Попробуйте позже.', AppLocale.kk: 'Қолдау нөмірі бапталмаған. Кейінірек көріңіз.', AppLocale.en: 'No support number is configured yet.'},
  // --- Screen 43 · the thread itself («шапка → диалог → чипы → поле») -------
  'sup_chat_title': {AppLocale.ru: 'Переписка с поддержкой', AppLocale.kk: 'Қолдаумен хат алмасу', AppLocale.en: 'Chat with support'},
  // The spec draws «шапка с именем оператора». We do not have one: the panel
  // records WHICH member of staff replied, but the app is never told, and
  // inventing «Айгуль» over an answer somebody else wrote is worse than a
  // truthful role. See docs/DESIGN_DEVIATIONS.md.
  'sup_chat_who': {AppLocale.ru: 'Оператор Ana-Bala', AppLocale.kk: 'Ana-Bala операторы', AppLocale.en: 'Ana-Bala support'},
  'sup_chat_sla': {AppLocale.ru: 'Обычно отвечаем в течение {h} часов', AppLocale.kk: 'Әдетте {h} сағат ішінде жауап береміз', AppLocale.en: 'We usually answer within {h} hours'},
  'sup_chat_disclaimer': {AppLocale.ru: 'Поддержка помогает с приложением, устройством и заказом. При опасных признаках звоните 103.', AppLocale.kk: 'Қолдау қосымша, құрылғы және тапсырыс бойынша көмектеседі. Қауіпті белгілерде 103-ке қоңырау шалыңыз.', AppLocale.en: 'Support helps with the app, the device and your order. For danger signs call 103.'},
  'sup_chat_you': {AppLocale.ru: 'Вы', AppLocale.kk: 'Сіз', AppLocale.en: 'You'},
  'sup_chat_hint': {AppLocale.ru: 'Напишите сообщение…', AppLocale.kk: 'Хабарлама жазыңыз…', AppLocale.en: 'Write a message…'},
  'sup_chat_send': {AppLocale.ru: 'Отправить', AppLocale.kk: 'Жіберу', AppLocale.en: 'Send'},
  'sup_chat_empty': {AppLocale.ru: 'Здесь пока пусто. Напишите, с чем помочь — ответит живой оператор.', AppLocale.kk: 'Әзірге бос. Немен көмектесу керектігін жазыңыз — тірі оператор жауап береді.', AppLocale.en: 'Nothing here yet. Tell us what you need — a real person answers.'},
  'sup_chat_first_note': {AppLocale.ru: 'Первое сообщение создаст обращение. Приложим версию приложения и номер устройства — ничего о здоровье и детях.', AppLocale.kk: 'Бірінші хабарлама өтініш ашады. Қосымша нұсқасы мен құрылғы нөмірін қосамыз — денсаулық пен балалар туралы ештеңе жоқ.', AppLocale.en: 'Your first message opens a ticket. We attach the app version and device id — nothing about health or children.'},
  // The result of the request, never the fact that one was sent.
  'sup_chat_failed': {AppLocale.ru: 'Не отправилось. Проверьте связь и попробуйте ещё раз.', AppLocale.kk: 'Жіберілмеді. Байланысты тексеріп, қайта көріңіз.', AppLocale.en: 'It did not send. Check your connection and try again.'},
  'sup_chat_load_failed': {AppLocale.ru: 'Переписка не загрузилась', AppLocale.kk: 'Хат алмасу жүктелмеді', AppLocale.en: 'The conversation did not load'},
  'sup_chat_retry': {AppLocale.ru: 'Повторить', AppLocale.kk: 'Қайталау', AppLocale.en: 'Try again'},
  'sup_chat_closed': {AppLocale.ru: 'Обращение закрыто. Новое сообщение откроет его снова.', AppLocale.kk: 'Өтініш жабылды. Жаңа хабарлама оны қайта ашады.', AppLocale.en: 'This ticket is closed. A new message reopens it.'},
  'sup_chat_sent_waiting': {AppLocale.ru: 'Отправлено. Ответ придёт уведомлением.', AppLocale.kk: 'Жіберілді. Жауап хабарландырумен келеді.', AppLocale.en: 'Sent. The answer arrives as a notification.'},
  // The entry row on «Помощь».
  'sup_chat_row_none': {AppLocale.ru: 'Ответит живой оператор, прямо в приложении', AppLocale.kk: 'Тірі оператор қосымшада жауап береді', AppLocale.en: 'A real person answers, right in the app'},
  'sup_chat_row_waiting': {AppLocale.ru: 'Есть ответ поддержки · {n}', AppLocale.kk: 'Қолдау жауабы бар · {n}', AppLocale.en: 'Support has answered · {n}'},
  'sup_chat_action': {AppLocale.ru: 'Можно сделать прямо сейчас', AppLocale.kk: 'Дәл қазір жасауға болады', AppLocale.en: 'You can do this right now'},
  // Every one of her tickets is on this screen, oldest first, and the live one
  // last against the input. Drawn only when there IS more than one: the desk
  // can open a second ticket for her from the panel, and an answer written into
  // it used to be unreachable anywhere in the app.
  'sup_chat_thread_live': {AppLocale.ru: 'Сюда уйдёт ваше сообщение', AppLocale.kk: 'Хабарламаңыз осында жіберіледі', AppLocale.en: 'Your message goes here'},
  'sup_chat_thread_past': {AppLocale.ru: 'Прошлое обращение', AppLocale.kk: 'Бұрынғы өтініш', AppLocale.en: 'An earlier ticket'},
  // --- Screen 44 · «Аудио дня · плеер» -------------------------------------
  'aud_title': {AppLocale.ru: 'Аудио дня', AppLocale.kk: 'Күн аудиосы', AppLocale.en: 'Audio of the day'},
  'aud_back15': {AppLocale.ru: 'Назад 15 секунд', AppLocale.kk: '15 секунд артқа', AppLocale.en: 'Back 15 seconds'},
  'aud_fwd15': {AppLocale.ru: 'Вперёд 15 секунд', AppLocale.kk: '15 секунд алға', AppLocale.en: 'Forward 15 seconds'},
  'aud_play': {AppLocale.ru: 'Слушать', AppLocale.kk: 'Тыңдау', AppLocale.en: 'Play'},
  'aud_pause': {AppLocale.ru: 'Пауза', AppLocale.kk: 'Кідірту', AppLocale.en: 'Pause'},
  // The promise the screen has to be able to keep: stayAwake is set on the
  // player, so the clip continues while the display is off.
  'aud_screen_off': {AppLocale.ru: 'Экран погаснет — запись не остановится', AppLocale.kk: 'Экран сөнеді — жазба тоқтамайды', AppLocale.en: 'The screen will dim — the recording keeps playing'},
  'aud_all': {AppLocale.ru: 'Все записи · {n}', AppLocale.kk: 'Барлық жазба · {n}', AppLocale.en: 'All recordings · {n}'},
  // --- «Все записи» · the library the row above leads to --------------------
  // Day NUMBERS, not dates: the catalogue is keyed by gestational day / day of
  // life, and the server holds no calendar to turn one into a date.
  'aud_lib_title': {AppLocale.ru: 'Все записи', AppLocale.kk: 'Барлық жазба', AppLocale.en: 'All recordings'},
  'aud_lib_day': {AppLocale.ru: 'День {n}', AppLocale.kk: '{n}-күн', AppLocale.en: 'Day {n}'},
  'aud_lib_untitled': {AppLocale.ru: 'Без названия', AppLocale.kk: 'Атауы жоқ', AppLocale.en: 'Untitled'},
  // Printed because tapping a row downloads the clip: on a village connection
  // the difference between 40 КБ and 4 МБ is the difference between "a moment"
  // and "not now".
  'aud_lib_size': {AppLocale.ru: '{n} КБ', AppLocale.kk: '{n} КБ', AppLocale.en: '{n} KB'},
  // Said out loud because the list is filtered to her language: a mother who
  // sees fewer entries than a friend does should know why.
  'aud_lib_lang_note': {AppLocale.ru: 'Записи на вашем языке · {n}', AppLocale.kk: 'Сіздің тіліңіздегі жазбалар · {n}', AppLocale.en: 'Recordings in your language · {n}'},
  'aud_lib_empty': {AppLocale.ru: 'Записей пока нет', AppLocale.kk: 'Әзірге жазба жоқ', AppLocale.en: 'No recordings yet'},
  'aud_lib_empty_hint': {AppLocale.ru: 'Они появятся здесь, как только их добавят', AppLocale.kk: 'Қосылған бойда осында пайда болады', AppLocale.en: 'They will appear here as soon as they are added'},
  'aud_lib_loading': {AppLocale.ru: 'Открываем запись…', AppLocale.kk: 'Жазба ашылуда…', AppLocale.en: 'Opening the recording…'},
  'aud_lib_failed': {AppLocale.ru: 'Не удалось открыть запись. Проверьте связь и попробуйте ещё раз.', AppLocale.kk: 'Жазбаны ашу мүмкін болмады. Байланысты тексеріп, қайталап көріңіз.', AppLocale.en: 'Could not open the recording. Check your connection and try again.'},
  // --- Screen 41 · «Магазин» ----------------------------------------------
  'shop_title': {AppLocale.ru: 'Магазин', AppLocale.kk: 'Дүкен', AppLocale.en: 'Shop'},
  'shop_for_your_stage': {AppLocale.ru: 'Для вашего этапа', AppLocale.kk: 'Сіздің кезеңіңізге', AppLocale.en: 'For where you are now'},
  'shop_why_pregnant': {AppLocale.ru: 'Вы ждёте малыша — часы следят за давлением и пульсом, а брелок пригодится позже', AppLocale.kk: 'Сіз бала күтудесіз — сағат қысым мен пульсті бақылайды, брелок кейін керек болады', AppLocale.en: 'You are expecting — the watch follows your blood pressure and pulse; the tracker matters later'},
  'shop_why_baby': {AppLocale.ru: 'Малыш ещё никуда не уходит — брелок пригодится, когда начнёт гулять сам', AppLocale.kk: 'Балаңыз әзірге еш жаққа кетпейді — брелок өзі жүре бастағанда керек болады', AppLocale.en: 'Your baby is not going anywhere yet — the tracker earns its place once they walk'},
  'shop_why_moving': {AppLocale.ru: 'Ребёнок уже ходит сам — брелок показывает, где он', AppLocale.kk: 'Балаңыз өзі жүреді — брелок оның қайда екенін көрсетеді', AppLocale.en: 'Your child walks on their own now — the tracker shows where they are'},
  'shop_why_unknown': {AppLocale.ru: 'Заполните профиль — подскажем, что подойдёт именно вам', AppLocale.kk: 'Профильді толтырыңыз — сізге не қолайлы екенін айтамыз', AppLocale.en: 'Fill in your profile and we will suggest what fits'},
  'shop_item_watch': {AppLocale.ru: 'Смарт-часы Ana-Bala', AppLocale.kk: 'Ana-Bala смарт-сағаты', AppLocale.en: 'Ana-Bala smart watch'},
  'shop_item_tracker': {AppLocale.ru: 'Детский брелок Kid', AppLocale.kk: 'Балаларға арналған Kid брелогы', AppLocale.en: 'Kid tracker'},
  'shop_item_watch_what': {AppLocale.ru: 'Давление, пульс, сон и SOS на запястье', AppLocale.kk: 'Қысым, пульс, ұйқы және SOS', AppLocale.en: 'Blood pressure, pulse, sleep and SOS'},
  'shop_item_tracker_what': {AppLocale.ru: 'Где ребёнок, зоны и кнопка SOS', AppLocale.kk: 'Бала қайда, аймақтар және SOS түймесі', AppLocale.en: 'Where the child is, zones and an SOS button'},
  'shop_wa_note': {AppLocale.ru: 'Заказы принимаем в WhatsApp: подтвердим наличие, цвет и адрес доставки. Оплата при получении.', AppLocale.kk: 'Тапсырыстарды WhatsApp арқылы қабылдаймыз: бар-жоғын, түсін және мекенжайды растаймыз. Төлем — алған кезде.', AppLocale.en: 'We take orders on WhatsApp: we confirm stock, colour and delivery. Pay on delivery.'},
  'shop_order_bundle': {AppLocale.ru: 'Заказать комплект', AppLocale.kk: 'Жинаққа тапсырыс беру', AppLocale.en: 'Order the set'},
  'shop_wa_item': {AppLocale.ru: 'Здравствуйте! Хочу заказать: {item}.', AppLocale.kk: 'Сәлеметсіз бе! Тапсырыс бергім келеді: {item}.', AppLocale.en: 'Hello! I would like to order: {item}.'},
  'shop_saving': {AppLocale.ru: 'Выгода {amount}', AppLocale.kk: 'Үнемдеу {amount}', AppLocale.en: 'You save {amount}'},
  // The live catalogue (frames 08 / 08a). Prices, names and the age band are
  // an operator's now, so the shop has to be able to say where a number came
  // from — and to admit when it is quoting one from memory.
  'shop_order_item': {AppLocale.ru: 'Заказать', AppLocale.kk: 'Тапсырыс беру', AppLocale.en: 'Order'},
  'shop_out_of_stock': {AppLocale.ru: 'Нет в наличии', AppLocale.kk: 'Қоймада жоқ', AppLocale.en: 'Out of stock'},
  'shop_order_backorder': {AppLocale.ru: 'Заказать под заказ', AppLocale.kk: 'Тапсырыс бойынша сұрау', AppLocale.en: 'Ask to backorder'},
  'shop_wa_backorder': {AppLocale.ru: 'Здравствуйте! Хочу заказать под заказ: {item}. Вижу, что сейчас нет в наличии — подскажите сроки, пожалуйста.', AppLocale.kk: 'Сәлеметсіз бе! Тапсырыс бойынша алғым келеді: {item}. Қазір қоймада жоқ екенін көріп тұрмын — мерзімін айтып жіберіңізші.', AppLocale.en: 'Hello! I would like to backorder: {item}. I can see it is out of stock — could you tell me when it will arrive?'},
  'shop_prices_cached': {AppLocale.ru: 'Нет связи с магазином. Цены и наличие — на {date}.', AppLocale.kk: 'Дүкенмен байланыс жоқ. Бағалар мен бар-жоғы — {date} жағдайы бойынша.', AppLocale.en: 'No connection to the shop. Prices and stock are as of {date}.'},
  'shop_prices_approx': {AppLocale.ru: 'Нет связи с магазином — цены ориентировочные. Уточним при заказе.', AppLocale.kk: 'Дүкенмен байланыс жоқ — бағалар шамамен. Тапсырыс кезінде нақтылаймыз.', AppLocale.en: 'No connection to the shop — these prices are approximate. We will confirm when you order.'},
  'shop_age_band': {AppLocale.ru: 'Для детей {from}–{to} мес.', AppLocale.kk: '{from}–{to} айлық балаларға', AppLocale.en: 'For children {from}–{to} months'},
  'shop_age_from': {AppLocale.ru: 'Для детей от {from} мес.', AppLocale.kk: '{from} айдан бастап балаларға', AppLocale.en: 'For children from {from} months'},
  'shop_age_to': {AppLocale.ru: 'Для детей до {to} мес.', AppLocale.kk: '{to} айға дейінгі балаларға', AppLocale.en: 'For children up to {to} months'},
  'shop_match_stage': {AppLocale.ru: 'Подходит вашему этапу', AppLocale.kk: 'Сіздің кезеңіңізге сай', AppLocale.en: 'Suits where you are now'},
  'shop_match_age': {AppLocale.ru: 'Подходит по возрасту ребёнка', AppLocale.kk: 'Балаңыздың жасына сай', AppLocale.en: 'Suits your child’s age'},
  'shop_empty': {AppLocale.ru: 'Не удалось загрузить товары. Напишите нам — подскажем, что есть в наличии.', AppLocale.kk: 'Тауарларды жүктеу мүмкін болмады. Бізге жазыңыз — не бар екенін айтамыз.', AppLocale.en: 'The products could not be loaded. Message us and we will tell you what is in stock.'},
  // --- Screen 34 · «Курс · без комплекта» ---------------------------------
  'crs_contents': {AppLocale.ru: 'Что в курсе', AppLocale.kk: 'Курста не бар', AppLocale.en: 'What is in the course'},
  'crs_free_badge': {AppLocale.ru: 'Бесплатно', AppLocale.kk: 'Тегін', AppLocale.en: 'Free'},
  'crs_watch_free': {AppLocale.ru: 'Посмотреть первый урок', AppLocale.kk: 'Бірінші сабақты көру', AppLocale.en: 'Watch the first lesson'},
  'crs_lessons_n': {AppLocale.ru: '{n} уроков', AppLocale.kk: '{n} сабақ', AppLocale.en: '{n} lessons'},
  // The price card. The комплект includes the course and costs LESS than the
  // course alone — that is the offer, stated plainly rather than buried.
  'crs_price_title': {AppLocale.ru: 'Как получить курс', AppLocale.kk: 'Курсты қалай алуға болады', AppLocale.en: 'How to get the course'},
  'crs_bundle_name': {AppLocale.ru: 'Комплект «Мама и ребёнок»', AppLocale.kk: '«Ана мен бала» жинағы', AppLocale.en: 'The «Mother and child» set'},
  'crs_bundle_what': {AppLocale.ru: 'Часы + брелок + курс целиком', AppLocale.kk: 'Сағат + брелок + толық курс', AppLocale.en: 'Watch + tracker + the whole course'},
  'crs_separate_name': {AppLocale.ru: 'То же по отдельности', AppLocale.kk: 'Бөлек алғанда', AppLocale.en: 'The same, bought separately'},
  'crs_course_only': {AppLocale.ru: 'Только курс', AppLocale.kk: 'Тек курс', AppLocale.en: 'The course alone'},
  'crs_order_wa': {AppLocale.ru: 'Заказать комплект в WhatsApp', AppLocale.kk: 'WhatsApp арқылы жинақ тапсырыс беру', AppLocale.en: 'Order the set on WhatsApp'},
  'crs_buy_course_wa': {AppLocale.ru: 'Купить только курс', AppLocale.kk: 'Тек курсты сатып алу', AppLocale.en: 'Buy the course alone'},
  'crs_already_bought': {AppLocale.ru: 'Уже купили комплект? Напишите нам — откроем доступ по номеру телефона.', AppLocale.kk: 'Жинақты сатып алдыңыз ба? Бізге жазыңыз — телефон нөмірі бойынша ашамыз.', AppLocale.en: 'Already bought the set? Message us and we will open it by phone number.'},
  'crs_wa_course': {AppLocale.ru: 'Здравствуйте! Хочу купить только курс Ма!Ма!.', AppLocale.kk: 'Сәлеметсіз бе! Тек Ма!Ма! курсын сатып алғым келеді.', AppLocale.en: 'Hello! I would like to buy the Ма!Ма! course on its own.'},
  'crs_empty': {AppLocale.ru: 'Уроки скоро появятся', AppLocale.kk: 'Сабақтар жақында пайда болады', AppLocale.en: 'Lessons are coming soon'},

  // --- Screen 39 · «Центр уведомлений» ------------------------------------
  'ntf_title': {AppLocale.ru: 'Уведомления', AppLocale.kk: 'Хабарламалар', AppLocale.en: 'Notifications'},
  'ntf_read_all': {AppLocale.ru: 'Прочитать всё', AppLocale.kk: 'Барлығын оқу', AppLocale.en: 'Mark all read'},
  'ntf_today': {AppLocale.ru: 'Сегодня', AppLocale.kk: 'Бүгін', AppLocale.en: 'Today'},
  'ntf_earlier': {AppLocale.ru: 'Раньше', AppLocale.kk: 'Бұрын', AppLocale.en: 'Earlier'},
  'ntf_empty': {AppLocale.ru: 'Пока ничего не произошло', AppLocale.kk: 'Әзірге ештеңе болған жоқ', AppLocale.en: 'Nothing has happened yet'},
  'ntf_empty_why': {AppLocale.ru: 'Здесь появятся выходы из зон, отметки «всё хорошо», сигналы SOS и сообщения от Ana-Bala.', AppLocale.kk: 'Мұнда аймақтан шығу, «бәрі жақсы» белгілері, SOS сигналдары және Ana-Bala хабарламалары пайда болады.', AppLocale.en: 'Zone crossings, check-ins, SOS signals and messages from Ana-Bala appear here.'},
  // Who a рассылка is from. It stands where a child's name stands on a safety
  // alert, so the two are never confused: one is about her child, the other is
  // us writing to her.
  'ntf_from_team': {AppLocale.ru: 'Ana-Bala', AppLocale.kk: 'Ana-Bala', AppLocale.en: 'Ana-Bala'},
  // The card that cannot be argued with.
  'ntf_emergency_locked': {AppLocale.ru: 'Экстренные отключить нельзя', AppLocale.kk: 'Төтенше хабарламаларды өшіруге болмайды', AppLocale.en: 'Emergency alerts cannot be turned off'},
  'ntf_emergency_why': {AppLocale.ru: 'SOS и выход ребёнка из безопасной зоны придут всегда — даже если всё остальное выключено.', AppLocale.kk: 'SOS және баланың қауіпсіз аймақтан шығуы әрқашан келеді — қалғаны өшірулі болса да.', AppLocale.en: 'An SOS and a child leaving a safe zone always arrive — even with everything else off.'},
  'ntf_configure_rest': {AppLocale.ru: 'Настроить остальные', AppLocale.kk: 'Қалғанын баптау', AppLocale.en: 'Configure the rest'},
  'ntf_ch_emergency': {AppLocale.ru: 'Экстренные', AppLocale.kk: 'Төтенше', AppLocale.en: 'Emergency'},
  'ntf_ch_zones': {AppLocale.ru: 'Зоны и отметки', AppLocale.kk: 'Аймақтар мен белгілер', AppLocale.en: 'Zones and check-ins'},
  'ntf_ch_battery': {AppLocale.ru: 'Заряд браслета', AppLocale.kk: 'Білезік заряды', AppLocale.en: 'Tracker battery'},
  'ntf_ch_reminders': {AppLocale.ru: 'Напоминания', AppLocale.kk: 'Еске салғыштар', AppLocale.en: 'Reminders'},
  'ntf_ch_updates': {AppLocale.ru: 'Новости и курс', AppLocale.kk: 'Жаңалықтар мен курс', AppLocale.en: 'News and the course'},

  // --- Screen 42 · «Мой заказ» --------------------------------------------
  'ord_title': {AppLocale.ru: 'Мой заказ', AppLocale.kk: 'Менің тапсырысым', AppLocale.en: 'My order'},
  'ord_step_placed': {AppLocale.ru: 'Заказ принят', AppLocale.kk: 'Тапсырыс қабылданды', AppLocale.en: 'Order placed'},
  'ord_step_confirmed': {AppLocale.ru: 'Подтверждён', AppLocale.kk: 'Расталды', AppLocale.en: 'Confirmed'},
  'ord_step_shipped': {AppLocale.ru: 'Передан курьеру', AppLocale.kk: 'Курьерге берілді', AppLocale.en: 'With the courier'},
  'ord_step_delivered': {AppLocale.ru: 'Доставлен', AppLocale.kk: 'Жеткізілді', AppLocale.en: 'Delivered'},
  // The headline card. One line, and it is the answer to the question she
  // opened the screen with.
  'ord_now_placed': {AppLocale.ru: 'Заказ принят — скоро подтвердим', AppLocale.kk: 'Тапсырыс қабылданды — жақында растаймыз', AppLocale.en: 'Order placed — we will confirm it shortly'},
  'ord_now_confirmed': {AppLocale.ru: 'Подтверждён — готовим к отправке', AppLocale.kk: 'Расталды — жөнелтуге дайындаудамыз', AppLocale.en: 'Confirmed — getting it ready'},
  'ord_now_shipped': {AppLocale.ru: 'Курьер везёт заказ', AppLocale.kk: 'Курьер тапсырысты әкеле жатыр', AppLocale.en: 'The courier is on the way'},
  'ord_now_delivered': {AppLocale.ru: 'Доставлен', AppLocale.kk: 'Жеткізілді', AppLocale.en: 'Delivered'},
  'ord_now_cancelled': {AppLocale.ru: 'Заказ отменён', AppLocale.kk: 'Тапсырыс тоқтатылды', AppLocale.en: 'Order cancelled'},
  'ord_contents': {AppLocale.ru: 'Что в заказе', AppLocale.kk: 'Тапсырыста не бар', AppLocale.en: 'What is in it'},
  'ord_total': {AppLocale.ru: 'Итого', AppLocale.kk: 'Барлығы', AppLocale.en: 'Total'},
  'ord_qty': {AppLocale.ru: '{n} шт', AppLocale.kk: '{n} дана', AppLocale.en: '{n} pcs'},
  'ord_deliver_to': {AppLocale.ru: 'Доставка: {city}, {address}', AppLocale.kk: 'Жеткізу: {city}, {address}', AppLocale.en: 'Delivery: {city}, {address}'},
  'ord_write': {AppLocale.ru: 'Написать', AppLocale.kk: 'Жазу', AppLocale.en: 'Message us'},
  'ord_cancel': {AppLocale.ru: 'Отменить заказ', AppLocale.kk: 'Тапсырысты тоқтату', AppLocale.en: 'Cancel the order'},
  'ord_cancel_confirm': {AppLocale.ru: 'Отменить заказ?', AppLocale.kk: 'Тапсырысты тоқтату керек пе?', AppLocale.en: 'Cancel the order?'},
  'ord_cancel_body': {AppLocale.ru: 'Мы не будем его собирать. Заказать снова можно в любой момент.', AppLocale.kk: 'Біз оны жинамаймыз. Қайта тапсырыс беруге болады.', AppLocale.en: 'We will not pack it. You can order again at any time.'},
  'ord_cancelled_ok': {AppLocale.ru: 'Заказ отменён', AppLocale.kk: 'Тапсырыс тоқтатылды', AppLocale.en: 'Order cancelled'},
  // Refused because the courier already has it — a different message from a
  // failure, and it needs a different next step.
  'ord_cancel_too_late': {AppLocale.ru: 'Курьер уже забрал заказ. Напишите нам — отменим вручную.', AppLocale.kk: 'Курьер тапсырысты алып кетті. Бізге жазыңыз — қолмен тоқтатамыз.', AppLocale.en: 'The courier already has it. Message us and we will sort it out.'},
  'ord_none': {AppLocale.ru: 'Заказов пока нет', AppLocale.kk: 'Әзірге тапсырыс жоқ', AppLocale.en: 'No orders yet'},
  'ord_none_why': {AppLocale.ru: 'Здесь появится заказ, как только вы его оформите — со статусом доставки и составом.', AppLocale.kk: 'Тапсырыс бергеннен кейін ол осында жеткізу күйімен бірге пайда болады.', AppLocale.en: 'An order appears here once you place one, with its delivery status.'},
  // The case that must not read as «у вас нет заказов».
  'ord_no_phone': {AppLocale.ru: 'Мы не знаем вашего номера', AppLocale.kk: 'Біз сіздің нөміріңізді білмейміз', AppLocale.en: 'We do not know your number'},
  'ord_no_phone_why': {AppLocale.ru: 'Заказы находятся по номеру телефона. Добавьте свой в профиле — и заказ появится здесь.', AppLocale.kk: 'Тапсырыстар телефон нөмірі бойынша табылады. Профильде нөміріңізді қосыңыз.', AppLocale.en: 'Orders are found by phone number. Add yours in your profile.'},
  'ord_add_phone': {AppLocale.ru: 'Добавить номер', AppLocale.kk: 'Нөмір қосу', AppLocale.en: 'Add a number'},
  'ord_failed': {AppLocale.ru: 'Не удалось загрузить заказы', AppLocale.kk: 'Тапсырыстарды жүктеу мүмкін болмады', AppLocale.en: 'Could not load your orders'},

  // --- Screen 20 · «Офлайн» -----------------------------------------------
  'off_no_internet': {AppLocale.ru: 'Нет интернета', AppLocale.kk: 'Интернет жоқ', AppLocale.en: 'No internet'},
  'off_data_from': {AppLocale.ru: 'Данные от {time} · {n} мин назад', AppLocale.kk: 'Дерек {time} · {n} мин бұрын', AppLocale.en: 'Data from {time} · {n} min ago'},
  'off_data_from_h': {AppLocale.ru: 'Данные от {time} · {n} ч назад', AppLocale.kk: 'Дерек {time} · {n} сағ бұрын', AppLocale.en: 'Data from {time} · {n} h ago'},
  'off_no_data': {AppLocale.ru: 'Последних данных нет', AppLocale.kk: 'Соңғы дерек жоқ', AppLocale.en: 'No recent data'},
  'off_what_now': {AppLocale.ru: 'Что можно сделать', AppLocale.kk: 'Не істеуге болады', AppLocale.en: 'What you can do'},
  'off_refresh': {AppLocale.ru: 'Обновить', AppLocale.kk: 'Жаңарту', AppLocale.en: 'Refresh'},
  'off_refresh_failed': {AppLocale.ru: 'Пока не получается. Связь не восстановилась.', AppLocale.kk: 'Әзірге болмайды. Байланыс қалпына келмеді.', AppLocale.en: 'Not yet — the connection is still down.'},
  // The most important line on the sheet: the tracker is on the child's wrist
  // and does not go through this phone.
  'off_act_sos': {AppLocale.ru: 'Кнопка SOS на браслете работает — она не зависит от вашего телефона', AppLocale.kk: 'Білезіктегі SOS түймесі жұмыс істейді — ол сіздің телефоныңызға байланысты емес', AppLocale.en: 'The SOS button on the tracker still works — it does not go through your phone'},
  'off_act_call': {AppLocale.ru: 'Позвонить по номеру из карточки ребёнка', AppLocale.kk: 'Бала картасындағы нөмірге қоңырау шалу', AppLocale.en: 'Call the number on the child’s card'},
  'off_act_read': {AppLocale.ru: 'Читать календари и прививки — они уже сохранены', AppLocale.kk: 'Күнтізбелер мен екпелерді оқу — олар сақталған', AppLocale.en: 'Read the calendars and vaccinations — already saved'},
  'off_act_log': {AppLocale.ru: 'Записывать в дневник — отправится, когда появится связь', AppLocale.kk: 'Күнделікке жазу — байланыс пайда болғанда жіберіледі', AppLocale.en: 'Write in the diary — it sends when the connection returns'},

  // --- Screen 40 · «Семейный доступ» --------------------------------------
  'fam_title': {AppLocale.ru: 'Семейный доступ', AppLocale.kk: 'Отбасылық қолжетімділік', AppLocale.en: 'Family access'},
  'fam_who': {AppLocale.ru: 'Кто видит ребёнка', AppLocale.kk: 'Баланы кім көреді', AppLocale.en: 'Who can see the child'},
  'fam_nobody': {AppLocale.ru: 'Пока никого нет', AppLocale.kk: 'Әзірге ешкім жоқ', AppLocale.en: 'Nobody yet'},
  'fam_nobody_why': {AppLocale.ru: 'Пригласите папу или бабушку — они увидят, где ребёнок и когда пришёл в школу.', AppLocale.kk: 'Әкесін немесе әжесін шақырыңыз — олар баланың қайда екенін көреді.', AppLocale.en: 'Invite a father or a grandmother — they will see where the child is.'},
  'fam_level_viewer': {AppLocale.ru: 'Только смотрит', AppLocale.kk: 'Тек қарайды', AppLocale.en: 'View only'},
  'fam_level_guardian': {AppLocale.ru: 'Может менять', AppLocale.kk: 'Өзгерте алады', AppLocale.en: 'Can change'},
  'fam_level_viewer_hint': {AppLocale.ru: 'Видит карту, зоны и события. Ничего не меняет.', AppLocale.kk: 'Картаны, аймақтарды және оқиғаларды көреді. Ештеңе өзгертпейді.', AppLocale.en: 'Sees the map, zones and events. Changes nothing.'},
  'fam_level_guardian_hint': {AppLocale.ru: 'То же плюс может добавлять зоны и отмечать события.', AppLocale.kk: 'Сол сияқты, оған қоса аймақ қоса алады.', AppLocale.en: 'The same, plus can add zones and log events.'},
  'fam_invite': {AppLocale.ru: 'Пригласить', AppLocale.kk: 'Шақыру', AppLocale.en: 'Invite'},
  'fam_invite_label': {AppLocale.ru: 'Кто это? Например, «Папа»', AppLocale.kk: 'Бұл кім? Мысалы, «Әкесі»', AppLocale.en: 'Who is this? E.g. «Dad»'},
  'fam_invite_ready': {AppLocale.ru: 'Ссылка готова', AppLocale.kk: 'Сілтеме дайын', AppLocale.en: 'Link ready'},
  // The one-shot warning. The server keeps only a hash and cannot show it again.
  'fam_invite_once': {AppLocale.ru: 'Скопируйте её сейчас — показать второй раз мы не сможем. Ссылка работает {n} ч и только один раз.', AppLocale.kk: 'Қазір көшіріп алыңыз — екінші рет көрсете алмаймыз. Сілтеме {n} сағат және бір рет қана жұмыс істейді.', AppLocale.en: 'Copy it now — we cannot show it again. It works for {n} h and once only.'},
  'fam_copy': {AppLocale.ru: 'Скопировать ссылку', AppLocale.kk: 'Сілтемені көшіру', AppLocale.en: 'Copy link'},
  'fam_copied': {AppLocale.ru: 'Ссылка скопирована', AppLocale.kk: 'Сілтеме көшірілді', AppLocale.en: 'Link copied'},
  'fam_open_invites': {AppLocale.ru: 'Ссылки, которыми ещё не воспользовались', AppLocale.kk: 'Әлі пайдаланылмаған сілтемелер', AppLocale.en: 'Links nobody has used yet'},
  'fam_expires_in': {AppLocale.ru: 'осталось {n} ч', AppLocale.kk: '{n} сағат қалды', AppLocale.en: '{n} h left'},
  'fam_revoke': {AppLocale.ru: 'Отозвать', AppLocale.kk: 'Кері қайтару', AppLocale.en: 'Revoke'},
  'fam_remove': {AppLocale.ru: 'Убрать доступ', AppLocale.kk: 'Қолжетімділікті алу', AppLocale.en: 'Remove access'},
  'fam_remove_confirm': {AppLocale.ru: 'Убрать доступ у «{name}»?', AppLocale.kk: '«{name}» қолжетімділігін алу керек пе?', AppLocale.en: 'Remove access for «{name}»?'},
  'fam_remove_body': {AppLocale.ru: 'Он больше не увидит, где ребёнок. Вернуть можно новым приглашением.', AppLocale.kk: 'Ол баланың қайда екенін енді көрмейді. Жаңа шақырумен қайтаруға болады.', AppLocale.en: 'They will no longer see where the child is. A new invitation restores it.'},
  'fam_removed': {AppLocale.ru: 'Доступ убран', AppLocale.kk: 'Қолжетімділік алынды', AppLocale.en: 'Access removed'},
  'fam_revoke_confirm': {AppLocale.ru: 'Отозвать эту ссылку?', AppLocale.kk: 'Бұл сілтемені кері қайтару керек пе?', AppLocale.en: 'Revoke this link?'},
  'fam_revoke_body': {AppLocale.ru: 'Тот, кому вы её отправили, больше не сможет ею воспользоваться.', AppLocale.kk: 'Сіз жібергён адам оны енді пайдалана алмайды.', AppLocale.en: 'Whoever you sent it to will no longer be able to use it.'},
  'fam_revoked': {AppLocale.ru: 'Ссылка отозвана', AppLocale.kk: 'Сілтеме кері қайтарылды', AppLocale.en: 'Link revoked'},
  // The green banner. Shown only while the server's own list says it is true.
  'fam_privacy': {AppLocale.ru: 'Здоровье и цикл не видит никто', AppLocale.kk: 'Денсаулық пен циклді ешкім көрмейді', AppLocale.en: 'Nobody sees your health or your cycle'},
  'fam_privacy_body': {AppLocale.ru: 'Близкие видят только ребёнка: карту, зоны и события. Ваши показатели, дневник и календарь остаются вашими.', AppLocale.kk: 'Жақындарыңыз тек баланы көреді: карта, аймақтар және оқиғалар. Сіздің көрсеткіштеріңіз бен күнделігіңіз сізде қалады.', AppLocale.en: 'Relatives see only the child: the map, the zones and the events. Your readings, diary and calendar stay yours.'},
  'fam_i_see': {AppLocale.ru: 'Вы видите чужого ребёнка', AppLocale.kk: 'Сіз басқа отбасының баласын көресіз', AppLocale.en: 'Children shared with you'},
  'fam_i_see_body': {AppLocale.ru: 'Вас пригласили в {n} семью. Ребёнок появится на вкладке карты.', AppLocale.kk: 'Сізді {n} отбасына шақырды. Бала карта бетінде көрінеді.', AppLocale.en: 'You were invited into {n} family. The child appears on the map tab.'},
  'fam_failed': {AppLocale.ru: 'Не удалось загрузить список', AppLocale.kk: 'Тізімді жүктеу мүмкін болмады', AppLocale.en: 'Could not load the list'},
  'fam_invite_failed': {AppLocale.ru: 'Не удалось создать ссылку', AppLocale.kk: 'Сілтеме жасау мүмкін болмады', AppLocale.en: 'Could not create the link'},
  'fam_refused_expired': {AppLocale.ru: 'Ссылка устарела. Попросите новую — они живут сутки.', AppLocale.kk: 'Сілтеме ескірген. Жаңасын сұраңыз — олар бір тәулік жұмыс істейді.', AppLocale.en: 'The link has expired. Ask for a new one — they last a day.'},
  'fam_refused_used': {AppLocale.ru: 'Этой ссылкой уже воспользовались. Каждая работает один раз.', AppLocale.kk: 'Бұл сілтеме пайдаланылған. Әрқайсысы бір рет жұмыс істейді.', AppLocale.en: 'This link has already been used. Each one works once.'},
  'fam_refused_revoked': {AppLocale.ru: 'Ссылку отозвали.', AppLocale.kk: 'Сілтеме кері қайтарылған.', AppLocale.en: 'The link was revoked.'},
  'fam_refused_own': {AppLocale.ru: 'Это ваша собственная ссылка.', AppLocale.kk: 'Бұл сіздің өз сілтемеңіз.', AppLocale.en: 'This is your own link.'},
  'fam_refused_unknown': {AppLocale.ru: 'Ссылка не подошла.', AppLocale.kk: 'Сілтеме келмеді.', AppLocale.en: 'The link did not work.'},
  // The other side of the invitation: pasting the code you were sent.
  'fam_have_code': {AppLocale.ru: 'У меня есть приглашение', AppLocale.kk: 'Менде шақыру бар', AppLocale.en: 'I have an invitation'},
  'fam_paste_code': {AppLocale.ru: 'Вставьте код из приглашения', AppLocale.kk: 'Шақырудағы кодты қойыңыз', AppLocale.en: 'Paste the code from the invitation'},
  'fam_accept': {AppLocale.ru: 'Принять', AppLocale.kk: 'Қабылдау', AppLocale.en: 'Accept'},
  'fam_accepted': {AppLocale.ru: 'Готово — ребёнок появится на вкладке карты', AppLocale.kk: 'Дайын — бала карта бетінде көрінеді', AppLocale.en: 'Done — the child appears on the map tab'},

  // --- Screens 47/48 · «История дня» -------------------------------------
  'day_history': {AppLocale.ru: 'История дня', AppLocale.kk: 'Күн тарихы', AppLocale.en: 'Day history'},
  'day_calendar': {AppLocale.ru: 'Календарь', AppLocale.kk: 'Күнтізбе', AppLocale.en: 'Calendar'},
  // «3,2 км · 4 точки» — the badge over the route.
  'day_route_badge': {AppLocale.ru: '{d} · {n} точек', AppLocale.kk: '{d} · {n} нүкте', AppLocale.en: '{d} · {n} points'},
  'day_timeline': {AppLocale.ru: 'Что было', AppLocale.kk: 'Не болды', AppLocale.en: 'What happened'},
  'day_left_zone': {AppLocale.ru: 'Вышла из зоны «{zone}»', AppLocale.kk: '«{zone}» аймағынан шықты', AppLocale.en: 'Left «{zone}»'},
  'day_entered_zone': {AppLocale.ru: 'Пришла в зону «{zone}»', AppLocale.kk: '«{zone}» аймағына келді', AppLocale.en: 'Arrived at «{zone}»'},
  // The zone was deleted after the crossing happened. The crossing still did.
  'day_left_unknown': {AppLocale.ru: 'Вышла из зоны', AppLocale.kk: 'Аймақтан шықты', AppLocale.en: 'Left a zone'},
  'day_entered_unknown': {AppLocale.ru: 'Пришла в зону', AppLocale.kk: 'Аймаққа келді', AppLocale.en: 'Arrived at a zone'},
  'day_sos': {AppLocale.ru: 'Нажала кнопку SOS', AppLocale.kk: 'SOS түймесін басты', AppLocale.en: 'Pressed SOS'},
  'day_retention': {AppLocale.ru: 'Маршруты хранятся {n} дней, потом удаляются автоматически', AppLocale.kk: 'Маршруттар {n} күн сақталады, содан кейін автоматты түрде жойылады', AppLocale.en: 'Routes are kept for {n} days, then deleted automatically'},
  'day_simplified': {AppLocale.ru: 'Линия упрощена: {raw} отметок сведены к {n}', AppLocale.kk: 'Сызық жеңілдетілді: {raw} белгі {n} нүктеге сыйды', AppLocale.en: 'Simplified: {raw} fixes drawn as {n} points'},
  'day_empty': {AppLocale.ru: 'В этот день браслет ничего не записал', AppLocale.kk: 'Бұл күні білезік ештеңе жазбаған', AppLocale.en: 'The tracker recorded nothing this day'},
  'day_empty_why': {AppLocale.ru: 'Обычно так бывает, когда браслет был выключен или без связи. Данные появятся, как только он снова выйдет на связь.', AppLocale.kk: 'Әдетте білезік өшірулі болғанда немесе байланыс болмағанда солай болады. Байланыс қалпына келгенде деректер пайда болады.', AppLocale.en: 'Usually the tracker was off or out of range. Data appears once it reconnects.'},
  'day_failed': {AppLocale.ru: 'Не удалось загрузить историю', AppLocale.kk: 'Тарихты жүктеу мүмкін болмады', AppLocale.en: 'Could not load the history'},
  'day_retry': {AppLocale.ru: 'Повторить', AppLocale.kk: 'Қайталау', AppLocale.en: 'Retry'},

  // Screen 48 — one event from the day.
  'sos_event_title': {AppLocale.ru: 'SOS · {time}', AppLocale.kk: 'SOS · {time}', AppLocale.en: 'SOS · {time}'},
  'sos_event_card': {AppLocale.ru: '{name} нажала кнопку SOS', AppLocale.kk: '{name} SOS түймесін басты', AppLocale.en: '{name} pressed the SOS button'},
  'sos_whats_next': {AppLocale.ru: 'Что было дальше', AppLocale.kk: 'Одан кейін не болды', AppLocale.en: 'What happened next'},
  'sos_how_ended': {AppLocale.ru: 'Чем закончилось', AppLocale.kk: 'Немен аяқталды', AppLocale.en: 'How it ended'},
  'sos_out_false': {AppLocale.ru: 'Случайное нажатие', AppLocale.kk: 'Кездейсоқ басу', AppLocale.en: 'Pressed by accident'},
  'sos_out_scared': {AppLocale.ru: 'Испугалась, всё хорошо', AppLocale.kk: 'Қорықты, бәрі жақсы', AppLocale.en: 'Got scared, all fine'},
  'sos_out_help': {AppLocale.ru: 'Нужна была помощь', AppLocale.kk: 'Көмек қажет болды', AppLocale.en: 'Help was needed'},
  'sos_out_unknown': {AppLocale.ru: 'Не удалось выяснить', AppLocale.kk: 'Анықтай алмадық', AppLocale.en: 'Could not find out'},
  'sos_save_mark': {AppLocale.ru: 'Сохранить отметку', AppLocale.kk: 'Белгіні сақтау', AppLocale.en: 'Save'},
  'sos_mark_saved': {AppLocale.ru: 'Отметка сохранена', AppLocale.kk: 'Белгі сақталды', AppLocale.en: 'Saved'},
  'sos_no_events': {AppLocale.ru: 'После сигнала больше ничего не записано', AppLocale.kk: 'Сигналдан кейін ештеңе жазылмаған', AppLocale.en: 'Nothing was recorded after the alert'},

  // --- Zone crossing history (GET /children/:id/events) --------------------
  //
  // The back office could read a child's crossings on «SOS и зоны» and the app
  // could not. These strings are the app's half. Everything here is written to
  // the absorber rule: this list holds enter/exit and nothing else, so it may
  // never be read as «ничего не случилось» — that is why the scope line is
  // shown on every state, not only the empty one.
  'zonehist_open': {AppLocale.ru: 'История зон', AppLocale.kk: 'Аймақтар тарихы', AppLocale.en: 'Zone history'},
  'zonehist_title': {AppLocale.ru: 'История зон: {name}', AppLocale.kk: '{name}: аймақтар тарихы', AppLocale.en: "{name}'s zone history"},
  // Said on every state. An SOS is a person pressing a button; a crossing is a
  // child walking past a boundary. They live in different tables behind
  // different routes, and this screen carries only the second.
  'zonehist_scope': {AppLocale.ru: 'Только входы и выходы из зон. Сигнал SOS — не пересечение зоны, он остаётся в оповещениях.', AppLocale.kk: 'Тек аймаққа кіру мен шығу. SOS сигналы — аймақты кесіп өту емес, ол хабарламаларда қалады.', AppLocale.en: 'Zone entries and exits only. An SOS is not a zone crossing — it stays in Alerts.'},
  'zonehist_empty': {AppLocale.ru: 'Пересечений зон не записано', AppLocale.kk: 'Аймақ шекарасын кесіп өту жазылмаған', AppLocale.en: 'No zone crossings recorded'},
  // Why it may be empty without anything being wrong — and without claiming
  // that nothing happened, which this screen cannot know.
  'zonehist_empty_why': {AppLocale.ru: 'Записи появляются, когда браслет сам пересекает границу зоны. Если зону удалить, её записи удаляются вместе с ней.', AppLocale.kk: 'Жазбалар білезік аймақ шекарасын кесіп өткенде пайда болады. Аймақты жойсаңыз, оның жазбалары да жойылады.', AppLocale.en: 'Records appear when the tracker itself crosses a zone boundary. Deleting a zone deletes its records with it.'},
  // Paired with day_failed. A server that did not answer is not a quiet week.
  'zonehist_failed_why': {AppLocale.ru: 'Сервер не ответил. Это не значит, что пересечений не было.', AppLocale.kk: 'Сервер жауап бермеді. Бұл кесіп өту болмады дегенді білдірмейді.', AppLocale.en: 'The server did not answer. That does not mean there were no crossings.'},
  'zonehist_capped': {AppLocale.ru: 'Показаны последние {n} — более ранние могут остаться на сервере.', AppLocale.kk: 'Соңғы {n} көрсетілген — ертерек жазбалар серверде қалуы мүмкін.', AppLocale.en: 'Showing the last {n} — earlier ones may remain on the server.'},
  // Said rather than approximated. These rows carry a time and a zone name and
  // no coordinates at all, so there is nothing honest to draw on a map here.
  'zonehist_no_coords': {AppLocale.ru: 'В этих записях нет координат — только время и название зоны. Место на карте есть в истории дня.', AppLocale.kk: 'Бұл жазбаларда координаттар жоқ — тек уақыт пен аймақ атауы. Картадағы орын күн тарихында бар.', AppLocale.en: 'These records carry no coordinates — only the time and the zone name. The map is in the day history.'},
  // Which instrument produced the fix that triggered the crossing. Named, not
  // judged: the app says where the position came from and asserts nothing about
  // how close it was.
  'possrc_gps': {AppLocale.ru: 'GPS', AppLocale.kk: 'GPS', AppLocale.en: 'GPS'},
  'possrc_wifi': {AppLocale.ru: 'Wi-Fi', AppLocale.kk: 'Wi-Fi', AppLocale.en: 'Wi-Fi'},
  'possrc_lbs': {AppLocale.ru: 'Вышки связи', AppLocale.kk: 'Байланыс мұнаралары', AppLocale.en: 'Cell towers'},
  'possrc_ble': {AppLocale.ru: 'Bluetooth', AppLocale.kk: 'Bluetooth', AppLocale.en: 'Bluetooth'},

  // Geofence zones management
  'zones_title': {AppLocale.ru: 'Зоны {name}', AppLocale.kk: '{name} аймақтары', AppLocale.en: "{name}'s zones"},
  'zones_empty': {AppLocale.ru: 'Пока нет зон. Добавьте дом, школу или другое безопасное место.', AppLocale.kk: 'Әзірге аймақ жоқ. Үй, мектеп немесе басқа қауіпсіз орын қосыңыз.', AppLocale.en: 'No zones yet. Add home, school, or any safe place.'},
  // How many safe zones a child has, for the Settings list. The count used
  // to be labelled with nav_child ('Ребёнок'), the name of the Child TAB, so
  // the row read '8 г. · 2 · Ребёнок' and the 2 belonged to nothing.
  'child_zone_count': {AppLocale.ru: '{n} зон', AppLocale.kk: '{n} аймақ', AppLocale.en: '{n} zones'},
  'zone_add': {AppLocale.ru: 'Добавить зону', AppLocale.kk: 'Аймақ қосу', AppLocale.en: 'Add zone'},
  'zone_edit': {AppLocale.ru: 'Изменить зону', AppLocale.kk: 'Аймақты өзгерту', AppLocale.en: 'Edit zone'},
  'zone_name_hint': {AppLocale.ru: 'Название зоны', AppLocale.kk: 'Аймақ атауы', AppLocale.en: 'Zone name'},
  'zone_radius': {AppLocale.ru: 'Радиус', AppLocale.kk: 'Радиус', AppLocale.en: 'Radius'},
  'zone_visits': {AppLocale.ru: '{n} посещ.', AppLocale.kk: '{n} рет', AppLocale.en: '{n} visits'},
  'child_gone': {AppLocale.ru: 'Этот ребёнок больше не в списке.', AppLocale.kk: 'Бұл бала тізімде жоқ.', AppLocale.en: 'This child is no longer in your list.'},
  'child_no_dob': {AppLocale.ru: 'Дата рождения не указана', AppLocale.kk: 'Туған күні көрсетілмеген', AppLocale.en: 'No birthday set'},
  'child_battery': {AppLocale.ru: 'Заряд трекера', AppLocale.kk: 'Трекер заряды', AppLocale.en: 'Tracker battery'},
  'child_last_checkin': {AppLocale.ru: 'Последняя отметка', AppLocale.kk: 'Соңғы белгі', AppLocale.en: 'Last check-in'},
  'child_last_activity': {AppLocale.ru: 'Последняя активность', AppLocale.kk: 'Соңғы белсенділік', AppLocale.en: 'Last activity'},
  'child_no_activity': {AppLocale.ru: 'Пока нет данных о ребёнке.', AppLocale.kk: 'Әзірге бала туралы дерек жоқ.', AppLocale.en: 'No activity recorded yet.'},
  'child_zones': {AppLocale.ru: 'Безопасные зоны', AppLocale.kk: 'Қауіпсіз аймақтар', AppLocale.en: 'Safe zones'},
  'child_no_zones': {AppLocale.ru: 'Зоны ещё не созданы.', AppLocale.kk: 'Аймақтар әлі құрылмаған.', AppLocale.en: 'No zones set up yet.'},
  'child_alerts': {AppLocale.ru: 'Оповещения', AppLocale.kk: 'Ескертулер', AppLocale.en: 'Alerts'},
  'zone_type_other': {AppLocale.ru: 'Другое', AppLocale.kk: 'Басқа', AppLocale.en: 'Other'},
  'zone_use_location': {AppLocale.ru: 'Моё текущее место', AppLocale.kk: 'Қазіргі орным', AppLocale.en: 'Use my current location'},
  'zone_pick_on_map': {AppLocale.ru: 'Выбрать на карте', AppLocale.kk: 'Картадан таңдау', AppLocale.en: 'Pick on map'},
  'zone_pick_hint': {AppLocale.ru: 'Нажмите на карту, чтобы выбрать центр зоны', AppLocale.kk: 'Аймақ орталығын таңдау үшін картаны басыңыз', AppLocale.en: 'Tap the map to set the zone centre'},
  'zone_location_set': {AppLocale.ru: 'Место задано', AppLocale.kk: 'Орын белгіленді', AppLocale.en: 'Location set'},
  'zone_meters': {AppLocale.ru: '{m} м', AppLocale.kk: '{m} м', AppLocale.en: '{m} m'},
  'confirm_remove_zone_title': {AppLocale.ru: 'Удалить зону?', AppLocale.kk: 'Аймақты жою керек пе?', AppLocale.en: 'Remove zone?'},
  'confirm_remove_zone_body': {AppLocale.ru: 'Зона «{name}» будет удалена. Оповещения о входе/выходе прекратятся.', AppLocale.kk: '«{name}» аймағы жойылады. Кіру/шығу туралы ескертулер тоқтайды.', AppLocale.en: 'The {name} zone will be removed. Enter/exit alerts for it will stop.'},
  // A device the server would not take. Both say what to DO — somebody
  // holding a tag from another marketplace still wants the service, and a bare
  // refusal costs the customer and the support conversation both.
  // The way out of a «not ours» refusal: the code printed on the box.
  'dev_have_code': {AppLocale.ru: 'У меня есть код', AppLocale.kk: 'Менде код бар', AppLocale.en: 'I have a code'},
  'dev_claim_title': {AppLocale.ru: 'Код с коробки', AppLocale.kk: 'Қораптағы код', AppLocale.en: 'Code from the box'},
  'dev_claim_body': {
    AppLocale.ru: 'Найдите код на коробке или на гарантийном талоне — он подтвердит, что устройство наше, и часы заработают.',
    AppLocale.kk: 'Қораптан немесе кепілдік талонынан кодты табыңыз — ол құрылғының біздікі екенін растайды, сағат жұмыс істей бастайды.',
    AppLocale.en: 'Find the code on the box or the warranty card — it confirms the device is ours and the watch will start working.',
  },
  'dev_claim_hint': {AppLocale.ru: 'Например, KZ-1234', AppLocale.kk: 'Мысалы, KZ-1234', AppLocale.en: 'For example, KZ-1234'},
  'dev_claim_action': {AppLocale.ru: 'Подтвердить', AppLocale.kk: 'Растау', AppLocale.en: 'Confirm'},
  'dev_claim_ok': {AppLocale.ru: 'Готово — устройство подключено.', AppLocale.kk: 'Дайын — құрылғы қосылды.', AppLocale.en: 'Done — the device is connected.'},
  'dev_claim_unknown': {
    AppLocale.ru: 'Такой код не найден. Проверьте, не спутаны ли 0 и O, и попробуйте ещё раз.',
    AppLocale.kk: 'Мұндай код табылмады. 0 мен O-ны шатастырмағаныңызды тексеріп, қайта көріңіз.',
    AppLocale.en: 'No such code. Check whether 0 and O got mixed up, and try again.',
  },
  'dev_claim_taken': {
    AppLocale.ru: 'Этот код уже использован на другом номере. Напишите нам — разберёмся.',
    AppLocale.kk: 'Бұл код басқа нөмірде қолданылған. Бізге жазыңыз — шешеміз.',
    AppLocale.en: 'This code has already been used on another number. Write to us and we will sort it out.',
  },
  'dev_claim_blocked': {
    AppLocale.ru: 'Это устройство заблокировано. Напишите нам, если купили его у нас.',
    AppLocale.kk: 'Бұл құрылғы бұғатталған. Бізден сатып алған болсаңыз, жазыңыз.',
    AppLocale.en: 'This device is blocked. Write to us if you bought it from us.',
  },
  'dev_claim_too_many': {
    AppLocale.ru: 'Слишком много попыток. Попробуйте через час.',
    AppLocale.kk: 'Тым көп әрекет. Бір сағаттан кейін көріңіз.',
    AppLocale.en: 'Too many attempts. Try again in an hour.',
  },
  'dev_claim_offline': {
    AppLocale.ru: 'Нет связи с сервером. Код не потрачен — попробуйте позже.',
    AppLocale.kk: 'Сервермен байланыс жоқ. Код жұмсалмады — кейінірек көріңіз.',
    AppLocale.en: 'No connection. The code was not used — try again later.',
  },
  'dev_not_ours': {
    AppLocale.ru: 'Это устройство не из нашей поставки, поэтому подключить его не получилось. Напишите нам в WhatsApp — разберёмся.',
    AppLocale.kk: 'Бұл құрылғы біздің жеткізілімнен емес, сондықтан қосу мүмкін болмады. WhatsApp-қа жазыңыз — шешеміз.',
    AppLocale.en: 'This device did not come from us, so it could not be connected. Message us on WhatsApp and we will sort it out.',
  },
  'dev_blocked': {
    AppLocale.ru: 'Это устройство заблокировано. Если вы купили его у нас, напишите нам в WhatsApp.',
    AppLocale.kk: 'Бұл құрылғы бұғатталған. Егер оны бізден сатып алсаңыз, WhatsApp-қа жазыңыз.',
    AppLocale.en: 'This device is blocked. If you bought it from us, message us on WhatsApp.',
  },
  'dev_band': {AppLocale.ru: 'Умный браслет', AppLocale.kk: 'Ақылды білезік', AppLocale.en: 'Smart band'},
  'dev_tag': {AppLocale.ru: 'Трекер-метка', AppLocale.kk: 'Трекер-белгі', AppLocale.en: 'Tracker tag'},
  'dev_id_hint': {AppLocale.ru: 'ID устройства', AppLocale.kk: 'Құрылғы ID', AppLocale.en: 'Device ID'},
  'dev_for_child': {AppLocale.ru: 'Чей трекер?', AppLocale.kk: 'Кімнің трекері?', AppLocale.en: "Whose tracker?"},
  'dev_linked_to': {AppLocale.ru: 'Привязан к {name}', AppLocale.kk: '{name} балаға тіркелген', AppLocale.en: 'Linked to {name}'},
  'dev_no_child': {AppLocale.ru: 'Сначала добавьте ребёнка', AppLocale.kk: 'Алдымен бала қосыңыз', AppLocale.en: 'Add a child first'},
  'dev_name_hint': {AppLocale.ru: 'Название', AppLocale.kk: 'Атауы', AppLocale.en: 'Name'},
  'act_save': {AppLocale.ru: 'Сохранить', AppLocale.kk: 'Сақтау', AppLocale.en: 'Save'},
  'act_cancel': {AppLocale.ru: 'Отмена', AppLocale.kk: 'Бас тарту', AppLocale.en: 'Cancel'},
  'act_clear_search': {AppLocale.ru: 'Очистить поиск', AppLocale.kk: 'Іздеуді тазалау', AppLocale.en: 'Clear search'},
  'act_edit': {AppLocale.ru: 'Изменить', AppLocale.kk: 'Өзгерту', AppLocale.en: 'Edit'},
  'act_remove': {AppLocale.ru: 'Удалить', AppLocale.kk: 'Жою', AppLocale.en: 'Remove'},
  'act_add': {AppLocale.ru: 'Добавить', AppLocale.kk: 'Қосу', AppLocale.en: 'Add'},

  // Photos
  'photo_title': {AppLocale.ru: 'Фото', AppLocale.kk: 'Сурет', AppLocale.en: 'Photo'},
  'photo_gallery': {AppLocale.ru: 'Из галереи', AppLocale.kk: 'Галереядан', AppLocale.en: 'Choose from gallery'},
  'photo_camera': {AppLocale.ru: 'Сделать фото', AppLocale.kk: 'Сурет түсіру', AppLocale.en: 'Take a photo'},
  'photo_remove': {AppLocale.ru: 'Удалить фото', AppLocale.kk: 'Суретті жою', AppLocale.en: 'Remove photo'},
  'photo_add': {AppLocale.ru: 'Добавить фото', AppLocale.kk: 'Сурет қосу', AppLocale.en: 'Add photo'},

  // Error fallback — what replaces a screen that failed to build. Plain
  // language, no apology, and one action that helps.
  'err_title': {
    AppLocale.ru: 'Этот экран не открылся',
    AppLocale.kk: 'Бұл экран ашылмады',
    AppLocale.en: 'This screen didn’t open'
  },
  'err_body': {
    AppLocale.ru: 'Ваши данные на месте. Вернитесь на главный экран и попробуйте ещё раз.',
    AppLocale.kk: 'Деректеріңіз сақталған. Басты бетке оралып, қайта көріңіз.',
    AppLocale.en: 'Your data is safe. Go back to the main screen and try again.'
  },
  'err_back': {
    AppLocale.ru: 'На главный экран',
    AppLocale.kk: 'Басты бетке',
    AppLocale.en: 'Back to the main screen'
  },
  'err_details': {
    AppLocale.ru: 'Технические детали',
    AppLocale.kk: 'Техникалық мәліметтер',
    AppLocale.en: 'Technical details'
  },

  // Settings
  'settings_title': {AppLocale.ru: 'Настройки', AppLocale.kk: 'Параметрлер', AppLocale.en: 'Settings'},
  'set_profile': {AppLocale.ru: 'Профиль', AppLocale.kk: 'Профиль', AppLocale.en: 'Profile'},
  'set_edit_profile': {AppLocale.ru: 'Изменить профиль', AppLocale.kk: 'Профильді өзгерту', AppLocale.en: 'Edit profile'},
  'set_language': {AppLocale.ru: 'Язык', AppLocale.kk: 'Тіл', AppLocale.en: 'Language'},
  'set_children': {AppLocale.ru: 'Дети', AppLocale.kk: 'Балалар', AppLocale.en: 'Children'},
  'set_devices': {AppLocale.ru: 'Устройства', AppLocale.kk: 'Құрылғылар', AppLocale.en: 'Devices'},
  'set_no_devices': {AppLocale.ru: 'Нет устройств', AppLocale.kk: 'Құрылғылар жоқ', AppLocale.en: 'No devices yet'},
  'set_notifications': {AppLocale.ru: 'Уведомления', AppLocale.kk: 'Хабарламалар', AppLocale.en: 'Notifications'},
  // This switch is the master gate for every NON-emergency notification (zones,
  // check-ins, battery) — it never touches SOS. It used to read «Оповещения о
  // входе и выходе из зон», which said "zones" while it silenced everything,
  // an SOS included. See AppController.shouldDeliverAlert.
  'set_notifications_sub': {AppLocale.ru: 'Все, кроме экстренных: SOS придёт всегда', AppLocale.kk: 'Шұғылдан басқасы: SOS әрқашан келеді', AppLocale.en: 'All but emergencies: SOS always arrives'},
  'set_data': {AppLocale.ru: 'Данные', AppLocale.kk: 'Деректер', AppLocale.en: 'Data'},
  'backup_never': {AppLocale.ru: 'Резервной копии ещё не было', AppLocale.kk: 'Сақтық көшірме әлі жасалмаған', AppLocale.en: 'Never backed up yet'},
  'backup_last': {AppLocale.ru: 'Последняя копия: {ago}', AppLocale.kk: 'Соңғы көшірме: {ago}', AppLocale.en: 'Last backed up {ago}'},
  'backup_stale': {AppLocale.ru: 'Копия устарела ({ago}) — стоит обновить', AppLocale.kk: 'Көшірме ескірген ({ago}) — жаңарту қажет', AppLocale.en: 'Backup is old ({ago}) — worth refreshing'},
  'journey_title': {AppLocale.ru: 'Ваш путь', AppLocale.kk: 'Сіздің жолыңыз', AppLocale.en: 'Your journey'},
  'journey_sub': {AppLocale.ru: 'Итоги всего, что вы отслеживали', AppLocale.kk: 'Барлық бақылауыңыздың қорытындысы', AppLocale.en: 'Totals across everything you\'ve tracked'},
  'journey_empty': {AppLocale.ru: 'Пока нечего показать. Начните что-нибудь отслеживать!', AppLocale.kk: 'Әзірге көрсететін ештеңе жоқ. Бірдеңе бақылай бастаңыз!', AppLocale.en: 'Nothing to show yet. Start tracking something!'},
  'journey_days': {AppLocale.ru: 'дней отмечено', AppLocale.kk: 'күн белгіленді', AppLocale.en: 'days logged'},
  'journey_cycles': {AppLocale.ru: 'циклов', AppLocale.kk: 'цикл', AppLocale.en: 'cycles tracked'},
  'journey_notes': {AppLocale.ru: 'заметок', AppLocale.kk: 'ескертпе', AppLocale.en: 'notes'},
  'journey_kicks': {AppLocale.ru: 'сессий шевелений', AppLocale.kk: 'тебіну сессиясы', AppLocale.en: 'kick sessions'},
  'journey_contractions': {AppLocale.ru: 'сессий схваток', AppLocale.kk: 'толғақ сессиясы', AppLocale.en: 'contraction sessions'},
  'journey_appointments': {AppLocale.ru: 'напоминаний', AppLocale.kk: 'еске салғыш', AppLocale.en: 'appointments'},
  'journey_weights': {AppLocale.ru: 'записей веса', AppLocale.kk: 'салмақ жазбасы', AppLocale.en: 'weight entries'},
  'journey_water': {AppLocale.ru: 'стаканов воды', AppLocale.kk: 'стакан су', AppLocale.en: 'glasses of water'},
  'journey_doses': {AppLocale.ru: 'приёмов витаминов', AppLocale.kk: 'дәрумен қабылдау', AppLocale.en: 'doses taken'},
  'set_export': {AppLocale.ru: 'Экспорт данных', AppLocale.kk: 'Деректерді экспорттау', AppLocale.en: 'Export data'},
  'set_export_sub': {AppLocale.ru: 'Резервная копия в формате JSON', AppLocale.kk: 'JSON форматындағы сақтық көшірме', AppLocale.en: 'A JSON backup of your data'},
  // Say what is IN the file, not only what is absent. It carries the child's
  // name and date of birth and the exact coordinates of home and school — the
  // most sensitive thing this app holds — and it is about to go on the
  // clipboard, from where it can be pasted into any messenger. "Keep it
  // somewhere safe" is not enough for someone to judge where that is.
  'set_export_hint': {AppLocale.ru: 'В файле — ваш профиль и телефоны, имя и дата рождения ребёнка, координаты ваших зон (дом, школа) и история здоровья. Показания браслета не включены. Храните файл как личный документ и не пересылайте в мессенджерах.', AppLocale.kk: 'Файлда — профиліңіз бен телефондарыңыз, баланың аты мен туған күні, аймақтарыңыздың координаттары (үй, мектеп) және денсаулық тарихы. Білезік көрсеткіштері кірмейді. Файлды жеке құжат ретінде сақтаңыз, мессенджерлерде жібермеңіз.', AppLocale.en: 'This file holds your profile and phone numbers, your child’s name and date of birth, the coordinates of your zones (home, school) and your health history. Band readings are not included. Keep it like a personal document — avoid sending it through messengers.'},
  // "Use my current location" failing silently would leave the zone centred on
  // somewhere she has never been, and the alerts would be about that place.
  // The lesson player. Never names a hosting provider: which store the file
  // sits in is our business, not something the user should have to read.
  'lesson_play_failed': {AppLocale.ru: 'Не удалось воспроизвести урок. Проверьте соединение и попробуйте ещё раз.', AppLocale.kk: 'Сабақты ойнату мүмкін болмады. Байланысты тексеріп, қайталап көріңіз.', AppLocale.en: 'Could not play this lesson. Check your connection and try again.'},
  'lesson_play': {AppLocale.ru: 'Воспроизвести', AppLocale.kk: 'Ойнату', AppLocale.en: 'Play'},
  'lesson_pause': {AppLocale.ru: 'Пауза', AppLocale.kk: 'Кідірту', AppLocale.en: 'Pause'},
  'zone_loc_denied': {AppLocale.ru: 'Нужен доступ к геолокации, чтобы поставить зону по вашему месту. Отметьте точку на карте или разрешите доступ.', AppLocale.kk: 'Аймақты орналасқан жеріңіз бойынша қою үшін геолокацияға рұқсат керек. Картадан нүкте белгілеңіз немесе рұқсат беріңіз.', AppLocale.en: 'Location access is needed to centre the zone on you. Pick a point on the map, or allow access.'},
  'zone_loc_denied_forever': {AppLocale.ru: 'Доступ к геолокации запрещён. Включите его в настройках телефона или отметьте точку на карте вручную.', AppLocale.kk: 'Геолокацияға тыйым салынған. Оны телефон параметрлерінде қосыңыз немесе картадан нүктені қолмен белгілеңіз.', AppLocale.en: 'Location access is blocked. Turn it on in your phone settings, or pick the point on the map by hand.'},
  'zone_loc_failed': {AppLocale.ru: 'Не удалось определить местоположение. Попробуйте у окна или отметьте точку на карте.', AppLocale.kk: 'Орналасқан жерді анықтау мүмкін болмады. Терезе жанында көріңіз немесе картадан нүкте белгілеңіз.', AppLocale.en: 'Could not get your location. Try near a window, or pick the point on the map.'},
  // Location is off for the whole phone — a different switch from the app's
  // own permission, so the instruction has to name the right one.
  'zone_loc_off': {AppLocale.ru: 'Геолокация выключена в настройках телефона. Включите её или отметьте точку на карте.', AppLocale.kk: 'Геолокация телефон параметрлерінде өшірулі. Оны қосыңыз немесе картадан нүкте белгілеңіз.', AppLocale.en: 'Location is turned off in your phone settings. Turn it on, or pick the point on the map.'},
  'set_erase': {AppLocale.ru: 'Удалить все данные', AppLocale.kk: 'Барлық деректі жою', AppLocale.en: 'Erase all data'},
  'set_erase_sub': {AppLocale.ru: 'Стереть всё с этого телефона и начать заново', AppLocale.kk: 'Осы телефондағының бәрін өшіріп, қайта бастау', AppLocale.en: 'Wipe everything from this phone and start over'},
  'set_erase_title': {AppLocale.ru: 'Удалить все данные?', AppLocale.kk: 'Барлық дерек жойылсын ба?', AppLocale.en: 'Erase all data?'},
  'set_erase_body': {AppLocale.ru: 'С телефона будут стёрты ваш профиль, дети и их зоны, календарь, вес, лекарства, приёмы и вся история. Восстановить их можно будет только из резервной копии. Приложение вернётся к первому запуску.', AppLocale.kk: 'Телефоннан профиліңіз, балалар мен олардың аймақтары, күнтізбе, салмақ, дәрілер, қабылдаулар және бүкіл тарих өшіріледі. Оларды тек сақтық көшірмеден қалпына келтіруге болады. Қосымша бастапқы күйге оралады.', AppLocale.en: 'Your profile, children and their zones, calendar, weight, medications, appointments and all history will be wiped from this phone. Only a backup can bring them back. The app returns to first-run.'},
  'set_erased': {AppLocale.ru: 'Все данные удалены', AppLocale.kk: 'Барлық дерек жойылды', AppLocale.en: 'All data erased'},
  // The phone is wiped either way. Saying "all data erased" when the server
  // copy is still there would be exactly the false promise this replaced.
  'set_erased_local_only': {
    AppLocale.ru: 'Данные удалены с телефона. Копию на сервере удалить не удалось — '
        'повторите, когда появится связь.',
    AppLocale.kk: 'Деректер телефоннан жойылды. Сервердегі көшірмені жою мүмкін болмады — '
        'байланыс пайда болғанда қайталаңыз.',
    AppLocale.en: 'Erased from this phone. The copy on the server could not be removed — '
        'please try again when you are online.'
  },
  'set_import_confirm_title': {AppLocale.ru: 'Заменить все данные?', AppLocale.kk: 'Барлық деректі ауыстыру керек пе?', AppLocale.en: 'Replace all your data?'},
  'set_import_confirm_body': {AppLocale.ru: 'Импорт заменит всё, что сейчас в приложении: профиль, детей, зоны, календарь и историю. Текущие данные восстановить не получится.', AppLocale.kk: 'Импорт қосымшадағының бәрін ауыстырады: профиль, балалар, аймақтар, күнтізбе және тарих. Ағымдағы деректерді қалпына келтіру мүмкін болмайды.', AppLocale.en: 'Importing replaces everything in the app: your profile, children, zones, calendar and history. What is here now cannot be recovered.'},
  'set_import_confirm_cta': {AppLocale.ru: 'Заменить', AppLocale.kk: 'Ауыстыру', AppLocale.en: 'Replace'},
  'set_export_copy': {AppLocale.ru: 'Копировать', AppLocale.kk: 'Көшіру', AppLocale.en: 'Copy'},
  'set_export_copied': {AppLocale.ru: 'Резервная копия скопирована', AppLocale.kk: 'Сақтық көшірме көшірілді', AppLocale.en: 'Backup copied to clipboard'},
  'set_export_save': {
    AppLocale.ru: 'Сохранить файл',
    AppLocale.kk: 'Файлды сақтау',
    AppLocale.en: 'Save the file'
  },
  'set_export_failed': {
    AppLocale.ru: 'Не удалось сохранить файл. Попробуйте ещё раз.',
    AppLocale.kk: 'Файлды сақтау мүмкін болмады. Қайталап көріңіз.',
    AppLocale.en: 'The file could not be saved. Please try again.'
  },
  'set_export_subject': {
    AppLocale.ru: 'Резервная копия Ana-Bala',
    AppLocale.kk: 'Ana-Bala сақтық көшірмесі',
    AppLocale.en: 'Ana-Bala backup'
  },
  'set_import': {AppLocale.ru: 'Импорт данных', AppLocale.kk: 'Деректерді импорттау', AppLocale.en: 'Import data'},
  'set_import_sub': {AppLocale.ru: 'Восстановить из резервной копии', AppLocale.kk: 'Сақтық көшірмеден қалпына келтіру', AppLocale.en: 'Restore from a backup'},
  'set_import_warn': {AppLocale.ru: 'Импорт заменит все текущие данные.', AppLocale.kk: 'Импорт барлық ағымдағы деректерді ауыстырады.', AppLocale.en: 'Importing replaces all your current data.'},
  'set_import_hint': {AppLocale.ru: 'Вставьте JSON резервной копии сюда', AppLocale.kk: 'Мұнда JSON сақтық көшірмесін қойыңыз', AppLocale.en: 'Paste your backup JSON here'},
  'set_import_apply': {AppLocale.ru: 'Импортировать', AppLocale.kk: 'Импорттау', AppLocale.en: 'Import'},
  'set_import_ok': {AppLocale.ru: 'Данные восстановлены', AppLocale.kk: 'Деректер қалпына келтірілді', AppLocale.en: 'Data restored'},
  // Most of the file came back, some of it could not be read. Saying plain
  // "restored" would leave her believing entries that are gone were recovered.
  'set_import_partial': {
    AppLocale.ru: 'Данные восстановлены, но {n} записей прочитать не удалось',
    AppLocale.kk: 'Деректер қалпына келтірілді, бірақ {n} жазбаны оқу мүмкін болмады',
    AppLocale.en: 'Data restored, but {n} entries could not be read'
  },
  'set_import_fail': {AppLocale.ru: 'Не удалось прочитать резервную копию', AppLocale.kk: 'Сақтық көшірмені оқу мүмкін болмады', AppLocale.en: "Couldn't read that backup"},
  'set_about': {AppLocale.ru: 'О приложении', AppLocale.kk: 'Қолданба туралы', AppLocale.en: 'About'},
  'set_about_body': {
    AppLocale.ru: 'Ana-Bala — уход за беременностью и безопасность ребёнка. Не является медицинским прибором.',
    AppLocale.kk: 'Ana-Bala — жүктілікке қамқорлық және бала қауіпсіздігі. Медициналық құрал емес.',
    AppLocale.en: 'Ana-Bala — pregnancy care and child safety. Not a medical device.'
  },
  'set_version': {AppLocale.ru: 'Версия', AppLocale.kk: 'Нұсқа', AppLocale.en: 'Version'},

  // ---- Legal: privacy policy & terms (legal_*) ----
  // ---- Help & support (help_*) ----
  'set_help': {AppLocale.ru: 'Помощь и поддержка', AppLocale.kk: 'Көмек және қолдау', AppLocale.en: 'Help & support'},
  'help_title': {AppLocale.ru: 'Помощь и поддержка', AppLocale.kk: 'Көмек және қолдау', AppLocale.en: 'Help & support'},
  'help_faq': {AppLocale.ru: 'Частые вопросы', AppLocale.kk: 'Жиі қойылатын сұрақтар', AppLocale.en: 'Frequently asked'},
  'help_q1_q': {AppLocale.ru: 'Как работает трекер ребёнка?', AppLocale.kk: 'Бала трекері қалай жұмыс істейді?', AppLocale.en: 'How does the child tracker work?'},
  'help_q1_a': {AppLocale.ru: 'Когда трекер привязан и на связи, приложение показывает, где находится ребёнок, и предупреждает о выходе из безопасных зон.', AppLocale.kk: 'Трекер байланып, байланыста болғанда қолданба баланың қайда екенін көрсетеді және қауіпсіз аймақтан шыққанда ескертеді.', AppLocale.en: 'When a tracker is linked and connected, the app shows where your child is and alerts you when they leave a safe zone.'},
  'help_q2_q': {AppLocale.ru: 'Насколько точны показатели здоровья?', AppLocale.kk: 'Денсаулық көрсеткіштері қаншалықты дәл?', AppLocale.en: 'How accurate are the health readings?'},
  'help_q2_a': {AppLocale.ru: 'Данные носят справочный характер и не заменяют врача. При тревожных признаках сразу обращайтесь к врачу.', AppLocale.kk: 'Деректер анықтамалық сипатта және дәрігердің орнын баспайды. Қауіпті белгілерде дереу дәрігерге жүгініңіз.', AppLocale.en: 'Readings are for reference and do not replace a doctor. See a doctor promptly if you have warning signs.'},
  'help_q3_q': {AppLocale.ru: 'Где хранятся мои данные?', AppLocale.kk: 'Деректерім қайда сақталады?', AppLocale.en: 'Where is my data stored?'},
  'help_q3_a': {AppLocale.ru: 'По умолчанию на вашем устройстве. Резервную копию можно выгрузить в разделе «Данные».', AppLocale.kk: 'Әдепкі бойынша құрылғыңызда. Сақтық көшірмені «Деректер» бөлімінде шығаруға болады.', AppLocale.en: 'On your device by default. You can export a backup in the “Data” section.'},
  'help_q4_q': {AppLocale.ru: 'Как удалить аккаунт и данные?', AppLocale.kk: 'Аккаунт пен деректерді қалай жоюға болады?', AppLocale.en: 'How do I delete my account and data?'},
  // The Kazakh line is a navigation instruction, so three things had to be true
  // of it and none were:
  //   * «Баптаулар» is not what the screen is called — `settings_title` kk is
  //     «Параметрлер», which is also what every other Kazakh string says. She
  //     was being sent to a menu the app does not have.
  //   * the item is labelled «Барлық деректі жою» (`set_erase`), not «өшіру».
  //   * U+2192 «→» is NOT in Rubik.ttf, and Rubik is the whole Kazakh font
  //     stack (DsFont.bodyFor/displayFor + the single-entry fallback). The
  //     arrow is the one character in this sentence she cannot be shown, in
  //     the middle of the instruction telling her which way to go. «›» (U+203A)
  //     is in the cmap; English already uses it in `rem_manage_hint`.
  'help_q4_a': {AppLocale.ru: 'Откройте «Настройки → Данные → Стереть все данные». Это удалит данные с устройства и с сервера.', AppLocale.kk: '«Параметрлер › Деректер › Барлық деректі жою» бөліміне өтіңіз. Бұл деректерді құрылғыдан және серверден жояды.', AppLocale.en: 'Go to Settings → Data → Erase all data. This removes your data from the device and the server.'},
  'help_contact_section': {AppLocale.ru: 'Связь с нами', AppLocale.kk: 'Бізбен байланыс', AppLocale.en: 'Get in touch'},
  'help_contact': {AppLocale.ru: 'Написать в поддержку', AppLocale.kk: 'Қолдауға жазу', AppLocale.en: 'Contact support'},

  // ---- Курс Ма!Ма! — the lessons the комплект pays for --------------------
  'course_title': {AppLocale.ru: 'Курс Ма!Ма!', AppLocale.kk: 'Ма!Ма! курсы', AppLocale.en: 'Ma!Ma! course'},
  'course_entry_sub': {AppLocale.ru: 'Уроки для мам — входят в комплект', AppLocale.kk: 'Аналарға арналған сабақтар — жинаққа кіреді', AppLocale.en: 'Lessons for mothers — included with the bundle'},
  'course_locked_title': {
    AppLocale.ru: 'Курс входит в комплект',
    AppLocale.kk: 'Курс жинаққа кіреді',
    AppLocale.en: 'The course comes with the bundle'
  },
  'course_locked_body': {
    AppLocale.ru: 'Уроки Ма!Ма! открываются вместе с комплектом «Мама и ребёнок» — часы и брелок. Если вы уже купили комплект, напишите нам: доступ откроем по номеру телефона.',
    AppLocale.kk: 'Ма!Ма! сабақтары «Мама и ребёнок» жинағымен бірге ашылады — сағат пен брелок. Егер жинақты сатып алған болсаңыз, бізге жазыңыз: телефон нөмірі бойынша ашамыз.',
    AppLocale.en: 'The Ma!Ma! lessons come with the «Mother and child» bundle — the watch and the tag. If you have already bought it, message us and we will open access by phone number.'
  },
  // The button under that paragraph. It told her to message us and gave her no
  // way to — the whole pitch for a 39 000 ₸ комплект dead-ending on its last
  // line.
  // The in-app player, and what to say when it cannot run.
  'course_open_youtube': {AppLocale.ru: 'Открыть на YouTube', AppLocale.kk: 'YouTube-та ашу', AppLocale.en: 'Open on YouTube'},
  'course_player_unavailable': {
    AppLocale.ru: 'Видео не удалось открыть здесь. Его можно посмотреть на YouTube — урок тот же.',
    AppLocale.kk: 'Бейнені осында ашу мүмкін болмады. Оны YouTube-та көруге болады — сабақ сол.',
    AppLocale.en: 'The video could not open here. You can watch it on YouTube — it is the same lesson.',
  },
  'course_bad_link': {
    AppLocale.ru: 'Ссылка на этот урок не открывается. Мы уже знаем об этом — напишите нам, если это срочно.',
    AppLocale.kk: 'Бұл сабақтың сілтемесі ашылмайды. Бізге белгілі — шұғыл болса, жазыңыз.',
    AppLocale.en: 'The link for this lesson does not open. We know about it — message us if it is urgent.',
  },
  // Where she got to. {done}/{total} rather than a built string, because the
  // word order is not the same in all three.
  'course_progress_of': {
    AppLocale.ru: 'Пройдено {done} из {total}',
    AppLocale.kk: '{total} сабақтың {done} өтілді',
    AppLocale.en: '{done} of {total} watched',
  },
  'course_entry_owned': {
    AppLocale.ru: 'Доступ открыт — начните первый урок',
    AppLocale.kk: 'Қолжетімді — бірінші сабақтан бастаңыз',
    AppLocale.en: 'Yours — start the first lesson',
  },
  'course_continue': {AppLocale.ru: 'Продолжить', AppLocale.kk: 'Жалғастыру', AppLocale.en: 'Continue'},
  'course_start': {AppLocale.ru: 'Начать', AppLocale.kk: 'Бастау', AppLocale.en: 'Start'},
  'course_resumed_at': {
    AppLocale.ru: 'Продолжаем с {time}',
    AppLocale.kk: '{time} уақытынан жалғастырамыз',
    AppLocale.en: 'Resuming from {time}',
  },
  'course_ask_access': {
    AppLocale.ru: 'Написать в WhatsApp',
    AppLocale.kk: 'WhatsApp-қа жазу',
    AppLocale.en: 'Message us on WhatsApp',
  },
  // What the chat opens with, so staff know what she is asking about without
  // her having to explain.
  'course_wa_text': {
    AppLocale.ru: 'Здравствуйте! Хочу открыть курс Ма!Ма! в приложении Ana-Bala.',
    AppLocale.kk: 'Сәлеметсіз бе! Ana-Bala қосымшасында Ма!Ма! курсын ашқым келеді.',
    AppLocale.en: 'Hello! I would like access to the Ma!Ma! course in the Ana-Bala app.',
  },
  'course_empty': {
    AppLocale.ru: 'Уроки скоро появятся. Доступ у вас уже есть — мы добавляем их по одному.',
    AppLocale.kk: 'Сабақтар жақында қосылады. Қолжетімділік сізде бар — біз оларды бір-бірлеп қосып жатырмыз.',
    AppLocale.en: 'Lessons are coming. You already have access — we add them one at a time.'
  },
  'course_open_failed': {
    AppLocale.ru: 'Не удалось открыть видео. Проверьте, установлен ли YouTube.',
    AppLocale.kk: 'Бейнені ашу мүмкін болмады. YouTube орнатылғанын тексеріңіз.',
    AppLocale.en: 'Could not open the video. Check that YouTube is installed.'
  },
  'help_email_subject': {AppLocale.ru: 'Вопрос по приложению Ana-Bala', AppLocale.kk: 'Ana-Bala қолданбасы бойынша сұрақ', AppLocale.en: 'Question about Ana-Bala'},
  'help_report': {AppLocale.ru: 'Сообщить о проблеме', AppLocale.kk: 'Ақаулық туралы хабарлау', AppLocale.en: 'Report a problem'},
  'help_report_sub': {AppLocale.ru: 'Опишите, что пошло не так', AppLocale.kk: 'Не болғанын сипаттаңыз', AppLocale.en: 'Tell us what went wrong'},
  'help_report_subject': {AppLocale.ru: 'Проблема в приложении Ana-Bala', AppLocale.kk: 'Ana-Bala қолданбасындағы ақаулық', AppLocale.en: 'Problem in Ana-Bala'},
  'help_report_diag': {AppLocale.ru: 'Тех. данные', AppLocale.kk: 'Техникалық деректер', AppLocale.en: 'Diagnostics'},
  'help_share': {AppLocale.ru: 'Поделиться приложением', AppLocale.kk: 'Қолданбамен бөлісу', AppLocale.en: 'Share the app'},
  'help_share_sub': {AppLocale.ru: 'Расскажите близким', AppLocale.kk: 'Жақындарыңызға айтыңыз', AppLocale.en: 'Tell someone close to you'},
  'help_share_text': {AppLocale.ru: 'Ana-Bala — спокойный уход за беременностью и безопасность ребёнка в одном приложении.', AppLocale.kk: 'Ana-Bala — жүктілікке қамқорлық пен бала қауіпсіздігі бір қолданбада.', AppLocale.en: 'Ana-Bala — calm pregnancy care and child safety in one app.'},
  'help_emergency_note': {AppLocale.ru: 'Поддержка — не служба экстренной помощи. При угрозе жизни звоните 103 или 112.', AppLocale.kk: 'Қолдау — жедел жәрдем қызметі емес. Өмірге қауіп төнгенде 103 немесе 112-ге қоңырау шалыңыз.', AppLocale.en: 'Support is not an emergency service. If life is at risk, call 103 or 112.'},
  // Brand line at the foot of Help — the name is a proper noun, identical in
  // every locale; through l10n only so no user-facing text bypasses it.
  'help_app_line': {AppLocale.ru: 'Ana-Bala · {v}', AppLocale.kk: 'Ana-Bala · {v}', AppLocale.en: 'Ana-Bala · {v}'},

  // Cry analysis — record a short clip, get the likely reason + advice.
  'cry_title': {AppLocale.ru: 'Почему малыш плачет', AppLocale.kk: 'Бала неге жылайды', AppLocale.en: 'Why is baby crying'},
  'cry_intro': {AppLocale.ru: 'Запишите 5 секунд плача — приложение подскажет наиболее вероятную причину. Это подсказка, а не диагноз.', AppLocale.kk: 'Жылаудың 5 секундын жазыңыз — қолданба ықтимал себебін ұсынады. Бұл кеңес, диагноз емес.', AppLocale.en: 'Record 5 seconds of crying and the app will suggest the most likely reason. It’s a hint, not a diagnosis.'},
  'cry_record': {AppLocale.ru: 'Записать плач', AppLocale.kk: 'Жылауды жазу', AppLocale.en: 'Record the cry'},
  'cry_recording': {AppLocale.ru: 'Слушаю…', AppLocale.kk: 'Тыңдап тұрмын…', AppLocale.en: 'Listening…'},
  'cry_analyzing': {AppLocale.ru: 'Анализирую…', AppLocale.kk: 'Талдап жатырмын…', AppLocale.en: 'Analysing…'},
  'cry_again': {AppLocale.ru: 'Записать ещё раз', AppLocale.kk: 'Қайта жазу', AppLocale.en: 'Record again'},
  'cry_result_title': {AppLocale.ru: 'Вероятная причина', AppLocale.kk: 'Ықтимал себеп', AppLocale.en: 'Likely reason'},
  'cry_confidence': {AppLocale.ru: 'Уверенность {n}%', AppLocale.kk: 'Сенімділік {n}%', AppLocale.en: 'Confidence {n}%'},
  'cry_mic_denied': {AppLocale.ru: 'Нет доступа к микрофону. Разрешите запись в настройках, чтобы услышать подсказку.', AppLocale.kk: 'Микрофонға рұқсат жоқ. Кеңес алу үшін жазуды баптауларда рұқсат етіңіз.', AppLocale.en: 'No microphone access. Allow recording in settings to get a hint.'},
  'cry_error': {AppLocale.ru: 'Не удалось разобрать запись. Попробуйте ещё раз в тишине.', AppLocale.kk: 'Жазбаны тану мүмкін болмады. Тыныштықта қайта көріңіз.', AppLocale.en: 'Couldn’t make sense of the recording. Try again somewhere quiet.'},
  'cry_reason_hungry': {AppLocale.ru: 'Голод', AppLocale.kk: 'Аштық', AppLocale.en: 'Hunger'},
  'cry_reason_tired': {AppLocale.ru: 'Усталость', AppLocale.kk: 'Шаршау', AppLocale.en: 'Tiredness'},
  'cry_reason_belly_pain': {AppLocale.ru: 'Боль в животе', AppLocale.kk: 'Іш ауруы', AppLocale.en: 'Belly pain'},
  'cry_reason_discomfort': {AppLocale.ru: 'Дискомфорт', AppLocale.kk: 'Ыңғайсыздық', AppLocale.en: 'Discomfort'},
  'cry_reason_burping': {AppLocale.ru: 'Газы / срыгивание', AppLocale.kk: 'Газдар / кекіру', AppLocale.en: 'Burping / gas'},
  'cry_reason_unknown': {AppLocale.ru: 'Не определено', AppLocale.kk: 'Анықталмады', AppLocale.en: 'Undetermined'},
  // Said where the microphone is, not only in a policy nobody opens before
  // pressing a red button. Consent that arrives after the recording is not
  // consent, and this is the one screen in the app that captures audio.
  'cry_privacy': {
    AppLocale.ru: 'Запись уходит на наш сервер только для разбора и не сохраняется — после ответа файла не остаётся.',
    AppLocale.kk: 'Жазба тек талдау үшін біздің серверге жіберіледі және сақталмайды — жауаптан кейін файл қалмайды.',
    AppLocale.en: 'The recording goes to our server for analysis only and is not stored — no file remains once you have the answer.',
  },
  'cry_disclaimer': {AppLocale.ru: 'Подсказка носит справочный характер и не заменяет консультацию педиатра.', AppLocale.kk: 'Кеңес анықтамалық сипатта және педиатр кеңесін алмастырмайды.', AppLocale.en: 'This hint is for reference only and does not replace a paediatrician.'},
  'cry_history_title': {AppLocale.ru: 'Недавние проверки', AppLocale.kk: 'Соңғы тексерулер', AppLocale.en: 'Recent checks'},
  'cry_last': {AppLocale.ru: 'Последняя проверка: {reason}', AppLocale.kk: 'Соңғы тексеру: {reason}', AppLocale.en: 'Last check: {reason}'},

  // Кадр 17c. Below the served threshold the screen names NO reason. «Голод» at
  // 31 % reads to a mother exactly like «Голод» at 91 %, and she acts on it the
  // same way — so the honest answer is that we do not know, plus the one thing
  // that helps: a quieter recording.
  'cry_unsure_title': {AppLocale.ru: 'Причина не определена', AppLocale.kk: 'Себебі анықталмады', AppLocale.en: 'No reason determined'},
  'cry_unsure_headline': {AppLocale.ru: 'Не уверены', AppLocale.kk: 'Сенімді емеспіз', AppLocale.en: 'Not sure'},
  'cry_unsure_body': {
    AppLocale.ru: 'Уверенности слишком мало, чтобы называть причину. Ниже — как распределились вероятности. Запишите ещё раз в тишине, ближе к малышу.',
    AppLocale.kk: 'Себебін атау үшін сенімділік тым аз. Төменде — ықтималдықтардың таралуы. Тыныштықта, балаға жақынырақ қайта жазыңыз.',
    AppLocale.en: 'Too little confidence to name a reason. The spread is below. Record again somewhere quiet, closer to the baby.',
  },
  // «Это было верно?» — the only ground truth this product has about why a baby
  // cried. Without it every accuracy figure in the back office would be the
  // model's own confidence wearing a different word.
  'cry_verdict_q': {AppLocale.ru: 'Это было верно?', AppLocale.kk: 'Бұл дұрыс па еді?', AppLocale.en: 'Was this right?'},
  'cry_verdict_hint': {
    AppLocale.ru: 'Ваш ответ — единственный способ узнать, насколько подсказка попадает. Он ни на что не влияет прямо сейчас.',
    AppLocale.kk: 'Сіздің жауабыңыз — кеңестің қаншалықты дәл екенін білудің жалғыз жолы. Ол дәл қазір ештеңеге әсер етпейді.',
    AppLocale.en: 'Your answer is the only way to know how well the hint works. It changes nothing right now.',
  },
  'cry_verdict_yes': {AppLocale.ru: 'Да', AppLocale.kk: 'Иә', AppLocale.en: 'Yes'},
  'cry_verdict_no': {AppLocale.ru: 'Нет', AppLocale.kk: 'Жоқ', AppLocale.en: 'No'},
  'cry_verdict_which': {AppLocale.ru: 'А что было на самом деле?', AppLocale.kk: 'Шын мәнінде не болды?', AppLocale.en: 'What was it actually?'},
  'cry_verdict_dont_know': {AppLocale.ru: 'Не знаю', AppLocale.kk: 'Білмеймін', AppLocale.en: 'I don’t know'},
  'cry_verdict_thanks': {AppLocale.ru: 'Спасибо, записали', AppLocale.kk: 'Рақмет, жазып алдық', AppLocale.en: 'Thank you — noted'},
  'cry_verdict_why': {
    AppLocale.ru: 'По таким ответам мы считаем точность подсказок. Записи плача при этом не сохраняются.',
    AppLocale.kk: 'Осындай жауаптар бойынша кеңестердің дәлдігін есептейміз. Жылау жазбалары сақталмайды.',
    AppLocale.en: 'Answers like this are how we measure the hint’s accuracy. The recordings themselves are not kept.',
  },
  'cry_verdict_failed': {
    AppLocale.ru: 'Не удалось сохранить ответ. Попробуйте ещё раз — пока он никуда не записан.',
    AppLocale.kk: 'Жауапты сақтау мүмкін болмады. Қайта көріңіз — ол әзірге ешқайда жазылмаған.',
    AppLocale.en: 'Could not save your answer. Try again — nothing has been recorded yet.',
  },
  'cry_verdict_was_right': {AppLocale.ru: 'Вы отметили: верно', AppLocale.kk: 'Сіз белгіледіңіз: дұрыс', AppLocale.en: 'You marked this right'},
  'cry_verdict_was_wrong': {AppLocale.ru: 'Вы отметили: неверно', AppLocale.kk: 'Сіз белгіледіңіз: дұрыс емес', AppLocale.en: 'You marked this wrong'},
  'cry_verdict_was_wrong_actual': {
    AppLocale.ru: 'Вы отметили: неверно, было «{reason}»',
    AppLocale.kk: 'Сіз белгіледіңіз: дұрыс емес, «{reason}» болған',
    AppLocale.en: 'You marked this wrong — it was “{reason}”',
  },

  // Permission priming — a plain-language "why" shown before the OS prompt, so
  // a denial (which the OS then remembers for good) is far less likely.
  'prime_continue': {AppLocale.ru: 'Продолжить', AppLocale.kk: 'Жалғастыру', AppLocale.en: 'Continue'},
  'prime_not_now': {AppLocale.ru: 'Не сейчас', AppLocale.kk: 'Қазір емес', AppLocale.en: 'Not now'},
  'prime_loc_title': {AppLocale.ru: 'Доступ к геопозиции', AppLocale.kk: 'Геолокацияға рұқсат', AppLocale.en: 'Location access'},
  'prime_loc_body': {AppLocale.ru: 'Ana-Bala использует геопозицию телефона, чтобы отметить безопасные зоны — дом, школу — и предупредить вас, если ребёнок их покидает. Мы запрашиваем её только для этого. На следующем шаге система спросит разрешение.', AppLocale.kk: 'Ana-Bala қауіпсіз аймақтарды — үй, мектеп — белгілеу және бала одан шыққанда сізге хабарлау үшін телефонның геолокациясын пайдаланады. Оны тек осы үшін сұраймыз. Келесі қадамда жүйе рұқсат сұрайды.', AppLocale.en: 'Ana-Bala uses your phone’s location to mark safe zones — home, school — and warn you if your child leaves them. That’s the only thing we use it for. Next, the system will ask for permission.'},
  'prime_notif_title': {AppLocale.ru: 'Уведомления', AppLocale.kk: 'Хабарландырулар', AppLocale.en: 'Notifications'},
  'prime_notif_body': {AppLocale.ru: 'Чтобы вовремя сообщать о выходе из зоны, сигналах SOS и ваших напоминаниях, Ana-Bala нужны уведомления. Экстренные оповещения приходят всегда. Дальше система спросит разрешение.', AppLocale.kk: 'Аймақтан шығу, SOS дабылдары және еске салулар туралы уақтылы хабарлау үшін Ana-Bala-ге хабарландырулар қажет. Шұғыл ескертулер әрқашан келеді. Әрі қарай жүйе рұқсат сұрайды.', AppLocale.en: 'To alert you about zone exits, SOS signals and your reminders in time, Ana-Bala needs notifications. Emergency alerts always come through. Next, the system will ask for permission.'},

  // Force-update gate — shown when this build is below the server's minimum.
  'upd_title': {AppLocale.ru: 'Пора обновить приложение', AppLocale.kk: 'Қолданбаны жаңарту қажет', AppLocale.en: 'Time to update the app'},
  'upd_body': {AppLocale.ru: 'Эта версия Ana-Bala больше не поддерживается. Обновите приложение, чтобы продолжить — это займёт минуту и сохранит ваши данные в безопасности.', AppLocale.kk: 'Ana-Bala-дің бұл нұсқасы бұдан былай қолдау таппайды. Жалғастыру үшін қолданбаны жаңартыңыз — бұл бір минут алады және деректеріңіз қауіпсіз қалады.', AppLocale.en: 'This version of Ana-Bala is no longer supported. Please update to continue — it takes a minute and keeps your data safe.'},
  'upd_cta': {AppLocale.ru: 'Обновить', AppLocale.kk: 'Жаңарту', AppLocale.en: 'Update'},

  'set_privacy': {AppLocale.ru: 'Политика конфиденциальности', AppLocale.kk: 'Құпиялылық саясаты', AppLocale.en: 'Privacy policy'},
  'set_terms': {AppLocale.ru: 'Условия использования', AppLocale.kk: 'Пайдалану шарттары', AppLocale.en: 'Terms of use'},
  'legal_privacy_title': {AppLocale.ru: 'Конфиденциальность', AppLocale.kk: 'Құпиялылық', AppLocale.en: 'Privacy'},
  'legal_terms_title': {AppLocale.ru: 'Условия использования', AppLocale.kk: 'Пайдалану шарттары', AppLocale.en: 'Terms of use'},
  'legal_draft_note': {
    AppLocale.ru: 'Черновик. Текст описывает, как приложение работает сегодня, и ожидает юридической проверки перед публикацией.',
    AppLocale.kk: 'Жоба. Мәтін қолданбаның бүгінгі жұмысын сипаттайды және жарияланар алдында заңгерлік тексеруден өтеді.',
    AppLocale.en: 'Draft. This text describes how the app works today and is pending legal review before publication.',
  },
  'legal_updated': {AppLocale.ru: 'Обновлено: июль 2026', AppLocale.kk: 'Жаңартылды: шілде 2026', AppLocale.en: 'Updated: July 2026'},
  'legal_update_title': {AppLocale.ru: 'Мы обновили документы', AppLocale.kk: 'Құжаттарды жаңарттық', AppLocale.en: 'We’ve updated our documents'},
  'legal_update_body': {
    AppLocale.ru: 'Политика конфиденциальности и условия использования изменились. Пожалуйста, ознакомьтесь и примите их, чтобы продолжить.',
    AppLocale.kk: 'Құпиялылық саясаты мен пайдалану шарттары өзгерді. Жалғастыру үшін оларды оқып, қабылдаңыз.',
    AppLocale.en: 'Our privacy policy and terms of use have changed. Please review and accept them to continue.',
  },
  'legal_update_accept': {AppLocale.ru: 'Принять и продолжить', AppLocale.kk: 'Қабылдап, жалғастыру', AppLocale.en: 'Accept and continue'},

  // Privacy sections.
  'legal_priv_collect_h': {AppLocale.ru: 'Какие данные мы обрабатываем', AppLocale.kk: 'Қандай деректерді өңдейміз', AppLocale.en: 'What data we handle'},
  'legal_priv_collect_b': {
    AppLocale.ru: 'Ваш профиль (имя, телефон), данные о беременности и цикле, имя и дату рождения ребёнка, зоны (дом, школа) и показатели здоровья с подключённого браслета.',
    AppLocale.kk: 'Профиліңіз (аты, телефоны), жүктілік пен цикл деректері, баланың аты мен туған күні, аймақтар (үй, мектеп) және жалғанған білезіктен келетін денсаулық көрсеткіштері.',
    AppLocale.en: 'Your profile (name, phone), pregnancy and cycle data, your child’s name and date of birth, zones (home, school), and health readings from a paired band.',
  },
  'legal_priv_storage_h': {AppLocale.ru: 'Хранение на устройстве', AppLocale.kk: 'Құрылғыда сақтау', AppLocale.en: 'Stored on your device'},
  'legal_priv_storage_b': {
    AppLocale.ru: 'По умолчанию данные хранятся на вашем телефоне. Резервную копию можно выгрузить в файл — он ваш, храните его как личный документ.',
    AppLocale.kk: 'Әдепкі бойынша деректер телефоныңызда сақталады. Сақтық көшірмені файлға шығаруға болады — ол сіздікі, оны жеке құжат ретінде сақтаңыз.',
    AppLocale.en: 'By default your data stays on your phone. You can export a backup to a file — it is yours; keep it like a personal document.',
  },
  'legal_priv_cloud_h': {AppLocale.ru: 'Что уходит в облако', AppLocale.kk: 'Бұлтқа не жіберіледі', AppLocale.en: 'What goes to the cloud'},
  // The cry recording was missing from this list.
  //
  // A privacy policy that names chat messages and band readings and stays
  // silent about five seconds of audio recorded inside somebody's home, of
  // their baby, is not a small omission — it is the most sensitive thing this
  // app sends anywhere, and it was the one thing not disclosed.
  //
  // Written to what the code ACTUALLY does today: the clip is uploaded, decoded
  // in memory and answered; neither the backend nor the classifier writes it to
  // disk. docs/CLAUDE-app-design.md wants that analysis on the phone instead —
  // until it is, this says where the audio goes rather than implying it stays.
  'legal_priv_cloud_b': {
    AppLocale.ru: 'Только когда вы пользуетесь облачными функциями: сообщения ассистенту, показатели браслета для анализа и запись плача — она отправляется на наш сервер, разбирается там и НЕ сохраняется: после ответа файла не остаётся ни у нас, ни у третьих лиц. Мы не продаём ваши данные.',
    AppLocale.kk: 'Тек бұлттық функцияларды пайдаланғанда: ассистентке жіберілген хабарлар, талдауға арналған білезік көрсеткіштері және жылау жазбасы — ол біздің серверге жіберіледі, сонда талданады және САҚТАЛМАЙДЫ: жауаптан кейін файл бізде де, үшінші тұлғаларда да қалмайды. Деректеріңізді сатпаймыз.',
    AppLocale.en: 'Only when you use cloud features: messages to the assistant, band readings for analysis, and the cry recording — it is sent to our server, analysed there and NOT stored: once you have the answer no file remains, with us or with anyone else. We do not sell your data.',
  },
  'legal_priv_medical_h': {AppLocale.ru: 'Не медицинский прибор', AppLocale.kk: 'Медициналық құрал емес', AppLocale.en: 'Not a medical device'},
  'legal_priv_medical_b': {
    AppLocale.ru: 'Приложение помогает следить за самочувствием, но не ставит диагноз и не заменяет врача. При тревожных признаках обращайтесь к врачу.',
    AppLocale.kk: 'Қолданба әл-ауқатты қадағалауға көмектеседі, бірақ диагноз қоймайды және дәрігердің орнын баспайды. Қауіпті белгілерде дәрігерге жүгініңіз.',
    AppLocale.en: 'The app helps you follow your wellbeing but does not diagnose and does not replace a doctor. See a doctor if you have warning signs.',
  },
  'legal_priv_controls_h': {AppLocale.ru: 'Ваш контроль', AppLocale.kk: 'Сіздің бақылауыңыз', AppLocale.en: 'Your controls'},
  'legal_priv_controls_b': {
    AppLocale.ru: 'В любой момент вы можете выгрузить копию всех данных или полностью стереть их в разделе «Данные».',
    AppLocale.kk: 'Кез келген уақытта барлық деректердің көшірмесін шығаруға немесе «Деректер» бөлімінде толық жоюға болады.',
    AppLocale.en: 'At any time you can export a copy of all your data or erase it completely in the “Data” section.',
  },
  'legal_priv_contact_h': {AppLocale.ru: 'Связь с нами', AppLocale.kk: 'Бізбен байланыс', AppLocale.en: 'Contact us'},
  'legal_priv_contact_b': {
    AppLocale.ru: 'По вопросам о ваших данных напишите нам через раздел поддержки в приложении.',
    AppLocale.kk: 'Деректеріңіз туралы сұрақтар бойынша қолданбадағы қолдау бөлімі арқылы жазыңыз.',
    AppLocale.en: 'For questions about your data, contact us through the in-app support section.',
  },

  // Terms sections.
  'legal_terms_use_h': {AppLocale.ru: 'Использование приложения', AppLocale.kk: 'Қолданбаны пайдалану', AppLocale.en: 'Using the app'},
  'legal_terms_use_b': {
    AppLocale.ru: 'Пользуясь приложением, вы соглашаетесь с этими условиями. Приложение предназначено для личного, некоммерческого использования.',
    AppLocale.kk: 'Қолданбаны пайдалану арқылы осы шарттармен келісесіз. Қолданба жеке, коммерциялық емес пайдалануға арналған.',
    AppLocale.en: 'By using the app you agree to these terms. The app is for personal, non-commercial use.',
  },
  'legal_terms_medical_h': {AppLocale.ru: 'Не медицинская помощь', AppLocale.kk: 'Медициналық көмек емес', AppLocale.en: 'Not medical advice'},
  'legal_terms_medical_b': {
    AppLocale.ru: 'Информация в приложении носит справочный характер и не является медицинской консультацией, диагнозом или назначением.',
    AppLocale.kk: 'Қолданбадағы ақпарат анықтамалық сипатта және медициналық кеңес, диагноз немесе тағайындау болып табылмайды.',
    AppLocale.en: 'Information in the app is for reference only and is not medical advice, a diagnosis, or a prescription.',
  },
  'legal_terms_emergency_h': {AppLocale.ru: 'В экстренных случаях', AppLocale.kk: 'Төтенше жағдайларда', AppLocale.en: 'In an emergency'},
  'legal_terms_emergency_b': {
    AppLocale.ru: 'Приложение не служба экстренной помощи. При угрозе жизни звоните в скорую (103) или единую службу (112).',
    AppLocale.kk: 'Қолданба — жедел жәрдем қызметі емес. Өмірге қауіп төнгенде жедел жәрдемге (103) немесе бірыңғай қызметке (112) қоңырау шалыңыз.',
    AppLocale.en: 'The app is not an emergency service. If life is at risk, call an ambulance (103) or the single emergency line (112).',
  },
  'legal_terms_responsib_h': {AppLocale.ru: 'Ваша ответственность', AppLocale.kk: 'Сіздің жауапкершілігіңіз', AppLocale.en: 'Your responsibilities'},
  'legal_terms_responsib_b': {
    AppLocale.ru: 'Вводите достоверные данные и берегите доступ к телефону — приложение хранит личную информацию о вас и вашем ребёнке.',
    AppLocale.kk: 'Дұрыс деректер енгізіңіз және телефонға қолжетімділікті сақтаңыз — қолданба сіз бен балаңыз туралы жеке ақпаратты сақтайды.',
    AppLocale.en: 'Enter accurate data and keep your phone secure — the app holds personal information about you and your child.',
  },
  'legal_terms_warranty_h': {AppLocale.ru: 'Без гарантий', AppLocale.kk: 'Кепілдіксіз', AppLocale.en: 'No warranty'},
  'legal_terms_warranty_b': {
    AppLocale.ru: 'Приложение предоставляется «как есть». Мы стремимся к точности, но не гарантируем бесперебойную работу и отсутствие ошибок.',
    AppLocale.kk: 'Қолданба «бар күйінде» ұсынылады. Дәлдікке ұмтыламыз, бірақ үздіксіз жұмысқа және қателердің болмауына кепілдік бермейміз.',
    AppLocale.en: 'The app is provided “as is”. We aim for accuracy but do not guarantee uninterrupted, error-free operation.',
  },
  'legal_terms_law_h': {AppLocale.ru: 'Применимое право', AppLocale.kk: 'Қолданылатын құқық', AppLocale.en: 'Governing law'},
  'legal_terms_law_b': {
    AppLocale.ru: 'Условия регулируются законодательством Республики Казахстан.',
    AppLocale.kk: 'Шарттар Қазақстан Республикасының заңнамасымен реттеледі.',
    AppLocale.en: 'These terms are governed by the laws of the Republic of Kazakhstan.',
  },
  'set_bp_calibration': {AppLocale.ru: 'Калибровка давления', AppLocale.kk: 'Қысымды калибрлеу', AppLocale.en: 'Blood pressure'},
  'cal_title': {AppLocale.ru: 'Калибровка давления', AppLocale.kk: 'Қысымды калибрлеу', AppLocale.en: 'Calibrate blood pressure'},
  'cal_intro': {
    AppLocale.ru: 'Введите показания вашего тонометра, чтобы уточнить оценку давления по браслету.',
    AppLocale.kk: 'Білезік бойынша қысым бағасын нақтылау үшін тонометр көрсеткіштерін енгізіңіз.',
    AppLocale.en: "Enter your cuff (tonometer) reading to correct the band's blood-pressure estimate."
  },
  'cal_cuff_sys': {AppLocale.ru: 'Систолическое (тонометр)', AppLocale.kk: 'Систолалық (тонометр)', AppLocale.en: 'Systolic (cuff)'},
  'cal_cuff_dia': {AppLocale.ru: 'Диастолическое (тонометр)', AppLocale.kk: 'Диастолалық (тонометр)', AppLocale.en: 'Diastolic (cuff)'},
  'cal_band_reading': {AppLocale.ru: 'Показания браслета: {sys}/{dia}', AppLocale.kk: 'Білезік көрсеткіші: {sys}/{dia}', AppLocale.en: 'Band reading: {sys}/{dia}'},
  'cal_no_band': {AppLocale.ru: 'Нет данных браслета для калибровки. Наденьте браслет и измерьте давление.', AppLocale.kk: 'Калибрлеуге білезік деректері жоқ. Білезікті тағып, қысымды өлшеңіз.', AppLocale.en: 'No band reading yet. Wear your band and measure blood pressure first.'},
  // The reading behind an emergency, shown on the rescue screen. Purely
  // factual — the number and its unit, nothing interpreted.
  'em_reading_bp': {AppLocale.ru: 'Ваше давление: {v} мм рт. ст.', AppLocale.kk: 'Қысымыңыз: {v} мм сын. бағ.', AppLocale.en: 'Your blood pressure: {v} mmHg'},
  'em_reading_temp': {AppLocale.ru: 'Ваша температура: {v} °C', AppLocale.kk: 'Дене қызуыңыз: {v} °C', AppLocale.en: 'Your temperature: {v} °C'},
  'em_reading_spo2': {AppLocale.ru: 'Ваш кислород: {v}%', AppLocale.kk: 'Оттегіңіз: {v}%', AppLocale.en: 'Your blood oxygen: {v}%'},
  'em_reading_hr': {AppLocale.ru: 'Ваш пульс: {v} уд/мин', AppLocale.kk: 'Пульсіңіз: {v} соғ/мин', AppLocale.en: 'Your heart rate: {v} bpm'},
  // A reading crossed an emergency threshold once. Calm and actionable on
  // purpose: she is not in an emergency, and one wrist estimate does not make
  // her one. Never say "preeclampsia" here — that word belongs to the confirmed
  // emergency screen, not to a single unconfirmed number.
  'repeat_title_bp': {AppLocale.ru: 'Давление выше обычного', AppLocale.kk: 'Қысым әдеттегіден жоғары', AppLocale.en: 'Higher blood pressure than usual'},
  'repeat_title_fever': {AppLocale.ru: 'Температура выше обычной', AppLocale.kk: 'Дене қызуы әдеттегіден жоғары', AppLocale.en: 'Higher temperature than usual'},
  'repeat_title_spo2': {AppLocale.ru: 'Кислород ниже обычного', AppLocale.kk: 'Оттегі әдеттегіден төмен', AppLocale.en: 'Lower oxygen than usual'},
  'repeat_title_hr': {AppLocale.ru: 'Пульс вне обычного диапазона', AppLocale.kk: 'Пульс әдеттегі шектен тыс', AppLocale.en: 'Heart rate outside its usual range'},
  'repeat_body': {AppLocale.ru: 'Одно измерение с браслета — ещё не повод для тревоги: на него влияют движение, поза и волнение. Отдохните пару минут и измерьте снова. Если покажет то же самое, приложение подскажет, что делать.', AppLocale.kk: 'Білезіктің бір өлшемі әлі алаңдауға себеп емес: оған қозғалыс, дене қалпы және толқу әсер етеді. Бірер минут тынығып, қайта өлшеңіз. Сол көрсеткіш қайталанса, қосымша не істеу керегін айтады.', AppLocale.en: 'One band reading is not a cause for alarm on its own — movement, posture and stress all affect it. Rest a couple of minutes and measure again. If it shows the same, the app will tell you what to do.'},
  'repeat_cta': {AppLocale.ru: 'Измерить снова', AppLocale.kk: 'Қайта өлшеу', AppLocale.en: 'Measure again'},
  'cal_too_far':{AppLocale.ru: 'Показания тонометра и браслета слишком расходятся — калибровка не сохранена. Проверьте цифры и измерьте ещё раз в покое.', AppLocale.kk: 'Тонометр мен білезік көрсеткіштері тым алшақ — калибрлеу сақталмады. Сандарды тексеріп, тыныш күйде қайта өлшеңіз.', AppLocale.en: 'Your cuff and band readings are too far apart — nothing was saved. Check the numbers and measure again at rest.'},
  'cal_last': {AppLocale.ru: 'Откалибровано {ago}', AppLocale.kk: '{ago} калибрленген', AppLocale.en: 'Calibrated {ago}'},
  'cal_never': {AppLocale.ru: 'Не откалибровано', AppLocale.kk: 'Калибрленбеген', AppLocale.en: 'Not calibrated'},
  'cal_stale': {AppLocale.ru: 'Рекомендуется повторная калибровка', AppLocale.kk: 'Қайта калибрлеу ұсынылады', AppLocale.en: 'Recalibration recommended'},
  'prof_children_count': {AppLocale.ru: 'Дети', AppLocale.kk: 'Балалар', AppLocale.en: 'Children'},
  'prof_devices_count': {AppLocale.ru: 'Устройства', AppLocale.kk: 'Құрылғылар', AppLocale.en: 'Devices'},
  // Appointments / reminders
  'appt_title': {AppLocale.ru: 'Напоминания', AppLocale.kk: 'Еске салғыштар', AppLocale.en: 'Reminders'},
  'appt_add': {AppLocale.ru: 'Добавить', AppLocale.kk: 'Қосу', AppLocale.en: 'Add reminder'},
  'appt_edit': {AppLocale.ru: 'Изменить напоминание', AppLocale.kk: 'Еске салғышты өзгерту', AppLocale.en: 'Edit reminder'},
  'appt_actions': {AppLocale.ru: 'Действия', AppLocale.kk: 'Әрекеттер', AppLocale.en: 'Actions'},
  'appt_plus_day': {AppLocale.ru: 'Перенести на день', AppLocale.kk: 'Бір күнге жылжыту', AppLocale.en: 'Move +1 day'},
  'appt_plus_week': {AppLocale.ru: 'Перенести на неделю', AppLocale.kk: 'Бір аптаға жылжыту', AppLocale.en: 'Move +1 week'},
  'appt_upcoming': {AppLocale.ru: 'Предстоящие', AppLocale.kk: 'Алдағы', AppLocale.en: 'Upcoming'},
  'appt_next': {AppLocale.ru: 'Следующий визит', AppLocale.kk: 'Келесі қабылдау', AppLocale.en: 'Next appointment'},
  'visit_summary': {AppLocale.ru: 'Сводка для врача', AppLocale.kk: 'Дәрігерге арналған жиынтық', AppLocale.en: 'Summary for your visit'},
  'visit_title': {AppLocale.ru: 'Сводка для приёма', AppLocale.kk: 'Қабылдауға арналған жиынтық', AppLocale.en: 'Visit summary'},
  'visit_period': {AppLocale.ru: 'За последние {n} дней', AppLocale.kk: 'Соңғы {n} күн', AppLocale.en: 'Last {n} days'},
  'visit_vitals': {AppLocale.ru: 'ПОКАЗАТЕЛИ ({n} измерений)', AppLocale.kk: 'КӨРСЕТКІШТЕР ({n} өлшем)', AppLocale.en: 'VITALS ({n} readings)'},
  'visit_avg': {AppLocale.ru: 'сред.', AppLocale.kk: 'орт.', AppLocale.en: 'avg'},
  // Names the instrument on the temperature row of a page a doctor reads. The
  // row exists ONLY for readings she measured and typed in — device estimates
  // never reach this summary (visit_summary.dart says why) — so this states a
  // fact about the number rather than warning about it, and no wording here may
  // suggest the app measured anything.
  'visit_temp_thermometer': {AppLocale.ru: 'измерено термометром, введено вручную', AppLocale.kk: 'термометрмен өлшенген, қолмен енгізілген', AppLocale.en: 'measured with a thermometer, entered by hand'},
  'visit_meds': {AppLocale.ru: 'ВИТАМИНЫ И ЛЕКАРСТВА', AppLocale.kk: 'ДӘРУМЕНДЕР МЕН ДӘРІЛЕР', AppLocale.en: 'MEDICATIONS'},
  'visit_weight': {AppLocale.ru: 'ВЕС', AppLocale.kk: 'САЛМАҚ', AppLocale.en: 'WEIGHT'},
  'visit_since_start': {AppLocale.ru: 'с начала', AppLocale.kk: 'басынан', AppLocale.en: 'since start'},
  'visit_symptoms': {AppLocale.ru: 'ОТМЕЧЕННЫЕ СИМПТОМЫ', AppLocale.kk: 'БЕЛГІЛЕНГЕН СИМПТОМДАР', AppLocale.en: 'SYMPTOMS LOGGED'},
  'visit_disclaimer': {AppLocale.ru: 'Это не медицинская карта — здесь только то, что записало приложение.', AppLocale.kk: 'Бұл медициналық карта емес — мұнда тек қолданба жазғаны бар.', AppLocale.en: 'Not a medical record — these are the figures the app recorded.'},
  'visit_copied': {AppLocale.ru: 'Сводка скопирована', AppLocale.kk: 'Жиынтық көшірілді', AppLocale.en: 'Summary copied'},
  'appt_search_hint': {AppLocale.ru: 'Поиск по напоминаниям', AppLocale.kk: 'Еске салғыштардан іздеу', AppLocale.en: 'Search reminders'},
  'appt_no_match': {AppLocale.ru: 'Ничего не найдено.', AppLocale.kk: 'Ештеңе табылмады.', AppLocale.en: 'No matching reminders.'},
  'med_title': {AppLocale.ru: 'Витамины и лекарства', AppLocale.kk: 'Дәрумендер мен дәрілер', AppLocale.en: 'Vitamins & medicines'},
  'med_add': {AppLocale.ru: 'Добавить', AppLocale.kk: 'Қосу', AppLocale.en: 'Add'},
  'med_edit': {AppLocale.ru: 'Изменить', AppLocale.kk: 'Өзгерту', AppLocale.en: 'Edit'},
  'med_empty': {AppLocale.ru: 'Пока ничего не добавлено. Добавьте витамины или лекарства, которые принимаете.', AppLocale.kk: 'Әзірге ештеңе қосылмаған. Қабылдайтын дәрумендер мен дәрілерді қосыңыз.', AppLocale.en: 'Nothing added yet. Add the vitamins or medicines you take.'},
  'med_today': {AppLocale.ru: 'Приёмы сегодня', AppLocale.kk: 'Бүгінгі қабылдау', AppLocale.en: 'Today\'s doses'},
  'med_streak': {AppLocale.ru: '{n} дн. подряд без пропусков', AppLocale.kk: 'Қатарынан {n} күн толық', AppLocale.en: '{n} days in a row, all taken'},
  'med_take': {AppLocale.ru: 'Отметить приём', AppLocale.kk: 'Қабылдағанды белгілеу', AppLocale.en: 'Mark a dose taken'},
  'med_undo': {AppLocale.ru: 'Отменить приём', AppLocale.kk: 'Қабылдауды болдырмау', AppLocale.en: 'Undo a dose'},
  'med_per_day': {AppLocale.ru: '{n} раза в день', AppLocale.kk: 'күніне {n} рет', AppLocale.en: '{n}× a day'},
  'med_per_day_label': {AppLocale.ru: 'Сколько раз в день', AppLocale.kk: 'Күніне неше рет', AppLocale.en: 'Doses per day'},
  'med_name_label': {AppLocale.ru: 'Название', AppLocale.kk: 'Атауы', AppLocale.en: 'Name'},
  'med_name_hint': {AppLocale.ru: 'Например, фолиевая кислота', AppLocale.kk: 'Мысалы, фолий қышқылы', AppLocale.en: 'e.g. Folic acid'},
  'med_dose_label': {AppLocale.ru: 'Дозировка (необязательно)', AppLocale.kk: 'Мөлшері (міндетті емес)', AppLocale.en: 'Dose (optional)'},
  'med_dose_hint': {AppLocale.ru: 'Например, 400 мкг', AppLocale.kk: 'Мысалы, 400 мкг', AppLocale.en: 'e.g. 400 mcg'},
  'med_more': {AppLocale.ru: 'и ещё {n}', AppLocale.kk: 'және тағы {n}', AppLocale.en: 'and {n} more'},
  'med_history': {AppLocale.ru: 'История приёмов', AppLocale.kk: 'Қабылдау тарихы', AppLocale.en: 'Dose history'},
  'med_adherence': {AppLocale.ru: '{pct}% за неделю', AppLocale.kk: 'Апта ішінде {pct}%', AppLocale.en: '{pct}% this week'},
  'med_history_span': {AppLocale.ru: 'Последние {n} дней', AppLocale.kk: 'Соңғы {n} күн', AppLocale.en: 'Last {n} days'},
  'med_delete_title': {AppLocale.ru: 'Удалить из списка?', AppLocale.kk: 'Тізімнен жою керек пе?', AppLocale.en: 'Remove from your list?'},
  'med_delete_body': {AppLocale.ru: '«{name}» и все отметки о приёме будут удалены. Это действие нельзя отменить.', AppLocale.kk: '«{name}» және оның барлық белгілері жойылады. Бұл әрекетті қайтару мүмкін емес.', AppLocale.en: '{name} and every dose recorded against it will be deleted. This can\'t be undone.'},
  'med_disclaimer': {AppLocale.ru: 'Приложение только записывает то, что вы отмечаете. Дозировки и назначения обсуждайте с врачом.', AppLocale.kk: 'Қолданба тек сіз белгілегенді жазады. Мөлшер мен тағайындауды дәрігеріңізбен талқылаңыз.', AppLocale.en: 'This only records what you tick off. Dosages and prescriptions are between you and your provider.'},
  'appt_past': {AppLocale.ru: 'Прошедшие', AppLocale.kk: 'Өткен', AppLocale.en: 'Past'},
  'appt_empty': {AppLocale.ru: 'Пока нет напоминаний.\nДобавьте визит к врачу или обследование.', AppLocale.kk: 'Әзірге еске салғыш жоқ.\nДәрігерге бару немесе тексеру қосыңыз.', AppLocale.en: 'No reminders yet.\nAdd a doctor visit or a check-up.'},
  'appt_none': {AppLocale.ru: 'Нет предстоящих напоминаний', AppLocale.kk: 'Алдағы еске салғыш жоқ', AppLocale.en: 'No upcoming reminders'},
  'appt_today': {AppLocale.ru: 'Сегодня', AppLocale.kk: 'Бүгін', AppLocale.en: 'Today'},
  'appt_tomorrow': {AppLocale.ru: 'Завтра', AppLocale.kk: 'Ертең', AppLocale.en: 'Tomorrow'},
  'appt_in_days': {AppLocale.ru: 'через {n} дн.', AppLocale.kk: '{n} күнде', AppLocale.en: 'in {n} days'},
  'appt_title_label': {AppLocale.ru: 'Название', AppLocale.kk: 'Атауы', AppLocale.en: 'Title'},
  'appt_title_hint': {AppLocale.ru: 'Напр., приём у гинеколога', AppLocale.kk: 'Мыс., гинекологқа бару', AppLocale.en: 'e.g. OB-GYN visit'},
  'appt_note_label': {AppLocale.ru: 'Заметка (необязательно)', AppLocale.kk: 'Ескертпе (міндетті емес)', AppLocale.en: 'Note (optional)'},
  'appt_delete_title': {AppLocale.ru: 'Удалить напоминание?', AppLocale.kk: 'Еске салғышты жою керек пе?', AppLocale.en: 'Delete this reminder?'},
  'appt_delete_body': {AppLocale.ru: '«{title}» будет удалено.', AppLocale.kk: '«{title}» жойылады.', AppLocale.en: '"{title}" will be removed.'},
  'appt_notif_body': {AppLocale.ru: 'Скоро запланированный визит.', AppLocale.kk: 'Жоспарланған бару жақындады.', AppLocale.en: "It's almost time for your appointment."},
  'prof_no_phone': {AppLocale.ru: 'Телефон не указан', AppLocale.kk: 'Телефон көрсетілмеген', AppLocale.en: 'No phone number'},
  'prof_open_settings': {AppLocale.ru: 'Открыть настройки', AppLocale.kk: 'Параметрлерді ашу', AppLocale.en: 'Open settings'},
  'set_reset': {AppLocale.ru: 'Сбросить приложение', AppLocale.kk: 'Қолданбаны қалпына келтіру', AppLocale.en: 'Reset app'},
  'set_reset_title': {AppLocale.ru: 'Сбросить приложение?', AppLocale.kk: 'Қолданбаны қалпына келтіру керек пе?', AppLocale.en: 'Reset the app?'},
  'set_reset_body': {
    AppLocale.ru: 'Все данные будут удалены, и настройка начнётся заново.',
    AppLocale.kk: 'Барлық деректер жойылып, баптау қайтадан басталады.',
    AppLocale.en: 'All data will be erased and setup will start over.'
  },
  // Why the primary button will not advance. Named one at a time: a list of
  // everything the step wants reads as a wall.
  'onb_need_consent': {
    AppLocale.ru: 'Отметьте согласие, чтобы продолжить',
    AppLocale.kk: 'Жалғастыру үшін келісімді белгілеңіз',
    AppLocale.en: 'Tick the box to continue',
  },
  'onb_need_name': {
    AppLocale.ru: 'Введите имя, чтобы продолжить',
    AppLocale.kk: 'Жалғастыру үшін атыңызды жазыңыз',
    AppLocale.en: 'Enter your name to continue',
  },
  'onb_need_phone': {
    AppLocale.ru: 'Проверьте номер телефона',
    AppLocale.kk: 'Телефон нөмірін тексеріңіз',
    AppLocale.en: 'Check the phone number',
  },
  'onb_need_child_zone': {
    AppLocale.ru: 'Укажите домашнюю зону для ребёнка',
    AppLocale.kk: 'Бала үшін үй аймағын көрсетіңіз',
    AppLocale.en: 'Add a home zone for your child',
  },
  'onb_next': {AppLocale.ru: 'Далее', AppLocale.kk: 'Келесі', AppLocale.en: 'Next'},
  'onb_back': {AppLocale.ru: 'Назад', AppLocale.kk: 'Артқа', AppLocale.en: 'Back'},
  'onb_finish': {AppLocale.ru: 'Готово', AppLocale.kk: 'Дайын', AppLocale.en: 'Finish'},
  // The child step is optional; saying so on the button is the difference
  // between "I can go on" and a form that looks unfinished.
  'onb_child_skip': {
    AppLocale.ru: 'Пропустить — добавлю позже',
    AppLocale.kk: 'Өткізіп жіберу — кейін қосамын',
    AppLocale.en: 'Skip for now'
  },
  'onb_step': {AppLocale.ru: 'Шаг {n} из {total}', AppLocale.kk: '{total} қадамнан {n}', AppLocale.en: 'Step {n} of {total}'},

  // Emergency screen
  'em_title': {AppLocale.ru: 'Срочное предупреждение о здоровье', AppLocale.kk: 'Шұғыл денсаулық ескертуі', AppLocale.en: 'Urgent health alert'},
  // Under the call button on every red-flag screen. The digits are shown as
  // well as dialled: if the dialler cannot open, she has still read them.
  'em_ambulance_hint': {
    AppLocale.ru: 'Скорая — {tel}. Звоните, если увидели у себя любой из этих признаков.',
    AppLocale.kk: 'Жедел жәрдем — {tel}. Осы белгілердің кез келгенін байқасаңыз, қоңырау шалыңыз.',
    AppLocale.en: 'Ambulance — {tel}. Call if you notice any of these signs.',
  },
  'em_call_ambulance': {AppLocale.ru: 'Вызвать скорую', AppLocale.kk: 'Жедел жәрдем шақыру', AppLocale.en: 'Call ambulance'},
  // Spoken by a screen reader after the button's own label, so it has to be in
  // the same language as the rest of the sentence.
  'em_call_semantics': {AppLocale.ru: 'Экстренный вызов.', AppLocale.kk: 'Шұғыл қоңырау.', AppLocale.en: 'Emergency call.'},
  'em_call_doctor': {AppLocale.ru: 'Позвонить врачу', AppLocale.kk: 'Дәрігерге қоңырау шалу', AppLocale.en: 'Call your doctor'},
  'em_not_emergency': {AppLocale.ru: 'Это не экстренная ситуация', AppLocale.kk: 'Бұл төтенше жағдай емес', AppLocale.en: "This isn't an emergency"},
  // Shown when the dialler will not open. She still needs the number, so the
  // copy is about what to do next, not about what went wrong.
  'em_call_failed_title': {
    AppLocale.ru: 'Наберите номер вручную',
    AppLocale.kk: 'Нөмірді қолмен теріңіз',
    AppLocale.en: 'Dial the number yourself'
  },
  'em_call_failed_body': {
    AppLocale.ru: 'Не удалось открыть телефон на этом устройстве. Позвоните по номеру:',
    AppLocale.kk: 'Бұл құрылғыда телефонды ашу мүмкін болмады. Мына нөмірге қоңырау шалыңыз:',
    AppLocale.en: 'The phone app could not be opened on this device. Call this number:'
  },
  'em_copy_number': {
    AppLocale.ru: 'Скопировать номер',
    AppLocale.kk: 'Нөмірді көшіру',
    AppLocale.en: 'Copy the number'
  },
  'act_close': {AppLocale.ru: 'Закрыть', AppLocale.kk: 'Жабу', AppLocale.en: 'Close'},

  'em_dismiss_title': {AppLocale.ru: 'Закрыть предупреждение?', AppLocale.kk: 'Ескертуді жабу керек пе?', AppLocale.en: 'Dismiss this alert?'},
  'em_dismiss_body': {
    AppLocale.ru: 'Мы обнаружили показатель, который может быть опасен при беременности. Закрывайте, только если вы уверены, что вам ничего не угрожает.',
    AppLocale.kk: 'Біз жүктілік кезінде қауіпті болуы мүмкін көрсеткішті байқадық. Тек өзіңізді қауіпсіз сезінсеңіз ғана жабыңыз.',
    AppLocale.en: 'We detected a reading that can be serious in pregnancy. Only dismiss if you are sure you are safe.'
  },
  'em_keep': {AppLocale.ru: 'Оставить', AppLocale.kk: 'Қалдыру', AppLocale.en: 'Keep it'},
  'em_dismiss': {AppLocale.ru: 'Закрыть', AppLocale.kk: 'Жабу', AppLocale.en: 'Dismiss'},

  // Dashboard
  'db_title': {AppLocale.ru: 'Ваше здоровье', AppLocale.kk: 'Сіздің денсаулығыңыз', AppLocale.en: 'Your health'},
  'db_greeting': {AppLocale.ru: '{name}', AppLocale.kk: '{name}', AppLocale.en: '{name}'},
  'db_share': {AppLocale.ru: 'Поделиться сводкой', AppLocale.kk: 'Қорытындымен бөлісу', AppLocale.en: 'Share summary'},
  // ---- Watch activity & wellness metrics (wm_*) ----
  'wm_title': {AppLocale.ru: 'Активность и самочувствие', AppLocale.kk: 'Белсенділік және көңіл-күй', AppLocale.en: 'Activity & wellness'},
  // «Свежесть данных подписана всегда» — a heart rate with no time on it is
  // read as 'now', and a reading six hours old is a different fact entirely.
  'db_vitals_as_of': {
    AppLocale.ru: 'Показания: {when}',
    AppLocale.kk: 'Көрсеткіштер: {when}',
    AppLocale.en: 'Readings: {when}',
  },
  // What the backfill from the watch actually covered. The number is the count
  // of days the WATCH returned data for, never the window the app asked for —
  // a chart that says seven days on the strength of a request that came back
  // with two is a lie the reader has no way to catch.
  'db_watch_history_span': {
    AppLocale.ru: 'История с часов: {n} дн.',
    AppLocale.kk: 'Сағаттан тарих: {n} күн',
    AppLocale.en: 'From the watch: {n} days of history',
  },
  'db_vitals_section': {AppLocale.ru: 'Показатели', AppLocale.kk: 'Көрсеткіштер', AppLocale.en: 'Vital signs'},
  'db_zone_care': {AppLocale.ru: 'Наблюдение', AppLocale.kk: 'Бақылау', AppLocale.en: 'Care'},
  'db_zone_tools': {AppLocale.ru: 'Инструменты', AppLocale.kk: 'Құралдар', AppLocale.en: 'Tools'},
  'wm_group_activity': {AppLocale.ru: 'Активность', AppLocale.kk: 'Белсенділік', AppLocale.en: 'Activity'},
  'wm_group_wellbeing': {AppLocale.ru: 'Самочувствие', AppLocale.kk: 'Көңіл-күй', AppLocale.en: 'Wellbeing'},
  'wm_steps': {AppLocale.ru: 'Шаги', AppLocale.kk: 'Қадамдар', AppLocale.en: 'Steps'},
  'wm_distance': {AppLocale.ru: 'Дистанция', AppLocale.kk: 'Қашықтық', AppLocale.en: 'Distance'},
  'wm_calories': {AppLocale.ru: 'Калории', AppLocale.kk: 'Калория', AppLocale.en: 'Calories'},
  'wm_sleep': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
  // «Күйзеліс» is the Kazakh word; «Стресс» was the Russian one left in place.
  'wm_stress': {AppLocale.ru: 'Стресс', AppLocale.kk: 'Күйзеліс', AppLocale.en: 'Stress'},
  'wm_breath': {AppLocale.ru: 'Дыхание', AppLocale.kk: 'Тыныс алу', AppLocale.en: 'Breathing'},
  'wm_sugar': {AppLocale.ru: 'Глюкоза', AppLocale.kk: 'Глюкоза', AppLocale.en: 'Glucose'},
  'wm_unit_km': {AppLocale.ru: 'км', AppLocale.kk: 'км', AppLocale.en: 'km'},
  'wm_unit_kcal': {AppLocale.ru: 'ккал', AppLocale.kk: 'ккал', AppLocale.en: 'kcal'},
  'wm_unit_brpm': {AppLocale.ru: 'вд/мин', AppLocale.kk: 'дем/мин', AppLocale.en: 'br/min'},
  'wm_unit_mmol': {AppLocale.ru: 'ммоль/л', AppLocale.kk: 'ммоль/л', AppLocale.en: 'mmol/L'},
  'wm_sleep_hm': {AppLocale.ru: '{h} ч {m} мин', AppLocale.kk: '{h} сағ {m} мин', AppLocale.en: '{h}h {m}m'},
  'wm_deep_light': {AppLocale.ru: 'глубокий {d} мин · лёгкий {l} мин', AppLocale.kk: 'терең {d} мин · жеңіл {l} мин', AppLocale.en: 'deep {d}m · light {l}m'},
  'wm_off_wrist': {AppLocale.ru: 'Часы сняты — данные могут быть неполными.', AppLocale.kk: 'Сағат шешілген — деректер толық болмауы мүмкін.', AppLocale.en: 'Watch is off the wrist — data may be incomplete.'},

  // ---- Signs of labour (lab_*) ----
  'lab_title': {AppLocale.ru: 'Признаки родов', AppLocale.kk: 'Босану белгілері', AppLocale.en: 'Signs of labour'},
  'lab_intro': {
    AppLocale.ru: 'Что подсказывает, что роды близко, и когда пора ехать. При любых сомнениях звоните.',
    AppLocale.kk: 'Босанудың жақындағанын не білдіреді және қашан баруға болатыны. Кез келген күмәнда қоңырау шалыңыз.',
    AppLocale.en: "What tells you labour is near, and when it's time to go. When in doubt, call.",
  },
  'lab_signs_title': {AppLocale.ru: 'Роды могут начинаться', AppLocale.kk: 'Босану басталуы мүмкін', AppLocale.en: 'Labour may be starting'},
  'lab_go_title': {AppLocale.ru: 'Когда ехать или звонить', AppLocale.kk: 'Қашан бару немесе қоңырау шалу', AppLocale.en: 'When to go in or call'},
  'lab_go_intro': {
    AppLocale.ru: 'Свяжитесь с роддомом или поезжайте, если появится что-то из этого:',
    AppLocale.kk: 'Мыналардың бірі болса, перзентханаға хабарласыңыз немесе барыңыз:',
    AppLocale.en: 'Contact or head to your maternity unit if any of these happen:',
  },
  'lab_disclaimer': {
    AppLocale.ru: 'Это общие сведения, а не медицинская консультация. Точные указания даёт ваш роддом.',
    AppLocale.kk: 'Бұл — жалпы мәлімет, медициналық кеңес емес. Нақты нұсқауларды перзентханаңыз береді.',
    AppLocale.en: 'General information, not medical advice. Your maternity unit gives the exact guidance.',
  },

  'lab_sign_contractions': {
    AppLocale.ru: 'Схватки становятся регулярными, сильнее и чаще.',
    AppLocale.kk: 'Толғақ реттелген, күшейіп, жиілей түседі.',
    AppLocale.en: 'Contractions become regular, stronger and closer together.',
  },
  'lab_sign_show': {
    AppLocale.ru: 'Отходит слизистая пробка — розоватые или кровянистые выделения.',
    AppLocale.kk: 'Шырышты тығын кетеді — қызғылт немесе қанды бөліністер.',
    AppLocale.en: "A 'show' — the mucus plug comes away, pink or blood-streaked.",
  },
  'lab_sign_backache': {
    AppLocale.ru: 'Тупая боль в пояснице или спазмы, как при месячных.',
    AppLocale.kk: 'Белдегі күңгірт ауырсыну немесе етеккірдегідей құрысу.',
    AppLocale.en: 'A dull lower-back ache, or period-like cramps.',
  },
  'lab_sign_waters': {
    AppLocale.ru: 'Отходят воды — струйкой или потоком.',
    AppLocale.kk: 'Су кетеді — тамшылап немесе ағып.',
    AppLocale.en: 'Your waters break — a trickle or a gush.',
  },

  'lab_go_waters_broke': {
    AppLocale.ru: 'Отошли воды — срочно, если они зелёные, коричневые или с кровью.',
    AppLocale.kk: 'Су кетті — жасыл, қоңыр немесе қанды болса, шұғыл.',
    AppLocale.en: 'Your waters have broken — urgent if they are green, brown or bloody.',
  },
  'lab_go_five_one_one': {
    AppLocale.ru: 'Схватки примерно каждые 5 минут по ~1 минуте в течение часа (правило 5-1-1).',
    AppLocale.kk: 'Толғақ шамамен әр 5 минут сайын, ~1 минуттан, бір сағат бойы (5-1-1 ережесі).',
    AppLocale.en: 'Contractions about every 5 minutes, ~1 minute long, for an hour (the 5-1-1 rule).',
  },
  'lab_go_bleeding': {
    AppLocale.ru: 'Любое кровотечение из влагалища.',
    AppLocale.kk: 'Қынаптан кез келген қан кету.',
    AppLocale.en: 'Any vaginal bleeding.',
  },
  'lab_go_reduced_movements': {
    AppLocale.ru: 'Малыш стал заметно меньше шевелиться.',
    AppLocale.kk: 'Нәресте айтарлықтай аз қимылдай бастады.',
    AppLocale.en: 'The baby is moving noticeably less.',
  },
  'lab_go_preterm': {
    AppLocale.ru: 'Любые признаки родов до 37 недель.',
    AppLocale.kk: '37 аптаға дейінгі кез келген босану белгілері.',
    AppLocale.en: 'Any signs of labour before 37 weeks.',
  },
  'lab_go_unsure': {
    AppLocale.ru: 'Сомневаетесь — позвоните в консультацию, вам подскажут.',
    AppLocale.kk: 'Күмәндансаңыз — консультацияға қоңырау шалыңыз, олар айтады.',
    AppLocale.en: 'When in doubt, call your clinic — they will guide you.',
  },

  // ---- Teething (teeth_*) ----
  'teeth_title': {AppLocale.ru: 'Прорезывание зубов', AppLocale.kk: 'Тіс шығу', AppLocale.en: 'Teething'},
  'teeth_intro': {
    AppLocale.ru: 'Зубы прорезываются по-своему у каждого малыша — возраст указан ориентировочно.',
    AppLocale.kk: 'Тістер әр нәрестеде өзінше шығады — жас шамамен көрсетілген.',
    AppLocale.en: 'Teeth arrive on their own schedule — the ages are a rough guide.',
  },
  'teeth_timeline_title': {AppLocale.ru: 'Примерный порядок', AppLocale.kk: 'Шамамен реті', AppLocale.en: 'The usual order'},
  'teeth_signs_title': {AppLocale.ru: 'Признаки', AppLocale.kk: 'Белгілері', AppLocale.en: 'Signs'},
  'teeth_soothe_title': {AppLocale.ru: 'Что помогает', AppLocale.kk: 'Не көмектеседі', AppLocale.en: 'What helps'},
  'teeth_not_title': {AppLocale.ru: 'Это не от зубов', AppLocale.kk: 'Бұл тістен емес', AppLocale.en: "This isn't teething"},
  'teeth_not_intro': {
    AppLocale.ru: 'Если появилось это, дело не в зубах — покажите ребёнка врачу:',
    AppLocale.kk: 'Мыналар пайда болса, бұл тістен емес — баланы дәрігерге көрсетіңіз:',
    AppLocale.en: "If these appear, it isn't the teeth — see a doctor:",
  },
  'teeth_age_range': {AppLocale.ru: '{from}–{to} мес.', AppLocale.kk: '{from}–{to} ай', AppLocale.en: '{from}–{to} mo'},
  'teeth_disclaimer': {
    AppLocale.ru: 'Это общие сведения, а не медицинская консультация. Вопросы о зубах ребёнка обсудите с педиатром или стоматологом.',
    AppLocale.kk: 'Бұл — жалпы мәлімет, медициналық кеңес емес. Бала тістері туралы педиатр немесе стоматологпен ақылдасыңыз.',
    AppLocale.en: "General information, not medical advice. Ask your paediatrician or dentist about your child's teeth.",
  },

  'teeth_lower_central': {AppLocale.ru: 'Нижние центральные резцы', AppLocale.kk: 'Төменгі ортаңғы күрек тістер', AppLocale.en: 'Lower central incisors'},
  'teeth_upper_central': {AppLocale.ru: 'Верхние центральные резцы', AppLocale.kk: 'Жоғарғы ортаңғы күрек тістер', AppLocale.en: 'Upper central incisors'},
  'teeth_upper_lateral': {AppLocale.ru: 'Верхние боковые резцы', AppLocale.kk: 'Жоғарғы бүйір күрек тістер', AppLocale.en: 'Upper lateral incisors'},
  'teeth_lower_lateral': {AppLocale.ru: 'Нижние боковые резцы', AppLocale.kk: 'Төменгі бүйір күрек тістер', AppLocale.en: 'Lower lateral incisors'},
  'teeth_first_molars': {AppLocale.ru: 'Первые моляры', AppLocale.kk: 'Бірінші азу тістер', AppLocale.en: 'First molars'},
  'teeth_canines': {AppLocale.ru: 'Клыки', AppLocale.kk: 'Азу тістер (сүйір)', AppLocale.en: 'Canines'},
  'teeth_second_molars': {AppLocale.ru: 'Вторые моляры', AppLocale.kk: 'Екінші азу тістер', AppLocale.en: 'Second molars'},

  'teeth_sign_drool': {AppLocale.ru: 'Обильное слюнотечение', AppLocale.kk: 'Мол сілекей ағу', AppLocale.en: 'Lots of drooling'},
  'teeth_sign_chewing': {AppLocale.ru: 'Тянет всё в рот и грызёт', AppLocale.kk: 'Бәрін аузына салып кеміреді', AppLocale.en: 'Chewing on everything'},
  'teeth_sign_irritable': {AppLocale.ru: 'Капризность и беспокойство', AppLocale.kk: 'Ерке мінез бен мазасыздық', AppLocale.en: 'Fussiness and irritability'},
  'teeth_sign_sore_gums': {AppLocale.ru: 'Покрасневшие, припухшие дёсны', AppLocale.kk: 'Қызарған, ісінген қызыл иек', AppLocale.en: 'Red, swollen gums'},
  'teeth_sign_sleep': {AppLocale.ru: 'Беспокойный сон', AppLocale.kk: 'Мазасыз ұйқы', AppLocale.en: 'Disturbed sleep'},

  'teeth_soothe_teething_ring': {AppLocale.ru: 'Прохладный (не замороженный) прорезыватель.', AppLocale.kk: 'Салқын (мұздатылмаған) тіс шығарғыш.', AppLocale.en: 'A cool (not frozen) teething ring.'},
  'teeth_soothe_gum_massage': {AppLocale.ru: 'Аккуратно помассируйте дёсны чистым пальцем.', AppLocale.kk: 'Қызыл иекті таза саусақпен ақырын уқалаңыз.', AppLocale.en: 'Gently rub the gums with a clean finger.'},
  'teeth_soothe_cool_food': {AppLocale.ru: 'Прохладная еда или питьё по возрасту.', AppLocale.kk: 'Жасына сай салқын тағам немесе сусын.', AppLocale.en: 'Cool food or drink, age-appropriate.'},
  'teeth_soothe_wipe_drool': {AppLocale.ru: 'Вытирайте слюну, чтобы не раздражать кожу.', AppLocale.kk: 'Теріні тітіркендірмеу үшін сілекейді сүртіп тұрыңыз.', AppLocale.en: 'Wipe away drool to protect the skin.'},

  'teeth_not_high_fever': {AppLocale.ru: 'Высокая температура — прорезывание её не вызывает.', AppLocale.kk: 'Жоғары температура — тіс шығу оны тудырмайды.', AppLocale.en: 'A high fever — teething does not cause one.'},
  'teeth_not_diarrhoea': {AppLocale.ru: 'Понос или рвота.', AppLocale.kk: 'Іш өту немесе құсу.', AppLocale.en: 'Diarrhoea or vomiting.'},

  // ---- Child emergency medical-ID info (ei_*) ----
  'ei_title': {AppLocale.ru: 'Экстренная информация', AppLocale.kk: 'Шұғыл ақпарат', AppLocale.en: 'Emergency info'},
  'ei_subtitle': {AppLocale.ru: 'Медданные на случай экстренной ситуации', AppLocale.kk: 'Шұғыл жағдайға арналған медициналық деректер', AppLocale.en: 'Medical details for an emergency'},
  'ei_empty': {
    AppLocale.ru: 'Добавьте важное на случай экстренной ситуации: аллергии, диагнозы, группу крови, кого позвать.',
    AppLocale.kk: 'Шұғыл жағдайға маңыздысын қосыңыз: аллергия, диагноздар, қан тобы, кімге қоңырау шалу керектігі.',
    AppLocale.en: 'Add what matters in an emergency: allergies, conditions, blood type, who to call.',
  },
  'ei_add': {AppLocale.ru: 'Заполнить', AppLocale.kk: 'Толтыру', AppLocale.en: 'Fill in'},
  'ei_edit': {AppLocale.ru: 'Изменить', AppLocale.kk: 'Өзгерту', AppLocale.en: 'Edit'},
  'ei_save': {AppLocale.ru: 'Сохранить', AppLocale.kk: 'Сақтау', AppLocale.en: 'Save'},
  'ei_call': {AppLocale.ru: 'Позвонить', AppLocale.kk: 'Қоңырау шалу', AppLocale.en: 'Call'},
  'ei_disclaimer': {
    AppLocale.ru: 'Эти данные вводите вы; приложение их не проверяет.',
    AppLocale.kk: 'Бұл деректерді сіз енгізесіз; қосымша оларды тексермейді.',
    AppLocale.en: 'You enter these details; the app does not verify them.',
  },
  'ei_blood': {AppLocale.ru: 'Группа крови', AppLocale.kk: 'Қан тобы', AppLocale.en: 'Blood type'},
  'ei_allergies': {AppLocale.ru: 'Аллергии', AppLocale.kk: 'Аллергиялар', AppLocale.en: 'Allergies'},
  'ei_conditions': {AppLocale.ru: 'Диагнозы / состояния', AppLocale.kk: 'Диагноздар / жағдайлар', AppLocale.en: 'Conditions'},
  'ei_medications': {AppLocale.ru: 'Лекарства', AppLocale.kk: 'Дәрілер', AppLocale.en: 'Medications'},
  'ei_doctor': {AppLocale.ru: 'Врач', AppLocale.kk: 'Дәрігер', AppLocale.en: 'Doctor'},
  'ei_contact': {AppLocale.ru: 'Экстренный контакт', AppLocale.kk: 'Шұғыл байланыс', AppLocale.en: 'Emergency contact'},
  'ei_notes': {AppLocale.ru: 'Заметки', AppLocale.kk: 'Ескертпелер', AppLocale.en: 'Notes'},
  'ei_name_hint': {AppLocale.ru: 'Имя', AppLocale.kk: 'Аты', AppLocale.en: 'Name'},
  'ei_phone_hint': {AppLocale.ru: 'Телефон', AppLocale.kk: 'Телефон', AppLocale.en: 'Phone'},

  'db_not_measuring': {
    AppLocale.ru: 'Устройство не на связи — данные могут быть неактуальны.',
    AppLocale.kk: 'Құрылғы байланыста емес — деректер ескірген болуы мүмкін.',
    AppLocale.en: 'Device not connected — these readings may be out of date.',
  },
  'db_share_copied': {AppLocale.ru: 'Сводка скопирована', AppLocale.kk: 'Қорытынды көшірілді', AppLocale.en: 'Summary copied to clipboard'},
  'share_summary_title': {AppLocale.ru: 'Сводка здоровья · Ana-Bala', AppLocale.kk: 'Денсаулық қорытындысы · Ana-Bala', AppLocale.en: 'Health summary · Ana-Bala'},
  'share_summary_notes': {AppLocale.ru: 'Заметки', AppLocale.kk: 'Ескертпелер', AppLocale.en: 'Notes'},
  'share_summary_nodata': {AppLocale.ru: 'Пока нет данных', AppLocale.kk: 'Әзірге дерек жоқ', AppLocale.en: 'No readings yet'},
  // Stands where the blood-pressure row used to be when only wrist estimates
  // exist. Approved copy, 2026-08-14. The row itself is DROPPED rather than
  // qualified — unlike temperature, where the qualifier travels with the number
  // — because a wrist BP's accuracy depends on a calibration whose age cannot
  // travel with a line of copied text. This line says what is missing, so its
  // absence is not read as "nothing to report": it states a fact about the
  // instrument and makes no claim about her.
  'share_bp_cuff_only': {AppLocale.ru: 'Давление: тонометром не измерялось', AppLocale.kk: 'Қан қысымы: тонометрмен өлшенбеген', AppLocale.en: 'Blood pressure: not measured with a cuff'},
  'share_status_pregnancy': {AppLocale.ru: 'Беременность · {week} нед.', AppLocale.kk: 'Жүктілік · {week} апта', AppLocale.en: 'Pregnancy · week {week}'},
  'share_status_cycle': {AppLocale.ru: 'Цикл · день {day} · месячные через {n} дн.', AppLocale.kk: 'Цикл · {day}-күн · етеккір {n} күнде', AppLocale.en: 'Cycle · day {day} · period in {n} days'},
  'db_chip_cycle': {AppLocale.ru: 'Цикл · день {n}', AppLocale.kk: 'Цикл · {n}-күн', AppLocale.en: 'Cycle · Day {n}'},
  'db_chip_late': {AppLocale.ru: 'Задержка {n} дн.', AppLocale.kk: '{n} күн кешігу', AppLocale.en: 'Period {n} days late'},
  'vitals_log': {AppLocale.ru: 'Записать показатели', AppLocale.kk: 'Көрсеткіштерді жазу', AppLocale.en: 'Log a reading'},
  // Bare unit labels shown next to a big number. Everywhere a unit appears
  // inside a sentence it is already translated ('кг', 'мм рт. ст.'), so these
  // must match — a Latin 'kg' directly above a Cyrillic 'кг' reads as a bug.
  'unit_kg': {AppLocale.ru: 'кг', AppLocale.kk: 'кг', AppLocale.en: 'kg'},
  // The compact forms ("мм рт.ст.", not "мм рт. ст.") — this sits beside a
  // 27px number inside a metric tile, where the spaced-out form overflowed.
  'unit_mmhg': {AppLocale.ru: 'мм рт.ст.', AppLocale.kk: 'мм с.б.', AppLocale.en: 'mmHg'},
  // ---- Timeline content (lessons + products for the current stage) ----
  // ---- Birth date + city ----
  // Asked for with a reason attached. "Complete your profile" is a chore; what
  // the answer actually changes is a reason to type it.
  'prof_birthdate': {AppLocale.ru: 'Дата рождения', AppLocale.kk: 'Туған күні', AppLocale.en: 'Date of birth'},
  'prof_city': {AppLocale.ru: 'Город', AppLocale.kk: 'Қала', AppLocale.en: 'City'},
  'prof_city_hint': {AppLocale.ru: 'Например, Алматы', AppLocale.kk: 'Мысалы, Алматы', AppLocale.en: 'For example, Almaty'},
  // The home address, asked for with the reason attached — it is on screen 37
  // and nowhere else, and «адрес» without that reason reads as a delivery form.
  'prof_address': {AppLocale.ru: 'Домашний адрес', AppLocale.kk: 'Үй мекенжайы', AppLocale.en: 'Home address'},
  'prof_address_hint': {
    AppLocale.ru: 'Улица, дом, квартира, домофон',
    AppLocale.kk: 'Көше, үй, пәтер, домофон',
    AppLocale.en: 'Street, building, flat, entry code',
  },
  'prof_more_why_address': {
    AppLocale.ru: 'Адрес — его спрашивают первым при вызове 103; экран «Экстренная помощь» покажет его вам.',
    AppLocale.kk: 'Мекенжай — 103-ке қоңырау шалғанда бірінші сұрайды; «Шұғыл көмек» экраны оны көрсетеді.',
    AppLocale.en: 'Your address — it is the first thing 103 asks for, and the emergency screen shows it to you.',
  },
  'prof_age_years': {AppLocale.ru: '{n} лет', AppLocale.kk: '{n} жаста', AppLocale.en: '{n} years old'},
  'prof_more_title': {
    AppLocale.ru: 'Сделать советы точнее',
    AppLocale.kk: 'Кеңестерді дәлірек ету',
    AppLocale.en: 'Make the guidance more precise',
  },
  'prof_more_why_birth': {
    AppLocale.ru: 'Дата рождения — часть обследований и норм зависит от возраста.',
    AppLocale.kk: 'Туған күні — тексерулер мен нормалардың бір бөлігі жасқа байланысты.',
    AppLocale.en: 'Your date of birth — some screenings and ranges depend on age.',
  },
  'prof_more_why_city': {
    AppLocale.ru: 'Город — сроки доставки и товары, доступные рядом с вами.',
    AppLocale.kk: 'Қала — жеткізу мерзімі және жаныңызда қолжетімді тауарлар.',
    AppLocale.en: 'Your city — delivery times and what is actually available near you.',
  },
  'prof_more_cta': {AppLocale.ru: 'Заполнить', AppLocale.kk: 'Толтыру', AppLocale.en: 'Add these'},
  'prof_more_later': {AppLocale.ru: 'Позже', AppLocale.kk: 'Кейінірек', AppLocale.en: 'Later'},
  'prof_more_optional': {
    AppLocale.ru: 'Необязательно — приложение работает и без этого.',
    AppLocale.kk: 'Міндетті емес — қолданба онсыз да жұмыс істейді.',
    AppLocale.en: 'Optional — the app works without them.',
  },
  'tl_title': {AppLocale.ru: 'Для вас сейчас', AppLocale.kk: 'Сізге қазір', AppLocale.en: 'For you now'},
  'tl_stage_week': {AppLocale.ru: '{n}-я неделя', AppLocale.kk: '{n}-апта', AppLocale.en: 'Week {n}'},
  'tl_stage_newborn': {AppLocale.ru: 'Новорождённый', AppLocale.kk: 'Жаңа туған', AppLocale.en: 'Newborn'},
  'tl_stage_month': {AppLocale.ru: '{n} мес.', AppLocale.kk: '{n} ай', AppLocale.en: '{n} months'},
  // The hook: what makes this week worth opening. All of it is factual — how
  // far along, what is next — rather than manufactured urgency.
  'tl_progress_weeks': {
    AppLocale.ru: '{n} из 40 недель · осталось {left}',
    AppLocale.kk: '40 аптаның {n}-сі · {left} қалды',
    AppLocale.en: 'Week {n} of 40 · {left} to go',
  },
  'tl_weeks_left': {AppLocale.ru: '{n} нед.', AppLocale.kk: '{n} апта', AppLocale.en: '{n} wks'},
  'tl_halfway': {AppLocale.ru: 'Половина пути', AppLocale.kk: 'Жолдың жартысы', AppLocale.en: 'Halfway there'},
  'tl_baby_size': {
    AppLocale.ru: 'Малыш размером с {size} · {cm} см',
    AppLocale.kk: 'Бала {size} көлемінде · {cm} см',
    AppLocale.en: 'Baby is the size of {size} · {cm} cm',
  },
  'tl_next_week': {AppLocale.ru: 'На следующей неделе', AppLocale.kk: 'Келесі аптада', AppLocale.en: 'Next week'},
  'tl_next_month': {AppLocale.ru: 'В следующем месяце', AppLocale.kk: 'Келесі айда', AppLocale.en: 'Next month'},
  'tl_month_progress': {
    AppLocale.ru: '{n}-й месяц',
    AppLocale.kk: '{n}-ай',
    AppLocale.en: 'Month {n}',
  },
  'tl_lessons': {AppLocale.ru: 'Видеоуроки', AppLocale.kk: 'Бейнесабақтар', AppLocale.en: 'Video lessons'},
  'tl_products': {AppLocale.ru: 'Товары', AppLocale.kk: 'Тауарлар', AppLocale.en: 'Products'},
  'tl_see_all': {AppLocale.ru: 'Смотреть все', AppLocale.kk: 'Барлығын көру', AppLocale.en: 'See all'},
  'tl_watch': {AppLocale.ru: 'Смотреть', AppLocale.kk: 'Көру', AppLocale.en: 'Watch'},
  // A guide whose content is the text somebody wrote in the back office. It is
  // not «Смотреть»: nothing plays, and a card promising a video that turns out
  // to be an article is a small lie told on every card of its kind.
  'tl_read': {AppLocale.ru: 'Читать', AppLocale.kk: 'Оқу', AppLocale.en: 'Read'},
  'tl_buy': {AppLocale.ru: 'Купить', AppLocale.kk: 'Сатып алу', AppLocale.en: 'Buy'},
  'tl_soon': {AppLocale.ru: 'Скоро', AppLocale.kk: 'Жақында', AppLocale.en: 'Soon'},
  'tl_minutes': {AppLocale.ru: '{n} мин', AppLocale.kk: '{n} мин', AppLocale.en: '{n} min'},
  'tl_empty': {
    AppLocale.ru: 'Укажите срок беременности или дату рождения ребёнка, чтобы видеть материалы для вашего этапа.',
    AppLocale.kk: 'Өз кезеңіңізге арналған материалдарды көру үшін жүктілік мерзімін немесе баланың туған күнін көрсетіңіз.',
    AppLocale.en: 'Add your due date or your child\'s date of birth to see material for your stage.',
  },
  'tl_none_for_stage': {
    AppLocale.ru: 'Для этого этапа материалы пока готовятся.',
    AppLocale.kk: 'Бұл кезеңге арналған материалдар дайындалып жатыр.',
    AppLocale.en: 'Material for this stage is still being prepared.',
  },

  // Screen 27 — «Гиды». The whole published library, not one stage of it.
  'tl_open_guides': {
    AppLocale.ru: 'Все гиды',
    AppLocale.kk: 'Барлық гидтер',
    AppLocale.en: 'All guides',
  },
  'gd_title': {AppLocale.ru: 'Гиды', AppLocale.kk: 'Гидтер', AppLocale.en: 'Guides'},
  'gd_search': {
    AppLocale.ru: 'Поиск по гидам',
    AppLocale.kk: 'Гидтерден іздеу',
    AppLocale.en: 'Search the guides',
  },
  'gd_search_clear': {AppLocale.ru: 'Очистить', AppLocale.kk: 'Тазалау', AppLocale.en: 'Clear'},
  // The amber card. Naming the signs on the card itself, not behind the tap:
  // somebody who is scrolling at 2am has to be able to recognise herself
  // without opening anything.
  'gd_call_title': {
    AppLocale.ru: 'Когда сразу звонить 103',
    AppLocale.kk: 'Қашан бірден 103-ке қоңырау шалу керек',
    AppLocale.en: 'When to call 103 right away',
  },
  'gd_call_body': {
    AppLocale.ru: 'Кровотечение, сильная непроходящая боль, судороги, потеря сознания, '
        'ребёнок дышит с трудом или не приходит в себя — не ждите утра.',
    AppLocale.kk: 'Қан кету, қатты басылмайтын ауырсыну, талма, есінен тану, '
        'бала әрең дем алады немесе есіне келмейді — таңды күтпеңіз.',
    AppLocale.en: 'Bleeding, severe pain that will not pass, seizures, fainting, '
        'a child struggling to breathe or not coming round — do not wait for morning.',
  },
  'gd_call_open': {AppLocale.ru: 'Что делать', AppLocale.kk: 'Не істеу керек', AppLocale.en: 'What to do'},

  // The article screen (admin frame 16a authors it). Named «Красный флаг» —
  // the same words the back office labels the field with, so an editor and a
  // reader are looking at one thing rather than two.
  'art_red_flag': {
    AppLocale.ru: 'Красный флаг',
    AppLocale.kk: 'Қауіпті белгі',
    AppLocale.en: 'Red flag',
  },

  // ---- Screen 37 «Экстренная помощь» -------------------------------------
  //
  // The scenarios themselves are NOT here: they are content, they live in
  // packages/contract/emergency_help.json, and the back office edits them
  // without a release (admin frame 16b). What is here is the furniture — the
  // 103 card, the section headings, the address card and the pediatrician
  // button — which is app chrome and changes with the app.
  'eh_title': {
    AppLocale.ru: 'Экстренная помощь',
    AppLocale.kk: 'Шұғыл көмек',
    AppLocale.en: 'Emergency help',
  },
  'eh_call_103': {
    AppLocale.ru: 'Позвонить 103',
    AppLocale.kk: '103-ке қоңырау шалу',
    AppLocale.en: 'Call 103',
  },
  // On the card itself, above the button. Not «мы вызовем скорую» — this app
  // calls nobody, it opens the dialler, and saying otherwise would be a promise
  // it cannot keep at the worst possible moment.
  'eh_call_body': {
    AppLocale.ru: 'Скорая помощь — бесплатно, круглосуточно, с любого телефона.',
    AppLocale.kk: 'Жедел жәрдем — тегін, тәулік бойы, кез келген телефоннан.',
    AppLocale.en: 'The ambulance service is free, day and night, from any phone.',
  },
  'eh_whats_happening': {
    AppLocale.ru: 'Что происходит?',
    AppLocale.kk: 'Не болып жатыр?',
    AppLocale.en: 'What is happening?',
  },
  'eh_sev_red': {
    AppLocale.ru: 'Звоните 103 сейчас',
    AppLocale.kk: 'Қазір 103-ке қоңырау шалыңыз',
    AppLocale.en: 'Call 103 now',
  },
  'eh_sev_amber': {
    AppLocale.ru: 'Позвоните врачу сегодня',
    AppLocale.kk: 'Бүгін дәрігерге қоңырау шалыңыз',
    AppLocale.en: 'Call the doctor today',
  },
  'eh_do': {AppLocale.ru: 'Что делать', AppLocale.kk: 'Не істеу керек', AppLocale.en: 'What to do'},
  // The address card. Titled for its PURPOSE — the dispatcher asks «адрес?»
  // first, and a card labelled «Адрес» reads as a settings row instead of the
  // line she is meant to read out.
  'eh_address_title': {
    AppLocale.ru: 'Адрес для диспетчера',
    AppLocale.kk: 'Диспетчерге арналған мекенжай',
    AppLocale.en: 'Address for the dispatcher',
  },
  'eh_address_hint': {
    AppLocale.ru: 'Прочитайте это диспетчеру — адрес спрашивают первым.',
    AppLocale.kk: 'Мұны диспетчерге оқып беріңіз — мекенжайды бірінші сұрайды.',
    AppLocale.en: 'Read this out to the dispatcher — the address is the first question.',
  },
  'eh_address_missing': {
    AppLocale.ru: 'Добавьте адрес',
    AppLocale.kk: 'Мекенжай қосыңыз',
    AppLocale.en: 'Add your address',
  },
  'eh_address_missing_body': {
    AppLocale.ru: 'Адрес не сохранён. Добавьте его в профиле — тогда он будет здесь, '
        'когда звонить придётся быстро.',
    AppLocale.kk: 'Мекенжай сақталмаған. Оны профильде қосыңыз — сонда ол тез қоңырау '
        'шалу керек болғанда осында тұрады.',
    AppLocale.en: 'No address saved. Add one in your profile so it is here when the call '
        'has to be quick.',
  },
  'eh_address_copy': {AppLocale.ru: 'Скопировать', AppLocale.kk: 'Көшіру', AppLocale.en: 'Copy'},
  'eh_address_copied': {
    AppLocale.ru: 'Адрес скопирован',
    AppLocale.kk: 'Мекенжай көшірілді',
    AppLocale.en: 'Address copied',
  },
  'eh_call_doctor': {
    AppLocale.ru: 'Позвонить педиатру',
    AppLocale.kk: 'Педиатрға қоңырау шалу',
    AppLocale.en: 'Call the pediatrician',
  },
  'eh_no_doctor': {
    AppLocale.ru: 'Телефон врача не сохранён — добавьте его в профиле.',
    AppLocale.kk: 'Дәрігердің телефоны сақталмаған — оны профильде қосыңыз.',
    AppLocale.en: "The doctor's number is not saved — add it in your profile.",
  },
  // Screen 37 for someone expecting: the row that leads to «Признаки родов».
  // The labour reference answers a different question from this screen — when
  // to set off for the maternity unit, not whether to dial an ambulance — and
  // this line says which one it is so the two are not tapped interchangeably.
  'eh_labour_signs': {
    AppLocale.ru: 'Схватки, воды и когда ехать в роддом',
    AppLocale.kk: 'Толғақ, су кету және перзентханаға қашан бару керек',
    AppLocale.en: 'Contractions, waters, and when to set off',
  },
  // The list could not be loaded AND the bundled copy is unusable. Rare, and
  // the screen still shows the 103 button, so this says what is missing rather
  // than pretending the screen is broken.
  'eh_no_scenarios': {
    AppLocale.ru: 'Список признаков сейчас недоступен. Кнопка вызова выше работает всегда.',
    AppLocale.kk: 'Белгілер тізімі қазір қолжетімсіз. Жоғарыдағы шақыру түймесі әрқашан жұмыс істейді.',
    AppLocale.en: 'The list of signs is unavailable right now. The call button above always works.',
  },
  'gd_topics': {AppLocale.ru: 'Темы', AppLocale.kk: 'Тақырыптар', AppLocale.en: 'Topics'},
  'gd_topic_pregnancy': {
    AppLocale.ru: 'Беременность',
    AppLocale.kk: 'Жүктілік',
    AppLocale.en: 'Pregnancy',
  },
  'gd_topic_baby': {
    AppLocale.ru: 'Малыш до года',
    AppLocale.kk: 'Бір жасқа дейін',
    AppLocale.en: 'The first year',
  },
  'gd_topic_child': {AppLocale.ru: 'Ребёнок', AppLocale.kk: 'Бала', AppLocale.en: 'Child'},
  // Her, not the pregnancy. Nothing about a week implies this shelf, so it
  // fills only when somebody files a card here by hand.
  'gd_topic_mother': {AppLocale.ru: 'Мама', AppLocale.kk: 'Ана', AppLocale.en: 'Mother'},
  'gd_topic_count': {
    AppLocale.ru: '{n} материалов',
    AppLocale.kk: '{n} материал',
    AppLocale.en: '{n} guides',
  },
  'gd_topic_empty': {AppLocale.ru: 'Пока пусто', AppLocale.kk: 'Әзірге бос', AppLocale.en: 'Nothing yet'},
  // «Читают в 7 месяцев» in the spec. Nothing in this app measures who reads
  // what — telemetry_batcher carries vitals and location and nothing else — so
  // a readership number here would be invented. The section says whose stage
  // the material is for, which is true and is the reason it is worth a look.
  'gd_for_stage': {AppLocale.ru: 'Для {stage}', AppLocale.kk: '{stage} үшін', AppLocale.en: 'For {stage}'},
  'gd_results': {AppLocale.ru: 'Найдено: {n}', AppLocale.kk: 'Табылды: {n}', AppLocale.en: 'Found: {n}'},
  'gd_nothing_found': {
    AppLocale.ru: 'Ничего не нашлось. Попробуйте другое слово.',
    AppLocale.kk: 'Ештеңе табылмады. Басқа сөзді байқап көріңіз.',
    AppLocale.en: 'Nothing matched. Try another word.',
  },
  'gd_empty': {
    AppLocale.ru: 'Материалы ещё не загрузились. Они появятся, как только будет связь.',
    AppLocale.kk: 'Материалдар әлі жүктелмеді. Байланыс пайда болғанда көрінеді.',
    AppLocale.en: 'The library has not loaded yet. It appears as soon as there is a connection.',
  },
  'sleep_log_title': {AppLocale.ru: 'Записать сон', AppLocale.kk: 'Ұйқыны жазу', AppLocale.en: 'Log sleep'},
  'sleep_log_sub': {
    AppLocale.ru: 'Укажите, когда легли и когда встали. Стадии сна измеряет только браслет.',
    AppLocale.kk: 'Қашан жатқаныңызды және тұрғаныңызды көрсетіңіз. Ұйқы кезеңдерін тек білезік өлшейді.',
    AppLocale.en: 'Enter when you went to bed and got up. Only the band can measure sleep stages.',
  },
  'sleep_bedtime': {AppLocale.ru: 'Лег(ла) спать', AppLocale.kk: 'Жатқан уақыт', AppLocale.en: 'Went to bed'},
  'sleep_woke': {AppLocale.ru: 'Проснулся(ась)', AppLocale.kk: 'Оянған уақыт', AppLocale.en: 'Woke up'},
  'sleep_awake_min': {AppLocale.ru: 'Не спал(а), мин', AppLocale.kk: 'Ояу болдым, мин', AppLocale.en: 'Awake, minutes'},
  'sleep_awake_hint': {
    AppLocale.ru: 'Примерно, сколько пролежали без сна',
    AppLocale.kk: 'Ұйықтамай жатқан шамамен уақыт',
    AppLocale.en: 'Roughly how long you lay awake',
  },
  'sleep_total': {AppLocale.ru: 'Сон: {h} ч {m} мин', AppLocale.kk: 'Ұйқы: {h} сағ {m} мин', AppLocale.en: 'Asleep: {h}h {m}m'},
  'sleep_err_empty': {
    AppLocale.ru: 'Укажите время отхода ко сну и пробуждения',
    AppLocale.kk: 'Жату және ояну уақытын көрсетіңіз',
    AppLocale.en: 'Set a bedtime and a wake time',
  },
  'sleep_err_too_long': {
    AppLocale.ru: 'Больше 18 часов — проверьте время',
    AppLocale.kk: '18 сағаттан көп — уақытты тексеріңіз',
    AppLocale.en: 'More than 18 hours — check the times',
  },
  'sleep_err_awake': {
    AppLocale.ru: 'Без сна больше, чем всего в постели',
    AppLocale.kk: 'Ояу уақыт төсекте болған уақыттан көп',
    AppLocale.en: 'More time awake than in bed',
  },
  'sleep_err_no_sleep': {
    AppLocale.ru: 'Не осталось времени сна',
    AppLocale.kk: 'Ұйқы уақыты қалмады',
    AppLocale.en: 'That leaves no sleep to record',
  },
  'sleep_logged': {AppLocale.ru: 'Сон записан', AppLocale.kk: 'Ұйқы жазылды', AppLocale.en: 'Sleep logged'},
  'sleep_manual_tag': {AppLocale.ru: 'Вручную', AppLocale.kk: 'Қолмен', AppLocale.en: 'Manual'},
  'vitals_title': {AppLocale.ru: 'Записать показатели', AppLocale.kk: 'Көрсеткіштерді жазу', AppLocale.en: 'Log a reading'},
  'vitals_sub': {AppLocale.ru: 'Заполните то, что измерили — остальное можно пропустить.', AppLocale.kk: 'Өлшегеніңізді толтырыңыз — қалғанын өткізіп жіберуге болады.', AppLocale.en: 'Fill in whatever you measured — the rest can stay empty.'},
  // Name and unit are SEPARATE. Baked into one label, the unit is what a
  // 360dp two-column layout drops first: «Верхнее (мм рт. …» and «Глюкоза
  // (ммоль…». The unit is the half that must survive — somebody reading a
  // glucometer in mg/dL and typing it into a mmol/L field records a number
  // eighteen times too large, and the app triages on these values.
  'vitals_systolic': {AppLocale.ru: 'Верхнее', AppLocale.kk: 'Жоғарғы', AppLocale.en: 'Systolic'},
  'vitals_diastolic': {AppLocale.ru: 'Нижнее', AppLocale.kk: 'Төменгі', AppLocale.en: 'Diastolic'},
  'vitals_hr': {AppLocale.ru: 'Пульс', AppLocale.kk: 'Тамыр соғуы', AppLocale.en: 'Heart rate'},
  'vitals_spo2': {AppLocale.ru: 'Сатурация', AppLocale.kk: 'Қанықтық', AppLocale.en: 'Blood oxygen'},
  'vitals_temp': {AppLocale.ru: 'Температура', AppLocale.kk: 'Дене қызуы', AppLocale.en: 'Temperature'},
  'vitals_glucose': {AppLocale.ru: 'Глюкоза', AppLocale.kk: 'Глюкоза', AppLocale.en: 'Glucose'},
  'vitals_u_mmhg': {AppLocale.ru: 'мм рт. ст.', AppLocale.kk: 'мм с.б.', AppLocale.en: 'mmHg'},
  'vitals_u_bpm': {AppLocale.ru: 'уд/мин', AppLocale.kk: 'соқ/мин', AppLocale.en: 'bpm'},
  'vitals_u_pct': {AppLocale.ru: '%', AppLocale.kk: '%', AppLocale.en: '%'},
  'vitals_u_celsius': {AppLocale.ru: '°C', AppLocale.kk: '°C', AppLocale.en: '°C'},
  'vitals_u_mmol': {AppLocale.ru: 'ммоль/л', AppLocale.kk: 'ммоль/л', AppLocale.en: 'mmol/L'},
  'vitals_err_range': {AppLocale.ru: 'Одно из значений вне допустимого диапазона — проверьте ввод.', AppLocale.kk: 'Мәндердің бірі рұқсат етілген ауқымнан тыс — тексеріңіз.', AppLocale.en: 'One of the values is outside the plausible range — please check it.'},
  'vitals_err_bp_pair': {AppLocale.ru: 'Укажите оба значения давления — верхнее и нижнее.', AppLocale.kk: 'Қысымның екі мәнін де көрсетіңіз.', AppLocale.en: 'Enter both blood-pressure values, upper and lower.'},
  'vitals_err_bp_order': {AppLocale.ru: 'Нижнее давление должно быть меньше верхнего — возможно, они переставлены.', AppLocale.kk: 'Төменгі қысым жоғарғыдан кіші болуы керек — орындары ауысып кеткен шығар.', AppLocale.en: 'The lower value must be below the upper one — they may be swapped.'},
  'vitals_saved': {AppLocale.ru: 'Показатели записаны', AppLocale.kk: 'Көрсеткіштер жазылды', AppLocale.en: 'Reading saved'},
  'audio_title': {AppLocale.ru: 'Аудио дня', AppLocale.kk: 'Күннің аудиосы', AppLocale.en: 'Daily audio'},
  'vitals_scan_cta': {AppLocale.ru: 'Считать с фото прибора', AppLocale.kk: 'Құрылғы фотосынан оқу', AppLocale.en: 'Read from a photo'},
  'vitals_scan_hint': {AppLocale.ru: 'Фото экрана глюкометра, тонометра или анализа', AppLocale.kk: 'Глюкометр, тонометр экраны немесе талдау фотосы', AppLocale.en: 'A photo of a glucometer, BP monitor or lab slip'},
  'med_scan_cta': {AppLocale.ru: 'Заполнить по фото', AppLocale.kk: 'Фотодан толтыру', AppLocale.en: 'Fill from a photo'},
  'med_scan_hint': {AppLocale.ru: 'Фото рецепта или упаковки лекарства', AppLocale.kk: 'Рецепт немесе дәрі қорабының фотосы', AppLocale.en: 'A photo of a prescription or medicine box'},
  'appt_scan_cta': {AppLocale.ru: 'Заполнить по фото', AppLocale.kk: 'Фотодан толтыру', AppLocale.en: 'Fill from a photo'},
  'appt_scan_hint': {AppLocale.ru: 'Фото талона или направления', AppLocale.kk: 'Талон немесе жолдама фотосы', AppLocale.en: 'A photo of a talon or referral'},
  // Generic scan UI, shared by every photo-fill affordance (PhotoScanTile).
  'scan_camera': {AppLocale.ru: 'Камера', AppLocale.kk: 'Камера', AppLocale.en: 'Camera'},
  'scan_gallery': {AppLocale.ru: 'Из галереи', AppLocale.kk: 'Галереядан', AppLocale.en: 'From gallery'},
  'scan_reading': {AppLocale.ru: 'Распознаём…', AppLocale.kk: 'Танып жатырмыз…', AppLocale.en: 'Reading…'},
  'scan_filled': {AppLocale.ru: 'Проверьте распознанное и сохраните', AppLocale.kk: 'Танылғанды тексеріп, сақтаңыз', AppLocale.en: 'Check the recognised details and save'},
  'scan_none': {AppLocale.ru: 'Не удалось распознать — введите вручную', AppLocale.kk: 'Тани алмадық — қолмен енгізіңіз', AppLocale.en: 'Couldn\'t read it — enter it by hand'},
  'scan_error': {AppLocale.ru: 'Не удалось обработать фото. Попробуйте ещё раз.', AppLocale.kk: 'Фотоны өңдеу мүмкін болмады. Қайталап көріңіз.', AppLocale.en: 'Couldn\'t process the photo. Please try again.'},
  'setup_title': {AppLocale.ru: 'Завершите настройку', AppLocale.kk: 'Баптауды аяқтаңыз', AppLocale.en: 'Finish setting up'},
  // Says what it is FOR, not "sign in". Nobody signs in to be signed in; she
  // does it so the app stops being one phone's worth of notes.
  'setup_signin': {
    AppLocale.ru: 'Войдите по номеру телефона — чтобы данные сохранились',
    AppLocale.kk: 'Телефон нөмірімен кіріңіз — деректер сақталуы үшін',
    AppLocale.en: 'Sign in with your phone so nothing is lost',
  },
  'setup_name': {AppLocale.ru: 'Добавьте своё имя в профиле', AppLocale.kk: 'Профильде атыңызды қосыңыз', AppLocale.en: 'Add your name in your profile'},
  'setup_health': {AppLocale.ru: 'Укажите срок родов или отметьте месячные', AppLocale.kk: 'Босану мерзімін немесе етеккірді белгілеңіз', AppLocale.en: 'Set a due date or log your period'},
  'setup_child': {AppLocale.ru: 'Добавьте ребёнка', AppLocale.kk: 'Бала қосыңыз', AppLocale.en: 'Add a child'},
  'setup_zone': {AppLocale.ru: 'Создайте безопасную зону', AppLocale.kk: 'Қауіпсіз аймақ құрыңыз', AppLocale.en: 'Create a safe zone'},
  'setup_details': {AppLocale.ru: 'Укажите дату рождения и город', AppLocale.kk: 'Туған күні мен қаланы көрсетіңіз', AppLocale.en: 'Add your date of birth and city'},
  'setup_backup': {AppLocale.ru: 'Сделайте резервную копию данных', AppLocale.kk: 'Деректердің сақтық көшірмесін жасаңыз', AppLocale.en: 'Back up your data'},
  'db_week_title': {AppLocale.ru: 'Итоги недели', AppLocale.kk: 'Апта қорытындысы', AppLocale.en: 'This week'},
  'db_week_logged': {AppLocale.ru: 'дней отмечено', AppLocale.kk: 'күн белгіленді', AppLocale.en: 'days logged'},
  'db_week_water': {AppLocale.ru: 'стаканов · цель {n} дн.', AppLocale.kk: 'стакан · мақсат {n} күн', AppLocale.en: 'glasses · goal {n}d'},
  'db_week_sleep': {AppLocale.ru: 'сон в среднем', AppLocale.kk: 'орташа ұйқы', AppLocale.en: 'avg sleep'},
  'db_chip_pregnancy': {AppLocale.ru: 'Беременность · {n} нед.', AppLocale.kk: 'Жүктілік · {n}-апта', AppLocale.en: 'Pregnancy · Week {n}'},
  'share_status_cycle_late': {AppLocale.ru: 'Цикл · день {day} · задержка {n} дн.', AppLocale.kk: 'Цикл · {day}-күн · кешігу {n} күн', AppLocale.en: 'Cycle · day {day} · {n} days late'},
  'metric_hr': {AppLocale.ru: 'Пульс', AppLocale.kk: 'Жүрек соғысы', AppLocale.en: 'Heart rate'},
  // Tile labels get one line in a half-width card. The fuller wordings were
  // ellipsised on-device to "Кислород в …", which is worse than naming the
  // metric slightly more briefly.
  'metric_spo2': {AppLocale.ru: 'Кислород', AppLocale.kk: 'Оттегі', AppLocale.en: 'Blood oxygen'},
  'metric_systolic': {AppLocale.ru: 'Систолическое', AppLocale.kk: 'Систолалық', AppLocale.en: 'Systolic'},
  'metric_diastolic': {AppLocale.ru: 'Диастолическое', AppLocale.kk: 'Диастолалық', AppLocale.en: 'Diastolic'},
  // «Дене қызуы» is the Kazakh for body temperature, and it is what every other
  // Kazakh string on this metric already says — em_reading_temp, ADV_TEMP_*,
  // temp_device_estimate_note. The tile label was the one place left in Russian.
  'metric_temp': {AppLocale.ru: 'Температура', AppLocale.kk: 'Дене қызуы', AppLocale.en: 'Temperature'},
  // Screen 05 — «Здоровье · браслета нет». «Апселла браслета здесь нет»:
  // for most users this is the permanent state of the app, not a step towards
  // buying one.
  'noband_title': {
    AppLocale.ru: 'Записывайте вручную',
    AppLocale.kk: 'Қолмен жазыңыз',
    AppLocale.en: 'Log it yourself',
  },
  'noband_body': {
    AppLocale.ru: 'Приложение работает и без браслета: дневник, календари и напоминания — всё то же самое.',
    AppLocale.kk: 'Қолданба білезіксіз де жұмыс істейді: күнделік, күнтізбелер және еске салулар — бәрі сол күйінде.',
    AppLocale.en: 'The app works without a band: the diary, the calendars and the reminders are all the same.',
  },
  'noband_bp': {AppLocale.ru: 'Давление', AppLocale.kk: 'Қысым', AppLocale.en: 'Pressure'},
  'noband_pulse': {AppLocale.ru: 'Пульс', AppLocale.kk: 'Тамыр соғысы', AppLocale.en: 'Pulse'},
  'noband_weight': {AppLocale.ru: 'Вес', AppLocale.kk: 'Салмақ', AppLocale.en: 'Weight'},
  'noband_sleep': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
  'noband_scan_title': {
    AppLocale.ru: 'Сфотографировать тонометр',
    AppLocale.kk: 'Тонометрді суретке түсіру',
    AppLocale.en: 'Photograph your monitor',
  },
  'noband_scan_body': {
    AppLocale.ru: 'Снимок экрана прибора — цифры подставятся сами',
    AppLocale.kk: 'Аспап экранының суреті — сандар өздігінен қойылады',
    AppLocale.en: 'A photo of the display — the numbers fill themselves in',
  },
  'db_empty_title': {AppLocale.ru: 'Пока нет данных', AppLocale.kk: 'Әзірге деректер жоқ', AppLocale.en: 'No readings yet'},
  'db_empty_body': {AppLocale.ru: 'Наденьте браслет — и данные появятся здесь.', AppLocale.kk: 'Білезікті тағыңыз — деректер осында пайда болады.', AppLocale.en: 'Put on your band and readings will appear here.'},
  'db_stats': {AppLocale.ru: 'мин {min} · макс {max} · сред {avg}', AppLocale.kk: 'мин {min} · макс {max} · орт {avg}', AppLocale.en: 'min {min} · max {max} · avg {avg}'},
  'stat_latest': {AppLocale.ru: 'Сейчас', AppLocale.kk: 'Қазір', AppLocale.en: 'Latest'},
  'stat_min': {AppLocale.ru: 'Мин', AppLocale.kk: 'Мин', AppLocale.en: 'Min'},
  'stat_max': {AppLocale.ru: 'Макс', AppLocale.kk: 'Макс', AppLocale.en: 'Max'},
  'stat_avg': {AppLocale.ru: 'Среднее', AppLocale.kk: 'Орташа', AppLocale.en: 'Average'},
  'detail_no_data': {AppLocale.ru: 'Недостаточно данных для графика', AppLocale.kk: 'График үшін деректер жеткіліксіз', AppLocale.en: 'Not enough data to chart yet'},
  'detail_safe_range': {AppLocale.ru: 'Безопасный диапазон', AppLocale.kk: 'Қауіпсіз аралық', AppLocale.en: 'Safe range'},
  'range_24h': {AppLocale.ru: '24 ч', AppLocale.kk: '24 сағ', AppLocale.en: '24h'},
  'range_7d': {AppLocale.ru: '7 дней', AppLocale.kk: '7 күн', AppLocale.en: '7 days'},
  'range_all': {AppLocale.ru: 'Всё', AppLocale.kk: 'Барлығы', AppLocale.en: 'All'},
  'db_outside_range': {AppLocale.ru: ', вне безопасного диапазона', AppLocale.kk: ', қауіпсіз аралықтан тыс', AppLocale.en: ', outside the safe range'},
  // What the peace-of-mind ring says when it has readings and may grade none of
  // them — a day of wrist blood pressure and a wrist temperature, now that both
  // are gated on provenance. The ring used to render a FULL arc in that state,
  // which is an assertion, in the most confident register the screen has, that
  // everything checked is fine on a day when nothing was checked. A shape
  // cannot be qualified, so the shape had to change: empty, dim, and explained
  // in words AND in the semantics tree, because `db_outside_range` was exactly
  // a claim that survived in the announcement after it was removed from the
  // paint.
  //
  // NOT shown when there is nothing to grade at all — that is ADV_GATHERING's
  // job in the banner beside it, and two explanations of two different absences
  // confuse both.
  'db_ring_ungraded': {AppLocale.ru: 'Эти показания приложение не оценивает', AppLocale.kk: 'Бұл көрсеткіштерді қолданба бағаламайды', AppLocale.en: 'The app does not grade these readings'},
  'metric_bp': {AppLocale.ru: 'Давление', AppLocale.kk: 'Қан қысымы', AppLocale.en: 'Blood pressure'},
  // db_peace_stable / db_peace_stable_noname / db_peace_stable_b are DELETED,
  // not reworded (docs/CLINICAL-REVIEW-WATCH.md, refused sentence #21).
  // «Ваши показатели в пределах нормы» was refused sentence #2 and went on
  // shipping unchanged because the peace banner substituted its own copy for
  // the positive tone instead of rendering the advisory — a second copy path
  // that escaped the review, and the reason fixing the advisor alone left the
  // first screen she opens still saying it. The banner now renders
  // ADV_NOTHING_UNUSUAL like every other tone, and her NAME is no longer
  // attached to a normality verdict.
  'db_advisor_cta': {AppLocale.ru: 'Спросите Ana-Bala о ваших данных', AppLocale.kk: 'Ana-Balaдан деректеріңіз туралы сұраңыз', AppLocale.en: 'Ask Ana-Bala about your readings'},
  'db_advisor_sub': {AppLocale.ru: 'Аналитика по данным браслета', AppLocale.kk: 'Білезік деректеріне талдау', AppLocale.en: 'Insights from your band data'},

  // Women's-health calendar
  'nav_calendar': {AppLocale.ru: 'Календарь', AppLocale.kk: 'Күнтізбе', AppLocale.en: 'Calendar'},
  'cal_screen_title': {AppLocale.ru: 'Женское здоровье', AppLocale.kk: 'Әйел денсаулығы', AppLocale.en: "Women's health"},
  // The three calendars, and what to say when one of them has nothing to
  // stand on yet. Never hidden: a calendar she cannot see is a calendar she
  // does not know exists.
  // Weekday column headers for the month grid, index 0 = Sunday.
  //
  // Ours, not the platform's, for two reasons. MaterialLocalizations offers
  // only NARROW names, and the Russian ones are В П В С Ч П С — two Вs, two Пs
  // and two Сs, so three of the seven columns cannot be told apart from their
  // header. And DateFormat.E reads Intl's GLOBAL locale, which nothing in this
  // app ever sets: a Russian screen was headed 'Mo Tu We Th Fr Sa Su' under a
  // Russian month name.
  //
  // The two-letter forms below are the standard abbreviations in each language
  // and are all distinct.
  'cal_dow_0': {AppLocale.ru: 'Вс', AppLocale.kk: 'Жс', AppLocale.en: 'Su'},
  'cal_dow_1': {AppLocale.ru: 'Пн', AppLocale.kk: 'Дс', AppLocale.en: 'Mo'},
  'cal_dow_2': {AppLocale.ru: 'Вт', AppLocale.kk: 'Сс', AppLocale.en: 'Tu'},
  'cal_dow_3': {AppLocale.ru: 'Ср', AppLocale.kk: 'Ср', AppLocale.en: 'We'},
  'cal_dow_4': {AppLocale.ru: 'Чт', AppLocale.kk: 'Бс', AppLocale.en: 'Th'},
  'cal_dow_5': {AppLocale.ru: 'Пт', AppLocale.kk: 'Жм', AppLocale.en: 'Fr'},
  // Saturday's Kazakh was «Сб» — the Russian Суббота, sitting in a column of six
  // correct Kazakh forms. Сенбі abbreviates to «Сн», on the same first-syllable
  // pattern as every other day here (Жек-сенбі → Жс, Дүй-сенбі → Дс, Сәр-сенбі →
  // Ср). Wednesday IS «Ср» in both languages and that collision is genuine; this
  // one was a copy.
  'cal_dow_6': {AppLocale.ru: 'Сб', AppLocale.kk: 'Сн', AppLocale.en: 'Sa'},
  // Under the month grid when there is nothing to colour in yet.
  //
  // With no logged days the grid is thirty grey numbers and one circle, taking
  // nearly half the screen and explaining none of itself — a reader cannot
  // tell whether it is empty, still loading, or simply not for her. It is also
  // the way a day is opened, and nothing said so.
  'cal_grid_empty': {
    AppLocale.ru: 'Нажмите на день, чтобы отметить самочувствие. Когда появятся отмеченные месячные, календарь начнёт показывать прогнозы.',
    AppLocale.kk: 'Күй-жағдайды белгілеу үшін күнді басыңыз. Етеккір күндері белгіленген соң, күнтізбе болжам көрсете бастайды.',
    AppLocale.en: 'Tap a day to log how you feel. Once some period days are marked, the calendar starts showing predictions.',
  },
  'cal_mode_cycle': {AppLocale.ru: 'Цикл', AppLocale.kk: 'Цикл', AppLocale.en: 'Cycle'},
  'cal_mode_pregnancy': {AppLocale.ru: 'Беременность', AppLocale.kk: 'Жүктілік', AppLocale.en: 'Pregnancy'},
  'cal_mode_child': {AppLocale.ru: 'Ребёнок', AppLocale.kk: 'Бала', AppLocale.en: 'Child'},
  'cal_child_empty_title': {AppLocale.ru: 'Календарь развития ребёнка', AppLocale.kk: 'Бала дамуының күнтізбесі', AppLocale.en: 'Child development calendar'},
  'cal_child_empty_body': {
    AppLocale.ru: 'Добавьте ребёнка и его дату рождения — и здесь появится, что он умеет сейчас и что будет дальше.',
    AppLocale.kk: 'Баланы және оның туған күнін қосыңыз — осында қазір не істей алатыны және әрі қарай не болатыны шығады.',
    AppLocale.en: 'Add a child and their date of birth, and this will show what they can do now and what comes next.',
  },
  'cal_child_of': {AppLocale.ru: 'Календарь для: {name}', AppLocale.kk: 'Күнтізбе: {name}', AppLocale.en: 'Calendar for {name}'},
  'cal_no_due_title': {AppLocale.ru: 'Добавьте срок беременности', AppLocale.kk: 'Жүктілік мерзімін қосыңыз', AppLocale.en: 'Add your due date'},
  'cal_no_due_body': {
    AppLocale.ru: 'Укажите предполагаемую дату родов, чтобы отслеживать неделю беременности.',
    AppLocale.kk: 'Болжамды босану күнін көрсетіп, жүктілік аптасын қадағалаңыз.',
    AppLocale.en: 'Set your estimated due date to track your pregnancy week.'
  },
  'cal_due_pick': {AppLocale.ru: 'Дата родов', AppLocale.kk: 'Босану күні', AppLocale.en: 'Due date'},
  'gest_week': {AppLocale.ru: 'Неделя {w}, день {d}', AppLocale.kk: '{w}-апта, {d}-күн', AppLocale.en: 'Week {w}, Day {d}'},
  // Week browser (prev/next weeks on the week-detail screen)
  'wk_label': {AppLocale.ru: 'Неделя {w}', AppLocale.kk: '{w}-апта', AppLocale.en: 'Week {w}'},
  'wk_current': {AppLocale.ru: 'Текущая', AppLocale.kk: 'Қазіргі', AppLocale.en: 'Current'},
  'wk_to_current': {AppLocale.ru: 'К текущей неделе', AppLocale.kk: 'Ағымдағы аптаға', AppLocale.en: 'Back to current week'},
  'wk_prev': {AppLocale.ru: 'Предыдущая неделя', AppLocale.kk: 'Алдыңғы апта', AppLocale.en: 'Previous week'},
  'wk_next': {AppLocale.ru: 'Следующая неделя', AppLocale.kk: 'Келесі апта', AppLocale.en: 'Next week'},
  'bsize_title': {AppLocale.ru: 'Размер малыша', AppLocale.kk: 'Нәресте өлшемі', AppLocale.en: 'Baby size'},
  'bsize_about': {AppLocale.ru: 'Примерно как {food}', AppLocale.kk: 'Шамамен {food} көлемінде', AppLocale.en: 'About the size of a {food}'},
  'bsize_length': {AppLocale.ru: '≈ {cm} см в длину', AppLocale.kk: '≈ {cm} см ұзындық', AppLocale.en: '≈ {cm} cm long'},
  'bsize_poppyseed': {AppLocale.ru: 'маковое зёрнышко', AppLocale.kk: 'көкнәр дәні', AppLocale.en: 'poppy seed'},
  'bsize_sesame': {AppLocale.ru: 'кунжутное семечко', AppLocale.kk: 'күнжіт дәні', AppLocale.en: 'sesame seed'},
  'bsize_lentil': {AppLocale.ru: 'чечевица', AppLocale.kk: 'жасымық', AppLocale.en: 'lentil'},
  'bsize_blueberry': {AppLocale.ru: 'черника', AppLocale.kk: 'көкжидек', AppLocale.en: 'blueberry'},
  'bsize_raspberry': {AppLocale.ru: 'малина', AppLocale.kk: 'таңқурай', AppLocale.en: 'raspberry'},
  'bsize_grape': {AppLocale.ru: 'виноградина', AppLocale.kk: 'жүзім', AppLocale.en: 'grape'},
  'bsize_strawberry': {AppLocale.ru: 'клубника', AppLocale.kk: 'құлпынай', AppLocale.en: 'strawberry'},
  'bsize_fig': {AppLocale.ru: 'инжир', AppLocale.kk: 'інжір', AppLocale.en: 'fig'},
  'bsize_lime': {AppLocale.ru: 'лайм', AppLocale.kk: 'лайм', AppLocale.en: 'lime'},
  'bsize_lemon': {AppLocale.ru: 'лимон', AppLocale.kk: 'лимон', AppLocale.en: 'lemon'},
  'bsize_peach': {AppLocale.ru: 'персик', AppLocale.kk: 'шабдалы', AppLocale.en: 'peach'},
  'bsize_avocado': {AppLocale.ru: 'авокадо', AppLocale.kk: 'авокадо', AppLocale.en: 'avocado'},
  'bsize_bellpepper': {AppLocale.ru: 'болгарский перец', AppLocale.kk: 'болгар бұрышы', AppLocale.en: 'bell pepper'},
  'bsize_banana': {AppLocale.ru: 'банан', AppLocale.kk: 'банан', AppLocale.en: 'banana'},
  'bsize_papaya': {AppLocale.ru: 'папайя', AppLocale.kk: 'папайя', AppLocale.en: 'papaya'},
  'bsize_corn': {AppLocale.ru: 'початок кукурузы', AppLocale.kk: 'жүгері собығы', AppLocale.en: 'ear of corn'},
  'bsize_lettuce': {AppLocale.ru: 'кочан салата', AppLocale.kk: 'салат басы', AppLocale.en: 'head of lettuce'},
  'bsize_eggplant': {AppLocale.ru: 'баклажан', AppLocale.kk: 'баялды', AppLocale.en: 'eggplant'},
  'bsize_cabbage': {AppLocale.ru: 'кочан капусты', AppLocale.kk: 'қырыжқабат', AppLocale.en: 'cabbage'},
  'bsize_squash': {AppLocale.ru: 'тыква-кабачок', AppLocale.kk: 'асқабақ', AppLocale.en: 'squash'},
  'bsize_cantaloupe': {AppLocale.ru: 'дыня-канталупа', AppLocale.kk: 'қауын (канталупа)', AppLocale.en: 'cantaloupe'},
  'bsize_honeydew': {AppLocale.ru: 'медовая дыня', AppLocale.kk: 'бал қауын', AppLocale.en: 'honeydew melon'},
  'bsize_pumpkin': {AppLocale.ru: 'небольшая тыква', AppLocale.kk: 'кішкене асқабақ', AppLocale.en: 'small pumpkin'},
  'bsize_watermelon': {AppLocale.ru: 'арбуз', AppLocale.kk: 'қарбыз', AppLocale.en: 'watermelon'},
  'gest_days_left': {AppLocale.ru: 'Осталось {n} дней', AppLocale.kk: '{n} күн қалды', AppLocale.en: '{n} days to go'},
  'gest_overdue': {AppLocale.ru: 'Срок подошёл', AppLocale.kk: 'Мерзімі жетті', AppLocale.en: 'Any day now'},
  'gest_trimester': {AppLocale.ru: '{n}-й триместр', AppLocale.kk: '{n}-триместр', AppLocale.en: 'Trimester {n}'},
  'gest_wk_short': {AppLocale.ru: 'нед', AppLocale.kk: 'апта', AppLocale.en: 'wk'},
  'gest_milestones': {AppLocale.ru: 'Этапы', AppLocale.kk: 'Кезеңдер', AppLocale.en: 'Milestones'},
  'ms_now': {AppLocale.ru: 'Сейчас', AppLocale.kk: 'Қазір', AppLocale.en: 'Now'},
  'ms_next_in': {AppLocale.ru: 'через {n} нед.', AppLocale.kk: '{n} аптадан кейін', AppLocale.en: 'in {n} wks'},
  'MS_FIRST_TRIMESTER': {AppLocale.ru: 'Первый триместр', AppLocale.kk: 'Бірінші триместр', AppLocale.en: 'First trimester'},
  'MS_SECOND_TRIMESTER': {AppLocale.ru: 'Второй триместр', AppLocale.kk: 'Екінші триместр', AppLocale.en: 'Second trimester'},
  'MS_HALFWAY': {AppLocale.ru: 'Половина пути', AppLocale.kk: 'Жарты жол', AppLocale.en: 'Halfway there'},
  'MS_THIRD_TRIMESTER': {AppLocale.ru: 'Третий триместр', AppLocale.kk: 'Үшінші триместр', AppLocale.en: 'Third trimester'},
  'MS_FULL_TERM': {AppLocale.ru: 'Доношенный срок', AppLocale.kk: 'Толық мерзім', AppLocale.en: 'Full term'},
  'MS_DUE': {AppLocale.ru: 'Срок родов', AppLocale.kk: 'Босану мерзімі', AppLocale.en: 'Due date'},
  // ---- Child growth ----
  'grw_title': {AppLocale.ru: 'Рост и вес', AppLocale.kk: 'Бой және салмақ', AppLocale.en: 'Growth'},
  'grw_weight': {AppLocale.ru: 'Вес', AppLocale.kk: 'Салмақ', AppLocale.en: 'Weight'},
  'grw_height': {AppLocale.ru: 'Рост', AppLocale.kk: 'Бой', AppLocale.en: 'Height'},
  'grw_add': {AppLocale.ru: 'Добавить измерение', AppLocale.kk: 'Өлшем қосу', AppLocale.en: 'Add a measurement'},
  'grw_empty': {AppLocale.ru: 'Запишите вес и рост после приёма — приложение покажет, как они меняются.', AppLocale.kk: 'Қабылдаудан кейін салмақ пен бойды жазыңыз — қосымша олардың өзгерісін көрсетеді.', AppLocale.en: 'Record weight and height after a check-up and the app will show how they change.'},
  'grw_since': {AppLocale.ru: 'за {n} дн.', AppLocale.kk: '{n} күнде', AppLocale.en: 'in {n} days'},
  'grw_first': {AppLocale.ru: 'первое измерение', AppLocale.kk: 'алғашқы өлшем', AppLocale.en: 'first measurement'},
  'grw_kg': {AppLocale.ru: 'кг', AppLocale.kk: 'кг', AppLocale.en: 'kg'},
  'grw_cm': {AppLocale.ru: 'см', AppLocale.kk: 'см', AppLocale.en: 'cm'},
  'grw_bad_weight': {AppLocale.ru: 'Проверьте вес — похоже на опечатку.', AppLocale.kk: 'Салмақты тексеріңіз — қате сияқты.', AppLocale.en: 'Check the weight — that looks like a typo.'},
  'grw_bad_height': {AppLocale.ru: 'Проверьте рост — похоже на опечатку.', AppLocale.kk: 'Бойды тексеріңіз — қате сияқты.', AppLocale.en: 'Check the height — that looks like a typo.'},
  // Said where it cannot be mistaken for modesty: the app is not comparing her
  // child to anyone, and should not be read as doing so.
  'child_care': {AppLocale.ru: 'Здоровье и развитие', AppLocale.kk: 'Денсаулық және даму', AppLocale.en: 'Health & development'},
  // ---- Newborn daily log ----
  'nb_title': {AppLocale.ru: 'Дневник малыша', AppLocale.kk: 'Бала күнделігі', AppLocale.en: 'Baby log'},
  'nb_today': {AppLocale.ru: 'Сегодня', AppLocale.kk: 'Бүгін', AppLocale.en: 'Today'},
  'nb_feeds': {AppLocale.ru: 'Кормления', AppLocale.kk: 'Тамақтандыру', AppLocale.en: 'Feeds'},
  'nb_diapers': {AppLocale.ru: 'Подгузники', AppLocale.kk: 'Жаялықтар', AppLocale.en: 'Diapers'},
  // Screen 22 — «Ночь · кормление». A night screen: one hand, no sound.
  'nightfeed_entry_title': {AppLocale.ru: 'Ночное кормление', AppLocale.kk: 'Түнгі емізу', AppLocale.en: 'Night feeding'},
  'nightfeed_entry_body': {
    AppLocale.ru: 'Таймер на тёмном экране — не разбудит',
    AppLocale.kk: 'Қараңғы экрандағы таймер — оятпайды',
    AppLocale.en: 'A timer on a dark screen — it will not wake anyone',
  },
  'nightfeed_title': {AppLocale.ru: 'Кормление', AppLocale.kk: 'Емізу', AppLocale.en: 'Feeding'},
  'nightfeed_quiet_hours': {
    AppLocale.ru: 'Тихие часы — экран приглушён, звуков не будет',
    AppLocale.kk: 'Тыныш сағаттар — экран күңгірт, дыбыс болмайды',
    AppLocale.en: 'Quiet hours — the screen is dimmed and nothing will sound',
  },
  'nightfeed_ready': {AppLocale.ru: 'Готово к началу', AppLocale.kk: 'Бастауға дайын', AppLocale.en: 'Ready to start'},
  'nightfeed_feeding': {AppLocale.ru: 'Идёт кормление', AppLocale.kk: 'Емізу жүріп жатыр', AppLocale.en: 'Feeding'},
  'nightfeed_paused': {AppLocale.ru: 'Пауза', AppLocale.kk: 'Кідіріс', AppLocale.en: 'Paused'},
  'nightfeed_start': {AppLocale.ru: 'Начать кормление', AppLocale.kk: 'Емізуді бастау', AppLocale.en: 'Start feeding'},
  'nightfeed_pause': {AppLocale.ru: 'Пауза', AppLocale.kk: 'Кідірту', AppLocale.en: 'Pause'},
  'nightfeed_resume': {AppLocale.ru: 'Продолжить', AppLocale.kk: 'Жалғастыру', AppLocale.en: 'Resume'},
  'nightfeed_finish': {AppLocale.ru: 'Закончить', AppLocale.kk: 'Аяқтау', AppLocale.en: 'Finish'},
  'nightfeed_last': {AppLocale.ru: 'Прошлое кормление', AppLocale.kk: 'Өткен емізу', AppLocale.en: 'Last feed'},
  'nightfeed_today': {AppLocale.ru: 'За сутки', AppLocale.kk: 'Тәулігіне', AppLocale.en: 'Today'},
  'nightfeed_none_yet': {AppLocale.ru: 'ещё не было', AppLocale.kk: 'әлі болған жоқ', AppLocale.en: 'none yet'},
  'nightfeed_ago': {AppLocale.ru: '{n} мин назад', AppLocale.kk: '{n} мин бұрын', AppLocale.en: '{n} min ago'},
  'nightfeed_count': {AppLocale.ru: '{n} кормлений', AppLocale.kk: '{n} рет емізу', AppLocale.en: '{n} feeds'},
  'nightfeed_one_hand': {
    AppLocale.ru: 'Кнопки крупные — чтобы попасть одной рукой в темноте.',
    AppLocale.kk: 'Түймелер ірі — қараңғыда бір қолмен басу үшін.',
    AppLocale.en: 'The buttons are large — to hit one-handed in the dark.',
  },
  'nb_sleep': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
  'nb_feed': {AppLocale.ru: 'Кормление', AppLocale.kk: 'Тамақтандыру', AppLocale.en: 'Feed'},
  'nb_diaper': {AppLocale.ru: 'Подгузник', AppLocale.kk: 'Жаялық', AppLocale.en: 'Diaper'},
  'nb_add_feed': {AppLocale.ru: 'Кормление', AppLocale.kk: 'Тамақтандыру', AppLocale.en: 'Feed'},
  'nb_add_diaper': {AppLocale.ru: 'Подгузник', AppLocale.kk: 'Жаялық', AppLocale.en: 'Diaper'},
  'nb_add_sleep': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
  'nb_left': {AppLocale.ru: 'Левая', AppLocale.kk: 'Сол', AppLocale.en: 'Left'},
  'nb_right': {AppLocale.ru: 'Правая', AppLocale.kk: 'Оң', AppLocale.en: 'Right'},
  'nb_bottle': {AppLocale.ru: 'Бутылочка', AppLocale.kk: 'Бөтелке', AppLocale.en: 'Bottle'},
  'nb_dur_hm': {AppLocale.ru: '{h} ч {m} мин', AppLocale.kk: '{h} сағ {m} мин', AppLocale.en: '{h}h {m}m'},
  'nb_dur_m': {AppLocale.ru: '{m} мин', AppLocale.kk: '{m} мин', AppLocale.en: '{m}m'},
  'nb_wet': {AppLocale.ru: 'Мокрый', AppLocale.kk: 'Дымқыл', AppLocale.en: 'Wet'},
  'nb_dirty': {AppLocale.ru: 'Грязный', AppLocale.kk: 'Кір', AppLocale.en: 'Dirty'},
  'nb_both': {AppLocale.ru: 'Оба', AppLocale.kk: 'Екеуі', AppLocale.en: 'Both'},
  'nb_last': {AppLocale.ru: 'Последнее: {ago}', AppLocale.kk: 'Соңғы: {ago}', AppLocale.en: 'Last: {ago}'},
  'nb_wet_count': {AppLocale.ru: 'мокрых: {n}', AppLocale.kk: 'дымқыл: {n}', AppLocale.en: '{n} wet'},
  'nb_empty': {AppLocale.ru: 'Отмечайте кормления, подгузники и сон — это то, о чём спросят на приёме.', AppLocale.kk: 'Тамақтандыру, жаялық пен ұйқыны белгілеңіз — қабылдауда осыны сұрайды.', AppLocale.en: 'Tap to log feeds, diapers and sleep — the things the clinic will ask about.'},
  // The 7-day recall — the numbers a clinic asks for at a check-up, which a
  // sleep-deprived parent cannot hold in their head.
  'nb_week_title': {AppLocale.ru: 'Последние 7 дней', AppLocale.kk: 'Соңғы 7 күн', AppLocale.en: 'Last 7 days'},
  'nb_week_feeds_avg': {AppLocale.ru: 'Кормлений в день: {n}', AppLocale.kk: 'Күніне тамақтандыру: {n}', AppLocale.en: 'Feeds per day: {n}'},
  'nb_week_wet_avg': {AppLocale.ru: 'Мокрых подгузников в день: {n}', AppLocale.kk: 'Күніне дымқыл жаялық: {n}', AppLocale.en: 'Wet diapers per day: {n}'},
  'nb_week_over': {AppLocale.ru: 'В среднем по {n} дн. с записями', AppLocale.kk: 'Жазбасы бар {n} күн бойынша орташа', AppLocale.en: 'Averaged over {n} days with entries'},
  'nb_week_none': {AppLocale.ru: 'нет', AppLocale.kk: 'жоқ', AppLocale.en: 'none'},
  'nb_delete_title': {AppLocale.ru: 'Удалить запись?', AppLocale.kk: 'Жазбаны жою керек пе?', AppLocale.en: 'Delete this entry?'},
  'nb_delete_body': {AppLocale.ru: 'Эту отметку нельзя будет вернуть.', AppLocale.kk: 'Бұл белгіні қайтару мүмкін болмайды.', AppLocale.en: 'This entry cannot be restored.'},
  'grw_history': {AppLocale.ru: 'История измерений', AppLocale.kk: 'Өлшемдер тарихы', AppLocale.en: 'Measurement history'},
  'grw_delete_title': {AppLocale.ru: 'Удалить измерение?', AppLocale.kk: 'Өлшемді жою керек пе?', AppLocale.en: 'Delete this measurement?'},
  'grw_delete_body': {AppLocale.ru: 'Запись за этот день будет удалена. Это действие нельзя отменить.', AppLocale.kk: 'Осы күнгі жазба жойылады. Бұл әрекетті болдырмау мүмкін емес.', AppLocale.en: 'The entry for this day will be removed. This cannot be undone.'},
  'grw_delete': {AppLocale.ru: 'Удалить', AppLocale.kk: 'Жою', AppLocale.en: 'Delete'},
  'grw_no_percentiles': {
    AppLocale.ru: 'Это график вашего ребёнка относительно него самого, без центильных коридоров. Сравнение с нормами ВОЗ делает врач на приёме.',
    AppLocale.kk: 'Бұл — балаңыздың өз көрсеткіштерінің графигі, центильдік дәліздерсіз. ДДҰ нормаларымен салыстыруды дәрігер қабылдауда жасайды.',
    AppLocale.en: 'This charts your child against their own history, without percentile bands. Comparing to WHO norms is your doctor’s job at the check-up.',
  },
  // ---- End of pregnancy ----
  //
  // Two outcomes, two paths, and the wording of each matters more than most
  // copy in this app. One door for both meant a woman who had just lost a
  // pregnancy was offered a cheerful "add your baby" prompt.
  'birth_which': {AppLocale.ru: 'Что произошло?', AppLocale.kk: 'Не болды?', AppLocale.en: 'What happened?'},
  'birth_born': {AppLocale.ru: 'Малыш родился', AppLocale.kk: 'Бала дүниеге келді', AppLocale.en: 'The baby is here'},
  'birth_born_sub': {AppLocale.ru: 'Перенесём дату рождения в календарь развития и прививок', AppLocale.kk: 'Туған күнді даму және егу күнтізбесіне көшіреміз', AppLocale.en: 'We will carry the birth date into the development and vaccination calendars'},
  'birth_other': {AppLocale.ru: 'Просто выключить отслеживание', AppLocale.kk: 'Бақылауды өшіру', AppLocale.en: 'Just turn tracking off'},
  'birth_other_sub': {AppLocale.ru: 'Вернётся календарь цикла. Ваши записи останутся.', AppLocale.kk: 'Цикл күнтізбесі қайтады. Жазбаларыңыз сақталады.', AppLocale.en: 'Cycle tracking returns. Your logs are kept.'},
  'birth_title': {AppLocale.ru: 'Поздравляем!', AppLocale.kk: 'Құттықтаймыз!', AppLocale.en: 'Congratulations'},
  'birth_date': {AppLocale.ru: 'Дата рождения', AppLocale.kk: 'Туған күні', AppLocale.en: 'Date of birth'},
  'birth_name': {AppLocale.ru: 'Имя (можно позже)', AppLocale.kk: 'Аты (кейін де болады)', AppLocale.en: 'Name (can wait)'},
  'birth_save': {AppLocale.ru: 'Готово', AppLocale.kk: 'Дайын', AppLocale.en: 'Done'},
  'birth_done': {AppLocale.ru: 'Календарь развития и прививок открыт', AppLocale.kk: 'Даму және егу күнтізбесі ашылды', AppLocale.en: 'The development and vaccination calendars are ready'},
  // ---- Vaccination calendar (Kazakhstan national schedule) ----
  'vac_title': {AppLocale.ru: 'Прививки', AppLocale.kk: 'Егулер', AppLocale.en: 'Vaccinations'},
  'vac_sub': {AppLocale.ru: 'Национальный календарь Казахстана', AppLocale.kk: 'Қазақстанның ұлттық күнтізбесі', AppLocale.en: 'Kazakhstan national schedule'},
  'vac_due': {AppLocale.ru: 'Пора', AppLocale.kk: 'Уақыты келді', AppLocale.en: 'Due now'},
  'vac_next': {AppLocale.ru: 'Следующий визит', AppLocale.kk: 'Келесі бару', AppLocale.en: 'Next visit'},
  'vac_passed': {AppLocale.ru: 'По плану раньше', AppLocale.kk: 'Жоспар бойынша ертерек', AppLocale.en: 'Scheduled earlier'},
  'vac_catchup': {AppLocale.ru: 'Стоит уточнить или наверстать', AppLocale.kk: 'Тексерген немесе толықтырған жөн', AppLocale.en: 'Worth checking or catching up'},
  'vac_in_months': {AppLocale.ru: 'через {n} мес.', AppLocale.kk: '{n} айдан кейін', AppLocale.en: 'in {n} months'},
  'vac_at_birth': {AppLocale.ru: 'В роддоме', AppLocale.kk: 'Перзентханада', AppLocale.en: 'At the maternity hospital'},
  'vac_at_month': {AppLocale.ru: 'В {n} мес.', AppLocale.kk: '{n} айда', AppLocale.en: 'At {n} months'},
  'vac_dose': {AppLocale.ru: 'доза {n}', AppLocale.kk: '{n}-доза', AppLocale.en: 'dose {n}'},
  'vac_complete': {AppLocale.ru: 'Календарь пройден', AppLocale.kk: 'Күнтізбе аяқталды', AppLocale.en: 'Schedule complete'},
  // The app does not read clinic records, and must not imply it does.
  'vac_disclaimer': {
    AppLocale.ru: 'Это календарь, а не медкарта: приложение не знает, какие прививки уже сделаны. Отметки в паспорте здоровья ведёт поликлиника.',
    AppLocale.kk: 'Бұл күнтізбе, медициналық карта емес: қосымша қандай егулер жасалғанын білмейді. Денсаулық паспортындағы белгілерді емхана жүргізеді.',
    AppLocale.en: 'This is a schedule, not a medical record: the app does not know which vaccinations have been given. The clinic keeps that record.',
  },
  'vac_revision': {AppLocale.ru: 'Календарь по состоянию на {d}', AppLocale.kk: '{d} жағдайы бойынша күнтізбе', AppLocale.en: 'Schedule as of {d}'},
  // Shown INSTEAD of vac_revision once a server answer has been applied: the
  // build's own date would then be a claim about the wrong table.
  'vac_source_server': {AppLocale.ru: 'Календарь обновлён из приложения Ана-Бала', AppLocale.kk: 'Күнтізбе Ана-Бала қосымшасынан жаңартылды', AppLocale.en: 'Schedule updated from the Ana-Bala service'},
  // The next-visit reminder notification.
  'vac_reminder_title': {AppLocale.ru: 'Скоро прививки', AppLocale.kk: 'Егулердің уақыты жақындады', AppLocale.en: 'Vaccinations coming up'},
  'vac_reminder_body': {AppLocale.ru: 'У {name} по плану визит в поликлинику. Проверьте календарь прививок.', AppLocale.kk: '{name} үшін емханаға бару жоспарланған. Егу күнтізбесін тексеріңіз.', AppLocale.en: "{name} has a clinic visit due. Check the vaccination schedule."},
  'vac_reminder_on': {AppLocale.ru: 'Напомним {d}', AppLocale.kk: '{d} еске саламыз', AppLocale.en: "We'll remind you on {d}"},

  // ---- Postpartum recovery (the mother's own recovery after birth) ----
  'pp_title': {AppLocale.ru: 'После родов', AppLocale.kk: 'Босанғаннан кейін', AppLocale.en: 'After birth'},
  'pp_card_title': {AppLocale.ru: 'Восстановление после родов', AppLocale.kk: 'Босанғаннан кейінгі қалпына келу', AppLocale.en: 'Recovery after birth'},
  'pp_card_sub': {AppLocale.ru: 'Что нормально сейчас и когда звонить врачу', AppLocale.kk: 'Қазір не қалыпты және қашан дәрігерге қоңырау шалу керек', AppLocale.en: 'What is normal now, and when to call a doctor'},
  'pp_disclaimer': {
    AppLocale.ru: 'Это общие сведения, а не медицинская консультация. При любых сомнениях звоните в свою поликлинику. При признаках ниже не ждите.',
    AppLocale.kk: 'Бұл — жалпы мәлімет, медициналық кеңес емес. Кез келген күмәнда өз емханаңызға қоңырау шалыңыз. Төмендегі белгілерде күтпеңіз.',
    AppLocale.en: 'This is general information, not medical advice. When in doubt, call your clinic. For the signs below, do not wait.',
  },
  'pp_now_title': {AppLocale.ru: 'Сейчас важно', AppLocale.kk: 'Қазір маңызды', AppLocale.en: 'Right now'},

  'pp_area_bleeding': {AppLocale.ru: 'Выделения', AppLocale.kk: 'Бөліністер', AppLocale.en: 'Bleeding'},
  'pp_area_body': {AppLocale.ru: 'Тело', AppLocale.kk: 'Дене', AppLocale.en: 'Body'},
  'pp_area_emotional': {AppLocale.ru: 'Настроение', AppLocale.kk: 'Көңіл-күй', AppLocale.en: 'Mood'},
  'pp_area_care': {AppLocale.ru: 'Забота о себе', AppLocale.kk: 'Өзіңе қамқорлық', AppLocale.en: 'Looking after yourself'},

  'pp_check_title': {AppLocale.ru: 'Осмотр после родов', AppLocale.kk: 'Босанғаннан кейінгі тексеру', AppLocale.en: 'Postnatal check'},
  'pp_check_in': {AppLocale.ru: 'примерно через {n} дн.', AppLocale.kk: 'шамамен {n} күннен кейін', AppLocale.en: 'in about {n} days'},
  'pp_check_past': {AppLocale.ru: 'Пройдите его, если ещё не были', AppLocale.kk: 'Әлі болмасаңыз, барыңыз', AppLocale.en: "Have it if you haven't yet"},
  'pp_check_body': {
    AppLocale.ru: 'На 6-й неделе врач проверит восстановление и настроение и поможет с контрацепцией.',
    AppLocale.kk: '6-шы аптада дәрігер қалпына келуіңіз бен көңіл-күйіңізді тексеріп, контрацепцияға көмектеседі.',
    AppLocale.en: 'Around six weeks, a clinician checks your recovery and mood, and helps with contraception.',
  },

  'pp_warn_title': {AppLocale.ru: 'Когда обращаться за помощью', AppLocale.kk: 'Қашан көмекке жүгіну керек', AppLocale.en: 'When to get help'},
  'pp_warn_intro': {
    AppLocale.ru: 'Свяжитесь с поликлиникой или скорой, если появится что-то из этого:',
    AppLocale.kk: 'Мыналардың бірі пайда болса, емханаға немесе жедел жәрдемге хабарласыңыз:',
    AppLocale.en: 'Contact your clinic or emergency services if any of these appear:',
  },

  // Recovery notes (pp_note_<id>).
  'pp_note_lochia_early': {
    AppLocale.ru: 'Кровянистые выделения (лохии) в первые дни обильные и ярко-красные — это нормально. Пользуйтесь послеродовыми прокладками, не тампонами.',
    AppLocale.kk: 'Алғашқы күндері қанды бөліністер (лохия) мол әрі ашық қызыл болады — бұл қалыпты. Тампон емес, босанғаннан кейінгі прокладка қолданыңыз.',
    AppLocale.en: 'Bleeding (lochia) is heavy and bright red in the first days — this is normal. Use maternity pads, not tampons.',
  },
  'pp_note_rest': {
    AppLocale.ru: 'Отдыхайте, когда спит малыш. Тело заживает, и сон — часть восстановления, а не роскошь.',
    AppLocale.kk: 'Нәресте ұйықтағанда сіз де демалыңыз. Дене жазылып жатыр, ал ұйқы — сәнділік емес, қалпына келудің бөлігі.',
    AppLocale.en: 'Rest when the baby sleeps. Your body is healing, and sleep is part of recovery, not a luxury.',
  },
  'pp_note_soreness': {
    AppLocale.ru: 'Боль в промежности или в области шва обычна в первые недели. Помогают прохладные компрессы и разрешённое врачом обезболивающее.',
    AppLocale.kk: 'Алғашқы апталарда шат аймағындағы немесе тігіс маңындағы ауырсыну — қалыпты. Салқын компресс пен дәрігер рұқсат еткен ауырсынуды басатын дәрі көмектеседі.',
    AppLocale.en: 'Soreness around the perineum or a stitch is common in the first weeks. Cool packs and pain relief your doctor approves can help.',
  },
  'pp_note_blues': {
    AppLocale.ru: 'Слёзы, тревога и перепады настроения в первые дни — «бэби-блюз», через это проходят большинство женщин. Обычно проходит к концу второй недели.',
    AppLocale.kk: 'Алғашқы күндердегі көз жасы, мазасыздық пен көңіл-күйдің құбылуы — «бэби-блюз», мұны әйелдердің көбі бастан кешіреді. Әдетте екінші аптаның соңына қарай басылады.',
    AppLocale.en: "Tears, anxiety and mood swings in the first days — the 'baby blues' — happen to most women. They usually ease by the end of the second week.",
  },
  'pp_note_hydrate': {
    AppLocale.ru: 'Пейте воду и ешьте регулярно, особенно при грудном вскармливании. О себе легко забыть — держите воду рядом с местом кормления.',
    AppLocale.kk: 'Су ішіп, тұрақты тамақтаныңыз, әсіресе емізіп жүрсеңіз. Өзіңізді ұмыту оңай — емізетін жеріңізге су қойыңыз.',
    AppLocale.en: 'Drink water and eat regularly, especially if you are breastfeeding. It is easy to forget yourself — keep water where you feed.',
  },
  // Bright red bleeding coming back is secondary postpartum haemorrhage until
  // proven otherwise — the same event `pp_warn_bleeding` sends her to the clinic
  // for. "Rest and observe" was the wrong verb; this note now matches the list.
  'pp_note_lochia_fading': {
    AppLocale.ru: 'Выделения светлеют: розовые, затем коричневые, затем кремовые. Внезапный возврат ярко-красной крови — не норма: свяжитесь с поликлиникой, а при обильном кровотечении или крупных сгустках вызывайте скорую.',
    AppLocale.kk: 'Бөліністер ашылады: қызғылт, содан қоңыр, кейін кремді түске енеді. Ашық қызыл қанның кенеттен қайта пайда болуы — қалыпты емес: емханаға хабарласыңыз, ал қан кету мол болса немесе ірі ұйындылар шықса — жедел жәрдем шақырыңыз.',
    AppLocale.en: 'The bleeding lightens — pink, then brown, then creamy. A sudden return to bright red is not normal: contact your clinic, and call emergency services if the bleeding is heavy or you pass large clots.',
  },
  'pp_note_pelvic_floor': {
    AppLocale.ru: 'Мягкие упражнения для тазового дна (Кегеля) можно начинать, когда будете готовы. Они помогают вернуть контроль и поддержку.',
    AppLocale.kk: 'Жамбас түбіне арналған жеңіл жаттығуларды (Кегель) дайын болғанда бастауға болады. Олар бақылау мен тіректі қалпына келтіреді.',
    AppLocale.en: 'Gentle pelvic-floor (Kegel) exercises can begin when you feel ready. They help rebuild control and support.',
  },
  'pp_note_gentle_moving': {
    AppLocale.ru: 'Короткие прогулки полезны, но не поднимайте тяжелее малыша и не спешите с нагрузками — швам и связкам нужно время.',
    AppLocale.kk: 'Қысқа серуендер пайдалы, бірақ нәрестеден ауыр нәрсе көтермеңіз және жаттығуға асықпаңыз — тігіс пен байламдарға уақыт керек.',
    AppLocale.en: 'Short walks are good, but avoid lifting anything heavier than the baby and do not rush back to exercise — stitches and ligaments need time.',
  },
  'pp_note_mood_check': {
    AppLocale.ru: 'Если грусть, тревога или пустота держатся дольше двух недель или мешают заботиться о себе и малыше — это не слабость. Скажите врачу: послеродовая депрессия хорошо лечится.',
    AppLocale.kk: 'Егер қайғы, мазасыздық немесе бос сезім екі аптадан артық сақталса не өзіңізге, нәрестеге қамқор болуға кедергі болса — бұл әлсіздік емес. Дәрігерге айтыңыз: босанғаннан кейінгі депрессия жақсы емделеді.',
    AppLocale.en: 'If sadness, anxiety or numbness lasts more than two weeks or gets in the way of caring for yourself or the baby, it is not weakness. Tell your doctor — postnatal depression responds well to treatment.',
  },
  'pp_note_clearance': {
    AppLocale.ru: 'Возвращение к спорту и близости — после осмотра и с одобрения врача. Единого срока нет; ориентируйтесь на своё тело и совет специалиста.',
    AppLocale.kk: 'Спортқа және жақындыққа оралу — тексеруден кейін және дәрігердің рұқсатымен. Бірыңғай мерзім жоқ; денеңізге және маман кеңесіне сүйеніңіз.',
    AppLocale.en: "Returning to exercise and intimacy comes after the check and with your doctor's go-ahead. There is no one date — follow your body and your clinician's advice.",
  },
  'pp_note_contraception': {
    AppLocale.ru: 'Зачатие возможно ещё до первой менструации. Если сейчас не планируете беременность, обсудите контрацепцию на осмотре.',
    AppLocale.kk: 'Жүктілік алғашқы етеккірге дейін де мүмкін. Қазір жүктілікті жоспарламасаңыз, тексеруде контрацепцияны талқылаңыз.',
    AppLocale.en: 'Pregnancy is possible again before your first period returns. If you are not planning another pregnancy now, discuss contraception at your check.',
  },

  // Warning signs (pp_warn_<id>).
  'pp_warn_bleeding': {
    AppLocale.ru: 'Кровотечение, при котором прокладка полностью промокает за час, или крупные сгустки',
    AppLocale.kk: 'Бір сағатта прокладканы толық суландыратын қан кету немесе ірі ұйындылар',
    AppLocale.en: 'Bleeding that soaks a pad in an hour, or large clots',
  },
  'pp_warn_fever': {
    AppLocale.ru: 'Температура 38 °C или выше, озноб',
    AppLocale.kk: 'Дене қызуы 38 °C немесе жоғары, қалтырау',
    AppLocale.en: 'A temperature of 38°C or higher, or chills',
  },
  'pp_warn_discharge': {
    AppLocale.ru: 'Выделения с неприятным запахом',
    AppLocale.kk: 'Жағымсыз иісі бар бөліністер',
    AppLocale.en: 'Discharge with a bad smell',
  },
  'pp_warn_headache': {
    AppLocale.ru: 'Сильная головная боль или нарушения зрения',
    AppLocale.kk: 'Қатты бас ауыруы немесе көру бұзылысы',
    AppLocale.en: 'A severe headache, or changes in your vision',
  },
  'pp_warn_calf': {
    AppLocale.ru: 'Покраснение, отёк и боль в одной ноге',
    AppLocale.kk: 'Бір аяқтың қызаруы, ісінуі және ауыруы',
    AppLocale.en: 'One leg red, swollen and painful',
  },
  'pp_warn_wound': {
    AppLocale.ru: 'Шов или рана после кесарева — горячие, опухшие или сочатся',
    AppLocale.kk: 'Тігіс немесе кесар тілігінен кейінгі жара — ыстық, ісінген немесе сұйықтық ағып тұр',
    AppLocale.en: 'A tear or caesarean wound that is hot, swollen or leaking',
  },
  'pp_warn_harm': {
    AppLocale.ru: 'Мысли навредить себе или малышу — обратитесь за помощью немедленно',
    AppLocale.kk: 'Өзіңізге немесе нәрестеге зиян келтіру ойлары — дереу көмекке жүгініңіз',
    AppLocale.en: 'Thoughts of harming yourself or the baby — seek help immediately',
  },

  // ---- «Как вы себя чувствуете»: her own mood, on her own recovery screen ----
  //
  // The same DayLog the calendar writes — one tap here is one tap there. The
  // section exists on THIS screen because it is the one a woman six weeks after
  // giving birth actually opens, and because the four-low-weeks card below it
  // can only be earned by entries somebody made.
  'pp_mood_title': {AppLocale.ru: 'Как вы себя чувствуете', AppLocale.kk: 'Өзіңізді қалай сезінесіз', AppLocale.en: 'How are you feeling'},
  'pp_mood_hint': {
    AppLocale.ru: 'Одна отметка в день. Это остаётся в вашем дневнике и помогает заметить, если тяжело держится неделями.',
    AppLocale.kk: 'Күніне бір белгі. Бұл сіздің күнделігіңізде қалады және ауыр күй апталап созылса, оны байқауға көмектеседі.',
    AppLocale.en: 'One tap a day. It stays in your diary and helps notice if a hard patch lasts for weeks.',
  },
  'pp_mood_cta': {AppLocale.ru: 'Отметить самочувствие', AppLocale.kk: 'Көңіл-күйді белгілеу', AppLocale.en: 'Log how you feel'},
  'pp_mood_saved': {AppLocale.ru: 'Отмечено на сегодня', AppLocale.kk: 'Бүгінге белгіленді', AppLocale.en: 'Logged for today'},

  // The amber card. It names the PATTERN in her own entries and offers a
  // self-check — it does not name a condition, and must never start to.
  'pp_low_run_title': {
    AppLocale.ru: 'Четвёртую неделю подряд так себе',
    AppLocale.kk: 'Төртінші апта қатарынан көңіл-күй нашар',
    AppLocale.en: 'A fourth week in a row of feeling low',
  },
  'pp_low_run_title_n': {
    AppLocale.ru: 'Уже {n} недель подряд так себе',
    AppLocale.kk: 'Қатарынан {n} апта бойы көңіл-күй нашар',
    AppLocale.en: '{n} weeks in a row of feeling low',
  },
  'pp_low_run_body': {
    AppLocale.ru: 'Так бывает, и это не слабость. Есть короткий опросник о самочувствии — он ничего не решает за вас, но помогает понять, стоит ли сказать об этом врачу.',
    AppLocale.kk: 'Бұлай болады, әрі бұл әлсіздік емес. Көңіл-күй туралы қысқа сауалнама бар — ол сіздің орныңызға шешім қабылдамайды, бірақ дәрігерге айту керек пе, соны түсінуге көмектеседі.',
    AppLocale.en: 'This happens, and it is not weakness. There is a short self-check — it decides nothing for you, but it helps you see whether this is worth telling a doctor.',
  },
  'pp_screen_offer_title': {AppLocale.ru: 'Проверить самочувствие', AppLocale.kk: 'Көңіл-күйді тексеру', AppLocale.en: 'Check how you are'},
  'pp_screen_offer_body': {
    AppLocale.ru: 'Короткий опросник о том, как прошли последние семь дней. Ответы остаются у вас: сохраняются только дата и число баллов.',
    AppLocale.kk: 'Соңғы жеті күн қалай өткені туралы қысқа сауалнама. Жауаптар сізде қалады: тек күні мен ұпай саны сақталады.',
    AppLocale.en: 'A short set of questions about the last seven days. The answers stay with you — only the date and the score are kept.',
  },
  'pp_screen_last': {
    AppLocale.ru: 'Прошлый раз: {d} · {n} из 30',
    AppLocale.kk: 'Өткен жолы: {d} · 30-дан {n}',
    AppLocale.en: 'Last time: {d} · {n} of 30',
  },

  // ---- The screening questionnaire (EPDS), frame 30 «Опросник · 10 вопросов» ----
  //
  // Wording rules, not preferences: nothing here diagnoses, nothing here is
  // called a test, and the Kazakh rendering is offered as a self-check because
  // the instrument is validated per language and this rendering has not been.
  'epds_title': {AppLocale.ru: 'Как вы себя чувствуете', AppLocale.kk: 'Өзіңізді қалай сезінесіз', AppLocale.en: 'How you have been feeling'},
  'epds_entry': {AppLocale.ru: 'Опросник · 10 вопросов', AppLocale.kk: 'Сауалнама · 10 сұрақ', AppLocale.en: 'Questionnaire · 10 questions'},
  'epds_instrument': {
    AppLocale.ru: 'Эдинбургская шкала (ЭШПД) — опросник самооценки',
    AppLocale.kk: 'Эдинбург шкаласы (ЭПДШ) — өзін-өзі бағалау сауалнамасы',
    AppLocale.en: 'The Edinburgh scale (EPDS) — a self-report questionnaire',
  },
  'epds_disclaimer': {
    AppLocale.ru: 'Это не диагноз и не заключение. Опросник помогает вам самой увидеть, как прошла неделя, и решить, стоит ли сказать об этом врачу. Ответы никуда не отправляются: сохраняются только дата и число баллов.',
    AppLocale.kk: 'Бұл диагноз да, қорытынды да емес. Сауалнама апта қалай өткенін өзіңіз көріп, бұл туралы дәрігерге айту керек пе, соны шешуге көмектеседі. Жауаптар еш жаққа жіберілмейді: тек күні мен ұпай саны сақталады.',
    AppLocale.en: 'This is not a diagnosis or an assessment. It helps you see your own week and decide whether to raise it with a doctor. The answers are not sent anywhere — only the date and the score are kept.',
  },
  // The Kazakh sentence is shown in Kazakh only; the same key carries a plain
  // note in the other languages rather than a blank.
  'epds_not_validated': {
    AppLocale.ru: 'Русский и казахский варианты опросника приводятся как вспомогательные: пороговые значения шкалы получены на других языковых версиях.',
    AppLocale.kk: 'Сауалнаманың қазақша нұсқасы көмекші құрал ретінде беріледі: шкаланың шекті мәндері басқа тілдік нұсқаларда алынған.',
    AppLocale.en: 'The Russian and Kazakh renderings are offered as an aid: the published thresholds come from studies of other language versions.',
  },
  'epds_period': {AppLocale.ru: 'За последние 7 дней', AppLocale.kk: 'Соңғы 7 күнде', AppLocale.en: 'In the past 7 days'},
  'epds_progress': {AppLocale.ru: 'Отвечено {n} из 10', AppLocale.kk: '10 сұрақтың {n} жауап берілді', AppLocale.en: '{n} of 10 answered'},
  'epds_submit': {AppLocale.ru: 'Показать результат', AppLocale.kk: 'Нәтижені көрсету', AppLocale.en: 'Show the result'},
  'epds_incomplete': {
    AppLocale.ru: 'Ответьте на все десять вопросов — иначе счёт будет неполным.',
    AppLocale.kk: 'Он сұрақтың бәріне жауап беріңіз — әйтпесе есеп толық болмайды.',
    AppLocale.en: 'Answer all ten questions — otherwise the score is incomplete.',
  },
  'epds_result_title': {AppLocale.ru: 'Ваш результат', AppLocale.kk: 'Сіздің нәтижеңіз', AppLocale.en: 'Your result'},
  'epds_score': {AppLocale.ru: '{n} из 30', AppLocale.kk: '30-дан {n}', AppLocale.en: '{n} of 30'},
  'epds_band_low': {
    AppLocale.ru: 'На этой неделе ответы в спокойной части шкалы. Если самочувствие изменится, пройдите опросник снова.',
    AppLocale.kk: 'Осы аптада жауаптар шкаланың тыныш бөлігінде. Көңіл-күй өзгерсе, сауалнаманы қайта өтіңіз.',
    AppLocale.en: 'This week your answers sit in the calm part of the scale. If things change, take it again.',
  },
  'epds_band_possible': {
    AppLocale.ru: 'Неделя была непростой. Это стоит проговорить с врачом на ближайшем приёме — и повторить опросник через неделю.',
    AppLocale.kk: 'Апта оңай болмады. Мұны жақындағы қабылдауда дәрігермен талқылаған жөн — және бір аптадан кейін сауалнаманы қайталаңыз.',
    AppLocale.en: 'It has been a hard week. It is worth mentioning at your next appointment, and taking this again in a week.',
  },
  'epds_band_high': {
    AppLocale.ru: 'Ответы набрали 13 баллов и выше — это тот порог, на котором опросник рекомендует поговорить с врачом. Не ждите планового осмотра.',
    AppLocale.kk: 'Жауаптар 13 және одан жоғары ұпай жинады — бұл сауалнама дәрігермен сөйлесуді ұсынатын шек. Жоспарлы тексеруді күтпеңіз.',
    AppLocale.en: 'The answers reached 13 or more — the threshold at which this questionnaire advises talking to a clinician. Do not wait for the scheduled check.',
  },
  // Shown whenever item 10 is answered at all, whatever the total. It is not a
  // softer version of the warning list — it introduces it.
  'epds_harm_flag': {
    AppLocale.ru: 'Вы отметили мысли навредить себе. Пожалуйста, не оставайтесь с этим одна — свяжитесь с врачом или скорой сегодня.',
    AppLocale.kk: 'Сіз өзіңізге зиян келтіру ойларын белгіледіңіз. Өтінеміз, мұнымен жалғыз қалмаңыз — бүгін дәрігерге немесе жедел жәрдемге хабарласыңыз.',
    AppLocale.en: 'You marked thoughts of harming yourself. Please do not stay alone with this — contact a clinician or emergency services today.',
  },
  'epds_saved': {
    AppLocale.ru: 'Сохранены только дата и баллы',
    AppLocale.kk: 'Тек күні мен ұпай сақталды',
    AppLocale.en: 'Only the date and the score were saved',
  },
  'epds_retake': {AppLocale.ru: 'Пройти заново', AppLocale.kk: 'Қайта өту', AppLocale.en: 'Take it again'},
  'epds_close': {AppLocale.ru: 'Закрыть', AppLocale.kk: 'Жабу', AppLocale.en: 'Close'},

  // The ten items (epds_q<i>) and their four options (epds_q<i>_a<0..3>), in
  // PRINTED order. Seven items are printed worst-first and score 3→0 — see
  // domain/epds.dart. Never reorder an option list without changing the scoring
  // there: the total stays plausible and becomes wrong.
  'epds_q1': {
    AppLocale.ru: 'Я могла смеяться и видеть смешную сторону вещей',
    AppLocale.kk: 'Мен күле алдым және нәрсенің күлкілі жағын көре алдым',
    AppLocale.en: 'I have been able to laugh and see the funny side of things',
  },
  'epds_q1_a0': {AppLocale.ru: 'Так же, как всегда', AppLocale.kk: 'Әрдайымғыдай', AppLocale.en: 'As much as I always could'},
  'epds_q1_a1': {AppLocale.ru: 'Пожалуй, чуть меньше', AppLocale.kk: 'Сәл азырақ', AppLocale.en: 'Not quite so much now'},
  'epds_q1_a2': {AppLocale.ru: 'Определённо меньше', AppLocale.kk: 'Әлдеқайда азырақ', AppLocale.en: 'Definitely not so much now'},
  'epds_q1_a3': {AppLocale.ru: 'Совсем нет', AppLocale.kk: 'Мүлдем жоқ', AppLocale.en: 'Not at all'},

  'epds_q2': {
    AppLocale.ru: 'Я ждала предстоящего с удовольствием',
    AppLocale.kk: 'Мен алдағыны қуанышпен күттім',
    AppLocale.en: 'I have looked forward with enjoyment to things',
  },
  'epds_q2_a0': {AppLocale.ru: 'Так же, как раньше', AppLocale.kk: 'Бұрынғыдай', AppLocale.en: 'As much as I ever did'},
  'epds_q2_a1': {AppLocale.ru: 'Немного меньше, чем раньше', AppLocale.kk: 'Бұрынғыдан сәл азырақ', AppLocale.en: 'Rather less than I used to'},
  'epds_q2_a2': {AppLocale.ru: 'Определённо меньше, чем раньше', AppLocale.kk: 'Бұрынғыдан әлдеқайда азырақ', AppLocale.en: 'Definitely less than I used to'},
  'epds_q2_a3': {AppLocale.ru: 'Почти совсем нет', AppLocale.kk: 'Мүлдем дерлік жоқ', AppLocale.en: 'Hardly at all'},

  'epds_q3': {
    AppLocale.ru: 'Я без причины винила себя, когда что-то шло не так',
    AppLocale.kk: 'Бірдеңе сәтсіз болғанда, себепсіз өзімді кінәладым',
    AppLocale.en: 'I have blamed myself unnecessarily when things went wrong',
  },
  'epds_q3_a0': {AppLocale.ru: 'Да, почти всё время', AppLocale.kk: 'Иә, көбіне', AppLocale.en: 'Yes, most of the time'},
  'epds_q3_a1': {AppLocale.ru: 'Да, иногда', AppLocale.kk: 'Иә, кейде', AppLocale.en: 'Yes, some of the time'},
  'epds_q3_a2': {AppLocale.ru: 'Не очень часто', AppLocale.kk: 'Онша жиі емес', AppLocale.en: 'Not very often'},
  'epds_q3_a3': {AppLocale.ru: 'Нет, никогда', AppLocale.kk: 'Жоқ, ешқашан', AppLocale.en: 'No, never'},

  'epds_q4': {
    AppLocale.ru: 'Я тревожилась или беспокоилась без явной причины',
    AppLocale.kk: 'Мен айқын себепсіз мазасызданып, уайымдадым',
    AppLocale.en: 'I have been anxious or worried for no good reason',
  },
  'epds_q4_a0': {AppLocale.ru: 'Нет, совсем нет', AppLocale.kk: 'Жоқ, мүлдем', AppLocale.en: 'No, not at all'},
  'epds_q4_a1': {AppLocale.ru: 'Почти никогда', AppLocale.kk: 'Дерлік ешқашан', AppLocale.en: 'Hardly ever'},
  'epds_q4_a2': {AppLocale.ru: 'Да, иногда', AppLocale.kk: 'Иә, кейде', AppLocale.en: 'Yes, sometimes'},
  'epds_q4_a3': {AppLocale.ru: 'Да, очень часто', AppLocale.kk: 'Иә, өте жиі', AppLocale.en: 'Yes, very often'},

  'epds_q5': {
    AppLocale.ru: 'Мне бывало страшно или я паниковала без серьёзной причины',
    AppLocale.kk: 'Маған елеулі себепсіз қорқынышты болды немесе дүрбелеңге түстім',
    AppLocale.en: 'I have felt scared or panicky for no very good reason',
  },
  'epds_q5_a0': {AppLocale.ru: 'Да, довольно часто', AppLocale.kk: 'Иә, едәуір жиі', AppLocale.en: 'Yes, quite a lot'},
  'epds_q5_a1': {AppLocale.ru: 'Да, иногда', AppLocale.kk: 'Иә, кейде', AppLocale.en: 'Yes, sometimes'},
  'epds_q5_a2': {AppLocale.ru: 'Нет, не очень', AppLocale.kk: 'Жоқ, онша емес', AppLocale.en: 'No, not much'},
  'epds_q5_a3': {AppLocale.ru: 'Нет, совсем нет', AppLocale.kk: 'Жоқ, мүлдем', AppLocale.en: 'No, not at all'},

  'epds_q6': {
    AppLocale.ru: 'Дела наваливались и мне было трудно справляться',
    AppLocale.kk: 'Істер үйіліп қалып, оларды атқару қиын болды',
    AppLocale.en: 'Things have been getting on top of me',
  },
  'epds_q6_a0': {
    AppLocale.ru: 'Да, почти всё время я совсем не справлялась',
    AppLocale.kk: 'Иә, көбіне мүлдем үлгере алмадым',
    AppLocale.en: "Yes, most of the time I haven't been able to cope at all",
  },
  'epds_q6_a1': {
    AppLocale.ru: 'Да, иногда справлялась хуже обычного',
    AppLocale.kk: 'Иә, кейде әдеттегіден нашар үлгердім',
    AppLocale.en: "Yes, sometimes I haven't been coping as well as usual",
  },
  'epds_q6_a2': {
    AppLocale.ru: 'Нет, почти всё время справлялась неплохо',
    AppLocale.kk: 'Жоқ, көбіне жақсы үлгердім',
    AppLocale.en: 'No, most of the time I have coped quite well',
  },
  'epds_q6_a3': {
    AppLocale.ru: 'Нет, справлялась как всегда',
    AppLocale.kk: 'Жоқ, әрдайымғыдай үлгердім',
    AppLocale.en: 'No, I have been coping as well as ever',
  },

  'epds_q7': {
    AppLocale.ru: 'Мне было так плохо, что я плохо спала',
    AppLocale.kk: 'Көңіл-күйім соншалық ауыр болып, ұйқым бұзылды',
    AppLocale.en: 'I have been so unhappy that I have had difficulty sleeping',
  },
  'epds_q7_a0': {AppLocale.ru: 'Да, почти всё время', AppLocale.kk: 'Иә, көбіне', AppLocale.en: 'Yes, most of the time'},
  'epds_q7_a1': {AppLocale.ru: 'Да, иногда', AppLocale.kk: 'Иә, кейде', AppLocale.en: 'Yes, sometimes'},
  'epds_q7_a2': {AppLocale.ru: 'Не очень часто', AppLocale.kk: 'Онша жиі емес', AppLocale.en: 'Not very often'},
  'epds_q7_a3': {AppLocale.ru: 'Нет, совсем нет', AppLocale.kk: 'Жоқ, мүлдем', AppLocale.en: 'No, not at all'},

  'epds_q8': {
    AppLocale.ru: 'Мне было грустно или тоскливо',
    AppLocale.kk: 'Мен мұңайдым немесе жабырқау болдым',
    AppLocale.en: 'I have felt sad or miserable',
  },
  'epds_q8_a0': {AppLocale.ru: 'Да, почти всё время', AppLocale.kk: 'Иә, көбіне', AppLocale.en: 'Yes, most of the time'},
  'epds_q8_a1': {AppLocale.ru: 'Да, довольно часто', AppLocale.kk: 'Иә, едәуір жиі', AppLocale.en: 'Yes, quite often'},
  'epds_q8_a2': {AppLocale.ru: 'Не очень часто', AppLocale.kk: 'Онша жиі емес', AppLocale.en: 'Not very often'},
  'epds_q8_a3': {AppLocale.ru: 'Нет, совсем нет', AppLocale.kk: 'Жоқ, мүлдем', AppLocale.en: 'No, not at all'},

  'epds_q9': {
    AppLocale.ru: 'Мне было так плохо, что я плакала',
    AppLocale.kk: 'Көңіл-күйім соншалық ауыр болып, жыладым',
    AppLocale.en: 'I have been so unhappy that I have been crying',
  },
  'epds_q9_a0': {AppLocale.ru: 'Да, почти всё время', AppLocale.kk: 'Иә, көбіне', AppLocale.en: 'Yes, most of the time'},
  'epds_q9_a1': {AppLocale.ru: 'Да, довольно часто', AppLocale.kk: 'Иә, едәуір жиі', AppLocale.en: 'Yes, quite often'},
  'epds_q9_a2': {AppLocale.ru: 'Только изредка', AppLocale.kk: 'Тек сирек', AppLocale.en: 'Only occasionally'},
  'epds_q9_a3': {AppLocale.ru: 'Нет, никогда', AppLocale.kk: 'Жоқ, ешқашан', AppLocale.en: 'No, never'},

  // Item 10. Any answer above «никогда» sends her outward on its own, whatever
  // the total — see domain/epds.dart, flaggedSelfHarm.
  'epds_q10': {
    AppLocale.ru: 'У меня возникала мысль навредить себе',
    AppLocale.kk: 'Менде өзіме зиян келтіру ойы туындады',
    AppLocale.en: 'The thought of harming myself has occurred to me',
  },
  'epds_q10_a0': {AppLocale.ru: 'Да, довольно часто', AppLocale.kk: 'Иә, едәуір жиі', AppLocale.en: 'Yes, quite often'},
  'epds_q10_a1': {AppLocale.ru: 'Иногда', AppLocale.kk: 'Кейде', AppLocale.en: 'Sometimes'},
  'epds_q10_a2': {AppLocale.ru: 'Почти никогда', AppLocale.kk: 'Дерлік ешқашан', AppLocale.en: 'Hardly ever'},
  'epds_q10_a3': {AppLocale.ru: 'Никогда', AppLocale.kk: 'Ешқашан', AppLocale.en: 'Never'},

  // ---- Pregnancy guide (what she might feel this stage, and when to call) ----
  'preg_expect_title': {AppLocale.ru: 'Как вы себя чувствуете', AppLocale.kk: 'Өзіңізді қалай сезінесіз', AppLocale.en: 'How you may feel'},
  'preg_warn_title': {AppLocale.ru: 'Когда обращаться к врачу', AppLocale.kk: 'Қашан дәрігерге қаралу керек', AppLocale.en: 'When to call your doctor'},
  'preg_warn_intro': {
    AppLocale.ru: 'Свяжитесь с консультацией или скорой, если появится что-то из этого:',
    AppLocale.kk: 'Мыналардың бірі пайда болса, консультацияға немесе жедел жәрдемге хабарласыңыз:',
    AppLocale.en: 'Contact your clinic or emergency services if any of these appear:',
  },

  'preg_area_body': {AppLocale.ru: 'Тело', AppLocale.kk: 'Дене', AppLocale.en: 'Body'},
  'preg_area_comfort': {AppLocale.ru: 'Комфорт', AppLocale.kk: 'Жайлылық', AppLocale.en: 'Comfort'},
  'preg_area_movement': {AppLocale.ru: 'Шевеления', AppLocale.kk: 'Қимылдар', AppLocale.en: 'Movements'},
  'preg_area_mind': {AppLocale.ru: 'Настроение', AppLocale.kk: 'Көңіл-күй', AppLocale.en: 'Mind'},

  // Stage notes (preg_note_<id>).
  'preg_note_nausea': {
    AppLocale.ru: 'Тошнота и утренняя дурнота часто бывают в первом триместре и обычно стихают к 12–14 неделе.',
    AppLocale.kk: 'Жүрек айну мен таңғы құсу бірінші триместрде жиі болады және әдетте 12–14 аптаға қарай басылады.',
    AppLocale.en: 'Nausea and morning sickness are common in the first trimester and usually ease by weeks 12–14.',
  },
  'preg_note_tired': {
    AppLocale.ru: 'Сильная усталость в начале — это нормально: тело строит плаценту. Отдыхайте без чувства вины.',
    AppLocale.kk: 'Басында қатты шаршау — қалыпты жағдай: дене плацента құрып жатыр. Кінәсіз демалыңыз.',
    AppLocale.en: 'Deep tiredness early on is normal — your body is building the placenta. Rest without guilt.',
  },
  'preg_note_eating': {
    AppLocale.ru: 'Ешьте понемногу и часто, пейте воду. Продолжайте принимать фолиевую кислоту, как советует врач.',
    AppLocale.kk: 'Аз-аздан жиі жеңіз, су ішіңіз. Дәрігер кеңесі бойынша фолий қышқылын қабылдай беріңіз.',
    AppLocale.en: 'Eat small amounts often, and drink water. Keep taking folic acid as your doctor advises.',
  },
  'preg_note_emotions': {
    AppLocale.ru: 'Перепады настроения из-за гормонов — обычное дело. Если тревога или подавленность не отпускают, скажите врачу.',
    AppLocale.kk: 'Гормондардан көңіл-күйдің құбылуы — қалыпты жағдай. Егер мазасыздық не көңілсіздік кетпесе, дәрігерге айтыңыз.',
    AppLocale.en: 'Mood swings from the hormones are ordinary. If anxiety or low mood does not lift, tell your doctor.',
  },
  'preg_note_energy': {
    AppLocale.ru: 'Во втором триместре многие чувствуют себя лучше: тошнота уходит, возвращается энергия.',
    AppLocale.kk: 'Екінші триместрде көбі өзін жақсы сезінеді: жүрек айну басылып, күш қайтады.',
    AppLocale.en: 'In the second trimester many women feel better — the nausea fades and energy returns.',
  },
  'preg_note_first_movements': {
    AppLocale.ru: 'Первые шевеления часто ощущаются примерно на 18–22 неделе, раньше — если беременность не первая. Сначала это лёгкое трепетание.',
    AppLocale.kk: 'Алғашқы қимылдар көбіне 18–22 апта шамасында сезіледі, бірінші жүктілік болмаса — ертерек. Басында ол жеңіл дірілдей сезіледі.',
    AppLocale.en: 'First movements are often felt around 18–22 weeks — earlier if this is not your first. At first it feels like fluttering.',
  },
  'preg_note_ligament': {
    AppLocale.ru: 'Резкие покалывания по бокам живота при движении — обычно это растяжение связок, а не тревожный знак.',
    AppLocale.kk: 'Қозғалғанда іштің бүйірінде пайда болатын өткір шаншу — әдетте байламдардың керілуі, қауіп белгісі емес.',
    AppLocale.en: 'Sharp twinges at the sides of your belly when you move are usually stretching ligaments, not a warning sign.',
  },
  'preg_note_bump': {
    AppLocale.ru: 'Живот становится заметнее. Коже и спине может понадобиться забота: увлажнение, удобная обувь, поддержка поясницы.',
    AppLocale.kk: 'Іш байқала бастайды. Тері мен арқаға қамқорлық керек болуы мүмкін: ылғалдандыру, ыңғайлы аяқ киім, бел тірегі.',
    AppLocale.en: 'The bump becomes visible. Your skin and back may need care — moisturiser, comfortable shoes, support for the lower back.',
  },
  'preg_note_braxton': {
    AppLocale.ru: 'Нерегулярные напряжения живота (схватки Брэкстона-Хикса) — это тренировка. Настоящие роды регулярны и усиливаются.',
    AppLocale.kk: 'Іштің біркелкі емес қатаюы (Брэкстон-Хикс жиырылуы) — жаттығу. Нағыз босану біркелкі әрі күшейе береді.',
    AppLocale.en: 'Irregular tightenings (Braxton Hicks) are practice contractions. Real labour is regular and builds in strength.',
  },
  'preg_note_swelling': {
    AppLocale.ru: 'Небольшой отёк стоп и лодыжек к вечеру бывает часто. Поднимайте ноги и отдыхайте. Внезапный сильный отёк — повод обратиться к врачу.',
    AppLocale.kk: 'Кешке қарай аяқ пен тобықтың сәл ісінуі жиі кездеседі. Аяғыңызды көтеріп демалыңыз. Кенеттен қатты ісіну — дәрігерге қаралуға себеп.',
    AppLocale.en: 'Mild swelling of the feet and ankles by evening is common. Put your feet up and rest. Sudden severe swelling is a reason to call your doctor.',
  },
  'preg_note_movement_pattern': {
    AppLocale.ru: 'Со временем вы узнаёте ритм малыша. Если движений заметно меньше обычного — сразу сообщите в консультацию, в любое время суток.',
    AppLocale.kk: 'Уақыт өте нәрестенің ырғағын білесіз. Қимыл әдеттегіден айтарлықтай аз болса — тәуліктің кез келген уақытында дереу консультацияға хабарлаңыз.',
    AppLocale.en: "Over time you learn your baby's pattern. If movements are noticeably fewer than usual, tell your clinic straight away, at any hour.",
  },
  'preg_note_sleep_side': {
    AppLocale.ru: 'В третьем триместре спите на боку — так лучше кровоток к малышу. Подушка между колен помогает устроиться удобнее.',
    AppLocale.kk: 'Үшінші триместрде бүйіріңізбен ұйықтаңыз — бұл нәрестеге қан ағымы үшін жақсы. Тізе арасына қойылған жастық ыңғайлы орналасуға көмектеседі.',
    AppLocale.en: 'In the third trimester, sleep on your side — it is better for blood flow to the baby. A pillow between the knees helps you settle.',
  },
  'preg_note_hospital_bag': {
    AppLocale.ru: 'Ближе к сроку соберите сумку в роддом и запишите номер своей консультации на видном месте.',
    AppLocale.kk: 'Мерзім жақындағанда перзентханаға сөмке жинап, консультацияңыздың нөмірін көрнекті жерге жазып қойыңыз.',
    AppLocale.en: "As the date nears, pack your hospital bag and keep your clinic's number somewhere easy to find.",
  },

  // Pregnancy warning signs (preg_warn_<id>).
  'preg_warn_bleeding': {
    AppLocale.ru: 'Кровотечение из влагалища',
    AppLocale.kk: 'Қынаптан қан кету',
    AppLocale.en: 'Bleeding from the vagina',
  },
  'preg_warn_fluid': {
    AppLocale.ru: 'Подтекание или излитие вод до начала схваток',
    AppLocale.kk: 'Жиырылу басталмай тұрып судың ағуы немесе кетуі',
    AppLocale.en: 'A trickle or gush of waters before contractions begin',
  },
  'preg_warn_headache': {
    AppLocale.ru: 'Сильная головная боль, нарушения зрения или внезапный отёк лица и рук',
    AppLocale.kk: 'Қатты бас ауыруы, көру бұзылысы немесе беттің, қолдың кенеттен ісінуі',
    AppLocale.en: 'A severe headache, vision changes, or sudden swelling of the face and hands',
  },
  'preg_warn_pain': {
    AppLocale.ru: 'Сильная или постоянная боль в животе',
    AppLocale.kk: 'Іштегі қатты немесе тұрақты ауырсыну',
    AppLocale.en: 'Severe or constant pain in the abdomen',
  },
  'preg_warn_movement': {
    AppLocale.ru: 'Малыш шевелится заметно меньше обычного',
    AppLocale.kk: 'Нәресте әдеттегіден айтарлықтай аз қимылдайды',
    AppLocale.en: 'The baby is moving noticeably less than usual',
  },
  'preg_warn_fever': {
    AppLocale.ru: 'Высокая температура или жжение при мочеиспускании',
    AppLocale.kk: 'Жоғары температура немесе зәр шығарғанда ашып ауыру',
    AppLocale.en: 'A high fever, or burning when passing urine',
  },

  // ---- Antenatal plan: the state 8-visit schedule (an_*) ----
  // From the Kazakhstan MOH clinical protocol "Антенатальный уход" (2025).
  'an_title': {AppLocale.ru: 'План наблюдения', AppLocale.kk: 'Бақылау жоспары', AppLocale.en: 'Your antenatal plan'},
  'an_intro': {
    AppLocale.ru: 'Стандартный план Минздрава: не менее 8 визитов. Вот что входит в каждый — чтобы вы знали, что вас ждёт.',
    AppLocale.kk: 'Денсаулық сақтау министрлігінің стандартты жоспары: кемінде 8 бару. Әр барудың мазмұны осында — не күтетініңізді білуіңіз үшін.',
    AppLocale.en: 'The Ministry of Health’s standard plan: at least 8 visits. Here is what each one is for, so you know what to expect.',
  },
  'an_disclaimer': {
    AppLocale.ru: 'Это стандартный план. При особенностях беременности врач меняет частоту и состав визитов — следуйте назначениям вашего врача.',
    AppLocale.kk: 'Бұл — стандартты жоспар. Жүктілік ерекшеліктерінде дәрігер бару жиілігі мен мазмұнын өзгертеді — дәрігеріңіздің тағайындауын ұстаныңыз.',
    AppLocale.en: 'This is the standard plan. Your doctor changes the timing and content for your pregnancy — always follow your own doctor’s advice.',
  },
  'an_source': {
    AppLocale.ru: 'По клиническому протоколу МЗ РК «Антенатальный уход» (2025).',
    AppLocale.kk: 'ҚР ДСМ «Антенаталдық күтім» клиникалық хаттамасы бойынша (2025).',
    AppLocale.en: 'Based on the Kazakhstan MOH clinical protocol “Antenatal care” (2025).',
  },
  'an_due_now': {AppLocale.ru: 'Пора на этот визит', AppLocale.kk: 'Осы баруға уақыт', AppLocale.en: 'Due now'},
  'an_upcoming': {AppLocale.ru: 'Следующий визит', AppLocale.kk: 'Келесі бару', AppLocale.en: 'Next visit'},
  'an_of_eight': {AppLocale.ru: 'Визит {n} из 8', AppLocale.kk: '8 барудың {n}-і', AppLocale.en: 'Visit {n} of 8'},
  'an_visit_label': {AppLocale.ru: 'Визит {n}', AppLocale.kk: '{n}-бару', AppLocale.en: 'Visit {n}'},
  'an_weeks_range': {AppLocale.ru: '{from}–{to} недель', AppLocale.kk: '{from}–{to} апта', AppLocale.en: '{from}–{to} weeks'},
  'an_week_single': {AppLocale.ru: '{w} недель', AppLocale.kk: '{w} апта', AppLocale.en: 'Week {w}'},
  'an_full_plan': {AppLocale.ru: 'Полный план визитов', AppLocale.kk: 'Барулардың толық жоспары', AppLocale.en: 'The full visit plan'},
  'an_windows_title': {AppLocale.ru: 'Сроки, которые важно не пропустить', AppLocale.kk: 'Өткізіп алмау маңызды мерзімдер', AppLocale.en: 'Time-sensitive checks'},
  'an_windows_intro': {
    AppLocale.ru: 'Эти обследования проводятся строго в определённые недели. Позже окно закрывается.',
    AppLocale.kk: 'Бұл зерттеулер тек белгілі бір аптада жасалады. Кейін терезе жабылады.',
    AppLocale.en: 'These are done only within set weeks. Miss the window and it closes.',
  },
  'an_win_open': {AppLocale.ru: 'Открыто сейчас', AppLocale.kk: 'Қазір ашық', AppLocale.en: 'Open now'},
  'an_win_range': {AppLocale.ru: '{from}–{to} нед.', AppLocale.kk: '{from}–{to} апта', AppLocale.en: 'wk {from}–{to}'},
  'an_risk_tag': {AppLocale.ru: 'если применимо к вам', AppLocale.kk: 'сізге қатысты болса', AppLocale.en: 'if it applies to you'},
  'an_risk_note': {
    AppLocale.ru: 'Пункты с этой пометкой назначаются по показаниям — не каждой женщине.',
    AppLocale.kk: 'Осы белгісі бар тармақтар көрсеткіш бойынша тағайындалады — әр әйелге емес.',
    AppLocale.en: 'Items with this tag are only for those who need them — not everyone.',
  },
  'an_book_cta': {AppLocale.ru: 'Добавить в мои приёмы', AppLocale.kk: 'Қабылдауларыма қосу', AppLocale.en: 'Add to my appointments'},
  'an_book_title': {AppLocale.ru: 'Антенатальный визит {n}', AppLocale.kk: '{n}-антенаталды бару', AppLocale.en: 'Antenatal visit {n}'},
  'an_booked': {AppLocale.ru: 'Визит добавлен в ваши приёмы — измените дату при необходимости', AppLocale.kk: 'Бару қабылдауларыңызға қосылды — қажет болса күнін өзгертіңіз', AppLocale.en: 'Visit added to your appointments — change the date if needed'},
  'an_card_title': {AppLocale.ru: 'План наблюдения', AppLocale.kk: 'Бақылау жоспары', AppLocale.en: 'Antenatal plan'},
  'an_card_due': {AppLocale.ru: 'Визит {n} — пора записаться', AppLocale.kk: '{n}-бару — жазылу уақыты', AppLocale.en: 'Visit {n} is due now'},
  'an_card_next': {AppLocale.ru: 'Впереди визит {n}', AppLocale.kk: 'Алда {n}-бару', AppLocale.en: 'Visit {n} is coming up'},
  'an_term_title': {AppLocale.ru: 'Плановые визиты пройдены', AppLocale.kk: 'Жоспарлы барулар аяқталды', AppLocale.en: 'The planned visits are complete'},
  'an_term_note': {
    AppLocale.ru: 'Все 8 визитов позади. Если роды не начались к 41 неделе, обсудите с врачом дальнейшую тактику.',
    AppLocale.kk: '8 бару да артта қалды. Босану 41 аптада басталмаса, дәрігермен әрі қарайғы әрекетті талқылаңыз.',
    AppLocale.en: 'All eight visits are behind you. If labour hasn’t begun by 41 weeks, talk with your doctor about next steps.',
  },

  // Visit categories (an_cat_<category>).
  'an_cat_counsel': {AppLocale.ru: 'Консультирование', AppLocale.kk: 'Кеңес беру', AppLocale.en: 'Counselling'},
  'an_cat_exam': {AppLocale.ru: 'Обследование', AppLocale.kk: 'Тексеру', AppLocale.en: 'Examination'},
  'an_cat_lab': {AppLocale.ru: 'Анализы', AppLocale.kk: 'Талдаулар', AppLocale.en: 'Lab tests'},
  'an_cat_imaging': {AppLocale.ru: 'Инструментальные', AppLocale.kk: 'Аспаптық зерттеу', AppLocale.en: 'Imaging'},
  'an_cat_prophylaxis': {AppLocale.ru: 'Профилактика', AppLocale.kk: 'Алдын алу', AppLocale.en: 'Prevention'},

  // Visit items (an_item_<id>).
  'an_item_history_risk': {AppLocale.ru: 'Сбор анамнеза и оценка факторов риска', AppLocale.kk: 'Анамнез жинау және қауіп факторларын бағалау', AppLocale.en: 'History taken and risk factors assessed'},
  'an_item_danger_signs': {AppLocale.ru: 'Обучение тревожным признакам и действиям при них', AppLocale.kk: 'Қауіпті белгілерді тану және не істеу керектігі', AppLocale.en: 'Learning the danger signs and what to do'},
  'an_item_schedule_plan': {AppLocale.ru: 'Индивидуальный график наблюдения', AppLocale.kk: 'Жеке бақылау кестесі', AppLocale.en: 'Your personal visit schedule'},
  'an_item_bmi': {AppLocale.ru: 'Рост, вес и расчёт ИМТ', AppLocale.kk: 'Бой, салмақ және дене салмағы индексі', AppLocale.en: 'Height, weight and BMI'},
  'an_item_bp_pulse': {AppLocale.ru: 'Измерение давления и пульса', AppLocale.kk: 'Қан қысымы мен тамыр соғуын өлшеу', AppLocale.en: 'Blood pressure and pulse'},
  'an_item_legs_varicose': {AppLocale.ru: 'Осмотр ног на варикозные вены', AppLocale.kk: 'Аяқты варикозға тексеру', AppLocale.en: 'Legs checked for varicose veins'},
  'an_item_breast_exam': {AppLocale.ru: 'Осмотр молочных желёз', AppLocale.kk: 'Сүт бездерін тексеру', AppLocale.en: 'Breast examination'},
  'an_item_gyn_exam': {AppLocale.ru: 'Гинекологический осмотр', AppLocale.kk: 'Гинекологиялық тексеру', AppLocale.en: 'Gynaecological examination'},
  'an_item_us_dating': {AppLocale.ru: 'УЗИ 11–13 нед.: срок, двойня, скрининг', AppLocale.kk: 'УДЗ 11–13 апта: мерзім, егіз, скрининг', AppLocale.en: 'Ultrasound 11–13 wk: dating and screening'},
  'an_item_ecg': {AppLocale.ru: 'ЭКГ по показаниям', AppLocale.kk: 'Көрсеткіш бойынша ЭКГ', AppLocale.en: 'ECG if indicated'},
  'an_item_cbc': {AppLocale.ru: 'Общий анализ крови', AppLocale.kk: 'Қанның жалпы талдауы', AppLocale.en: 'Full blood count'},
  'an_item_blood_glucose': {AppLocale.ru: 'Глюкоза венозной крови', AppLocale.kk: 'Веналық қандағы глюкоза', AppLocale.en: 'Blood glucose'},
  'an_item_urinalysis': {AppLocale.ru: 'Общий анализ мочи', AppLocale.kk: 'Зәрдің жалпы талдауы', AppLocale.en: 'Urinalysis'},
  'an_item_blood_type_rh': {AppLocale.ru: 'Группа крови и резус-фактор', AppLocale.kk: 'Қан тобы және резус-фактор', AppLocale.en: 'Blood group and rhesus factor'},
  'an_item_urine_culture': {AppLocale.ru: 'Посев мочи (до 16 нед.)', AppLocale.kk: 'Зәр егісі (16 аптаға дейін)', AppLocale.en: 'Urine culture (before 16 wk)'},
  'an_item_cervical_cytology': {AppLocale.ru: 'Мазок на онкоцитологию', AppLocale.kk: 'Онкоцитологияға жағынды', AppLocale.en: 'Cervical cytology smear'},
  'an_item_hiv': {AppLocale.ru: 'Анализ на ВИЧ', AppLocale.kk: 'АИТВ-ға талдау', AppLocale.en: 'HIV test'},
  'an_item_syphilis': {AppLocale.ru: 'Анализ на сифилис', AppLocale.kk: 'Мерезге талдау', AppLocale.en: 'Syphilis test'},
  'an_item_hep_b': {AppLocale.ru: 'Анализ на гепатит B', AppLocale.kk: 'В гепатитіне талдау', AppLocale.en: 'Hepatitis B test'},
  'an_item_serum_markers': {AppLocale.ru: 'Сывороточные маркёры (11–13 нед.)', AppLocale.kk: 'Сарысулық маркерлер (11–13 апта)', AppLocale.en: 'Serum markers (11–13 wk)'},
  'an_item_therapist': {AppLocale.ru: 'Осмотр терапевта / ВОП', AppLocale.kk: 'Терапевт / ЖТД қарауы', AppLocale.en: 'Therapist / GP review'},
  'an_item_folic_acid': {AppLocale.ru: 'Фолиевая кислота 400 мкг в день', AppLocale.kk: 'Күніне 400 мкг фолий қышқылы', AppLocale.en: 'Folic acid 400 mcg daily'},
  'an_item_aspirin': {AppLocale.ru: 'Аспирин с 12 до 36 нед. при риске преэклампсии', AppLocale.kk: 'Преэклампсия қаупінде 12–36 аптада аспирин', AppLocale.en: 'Aspirin 12–36 wk if at risk of pre-eclampsia'},
  'an_item_calcium': {AppLocale.ru: 'Кальций с 12 нед. при низком его потреблении', AppLocale.kk: 'Кальций аз болса, 12 аптадан кальций', AppLocale.en: 'Calcium from 12 wk if intake is low'},
  'an_item_screening_review': {AppLocale.ru: 'Обзор результатов всех скринингов', AppLocale.kk: 'Барлық скрининг нәтижелерін қарау', AppLocale.en: 'Review of all screening results'},
  'an_item_birth_school': {AppLocale.ru: 'Школа подготовки к родам', AppLocale.kk: 'Босануға дайындық мектебі', AppLocale.en: 'Antenatal (birth-prep) classes'},
  'an_item_fundal_height': {AppLocale.ru: 'Высота дна матки (гравидограмма)', AppLocale.kk: 'Жатыр түбінің биіктігі (гравидограмма)', AppLocale.en: 'Fundal height on the gravidogram'},
  'an_item_urine_protein': {AppLocale.ru: 'Анализ мочи на белок', AppLocale.kk: 'Зәрдегі ақуызға талдау', AppLocale.en: 'Urine test for protein'},
  'an_item_us_anomaly': {AppLocale.ru: 'УЗИ 19–21 нед.: скрининг аномалий', AppLocale.kk: 'УДЗ 19–21 апта: ақау скринингі', AppLocale.en: 'Ultrasound 19–21 wk: anomaly scan'},
  'an_item_risk_review': {AppLocale.ru: 'Повторная оценка факторов риска', AppLocale.kk: 'Қауіп факторларын қайта бағалау', AppLocale.en: 'Risk factors reviewed again'},
  'an_item_fetal_heartbeat': {AppLocale.ru: 'Выслушивание сердцебиения плода', AppLocale.kk: 'Ұрықтың жүрек соғуын тыңдау', AppLocale.en: 'Listening to the baby’s heartbeat'},
  'an_item_ogtt': {AppLocale.ru: 'Тест на толерантность к глюкозе (24–28 нед.)', AppLocale.kk: 'Глюкозаға төзімділік тесті (24–28 апта)', AppLocale.en: 'Glucose-tolerance test (24–28 wk)'},
  'an_item_anti_d': {AppLocale.ru: 'Анти-D иммуноглобулин в 28–30 нед. при резус-отрицательной крови', AppLocale.kk: 'Резус теріс қанда 28–30 аптада анти-D иммуноглобулин', AppLocale.en: 'Anti-D at 28–30 wk if rhesus-negative'},
  'an_item_weight_recheck': {AppLocale.ru: 'Контроль веса при низком ИМТ', AppLocale.kk: 'Төмен ДСИ кезінде салмақты бақылау', AppLocale.en: 'Weight rechecked if BMI is low'},
  'an_item_us_growth': {AppLocale.ru: 'УЗИ 30–32 нед.: рост плода', AppLocale.kk: 'УДЗ 30–32 апта: ұрықтың өсуі', AppLocale.en: 'Ultrasound 30–32 wk: growth scan'},
  'an_item_maternity_leave': {AppLocale.ru: 'Оформление дородового отпуска (30 нед.)', AppLocale.kk: 'Босануға дейінгі демалысты рәсімдеу (30 апта)', AppLocale.en: 'Maternity leave issued (30 wk)'},
  'an_item_fetal_position': {AppLocale.ru: 'Определение положения и предлежания плода', AppLocale.kk: 'Ұрықтың жағдайы мен келуін анықтау', AppLocale.en: 'Baby’s position and presentation checked'},
  'an_item_breastfeeding_contraception': {AppLocale.ru: 'Беседа о грудном вскармливании и контрацепции', AppLocale.kk: 'Емізу мен контрацепция туралы әңгіме', AppLocale.en: 'Talk on breastfeeding and contraception'},
  'an_item_postterm_talk': {AppLocale.ru: 'Беседа о переношенной беременности', AppLocale.kk: 'Мерзімінен асқан жүктілік туралы әңгіме', AppLocale.en: 'Talk about going past your due date'},
  'an_item_hospital_41w': {AppLocale.ru: 'Обсуждение госпитализации на 41 неделе', AppLocale.kk: '41 аптада жатқызу туралы талқылау', AppLocale.en: 'Discussing admission at 41 weeks'},

  // ---- Fetal development, week by week (fet_<id>) ----
  'fet_title': {AppLocale.ru: 'Развитие малыша', AppLocale.kk: 'Нәрестенің дамуы', AppLocale.en: 'Baby this week'},
  // Week-by-week pregnancy calendar (pw_*), from the MoH calendar contract.
  'pw_week_title': {AppLocale.ru: 'Ваша неделя', AppLocale.kk: 'Сіздің аптаңыз', AppLocale.en: 'Your week'},
  'pw_recommend': {AppLocale.ru: 'Рекомендуем', AppLocale.kk: 'Ұсынамыз', AppLocale.en: 'We recommend'},
  'pw_you': {AppLocale.ru: 'О вас', AppLocale.kk: 'Сіз туралы', AppLocale.en: 'About you'},
  'pw_baby': {AppLocale.ru: 'О малыше', AppLocale.kk: 'Нәресте туралы', AppLocale.en: 'About the baby'},
  'fet_heartbeat': {AppLocale.ru: 'Начинает биться крошечное сердце.', AppLocale.kk: 'Кішкентай жүрек соға бастайды.', AppLocale.en: 'The tiny heart begins to beat.'},
  'fet_neural': {AppLocale.ru: 'Формируются головной и спинной мозг.', AppLocale.kk: 'Ми мен жұлын қалыптасады.', AppLocale.en: 'The brain and spinal cord are taking shape.'},
  'fet_limb_buds': {AppLocale.ru: 'Появляются зачатки ручек и ножек.', AppLocale.kk: 'Қол мен аяқтың бүршіктері пайда болады.', AppLocale.en: 'Tiny arm and leg buds appear.'},
  'fet_fingers': {AppLocale.ru: 'Начинают формироваться пальчики на руках и ногах.', AppLocale.kk: 'Қол мен аяқтың саусақтары қалыптаса бастайды.', AppLocale.en: 'Fingers and toes begin to form.'},
  'fet_organs': {AppLocale.ru: 'Заложены все основные органы.', AppLocale.kk: 'Барлық негізгі мүшелер қаланды.', AppLocale.en: 'All the essential organs are in place.'},
  'fet_nails': {AppLocale.ru: 'Суставы сгибаются, начинают расти ногти.', AppLocale.kk: 'Буындар бүгіледі, тырнақтар өсе бастайды.', AppLocale.en: 'The joints bend and nails start to grow.'},
  'fet_bones': {AppLocale.ru: 'Кости постепенно твердеют.', AppLocale.kk: 'Сүйектер біртіндеп қатаяды.', AppLocale.en: 'The bones are beginning to harden.'},
  'fet_reflexes': {AppLocale.ru: 'Появляются рефлексы: малыш умеет сосать.', AppLocale.kk: 'Рефлекстер пайда болады: нәресте сора алады.', AppLocale.en: 'Reflexes appear — the baby can make sucking movements.'},
  'fet_expressions': {AppLocale.ru: 'Малыш умеет щуриться и хмуриться.', AppLocale.kk: 'Нәресте көзін қысып, қабағын түйе алады.', AppLocale.en: 'The baby can squint and frown.'},
  'fet_fist': {AppLocale.ru: 'Малыш умеет сжимать кулачок.', AppLocale.kk: 'Нәресте жұдырығын түйе алады.', AppLocale.en: 'The baby can make a fist.'},
  'fet_hearing': {AppLocale.ru: 'Ушки заняли своё место — малыш может улавливать звуки.', AppLocale.kk: 'Құлақтар өз орнына орналасты — нәресте дыбыстарды сезе алады.', AppLocale.en: 'The ears are in position — the baby may pick up sounds.'},
  'fet_voice': {AppLocale.ru: 'Малыш начинает слышать ваш голос.', AppLocale.kk: 'Нәресте сіздің дауысыңызды ести бастайды.', AppLocale.en: 'The baby can begin to hear your voice.'},
  'fet_touch': {AppLocale.ru: 'Развиваются осязание и вкусовые рецепторы.', AppLocale.kk: 'Сипап сезу мен дәм сезу дамиды.', AppLocale.en: 'The senses of touch and taste are developing.'},
  'fet_responds': {AppLocale.ru: 'Малыш отвечает на звук движением.', AppLocale.kk: 'Нәресте дыбысқа қимылмен жауап береді.', AppLocale.en: 'The baby responds to sound with movement.'},
  'fet_eyes_open': {AppLocale.ru: 'Глазки начинают открываться.', AppLocale.kk: 'Көздер ашыла бастайды.', AppLocale.en: 'The eyes begin to open.'},
  'fet_dreams': {AppLocale.ru: 'Мозг очень активен, появляются фазы быстрого сна.', AppLocale.kk: 'Ми өте белсенді, жылдам ұйқы кезеңдері пайда болады.', AppLocale.en: 'The brain is very active, with phases of REM sleep.'},
  'fet_light': {AppLocale.ru: 'Малыш уже различает свет и темноту.', AppLocale.kk: 'Нәресте жарық пен қараңғыны ажырата алады.', AppLocale.en: 'The baby can now tell light from dark.'},
  'fet_breathing': {AppLocale.ru: 'Малыш тренирует дыхательные движения.', AppLocale.kk: 'Нәресте тыныс алу қимылдарын жаттықтырады.', AppLocale.en: 'The baby is practising breathing movements.'},
  'fet_lungs': {AppLocale.ru: 'Лёгкие почти готовы к первому вдоху.', AppLocale.kk: 'Өкпе алғашқы дем алуға дерлік дайын.', AppLocale.en: 'The lungs are nearly ready for that first breath.'},
  'fet_head_down': {AppLocale.ru: 'Малыш часто устраивается головкой вниз.', AppLocale.kk: 'Нәресте көбіне басын төмен қаратып орналасады.', AppLocale.en: 'The baby is often settling head-down.'},
  'fet_term': {AppLocale.ru: 'Совсем скоро малыш будет считаться доношенным.', AppLocale.kk: 'Жақында нәресте толық жетілген болып саналады.', AppLocale.en: 'Very soon the baby will be considered full term.'},
  'fet_ready': {AppLocale.ru: 'Малыш готов встретиться с вами.', AppLocale.kk: 'Нәресте сізбен кездесуге дайын.', AppLocale.en: 'The baby is ready to meet you.'},

  // ---- Safe infant sleep (ss_<id>) ----
  'ss_title': {AppLocale.ru: 'Безопасный сон', AppLocale.kk: 'Қауіпсіз ұйқы', AppLocale.en: 'Safe sleep'},
  'ss_intro': {
    AppLocale.ru: 'Каждый сон — малыш один, на спине, в своей кроватке. Эти простые правила заметно снижают риски.',
    AppLocale.kk: 'Әр ұйқыда нәресте жалғыз, шалқасынан, өз бесігінде. Осы қарапайым ережелер қауіпті айтарлықтай азайтады.',
    AppLocale.en: 'Every sleep — baby alone, on the back, in their own cot. These simple rules lower the risk markedly.',
  },
  'ss_do_title': {AppLocale.ru: 'Как безопасно', AppLocale.kk: 'Қалай қауіпсіз', AppLocale.en: 'What helps'},
  'ss_avoid_title': {AppLocale.ru: 'Чего избегать', AppLocale.kk: 'Неден аулақ болу керек', AppLocale.en: 'What to avoid'},
  'ss_disclaimer': {
    AppLocale.ru: 'Это общие рекомендации по безопасному сну, а не медицинская консультация. Вопросы о конкретном ребёнке обсудите с педиатром.',
    AppLocale.kk: 'Бұл — қауіпсіз ұйқы бойынша жалпы ұсыныстар, медициналық кеңес емес. Нақты бала туралы сұрақтарды педиатрмен талқылаңыз.',
    AppLocale.en: 'This is general safe-sleep guidance, not medical advice. Ask your paediatrician about your own child.',
  },

  'ss_back': {
    AppLocale.ru: 'Кладите малыша спать на спину — на дневной и ночной сон.',
    AppLocale.kk: 'Нәрестені шалқасынан ұйықтатыңыз — күндіз де, түнде де.',
    AppLocale.en: 'Put the baby to sleep on the back — for naps and at night.',
  },
  'ss_firm': {
    AppLocale.ru: 'Твёрдый ровный матрас и натянутая простыня, без наклона.',
    AppLocale.kk: 'Қатты тегіс матрас пен тартылған төсеніш, еңкейтусіз.',
    AppLocale.en: 'A firm, flat mattress with a fitted sheet, no incline.',
  },
  'ss_own_bed': {
    AppLocale.ru: 'Своя кроватка в вашей комнате — первые 6 месяцев рядом с вами.',
    AppLocale.kk: 'Өз бесігі сіздің бөлмеңізде — алғашқы 6 айда қасыңызда.',
    AppLocale.en: 'Their own cot in your room — beside you for the first 6 months.',
  },
  'ss_clear': {
    AppLocale.ru: 'В кроватке ничего лишнего: без подушек, одеял, бортиков и игрушек.',
    AppLocale.kk: 'Бесікте артық ешнәрсе жоқ: жастық, көрпе, борт пен ойыншықсыз.',
    AppLocale.en: 'Nothing else in the cot — no pillows, duvets, bumpers or toys.',
  },
  'ss_pacifier': {
    AppLocale.ru: 'Можно предложить пустышку на сон, когда наладится кормление.',
    AppLocale.kk: 'Емізу ретке келгенде ұйқыға емізік ұсынуға болады.',
    AppLocale.en: 'A dummy at sleep can help, once feeding is established.',
  },

  'ss_bedshare': {
    AppLocale.ru: 'Не спите на одной поверхности с малышом, особенно на диване или в кресле.',
    AppLocale.kk: 'Нәрестемен бір бетте ұйықтамаңыз, әсіресе диванда немесе креслода.',
    AppLocale.en: 'Do not sleep on the same surface as the baby, especially a sofa or armchair.',
  },
  'ss_soft': {
    AppLocale.ru: 'Без мягких бортиков, подушек, объёмных одеял и мягких игрушек.',
    AppLocale.kk: 'Жұмсақ борт, жастық, көлемді көрпе мен жұмсақ ойыншықсыз.',
    AppLocale.en: 'No soft bumpers, pillows, thick duvets or soft toys.',
  },
  'ss_overheat': {
    AppLocale.ru: 'Не перегревайте: лёгкая одежда, голова открыта, комнатная температура.',
    AppLocale.kk: 'Қыздырып жібермеңіз: жеңіл киім, бас ашық, бөлме температурасы.',
    AppLocale.en: 'Do not overheat — light clothing, head uncovered, a comfortable room.',
  },
  'ss_smoke': {
    AppLocale.ru: 'Никакого табачного дыма рядом с малышом — ни дома, ни в машине.',
    AppLocale.kk: 'Нәресте маңында темекі түтіні болмасын — үйде де, көлікте де.',
    AppLocale.en: 'No tobacco smoke near the baby — not at home, not in the car.',
  },

  // ---- Starting solids (sol_*) ----
  'sol_title': {AppLocale.ru: 'Прикорм', AppLocale.kk: 'Қосымша тамақ', AppLocale.en: 'Starting solids'},
  'sol_card_title': {AppLocale.ru: 'Прикорм', AppLocale.kk: 'Қосымша тамақ', AppLocale.en: 'Starting solids'},
  'sol_card_sub': {AppLocale.ru: 'Когда и с чего начинать', AppLocale.kk: 'Қашан және неден бастау', AppLocale.en: 'When and how to begin'},
  'sol_until': {AppLocale.ru: 'примерно через {n} мес.', AppLocale.kk: 'шамамен {n} айдан кейін', AppLocale.en: 'in about {n} months'},
  'sol_when_title': {AppLocale.ru: 'Когда начинать', AppLocale.kk: 'Қашан бастау керек', AppLocale.en: 'When to begin'},
  'sol_when_body': {
    AppLocale.ru: 'Обычно около 6 месяцев и не раньше 4. Ориентируйтесь на готовность малыша и совет педиатра.',
    AppLocale.kk: 'Әдетте 6 ай шамасында және 4 айдан ерте емес. Нәрестенің дайындығы мен педиатр кеңесіне сүйеніңіз.',
    AppLocale.en: 'Usually around 6 months, and not before 4. Follow your baby’s readiness and your paediatrician’s advice.',
  },
  'sol_ready_title': {AppLocale.ru: 'Признаки готовности', AppLocale.kk: 'Дайындық белгілері', AppLocale.en: 'Signs of readiness'},
  'sol_stage_title': {AppLocale.ru: 'Что предлагать сейчас', AppLocale.kk: 'Қазір нені ұсыну', AppLocale.en: 'What to offer now'},
  'sol_avoid_title': {AppLocale.ru: 'Пока не стоит', AppLocale.kk: 'Әзірше болмайды', AppLocale.en: 'Not yet'},
  'sol_disclaimer': {
    AppLocale.ru: 'Это общие сведения, а не медицинская консультация. Питание конкретного ребёнка обсуждайте с педиатром.',
    AppLocale.kk: 'Бұл — жалпы мәлімет, медициналық кеңес емес. Нақты баланың тамағын педиатрмен талқылаңыз.',
    AppLocale.en: 'This is general information, not medical advice. Discuss your own child’s diet with your paediatrician.',
  },

  'sol_ready_sits': {
    AppLocale.ru: 'Уверенно сидит с поддержкой и хорошо держит голову.',
    AppLocale.kk: 'Демеумен сенімді отырады және басын жақсы ұстайды.',
    AppLocale.en: 'Sits steadily with support and holds the head well.',
  },
  'sol_ready_interest': {
    AppLocale.ru: 'Проявляет интерес к еде: смотрит и тянется к тому, что вы едите.',
    AppLocale.kk: 'Тамаққа қызығушылық танытады: сіз жегенге қарап, қолын созады.',
    AppLocale.en: 'Shows interest in food — watches and reaches for what you eat.',
  },
  'sol_ready_mouth': {
    AppLocale.ru: 'Может взять предмет и поднести его ко рту.',
    AppLocale.kk: 'Затты алып, аузына апара алады.',
    AppLocale.en: 'Can pick things up and bring them to the mouth.',
  },
  'sol_ready_reflex': {
    AppLocale.ru: 'Больше не выталкивает пищу языком автоматически.',
    AppLocale.kk: 'Тамақты тілімен автоматты түрде итеріп шығармайды.',
    AppLocale.en: 'No longer pushes food back out with the tongue automatically.',
  },

  'sol_stage_first_foods': {
    AppLocale.ru: 'Начинайте с мягких пюре и хорошо размятых продуктов — по одному новому за раз.',
    AppLocale.kk: 'Жұмсақ пюре мен жақсы езілген тағамнан бастаңыз — бір ретте бір жаңа өнім.',
    AppLocale.en: 'Start with smooth purées and well-mashed food — one new food at a time.',
  },
  'sol_stage_allergens': {
    AppLocale.ru: 'Знакомьте с типичными аллергенами (яйцо, арахисовая паста) рано, по одному, наблюдая за реакцией.',
    AppLocale.kk: 'Кең тараған аллергендермен (жұмыртқа, жержаңғақ пастасы) ерте таныстырыңыз — бір-бірлеп, реакцияны бақылап.',
    AppLocale.en: 'Introduce common allergens (egg, smooth peanut) early, one at a time, watching for a reaction.',
  },
  'sol_stage_textures': {
    AppLocale.ru: 'Постепенно делайте пищу гуще и с мягкими кусочками; предлагайте кусочки в руку.',
    AppLocale.kk: 'Тағамды біртіндеп қоюлатып, жұмсақ түйіршіктер қосыңыз; қолға ұстайтын кесектер ұсыныңыз.',
    AppLocale.en: 'Gradually make food thicker and lumpier; offer soft pieces to hold.',
  },
  'sol_stage_family': {
    AppLocale.ru: 'Переходите к измельчённой семейной еде; малыш ест руками и учится ложке.',
    AppLocale.kk: 'Ұсақталған отбасылық тамаққа көшіңіз; нәресте қолымен жеп, қасық ұстауды үйренеді.',
    AppLocale.en: 'Move to chopped family food; the baby eats with their hands and learns the spoon.',
  },

  'sol_avoid_honey': {
    AppLocale.ru: 'Мёд — нельзя до 1 года (риск ботулизма).',
    AppLocale.kk: 'Бал — 1 жасқа дейін болмайды (ботулизм қаупі).',
    AppLocale.en: 'No honey before 1 year (risk of botulism).',
  },
  'sol_avoid_choking': {
    AppLocale.ru: 'Цельные орехи, виноград целиком, твёрдые кусочки — режьте мелко, риск подавиться.',
    AppLocale.kk: 'Бүтін жаңғақ, бүтін жүзім, қатты кесектер — ұсақтап тураңыз, тұншығу қаупі бар.',
    AppLocale.en: 'Whole nuts, whole grapes, hard chunks — cut small; they are choking hazards.',
  },
  'sol_avoid_salt': {
    AppLocale.ru: 'Без добавленной соли — почки малыша ещё незрелы.',
    AppLocale.kk: 'Қосымша тұзсыз — нәрестенің бүйрегі әлі жетілмеген.',
    AppLocale.en: 'No added salt — the baby’s kidneys are still immature.',
  },
  'sol_avoid_sugar': {
    AppLocale.ru: 'Без добавленного сахара и сладких напитков.',
    AppLocale.kk: 'Қосымша қантсыз және тәтті сусынсыз.',
    AppLocale.en: 'No added sugar and no sweet drinks.',
  },

  // ---- Pregnancy weight-gain guide (pwg_*) ----
  'pwg_title': {AppLocale.ru: 'Прибавка в весе', AppLocale.kk: 'Салмақ қосу', AppLocale.en: 'Weight gain'},
  'pwg_link': {AppLocale.ru: 'Сколько набирать?', AppLocale.kk: 'Қанша қосу керек?', AppLocale.en: 'How much to gain?'},
  'pwg_intro': {
    AppLocale.ru: 'Сколько прибавить — зависит от веса до беременности. Ниже — общие ориентиры; личную цель определяет врач.',
    AppLocale.kk: 'Қанша қосу керектігі жүктілікке дейінгі салмаққа байланысты. Төменде — жалпы бағдар; жеке мақсатты дәрігер белгілейді.',
    AppLocale.en: 'How much to gain depends on your pre-pregnancy weight. Below are general guides; your doctor sets your personal goal.',
  },
  'pwg_ranges_title': {AppLocale.ru: 'Ориентировочные диапазоны за всю беременность', AppLocale.kk: 'Бүкіл жүктілікке шамамен диапазондар', AppLocale.en: 'Typical range for the whole pregnancy'},
  'pwg_range_value': {AppLocale.ru: '{low}–{high} кг', AppLocale.kk: '{low}–{high} кг', AppLocale.en: '{low}–{high} kg'},
  'pwg_band_underweight': {AppLocale.ru: 'Недостаточный вес (ИМТ < 18,5)', AppLocale.kk: 'Салмақ жеткіліксіз (ДСИ < 18,5)', AppLocale.en: 'Underweight (BMI < 18.5)'},
  'pwg_band_normal': {AppLocale.ru: 'Нормальный вес (ИМТ 18,5–24,9)', AppLocale.kk: 'Қалыпты салмақ (ДСИ 18,5–24,9)', AppLocale.en: 'Normal (BMI 18.5–24.9)'},
  'pwg_band_overweight': {AppLocale.ru: 'Избыточный вес (ИМТ 25–29,9)', AppLocale.kk: 'Артық салмақ (ДСИ 25–29,9)', AppLocale.en: 'Overweight (BMI 25–29.9)'},
  'pwg_band_obese': {AppLocale.ru: 'Ожирение (ИМТ ≥ 30)', AppLocale.kk: 'Семіздік (ДСИ ≥ 30)', AppLocale.en: 'Obese (BMI ≥ 30)'},

  'pwg_weekly_title': {AppLocale.ru: 'Скорость набора', AppLocale.kk: 'Қосу жылдамдығы', AppLocale.en: 'Rate of gain'},
  'pwg_weekly_body': {
    AppLocale.ru: 'Во 2–3 триместре обычно около {low}–{high} кг в неделю (при нормальном весе до беременности). В 1 триместре прибавка небольшая — примерно {t1low}–{t1high} кг за весь триместр.',
    AppLocale.kk: '2–3 триместрде әдетте аптасына шамамен {low}–{high} кг (жүктілікке дейінгі салмақ қалыпты болса). 1 триместрде қосу аз — бүкіл триместрге шамамен {t1low}–{t1high} кг.',
    AppLocale.en: 'In the 2nd–3rd trimester, typically about {low}–{high} kg a week (for a normal pre-pregnancy weight). The 1st trimester adds little — around {t1low}–{t1high} kg over the whole trimester.',
  },

  'pwg_your_pace_title': {AppLocale.ru: 'Ваш темп', AppLocale.kk: 'Сіздің қарқыныңыз', AppLocale.en: 'Your pace'},
  'pwg_your_avg': {AppLocale.ru: 'Ваша средняя прибавка: {n} кг/нед', AppLocale.kk: 'Орташа қосуыңыз: {n} кг/апта', AppLocale.en: 'Your average gain: {n} kg/week'},
  'pwg_no_data': {AppLocale.ru: 'Отметьте вес несколько раз, чтобы увидеть свой темп.', AppLocale.kk: 'Қарқыныңызды көру үшін салмағыңызды бірнеше рет белгілеңіз.', AppLocale.en: 'Log your weight a few times to see your pace.'},
  'pwg_pace_onTrack': {AppLocale.ru: 'В пределах типичного диапазона.', AppLocale.kk: 'Типтік диапазон шегінде.', AppLocale.en: 'Within the typical range.'},
  'pwg_pace_slow': {
    AppLocale.ru: 'Ниже типичного диапазона. Это не всегда проблема — обсудите с врачом.',
    AppLocale.kk: 'Типтік диапазоннан төмен. Бұл әрқашан мәселе емес — дәрігермен талқылаңыз.',
    AppLocale.en: 'Below the typical range. Not always a problem — discuss it with your doctor.',
  },
  'pwg_pace_fast': {
    AppLocale.ru: 'Выше типичного диапазона. Это не всегда проблема — обсудите с врачом.',
    AppLocale.kk: 'Типтік диапазоннан жоғары. Бұл әрқашан мәселе емес — дәрігермен талқылаңыз.',
    AppLocale.en: 'Above the typical range. Not always a problem — discuss it with your doctor.',
  },
  'pwg_disclaimer': {
    AppLocale.ru: 'Это общие ориентиры, а не медицинская консультация. Диапазоны зависят от веса до беременности и здоровья; вашу цель определяет врач.',
    AppLocale.kk: 'Бұл — жалпы бағдар, медициналық кеңес емес. Диапазондар жүктілікке дейінгі салмақ пен денсаулыққа байланысты; мақсатыңызды дәрігер белгілейді.',
    AppLocale.en: 'These are general guides, not medical advice. Ranges depend on your pre-pregnancy weight and health; your doctor sets your goal.',
  },

  // ---- Hospital-bag checklist (bag_*) ----
  'bag_title': {AppLocale.ru: 'Сумка в роддом', AppLocale.kk: 'Перзентханаға сөмке', AppLocale.en: 'Hospital bag'},
  'bag_card_title': {AppLocale.ru: 'Сумка в роддом', AppLocale.kk: 'Перзентханаға сөмке', AppLocale.en: 'Hospital bag'},
  'bag_packed': {AppLocale.ru: 'Собрано {n} из {total}', AppLocale.kk: '{total} ішінен {n} жиналды', AppLocale.en: '{n} of {total} packed'},
  'bag_done': {AppLocale.ru: 'Всё собрано!', AppLocale.kk: 'Бәрі жиналды!', AppLocale.en: 'All packed!'},
  'bag_intro': {
    AppLocale.ru: 'Отмечайте, что уже собрали. В роддоме могут дать свой список — это отправная точка.',
    AppLocale.kk: 'Жиналған нәрсені белгілеңіз. Перзентхана өз тізімін беруі мүмкін — бұл бастама.',
    AppLocale.en: "Tick off what you've packed. Your hospital may give its own list — this is a starting point.",
  },
  'bag_cat_documents': {AppLocale.ru: 'Документы', AppLocale.kk: 'Құжаттар', AppLocale.en: 'Documents'},
  'bag_cat_mother': {AppLocale.ru: 'Для мамы', AppLocale.kk: 'Ана үшін', AppLocale.en: 'For you'},
  'bag_cat_baby': {AppLocale.ru: 'Для малыша', AppLocale.kk: 'Нәресте үшін', AppLocale.en: 'For the baby'},

  'bag_id_documents': {AppLocale.ru: 'Паспорт / удостоверение', AppLocale.kk: 'Төлқұжат / жеке куәлік', AppLocale.en: 'ID / passport'},
  'bag_exchange_card': {AppLocale.ru: 'Обменная карта', AppLocale.kk: 'Алмасу картасы', AppLocale.en: 'Maternity notes (exchange card)'},
  'bag_insurance': {AppLocale.ru: 'Полис / страховка', AppLocale.kk: 'Полис / сақтандыру', AppLocale.en: 'Insurance'},
  'bag_birth_plan': {AppLocale.ru: 'План родов (если есть)', AppLocale.kk: 'Босану жоспары (болса)', AppLocale.en: 'Birth plan (if you have one)'},

  'bag_nightgown': {AppLocale.ru: 'Ночная рубашка', AppLocale.kk: 'Түнгі көйлек', AppLocale.en: 'Nightgown'},
  'bag_robe_slippers': {AppLocale.ru: 'Халат и тапочки', AppLocale.kk: 'Халат пен тәпішке', AppLocale.en: 'Robe and slippers'},
  'bag_toiletries': {AppLocale.ru: 'Средства гигиены', AppLocale.kk: 'Гигиена құралдары', AppLocale.en: 'Toiletries'},
  'bag_maternity_pads': {AppLocale.ru: 'Послеродовые прокладки', AppLocale.kk: 'Босанғаннан кейінгі прокладкалар', AppLocale.en: 'Maternity pads'},
  'bag_nursing_bra': {AppLocale.ru: 'Бюстгальтер для кормления', AppLocale.kk: 'Емізуге арналған бюстгальтер', AppLocale.en: 'Nursing bra'},
  'bag_phone_charger': {AppLocale.ru: 'Телефон и зарядка', AppLocale.kk: 'Телефон және зарядтағыш', AppLocale.en: 'Phone and charger'},
  'bag_snacks_water': {AppLocale.ru: 'Вода и перекусы', AppLocale.kk: 'Су және жеңіл тағам', AppLocale.en: 'Water and snacks'},
  'bag_going_home_clothes': {AppLocale.ru: 'Одежда на выписку', AppLocale.kk: 'Шығуға арналған киім', AppLocale.en: 'Going-home clothes'},

  'bag_bodysuits': {AppLocale.ru: 'Боди', AppLocale.kk: 'Боди', AppLocale.en: 'Bodysuits'},
  'bag_sleepsuits': {AppLocale.ru: 'Слипы / комбинезоны', AppLocale.kk: 'Слиптер / комбинезондар', AppLocale.en: 'Sleepsuits'},
  'bag_hat_socks': {AppLocale.ru: 'Шапочка и носочки', AppLocale.kk: 'Телпек пен шұлық', AppLocale.en: 'Hat and socks'},
  'bag_nappies': {AppLocale.ru: 'Подгузники для новорождённых', AppLocale.kk: 'Жаңа туған нәрестеге жаялықтар', AppLocale.en: 'Newborn nappies'},
  'bag_swaddle_blanket': {AppLocale.ru: 'Пелёнка / одеяльце', AppLocale.kk: 'Жөргек / көрпеше', AppLocale.en: 'Swaddle / blanket'},
  'bag_car_seat': {AppLocale.ru: 'Автокресло', AppLocale.kk: 'Автокөлік орындығы', AppLocale.en: 'Car seat'},

  // ---- When a child is unwell (ill_*) ----
  'ill_title': {AppLocale.ru: 'Если малыш заболел', AppLocale.kk: 'Егер нәресте ауырса', AppLocale.en: 'When your child is unwell'},
  'ill_intro': {
    AppLocale.ru: 'Короткая памятка на случай болезни. Это не диагноз — при любых сомнениях звоните врачу.',
    AppLocale.kk: 'Ауырған жағдайға арналған қысқаша жаднама. Бұл диагноз емес — кез келген күмәнда дәрігерге қоңырау шалыңыз.',
    AppLocale.en: 'A short reminder for when they are ill. Not a diagnosis — when in doubt, call your doctor.',
  },
  'ill_young_title': {AppLocale.ru: 'Малышам до 3 месяцев', AppLocale.kk: '3 айға дейінгі нәрестелерге', AppLocale.en: 'Babies under 3 months'},
  'ill_young_body': {
    AppLocale.ru: 'В этом возрасте любая температура 38 °C и выше — повод срочно показать ребёнка врачу.',
    AppLocale.kk: 'Бұл жаста 38 °C және одан жоғары кез келген температура — баланы дереу дәрігерге көрсету себебі.',
    AppLocale.en: 'At this age, any temperature of 38 °C or higher needs prompt medical review.',
  },
  'ill_care_title': {AppLocale.ru: 'Что помогает дома', AppLocale.kk: 'Үйде не көмектеседі', AppLocale.en: 'What helps at home'},
  'ill_warn_title': {AppLocale.ru: 'Когда срочно к врачу', AppLocale.kk: 'Қашан дереу дәрігерге', AppLocale.en: 'When to get help now'},
  'ill_warn_intro': {
    AppLocale.ru: 'Позвоните в поликлинику или скорую, если появится что-то из этого:',
    AppLocale.kk: 'Мыналардың бірі пайда болса, емханаға немесе жедел жәрдемге қоңырау шалыңыз:',
    AppLocale.en: 'Call your clinic or emergency services if any of these appear:',
  },
  'ill_disclaimer': {
    AppLocale.ru: 'Это общие сведения, а не медицинская консультация. Дозы лекарств и лечение подбирает врач или фармацевт по весу и возрасту.',
    AppLocale.kk: 'Бұл — жалпы мәлімет, медициналық кеңес емес. Дәрі мөлшері мен емдеуді дәрігер немесе фармацевт салмақ пен жасқа қарай таңдайды.',
    AppLocale.en: 'General information, not medical advice. Medicine doses and treatment are set by a doctor or pharmacist, by weight and age.',
  },

  'ill_care_fluids': {
    AppLocale.ru: 'Чаще предлагайте грудь, смесь или воду (по возрасту) — обезвоживание опаснее самой температуры.',
    AppLocale.kk: 'Кеудені, қоспаны немесе суды (жасына қарай) жиі ұсыныңыз — сусыздану температураның өзінен қауіптірек.',
    AppLocale.en: 'Offer the breast, formula or water (as age-appropriate) often — dehydration is the real risk, more than the fever itself.',
  },
  'ill_care_rest': {
    AppLocale.ru: 'Дайте отдохнуть и не кутайте — перегрев не помогает.',
    AppLocale.kk: 'Демалуға мүмкіндік беріңіз, қатты орамаңыз — қызып кету көмектеспейді.',
    AppLocale.en: 'Let them rest, and do not overwrap — overheating does not help.',
  },
  'ill_care_light_clothing': {
    AppLocale.ru: 'Лёгкая одежда и комфортная температура в комнате.',
    AppLocale.kk: 'Жеңіл киім және бөлмедегі жайлы температура.',
    AppLocale.en: 'Light clothing and a comfortable room temperature.',
  },
  'ill_care_medicine': {
    AppLocale.ru: 'Жаропонижающее — только по возрасту и по совету врача или инструкции; не давайте аспирин детям.',
    AppLocale.kk: 'Температура түсіретін дәрі — тек жасына қарай және дәрігер кеңесімен не нұсқаулықпен; балаларға аспирин бермеңіз.',
    AppLocale.en: "Fever medicine only by age and your doctor's or the label's guidance; never give a child aspirin.",
  },
  'ill_care_watch': {
    AppLocale.ru: 'Следите за самочувствием и признаками ниже; доверяйте себе — вы знаете своего малыша.',
    AppLocale.kk: 'Жағдайын және төмендегі белгілерді бақылаңыз; өзіңізге сеніңіз — нәрестеңізді өзіңіз жақсы білесіз.',
    AppLocale.en: 'Watch how they seem and the signs below; trust yourself — you know your child.',
  },

  'ill_warn_breathing': {
    AppLocale.ru: 'Тяжёлое, частое дыхание или кряхтение при дыхании',
    AppLocale.kk: 'Ауыр, жиі тыныс алу немесе тыныс алғанда ыңқылдау',
    AppLocale.en: 'Fast, laboured or grunting breathing',
  },
  'ill_warn_colour': {
    AppLocale.ru: 'Очень бледная, синюшная или серая кожа или губы',
    AppLocale.kk: 'Өте бозарған, көгілдір немесе сұр тері не ерін',
    AppLocale.en: 'Very pale, blue or grey skin or lips',
  },
  'ill_warn_rash': {
    AppLocale.ru: 'Сыпь, которая не бледнеет при надавливании (проверьте стеклянным стаканом)',
    AppLocale.kk: 'Басқанда бозармайтын бөртпе (шыны стақанмен тексеріңіз)',
    AppLocale.en: 'A rash that does not fade when you press a glass on it',
  },
  'ill_warn_stiff_neck': {
    AppLocale.ru: 'Ригидность шеи, выбухание родничка или светобоязнь',
    AppLocale.kk: 'Мойынның қатаюы, еңбектің томпаюы немесе жарықтан қорқу',
    AppLocale.en: 'A stiff neck, a bulging soft spot, or dislike of bright light',
  },
  'ill_warn_seizure': {
    AppLocale.ru: 'Судороги (припадок)',
    AppLocale.kk: 'Құрысу (талма)',
    AppLocale.en: 'A fit or convulsion',
  },
  'ill_warn_unrousable': {
    AppLocale.ru: 'Вялость, необычная сонливость, трудно разбудить',
    AppLocale.kk: 'Босаңдық, әдеттен тыс ұйқышылдық, оятудың қиындығы',
    AppLocale.en: 'Floppy, unusually drowsy, or hard to wake',
  },
  'ill_warn_dehydration': {
    AppLocale.ru: 'Нет мокрых подгузников, плач без слёз, запавшие глаза',
    AppLocale.kk: 'Дымқыл жаялық жоқ, жансыз жылау, көздің шүңірейуі',
    AppLocale.en: 'No wet nappies, crying without tears, or sunken eyes',
  },
  'ill_warn_persistent': {
    AppLocale.ru: 'Высокая температура, которая не спадает или держится долго',
    AppLocale.kk: 'Түспейтін немесе ұзаққа созылатын жоғары температура',
    AppLocale.en: 'A high fever that will not come down, or lasts',
  },

  // ---- Home-safety / babyproofing checklist (hs_*) ----
  'hs_title': {AppLocale.ru: 'Безопасность дома', AppLocale.kk: 'Үйдегі қауіпсіздік', AppLocale.en: 'Home safety'},
  'hs_card_title': {AppLocale.ru: 'Безопасность дома', AppLocale.kk: 'Үйдегі қауіпсіздік', AppLocale.en: 'Home safety'},
  'hs_progress': {AppLocale.ru: 'Сделано {n} из {total}', AppLocale.kk: '{total} ішінен {n} орындалды', AppLocale.en: '{n} of {total} done'},
  'hs_all_done': {AppLocale.ru: 'Всё готово!', AppLocale.kk: 'Бәрі дайын!', AppLocale.en: 'All done!'},
  'hs_intro': {
    AppLocale.ru: 'Безопасность дома растёт вместе с малышом: список пополняется по мере взросления. Это общие подсказки, а не гарантия.',
    AppLocale.kk: 'Үйдегі қауіпсіздік нәрестемен бірге өседі: тізім балаңыз есейген сайын толығады. Бұл — жалпы кеңестер, кепілдік емес.',
    AppLocale.en: 'Home safety grows with your child — the list fills out as they get older. General prompts, not a guarantee.',
  },
  'hs_stage_birth': {AppLocale.ru: 'С рождения', AppLocale.kk: 'Туғаннан бастап', AppLocale.en: 'From birth'},
  'hs_stage_rolling': {AppLocale.ru: 'Когда начинает тянуться и переворачиваться', AppLocale.kk: 'Аунап, қол созғаннан бастап', AppLocale.en: 'Once they roll and reach'},
  'hs_stage_crawling': {AppLocale.ru: 'Когда ползает', AppLocale.kk: 'Еңбектегеннен бастап', AppLocale.en: 'Once they crawl'},
  'hs_stage_standing': {AppLocale.ru: 'Когда встаёт и лезет', AppLocale.kk: 'Тұрып, өрмелегеннен бастап', AppLocale.en: 'Once they pull up and climb'},

  'hs_safe_sleep_space': {AppLocale.ru: 'Безопасное место для сна: жёсткий матрас, без подушек и мягких игрушек.', AppLocale.kk: 'Қауіпсіз ұйқы орны: қатты матрас, жастықсыз және жұмсақ ойыншықсыз.', AppLocale.en: 'A safe sleep space: firm mattress, no pillows or soft toys.'},
  'hs_smoke_alarm': {AppLocale.ru: 'Рабочий датчик дыма в доме.', AppLocale.kk: 'Үйде істейтін түтін датчигі.', AppLocale.en: 'A working smoke alarm in the home.'},
  'hs_water_temp': {AppLocale.ru: 'Вода из-под крана не горячее ~50 °C.', AppLocale.kk: 'Судан келетін су ~50 °C-тан ыстық емес.', AppLocale.en: 'Tap water no hotter than ~50 °C.'},
  'hs_never_alone_high': {AppLocale.ru: 'Не оставляйте малыша одного на высоте — на пеленальном столике, на кровати.', AppLocale.kk: 'Нәрестені биікте — жөргек үстелінде, төсекте жалғыз қалдырмаңыз.', AppLocale.en: 'Never leave the baby alone up high — on a changing table or bed.'},

  'hs_small_objects': {AppLocale.ru: 'Мелкие предметы — вне досягаемости (риск подавиться).', AppLocale.kk: 'Ұсақ заттар — қол жетпейтін жерде (тұншығу қаупі).', AppLocale.en: 'Small objects out of reach (choking risk).'},
  'hs_blind_cords': {AppLocale.ru: 'Шнуры от штор и жалюзи подняты и закреплены.', AppLocale.kk: 'Перде мен жалюзи баулары жоғары көтеріліп бекітілген.', AppLocale.en: 'Blind and curtain cords tied up out of reach.'},
  'hs_hot_drinks': {AppLocale.ru: 'Горячие напитки — подальше от края стола и от малыша.', AppLocale.kk: 'Ыстық сусындар — үстел шетінен және нәрестеден алыс.', AppLocale.en: 'Hot drinks away from table edges and the baby.'},

  'hs_outlet_covers': {AppLocale.ru: 'Заглушки на электрические розетки.', AppLocale.kk: 'Электр розеткаларына тығындар.', AppLocale.en: 'Covers on electrical outlets.'},
  'hs_cupboard_locks': {AppLocale.ru: 'Замки на шкафы и ящики.', AppLocale.kk: 'Шкаф пен тартпаларға құлыптар.', AppLocale.en: 'Locks on cupboards and drawers.'},
  'hs_stair_gates': {AppLocale.ru: 'Ворота безопасности на лестнице — сверху и снизу.', AppLocale.kk: 'Баспалдаққа қауіпсіздік қақпалары — жоғарыда және төменде.', AppLocale.en: 'Safety gates on stairs — top and bottom.'},
  'hs_sharp_corners': {AppLocale.ru: 'Накладки на острые углы мебели.', AppLocale.kk: 'Жиһаздың өткір бұрыштарына қаптамалар.', AppLocale.en: 'Guards on sharp furniture corners.'},
  'hs_chemicals_high': {AppLocale.ru: 'Бытовая химия — высоко и под замком.', AppLocale.kk: 'Тұрмыстық химия — биікте және құлыпта.', AppLocale.en: 'Cleaning products high up and locked away.'},
  'hs_medicines_locked': {AppLocale.ru: 'Лекарства — под замком, вне досягаемости.', AppLocale.kk: 'Дәрілер — құлыпта, қол жетпейтін жерде.', AppLocale.en: 'Medicines locked away, out of reach.'},

  'hs_furniture_anchored': {AppLocale.ru: 'Высокая мебель и телевизор закреплены к стене.', AppLocale.kk: 'Биік жиһаз бен теледидар қабырғаға бекітілген.', AppLocale.en: 'Tall furniture and the TV anchored to the wall.'},
  'hs_window_locks': {AppLocale.ru: 'Ограничители или замки на окнах.', AppLocale.kk: 'Терезелерге шектегіштер немесе құлыптар.', AppLocale.en: 'Restrictors or locks on windows.'},
  'hs_water_supervision': {AppLocale.ru: 'Никогда не оставляйте у воды без присмотра — ванна, ведро, бассейн.', AppLocale.kk: 'Су маңында қараусыз қалдырмаңыз — ванна, шелек, бассейн.', AppLocale.en: 'Never leave them near water unsupervised — bath, bucket, pool.'},

  'vac_hepb': {AppLocale.ru: 'Гепатит B', AppLocale.kk: 'В гепатиті', AppLocale.en: 'Hepatitis B'},
  'vac_hepb_note': {AppLocale.ru: 'Защищает печень от вирусного гепатита B.', AppLocale.kk: 'Бауырды В вирусты гепатитінен қорғайды.', AppLocale.en: 'Protects the liver against hepatitis B.'},
  'vac_bcg': {AppLocale.ru: 'БЦЖ', AppLocale.kk: 'БЦЖ', AppLocale.en: 'BCG'},
  'vac_bcg_note': {AppLocale.ru: 'Против тяжёлых форм туберкулёза.', AppLocale.kk: 'Туберкулёздің ауыр түрлеріне қарсы.', AppLocale.en: 'Against severe forms of tuberculosis.'},
  'vac_pentavalent': {AppLocale.ru: 'Пятивалентная (АКДС + гепатит B + Hib)', AppLocale.kk: 'Бес валентті (АКДС + В гепатиті + Hib)', AppLocale.en: 'Pentavalent (DTP + hep B + Hib)'},
  'vac_pentavalent_note': {AppLocale.ru: 'Дифтерия, столбняк, коклюш, гепатит B и гемофильная инфекция — одним уколом.', AppLocale.kk: 'Дифтерия, сіреспе, көкжөтел, В гепатиті және гемофильді инфекция — бір егумен.', AppLocale.en: 'Diphtheria, tetanus, whooping cough, hepatitis B and Hib in one injection.'},
  'vac_opv': {AppLocale.ru: 'Полиомиелит', AppLocale.kk: 'Полиомиелит', AppLocale.en: 'Polio'},
  'vac_opv_note': {AppLocale.ru: 'Капли или укол — по схеме поликлиники.', AppLocale.kk: 'Тамшы немесе егу — емхана сызбасы бойынша.', AppLocale.en: 'Drops or an injection, depending on the clinic’s schedule.'},
  'vac_pcv': {AppLocale.ru: 'Пневмококковая', AppLocale.kk: 'Пневмококк', AppLocale.en: 'Pneumococcal'},
  'vac_pcv_note': {AppLocale.ru: 'Против пневмонии и отита, вызванных пневмококком.', AppLocale.kk: 'Пневмококк тудыратын пневмония мен отитке қарсы.', AppLocale.en: 'Against pneumonia and ear infections caused by pneumococcus.'},
  'vac_mmr': {AppLocale.ru: 'Корь, паротит, краснуха (ККП)', AppLocale.kk: 'Қызылша, паротит, қызамық (ҚПҚ)', AppLocale.en: 'Measles, mumps, rubella (MMR)'},
  'vac_mmr_note': {AppLocale.ru: 'Три инфекции одной вакциной; вторая доза — перед школой.', AppLocale.kk: 'Бір вакцинамен үш инфекция; екінші доза — мектеп алдында.', AppLocale.en: 'Three infections in one vaccine; the second dose is before school.'},
  // The Kazakh of these two was the Russian, word for word. Only the
  // parenthetical is translated: АКДС and Hib are what is printed on the RK
  // immunisation card a mother matches this list against, so they stay, while
  // «ревакцинация» has an ordinary Kazakh word — «қайта екпе» — and had no
  // reason to be Russian.
  'vac_dtp': {AppLocale.ru: 'АКДС (ревакцинация)', AppLocale.kk: 'АКДС (қайта екпе)', AppLocale.en: 'DTP booster'},
  'vac_dtp_note': {AppLocale.ru: 'Поддерживает защиту от дифтерии, столбняка и коклюша.', AppLocale.kk: 'Дифтерия, сіреспе және көкжөтелден қорғанысты сақтайды.', AppLocale.en: 'Keeps up protection against diphtheria, tetanus and whooping cough.'},
  'vac_hib': {AppLocale.ru: 'Гемофильная инфекция (ревакцинация)', AppLocale.kk: 'Гемофильді инфекция (қайта екпе)', AppLocale.en: 'Hib booster'},
  'vac_hib_note': {AppLocale.ru: 'Против менингита и пневмонии, вызванных Hib.', AppLocale.kk: 'Hib тудыратын менингит пен пневмонияға қарсы.', AppLocale.en: 'Against Hib meningitis and pneumonia.'},
  'vac_adt': {AppLocale.ru: 'АДС-М', AppLocale.kk: 'АДС-М', AppLocale.en: 'Td'},
  'vac_adt_note': {AppLocale.ru: 'Дифтерия и столбняк, перед школой.', AppLocale.kk: 'Дифтерия мен сіреспе, мектеп алдында.', AppLocale.en: 'Diphtheria and tetanus, before school.'},
  // ---- Week detail ----
  'gest_details': {AppLocale.ru: 'Подробнее', AppLocale.kk: 'Толығырақ', AppLocale.en: 'More'},
  'ms_next': {AppLocale.ru: 'Следующий рубеж', AppLocale.kk: 'Келесі кезең', AppLocale.en: 'Next milestone'},
  'ms_in_weeks': {AppLocale.ru: 'через {n} нед.', AppLocale.kk: '{n} аптадан кейін', AppLocale.en: 'in {n} weeks'},
  // Every week figure in the app is calendar-derived, not measured. Said once,
  // plainly, on the screen that goes into the most detail about it.
  'gest_estimate_note': {
    AppLocale.ru: 'Все сроки здесь рассчитаны от предполагаемой даты родов. Точные данные о развитии даёт только УЗИ и осмотр врача.',
    AppLocale.kk: 'Мұндағы барлық мерзім болжамды босану күнінен есептелген. Дамудың нақты көрсеткіштерін тек УДЗ бен дәрігер қарауы береді.',
    AppLocale.en: 'Every date here is calculated from the estimated due date. Only a scan and your doctor can say how the baby is actually developing.',
  },

  // ---- Child development calendar ----
  //
  // Every milestone has a title and a short note. The note carries the RANGE in
  // words, because a parent reading "5 месяцев" next to a 7-month-old needs to
  // be told, in the same breath, that the spread is normal.
  'dev_title': {AppLocale.ru: 'Развитие малыша', AppLocale.kk: 'Баланың дамуы', AppLocale.en: 'Baby development'},
  'dev_sub': {AppLocale.ru: 'Что происходит сейчас и что впереди', AppLocale.kk: 'Қазір не болып жатыр және алда не бар', AppLocale.en: 'What is happening now, and what comes next'},
  'dev_now': {AppLocale.ru: 'Сейчас', AppLocale.kk: 'Қазір', AppLocale.en: 'Right now'},
  'dev_next': {AppLocale.ru: 'Скоро', AppLocale.kk: 'Жақында', AppLocale.en: 'Coming up'},
  'dev_done': {AppLocale.ru: 'Уже позади', AppLocale.kk: 'Артта қалды', AppLocale.en: 'Already behind you'},
  'dev_ask': {AppLocale.ru: 'Стоит обсудить с врачом', AppLocale.kk: 'Дәрігермен талқылаған жөн', AppLocale.en: 'Worth asking your doctor'},
  'dev_age': {AppLocale.ru: '{n} мес.', AppLocale.kk: '{n} ай', AppLocale.en: '{n} mo'},
  'dev_range': {AppLocale.ru: '{a}–{b} мес.', AppLocale.kk: '{a}–{b} ай', AppLocale.en: '{a}–{b} mo'},
  'dev_ask_note': {
    AppLocale.ru: 'Если этого пока нет — просто спросите на ближайшем приёме. Это не диагноз и не повод для тревоги.',
    AppLocale.kk: 'Егер бұл әлі болмаса — жақындағы қабылдауда сұраңыз. Бұл диагноз да, алаңдау себебі де емес.',
    AppLocale.en: 'If this has not happened yet, just mention it at the next visit. It is not a diagnosis and not a reason to worry.',
  },
  'dev_spread': {
    AppLocale.ru: 'Дети развиваются очень по-разному. Диапазоны здесь — это то, где оказывается большинство, а не расписание.',
    AppLocale.kk: 'Балалар әртүрлі дамиды. Мұндағы аралықтар — көпшілік қай кезде жететіні, кесте емес.',
    AppLocale.en: 'Children develop at very different rates. These ranges are where most land — not a schedule.',
  },
  'dev_no_birthdate': {AppLocale.ru: 'Добавьте дату рождения ребёнка, чтобы увидеть его календарь развития.', AppLocale.kk: 'Даму күнтізбесін көру үшін баланың туған күнін қосыңыз.', AppLocale.en: 'Add your child’s date of birth to see their development calendar.'},
  // Past the calendar's range (the milestone table stops around three years).
  // Without this the screen showed a name, a disclaimer and then nothing,
  // which reads as data that failed to load rather than as a child who has
  // grown out of it.
  'dev_outgrown_title': {
    AppLocale.ru: 'Этот календарь — для первых лет',
    AppLocale.kk: 'Бұл күнтізбе — алғашқы жылдарға',
    AppLocale.en: 'This calendar covers the early years',
  },
  'dev_outgrown_body': {
    AppLocale.ru: 'Ваш ребёнок уже прошёл все вехи раннего развития — здесь больше нечего отмечать. Прививки, рост и вес по-прежнему на его карточке во вкладке «Ребёнок».',
    AppLocale.kk: 'Балаңыз ерте дамудың барлық кезеңдерінен өтті — мұнда белгілейтін ештеңе қалмады. Егулер, бой мен салмақ «Бала» бөліміндегі карточкасында сақталады.',
    AppLocale.en: 'Your child has passed every early-development milestone, so there is nothing left to track here. Vaccinations, height and weight are still on their card in the Child tab.',
  },

  // Week-by-week growth & skills card (baby_development calendar, first year)
  'cdw_title': {AppLocale.ru: 'Ваш малыш на этой неделе', AppLocale.kk: 'Балаңыз осы аптада', AppLocale.en: 'Your baby this week'},
  'cdw_week': {AppLocale.ru: '{n}-я неделя', AppLocale.kk: '{n}-апта', AppLocale.en: 'Week {n}'},
  'cdw_weight': {AppLocale.ru: 'Вес', AppLocale.kk: 'Салмағы', AppLocale.en: 'Weight'},
  'cdw_height': {AppLocale.ru: 'Рост', AppLocale.kk: 'Бойы', AppLocale.en: 'Height'},
  'cdw_motor': {AppLocale.ru: 'Двигательные навыки', AppLocale.kk: 'Қимыл-қозғалыс дағдылары', AppLocale.en: 'Motor skills'},
  'cdw_speech': {AppLocale.ru: 'Речевые навыки', AppLocale.kk: 'Сөйлеу дағдылары', AppLocale.en: 'Speech skills'},
  'cdw_cognition': {AppLocale.ru: 'Познание', AppLocale.kk: 'Таным', AppLocale.en: 'Cognition'},

  // Areas
  'dev_area_motor': {AppLocale.ru: 'Движение', AppLocale.kk: 'Қозғалыс', AppLocale.en: 'Movement'},
  'dev_area_fine': {AppLocale.ru: 'Руки', AppLocale.kk: 'Қол қимылы', AppLocale.en: 'Hands'},
  'dev_area_speech': {AppLocale.ru: 'Речь', AppLocale.kk: 'Сөйлеу', AppLocale.en: 'Speech'},
  'dev_area_social': {AppLocale.ru: 'Общение', AppLocale.kk: 'Қарым-қатынас', AppLocale.en: 'Social'},
  'dev_area_teeth': {AppLocale.ru: 'Зубы', AppLocale.kk: 'Тістер', AppLocale.en: 'Teeth'},
  'dev_area_feeding': {AppLocale.ru: 'Питание', AppLocale.kk: 'Тамақтану', AppLocale.en: 'Feeding'},

  // Milestones
  'dev_lifts_head': {AppLocale.ru: 'Приподнимает голову', AppLocale.kk: 'Басын көтереді', AppLocale.en: 'Lifts their head'},
  'dev_lifts_head_note': {AppLocale.ru: 'Лёжа на животе поднимает голову на несколько секунд.', AppLocale.kk: 'Етпетінен жатып басын бірнеше секундқа көтереді.', AppLocale.en: 'Lifts their head for a few seconds while on their tummy.'},
  'dev_social_smile': {AppLocale.ru: 'Улыбается в ответ', AppLocale.kk: 'Жауап ретінде жымияды', AppLocale.en: 'Smiles back'},
  'dev_social_smile_note': {AppLocale.ru: 'Первая настоящая улыбка — не во сне, а вам.', AppLocale.kk: 'Алғашқы шынайы күлкі — ұйқыда емес, сізге.', AppLocale.en: 'The first real smile — not in sleep, but at you.'},
  'dev_follows_objects': {AppLocale.ru: 'Следит взглядом', AppLocale.kk: 'Көзімен қадағалайды', AppLocale.en: 'Follows with their eyes'},
  'dev_follows_objects_note': {AppLocale.ru: 'Провожает глазами лицо или игрушку, которая двигается.', AppLocale.kk: 'Қозғалған бет пен ойыншықты көзімен қуады.', AppLocale.en: 'Tracks a face or a toy as it moves.'},
  'dev_coos': {AppLocale.ru: 'Гулит', AppLocale.kk: 'Гуілдейді', AppLocale.en: 'Coos'},
  'dev_coos_note': {AppLocale.ru: 'Тянет гласные — «а-а», «у-у». Первые звуки, не плач.', AppLocale.kk: 'Дауысты дыбыстарды созады. Жылау емес, алғашқы дыбыстар.', AppLocale.en: 'Drawn-out vowel sounds. The first noises that are not crying.'},
  'dev_holds_head_steady': {AppLocale.ru: 'Уверенно держит голову', AppLocale.kk: 'Басын сенімді ұстайды', AppLocale.en: 'Holds their head steady'},
  'dev_holds_head_steady_note': {AppLocale.ru: 'На руках голова больше не запрокидывается.', AppLocale.kk: 'Қолда басы енді шалқаймайды.', AppLocale.en: 'Their head no longer lolls when you hold them upright.'},
  'dev_grasps': {AppLocale.ru: 'Хватает предметы', AppLocale.kk: 'Заттарды ұстайды', AppLocale.en: 'Grabs things'},
  'dev_grasps_note': {AppLocale.ru: 'Тянется и берёт погремушку — и сразу тянет в рот.', AppLocale.kk: 'Сылдырмаққа қол созып алады — және бірден аузына салады.', AppLocale.en: 'Reaches for a rattle and takes it — then puts it straight in their mouth.'},
  'dev_rolls_over': {AppLocale.ru: 'Переворачивается', AppLocale.kk: 'Аунайды', AppLocale.en: 'Rolls over'},
  'dev_rolls_over_note': {AppLocale.ru: 'Со спины на живот и обратно. С этого дня не оставляйте одного на высоте.', AppLocale.kk: 'Арқасынан етпетіне және кері. Осы күннен бастап биікте жалғыз қалдырмаңыз.', AppLocale.en: 'Back to front and back again. From now on, never alone on a raised surface.'},
  'dev_laughs': {AppLocale.ru: 'Смеётся', AppLocale.kk: 'Күледі', AppLocale.en: 'Laughs'},
  'dev_laughs_note': {AppLocale.ru: 'Настоящий смех в ответ на игру.', AppLocale.kk: 'Ойынға жауап ретінде нағыз күлкі.', AppLocale.en: 'A real laugh in response to play.'},
  'dev_first_solids': {AppLocale.ru: 'Первый прикорм', AppLocale.kk: 'Алғашқы қосымша тамақ', AppLocale.en: 'First solid food'},
  'dev_first_solids_note': {AppLocale.ru: 'ВОЗ рекомендует начинать около 6 месяцев. Сроки лучше обсудить с педиатром.', AppLocale.kk: 'ДДҰ шамамен 6 айдан бастауды ұсынады. Мерзімін педиатрмен талқылаған жөн.', AppLocale.en: 'The WHO suggests starting around 6 months. Discuss the timing with your paediatrician.'},
  'dev_first_tooth': {AppLocale.ru: 'Первый зуб', AppLocale.kk: 'Алғашқы тіс', AppLocale.en: 'First tooth'},
  'dev_first_tooth_note': {AppLocale.ru: 'Обычно нижние передние. Разброс огромный: и в 3 месяца, и в год — норма.', AppLocale.kk: 'Әдетте төменгі алдыңғы тістер. Аралығы өте кең: 3 айда да, бір жаста да — қалыпты.', AppLocale.en: 'Usually the bottom front two. The spread is huge — 3 months and 12 months are both ordinary.'},
  'dev_sits_supported': {AppLocale.ru: 'Сидит с поддержкой', AppLocale.kk: 'Демеумен отырады', AppLocale.en: 'Sits with support'},
  'dev_sits_supported_note': {AppLocale.ru: 'Держит спину, если его подпереть подушками.', AppLocale.kk: 'Жастықпен демегенде арқасын ұстайды.', AppLocale.en: 'Holds their back upright when propped with cushions.'},
  'dev_babbles': {AppLocale.ru: 'Лепечет', AppLocale.kk: 'Былдырлайды', AppLocale.en: 'Babbles'},
  'dev_babbles_note': {AppLocale.ru: '«ба-ба», «да-да» — слоги, ещё без значения.', AppLocale.kk: '«ба-ба», «да-да» — мағынасыз буындар.', AppLocale.en: '“ba-ba”, “da-da” — syllables, not yet words.'},
  'dev_sits_alone': {AppLocale.ru: 'Сидит сам', AppLocale.kk: 'Өзі отырады', AppLocale.en: 'Sits unsupported'},
  'dev_sits_alone_note': {AppLocale.ru: 'Сидит без опоры и при этом может играть руками.', AppLocale.kk: 'Демеусіз отырады және сол кезде қолымен ойнай алады.', AppLocale.en: 'Sits without support, and can play with their hands while doing it.'},
  'dev_passes_objects': {AppLocale.ru: 'Перекладывает из руки в руку', AppLocale.kk: 'Қолдан қолға ауыстырады', AppLocale.en: 'Passes things hand to hand'},
  'dev_passes_objects_note': {AppLocale.ru: 'Берёт предмет одной рукой и передаёт в другую.', AppLocale.kk: 'Затты бір қолымен алып, екіншісіне береді.', AppLocale.en: 'Takes something in one hand and moves it to the other.'},
  'dev_stranger_awareness': {AppLocale.ru: 'Отличает своих от чужих', AppLocale.kk: 'Өзін-өзгені ажыратады', AppLocale.en: 'Notices strangers'},
  'dev_stranger_awareness_note': {AppLocale.ru: 'Может стесняться незнакомых. Это признак привязанности, а не характера.', AppLocale.kk: 'Бейтаныс адамдардан ұялуы мүмкін. Бұл мінез емес, бауырмалдық белгісі.', AppLocale.en: 'May go shy with unfamiliar people. A sign of attachment, not temperament.'},
  'dev_crawls': {AppLocale.ru: 'Ползает', AppLocale.kk: 'Еңбектейді', AppLocale.en: 'Crawls'},
  'dev_crawls_note': {AppLocale.ru: 'По-пластунски, на четвереньках или на попе. Некоторые дети пропускают ползание совсем — это тоже норма.', AppLocale.kk: 'Жорғалап, төрт аяқтап немесе отырып. Кейбір балалар мүлде еңбектемейді — бұл да қалыпты.', AppLocale.en: 'On their belly, on all fours, or shuffling. Some children skip crawling entirely — also ordinary.'},
  'dev_pincer_grip': {AppLocale.ru: 'Берёт двумя пальцами', AppLocale.kk: 'Екі саусақпен алады', AppLocale.en: 'Pincer grip'},
  'dev_pincer_grip_note': {AppLocale.ru: 'Поднимает крошку большим и указательным пальцем.', AppLocale.kk: 'Үлкен және сұқ саусағымен ұсақ нәрсені көтереді.', AppLocale.en: 'Picks up a crumb between thumb and forefinger.'},
  'dev_pulls_to_stand': {AppLocale.ru: 'Встаёт у опоры', AppLocale.kk: 'Тіреуге сүйеніп тұрады', AppLocale.en: 'Pulls up to stand'},
  'dev_pulls_to_stand_note': {AppLocale.ru: 'Подтягивается за диван или кроватку и встаёт.', AppLocale.kk: 'Диванға немесе кереуетке тартылып тұрады.', AppLocale.en: 'Hauls themselves up on the sofa or the cot.'},
  'dev_waves_bye': {AppLocale.ru: 'Машет «пока»', AppLocale.kk: '«Сау бол» деп қол бұлғайды', AppLocale.en: 'Waves bye-bye'},
  'dev_waves_bye_note': {AppLocale.ru: 'Повторяет жест за вами и понимает, что он значит.', AppLocale.kk: 'Ишараны сізден қайталайды және мағынасын түсінеді.', AppLocale.en: 'Copies the gesture and understands what it means.'},
  'dev_cup': {AppLocale.ru: 'Пьёт из чашки', AppLocale.kk: 'Кеседен ішеді', AppLocale.en: 'Drinks from a cup'},
  'dev_cup_note': {AppLocale.ru: 'С вашей помощью — и почти всё мимо. Это нормально.', AppLocale.kk: 'Сіздің көмегіңізбен — және көбі төгіледі. Бұл қалыпты.', AppLocale.en: 'With your help, and mostly down their front. That is normal.'},
  'dev_first_words': {AppLocale.ru: 'Первые слова', AppLocale.kk: 'Алғашқы сөздер', AppLocale.en: 'First words'},
  'dev_first_words_note': {AppLocale.ru: '«мама», «папа» — уже осмысленно, обращаясь именно к вам.', AppLocale.kk: '«мама», «папа» — енді мағыналы, дәл сізге қаратып.', AppLocale.en: '“mama”, “papa” — meant, and aimed at you.'},
  'dev_stands_alone': {AppLocale.ru: 'Стоит сам', AppLocale.kk: 'Өзі тұрады', AppLocale.en: 'Stands alone'},
  'dev_stands_alone_note': {AppLocale.ru: 'Несколько секунд без опоры.', AppLocale.kk: 'Бірнеше секунд тіреусіз.', AppLocale.en: 'A few seconds without holding on.'},
  'dev_first_steps': {AppLocale.ru: 'Первые шаги', AppLocale.kk: 'Алғашқы қадамдар', AppLocale.en: 'First steps'},
  'dev_first_steps_note': {AppLocale.ru: 'Разброс от 9 до 15 месяцев — и это всё норма. Позже тоже бывает.', AppLocale.kk: '9 айдан 15 айға дейін — бәрі қалыпты. Кешірек те болады.', AppLocale.en: 'Anywhere from 9 to 15 months is ordinary. Later happens too.'},
  'dev_self_feeds_spoon': {AppLocale.ru: 'Ест ложкой сам', AppLocale.kk: 'Қасықпен өзі жейді', AppLocale.en: 'Uses a spoon'},
  'dev_self_feeds_spoon_note': {AppLocale.ru: 'Держит ложку и доносит до рта — не каждый раз.', AppLocale.kk: 'Қасықты ұстап аузына жеткізеді — әрдайым емес.', AppLocale.en: 'Holds the spoon and gets it to their mouth — not every time.'},
  'dev_points': {AppLocale.ru: 'Показывает пальцем', AppLocale.kk: 'Саусағымен көрсетеді', AppLocale.en: 'Points'},
  'dev_points_note': {AppLocale.ru: 'Показывает на то, что хочет или что заметил. Важный шаг к речи.', AppLocale.kk: 'Қалағанын немесе байқағанын көрсетеді. Сөйлеуге маңызды қадам.', AppLocale.en: 'Points at what they want or have noticed. An important step toward speech.'},
  'dev_walks_well': {AppLocale.ru: 'Уверенно ходит', AppLocale.kk: 'Сенімді жүреді', AppLocale.en: 'Walks steadily'},
  'dev_walks_well_note': {AppLocale.ru: 'Ходит через комнату и почти не падает.', AppLocale.kk: 'Бөлмені кесіп өтеді, дерлік құламайды.', AppLocale.en: 'Crosses the room and rarely falls.'},
  'dev_molars': {AppLocale.ru: 'Коренные зубы', AppLocale.kk: 'Азу тістер', AppLocale.en: 'Molars'},
  'dev_molars_note': {AppLocale.ru: 'Часто самые тяжёлые дни прорезывания.', AppLocale.kk: 'Көбіне тіс шығудың ең ауыр күндері.', AppLocale.en: 'Often the hardest days of teething.'},
  'dev_several_words': {AppLocale.ru: 'Говорит несколько слов', AppLocale.kk: 'Бірнеше сөз айтады', AppLocale.en: 'Says several words'},
  'dev_several_words_note': {AppLocale.ru: 'Обычно 5–20 слов, которые понимает семья.', AppLocale.kk: 'Әдетте отбасы түсінетін 5–20 сөз.', AppLocale.en: 'Usually 5–20 words the family understands.'},
  'dev_runs': {AppLocale.ru: 'Бегает', AppLocale.kk: 'Жүгіреді', AppLocale.en: 'Runs'},
  'dev_runs_note': {AppLocale.ru: 'Ещё неуклюже, но уже быстрее вас.', AppLocale.kk: 'Әлі икемсіз, бірақ сізден жылдам.', AppLocale.en: 'Still wobbly, and already faster than you.'},
  'dev_two_word_phrases': {AppLocale.ru: 'Фразы из двух слов', AppLocale.kk: 'Екі сөзден тіркес', AppLocale.en: 'Two-word phrases'},
  'dev_two_word_phrases_note': {AppLocale.ru: '«мама дай», «пойдём гулять».', AppLocale.kk: '«мама бер», «серуенге барайық».', AppLocale.en: '“mama give”, “go out”.'},
  'dev_full_milk_teeth': {AppLocale.ru: 'Все молочные зубы', AppLocale.kk: 'Барлық сүт тістер', AppLocale.en: 'A full set of milk teeth'},
  'dev_full_milk_teeth_note': {AppLocale.ru: 'Обычно 20 зубов к 2,5–3 годам.', AppLocale.kk: 'Әдетте 2,5–3 жасқа қарай 20 тіс.', AppLocale.en: 'Usually all 20 by two and a half to three years.'},
  'dev_stairs': {AppLocale.ru: 'Поднимается по лестнице', AppLocale.kk: 'Баспалдақпен көтеріледі', AppLocale.en: 'Climbs stairs'},
  'dev_stairs_note': {AppLocale.ru: 'Держась за перила, приставным шагом.', AppLocale.kk: 'Тұтқадан ұстап, қосып басып.', AppLocale.en: 'Holding the rail, one step at a time.'},
  'log_title': {AppLocale.ru: 'Как вы себя чувствуете?', AppLocale.kk: 'Өзіңізді қалай сезінесіз?', AppLocale.en: 'How are you feeling?'},
  'log_mood': {AppLocale.ru: 'Настроение', AppLocale.kk: 'Көңіл-күй', AppLocale.en: 'Mood'},
  'log_symptoms': {AppLocale.ru: 'Симптомы', AppLocale.kk: 'Симптомдар', AppLocale.en: 'Symptoms'},
  // Screen 53's hero — §2.4. The caption, the white pill and the size line.
  'hero_week_trimester': {
    AppLocale.ru: '{w} неделя · {t}-й триместр',
    AppLocale.kk: '{w} апта · {t}-триместр',
    AppLocale.en: 'Week {w} · trimester {t}',
  },
  'hero_weeks_left': {
    AppLocale.ru: 'осталось {n} нед.',
    AppLocale.kk: '{n} апта қалды',
    AppLocale.en: '{n} weeks to go',
  },
  'hero_length': {AppLocale.ru: '{cm} см', AppLocale.kk: '{cm} см', AppLocale.en: '{cm} cm'},
  // Before week 4 no size comparison is honest, so the hero says the week.
  'hero_early': {
    AppLocale.ru: 'Самое начало пути',
    AppLocale.kk: 'Жолдың басы',
    AppLocale.en: 'The very beginning',
  },
  // The three quick actions under it.
  'qa_wellbeing': {AppLocale.ru: 'Самочувствие', AppLocale.kk: 'Көңіл күй', AppLocale.en: 'How you feel'},
  'qa_weight': {AppLocale.ru: 'Вес', AppLocale.kk: 'Салмақ', AppLocale.en: 'Weight'},
  'qa_logged_today': {AppLocale.ru: 'отмечено', AppLocale.kk: 'белгіленді', AppLocale.en: 'logged'},
  'qa_not_yet': {AppLocale.ru: 'ещё нет', AppLocale.kk: 'әлі жоқ', AppLocale.en: 'not yet'},
  'log_kicks': {AppLocale.ru: 'Счётчик шевелений', AppLocale.kk: 'Тебіну санауышы', AppLocale.en: 'Kick counter'},
  'log_note': {AppLocale.ru: 'Заметка', AppLocale.kk: 'Ескертпе', AppLocale.en: 'Note'},
  'log_note_hint': {AppLocale.ru: 'Как прошёл день?', AppLocale.kk: 'Күн қалай өтті?', AppLocale.en: 'How was your day?'},
  'mood_happy': {AppLocale.ru: 'Радость', AppLocale.kk: 'Қуаныш', AppLocale.en: 'Happy'},
  'mood_calm': {AppLocale.ru: 'Спокойствие', AppLocale.kk: 'Тыныштық', AppLocale.en: 'Calm'},
  'mood_anxious': {AppLocale.ru: 'Тревога', AppLocale.kk: 'Мазасыздық', AppLocale.en: 'Anxious'},
  'mood_tired': {AppLocale.ru: 'Усталость', AppLocale.kk: 'Шаршау', AppLocale.en: 'Tired'},
  'mood_sad': {AppLocale.ru: 'Грусть', AppLocale.kk: 'Мұң', AppLocale.en: 'Sad'},
  'sym_allGood': {AppLocale.ru: 'Всё хорошо', AppLocale.kk: 'Бәрі жақсы', AppLocale.en: 'All good'},
  'sym_cramps': {AppLocale.ru: 'Лёгкие спазмы', AppLocale.kk: 'Жеңіл құрысу', AppLocale.en: 'Mild cramps'},
  'sym_spotting': {AppLocale.ru: 'Мажущие выделения', AppLocale.kk: 'Дақ бөліну', AppLocale.en: 'Spotting'},
  'sym_headache': {AppLocale.ru: 'Головная боль', AppLocale.kk: 'Бас ауыруы', AppLocale.en: 'Headache'},
  'sym_nausea': {AppLocale.ru: 'Тошнота', AppLocale.kk: 'Жүрек айну', AppLocale.en: 'Nausea'},
  'sym_swelling': {AppLocale.ru: 'Отёки', AppLocale.kk: 'Ісіну', AppLocale.en: 'Swelling'},
  'kick_today': {AppLocale.ru: 'шевелений сегодня', AppLocale.kk: 'тебіну бүгін', AppLocale.en: 'kicks today'},
  'kick_add': {AppLocale.ru: 'Записать шевеление', AppLocale.kk: 'Тебінуді белгілеу', AppLocale.en: 'Log a kick'},
  'kick_reset': {AppLocale.ru: 'Сбросить', AppLocale.kk: 'Ысыру', AppLocale.en: 'Reset'},
  'kick_session_start': {AppLocale.ru: 'Сессия с таймером', AppLocale.kk: 'Таймермен сессия', AppLocale.en: 'Timed session'},
  'kick_session_title': {AppLocale.ru: 'Счёт шевелений', AppLocale.kk: 'Тебінуді санау', AppLocale.en: 'Kick session'},
  'kick_session_hint': {AppLocale.ru: 'Нажмите на круг при каждом шевелении. Таймер начнётся с первого.', AppLocale.kk: 'Әр тебінуде шеңберді басыңыз. Таймер алғашқысынан басталады.', AppLocale.en: 'Tap the circle for each movement. The timer starts on the first one.'},
  'kick_session_running': {AppLocale.ru: 'Сессия идёт', AppLocale.kk: 'Сессия жүріп жатыр', AppLocale.en: 'Session running'},
  'kick_session_tap': {AppLocale.ru: 'шевеление', AppLocale.kk: 'тебіну', AppLocale.en: 'movement'},
  'kick_session_undo': {AppLocale.ru: 'Отменить', AppLocale.kk: 'Болдырмау', AppLocale.en: 'Undo'},
  'kick_session_save': {AppLocale.ru: 'Сохранить сессию', AppLocale.kk: 'Сессияны сақтау', AppLocale.en: 'Save session'},
  'kick_session_close': {AppLocale.ru: 'Закрыть', AppLocale.kk: 'Жабу', AppLocale.en: 'Close'},
  'kick_session_saved': {AppLocale.ru: 'Записано шевелений: {n}', AppLocale.kk: 'Жазылған тебіну: {n}', AppLocale.en: 'Logged {n} movements'},
  'kick_session_discard_title': {AppLocale.ru: 'Прервать сессию?', AppLocale.kk: 'Сессияны тоқтату керек пе?', AppLocale.en: 'Discard this session?'},
  'kick_session_discard_body': {AppLocale.ru: 'Подсчитанные шевеления не сохранятся.', AppLocale.kk: 'Саналған тебінулер сақталмайды.', AppLocale.en: 'The movements you counted won\'t be saved.'},
  'kick_session_discard': {AppLocale.ru: 'Прервать', AppLocale.kk: 'Тоқтату', AppLocale.en: 'Discard'},
  'kick_goal_reached': {AppLocale.ru: 'Цель достигнута', AppLocale.kk: 'Мақсатқа жетті', AppLocale.en: 'Goal reached'},
  // Ten movements, but it took longer than the two hours the count-to-ten
  // method references. No confetti and no diagnosis — it states the fact and
  // defers to her provider, the same voice the 5-1-1 card uses.
  'kick_goal_reached_slow': {
    AppLocale.ru: '10 движений записано, но это заняло больше двух часов. '
        'Многие врачи просят сообщать, если шевеления кажутся реже обычного.',
    AppLocale.kk: '10 қозғалыс жазылды, бірақ бұл екі сағаттан асты. '
        'Көптеген дәрігерлер қозғалыс әдеттегіден сирек сезілсе, хабарлауды сұрайды.',
    AppLocale.en: '10 movements recorded, but it took over two hours. '
        'Many providers ask to be told if movements feel less frequent than usual.'
  },
  // Saved a session in which two hours passed WITHOUT ten movements — the
  // count-to-ten method's own trigger, and the case that used to save as
  // «Записано шевелений: 4» and nothing more. Stated as facts — her numbers,
  // then what the method looks for — with no verdict and no threshold the app
  // did not already have. Under it comes `kick_low_action` (what to do when
  // the count trigger is met) and `preg_note_movement_pattern` (the other
  // trigger: movements noticeably fewer than usual). The dialog's second
  // button opens the warning-signs screen (`preg_warn_title`), which lists
  // «Малыш шевелится заметно меньше обычного» and the ambulance number.
  //
  // The kk half says «қимыл» throughout, the same word as
  // `preg_note_movement_pattern`, `preg_warn_movement` and the week-27 card,
  // so the number and the reference are comparable the way they are in ru.
  'kick_low_title': {
    AppLocale.ru: 'Обратите внимание на шевеления',
    AppLocale.kk: 'Қимылдарға назар аударыңыз',
    AppLocale.en: 'Take note of the movements',
  },
  'kick_low_body': {
    AppLocale.ru: 'Записано шевелений: {n}, время: {t}. '
        'Метод «считай до десяти» ориентируется на десять шевелений примерно за два часа.',
    AppLocale.kk: 'Жазылған қимыл: {n}, уақыты: {t}. '
        '«Онға дейін сана» әдісі шамамен екі сағатта он қимылға негізделген.',
    AppLocale.en: 'Logged {n} movements in {t}. '
        'The count-to-ten method looks for ten movements in about two hours.',
  },
  // The action the method attaches to its own threshold. Without it the app
  // taught the numbers and stopped: a mother who counted six in two hours had
  // met the trigger for calling and was told nothing about it, because
  // `preg_note_movement_pattern` covers only the subjective «меньше обычного».
  'kick_low_action': {
    AppLocale.ru: 'Если за два часа вы не насчитали десяти шевелений — '
        'свяжитесь с консультацией сегодня, не ждите до завтра.',
    AppLocale.kk: 'Екі сағат ішінде он қимыл санамасаңыз — '
        'бүгін консультацияға хабарласыңыз, ертеңге қалдырмаңыз.',
    AppLocale.en: 'If you have not counted ten movements in two hours, '
        'contact your clinic today — do not wait until tomorrow.',
  },
  // Shown beside the save confirmation when the session ended BEFORE the two
  // hours with fewer than ten movements. The method has given no signal there,
  // so this states what it looks for and stops: no verdict, no clinic
  // instruction, no route to the warning signs.
  'kick_method_note': {
    AppLocale.ru: 'Метод «считай до десяти» ориентируется на десять шевелений примерно за два часа.',
    AppLocale.kk: '«Онға дейін сана» әдісі шамамен екі сағатта он қимылға негізделген.',
    AppLocale.en: 'The count-to-ten method looks for ten movements in about two hours.',
  },
  'kick_history': {AppLocale.ru: 'История сессий', AppLocale.kk: 'Сессиялар тарихы', AppLocale.en: 'Session history'},
  'kick_avg_count': {AppLocale.ru: 'Ср. шевелений', AppLocale.kk: 'Орт. тебіну', AppLocale.en: 'Avg movements'},
  'kick_avg_length': {AppLocale.ru: 'Ср. длительность', AppLocale.kk: 'Орт. ұзақтық', AppLocale.en: 'Avg length'},
  'kick_goal_hits': {AppLocale.ru: 'Цель достигнута', AppLocale.kk: 'Мақсатқа жетті', AppLocale.en: 'Goals met'},
  'kick_history_count': {AppLocale.ru: '{n} шевелений', AppLocale.kk: '{n} тебіну', AppLocale.en: '{n} movements'},
  'cal_tooltip': {
    AppLocale.ru: 'Калибруйте по медицинскому тонометру еженедельно для точной оценки давления по браслету.',
    AppLocale.kk: 'Дәл өлшеу үшін білезік қысымын апта сайын медициналық тонометрмен калибрлеңіз.',
    AppLocale.en: 'Calibrate with a medical tonometer weekly for precise smart-band mapping.'
  },

  // Destructive-action confirmations
  'confirm_remove_child_title': {AppLocale.ru: 'Удалить ребёнка?', AppLocale.kk: 'Баланы жою керек пе?', AppLocale.en: 'Remove child?'},
  'confirm_remove_child_body': {
    AppLocale.ru: '«{name}» и связанные с ним устройства будут удалены. Это действие нельзя отменить.',
    AppLocale.kk: '«{name}» және онымен байланысты құрылғылар жойылады. Бұл әрекетті қайтару мүмкін емес.',
    AppLocale.en: "{name} and any linked devices will be removed. This can't be undone."
  },
  'confirm_remove_device_title': {AppLocale.ru: 'Удалить устройство?', AppLocale.kk: 'Құрылғыны жою керек пе?', AppLocale.en: 'Remove device?'},
  'confirm_remove_device_body': {
    AppLocale.ru: '«{name}» будет отвязано и удалено.',
    AppLocale.kk: '«{name}» ажыратылып, жойылады.',
    AppLocale.en: '{name} will be unpaired and removed.'
  },
  'confirm_reset_kicks_title': {AppLocale.ru: 'Сбросить счётчик?', AppLocale.kk: 'Санауышты ысыру керек пе?', AppLocale.en: 'Reset kick count?'},
  'confirm_reset_kicks_body': {
    AppLocale.ru: 'Счётчик шевелений за этот день обнулится.',
    AppLocale.kk: 'Осы күнгі тебіну саны нөлге түседі.',
    AppLocale.en: 'The kick count for this day will be reset to zero.'
  },

  // Contraction timer (pregnancy)
  'contr_title': {AppLocale.ru: 'Схватки', AppLocale.kk: 'Толғақ', AppLocale.en: 'Contractions'},
  'contr_start': {AppLocale.ru: 'Начать', AppLocale.kk: 'Бастау', AppLocale.en: 'Start'},
  'contr_stop': {AppLocale.ru: 'Стоп', AppLocale.kk: 'Тоқтату', AppLocale.en: 'Stop'},
  'contr_hint': {AppLocale.ru: 'Нажмите, когда схватка началась.', AppLocale.kk: 'Толғақ басталғанда басыңыз.', AppLocale.en: 'Tap when a contraction begins.'},
  'contr_running': {AppLocale.ru: 'Схватка идёт — нажмите в конце.', AppLocale.kk: 'Толғақ жүріп жатыр — соңында басыңыз.', AppLocale.en: 'Contraction in progress — tap when it ends.'},
  'contr_empty': {AppLocale.ru: 'Схватки пока не записаны.', AppLocale.kk: 'Толғақ әлі жазылмаған.', AppLocale.en: 'No contractions recorded yet.'},
  'contr_count': {AppLocale.ru: 'Всего', AppLocale.kk: 'Барлығы', AppLocale.en: 'Total'},
  'contr_avg_dur': {AppLocale.ru: 'Ср. длит.', AppLocale.kk: 'Орт. ұзақтығы', AppLocale.en: 'Avg length'},
  'contr_avg_freq': {AppLocale.ru: 'Ср. интервал', AppLocale.kk: 'Орт. аралық', AppLocale.en: 'Avg interval'},
  'contr_duration': {AppLocale.ru: 'Длительность {d}', AppLocale.kk: 'Ұзақтығы {d}', AppLocale.en: 'Lasted {d}'},
  'contr_apart': {AppLocale.ru: 'через {i}', AppLocale.kk: '{i} кейін', AppLocale.en: '{i} apart'},
  'contr_511_title': {AppLocale.ru: 'Схема 5-1-1', AppLocale.kk: '5-1-1 үлгісі', AppLocale.en: '5-1-1 pattern'},
  'contr_511_interval': {AppLocale.ru: 'Интервал около 5 минут', AppLocale.kk: 'Аралығы шамамен 5 минут', AppLocale.en: 'About 5 minutes apart'},
  'contr_511_duration': {AppLocale.ru: 'Длятся около 1 минуты', AppLocale.kk: 'Ұзақтығы шамамен 1 минут', AppLocale.en: 'Each lasting about 1 minute'},
  'contr_511_sustained': {AppLocale.ru: 'Держится не менее 1 часа', AppLocale.kk: 'Кемінде 1 сағат сақталады', AppLocale.en: 'Sustained for at least 1 hour'},
  'contr_511_note': {AppLocale.ru: 'Справочная схема из курсов подготовки к родам — не медицинский совет. Всегда следуйте рекомендациям своего врача.', AppLocale.kk: 'Босануға дайындық курстарынан анықтамалық үлгі — медициналық кеңес емес. Әрдайым дәрігеріңіздің нұсқауын ұстаныңыз.', AppLocale.en: 'A reference pattern from childbirth classes — not medical advice. Always follow your provider\'s guidance.'},
  'contr_511_ready': {AppLocale.ru: 'Схема 5-1-1 соблюдается. Многие врачи советуют связаться с ними на этом этапе — следуйте своему плану родов.', AppLocale.kk: '5-1-1 үлгісі орындалды. Көптеген дәрігерлер осы кезеңде хабарласуды ұсынады — босану жоспарыңызды ұстаныңыз.', AppLocale.en: 'The 5-1-1 pattern is met. Many providers suggest contacting them around now — follow your birth plan.'},
  'contr_first': {AppLocale.ru: 'первая', AppLocale.kk: 'бірінші', AppLocale.en: 'first'},
  'contr_reset': {AppLocale.ru: 'Сбросить', AppLocale.kk: 'Ысыру', AppLocale.en: 'Reset'},
  'contr_reset_title': {AppLocale.ru: 'Сбросить схватки?', AppLocale.kk: 'Толғақтарды ысыру керек пе?', AppLocale.en: 'Reset contractions?'},
  'contr_reset_body': {AppLocale.ru: 'Записанные схватки будут удалены.', AppLocale.kk: 'Жазылған толғақтар жойылады.', AppLocale.en: 'The recorded contractions will be cleared.'},
  'contr_history': {AppLocale.ru: 'История схваток', AppLocale.kk: 'Толғақтар тарихы', AppLocale.en: 'Contraction history'},
  'contr_history_count': {AppLocale.ru: '{n} схваток', AppLocale.kk: '{n} толғақ', AppLocale.en: '{n} contractions'},
  'contr_history_interval': {AppLocale.ru: 'интервал {i}', AppLocale.kk: 'аралығы {i}', AppLocale.en: '{i} apart'},
  'contr_history_clear_title': {AppLocale.ru: 'Очистить историю схваток?', AppLocale.kk: 'Толғақтар тарихын тазалау керек пе?', AppLocale.en: 'Clear contraction history?'},
  'hist_clear': {AppLocale.ru: 'Очистить', AppLocale.kk: 'Тазалау', AppLocale.en: 'Clear'},
  'hist_see_all': {AppLocale.ru: 'Показать все ({n})', AppLocale.kk: 'Барлығын көрсету ({n})', AppLocale.en: 'See all ({n})'},
  'hist_clear_body': {AppLocale.ru: 'Записи истории будут удалены.', AppLocale.kk: 'Тарих жазбалары жойылады.', AppLocale.en: 'The history entries will be removed.'},
  'kick_history_clear_title': {AppLocale.ru: 'Очистить историю сессий?', AppLocale.kk: 'Сессиялар тарихын тазалау керек пе?', AppLocale.en: 'Clear session history?'},

  // Weight (pregnancy)
  'weight_title': {AppLocale.ru: 'Вес', AppLocale.kk: 'Салмақ', AppLocale.en: 'Weight'},
  'weight_log': {AppLocale.ru: 'Записать', AppLocale.kk: 'Жазу', AppLocale.en: 'Log weight'},
  'weight_log_title': {AppLocale.ru: 'Ваш вес сегодня', AppLocale.kk: 'Бүгінгі салмағыңыз', AppLocale.en: 'Your weight today'},
  'weight_empty': {AppLocale.ru: 'Запишите вес, чтобы видеть динамику.', AppLocale.kk: 'Динамиканы көру үшін салмақты жазыңыз.', AppLocale.en: 'Log your weight to see the trend.'},
  'weight_delta': {AppLocale.ru: '{sign}{kg} кг с начала', AppLocale.kk: 'басынан {sign}{kg} кг', AppLocale.en: '{sign}{kg} kg since start'},
  'weight_rate': {AppLocale.ru: 'В среднем {sign}{kg} кг/нед. за {weeks} нед.', AppLocale.kk: 'Орташа {sign}{kg} кг/апта, {weeks} апта', AppLocale.en: 'Averaging {sign}{kg} kg/week over {weeks} wks'},
  'weight_set_target': {AppLocale.ru: '+ Задать цель веса', AppLocale.kk: '+ Салмақ мақсатын қою', AppLocale.en: '+ Set a weight target'},
  'weight_target_title': {AppLocale.ru: 'Целевой вес', AppLocale.kk: 'Мақсатты салмақ', AppLocale.en: 'Target weight'},
  'weight_target_to_go': {AppLocale.ru: 'Цель {target} кг · осталось {kg} кг', AppLocale.kk: 'Мақсат {target} кг · {kg} кг қалды', AppLocale.en: 'Target {target} kg · {kg} kg to go'},
  'weight_target_reached': {AppLocale.ru: 'Цель достигнута', AppLocale.kk: 'Мақсатқа жетті', AppLocale.en: 'Target reached'},
  'weight_target_clear': {AppLocale.ru: 'Убрать цель', AppLocale.kk: 'Мақсатты жою', AppLocale.en: 'Clear target'},
  'weight_history_title': {AppLocale.ru: 'История веса', AppLocale.kk: 'Салмақ тарихы', AppLocale.en: 'Weight history'},
  'weight_delete_title': {AppLocale.ru: 'Удалить запись?', AppLocale.kk: 'Жазбаны жою керек пе?', AppLocale.en: 'Delete this entry?'},
  'weight_delete_body': {AppLocale.ru: 'Запись {kg} кг будет удалена.', AppLocale.kk: '{kg} кг жазбасы жойылады.', AppLocale.en: 'The {kg} kg entry will be removed.'},

  // Hydration (daily water)
  'water_title': {AppLocale.ru: 'Вода', AppLocale.kk: 'Су', AppLocale.en: 'Water'},
  'water_progress': {AppLocale.ru: '{n} из {goal} стаканов', AppLocale.kk: '{goal} стақаннан {n}', AppLocale.en: '{n} of {goal} glasses'},
  'water_goal_met': {AppLocale.ru: 'Дневная норма выполнена', AppLocale.kk: 'Күнделікті норма орындалды', AppLocale.en: 'Daily goal reached'},
  'water_correct': {AppLocale.ru: 'Исправить день', AppLocale.kk: 'Күнді түзету', AppLocale.en: 'Correct a day'},
  'water_add': {AppLocale.ru: 'Добавить стакан', AppLocale.kk: 'Стақан қосу', AppLocale.en: 'Add a glass'},
  'water_remove': {AppLocale.ru: 'Убрать стакан', AppLocale.kk: 'Стақанды алу', AppLocale.en: 'Remove a glass'},
  'water_goal_title': {AppLocale.ru: 'Дневная норма воды', AppLocale.kk: 'Күнделікті су нормасы', AppLocale.en: 'Daily water goal'},
  'water_goal_hint': {AppLocale.ru: 'Сколько стаканов в день — ваша цель.', AppLocale.kk: 'Күніне неше стақан — сіздің мақсатыңыз.', AppLocale.en: 'How many glasses a day you aim for.'},
  'water_reminder': {AppLocale.ru: 'Напоминание о воде', AppLocale.kk: 'Су туралы еске салу', AppLocale.en: 'Daily water reminder'},
  'water_reminder_off': {AppLocale.ru: 'Выключено', AppLocale.kk: 'Өшірулі', AppLocale.en: 'Off'},
  'water_reminder_at': {AppLocale.ru: 'Каждый день в {time}', AppLocale.kk: 'Күн сайын {time}', AppLocale.en: 'Every day at {time}'},
  'rem_title': {AppLocale.ru: 'Напоминания', AppLocale.kk: 'Еске салулар', AppLocale.en: 'Reminders'},
  'rem_active': {AppLocale.ru: 'Активно: {n}', AppLocale.kk: 'Белсенді: {n}', AppLocale.en: '{n} active'},
  'rem_needs_cycle': {AppLocale.ru: 'Нужны данные цикла, чтобы запланировать', AppLocale.kk: 'Жоспарлау үшін цикл деректері қажет', AppLocale.en: 'Needs cycle data to schedule'},
  'rem_needs_meds': {AppLocale.ru: 'Сначала добавьте витамины или лекарства', AppLocale.kk: 'Алдымен дәрумен немесе дәрі қосыңыз', AppLocale.en: 'Add a vitamin or medicine first'},
  'med_reminder': {AppLocale.ru: 'Напоминание о приёме', AppLocale.kk: 'Қабылдау туралы еске салу', AppLocale.en: 'Medication reminder'},
  'med_reminder_off': {AppLocale.ru: 'Выключено', AppLocale.kk: 'Өшірулі', AppLocale.en: 'Off'},
  'med_reminder_at': {AppLocale.ru: 'Каждый день в {time}', AppLocale.kk: 'Күн сайын {time}', AppLocale.en: 'Every day at {time}'},
  'med_reminder_title': {AppLocale.ru: 'Время принять витамины', AppLocale.kk: 'Дәрумен қабылдау уақыты', AppLocale.en: 'Time for your vitamins'},
  'med_reminder_body': {AppLocale.ru: 'Отметьте сегодняшние приёмы в Ana-Bala.', AppLocale.kk: 'Бүгінгі қабылдауды Ana-Bala-да белгілеңіз.', AppLocale.en: 'Tick off today\'s doses in Ana-Bala.'},
  'rem_footer': {AppLocale.ru: 'Напоминания приходят как обычные уведомления. Их можно отключить в любой момент здесь.', AppLocale.kk: 'Еске салулар қарапайым хабарландыру ретінде келеді. Оларды кез келген уақытта осы жерде өшіруге болады.', AppLocale.en: 'Reminders arrive as ordinary notifications. You can turn any of them off here at any time.'},
  // Safety-notification categories + quiet hours (notif_*).
  'notif_safety_section': {AppLocale.ru: 'Уведомления безопасности', AppLocale.kk: 'Қауіпсіздік хабарламалары', AppLocale.en: 'Safety notifications'},
  'notif_zone': {AppLocale.ru: 'Вход и выход из зон', AppLocale.kk: 'Аймаққа кіру және шығу', AppLocale.en: 'Zone entry & exit'},
  'notif_zone_sub': {AppLocale.ru: 'Когда ребёнок входит в зону или выходит из неё', AppLocale.kk: 'Бала аймаққа кірген немесе шыққан кезде', AppLocale.en: 'When your child enters or leaves a zone'},
  'notif_checkin': {AppLocale.ru: 'Отметки «я на месте»', AppLocale.kk: '«Мен жеттім» белгілері', AppLocale.en: 'Check-ins'},
  'notif_checkin_sub': {AppLocale.ru: 'Когда ребёнок отмечает, что всё хорошо', AppLocale.kk: 'Бала бәрі жақсы екенін белгілегенде', AppLocale.en: 'When your child marks they’ve arrived safely'},
  'notif_lowbattery': {AppLocale.ru: 'Низкий заряд трекера', AppLocale.kk: 'Трекер заряды төмен', AppLocale.en: 'Tracker low battery'},
  'notif_lowbattery_sub': {AppLocale.ru: 'Когда у трекера садится батарея', AppLocale.kk: 'Трекердің батареясы отырғанда', AppLocale.en: 'When the tracker battery is running low'},
  // Рассылки и ответы поддержки — то, что говорит продукт, а не трекер ребёнка.
  // Отдельный переключатель: выключив объявления, она не должна выключить
  // «ребёнок на месте».
  'notif_updates': {AppLocale.ru: 'Новости и ответы', AppLocale.kk: 'Жаңалықтар мен жауаптар', AppLocale.en: 'News and replies'},
  'notif_updates_sub': {AppLocale.ru: 'Сообщения от Ana-Bala и ответы поддержки', AppLocale.kk: 'Ana-Bala хабарламалары және қолдау жауаптары', AppLocale.en: 'Messages from Ana-Bala and support replies'},
  'notif_quiet': {AppLocale.ru: 'Тихие часы', AppLocale.kk: 'Тыныш сағаттар', AppLocale.en: 'Quiet hours'},
  'notif_quiet_off': {AppLocale.ru: 'Не заданы', AppLocale.kk: 'Орнатылмаған', AppLocale.en: 'Not set'},
  'notif_quiet_at': {AppLocale.ru: 'С {from} до {to}', AppLocale.kk: '{from} — {to}', AppLocale.en: '{from} to {to}'},
  'notif_quiet_from': {AppLocale.ru: 'Начало тихих часов', AppLocale.kk: 'Тыныш сағаттардың басы', AppLocale.en: 'Quiet hours start'},
  'notif_quiet_to': {AppLocale.ru: 'Конец тихих часов', AppLocale.kk: 'Тыныш сағаттардың соңы', AppLocale.en: 'Quiet hours end'},
  'notif_sos_note': {AppLocale.ru: 'Сигналы SOS и экстренные оповещения приходят всегда — их нельзя отключить и они не молчат в тихие часы.', AppLocale.kk: 'SOS және шұғыл дабылдар әрқашан келеді — оларды өшіру мүмкін емес және тыныш сағаттарда да үнсіз қалмайды.', AppLocale.en: 'SOS and emergency alerts always come through — they can’t be turned off and are never held during quiet hours.'},
  // «›» not «→»: U+2192 is absent from Rubik.ttf, the only Kazakh-capable
  // family bundled, so the arrow is a box for the one reader who needs the
  // path. English already used «›» here; Kazakh now matches.
  'rem_manage_hint': {AppLocale.ru: 'Напоминания о цикле — в разделе «Настройки → Напоминания».', AppLocale.kk: 'Цикл еске салулары «Параметрлер › Еске салулар» бөлімінде.', AppLocale.en: 'Manage cycle reminders in Settings › Reminders.'},
  'water_reminder_title': {AppLocale.ru: 'Время попить воды', AppLocale.kk: 'Су ішу уақыты', AppLocale.en: 'Time to drink water'},
  'water_reminder_body': {AppLocale.ru: 'Не забывайте про водный баланс сегодня.', AppLocale.kk: 'Бүгін су балансын ұмытпаңыз.', AppLocale.en: "Keep up your hydration goal today."},
  'water_week_title': {AppLocale.ru: 'Вода за неделю', AppLocale.kk: 'Апталық су', AppLocale.en: 'Water this week'},
  'water_week_bars': {AppLocale.ru: 'Последние 7 дней', AppLocale.kk: 'Соңғы 7 күн', AppLocale.en: 'Last 7 days'},
  'water_week_total': {AppLocale.ru: 'Всего стаканов', AppLocale.kk: 'Барлық стақан', AppLocale.en: 'Total glasses'},
  'water_week_met': {AppLocale.ru: 'Дней с нормой', AppLocale.kk: 'Норма күндері', AppLocale.en: 'Goal days'},
  'water_streak': {AppLocale.ru: 'Серия: {n} дн.', AppLocale.kk: 'Серия: {n} күн', AppLocale.en: '{n}-day streak'},
  'water_streak_none': {AppLocale.ru: 'Пока без серии', AppLocale.kk: 'Әзірге серия жоқ', AppLocale.en: 'No streak yet'},
  'water_streak_sub': {AppLocale.ru: 'Дней подряд с выполненной нормой', AppLocale.kk: 'Норма орындалған қатарынан күндер', AppLocale.en: 'Consecutive days you hit your goal'},

  // Child date of birth + age
  'child_gender': {AppLocale.ru: 'Пол', AppLocale.kk: 'Жынысы', AppLocale.en: 'Gender'},
  'gender_boy': {AppLocale.ru: 'Мальчик', AppLocale.kk: 'Ұл', AppLocale.en: 'Boy'},
  'gender_girl': {AppLocale.ru: 'Девочка', AppLocale.kk: 'Қыз', AppLocale.en: 'Girl'},
  'child_dob_hint': {AppLocale.ru: 'Дата рождения', AppLocale.kk: 'Туған күні', AppLocale.en: 'Date of birth'},
  'child_dob_help': {AppLocale.ru: 'Помогает персонализировать советы по возрасту', AppLocale.kk: 'Жасына қарай кеңестерді жекелендіруге көмектеседі', AppLocale.en: 'Helps personalize tips by age'},
  'age_years': {AppLocale.ru: '{n} г.', AppLocale.kk: '{n} жас', AppLocale.en: '{n} yrs'},
  'age_year_months': {AppLocale.ru: '{y} г. {m} мес.', AppLocale.kk: '{y} жыл {m} ай', AppLocale.en: '{y}y {m}m'},
  'age_months': {AppLocale.ru: '{n} мес.', AppLocale.kk: '{n} ай', AppLocale.en: '{n} mo'},
  'age_newborn': {AppLocale.ru: 'Новорождённый', AppLocale.kk: 'Жаңа туған', AppLocale.en: 'Newborn'},

  // Sleep
  'metric_sleep': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
  'sleep_last_night': {AppLocale.ru: 'Прошлой ночью', AppLocale.kk: 'Өткен түні', AppLocale.en: 'Last night'},
  'sleep_week_avg': {AppLocale.ru: 'В среднем за неделю: {dur}', AppLocale.kk: 'Апталық орташа: {dur}', AppLocale.en: '{dur} average this week'},
  'sleep_recent_nights': {AppLocale.ru: 'Последние ночи', AppLocale.kk: 'Соңғы түндер', AppLocale.en: 'Recent nights'},
  'sleep_deep': {AppLocale.ru: 'Глубокий', AppLocale.kk: 'Терең', AppLocale.en: 'Deep'},
  'sleep_rem': {AppLocale.ru: 'Быстрый', AppLocale.kk: 'REM', AppLocale.en: 'REM'},
  'sleep_light': {AppLocale.ru: 'Лёгкий', AppLocale.kk: 'Жеңіл', AppLocale.en: 'Light'},
  'sleep_awake': {AppLocale.ru: 'Бодрствование', AppLocale.kk: 'Ояу', AppLocale.en: 'Awake'},
  'sleep_efficiency': {AppLocale.ru: 'Эффективность', AppLocale.kk: 'Тиімділік', AppLocale.en: 'Efficiency'},
  'sleep_avg': {AppLocale.ru: 'В среднем за {n} ноч.', AppLocale.kk: '{n} түн орташа', AppLocale.en: 'Avg over {n} nights'},
  'sleep_title': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
  'sleep_cons_good': {AppLocale.ru: 'Сон стабильный', AppLocale.kk: 'Ұйқы тұрақты', AppLocale.en: 'Your sleep is consistent'},
  'sleep_cons_variable': {AppLocale.ru: 'Длительность сна колеблется', AppLocale.kk: 'Ұйқы ұзақтығы құбылады', AppLocale.en: 'Your sleep length varies'},
  'sleep_cons_irregular': {AppLocale.ru: 'Сон нерегулярный', AppLocale.kk: 'Ұйқы тұрақсыз', AppLocale.en: 'Your sleep is irregular'},
  'sleep_cons_sub': {AppLocale.ru: 'Разброс длительности {spread}', AppLocale.kk: 'Ұзақтық айырмасы {spread}', AppLocale.en: '{spread} spread between nights'},
  'sleep_empty': {AppLocale.ru: 'Данные о сне появятся после ночи с браслетом.', AppLocale.kk: 'Ұйқы деректері білезікпен өткен түннен кейін пайда болады.', AppLocale.en: 'Sleep data appears after a night with your band.'},
  'sleep_quality_good': {AppLocale.ru: 'Хороший сон', AppLocale.kk: 'Жақсы ұйқы', AppLocale.en: 'Good sleep'},
  'sleep_quality_fair': {AppLocale.ru: 'Средний сон', AppLocale.kk: 'Орташа ұйқы', AppLocale.en: 'Fair sleep'},
  'sleep_quality_poor': {AppLocale.ru: 'Мало сна', AppLocale.kk: 'Аз ұйқы', AppLocale.en: 'Poor sleep'},
  'dur_hm': {AppLocale.ru: '{h} ч {m} мин', AppLocale.kk: '{h} сағ {m} мин', AppLocale.en: '{h}h {m}m'},
  'dur_h': {AppLocale.ru: '{h} ч', AppLocale.kk: '{h} сағ', AppLocale.en: '{h}h'},
  'dur_m': {AppLocale.ru: '{m} мин', AppLocale.kk: '{m} мин', AppLocale.en: '{m}m'},
  'ADV_SLEEP_SHORT': {AppLocale.ru: 'Недосып', AppLocale.kk: 'Ұйқы жетіспеді', AppLocale.en: 'Short on sleep'},
  'ADV_SLEEP_SHORT_b': {AppLocale.ru: 'Прошлой ночью вы спали меньше 6 часов. Постарайтесь отдохнуть днём.', AppLocale.kk: 'Өткен түні 6 сағаттан аз ұйықтадыңыз. Күндіз демалуға тырысыңыз.', AppLocale.en: 'You slept under 6 hours last night. Try to rest during the day.'},
  'ADV_SLEEP_DEBT': {AppLocale.ru: 'Несколько коротких ночей', AppLocale.kk: 'Бірнеше қысқа түн', AppLocale.en: 'Several short nights'},
  'ADV_SLEEP_DEBT_b': {AppLocale.ru: 'Три ночи подряд вы спали мало. Во время беременности отдых особенно важен — по возможности планируйте ранний отход ко сну и дневной отдых.', AppLocale.kk: 'Қатарынан үш түн аз ұйықтадыңыз. Жүктілік кезінде демалу аса маңызды — мүмкіндігінше ерте жатып, күндіз демалыңыз.', AppLocale.en: 'You’ve slept little three nights running. Rest matters especially in pregnancy — try an earlier bedtime and a daytime rest when you can.'},
  'ADV_SLEEP_GOOD': {AppLocale.ru: 'Хороший сон', AppLocale.kk: 'Жақсы ұйқы', AppLocale.en: 'Good sleep'},
  'ADV_SLEEP_GOOD_b': {AppLocale.ru: 'Прошлой ночью вы хорошо выспались с достаточным глубоким сном.', AppLocale.kk: 'Өткен түні терең ұйқымен жақсы дем алдыңыз.', AppLocale.en: 'You slept well last night with enough deep sleep.'},

  // Menstrual cycle / period tracking
  'log_period': {AppLocale.ru: 'Менструация', AppLocale.kk: 'Етеккір', AppLocale.en: 'Period'},
  'cyc_log_period': {AppLocale.ru: 'Отметить месячные', AppLocale.kk: 'Етеккірді белгілеу', AppLocale.en: 'Log period'},
  'cyc_period_logged': {AppLocale.ru: 'Отмечено сегодня', AppLocale.kk: 'Бүгін белгіленді', AppLocale.en: 'Logged today'},
  'cyc_period_logged_toast': {AppLocale.ru: 'Месячные отмечены на сегодня', AppLocale.kk: 'Бүгінге етеккір белгіленді', AppLocale.en: 'Period logged for today'},
  'flow_light': {AppLocale.ru: 'Слабые', AppLocale.kk: 'Әлсіз', AppLocale.en: 'Light'},
  'flow_medium': {AppLocale.ru: 'Умеренные', AppLocale.kk: 'Орташа', AppLocale.en: 'Medium'},
  'flow_heavy': {AppLocale.ru: 'Обильные', AppLocale.kk: 'Күшті', AppLocale.en: 'Heavy'},
  'cyc_period': {AppLocale.ru: 'Месячные', AppLocale.kk: 'Етеккір', AppLocale.en: 'Period'},
  'cyc_predicted': {AppLocale.ru: 'Прогноз', AppLocale.kk: 'Болжам', AppLocale.en: 'Predicted'},
  'cyc_fertile': {AppLocale.ru: 'Фертильные', AppLocale.kk: 'Құнарлы', AppLocale.en: 'Fertile'},
  'cyc_ovulation': {AppLocale.ru: 'Овуляция', AppLocale.kk: 'Овуляция', AppLocale.en: 'Ovulation'},
  'cyc_day_short': {AppLocale.ru: 'день', AppLocale.kk: 'күн', AppLocale.en: 'day'},
  'cyc_period_in': {AppLocale.ru: 'Месячные через {n} дн.', AppLocale.kk: 'Етеккірге {n} күн', AppLocale.en: 'Period in {n} days'},
  'cyc_period_today': {AppLocale.ru: 'Месячные ожидаются сегодня', AppLocale.kk: 'Бүгін етеккір күтіледі', AppLocale.en: 'Period expected today'},
  'cyc_period_late': {AppLocale.ru: 'Задержка {n} дн.', AppLocale.kk: '{n} күн кешігу', AppLocale.en: '{n} days late'},
  // Screen 55's cycle hero and its «Что дальше» routers.
  // «Тест положительный» asks for the date she knows — the last period — and
  // derives the due date from it.
  'preg_lmp_help': {
    AppLocale.ru: 'Первый день последних месячных',
    AppLocale.kk: 'Соңғы етеккірдің бірінші күні',
    AppLocale.en: 'First day of your last period',
  },
  'preg_started': {
    AppLocale.ru: 'Поздравляем! Календарь теперь показывает беременность.',
    AppLocale.kk: 'Құттықтаймыз! Күнтізбе енді жүктілікті көрсетеді.',
    AppLocale.en: 'Congratulations! The calendar now follows your pregnancy.',
  },
  // Screen 54's home block.
  'childhero_age': {AppLocale.ru: '{name} · {n} мес.', AppLocale.kk: '{name} · {n} ай', AppLocale.en: '{name} · {n} months'},
  'childhero_growing': {AppLocale.ru: 'Растёт по-своему', AppLocale.kk: 'Өзінше өсуде', AppLocale.en: 'Growing her own way'},
  'childhero_weight': {AppLocale.ru: 'Вес {kg} кг', AppLocale.kk: 'Салмағы {kg} кг', AppLocale.en: 'Weight {kg} kg'},
  // «растёт по своему коридору» — her against herself, which is the comparison
  // this app can stand behind. See child_hero.dart on why not WHO percentiles.
  'childhero_own_corridor': {
    AppLocale.ru: 'Растёт по своему коридору',
    AppLocale.kk: 'Өз дәлізімен өсуде',
    AppLocale.en: 'Growing along her own corridor',
  },
  'childhero_gained': {
    AppLocale.ru: '+{g} г за {d} дн. · свой коридор',
    AppLocale.kk: '{d} күнде +{g} г · өз дәлізі',
    AppLocale.en: '+{g} g in {d} days · her own corridor',
  },
  'cyc_day_n': {AppLocale.ru: 'День цикла {n}', AppLocale.kk: 'Цикл күні {n}', AppLocale.en: 'Cycle day {n}'},
  'cyc_ovulation_today': {AppLocale.ru: 'Овуляция сегодня', AppLocale.kk: 'Бүгін овуляция', AppLocale.en: 'Ovulation today'},
  'cyc_band_follicular': {AppLocale.ru: 'Спокойные дни', AppLocale.kk: 'Тыныш күндер', AppLocale.en: 'Quiet days'},
  'cyc_band_luteal': {AppLocale.ru: 'Вторая половина цикла', AppLocale.kk: 'Циклдің екінші жартысы', AppLocale.en: 'Second half of the cycle'},
  // The accuracy claim in words. The app has no percentage to show and will not
  // invent one — see cycle_hero.dart.
  'cyc_forecast_is': {AppLocale.ru: 'прогноз: {v}', AppLocale.kk: 'болжам: {v}', AppLocale.en: 'forecast: {v}'},
  'whatnext_title': {AppLocale.ru: 'Что дальше', AppLocale.kk: 'Әрі қарай не', AppLocale.en: 'What next'},
  'whatnext_planning': {AppLocale.ru: 'Планирую беременность', AppLocale.kk: 'Жүктілікті жоспарлаймын', AppLocale.en: 'Planning a pregnancy'},
  'whatnext_pregnant': {AppLocale.ru: 'Тест положительный — я беременна', AppLocale.kk: 'Тест оң — мен жүктімін', AppLocale.en: 'The test is positive — I am pregnant'},
  'whatnext_haschild': {AppLocale.ru: 'У меня уже есть ребёнок', AppLocale.kk: 'Менде бала бар', AppLocale.en: 'I already have a child'},
  'cyc_phase_period': {AppLocale.ru: 'Менструация', AppLocale.kk: 'Етеккір', AppLocale.en: 'Period'},
  'cyc_phase_fertile': {AppLocale.ru: 'Фертильное окно', AppLocale.kk: 'Құнарлы кезең', AppLocale.en: 'Fertile window'},
  'cyc_phase_ovulation': {AppLocale.ru: 'Овуляция', AppLocale.kk: 'Овуляция', AppLocale.en: 'Ovulation'},
  'cyc_predictions': {AppLocale.ru: 'Прогнозы', AppLocale.kk: 'Болжамдар', AppLocale.en: 'Predictions'},
  'cyc_usual_title': {AppLocale.ru: 'Обычно в это время вы отмечаете', AppLocale.kk: 'Әдетте осы кезде белгілейсіз', AppLocale.en: 'Around now you often log'},
  'cyc_conf_low': {AppLocale.ru: 'мало данных', AppLocale.kk: 'дерек аз', AppLocale.en: 'low data'},
  'cyc_conf_building': {AppLocale.ru: 'уточняется', AppLocale.kk: 'нақтылануда', AppLocale.en: 'building'},
  // Not "уточняется" — that promises the estimate will sharpen with more
  // logging, and for cycles that genuinely vary it never will. This says the
  // spread is a property of her cycles, not a gap in the data.
  'cyc_conf_variable': {
    AppLocale.ru: 'циклы разной длины — дата примерная',
    AppLocale.kk: 'циклдар ұзақтығы әртүрлі — күні шамамен',
    AppLocale.en: 'cycles vary — this date is approximate'
  },
  'cyc_conf_good': {AppLocale.ru: 'надёжный', AppLocale.kk: 'сенімді', AppLocale.en: 'confident'},
  'cyc_conf_tip': {AppLocale.ru: 'Точность прогноза растёт с числом отслеженных циклов.', AppLocale.kk: 'Болжам дәлдігі бақыланған цикл санына қарай артады.', AppLocale.en: 'Forecast accuracy improves as you track more cycles.'},
  'cyc_fertile_in': {AppLocale.ru: 'Фертильное окно через {n} дн.', AppLocale.kk: 'Құнарлы кезең {n} күнде', AppLocale.en: 'Fertile window in {n} days'},
  'cyc_ovulation_in': {AppLocale.ru: 'Овуляция примерно через {n} дн.', AppLocale.kk: 'Овуляция шамамен {n} күнде', AppLocale.en: 'Ovulation in about {n} days'},
  'phase_day': {AppLocale.ru: 'День {n} из {of}', AppLocale.kk: '{of} ішінен {n}-күн', AppLocale.en: 'Day {n} of {of}'},
  'phase_menstrual': {AppLocale.ru: 'Менструация', AppLocale.kk: 'Етеккір', AppLocale.en: 'Menstrual'},
  'phase_follicular': {AppLocale.ru: 'Фолликулярная фаза', AppLocale.kk: 'Фолликулалық фаза', AppLocale.en: 'Follicular'},
  'phase_fertile': {AppLocale.ru: 'Фертильная фаза', AppLocale.kk: 'Құнарлы фаза', AppLocale.en: 'Fertile'},
  'phase_luteal': {AppLocale.ru: 'Лютеиновая фаза', AppLocale.kk: 'Лютеиндік фаза', AppLocale.en: 'Luteal'},
  'phase_menstrual_note': {AppLocale.ru: 'Идут месячные. Отдыхайте и пейте больше воды.', AppLocale.kk: 'Етеккір кезеңі. Демалып, көбірек су ішіңіз.', AppLocale.en: 'Your period is here. Rest and stay hydrated.'},
  'phase_follicular_note': {AppLocale.ru: 'Энергия растёт по мере подготовки организма к овуляции.', AppLocale.kk: 'Ағза овуляцияға дайындалып, энергия артады.', AppLocale.en: 'Energy rises as your body prepares to ovulate.'},
  'phase_fertile_note': {AppLocale.ru: 'Наиболее вероятное время для зачатия.', AppLocale.kk: 'Жүктілік ықтималдығы жоғары кезең.', AppLocale.en: 'Your most fertile days — highest chance of conception.'},
  'phase_luteal_note': {AppLocale.ru: 'Возможен ПМС. Прислушивайтесь к своему телу.', AppLocale.kk: 'ПМС мүмкін. Денеңізді тыңдаңыз.', AppLocale.en: 'PMS symptoms may appear. Listen to your body.'},
  'cyc_share': {AppLocale.ru: 'Поделиться прогнозом', AppLocale.kk: 'Болжаммен бөлісу', AppLocale.en: 'Share cycle'},
  'cyc_share_copied': {AppLocale.ru: 'Прогноз скопирован', AppLocale.kk: 'Болжам көшірілді', AppLocale.en: 'Cycle summary copied to clipboard'},
  'cyc_share_title': {AppLocale.ru: 'Прогноз цикла · Ana-Bala', AppLocale.kk: 'Цикл болжамы · Ana-Bala', AppLocale.en: 'Cycle forecast · Ana-Bala'},
  'cyc_share_nodata': {AppLocale.ru: 'Пока недостаточно данных для прогноза', AppLocale.kk: 'Болжам үшін дерек әлі жеткіліксіз', AppLocale.en: 'Not enough data to predict yet'},
  'cyc_share_disclaimer': {AppLocale.ru: 'Оценка для самочувствия, не средство контрацепции.', AppLocale.kk: 'Бұл — болжам, контрацепция құралы емес.', AppLocale.en: 'Wellness estimate, not contraception guidance.'},
  'cyc_insights_title': {AppLocale.ru: 'Аналитика цикла', AppLocale.kk: 'Цикл аналитикасы', AppLocale.en: 'Cycle insights'},
  'period_reminder': {AppLocale.ru: 'Напоминание о месячных', AppLocale.kk: 'Етеккір туралы еске салу', AppLocale.en: 'Period reminder'},
  'period_reminder_sub': {AppLocale.ru: 'За 2 дня до предполагаемого начала', AppLocale.kk: 'Болжамды басталуға 2 күн қалғанда', AppLocale.en: '2 days before the expected start'},
  'period_reminder_title': {AppLocale.ru: 'Скоро месячные', AppLocale.kk: 'Етеккір жақындады', AppLocale.en: 'Period coming soon'},
  'period_reminder_body': {AppLocale.ru: 'По прогнозу месячные начнутся примерно через 2 дня.', AppLocale.kk: 'Болжам бойынша етеккір шамамен 2 күнде басталады.', AppLocale.en: 'Your period is predicted to start in about 2 days.'},
  'fertile_reminder': {AppLocale.ru: 'Напоминание о фертильном окне', AppLocale.kk: 'Фертильді терезе туралы еске салу', AppLocale.en: 'Fertile window reminder'},
  'fertile_reminder_sub': {AppLocale.ru: 'В день начала фертильного окна', AppLocale.kk: 'Фертильді терезе басталған күні', AppLocale.en: 'On the day the fertile window opens'},
  'fertile_reminder_title': {AppLocale.ru: 'Начинается фертильное окно', AppLocale.kk: 'Фертильді терезе басталады', AppLocale.en: 'Fertile window is opening'},
  'fertile_reminder_body': {AppLocale.ru: 'По прогнозу начинаются наиболее фертильные дни.', AppLocale.kk: 'Болжам бойынша ең фертильді күндер басталады.', AppLocale.en: 'Your most fertile days are predicted to begin now.'},
  'cyc_settings_title': {AppLocale.ru: 'Настройки цикла', AppLocale.kk: 'Цикл параметрлері', AppLocale.en: 'Cycle settings'},
  'cyc_avg_cycle_label': {AppLocale.ru: 'Средняя длина цикла', AppLocale.kk: 'Орташа цикл ұзақтығы', AppLocale.en: 'Average cycle length'},
  'cyc_avg_period_label': {AppLocale.ru: 'Средняя длительность месячных', AppLocale.kk: 'Орташа етеккір ұзақтығы', AppLocale.en: 'Average period length'},
  'cyc_settings_hint': {AppLocale.ru: 'Используется для прогнозов, пока не накопится история циклов.', AppLocale.kk: 'Цикл тарихы жиналғанша болжам үшін қолданылады.', AppLocale.en: 'Used for predictions until you have logged a few cycles.'},
  'cyc_insights_empty': {AppLocale.ru: 'Отмечайте дни менструации, чтобы видеть статистику.', AppLocale.kk: 'Статистиканы көру үшін етеккір күндерін белгілеңіз.', AppLocale.en: 'Log period days to see your stats.'},
  'cyc_history': {AppLocale.ru: 'История циклов', AppLocale.kk: 'Цикл тарихы', AppLocale.en: 'Cycle history'},
  'cyc_reg_regular': {AppLocale.ru: 'Цикл регулярный', AppLocale.kk: 'Цикл тұрақты', AppLocale.en: 'Your cycle is regular'},
  'cyc_reg_variable': {AppLocale.ru: 'Цикл слегка непостоянный', AppLocale.kk: 'Цикл сәл құбылмалы', AppLocale.en: 'Your cycle varies a little'},
  'cyc_reg_irregular': {AppLocale.ru: 'Цикл нерегулярный', AppLocale.kk: 'Цикл тұрақсыз', AppLocale.en: 'Your cycle is irregular'},
  'cyc_reg_sub': {AppLocale.ru: 'Разброс {var} дн. · в среднем {avg} дн.', AppLocale.kk: 'Айырмасы {var} күн · орташа {avg} күн', AppLocale.en: 'Varies by {var} days · {avg}-day average'},
  'cyc_recent_notes': {AppLocale.ru: 'Заметки', AppLocale.kk: 'Ескертпелер', AppLocale.en: 'Recent notes'},
  'notes_see_all': {AppLocale.ru: 'Все заметки ({n})', AppLocale.kk: 'Барлық ескертпе ({n})', AppLocale.en: 'See all notes ({n})'},
  'notes_browser_title': {AppLocale.ru: 'Заметки', AppLocale.kk: 'Ескертпелер', AppLocale.en: 'Notes'},
  'notes_search_hint': {AppLocale.ru: 'Поиск по заметкам', AppLocale.kk: 'Ескертпелерден іздеу', AppLocale.en: 'Search notes'},
  'notes_empty': {AppLocale.ru: 'Пока нет заметок. Добавьте заметку к любому дню.', AppLocale.kk: 'Әзірге ескертпе жоқ. Кез келген күнге ескертпе қосыңыз.', AppLocale.en: 'No notes yet. Add a note to any day.'},
  'notes_no_match': {AppLocale.ru: 'Ничего не найдено.', AppLocale.kk: 'Ештеңе табылмады.', AppLocale.en: 'No matching notes.'},
  'cyc_this_week': {AppLocale.ru: 'Симптомы за неделю', AppLocale.kk: 'Апталық симптомдар', AppLocale.en: 'Symptoms this week'},
  'cyc_mood_week': {AppLocale.ru: 'Настроение за неделю', AppLocale.kk: 'Апталық көңіл-күй', AppLocale.en: 'Mood this week'},
  'cyc_mood_trend': {AppLocale.ru: 'Тренд настроения', AppLocale.kk: 'Көңіл-күй трені', AppLocale.en: 'Mood trend'},
  'cyc_length_range': {AppLocale.ru: 'Длина цикла', AppLocale.kk: 'Цикл ұзақтығы', AppLocale.en: 'Cycle length'},
  'cyc_flow_title': {AppLocale.ru: 'Интенсивность', AppLocale.kk: 'Қарқындылық', AppLocale.en: 'Flow intensity'},
  'cyc_flow_days': {AppLocale.ru: '{n} дн.', AppLocale.kk: '{n} күн', AppLocale.en: '{n}d'},
  'cyc_flow_total': {AppLocale.ru: 'Всего дней с выделениями: {n}', AppLocale.kk: 'Барлығы {n} күн белгіленген', AppLocale.en: '{n} bleeding days logged in total'},
  'cyc_sym_phase_title': {AppLocale.ru: 'Симптом и фаза', AppLocale.kk: 'Симптом мен фаза', AppLocale.en: 'Symptom pattern'},
  'cyc_sym_phase_body': {AppLocale.ru: 'Чаще всего «{symptom}» появляется в фазе: {phase}', AppLocale.kk: '«{symptom}» көбіне {phase} фазасында байқалады', AppLocale.en: 'Your {symptom} most often appears in the {phase} phase'},
  'cyc_sym_phase_count': {AppLocale.ru: '{n} из {total} отметок', AppLocale.kk: '{total} ішінен {n} рет', AppLocale.en: '{n} of {total} times logged'},
  'cyc_len_shortest': {AppLocale.ru: 'мин. (дн.)', AppLocale.kk: 'ең қысқа (күн)', AppLocale.en: 'shortest (d)'},
  'cyc_len_average': {AppLocale.ru: 'сред. (дн.)', AppLocale.kk: 'орташа (күн)', AppLocale.en: 'average (d)'},
  'cyc_len_longest': {AppLocale.ru: 'макс. (дн.)', AppLocale.kk: 'ең ұзын (күн)', AppLocale.en: 'longest (d)'},
  'cyc_len_based_on': {AppLocale.ru: 'По {n} завершённым циклам', AppLocale.kk: '{n} аяқталған цикл бойынша', AppLocale.en: 'Based on {n} completed cycles'},
  'cyc_weeks_ago': {AppLocale.ru: '{n} нед. назад', AppLocale.kk: '{n} апта бұрын', AppLocale.en: '{n} wks ago'},
  'cyc_this_week_short': {AppLocale.ru: 'Эта неделя', AppLocale.kk: 'Осы апта', AppLocale.en: 'This week'},
  'cyc_streak': {AppLocale.ru: 'Серия записей: {n} дн.', AppLocale.kk: 'Жазба сериясы: {n} күн', AppLocale.en: '{n}-day logging streak'},
  'cyc_streak_sub': {AppLocale.ru: 'Дней подряд с записями', AppLocale.kk: 'Қатарынан жазба жасалған күндер', AppLocale.en: 'Consecutive days you logged something'},
  'cyc_cycles_tracked': {AppLocale.ru: 'Циклов', AppLocale.kk: 'Цикл', AppLocale.en: 'Cycles'},
  'cyc_avg_period_stat': {AppLocale.ru: 'Менструация', AppLocale.kk: 'Етеккір', AppLocale.en: 'Period'},
  'cyc_avg_cycle_stat': {AppLocale.ru: 'Цикл', AppLocale.kk: 'Цикл', AppLocale.en: 'Cycle'},
  'cyc_days_short': {AppLocale.ru: '{n} дн.', AppLocale.kk: '{n} к.', AppLocale.en: '{n}d'},
  'cyc_ongoing': {AppLocale.ru: 'Текущий', AppLocale.kk: 'Ағымдағы', AppLocale.en: 'Ongoing'},
  'cyc_period_len': {AppLocale.ru: 'менструация {n} дн.', AppLocale.kk: 'етеккір {n} күн', AppLocale.en: '{n}-day period'},
  'cyc_top_symptoms': {AppLocale.ru: 'Частые симптомы', AppLocale.kk: 'Жиі симптомдар', AppLocale.en: 'Common symptoms'},
  'cyc_top_moods': {AppLocale.ru: 'Настроение', AppLocale.kk: 'Көңіл-күй', AppLocale.en: 'Moods'},
  'cyc_times': {AppLocale.ru: '{n}×', AppLocale.kk: '{n}×', AppLocale.en: '{n}×'},
  'sym_days_count': {AppLocale.ru: 'Отмечено дней: {n}', AppLocale.kk: 'Белгіленген күндер: {n}', AppLocale.en: 'Logged on {n} days'},
  'sym_days_empty': {AppLocale.ru: 'Этот симптом ещё не отмечался.', AppLocale.kk: 'Бұл симптом әлі белгіленбеген.', AppLocale.en: 'This symptom hasn\'t been logged yet.'},
  'cyc_next_period': {AppLocale.ru: 'Следующие месячные', AppLocale.kk: 'Келесі етеккір', AppLocale.en: 'Next period'},
  'cyc_avg_cycle': {AppLocale.ru: 'Средний цикл: {n} дн.', AppLocale.kk: 'Орташа цикл: {n} күн', AppLocale.en: 'Average cycle: {n} days'},
  'gest_due': {AppLocale.ru: 'Дата родов: {date}', AppLocale.kk: 'Босану күні: {date}', AppLocale.en: 'Due date: {date}'},
  'cyc_no_data_title': {AppLocale.ru: 'Отслеживайте цикл', AppLocale.kk: 'Циклді қадағалаңыз', AppLocale.en: 'Track your cycle'},
  'cyc_no_data_body': {AppLocale.ru: 'Отметьте день менструации, чтобы видеть прогнозы.', AppLocale.kk: 'Болжамды көру үшін етеккір күнін белгілеңіз.', AppLocale.en: 'Log a period day to see predictions.'},
  'cyc_pp_paused_title': {AppLocale.ru: 'Цикл на паузе после родов', AppLocale.kk: 'Босанғаннан кейін цикл кідіртілді', AppLocale.en: 'Cycle paused after birth'},
  'cyc_pp_paused_body': {AppLocale.ru: 'После родов месячные могут не приходить несколько месяцев — особенно при грудном вскармливании. Отметьте месячные, когда они вернутся, и прогнозы возобновятся.', AppLocale.kk: 'Босанғаннан кейін етеккір бірнеше ай болмауы мүмкін — әсіресе емізу кезінде. Ол қайта басталғанда белгілеңіз, сонда болжамдар жалғасады.', AppLocale.en: 'Periods can pause for months after birth — especially while breastfeeding. Log your period when it returns and predictions will resume.'},
  'cyc_expecting': {AppLocale.ru: 'Ждёте ребёнка? Укажите срок', AppLocale.kk: 'Бала күтудесіз бе? Мерзімін қосыңыз', AppLocale.en: 'Expecting? Add a due date'},
  'cyc_end_pregnancy': {AppLocale.ru: 'Больше не беременны?', AppLocale.kk: 'Енді жүкті емессіз бе?', AppLocale.en: 'No longer pregnant?'},
  'cyc_end_pregnancy_body': {AppLocale.ru: 'Отслеживание беременности отключится, и вернётся календарь цикла. Ваши записи останутся.', AppLocale.kk: 'Жүктілікті бақылау өшіріліп, цикл күнтізбесі қайтады. Жазбаларыңыз сақталады.', AppLocale.en: 'Pregnancy tracking turns off and cycle tracking returns. Your logs are kept.'},

  // Child safety tips (age-appropriate + status-driven)
  'safety_title': {AppLocale.ru: 'Советы по безопасности', AppLocale.kk: 'Қауіпсіздік кеңестері', AppLocale.en: 'Safety tips'},
  'safety_intro': {AppLocale.ru: 'Советы с учётом возраста {name}', AppLocale.kk: '{name} жасына сай кеңестер', AppLocale.en: 'Tips for {name}, by age'},
  'safety_age': {AppLocale.ru: 'Возраст: {age}', AppLocale.kk: 'Жасы: {age}', AppLocale.en: 'Age: {age}'},
  'CS_DELAYED': {AppLocale.ru: 'Задержка данных', AppLocale.kk: 'Дерек кешігуде', AppLocale.en: 'Location delayed'},
  'CS_DELAYED_b': {AppLocale.ru: 'Давно не было свежих данных о местоположении {name}. Напишите или позвоните, чтобы проверить.', AppLocale.kk: '{name} орналасуы жайлы жаңа дерек көптен бері жоқ. Хабарласып тексеріңіз.', AppLocale.en: "There hasn't been a fresh location for {name} in a while. Message or call to check in."},
  'CS_AT_ZONE': {AppLocale.ru: 'В безопасной зоне', AppLocale.kk: 'Қауіпсіз аймақта', AppLocale.en: 'In a safe zone'},
  'CS_AT_ZONE_b': {AppLocale.ru: '{name} сейчас в зоне «{zone}».', AppLocale.kk: '{name} қазір «{zone}» аймағында.', AppLocale.en: '{name} is inside the {zone} zone right now.'},
  'CS_ON_MOVE': {AppLocale.ru: 'В пути', AppLocale.kk: 'Жолда', AppLocale.en: 'On the move'},
  'CS_ON_MOVE_b': {AppLocale.ru: '{name} между сохранёнными зонами. Вы получите уведомление о прибытии.', AppLocale.kk: '{name} сақталған аймақтар арасында. Келгенде хабарлама аласыз.', AppLocale.en: "{name} is between saved zones. You'll be alerted on arrival."},
  'CS_NO_DOB': {AppLocale.ru: 'Добавьте дату рождения', AppLocale.kk: 'Туған күнін қосыңыз', AppLocale.en: 'Add a birth date'},
  'CS_NO_DOB_b': {AppLocale.ru: 'Укажите дату рождения {name}, чтобы получать советы по возрасту.', AppLocale.kk: '{name} туған күнін қосып, жасына сай кеңес алыңыз.', AppLocale.en: "Add {name}'s date of birth to get age-tailored safety tips."},
  'CS_INFANT_SLEEP': {AppLocale.ru: 'Безопасный сон', AppLocale.kk: 'Қауіпсіз ұйқы', AppLocale.en: 'Safe sleep'},
  'CS_INFANT_SLEEP_b': {AppLocale.ru: 'Укладывайте малыша на спину, на твёрдую и свободную поверхность.', AppLocale.kk: 'Нәрестені шалқасынан, қатты әрі бос бетке жатқызыңыз.', AppLocale.en: 'Place your baby on their back to sleep, on a firm, clear surface.'},
  'CS_INFANT_CARSEAT': {AppLocale.ru: 'Автокресло против хода', AppLocale.kk: 'Кері қараған автокресло', AppLocale.en: 'Rear-facing car seat'},
  'CS_INFANT_CARSEAT_b': {AppLocale.ru: 'Используйте автокресло против хода движения и проверяйте ремни каждую поездку.', AppLocale.kk: 'Кері қараған автокреслоны пайдаланып, әр сапарда белдікті тексеріңіз.', AppLocale.en: 'Use a rear-facing car seat and check the harness fit every trip.'},
  'CS_TODDLER_WATER': {AppLocale.ru: 'Вода и лестницы', AppLocale.kk: 'Су мен баспалдақ', AppLocale.en: 'Water & stairs'},
  'CS_TODDLER_WATER_b': {AppLocale.ru: 'Не оставляйте малыша одного у воды, лестниц и открытых окон.', AppLocale.kk: 'Баланы су, баспалдақ, ашық терезе жанында жалғыз қалдырмаңыз.', AppLocale.en: 'Never leave a toddler alone near water, stairs, or open windows.'},
  'CS_TODDLER_CHOKING': {AppLocale.ru: 'Мелкие предметы', AppLocale.kk: 'Ұсақ заттар', AppLocale.en: 'Small objects'},
  'CS_TODDLER_CHOKING_b': {AppLocale.ru: 'Держите монеты, батарейки и мелкие детали вне досягаемости.', AppLocale.kk: 'Тиын, батарея, ұсақ бөлшектерді қолы жетпейтін жерде сақтаңыз.', AppLocale.en: 'Keep coins, button batteries, and small parts out of reach.'},
  'CS_PRESCHOOL_ROAD': {AppLocale.ru: 'Рядом с дорогой', AppLocale.kk: 'Жол жанында', AppLocale.en: 'Near roads'},
  'CS_PRESCHOOL_ROAD_b': {AppLocale.ru: 'Держите за руку у проезжей части и учите останавливаться у края.', AppLocale.kk: 'Жол жиегінде қолынан ұстап, тоқтауды үйретіңіз.', AppLocale.en: 'Hold hands near traffic and practice stopping at the curb.'},
  'CS_PRESCHOOL_IDENTITY': {AppLocale.ru: 'Знает свои данные', AppLocale.kk: 'Өз мәліметін біледі', AppLocale.en: 'Knows their info'},
  'CS_PRESCHOOL_IDENTITY_b': {AppLocale.ru: 'Помогите запомнить полное имя и ваш номер телефона.', AppLocale.kk: 'Толық аты мен телефоныңызды жаттауға көмектесіңіз.', AppLocale.en: 'Help them memorize their full name and your phone number.'},
  'CS_SCHOOL_ROUTE': {AppLocale.ru: 'Безопасный маршрут', AppLocale.kk: 'Қауіпсіз бағыт', AppLocale.en: 'Safe route'},
  'CS_SCHOOL_ROUTE_b': {AppLocale.ru: 'Пройдите путь в школу вместе и договоритесь о безопасных переходах.', AppLocale.kk: 'Мектепке дейінгі жолды бірге жүріп, қауіпсіз өткелдерді келісіңіз.', AppLocale.en: 'Walk the route to school together and agree on safe crossings.'},
  'CS_SCHOOL_CHECKIN': {AppLocale.ru: 'Время связи', AppLocale.kk: 'Хабарласу уақыты', AppLocale.en: 'Check-in times'},
  'CS_SCHOOL_CHECKIN_b': {AppLocale.ru: 'Договоритесь, когда {name} выходит на связь после школы.', AppLocale.kk: '{name} мектептен кейін қашан хабарласатынын келісіңіз.', AppLocale.en: 'Agree on when {name} checks in after school.'},
  'CS_PRETEEN_ONLINE': {AppLocale.ru: 'Безопасность в сети', AppLocale.kk: 'Онлайн қауіпсіздік', AppLocale.en: 'Online safety'},
  'CS_PRETEEN_ONLINE_b': {AppLocale.ru: 'Поговорите о приватности, геолокации и общении с незнакомцами.', AppLocale.kk: 'Құпиялылық, геолокация, бейтаныстармен сөйлесу туралы әңгімелесіңіз.', AppLocale.en: 'Talk about privacy, sharing location, and messaging strangers.'},
  'CS_PRETEEN_LOCATION': {AppLocale.ru: 'Обмен геолокацией', AppLocale.kk: 'Геолокация бөлісу', AppLocale.en: 'Location sharing'},
  'CS_PRETEEN_LOCATION_b': {AppLocale.ru: 'Договоритесь о чётких правилах: геолокация остаётся включённой.', AppLocale.kk: 'Айқын келісіңіз: геолокация қосулы қалады.', AppLocale.en: 'Set clear expectations about keeping location sharing on.'},

  // Tracking
  // No child added yet — the ordinary state for a first-time expectant
  // mother. Written out rather than substituting a noun into the sentences
  // above: Russian needs the nominative in one and the genitive in the other,
  // and Kazakh has the same problem.
  'child_generic': {AppLocale.ru: 'ребёнок', AppLocale.kk: 'бала', AppLocale.en: 'your child'},
  'tr_title_nochild': {AppLocale.ru: 'Где ребёнок?', AppLocale.kk: 'Бала қайда?', AppLocale.en: 'Where is your child?'},
  'tr_waiting_nochild': {
    AppLocale.ru: 'Ожидание местоположения…',
    AppLocale.kk: 'Орналасуын күту…',
    AppLocale.en: 'Waiting for a location…',
  },
  'tr_title': {AppLocale.ru: 'Где {name}?', AppLocale.kk: '{name} қайда?', AppLocale.en: 'Where is {name}?'},
  'fresh_live': {AppLocale.ru: 'В сети', AppLocale.kk: 'Желіде', AppLocale.en: 'Live'},
  'fresh_recent': {AppLocale.ru: 'Недавно', AppLocale.kk: 'Жақында', AppLocale.en: 'Recent'},
  'fresh_stale': {AppLocale.ru: 'Задержка', AppLocale.kk: 'Кешігу', AppLocale.en: 'Delayed'},
  'tr_inside_zone': {AppLocale.ru: 'В зоне «{zone}»', AppLocale.kk: '«{zone}» аймағында', AppLocale.en: 'Inside {zone} zone'},
  'tr_in_zone_for': {AppLocale.ru: 'уже {dur}', AppLocale.kk: '{dur} болды', AppLocale.en: 'for {dur}'},
  'tr_last_checkin': {AppLocale.ru: 'Отметился {ago}', AppLocale.kk: '{ago} белгіленді', AppLocale.en: 'Checked in {ago}'},
  'tr_battery': {AppLocale.ru: 'Заряд трекера {pct}%', AppLocale.kk: 'Трекер заряды {pct}%', AppLocale.en: 'Tracker battery {pct}%'},
  'bat_history_title': {AppLocale.ru: 'История заряда', AppLocale.kk: 'Заряд тарихы', AppLocale.en: 'Battery history'},
  'bat_change_down': {AppLocale.ru: 'Снизился на {n}% за период', AppLocale.kk: 'Кезең ішінде {n}%-ға төмендеді', AppLocale.en: 'Down {n}% over this period'},
  'bat_change_up': {AppLocale.ru: 'Вырос на {n}% за период', AppLocale.kk: 'Кезең ішінде {n}%-ға өсті', AppLocale.en: 'Up {n}% over this period'},
  'bat_change_flat': {AppLocale.ru: 'Без изменений за период', AppLocale.kk: 'Кезең ішінде өзгермеді', AppLocale.en: 'No change over this period'},
  'tr_dist_m': {AppLocale.ru: '{m} м от дома', AppLocale.kk: 'үйден {m} м', AppLocale.en: '{m} m from home'},
  'tr_dist_km': {AppLocale.ru: '{km} км от дома', AppLocale.kk: 'үйден {km} км', AppLocale.en: '{km} km from home'},
  'map_unavailable': {AppLocale.ru: 'Карта появится после настройки ключа', AppLocale.kk: 'Кілт бапталғаннан кейін карта пайда болады', AppLocale.en: 'Map appears once a Maps key is configured'},
  'tr_at_zone': {AppLocale.ru: '{name} в «{zone}»', AppLocale.kk: '{name} «{zone}» жерінде', AppLocale.en: '{name} is at {zone}'},
  'tr_on_move': {AppLocale.ru: '{name} в пути — обновлено {ago}', AppLocale.kk: '{name} жолда — {ago} жаңартылды', AppLocale.en: '{name} is on the move — updated {ago}'},
  'tr_stale': {AppLocale.ru: 'Местоположение {name} {phrase} — последний раз {ago}', AppLocale.kk: '{name} орналасуы {phrase} — соңғы рет {ago}', AppLocale.en: "{name}'s location is {phrase} — last seen {ago}"},
  'tr_waiting': {AppLocale.ru: 'Ожидание местоположения {name}…', AppLocale.kk: '{name} орналасуын күту…', AppLocale.en: "Waiting for {name}'s location…"},
  'tr_clock_skew': {
    AppLocale.ru: 'Ana-Bala не может определить, насколько свежие данные о местоположении {name} — часы телефона и трекера расходятся',
    AppLocale.kk: 'Ana-Bala {name} орналасуының қаншалықты жаңа екенін анықтай алмайды — телефон мен трекердің уақыты сәйкес келмейді',
    AppLocale.en: "Ana-Bala can't tell how old {name}'s location is — the phone and the tracker disagree about the time",
  },
  'stale_delayed': {AppLocale.ru: 'задерживается', AppLocale.kk: 'кешігуде', AppLocale.en: 'delayed'},
  'stale_outdated': {AppLocale.ru: 'устарело', AppLocale.kk: 'ескірген', AppLocale.en: 'out of date'},

  // Relative time
  'ago_just_now': {AppLocale.ru: 'только что', AppLocale.kk: 'дәл қазір', AppLocale.en: 'just now'},
  'ago_lt_minute': {AppLocale.ru: 'меньше минуты назад', AppLocale.kk: 'бір минуттан аз уақыт бұрын', AppLocale.en: 'less than a minute ago'},
  'ago_min': {AppLocale.ru: '{n} мин назад', AppLocale.kk: '{n} мин бұрын', AppLocale.en: '{n} min ago'},
  'ago_hour': {AppLocale.ru: '{n} ч назад', AppLocale.kk: '{n} сағ бұрын', AppLocale.en: '{n} h ago'},
  'ago_day': {AppLocale.ru: '{n} дн назад', AppLocale.kk: '{n} күн бұрын', AppLocale.en: '{n} d ago'},

  // ---- Device-estimated temperature -----------------------------------------
  // Approved copy, 2026-08-13. Do not rewrite: a rewrite voids the approval.
  //
  // Three rules are carried by the wording rather than by a comment, so read
  // before editing (docs/CLINICAL-REVIEW-WATCH.md):
  //   * the subject is the SENSOR, never her temperature. ADV_TEMP_ELEVATED
  //     asserts «Температура повышена» and tells her to «измерьте снова» without
  //     naming an instrument — off a wrist, re-reading it is not a second
  //     measurement. Refused sentence #16.
  //   * the escalation is «позвоните врачу сегодня», NOT 103: emergency_help.json
  //     reserves 103 for lethargy and unresponsiveness.
  //   * no number. 37.8 and 38.5 have no cited source for pregnancy anywhere in
  //     this repo, so no user-facing string may state either.
  'ADV_TEMP_DEVICE_HIGH': {AppLocale.ru: 'Датчик показывает повышенную температуру', AppLocale.kk: 'Датчик жоғары дене қызуын көрсетіп тұр', AppLocale.en: 'The sensor is reading a raised temperature'},
  'ADV_TEMP_DEVICE_HIGH_b': {AppLocale.ru: 'Это оценка датчика на запястье, а не измерение. Измерьте температуру термометром под мышкой и введите результат в приложении. Если термометр тоже показывает повышенную температуру или вы плохо себя чувствуете — позвоните врачу сегодня.', AppLocale.kk: 'Бұл — білезіктегі датчиктің болжамы, өлшем емес. Дене қызуын термометрмен қолтық астынан өлшеп, нәтижесін қолданбаға енгізіңіз. Термометр де жоғары қызуды көрсетсе немесе өзіңізді нашар сезінсеңіз — бүгін дәрігерге хабарласыңыз.', AppLocale.en: 'This is a wrist-sensor estimate, not a measurement. Take your temperature with a thermometer under your arm and enter the result in the app. If the thermometer also shows a raised temperature, or you feel unwell, call your doctor today.'},
  // Sits next to the number on the vitals grid — the place the claim is made.
  // States a limitation and stops there: «если что-то будет не так, приложение
  // вас предупредит» is refused sentence #12, in every phrasing, because it
  // turns every gap in coverage into an implied all-clear.
  'temp_device_estimate_note': {AppLocale.ru: 'Температура с датчика — приблизительная оценка: она сильно зависит от того, насколько вам тепло и как плотно надето устройство. По ней нельзя судить, есть ли у вас жар. Точную температуру даёт только термометр.', AppLocale.kk: 'Датчиктен алынған дене қызуы — шамалас болжам: ол сізге қаншалықты жылы екеніне және құрылғының қаншалықты тығыз тағылғанына қатты тәуелді. Ол бойынша қызуыңыз бар-жоғын білуге болмайды. Нақты дене қызуын тек термометр көрсетеді.', AppLocale.en: 'A temperature from the sensor is a rough estimate: it depends heavily on how warm you are and how tightly the device is worn. It cannot tell you whether you have a fever. Only a thermometer gives an accurate temperature.'},

  // Triage messages (emergency-severity codes; the safety layer emits the code)
  'PREECLAMPSIA_BP': {
    AppLocale.ru: 'Обнаружено высокое давление — признак преэклампсии. Немедленно свяжитесь с врачом.',
    AppLocale.kk: 'Жоғары қан қысымы анықталды — преэклампсия белгісі. Дереу дәрігерге хабарласыңыз.',
    AppLocale.en: 'High blood pressure detected — a warning sign of preeclampsia. Contact your doctor immediately.'
  },
  'PREECLAMPSIA_BP_SEVERE': {
    AppLocale.ru: 'Обнаружено очень высокое давление. Это может быть признаком тяжёлой преэклампсии. Немедленно обратитесь за неотложной помощью.',
    AppLocale.kk: 'Өте жоғары қан қысымы анықталды. Бұл ауыр преэклампсия белгісі болуы мүмкін. Дереу жедел жәрдемге жүгініңіз.',
    AppLocale.en: 'Severe-range blood pressure detected. This can signal severe preeclampsia. Seek emergency care now.'
  },
  'HIGH_FEVER': {
    AppLocale.ru: 'Высокая температура во время беременности. Требуется срочный осмотр врача.',
    AppLocale.kk: 'Жүктілік кезіндегі жоғары қызу. Шұғыл медициналық тексеру қажет.',
    AppLocale.en: 'High fever detected during pregnancy. Urgent medical review is needed.'
  },
  'HYPOXIA_SEVERE': {
    AppLocale.ru: 'Обнаружен очень низкий уровень кислорода в крови. Немедленно обратитесь за неотложной помощью.',
    AppLocale.kk: 'Қандағы оттегі деңгейі өте төмен. Дереу жедел жәрдемге жүгініңіз.',
    AppLocale.en: 'Very low blood oxygen detected. Seek emergency care now.'
  },
  'TACHYCARDIA_SEVERE': {
    AppLocale.ru: 'Обнаружено опасное сердцебиение. Срочно обратитесь за медицинской помощью.',
    AppLocale.kk: 'Қауіпті жүрек соғысы анықталды. Шұғыл медициналық көмекке жүгініңіз.',
    AppLocale.en: 'Dangerous heart rate detected. Seek urgent medical help.'
  },
  'BRADYCARDIA_SEVERE': {
    AppLocale.ru: 'Обнаружено опасное сердцебиение. Срочно обратитесь за медицинской помощью.',
    AppLocale.kk: 'Қауіпті жүрек соғысы анықталды. Шұғыл медициналық көмекке жүгініңіз.',
    AppLocale.en: 'Dangerous heart rate detected. Seek urgent medical help.'
  },
  'EMERGENCY_GENERIC': {
    AppLocale.ru: 'Обнаружен серьёзный признак. Немедленно обратитесь за медицинской помощью.',
    AppLocale.kk: 'Елеулі белгі анықталды. Дереу медициналық көмекке жүгініңіз.',
    AppLocale.en: 'A serious sign was detected. Please seek medical help immediately.'
  },

  // ---- Onboarding · the pairing step, once it can tell its states apart ----
  //
  // The page had two sentences for six situations: «Поиск устройств…» and a
  // list. With Bluetooth off it showed the first one for ever, and nothing on
  // the screen was about the phone — which is the only thing she could have
  // fixed. Each key below belongs to exactly one state of [BandScanPhase]; the
  // wording says what happened and what to do, and none of it promises that the
  // app will notice anything on her behalf.
  //
  // `onb_pair_body` («Выберите ваш браслет из списка») is kept and now shown
  // ONLY in the state where a list exists; `onb_pair_hint` is what leads every
  // other state, because "pick from the list" over an empty area is the sentence
  // that made the step read as broken.
  'onb_pair_hint': {
    AppLocale.ru: 'Включите браслет и держите его рядом с телефоном.',
    AppLocale.kk: 'Білезікті қосып, телефонның қасында ұстаңыз.',
    AppLocale.en: 'Switch the band on and keep it near the phone.'
  },
  'onb_pair_scanning_more': {
    AppLocale.ru: 'Ищем ещё…',
    AppLocale.kk: 'Іздеу жалғасуда…',
    AppLocale.en: 'Still looking…'
  },
  'onb_pair_none_title': {
    AppLocale.ru: 'Рядом ничего не нашли',
    AppLocale.kk: 'Жақын маңнан ештеңе табылмады',
    AppLocale.en: 'Nothing found nearby'
  },
  'onb_pair_none_body': {
    AppLocale.ru: 'Проверьте: браслет заряжен и включён, лежит рядом с телефоном и не подключён к другому телефону.',
    AppLocale.kk: 'Тексеріңіз: білезік зарядталған және қосулы, телефонның қасында тұр және басқа телефонға жалғанбаған.',
    AppLocale.en: 'Check that the band is charged and switched on, is next to the phone, and is not connected to another phone.'
  },
  'onb_pair_retry': {
    AppLocale.ru: 'Искать снова',
    AppLocale.kk: 'Қайта іздеу',
    AppLocale.en: 'Search again'
  },
  'onb_pair_bt_off_title': {
    AppLocale.ru: 'Bluetooth выключен',
    AppLocale.kk: 'Bluetooth өшірулі',
    AppLocale.en: 'Bluetooth is off'
  },
  'onb_pair_bt_off_body': {
    AppLocale.ru: 'Без него телефон не видит браслет.',
    AppLocale.kk: 'Онсыз телефон білезікті көрмейді.',
    AppLocale.en: 'Without it the phone cannot see the band.'
  },
  'onb_pair_bt_on': {
    AppLocale.ru: 'Включить Bluetooth',
    AppLocale.kk: 'Bluetooth қосу',
    AppLocale.en: 'Turn Bluetooth on'
  },
  'onb_pair_perm_title': {
    AppLocale.ru: 'Нужен доступ к Bluetooth',
    AppLocale.kk: 'Bluetooth-қа рұқсат керек',
    AppLocale.en: 'Bluetooth permission is needed'
  },
  'onb_pair_perm_body': {
    AppLocale.ru: 'Разрешите в настройках телефона — искать браслет без этого нельзя. Мы не определяем ваше местоположение.',
    AppLocale.kk: 'Телефон параметрлерінен рұқсат беріңіз — онсыз білезікті іздеу мүмкін емес. Біз сіздің орналасқан жеріңізді анықтамаймыз.',
    AppLocale.en: 'Allow it in your phone settings — the band cannot be found without it. We do not use your location.'
  },
  'onb_pair_unsupported_title': {
    AppLocale.ru: 'На этом телефоне нет Bluetooth',
    AppLocale.kk: 'Бұл телефонда Bluetooth жоқ',
    AppLocale.en: 'This phone has no Bluetooth'
  },
  'onb_pair_unsupported_body': {
    AppLocale.ru: 'Браслет подключить не получится. Всё остальное в приложении работает так же.',
    AppLocale.kk: 'Білезікті қосу мүмкін болмайды. Қосымшадағы қалғанының бәрі бұрынғыдай жұмыс істейді.',
    AppLocale.en: 'A band cannot be paired here. Everything else in the app works the same.'
  },
  'onb_pair_failed_title': {
    AppLocale.ru: 'Поиск не запустился',
    AppLocale.kk: 'Іздеу басталмады',
    AppLocale.en: 'The search did not start'
  },
  'onb_pair_failed_body': {
    AppLocale.ru: 'Телефон не смог включить поиск. Попробуйте ещё раз.',
    AppLocale.kk: 'Телефон іздеуді бастай алмады. Қайталап көріңіз.',
    AppLocale.en: 'The phone could not start the search. Please try again.'
  },
  'onb_pair_signal_strong': {
    AppLocale.ru: 'сигнал сильный',
    AppLocale.kk: 'сигнал күшті',
    AppLocale.en: 'strong signal'
  },
  'onb_pair_signal_weak': {
    AppLocale.ru: 'сигнал слабый',
    AppLocale.kk: 'сигнал әлсіз',
    AppLocale.en: 'weak signal'
  },
  // «Пропустить» said nothing about what she was skipping, on the one step
  // where the answer «у меня его нет» is the ordinary one, not the exception.
  'onb_pair_no_device': {
    AppLocale.ru: 'Пока нет — буду записывать вручную',
    AppLocale.kk: 'Әзірге жоқ — қолмен жазып отырамын',
    AppLocale.en: 'Not yet — I will log by hand'
  },
  'onb_pair_manual_title': {
    AppLocale.ru: 'Записывайте вручную',
    AppLocale.kk: 'Қолмен жазып отырыңыз',
    AppLocale.en: 'Log it by hand'
  },
  // No arrow glyph: Rubik has no U+2192, and it is the only face with the full
  // Kazakh set — «Настройки → Устройства» renders as a tofu box in Kazakh.
  'onb_pair_manual_body': {
    AppLocale.ru: 'Давление, вес и сон вы вводите сами — дневник, календари и напоминания те же самые. Браслет можно подключить в любой момент в разделе «Настройки», пункт «Устройства».',
    AppLocale.kk: 'Қысым, салмақ және ұйқыны өзіңіз енгізесіз — күнделік, күнтізбелер мен еске салғыштар сол күйінде. Білезікті кез келген уақытта «Параметрлер» бөліміндегі «Құрылғылар» тармағынан қосуға болады.',
    AppLocale.en: 'You enter blood pressure, weight and sleep yourself — the diary, the calendars and the reminders are the same. You can pair a band at any time in Settings, under Devices.'
  },
  // ---- Visit summary: the page she hands to a doctor ----
  //
  // Names the instrument on the blood-pressure row, exactly as
  // `visit_temp_thermometer` does for temperature. That row exists ONLY for
  // readings she took with a cuff and typed in — wrist estimates never reach
  // this summary, and visit_summary.dart says why — so this states a fact about
  // the number rather than warning about it. No wording here may suggest the
  // app measured anything, and none of it may carry a threshold: 140/90 is
  // ACOG's and belongs to triage, not to a label on a printout.
  'visit_bp_cuff': {
    AppLocale.ru: 'измерено тонометром, введено вручную',
    AppLocale.kk: 'тонометрмен өлшенген, қолмен енгізілген',
    AppLocale.en: 'measured with a cuff, entered by hand'
  },
  // The header over the vitals block, with no count on it. The count now sits
  // on each row, because after the provenance filters no two rows are built
  // from the same pool — see visit_summary.dart. `visit_vitals`, the counted
  // header this replaces, is left in place: nothing may be assumed dead in a
  // table 64 call sites index dynamically.
  'visit_vitals_head': {
    AppLocale.ru: 'ПОКАЗАТЕЛИ',
    AppLocale.kk: 'КӨРСЕТКІШТЕР',
    AppLocale.en: 'VITALS'
  },
  // How many readings one row rests on. Only ever rendered for n ≥ 2, so the
  // English plural is always right; the Russian is abbreviated so that no form
  // of the noun has to agree with a number this app has no plural helper for.
  'visit_row_readings': {
    AppLocale.ru: '{n} изм.',
    AppLocale.kk: '{n} өлшем',
    AppLocale.en: '{n} readings'
  },

  // The manual-entry card (screen 05), second sentence, for a woman who is
  // already using it.
  //
  // The card used to vanish after her first hand-typed reading, so `noband_body`
  // could only ever be read by someone with nothing logged and could safely be
  // an introduction — «приложение работает и без браслета». Now that the card
  // stays, that sentence would greet her above her own readings every morning:
  // still true, but an answer to a question she settled months ago. This is
  // what is true and worth saying instead — where the readings she just took
  // have gone. It states a fact about the app's own screens and promises
  // nothing about noticing anything on her behalf.
  'noband_body_logging': {
    AppLocale.ru: 'Ваши замеры — в дневнике и в календарях. Добавьте ещё:',
    AppLocale.kk: 'Өлшемдеріңіз күнделік пен күнтізбелерде. Тағы қосыңыз:',
    AppLocale.en: 'Your readings are in the diary and the calendars. Add another:'
  },

  // The Ма!Ма! course when the entitlement could not be read at all.
  //
  // Every word here is load-bearing. The sentence may not say she has bought
  // the course and may not say she has not — the app does not know, and both
  // guesses have already been shipped and cost trust. It also promises nothing
  // about being told later: the retry is hers to press.
  'course_check_failed': {
    AppLocale.ru: 'Не удалось проверить доступ к курсу',
    AppLocale.kk: 'Курсқа қолжетімділікті тексеру мүмкін болмады',
    AppLocale.en: 'Could not check your access to the course'
  },
  // Written like `zonehist_failed_why`, and for the same reason: it denies the
  // inference rather than making the opposite one.
  'course_check_failed_why': {
    AppLocale.ru: 'Сервер не ответил. Это не значит, что доступа нет.',
    AppLocale.kk: 'Сервер жауап бермеді. Бұл қолжетімділік жоқ дегенді білдірмейді.',
    AppLocale.en: 'The server did not answer. That does not mean you have no access.'
  },
  // The profile row's one line in the same state. The tap is the retry, so the
  // line says what the tap does instead of the row growing a second control.
  'course_entry_uncheckable': {
    AppLocale.ru: 'Не удалось проверить доступ — нажмите, чтобы повторить',
    AppLocale.kk: 'Қолжетімділікті тексеру мүмкін болмады — қайталау үшін басыңыз',
    AppLocale.en: 'Could not check access — tap to retry'
  },
};

/// The set of triage codes that have a localized message (for coverage checks).
const triageCodesWithMessages = <String>{
  'PREECLAMPSIA_BP',
  'PREECLAMPSIA_BP_SEVERE',
  'HIGH_FEVER',
  'HYPOXIA_SEVERE',
  'TACHYCARDIA_SEVERE',
  'BRADYCARDIA_SEVERE',
  'EMERGENCY_GENERIC',
};

class L10n {
  final AppLocale locale;
  const L10n(this.locale);

  String get localeCode => locale.name;

  /// Look up [key], interpolate {placeholders} from [params].
  String t(String key, [Map<String, Object?> params = const {}]) {
    final row = _catalog[key];
    var s = row?[locale] ?? row?[AppLocale.en] ?? key;
    params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  String triageMessage(String? code) =>
      code != null && _catalog.containsKey(code) ? t(code) : t('EMERGENCY_GENERIC');

  String metricLabel(String metricKey) => t('metric_$metricKey');

  /// Localized "7h 40m" style duration from minutes.
  String duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return t('dur_hm', {'h': h, 'm': m});
    if (h > 0) return t('dur_h', {'h': h});
    return t('dur_m', {'m': m});
  }

  /// Localized sleep-quality label.
  String sleepQuality(SleepQuality q) => switch (q) {
        SleepQuality.good => t('sleep_quality_good'),
        SleepQuality.fair => t('sleep_quality_fair'),
        SleepQuality.poor => t('sleep_quality_poor'),
      };

  /// Localized child age from whole months (see ChildProfile.ageInMonths).
  String childAge(int months) {
    if (months >= 24) return t('age_years', {'n': months ~/ 12});
    if (months >= 12) return t('age_year_months', {'y': months ~/ 12, 'm': months % 12});
    if (months >= 1) return t('age_months', {'n': months});
    return t('age_newborn');
  }

  String freshnessLabel(Freshness f) => switch (f) {
        Freshness.live => t('fresh_live'),
        Freshness.recent => t('fresh_recent'),
        Freshness.stale => t('fresh_stale'),
      };

  /// Localized "x ago" for a caller that has already decided what a negative
  /// age means — the battery strip and the check-in row both clamp to zero,
  /// treating a slightly-ahead timestamp as "just now" on purpose.
  ///
  /// Use [agoIfKnown] anywhere the phrase carries a claim about how current
  /// the child's position is.
  String ago(Duration age) => agoIfKnown(age) ?? t('ago_just_now');

  /// Localized "x ago" — mirrors the buckets in child_tracker_state.formatAgo,
  /// including its refusal to describe a timestamp from the future.
  String? agoIfKnown(Duration age) {
    if (clockDisagrees(age)) return null;
    if (age.inSeconds < 45) return t('ago_just_now');
    if (age.inMinutes < 1) return t('ago_lt_minute');
    if (age.inMinutes < 60) return t('ago_min', {'n': age.inMinutes});
    if (age.inHours < 24) return t('ago_hour', {'n': age.inHours});
    return t('ago_day', {'n': age.inDays});
  }

  String distanceFromHome(double meters) => meters >= 1000
      ? t('tr_dist_km', {'km': (meters / 1000).toStringAsFixed(1)})
      : t('tr_dist_m', {'m': meters.round()});

  /// Localized tracking headline composed from structured status fields.
  String trackingHeadline(ChildStatus status, String childName, DateTime now,
      {bool named = true}) {
    if (status.location == null || status.updatedAt == null) {
      // With no child added there is no name to decline into the sentence, so
      // the waiting line is written without one rather than reading
      // "Ожидание местоположения ребёнок…".
      return named ? t('tr_waiting', {'name': childName}) : t('tr_waiting_nochild');
    }
    final age = now.difference(status.updatedAt!);
    final agoStr = agoIfKnown(age);
    // No trustworthy age means no "last seen" clause to put in the sentence.
    if (agoStr == null) return t('tr_clock_skew', {'name': childName});
    if (status.freshness == Freshness.stale) {
      final phrase = age.inHours >= 1 ? t('stale_outdated') : t('stale_delayed');
      return t('tr_stale', {'name': childName, 'phrase': phrase, 'ago': agoStr});
    }
    if (status.currentZone != null) {
      return t('tr_at_zone', {'name': childName, 'zone': status.currentZone});
    }
    return t('tr_on_move', {'name': childName, 'ago': agoStr});
  }
}

/// All catalog keys (for the coverage test).
Iterable<String> get allL10nKeys => _catalog.keys;

/// For coverage: how many locales a key defines.
int localesDefinedFor(String key) => _catalog[key]?.length ?? 0;
