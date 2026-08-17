/**
 * Frames 24 / 24a / 24b — «Интеграции», «Настроить», «Проверить связь».
 *
 * WHAT THIS SCREEN IS FOR
 *
 * Every outside service this product depends on, and — for each — whether it is
 * actually wired, what breaks while it is not, and what would have to be
 * supplied to fix it. Nothing here guesses: a key is either stored or it is
 * not, a sender is either injected or it is not.
 *
 * The honest answer today is that three of them are OFF, and two of those are
 * load-bearing. Phone sign-in cannot send a code, because `smsSender()` returns
 * a console logger and nothing else; push cannot deliver, because no sender is
 * wired. Both fail SILENTLY at the point of use — the user sees a code field
 * that no code arrives for — so a screen that says so is the difference between
 * a known gap and a mystery.
 *
 * ON SECRETS. Nothing here returns a key. A stored key becomes `••••7f2a`: the
 * last four characters, which is enough to tell two keys apart and to confirm
 * that the one in the panel is the one from the dashboard, and useless to
 * anyone reading over a shoulder.
 *
 * GET /admin/settings used to return the real values — the Anthropic key and
 * the Telegram bot token travelled to the browser in plaintext and sat in an
 * `<input>` on the Магазин screen, readable by anybody who could open it or
 * read the response in a devtools tab. It does not any more: `redactSettings()`
 * below strips every secret out of that response too, and the same `••••7f2a`
 * is all either screen ever sees.
 *
 * PURE: settings and a few booleans in, a list of statuses out.
 */

/** How well an integration is doing. Three states, not two. */
export type IntegrationState =
  /** Configured, and nothing suggests it is failing. */
  | 'ok'
  /** Partly configured — it will half-work, which is worse than off. */
  | 'partial'
  /** Not configured. Whatever depends on it does not happen. */
  | 'off';

export interface IntegrationStatus {
  id: string;
  /** What an operator calls it. */
  name: string;
  /** One line: what it is FOR. */
  purpose: string;
  state: IntegrationState;
  /** What is true right now, in a sentence. */
  detail: string;
  /**
   * What does not work while this is off. Empty when it is working.
   *
   * The most important field on the screen: «нет ключа» tells an operator
   * nothing, «мама не получит код и не сможет войти» tells her whether to
   * escalate tonight.
   */
  breaks: string;
  /** What has to be supplied. Empty when nothing is needed. */
  needs: string[];
  /** Masked, never the value. Null when nothing is stored. */
  secret: string | null;
  /** Whether 24b can run a live check against it. */
  checkable: boolean;
}

/**
 * `••••7f2a` — the last four characters of a secret.
 *
 * A secret too short to mask is shown as all dots rather than partly revealed:
 * a four-character key would otherwise be printed in full.
 */
export function maskSecret(value: string | null | undefined): string | null {
  const v = (value ?? '').trim();
  if (!v) return null;
  if (v.length <= 6) return '••••';
  return `••••${v.slice(-4)}`;
}

/**
 * The settings whose VALUE must never leave the server.
 *
 * `googleMapsApiKey` is here as well even though nothing writes it any more:
 * a row saved before the field was withdrawn is still in the table, and
 * redacting it costs nothing while leaking it costs a key.
 */
export const SECRET_SETTING_KEYS = [
  'anthropicApiKey',
  'telegramBotToken',
  'googleMapsApiKey',
] as const;

export type SecretSettingKey = (typeof SECRET_SETTING_KEYS)[number];

export interface SecretView {
  /** Whether a value is stored at all. */
  stored: boolean;
  /** `••••7f2a`, or null when nothing is stored. Never the value. */
  mask: string | null;
}

export interface RedactedSettings {
  /** Everything that is not a secret, verbatim. */
  settings: Record<string, string>;
  /** One entry per secret key, always present so the form can say «не сохранён». */
  secrets: Record<SecretSettingKey, SecretView>;
}

