/**
 * Frame 24 — «Интеграции».
 *
 * The screen's job is to say what is NOT working and what that costs. These
 * pin the two claims that are easy to get wrong in the flattering direction:
 * a half-configured service must not read as working, and a console logger
 * must not read as an SMS gateway.
 */

import { describe, it, expect } from 'vitest';
import { buildIntegrations, integrationSummary, maskSecret } from '../admin/integrations';

const base = {
  settings: {} as Record<string, string>,
  smsSenderIsReal: false,
  requirePhoneCode: false,
  pushWired: false,
  anthropicEnvKey: null as string | null,
};
const byId = (input: Partial<typeof base>, id: string) =>
  buildIntegrations({ ...base, ...input }).find((i) => i.id === id)!;

describe('masking a secret', () => {
  it('keeps the last four so two keys can be told apart', () => {
    expect(maskSecret('sk-ant-api03-abcd7f2a')).toBe('••••7f2a');
  });

  it('hides a short secret ENTIRELY rather than revealing most of it', () => {
    // A six-character key masked "the same way" would print two thirds of
    // itself. Shorter than that, there is nothing safe to show.
    expect(maskSecret('abc123')).toBe('••••');
  });

  it('reports nothing stored as null, not as an empty mask', () => {
    expect(maskSecret('')).toBeNull();
    expect(maskSecret(null)).toBeNull();
    expect(maskSecret('   ')).toBeNull();
  });
});

describe('the SMS gateway', () => {
  it('is OFF when the only sender is the console logger', () => {
    // smsSenderIsReal is the whole point: index.ts substitutes a logger that
    // prints the code server-side and sends nothing. Reporting that as
    // «подключено» would hide the exact failure this screen exists to show.
    const sms = byId({ smsSenderIsReal: false }, 'sms');
    expect(sms.state).not.toBe('ok');
    expect(sms.needs.length).toBeGreaterThan(0);
  });

  it('says every mother is locked out when codes are demanded and cannot be sent', () => {
    const sms = byId({ smsSenderIsReal: false, requirePhoneCode: true }, 'sms');
    expect(sms.state).toBe('off');
    expect(sms.breaks).toContain('не сможет войти');
  });

  it('is only PARTIAL when codes are not demanded — nobody is blocked', () => {
    // The distinction that decides whether somebody is woken up tonight.
    const sms = byId({ smsSenderIsReal: false, requirePhoneCode: false }, 'sms');
    expect(sms.state).toBe('partial');
    expect(sms.breaks).not.toContain('Ни одна мама');
  });

  it('is ok with a real gateway', () => {
    expect(byId({ smsSenderIsReal: true }, 'sms').state).toBe('ok');
    expect(byId({ smsSenderIsReal: true }, 'sms').breaks).toBe('');
  });
});

describe('push', () => {
  it('names what an unwired sender actually costs', () => {
    const push = byId({ pushWired: false }, 'push');
    expect(push.state).toBe('off');
    // This is a child-safety product. The consequence, not «нет ключа».
    expect(push.breaks).toContain('SOS');
  });

  it('is ok once wired', () => {
    expect(byId({ pushWired: true }, 'push').state).toBe('ok');
  });
});

describe('Telegram lead alerts', () => {
  it('is PARTIAL with a token but no chat', () => {
    // Half-configured is its own state: it looks set up and delivers nothing.
    const tg = byId({ settings: { telegramBotToken: 'abc123456789' } }, 'telegram');
    expect(tg.state).toBe('partial');
    expect(tg.checkable).toBe(false);
    expect(tg.needs).toHaveLength(1);
  });

  it('is PARTIAL with a chat but no token', () => {
    const tg = byId({ settings: { telegramChatId: '-100200' } }, 'telegram');
    expect(tg.state).toBe('partial');
  });

  it('is ok and checkable with both', () => {
    const tg = byId({ settings: { telegramBotToken: 'abc123456789', telegramChatId: '-100200' } }, 'telegram');
    expect(tg.state).toBe('ok');
    expect(tg.checkable).toBe(true);
  });

  it('never returns the token itself', () => {
    const tg = byId({ settings: { telegramBotToken: '123456:AAHfake_token_7f2a', telegramChatId: '-1' } }, 'telegram');
    expect(tg.secret).toBe('••••7f2a');
    expect(JSON.stringify(tg)).not.toContain('AAHfake');
  });
});

describe('the AI key', () => {
  it('accepts one from the environment when the panel has none', () => {
    const ai = byId({ anthropicEnvKey: 'sk-ant-xxxx9999' }, 'anthropic');
    expect(ai.state).toBe('ok');
    expect(ai.detail).toContain('окружения');
  });

  it('prefers the panel key and says so', () => {
    const ai = byId(
      { settings: { anthropicApiKey: 'sk-panel-1111' }, anthropicEnvKey: 'sk-env-9999' },
      'anthropic');
    expect(ai.detail).toContain('панели');
    expect(ai.secret).toBe('••••1111');
  });
});

describe('Google Maps', () => {
  it('says it cannot be checked from here rather than pretending', () => {
    // The key is baked into the Android manifest at build time; a field here
    // would store something nothing reads.
    const maps = byId({}, 'maps');
    expect(maps.checkable).toBe(false);
    expect(maps.detail).toContain('сборке');
  });
});

describe('the summary', () => {
  it('counts states and names what is blocking', () => {
    const list = buildIntegrations({
      ...base,
      settings: { whatsapp: '+77000000000', kaspiUrl: 'https://kaspi.kz/x' },
    });
    const s = integrationSummary(list);
    expect(s.ok).toBeGreaterThanOrEqual(2);
    // Named, not counted: the banner has to print them.
    expect(s.blocking).toContain('SMS-шлюз');
    expect(s.blocking).toContain('Push-уведомления (Firebase)');
  });

  it('a fully configured shop still flags what genuinely cannot be verified', () => {
    const list = buildIntegrations({
      settings: {
        whatsapp: '+77000000000', kaspiUrl: 'https://kaspi.kz/x',
        telegramBotToken: 'abc123456789', telegramChatId: '-100',
        anthropicApiKey: 'sk-1234',
      },
      smsSenderIsReal: true, requirePhoneCode: true, pushWired: true,
      anthropicEnvKey: null,
    });
    // Maps stays partial by design — honest, not a nag we can clear.
    expect(integrationSummary(list).blocking).toEqual(['Google Maps']);
  });
});
