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

  // Geofence zones management
  'zones_title': {AppLocale.ru: 'Зоны {name}', AppLocale.kk: '{name} аймақтары', AppLocale.en: "{name}'s zones"},
  'zones_empty': {AppLocale.ru: 'Пока нет зон. Добавьте дом, школу или другое безопасное место.', AppLocale.kk: 'Әзірге аймақ жоқ. Үй, мектеп немесе басқа қауіпсіз орын қосыңыз.', AppLocale.en: 'No zones yet. Add home, school, or any safe place.'},
  'zone_add': {AppLocale.ru: 'Добавить зону', AppLocale.kk: 'Аймақ қосу', AppLocale.en: 'Add zone'},
  'zone_edit': {AppLocale.ru: 'Изменить зону', AppLocale.kk: 'Аймақты өзгерту', AppLocale.en: 'Edit zone'},
  'zone_name_hint': {AppLocale.ru: 'Название зоны', AppLocale.kk: 'Аймақ атауы', AppLocale.en: 'Zone name'},
  'zone_radius': {AppLocale.ru: 'Радиус', AppLocale.kk: 'Радиус', AppLocale.en: 'Radius'},
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
  'sleep_recent_nights': {AppLocale.ru: 'Последние ночи', AppLocale.kk: 'Соңғы түндер', AppLocale.en: 'Recent nights'},
  'sleep_deep': {AppLocale.ru: 'Глубокий', AppLocale.kk: 'Терең', AppLocale.en: 'Deep'},
  'sleep_rem': {AppLocale.ru: 'Быстрый', AppLocale.kk: 'REM', AppLocale.en: 'REM'},
  'sleep_light': {AppLocale.ru: 'Лёгкий', AppLocale.kk: 'Жеңіл', AppLocale.en: 'Light'},
  'sleep_awake': {AppLocale.ru: 'Бодрствование', AppLocale.kk: 'Ояу', AppLocale.en: 'Awake'},
  'sleep_efficiency': {AppLocale.ru: 'Эффективность', AppLocale.kk: 'Тиімділік', AppLocale.en: 'Efficiency'},
  'sleep_avg': {AppLocale.ru: 'В среднем за {n} ноч.', AppLocale.kk: '{n} түн орташа', AppLocale.en: 'Avg over {n} nights'},
  'sleep_title': {AppLocale.ru: 'Сон', AppLocale.kk: 'Ұйқы', AppLocale.en: 'Sleep'},
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
  'cyc_insights_title': {AppLocale.ru: 'Аналитика цикла', AppLocale.kk: 'Цикл аналитикасы', AppLocale.en: 'Cycle insights'},
  'cyc_settings_title': {AppLocale.ru: 'Настройки цикла', AppLocale.kk: 'Цикл параметрлері', AppLocale.en: 'Cycle settings'},
  'cyc_avg_cycle_label': {AppLocale.ru: 'Средняя длина цикла', AppLocale.kk: 'Орташа цикл ұзақтығы', AppLocale.en: 'Average cycle length'},
  'cyc_avg_period_label': {AppLocale.ru: 'Средняя длительность месячных', AppLocale.kk: 'Орташа етеккір ұзақтығы', AppLocale.en: 'Average period length'},
  'cyc_settings_hint': {AppLocale.ru: 'Используется для прогнозов, пока не накопится история циклов.', AppLocale.kk: 'Цикл тарихы жиналғанша болжам үшін қолданылады.', AppLocale.en: 'Used for predictions until you have logged a few cycles.'},
  'cyc_insights_empty': {AppLocale.ru: 'Отмечайте дни менструации, чтобы видеть статистику.', AppLocale.kk: 'Статистиканы көру үшін етеккір күндерін белгілеңіз.', AppLocale.en: 'Log period days to see your stats.'},
  'cyc_history': {AppLocale.ru: 'История циклов', AppLocale.kk: 'Цикл тарихы', AppLocale.en: 'Cycle history'},
  'cyc_cycles_tracked': {AppLocale.ru: 'Циклов', AppLocale.kk: 'Цикл', AppLocale.en: 'Cycles'},
  'cyc_avg_period_stat': {AppLocale.ru: 'Менструация', AppLocale.kk: 'Етеккір', AppLocale.en: 'Period'},
  'cyc_avg_cycle_stat': {AppLocale.ru: 'Цикл', AppLocale.kk: 'Цикл', AppLocale.en: 'Cycle'},
  'cyc_days_short': {AppLocale.ru: '{n} дн.', AppLocale.kk: '{n} к.', AppLocale.en: '{n}d'},
  'cyc_ongoing': {AppLocale.ru: 'Текущий', AppLocale.kk: 'Ағымдағы', AppLocale.en: 'Ongoing'},
  'cyc_period_len': {AppLocale.ru: 'менструация {n} дн.', AppLocale.kk: 'етеккір {n} күн', AppLocale.en: '{n}-day period'},
  'cyc_top_symptoms': {AppLocale.ru: 'Частые симптомы', AppLocale.kk: 'Жиі симптомдар', AppLocale.en: 'Common symptoms'},
  'cyc_top_moods': {AppLocale.ru: 'Настроение', AppLocale.kk: 'Көңіл-күй', AppLocale.en: 'Moods'},
  'cyc_times': {AppLocale.ru: '{n}×', AppLocale.kk: '{n}×', AppLocale.en: '{n}×'},
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