/**
 * Split a settings map into what may be shown and what may only be counted.
 *
 * Every secret key gets an entry whether or not it is stored: a form that has
 * to distinguish «ключ сохранён» from «ключа нет» cannot do it from a missing
 * property, and an absent entry reads as «нет» — which is how somebody retypes
 * a key that was already correct.
 */
export function redactSettings(all: Record<string, string> | null | undefined): RedactedSettings {
  const src = all ?? {};
  const settings: Record<string, string> = {};
  for (const [k, v] of Object.entries(src)) {
    if ((SECRET_SETTING_KEYS as readonly string[]).includes(k)) continue;
    settings[k] = v;
  }
  const secrets = {} as Record<SecretSettingKey, SecretView>;
  for (const k of SECRET_SETTING_KEYS) {
    const mask = maskSecret(src[k]);
    secrets[k] = { stored: mask !== null, mask };
  }
  return { settings, secrets };
}

/**
 * Whether a submitted secret is the MASK coming back, not a new value.
 *
 * This is the whole difference between a mask that protects a key and a mask
 * that destroys one. Put `••••7f2a` in the box, let somebody open the form to
 * change an unrelated field, and a naive save writes eight bullet characters
 * over the real key — silently, completely, and with a green «Сохранено» on
 * screen. Nothing would say so until the assistant stopped answering.
 *
 * The test is the bullet itself: U+2022 cannot occur in an Anthropic key or a
 * BotFather token, both of which are ASCII, so a value containing one was
 * never typed by a person. Such a value means «оставить как есть», never
 * «записать это».
 *
 * An EMPTY string is not masked and is not ignored — clearing a key on purpose
 * has to stay possible, and the panel confirms before it does.
 */
export function looksMasked(value: string | null | undefined): boolean {
  return (value ?? '').includes('•');
}

export interface IntegrationInputs {
  /** The shop_settings key/value map. */
  settings: Record<string, string>;
  /** Whether a REAL sms sender is wired (not the console logger). */
  smsSenderIsReal: boolean;
  /** Whether phone codes are demanded at sign-in — the EFFECTIVE gate. */
  requirePhoneCode: boolean;
  /**
   * Whether REQUIRE_PHONE_CODE=1 was set, regardless of whether it took effect.
   *
   * Defaults to [requirePhoneCode] for a caller that does not know — an older
   * one then reads exactly as it did before, rather than inventing a
   * misconfiguration nobody made.
   */
  phoneCodeRequested?: boolean;
  /** Whether a push sender is wired. */
  pushWired: boolean;
  /** ANTHROPIC_API_KEY from the environment, if the process has one. */
  anthropicEnvKey?: string | null;
}

const has = (v: string | undefined | null) => !!(v && v.trim());

