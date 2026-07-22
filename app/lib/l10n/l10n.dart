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
  'nav_health': {AppLocale.ru: 'Здоровье', AppLocale.kk: 'Денсаулық', AppLocale.en: 'Health'},
  'nav_assistant': {AppLocale.ru: 'Помощник', AppLocale.kk: 'Көмекші', AppLocale.en: 'Assistant'},
  'nav_child': {AppLocale.ru: 'Ребёнок', AppLocale.kk: 'Бала', AppLocale.en: 'Child'},
  'nav_profile': {AppLocale.ru: 'Профиль', AppLocale.kk: 'Профиль', AppLocale.en: 'Profile'},

  // Assistant chat
  'chat_title': {AppLocale.ru: 'Умай — помощник', AppLocale.kk: 'Умай — көмекші', AppLocale.en: 'Umay — assistant'},
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
  'ADV_GATHERING': {AppLocale.ru: 'Собираем данные', AppLocale.kk: 'Деректер жиналуда', AppLocale.en: 'Gathering data'},
  'ADV_GATHERING_b': {AppLocale.ru: 'Наденьте браслет — советы появятся после нескольких измерений.', AppLocale.kk: 'Білезікті тағыңыз — бірнеше өлшеуден кейін кеңестер пайда болады.', AppLocale.en: 'Wear your band — advice appears after a few readings.'},
  'ADV_ALL_STEADY': {AppLocale.ru: 'Всё стабильно', AppLocale.kk: 'Барлығы тұрақты', AppLocale.en: 'All steady'},
  'ADV_ALL_STEADY_b': {AppLocale.ru: 'Показания браслета держатся ровно. Так держать.', AppLocale.kk: 'Білезік көрсеткіштері біркелкі. Осылай жалғастырыңыз.', AppLocale.en: 'Your band readings have been steady. Keep it up.'},
  'ADV_BP_STEADY': {AppLocale.ru: 'Давление ровное', AppLocale.kk: 'Қысым біркелкі', AppLocale.en: 'Blood pressure steady'},
  'ADV_BP_STEADY_b': {AppLocale.ru: 'Давление по браслету держится ровно, без скачков.', AppLocale.kk: 'Білезік бойынша қысым секірмей, біркелкі.', AppLocale.en: 'Your blood-pressure readings have held steady, without spikes.'},
  'ADV_BP_ELEVATED': {AppLocale.ru: 'Следите за давлением', AppLocale.kk: 'Қысымды қадағалаңыз', AppLocale.en: 'Watch your blood pressure'},
  'ADV_BP_ELEVATED_b': {AppLocale.ru: 'Давление повышено. Отдохните, выпейте воды и измерьте снова. При стойком повышении обратитесь к врачу.', AppLocale.kk: 'Қысым жоғарылаған. Демалыңыз, су ішіп, қайта өлшеңіз. Тұрақты жоғары болса, дәрігерге жүгініңіз.', AppLocale.en: 'Your blood pressure is elevated. Rest, hydrate, and re-measure. If it stays high, contact your doctor.'},
  'ADV_HR_STEADY': {AppLocale.ru: 'Пульс ровный', AppLocale.kk: 'Тамыр соғысы тұрақты', AppLocale.en: 'Heart rate steady'},
  'ADV_HR_STEADY_b': {AppLocale.ru: 'Частота сердечных сокращений стабильна.', AppLocale.kk: 'Жүрек соғу жиілігі тұрақты.', AppLocale.en: 'Your heart rate is stable.'},
  'ADV_HR_RISING': {AppLocale.ru: 'Пульс растёт', AppLocale.kk: 'Тамыр соғысы артып барады', AppLocale.en: 'Heart rate rising'},
  'ADV_HR_RISING_b': {AppLocale.ru: 'Средний пульс вырос за последнее время. Отдохните; при беспокойстве обратитесь к врачу.', AppLocale.kk: 'Соңғы кезде орташа тамыр соғысы өсті. Демалыңыз; алаңдасаңыз дәрігерге жүгініңіз.', AppLocale.en: 'Your average heart rate has risen recently. Rest; if concerned, see your doctor.'},
  'ADV_SPO2_SLEEP_DIP': {AppLocale.ru: 'Кислород во сне', AppLocale.kk: 'Ұйқыдағы оттегі', AppLocale.en: 'Oxygen during sleep'},
  'ADV_SPO2_SLEEP_DIP_b': {AppLocale.ru: 'Во сне уровень кислорода опускался ниже 95%. Если повторяется — обсудите с врачом.', AppLocale.kk: 'Ұйқы кезінде оттегі деңгейі 95%-дан төмендеді. Қайталанса, дәрігермен ақылдасыңыз.', AppLocale.en: 'Your blood oxygen dipped below 95% during sleep. If it recurs, discuss with your doctor.'},
  'ADV_TEMP_ELEVATED': {AppLocale.ru: 'Повышенная температура', AppLocale.kk: 'Дене қызуы жоғары', AppLocale.en: 'Elevated temperature'},
  'ADV_TEMP_ELEVATED_b': {AppLocale.ru: 'Температура выше нормы. Отдых и питьё; следите за динамикой.', AppLocale.kk: 'Температура қалыптыдан жоғары. Демалыс пен сұйықтық; өзгерісті бақылаңыз.', AppLocale.en: 'Your temperature is above normal. Rest and hydrate; keep an eye on it.'},
  'ADV_TEMP_STEADY': {AppLocale.ru: 'Температура ровная', AppLocale.kk: 'Дене қызуы біркелкі', AppLocale.en: 'Temperature steady'},
  'ADV_TEMP_STEADY_b': {AppLocale.ru: 'Температура по браслету держится ровно.', AppLocale.kk: 'Білезік бойынша дене қызуы біркелкі.', AppLocale.en: 'Your temperature readings have held steady.'},
  'ADV_HYDRATED': {AppLocale.ru: 'Водный баланс в норме', AppLocale.kk: 'Су балансы қалыпты', AppLocale.en: 'Well hydrated'},
  'ADV_HYDRATED_b': {AppLocale.ru: 'Вы выполнили дневную норму воды. Так держать!', AppLocale.kk: 'Күнделікті су нормасын орындадыңыз. Жалғастыра беріңіз!', AppLocale.en: "You've met today's water goal. Keep it up!"},
  'ADV_HYDRATE_LOW': {AppLocale.ru: 'Пора выпить воды', AppLocale.kk: 'Су ішетін кез', AppLocale.en: 'Time to hydrate'},
  'ADV_HYDRATE_LOW_b': {AppLocale.ru: 'До вечера выпито мало воды. Сделайте пару глотков.', AppLocale.kk: 'Кешке дейін су аз ішілді. Бірнеше жұтым жасаңыз.', AppLocale.en: "You're behind on water for today — have a glass or two."},
  'ADV_SPO2_STEADY': {AppLocale.ru: 'Кислород ровный', AppLocale.kk: 'Оттегі біркелкі', AppLocale.en: 'Oxygen steady'},
  'ADV_SPO2_STEADY_b': {AppLocale.ru: 'Кислород по браслету держится ровно.', AppLocale.kk: 'Білезік бойынша оттегі біркелкі.', AppLocale.en: 'Your oxygen readings have held steady.'},
  'ADV_SLEEP_OK': {AppLocale.ru: 'Спокойный сон', AppLocale.kk: 'Тыныш ұйқы', AppLocale.en: 'Restful sleep'},
  'ADV_SLEEP_OK_b': {AppLocale.ru: 'Во сне показатели были стабильны — хороший отдых.', AppLocale.kk: 'Ұйқы кезінде көрсеткіштер тұрақты болды — жақсы демалыс.', AppLocale.en: 'Your readings were stable during sleep — a good rest.'},

  // Onboarding
  'onb_welcome_title': {AppLocale.ru: 'Добро пожаловать в Умай', AppLocale.kk: 'Умайға қош келдіңіз', AppLocale.en: 'Welcome to Umay'},
  'onb_welcome_body': {AppLocale.ru: 'Спокойный уход за беременностью и безопасность ребёнка в одном приложении.', AppLocale.kk: 'Жүктілікке қамқорлық пен бала қауіпсіздігі бір қолданбада.', AppLocale.en: 'Calm pregnancy care and child safety in one app.'},
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
  'tr_manage_zones': {AppLocale.ru: 'Зоны безопасности', AppLocale.kk: 'Қауіпсіздік аймақтары', AppLocale.en: 'Safe zones'},

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
  'alerts_filter_battery': {AppLocale.ru: 'Заряд', AppLocale.kk: 'Заряд', AppLocale.en: 'Battery'},
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

  // Geofence zones management
  'zones_title': {AppLocale.ru: 'Зоны {name}', AppLocale.kk: '{name} аймақтары', AppLocale.en: "{name}'s zones"},
  'zones_empty': {AppLocale.ru: 'Пока нет зон. Добавьте дом, школу или другое безопасное место.', AppLocale.kk: 'Әзірге аймақ жоқ. Үй, мектеп немесе басқа қауіпсіз орын қосыңыз.', AppLocale.en: 'No zones yet. Add home, school, or any safe place.'},
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
  'set_notifications_sub': {AppLocale.ru: 'Оповещения о входе и выходе из зон', AppLocale.kk: 'Аймаққа кіру/шығу туралы ескертулер', AppLocale.en: 'Zone entry and exit alerts'},
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
    AppLocale.ru: 'Резервная копия Umay',
    AppLocale.kk: 'Umay сақтық көшірмесі',
    AppLocale.en: 'Umay backup'
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
    AppLocale.ru: 'Умай — уход за беременностью и безопасность ребёнка. Не является медицинским прибором.',
    AppLocale.kk: 'Умай — жүктілікке қамқорлық және бала қауіпсіздігі. Медициналық құрал емес.',
    AppLocale.en: 'Umay — pregnancy care and child safety. Not a medical device.'
  },
  'set_version': {AppLocale.ru: 'Версия', AppLocale.kk: 'Нұсқа', AppLocale.en: 'Version'},
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
  'db_share_copied': {AppLocale.ru: 'Сводка скопирована', AppLocale.kk: 'Қорытынды көшірілді', AppLocale.en: 'Summary copied to clipboard'},
  'share_summary_title': {AppLocale.ru: 'Сводка здоровья · Umay', AppLocale.kk: 'Денсаулық қорытындысы · Umay', AppLocale.en: 'Health summary · Umay'},
  'share_summary_notes': {AppLocale.ru: 'Заметки', AppLocale.kk: 'Ескертпелер', AppLocale.en: 'Notes'},
  'share_summary_nodata': {AppLocale.ru: 'Пока нет данных', AppLocale.kk: 'Әзірге дерек жоқ', AppLocale.en: 'No readings yet'},
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
  'vitals_systolic': {AppLocale.ru: 'Верхнее (мм рт. ст.)', AppLocale.kk: 'Жоғарғы (мм с.б.)', AppLocale.en: 'Systolic (mmHg)'},
  'vitals_diastolic': {AppLocale.ru: 'Нижнее (мм рт. ст.)', AppLocale.kk: 'Төменгі (мм с.б.)', AppLocale.en: 'Diastolic (mmHg)'},
  'vitals_hr': {AppLocale.ru: 'Пульс (уд/мин)', AppLocale.kk: 'Тамыр соғуы (соқ/мин)', AppLocale.en: 'Heart rate (bpm)'},
  'vitals_spo2': {AppLocale.ru: 'Сатурация (%)', AppLocale.kk: 'Қанықтық (%)', AppLocale.en: 'Blood oxygen (%)'},
  'vitals_temp': {AppLocale.ru: 'Температура (°C)', AppLocale.kk: 'Температура (°C)', AppLocale.en: 'Temperature (°C)'},
  'vitals_err_range': {AppLocale.ru: 'Одно из значений вне допустимого диапазона — проверьте ввод.', AppLocale.kk: 'Мәндердің бірі рұқсат етілген ауқымнан тыс — тексеріңіз.', AppLocale.en: 'One of the values is outside the plausible range — please check it.'},
  'vitals_err_bp_pair': {AppLocale.ru: 'Укажите оба значения давления — верхнее и нижнее.', AppLocale.kk: 'Қысымның екі мәнін де көрсетіңіз.', AppLocale.en: 'Enter both blood-pressure values, upper and lower.'},
  'vitals_err_bp_order': {AppLocale.ru: 'Нижнее давление должно быть меньше верхнего — возможно, они переставлены.', AppLocale.kk: 'Төменгі қысым жоғарғыдан кіші болуы керек — орындары ауысып кеткен шығар.', AppLocale.en: 'The lower value must be below the upper one — they may be swapped.'},
  'vitals_saved': {AppLocale.ru: 'Показатели записаны', AppLocale.kk: 'Көрсеткіштер жазылды', AppLocale.en: 'Reading saved'},
  'setup_title': {AppLocale.ru: 'Завершите настройку', AppLocale.kk: 'Баптауды аяқтаңыз', AppLocale.en: 'Finish setting up'},
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
  'metric_temp': {AppLocale.ru: 'Температура', AppLocale.kk: 'Температура', AppLocale.en: 'Temperature'},
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
  'metric_bp': {AppLocale.ru: 'Давление', AppLocale.kk: 'Қан қысымы', AppLocale.en: 'Blood pressure'},
  'db_peace_stable': {AppLocale.ru: 'Всё стабильно, {name}', AppLocale.kk: 'Барлығы тұрақты, {name}', AppLocale.en: 'Everything is stable, {name}'},
  'db_peace_stable_noname': {AppLocale.ru: 'Всё выглядит стабильно', AppLocale.kk: 'Барлығы тұрақты көрінеді', AppLocale.en: 'Everything looks stable'},
  'db_peace_stable_b': {AppLocale.ru: 'Ваши показатели в пределах нормы.', AppLocale.kk: 'Көрсеткіштеріңіз қалыпты шамада.', AppLocale.en: 'Your readings are within a healthy range.'},
  'db_advisor_cta': {AppLocale.ru: 'Спросите Умай о ваших данных', AppLocale.kk: 'Умайдан деректеріңіз туралы сұраңыз', AppLocale.en: 'Ask Umay about your readings'},
  'db_advisor_sub': {AppLocale.ru: 'Аналитика по данным браслета', AppLocale.kk: 'Білезік деректеріне талдау', AppLocale.en: 'Insights from your band data'},

  // Women's-health calendar
  'nav_calendar': {AppLocale.ru: 'Календарь', AppLocale.kk: 'Күнтізбе', AppLocale.en: 'Calendar'},
  'cal_screen_title': {AppLocale.ru: 'Женское здоровье', AppLocale.kk: 'Әйел денсаулығы', AppLocale.en: "Women's health"},
  'cal_no_due_title': {AppLocale.ru: 'Добавьте срок беременности', AppLocale.kk: 'Жүктілік мерзімін қосыңыз', AppLocale.en: 'Add your due date'},
  'cal_no_due_body': {
    AppLocale.ru: 'Укажите предполагаемую дату родов, чтобы отслеживать неделю беременности.',
    AppLocale.kk: 'Болжамды босану күнін көрсетіп, жүктілік аптасын қадағалаңыз.',
    AppLocale.en: 'Set your estimated due date to track your pregnancy week.'
  },
  'cal_due_pick': {AppLocale.ru: 'Дата родов', AppLocale.kk: 'Босану күні', AppLocale.en: 'Due date'},
  'gest_week': {AppLocale.ru: 'Неделя {w}, день {d}', AppLocale.kk: '{w}-апта, {d}-күн', AppLocale.en: 'Week {w}, Day {d}'},
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
  'pp_note_lochia_fading': {
    AppLocale.ru: 'Выделения светлеют: розовые, затем коричневые, затем кремовые. Внезапный возврат ярко-красной крови — повод отдохнуть и понаблюдать.',
    AppLocale.kk: 'Бөліністер ашылады: қызғылт, содан қоңыр, кейін кремді түске енеді. Ашық қызыл қанның кенеттен қайта пайда болуы — демалып, бақылауға белгі.',
    AppLocale.en: 'The bleeding lightens — pink, then brown, then creamy. A sudden return to bright red is a sign to rest and keep an eye on it.',
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
  'vac_dtp': {AppLocale.ru: 'АКДС (ревакцинация)', AppLocale.kk: 'АКДС (ревакцинация)', AppLocale.en: 'DTP booster'},
  'vac_dtp_note': {AppLocale.ru: 'Поддерживает защиту от дифтерии, столбняка и коклюша.', AppLocale.kk: 'Дифтерия, сіреспе және көкжөтелден қорғанысты сақтайды.', AppLocale.en: 'Keeps up protection against diphtheria, tetanus and whooping cough.'},
  'vac_hib': {AppLocale.ru: 'Гемофильная инфекция (ревакцинация)', AppLocale.kk: 'Гемофильді инфекция (ревакцинация)', AppLocale.en: 'Hib booster'},
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
  'kick_goal_reached': {AppLocale.ru: 'Цель достигнута 🎉', AppLocale.kk: 'Мақсатқа жетті 🎉', AppLocale.en: 'Goal reached 🎉'},
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
  'weight_target_reached': {AppLocale.ru: 'Цель достигнута 🎉', AppLocale.kk: 'Мақсатқа жетті 🎉', AppLocale.en: 'Target reached 🎉'},
  'weight_target_clear': {AppLocale.ru: 'Убрать цель', AppLocale.kk: 'Мақсатты жою', AppLocale.en: 'Clear target'},
  'weight_history_title': {AppLocale.ru: 'История веса', AppLocale.kk: 'Салмақ тарихы', AppLocale.en: 'Weight history'},
  'weight_delete_title': {AppLocale.ru: 'Удалить запись?', AppLocale.kk: 'Жазбаны жою керек пе?', AppLocale.en: 'Delete this entry?'},
  'weight_delete_body': {AppLocale.ru: 'Запись {kg} кг будет удалена.', AppLocale.kk: '{kg} кг жазбасы жойылады.', AppLocale.en: 'The {kg} kg entry will be removed.'},

  // Hydration (daily water)
  'water_title': {AppLocale.ru: 'Вода', AppLocale.kk: 'Су', AppLocale.en: 'Water'},
  'water_progress': {AppLocale.ru: '{n} из {goal} стаканов', AppLocale.kk: '{goal} стақаннан {n}', AppLocale.en: '{n} of {goal} glasses'},
  'water_goal_met': {AppLocale.ru: 'Дневная норма выполнена 🎉', AppLocale.kk: 'Күнделікті норма орындалды 🎉', AppLocale.en: 'Daily goal reached 🎉'},
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
  'med_reminder_body': {AppLocale.ru: 'Отметьте сегодняшние приёмы в Umay.', AppLocale.kk: 'Бүгінгі қабылдауды Umay-да белгілеңіз.', AppLocale.en: 'Tick off today\'s doses in Umay.'},
  'rem_footer': {AppLocale.ru: 'Напоминания приходят как обычные уведомления. Их можно отключить в любой момент здесь.', AppLocale.kk: 'Еске салулар қарапайым хабарландыру ретінде келеді. Оларды кез келген уақытта осы жерде өшіруге болады.', AppLocale.en: 'Reminders arrive as ordinary notifications. You can turn any of them off here at any time.'},
  'rem_manage_hint': {AppLocale.ru: 'Напоминания о цикле — в разделе «Настройки → Напоминания».', AppLocale.kk: 'Цикл еске салулары «Параметрлер → Еске салулар» бөлімінде.', AppLocale.en: 'Manage cycle reminders in Settings › Reminders.'},
  'water_reminder_title': {AppLocale.ru: 'Время попить воды 💧', AppLocale.kk: 'Су ішу уақыты 💧', AppLocale.en: 'Time to drink water 💧'},
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
  'cyc_share_title': {AppLocale.ru: 'Прогноз цикла · Umay', AppLocale.kk: 'Цикл болжамы · Umay', AppLocale.en: 'Cycle forecast · Umay'},
  'cyc_share_nodata': {AppLocale.ru: 'Пока недостаточно данных для прогноза', AppLocale.kk: 'Болжам үшін дерек әлі жеткіліксіз', AppLocale.en: 'Not enough data to predict yet'},
  'cyc_share_disclaimer': {AppLocale.ru: 'Оценка для самочувствия, не средство контрацепции.', AppLocale.kk: 'Бұл — болжам, контрацепция құралы емес.', AppLocale.en: 'Wellness estimate, not contraception guidance.'},
  'cyc_insights_title': {AppLocale.ru: 'Аналитика цикла', AppLocale.kk: 'Цикл аналитикасы', AppLocale.en: 'Cycle insights'},
  'period_reminder': {AppLocale.ru: 'Напоминание о месячных', AppLocale.kk: 'Етеккір туралы еске салу', AppLocale.en: 'Period reminder'},
  'period_reminder_sub': {AppLocale.ru: 'За 2 дня до предполагаемого начала', AppLocale.kk: 'Болжамды басталуға 2 күн қалғанда', AppLocale.en: '2 days before the expected start'},
  'period_reminder_title': {AppLocale.ru: 'Скоро месячные 🌸', AppLocale.kk: 'Етеккір жақындады 🌸', AppLocale.en: 'Period coming soon 🌸'},
  'period_reminder_body': {AppLocale.ru: 'По прогнозу месячные начнутся примерно через 2 дня.', AppLocale.kk: 'Болжам бойынша етеккір шамамен 2 күнде басталады.', AppLocale.en: 'Your period is predicted to start in about 2 days.'},
  'fertile_reminder': {AppLocale.ru: 'Напоминание о фертильном окне', AppLocale.kk: 'Фертильді терезе туралы еске салу', AppLocale.en: 'Fertile window reminder'},
  'fertile_reminder_sub': {AppLocale.ru: 'В день начала фертильного окна', AppLocale.kk: 'Фертильді терезе басталған күні', AppLocale.en: 'On the day the fertile window opens'},
  'fertile_reminder_title': {AppLocale.ru: 'Начинается фертильное окно 🌱', AppLocale.kk: 'Фертильді терезе басталады 🌱', AppLocale.en: 'Fertile window is opening 🌱'},
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
    AppLocale.ru: 'Umay не может определить, насколько свежие данные о местоположении {name} — часы телефона и трекера расходятся',
    AppLocale.kk: 'Umay {name} орналасуының қаншалықты жаңа екенін анықтай алмайды — телефон мен трекердің уақыты сәйкес келмейді',
    AppLocale.en: "Umay can't tell how old {name}'s location is — the phone and the tracker disagree about the time",
  },
  'stale_delayed': {AppLocale.ru: 'задерживается', AppLocale.kk: 'кешігуде', AppLocale.en: 'delayed'},
  'stale_outdated': {AppLocale.ru: 'устарело', AppLocale.kk: 'ескірген', AppLocale.en: 'out of date'},

  // Relative time
  'ago_just_now': {AppLocale.ru: 'только что', AppLocale.kk: 'дәл қазір', AppLocale.en: 'just now'},
  'ago_lt_minute': {AppLocale.ru: 'меньше минуты назад', AppLocale.kk: 'бір минуттан аз уақыт бұрын', AppLocale.en: 'less than a minute ago'},
  'ago_min': {AppLocale.ru: '{n} мин назад', AppLocale.kk: '{n} мин бұрын', AppLocale.en: '{n} min ago'},
  'ago_hour': {AppLocale.ru: '{n} ч назад', AppLocale.kk: '{n} сағ бұрын', AppLocale.en: '{n} h ago'},
  'ago_day': {AppLocale.ru: '{n} дн назад', AppLocale.kk: '{n} күн бұрын', AppLocale.en: '{n} d ago'},

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
  String trackingHeadline(ChildStatus status, String childName, DateTime now) {
    if (status.location == null || status.updatedAt == null) {
      return t('tr_waiting', {'name': childName});
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
