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
  'onb_country': {AppLocale.ru: 'Страна', AppLocale.kk: 'Ел', AppLocale.en: 'Country'},
  'tr_add_child': {AppLocale.ru: 'Добавить ребёнка', AppLocale.kk: 'Бала қосу', AppLocale.en: 'Add child'},
  'tr_add_device': {AppLocale.ru: 'Добавить устройство', AppLocale.kk: 'Құрылғы қосу', AppLocale.en: 'Add device'},
  'dev_band': {AppLocale.ru: 'Умный браслет', AppLocale.kk: 'Ақылды білезік', AppLocale.en: 'Smart band'},
  'dev_tag': {AppLocale.ru: 'Трекер-метка', AppLocale.kk: 'Трекер-белгі', AppLocale.en: 'Tracker tag'},
  'dev_id_hint': {AppLocale.ru: 'ID устройства', AppLocale.kk: 'Құрылғы ID', AppLocale.en: 'Device ID'},
  'dev_name_hint': {AppLocale.ru: 'Название', AppLocale.kk: 'Атауы', AppLocale.en: 'Name'},
  'act_save': {AppLocale.ru: 'Сохранить', AppLocale.kk: 'Сақтау', AppLocale.en: 'Save'},
  'act_cancel': {AppLocale.ru: 'Отмена', AppLocale.kk: 'Бас тарту', AppLocale.en: 'Cancel'},
  'act_edit': {AppLocale.ru: 'Изменить', AppLocale.kk: 'Өзгерту', AppLocale.en: 'Edit'},
  'act_remove': {AppLocale.ru: 'Удалить', AppLocale.kk: 'Жою', AppLocale.en: 'Remove'},

  // Settings
  'settings_title': {AppLocale.ru: 'Настройки', AppLocale.kk: 'Параметрлер', AppLocale.en: 'Settings'},
  'set_profile': {AppLocale.ru: 'Профиль', AppLocale.kk: 'Профиль', AppLocale.en: 'Profile'},
  'set_edit_profile': {AppLocale.ru: 'Изменить профиль', AppLocale.kk: 'Профильді өзгерту', AppLocale.en: 'Edit profile'},
  'set_language': {AppLocale.ru: 'Язык', AppLocale.kk: 'Тіл', AppLocale.en: 'Language'},
  'set_children': {AppLocale.ru: 'Дети', AppLocale.kk: 'Балалар', AppLocale.en: 'Children'},
  'set_devices': {AppLocale.ru: 'Устройства', AppLocale.kk: 'Құрылғылар', AppLocale.en: 'Devices'},
  'set_no_devices': {AppLocale.ru: 'Нет устройств', AppLocale.kk: 'Құрылғылар жоқ', AppLocale.en: 'No devices yet'},
  'set_about': {AppLocale.ru: 'О приложении', AppLocale.kk: 'Қолданба туралы', AppLocale.en: 'About'},
  'set_about_body': {
    AppLocale.ru: 'Умай — уход за беременностью и безопасность ребёнка. Не является медицинским прибором.',
    AppLocale.kk: 'Умай — жүктілікке қамқорлық және бала қауіпсіздігі. Медициналық құрал емес.',
    AppLocale.en: 'Umay — pregnancy care and child safety. Not a medical device.'
  },
  'set_version': {AppLocale.ru: 'Версия', AppLocale.kk: 'Нұсқа', AppLocale.en: 'Version'},
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
  'db_greeting': {AppLocale.ru: 'Здравствуйте, {name}', AppLocale.kk: 'Сәлеметсіз бе, {name}', AppLocale.en: 'Hi, {name}'},
  'metric_hr': {AppLocale.ru: 'Пульс', AppLocale.kk: 'Жүрек соғысы', AppLocale.en: 'Heart rate'},
  'metric_spo2': {AppLocale.ru: 'Кислород в крови', AppLocale.kk: 'Қандағы оттегі', AppLocale.en: 'Blood oxygen'},
  'metric_systolic': {AppLocale.ru: 'Систолическое', AppLocale.kk: 'Систолалық', AppLocale.en: 'Systolic'},
  'metric_diastolic': {AppLocale.ru: 'Диастолическое', AppLocale.kk: 'Диастолалық', AppLocale.en: 'Diastolic'},
  'metric_temp': {AppLocale.ru: 'Температура', AppLocale.kk: 'Температура', AppLocale.en: 'Temperature'},
  'db_empty_title': {AppLocale.ru: 'Пока нет данных', AppLocale.kk: 'Әзірге деректер жоқ', AppLocale.en: 'No readings yet'},
  'db_empty_body': {AppLocale.ru: 'Наденьте браслет — и данные появятся здесь.', AppLocale.kk: 'Білезікті тағыңыз — деректер осында пайда болады.', AppLocale.en: 'Put on your band and readings will appear here.'},
  'db_stats': {AppLocale.ru: 'мин {min} · макс {max} · сред {avg}', AppLocale.kk: 'мин {min} · макс {max} · орт {avg}', AppLocale.en: 'min {min} · max {max} · avg {avg}'},
  'db_outside_range': {AppLocale.ru: ', вне безопасного диапазона', AppLocale.kk: ', қауіпсіз аралықтан тыс', AppLocale.en: ', outside the safe range'},

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