export function buildIntegrations(input: IntegrationInputs): IntegrationStatus[] {
  const s = input.settings ?? {};
  const out: IntegrationStatus[] = [];

  // ---- Ordering: WhatsApp -------------------------------------------------
  out.push({
    id: 'whatsapp',
    name: 'WhatsApp',
    purpose: 'Как мама заказывает: витрина, курс и «Поддержка» ведут сюда',
    state: has(s.whatsapp) ? 'ok' : 'off',
    detail: has(s.whatsapp)
      ? `Номер ${s.whatsapp}`
      : 'Номер не указан',
    breaks: has(s.whatsapp)
      ? ''
      : 'Кнопки «Заказать» и «Написать в поддержку» никуда не ведут — заказов не будет вообще',
    needs: has(s.whatsapp) ? [] : ['Номер WhatsApp в международном формате'],
    secret: null, // a phone number is not a secret; it is printed on the site
    checkable: false,
  });

  // ---- Payment: Kaspi -----------------------------------------------------
  out.push({
    id: 'kaspi',
    name: 'Kaspi',
    purpose: 'Ссылка на оплату в карточке заказа и на лендинге',
    state: has(s.kaspiUrl) ? 'ok' : 'off',
    detail: has(s.kaspiUrl) ? s.kaspiUrl : 'Ссылка не указана',
    breaks: has(s.kaspiUrl) ? '' : 'Оплатить онлайн нельзя — только наличными курьеру',
    needs: has(s.kaspiUrl) ? [] : ['Ссылка Kaspi на магазин или на счёт'],
    secret: null,
    checkable: false,
  });

  // ---- Lead alerts: Telegram ---------------------------------------------
  const tgToken = has(s.telegramBotToken);
  const tgChat = has(s.telegramChatId);
  out.push({
    id: 'telegram',
    name: 'Telegram — заявки',
    purpose: 'Куда падает уведомление о новой заявке с витрины',
    // Half-configured is its own state: a token without a chat id looks set up
    // on this screen and delivers nothing.
    state: tgToken && tgChat ? 'ok' : (tgToken || tgChat ? 'partial' : 'off'),
    detail: tgToken && tgChat
      ? `Бот настроен, чат ${s.telegramChatId}`
      : tgToken ? 'Есть токен бота, но не указан чат'
      : tgChat ? 'Есть чат, но нет токена бота'
      : 'Не настроено',
    breaks: tgToken && tgChat
      ? ''
      : 'Никто не узнает о новой заявке, пока не откроет панель',
    needs: [
      ...(tgToken ? [] : ['Токен бота от @BotFather']),
      ...(tgChat ? [] : ['ID чата или канала, куда слать']),
    ],
    secret: maskSecret(s.telegramBotToken),
    checkable: tgToken && tgChat,
  });

  // ---- Phone sign-in: SMS -------------------------------------------------
  //
  // The one that matters most and is least visible. A console logger counts as
  // NOT wired: it prints the code on the server and sends nothing.
  //
  // Three ways to be off, not one. The third — REQUIRE_PHONE_CODE=1 set on a
  // server that has no sender — LOOKED exactly like "nobody turned it on",
  // which is how the variable ended up written down as the fix for
  // unverified sign-in. It is reported separately and in the operator's words:
  // the setting is on, and it is doing nothing.
  const phoneCodeAsked = input.phoneCodeRequested ?? input.requirePhoneCode;
  const phoneCodeIgnored = phoneCodeAsked && !input.requirePhoneCode;
  out.push({
    id: 'sms',
    name: 'SMS-шлюз',
    purpose: 'Код подтверждения при входе по номеру телефона',
    state: input.smsSenderIsReal ? 'ok' : (input.requirePhoneCode || phoneCodeIgnored ? 'off' : 'partial'),
    detail: input.smsSenderIsReal
      ? 'Шлюз подключён'
      : phoneCodeIgnored
        ? 'REQUIRE_PHONE_CODE=1 задан, но шлюза нет — настройка НЕ действует, вход идёт без кода'
        : input.requirePhoneCode
          ? 'Код обязателен, но отправлять его нечем'
          : 'Шлюза нет; вход по коду выключен, поэтому никто не заблокирован',
    breaks: input.smsSenderIsReal
      ? ''
      : phoneCodeIgnored
        // The honest version of the thing the release notes called a
        // mitigation: it is switched on and it protects nobody.
        ? 'Проверка кода включена в настройках, но не работает: вход по номеру ' +
          'подтверждается ничем, и кто знает номер мамы — войдёт в её аккаунт, ' +
          'к её беременности, детям и их местоположению'
        : input.requirePhoneCode
          ? 'Ни одна мама не сможет войти: код запрашивается и никогда не приходит'
          : 'Вход по SMS-коду недоступен — аккаунт держится только на сессии устройства',
    needs: input.smsSenderIsReal
      ? []
      : [
          'Договор и API-ключ SMS-шлюза (Казахстан)',
          // Said out loud because the opposite was believed: on any server with
          // a database the variable alone changes nothing.
          ...(phoneCodeIgnored
            ? ['Подключить шлюз в коде: smsSender() в src/index.ts возвращает отправителя только без DATABASE_URL — переменной окружения недостаточно']
            : []),
        ],
    secret: null,
    checkable: false,
  });

  // ---- Push: Firebase -----------------------------------------------------
  out.push({
    id: 'push',
    name: 'Push-уведомления (Firebase)',
    purpose: 'Тревога SOS, выход из зоны, напоминания',
    state: input.pushWired ? 'ok' : 'off',
    detail: input.pushWired ? 'Отправка подключена' : 'Отправка не подключена',
    breaks: input.pushWired
      ? ''
      // The honest version. This is a child-safety product whose alarms are
      // currently in-app only.
      : 'Тревога SOS и выход из зоны не дойдут до телефона, пока приложение закрыто',
    needs: input.pushWired ? [] : ['Файл сервисного аккаунта Firebase (JSON) на сервере'],
    secret: null,
    checkable: false,
  });

  // ---- AI assistant -------------------------------------------------------
  //
  // WHICH KEY IS ACTUALLY IN USE. index.ts copies a stored key into the
  // environment only when the environment has none — `if (!process.env[envName]
  // && stored[key])` — so the ENVIRONMENT wins, and it wins at startup.
  //
  // This screen used to claim the opposite: with both set it printed «Ключ из
  // панели» and the panel key's last four characters, while every request went
  // out on the environment key. Someone comparing `••••1111` here against the
  // Anthropic dashboard to find out which key was being billed was reading a
  // key the server was not using.
  const envKey = input.anthropicEnvKey ?? '';
  const panelKey = s.anthropicApiKey ?? '';
  const aiKey = has(envKey) ? envKey : panelKey;
  out.push({
    id: 'anthropic',
    name: 'AI-ассистент',
    purpose: 'Ответы ассистента и распознавание фото анализов',
    state: has(aiKey) ? 'ok' : 'off',
    detail: !has(aiKey)
      ? 'Ключа нет'
      : has(envKey)
        ? (has(panelKey)
          // Both. Named out loud, because the two are different keys and the
          // one on screen is the one being charged.
          ? 'Ключ из переменных окружения — он важнее сохранённого в панели, панельный сейчас не используется'
          : 'Ключ из переменных окружения')
        : 'Ключ из панели — применяется после перезапуска сервера',
    breaks: has(aiKey) ? '' : 'Ассистент не отвечает, фото анализов не распознаются',
    needs: has(aiKey) ? [] : ['API-ключ Anthropic'],
    secret: maskSecret(aiKey),
    checkable: false,
  });

  // ---- Maps ---------------------------------------------------------------
  //
  // Deliberately not settable here. The app's map key is baked into the Android
  // manifest at build time, so a key stored on the server could never be used —
  // and a field that stores something nothing reads is worse than no field.
  out.push({
    id: 'maps',
    name: 'Google Maps',
    purpose: 'Карта ребёнка и история дня в приложении',
    state: 'partial',
    detail: 'Ключ задаётся при сборке приложения, а не здесь — отсюда его не проверить',
    breaks: 'Если ключ в сборке не указан, карта у мамы будет серой',
    needs: ['Ключ Google Maps в сборке Android (local.properties)'],
    secret: null,
    checkable: false,
  });

  return out;
}

/** The screen's own summary line: how many are actually working. */
export function integrationSummary(list: IntegrationStatus[]): {
  ok: number; partial: number; off: number; blocking: string[];
} {
  const blocking = list
    .filter((i) => i.state !== 'ok' && i.breaks)
    .map((i) => i.name);
  return {
    ok: list.filter((i) => i.state === 'ok').length,
    partial: list.filter((i) => i.state === 'partial').length,
    off: list.filter((i) => i.state === 'off').length,
    blocking,
  };
}
