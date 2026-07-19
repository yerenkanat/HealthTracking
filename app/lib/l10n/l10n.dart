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
  'ADV_ALL_STEADY_b': {AppLocale.ru: 'Ваши показатели в пределах нормы. Так держать.', AppLocale.kk: 'Көрсеткіштеріңіз қалыпты шамада. Осылай жалғастырыңыз.', AppLocale.en: 'Your readings are within a healthy range. Keep it up.'},
  'ADV_BP_STEADY': {AppLocale.ru: 'Давление в норме', AppLocale.kk: 'Қысым қалыпты', AppLocale.en: 'Blood pressure steady'},
  'ADV_BP_STEADY_b': {AppLocale.ru: 'Артериальное давление держится в здоровом диапазоне.', AppLocale.kk: 'Қан қысымы сау аралықта.', AppLocale.en: 'Your blood pressure is holding in a healthy range.'},
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
  'ADV_TEMP_STEADY': {AppLocale.ru: 'Температура в норме', AppLocale.kk: 'Температура қалыпты', AppLocale.en: 'Temperature is normal'},
  'ADV_TEMP_STEADY_b': {AppLocale.ru: 'Температура тела в пределах нормы.', AppLocale.kk: 'Дене температурасы қалыпты шамада.', AppLocale.en: 'Your body temperature is within a normal range.'},
  'ADV_HYDRATED': {AppLocale.ru: 'Водный баланс в норме', AppLocale.kk: 'Су балансы қалыпты', AppLocale.en: 'Well hydrated'},
  'ADV_HYDRATED_b': {AppLocale.ru: 'Вы выполнили дневную норму воды. Так держать!', AppLocale.kk: 'Күнделікті су нормасын орындадыңыз. Жалғастыра беріңіз!', AppLocale.en: "You've met today's water goal. Keep it up!"},
  'ADV_HYDRATE_LOW': {AppLocale.ru: 'Пора выпить воды', AppLocale.kk: 'Су ішетін кез', AppLocale.en: 'Time to hydrate'},
  'ADV_HYDRATE_LOW_b': {AppLocale.ru: 'До вечера выпито мало воды. Сделайте пару глотков.', AppLocale.kk: 'Кешке дейін су аз ішілді. Бірнеше жұтым жасаңыз.', AppLocale.en: "You're behind on water for today — have a glass or two."},
  'ADV_SPO2_STEADY': {AppLocale.ru: 'Кислород в норме', AppLocale.kk: 'Оттегі қалыпты', AppLocale.en: 'Healthy oxygen levels'},
  'ADV_SPO2_STEADY_b': {AppLocale.ru: 'Уровень кислорода в крови здоровый.', AppLocale.kk: 'Қандағы оттегі деңгейі сау.', AppLocale.en: 'Your blood oxygen has been at healthy levels.'},
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
  'set_export_hint': {AppLocale.ru: 'Скопируйте и сохраните в надёжном месте. Показания браслета не включены.', AppLocale.kk: 'Көшіріп, сенімді жерде сақтаңыз. Білезік көрсеткіштері кірмейді.', AppLocale.en: 'Copy and keep it somewhere safe. Band readings are not included.'},
  'set_export_copy': {AppLocale.ru: 'Копировать', AppLocale.kk: 'Көшіру', AppLocale.en: 'Copy'},
  'set_export_copied': {AppLocale.ru: 'Резервная копия скопирована', AppLocale.kk: 'Сақтық көшірме көшірілді', AppLocale.en: 'Backup copied to clipboard'},
  'set_import': {AppLocale.ru: 'Импорт данных', AppLocale.kk: 'Деректерді импорттау', AppLocale.en: 'Import data'},
  'set_import_sub': {AppLocale.ru: 'Восстановить из резервной копии', AppLocale.kk: 'Сақтық көшірмеден қалпына келтіру', AppLocale.en: 'Restore from a backup'},
  'set_import_warn': {AppLocale.ru: 'Импорт заменит все текущие данные.', AppLocale.kk: 'Импорт барлық ағымдағы деректерді ауыстырады.', AppLocale.en: 'Importing replaces all your current data.'},
  'set_import_hint': {AppLocale.ru: 'Вставьте JSON резервной копии сюда', AppLocale.kk: 'Мұнда JSON сақтық көшірмесін қойыңыз', AppLocale.en: 'Paste your backup JSON here'},
  'set_import_apply': {AppLocale.ru: 'Импортировать', AppLocale.kk: 'Импорттау', AppLocale.en: 'Import'},
  'set_import_ok': {AppLocale.ru: 'Данные восстановлены', AppLocale.kk: 'Деректер қалпына келтірілді', AppLocale.en: 'Data restored'},
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
  'onb_step': {AppLocale.ru: 'Шаг {n} из {total}', AppLocale.kk: '{total} қадамнан {n}', AppLocale.en: 'Step {n} of {total}'},

  // Emergency screen
  'em_title': {AppLocale.ru: 'Срочное предупреждение о здоровье', AppLocale.kk: 'Шұғыл денсаулық ескертуі', AppLocale.en: 'Urgent health alert'},
  'em_call_ambulance': {AppLocale.ru: 'Вызвать скорую', AppLocale.kk: 'Жедел жәрдем шақыру', AppLocale.en: 'Call ambulance'},
  'em_call_doctor': {AppLocale.ru: 'Позвонить врачу', AppLocale.kk: 'Дәрігерге қоңырау шалу', AppLocale.en: 'Call your doctor'},
  'em_not_emergency': {AppLocale.ru: 'Это не экстренная ситуация', AppLocale.kk: 'Бұл төтенше жағдай емес', AppLocale.en: "This isn't an emergency"},
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
  'setup_title': {AppLocale.ru: 'Завершите настройку', AppLocale.kk: 'Баптауды аяқтаңыз', AppLocale.en: 'Finish setting up'},
  'setup_name': {AppLocale.ru: 'Добавьте своё имя в профиле', AppLocale.kk: 'Профильде атыңызды қосыңыз', AppLocale.en: 'Add your name in your profile'},
  'setup_health': {AppLocale.ru: 'Укажите срок родов или отметьте месячные', AppLocale.kk: 'Босану мерзімін немесе етеккірді белгілеңіз', AppLocale.en: 'Set a due date or log your period'},
  'setup_child': {AppLocale.ru: 'Добавьте ребёнка', AppLocale.kk: 'Бала қосыңыз', AppLocale.en: 'Add a child'},
  'setup_zone': {AppLocale.ru: 'Создайте безопасную зону', AppLocale.kk: 'Қауіпсіз аймақ құрыңыз', AppLocale.en: 'Create a safe zone'},
  'setup_backup': {AppLocale.ru: 'Сделайте резервную копию данных', AppLocale.kk: 'Деректердің сақтық көшірмесін жасаңыз', AppLocale.en: 'Back up your data'},
  'db_week_title': {AppLocale.ru: 'Итоги недели', AppLocale.kk: 'Апта қорытындысы', AppLocale.en: 'This week'},
  'db_week_logged': {AppLocale.ru: 'дней отмечено', AppLocale.kk: 'күн белгіленді', AppLocale.en: 'days logged'},
  'db_week_water': {AppLocale.ru: 'стаканов · цель {n} дн.', AppLocale.kk: 'стакан · мақсат {n} күн', AppLocale.en: 'glasses · goal {n}d'},
  'db_week_sleep': {AppLocale.ru: 'сон в среднем', AppLocale.kk: 'орташа ұйқы', AppLocale.en: 'avg sleep'},
  'db_chip_pregnancy': {AppLocale.ru: 'Беременность · {n} нед.', AppLocale.kk: 'Жүктілік · {n}-апта', AppLocale.en: 'Pregnancy · Week {n}'},
  'share_status_cycle_late': {AppLocale.ru: 'Цикл · день {day} · задержка {n} дн.', AppLocale.kk: 'Цикл · {day}-күн · кешігу {n} күн', AppLocale.en: 'Cycle · day {day} · {n} days late'},
  'metric_hr': {AppLocale.ru: 'Пульс', AppLocale.kk: 'Жүрек соғысы', AppLocale.en: 'Heart rate'},
  'metric_spo2': {AppLocale.ru: 'Кислород в крови', AppLocale.kk: 'Қандағы оттегі', AppLocale.en: 'Blood oxygen'},
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
  'bsize_poppyseed': {AppLocale.ru: 'макового зёрнышка', AppLocale.kk: 'көкнәр дәні', AppLocale.en: 'poppy seed'},
  'bsize_sesame': {AppLocale.ru: 'кунжутного семечка', AppLocale.kk: 'күнжіт дәні', AppLocale.en: 'sesame seed'},
  'bsize_lentil': {AppLocale.ru: 'чечевицы', AppLocale.kk: 'жасымық', AppLocale.en: 'lentil'},
  'bsize_blueberry': {AppLocale.ru: 'черники', AppLocale.kk: 'көкжидек', AppLocale.en: 'blueberry'},
  'bsize_raspberry': {AppLocale.ru: 'малины', AppLocale.kk: 'таңқурай', AppLocale.en: 'raspberry'},
  'bsize_grape': {AppLocale.ru: 'виноградины', AppLocale.kk: 'жүзім', AppLocale.en: 'grape'},
  'bsize_strawberry': {AppLocale.ru: 'клубники', AppLocale.kk: 'құлпынай', AppLocale.en: 'strawberry'},
  'bsize_fig': {AppLocale.ru: 'инжира', AppLocale.kk: 'інжір', AppLocale.en: 'fig'},
  'bsize_lime': {AppLocale.ru: 'лайма', AppLocale.kk: 'лайм', AppLocale.en: 'lime'},
  'bsize_lemon': {AppLocale.ru: 'лимона', AppLocale.kk: 'лимон', AppLocale.en: 'lemon'},
  'bsize_peach': {AppLocale.ru: 'персика', AppLocale.kk: 'шабдалы', AppLocale.en: 'peach'},
  'bsize_avocado': {AppLocale.ru: 'авокадо', AppLocale.kk: 'авокадо', AppLocale.en: 'avocado'},
  'bsize_bellpepper': {AppLocale.ru: 'болгарского перца', AppLocale.kk: 'болгар бұрышы', AppLocale.en: 'bell pepper'},
  'bsize_banana': {AppLocale.ru: 'банана', AppLocale.kk: 'банан', AppLocale.en: 'banana'},
  'bsize_papaya': {AppLocale.ru: 'папайи', AppLocale.kk: 'папайя', AppLocale.en: 'papaya'},
  'bsize_corn': {AppLocale.ru: 'початка кукурузы', AppLocale.kk: 'жүгері собығы', AppLocale.en: 'ear of corn'},
  'bsize_lettuce': {AppLocale.ru: 'кочана салата', AppLocale.kk: 'салат басы', AppLocale.en: 'head of lettuce'},
  'bsize_eggplant': {AppLocale.ru: 'баклажана', AppLocale.kk: 'баялды', AppLocale.en: 'eggplant'},
  'bsize_cabbage': {AppLocale.ru: 'кочана капусты', AppLocale.kk: 'қырыжқабат', AppLocale.en: 'cabbage'},
  'bsize_squash': {AppLocale.ru: 'тыквы-кабачка', AppLocale.kk: 'асқабақ', AppLocale.en: 'squash'},
  'bsize_cantaloupe': {AppLocale.ru: 'дыни-канталупы', AppLocale.kk: 'қауын (канталупа)', AppLocale.en: 'cantaloupe'},
  'bsize_honeydew': {AppLocale.ru: 'медовой дыни', AppLocale.kk: 'бал қауын', AppLocale.en: 'honeydew melon'},
  'bsize_pumpkin': {AppLocale.ru: 'небольшой тыквы', AppLocale.kk: 'кішкене асқабақ', AppLocale.en: 'small pumpkin'},
  'bsize_watermelon': {AppLocale.ru: 'арбуза', AppLocale.kk: 'қарбыз', AppLocale.en: 'watermelon'},
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

  /// Localized "x ago" — mirrors the buckets in child_tracker_state.formatAgo.
  String ago(Duration age) {
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
    final agoStr = ago(age);
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
