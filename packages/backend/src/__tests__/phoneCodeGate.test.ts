/**
 * The SMS code gate that cannot engage — and the boot line that says so.
 *
 * THE DEFECT. `index.ts` computes
 *
 *     requirePhoneCode: REQUIRE_PHONE_CODE === '1' && !!smsSender()
 *
 * and `smsSender()` returns undefined whenever a database exists. So on every
 * real deployment the right-hand side is false, the flag is silently ignored,
 * and phone sign-in goes on accepting any number with no verification —
 * while docs/RELEASE.md listed that same variable as the mitigation.
 *
 * Nothing here invents a gateway; there still isn't one. What is tested is that
 * the impossibility is VISIBLE: loud at boot, and on «Интеграции» as a
 * setting that is on and doing nothing.
 */

import { describe, it, expect, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer, type ServerDeps } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { phoneCodePosture, phoneCodeWarning } from '../authPosture';
import { buildIntegrations } from '../admin/integrations';

const env = (o: Record<string, string>) => o as unknown as NodeJS.ProcessEnv;

/** A sender that would work — the thing production does not have. */
const REAL_SENDER = { newCode: () => '424242', send: async () => true };

function deps(over: Partial<ServerDeps> = {}): ServerDeps {
  return {
    repo: createMemoryRepository(),
    guardrail: { callLLM: async () => 'ok' },
    ingest: {
      cacheLocation: async () => {}, resolveTransition: async () => null,
      sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
    },
    cacheLastLocation: async () => null,
    setBpCalibration: async () => {},
    ...over,
  };
}

/** Boot a server for real and collect everything it warned about on the way up. */
async function bootWarnings(over: Partial<ServerDeps>): Promise<string[]> {
  const app: FastifyInstance = buildServer(deps(over), { logger: false });
  const said: string[] = [];
  vi.spyOn(app.log, 'warn').mockImplementation(((...args: unknown[]) => {
    said.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  }) as never);
  await app.ready();
  await app.close();
  return said;
}

describe('phoneCodePosture — what was asked for vs what is in force', () => {
  it('reports the flag as ignored when no sender exists', () => {
    const p = phoneCodePosture(env({ REQUIRE_PHONE_CODE: '1' }), false);
    expect(p.requested).toBe(true);
    expect(p.effective, 'the gate cannot engage with nothing to send a code').toBe(false);
    expect(p.ignored).toBe(true);
    expect(p.warning).toContain('REQUIRE_PHONE_CODE=1 is set but');
  });

  it('says nothing when the flag was never set', () => {
    // The common case. A warning on every boot is a warning nobody reads.
    const p = phoneCodePosture(env({}), false);
    expect(p.ignored).toBe(false);
    expect(p.warning).toBeNull();
  });

  it('says nothing once a sender is wired — then the flag really works', () => {
    const p = phoneCodePosture(env({ REQUIRE_PHONE_CODE: '1' }), true);
    expect(p.effective).toBe(true);
    expect(p.warning).toBeNull();
  });

  it('names the code change, not another environment variable', () => {
    // The exact misunderstanding that put this in the release notes: people
    // read "set REQUIRE_PHONE_CODE=1" and believed sign-in was then verified.
    const w = phoneCodeWarning(true, false)!;
    expect(w).toContain('src/index.ts');
    expect(w).toMatch(/accepts any number/);
  });
});

describe('the boot warning fires', () => {
  it('warns when a code is demanded and no sender is wired', async () => {
    const said = await bootWarnings({ phoneCodeRequested: true, sms: undefined });
    expect(
      said.filter((l) => l.includes('REQUIRE_PHONE_CODE=1 is set but')),
      'a server started with REQUIRE_PHONE_CODE=1 and no gateway said nothing about it',
    ).toHaveLength(1);
  });

  it('stays quiet on a normal boot', async () => {
    const said = await bootWarnings({ phoneCodeRequested: false, sms: undefined });
    expect(said.filter((l) => l.includes('REQUIRE_PHONE_CODE'))).toEqual([]);
  });

  it('stays quiet once a real sender is injected', async () => {
    const said = await bootWarnings({ phoneCodeRequested: true, sms: REAL_SENDER });
    expect(said.filter((l) => l.includes('REQUIRE_PHONE_CODE'))).toEqual([]);
  });
});

describe('«Интеграции» reports a setting that is on and doing nothing', () => {
  const base = { settings: {}, pushWired: false, anthropicEnvKey: null };
  const sms = (over: Record<string, unknown>) =>
    buildIntegrations({ ...base, smsSenderIsReal: false, requirePhoneCode: false, ...over } as never)
      .find((i) => i.id === 'sms')!;

  it('distinguishes «nobody turned it on» from «it is on and ignored»', () => {
    const untouched = sms({});
    const ignored = sms({ phoneCodeRequested: true });
    expect(untouched.state, 'nothing demanded, nobody locked out').toBe('partial');
    expect(ignored.state).toBe('off');
    expect(ignored.detail, 'the operator has to see the variable named').toContain('REQUIRE_PHONE_CODE=1');
    expect(ignored.detail).toContain('НЕ действует');
    expect(untouched.detail).not.toContain('REQUIRE_PHONE_CODE');
  });

  it('states the consequence in the operator’s terms, not the flag’s', () => {
    const ignored = sms({ phoneCodeRequested: true });
    expect(ignored.breaks).toContain('войдёт в её аккаунт');
    expect(ignored.breaks).toContain('местоположению');
  });

  it('says the environment variable is not enough on its own', () => {
    const ignored = sms({ phoneCodeRequested: true });
    expect(ignored.needs.join(' ')).toContain('src/index.ts');
    // …and does not say that where it would be noise.
    expect(sms({}).needs.join(' ')).not.toContain('src/index.ts');
  });

  it('an older caller that knows nothing of the flag reads exactly as before', () => {
    // phoneCodeRequested defaults to requirePhoneCode, so a caller that has not
    // been updated cannot start reporting a misconfiguration nobody made.
    const gateOn = sms({ requirePhoneCode: true });
    expect(gateOn.state).toBe('off');
    expect(gateOn.detail).toBe('Код обязателен, но отправлять его нечем');
  });

  it('goes green only for a real gateway', () => {
    expect(sms({ smsSenderIsReal: true, phoneCodeRequested: true }).state).toBe('ok');
    expect(sms({ smsSenderIsReal: true, phoneCodeRequested: true }).breaks).toBe('');
  });
});
