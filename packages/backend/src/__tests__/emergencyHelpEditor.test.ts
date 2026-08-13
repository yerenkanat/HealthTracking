/**
 * Frame 16b «Экстренная помощь» → app screen 37 — the first-aid list becomes
 * editable.
 *
 * Nine scenarios that tell a frightened person at 3am whether to dial 103 now
 * or call the clinic in the morning, and they shipped compiled into the server
 * and bundled into the app: correcting «держите ожог под водой 20 минут» was a
 * backend release and a store rollout.
 *
 * The whole feature is one claim, and these drive it over HTTP against a real
 * memory repository rather than asserting on functions:
 *
 *   editing «сильное кровотечение» in the back office changes what
 *   GET /emergency-help says, and nothing else moves — the shipped contract is
 *   untouched, every other scenario still reads exactly as it shipped, and a
 *   database that cannot be reached costs the edits and not the list.
 *
 * Plus the two rules that make it survivable (no Kazakh, no publication;
 * medical text needs a second person), and the dispatcher address, which is the
 * other half of screen 37 and lives on `users`.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import type { StaffRole } from '../auth/capabilities';
import { emergencyHelp } from '../emergency/help';
import { mergeEmergencyHelp, scenarioAsReviewable } from '../emergency/overrides';
import { textFingerprint } from '../content/medicalReview';

let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

function appAs(role: StaffRole, r: Repository = repo): FastifyInstance {
  return buildServer(
    {
      repo: r,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: `${role}-1`, role }),
    },
    { logger: false },
  );
}

const ID = 'bleeding';
const base = () => emergencyHelp.scenarios.find((s) => s.id === ID)!;

const EDIT = {
  severity: 'red' as const,
  sort: 30,
  ru: {
    title: 'Сильное кровотечение',
    what: 'Прокладка промокает быстрее чем за час, кровь не останавливается.',
    do: 'Звоните 103, лягте на бок, ноги выше. Сохраните прокладку.',
  },
  kk: {
    title: 'Қатты қан кету',
    what: 'Прокладка бір сағаттан тез малынады, қан тоқтамайды.',
    do: '103-ке қоңырау шалыңыз, бүйіріңізге жатыңыз, аяғыңызды жоғары қойыңыз.',
  },
};

/**
 * The database with the overrides table taken away — migration 043 not applied
 * on a freshly deployed panel, or an ordinary connection blip. Everything else
 * still works, which is the point: one table's failure must not decide what the
 * emergency screen can show.
 */
const TABLE_GONE = 'relation "emergency_help_overrides" does not exist';
function withoutOverridesTable(r: Repository): Repository {
  return {
    ...r,
    emergencyHelpOverrides: async () => { throw new Error(TABLE_GONE); },
  };
}

const put = (app: FastifyInstance, body: unknown, id = ID) =>
  app.inject({ method: 'PUT', url: `/admin/emergency-help/${id}`, payload: body as never });
const approve = (app: FastifyInstance, id = ID) =>
  app.inject({ method: 'POST', url: `/admin/emergency-help/${id}/review` });
const served = async (app: FastifyInstance) =>
  (await app.inject({ method: 'GET', url: '/emergency-help' })).json() as
    { version: number; tel: string; scenarios: Array<{ id: string; severity: string; sort: number; ru: { title: string; what: string; do: string }; kk: { title: string } }> };

/** The full ceremony: author saves, clinician signs, author publishes. */
async function publishEdit(id = ID, edit = EDIT) {
  await put(appAs('content'), { ...edit, draft: true }, id);
  await approve(appAs('clinician'), id);
  return put(appAs('content'), edit, id);
}

// ---------------------------------------------------------------------------

describe('editing a scenario reaches the app', () => {
  it('GET /emergency-help serves the shipped contract when nothing is edited', async () => {
    const app = appAs('admin');
    const list = await served(app);
    expect(list.version).toBe(emergencyHelp.version);
    expect(list.tel).toBe('103');
    expect(list.scenarios).toHaveLength(emergencyHelp.scenarios.length);
    expect(list.scenarios.find((s) => s.id === ID)!.ru.do).toBe(base().ru.do);
  });

  it('the list is PUBLIC — no session, because this is the screen opened in a panic', async () => {
    // Every other content route the app reads is public too, and this one is
    // the least negotiable of them: a woman whose token expired must not meet a
    // 401 while deciding whether to call an ambulance.
    const res = await appAs('admin').inject({ method: 'GET', url: '/emergency-help' });
    expect(res.statusCode).toBe(200);
  });

  it('a published edit is what the app then receives', async () => {
    const res = await publishEdit();
    expect(res.statusCode).toBe(200);

    const s = (await served(appAs('admin'))).scenarios.find((x) => x.id === ID)!;
    expect(s.ru.do).toBe(EDIT.ru.do);
    expect(s.kk.title).toBe(EDIT.kk.title);
  });

  it('changes nothing else: every other scenario still reads as it shipped', async () => {
    await publishEdit();
    const list = await served(appAs('admin'));
    for (const shipped of emergencyHelp.scenarios) {
      if (shipped.id === ID) continue;
      const now = list.scenarios.find((x) => x.id === shipped.id)!;
      expect(now.ru.do, shipped.id).toBe(shipped.ru.do);
      expect(now.severity, shipped.id).toBe(shipped.severity);
    }
  });

  it('leaves the shipped contract itself untouched in memory', async () => {
    // The app bundles this exact file and
    // verify_emergency_help_contract.dart asserts they are identical. A merge
    // that mutated the loaded contract would poison every later request in the
    // process and break that check.
    const before = JSON.stringify(emergencyHelp);
    await publishEdit();
    await served(appAs('admin'));
    expect(JSON.stringify(emergencyHelp)).toBe(before);
  });

  it('bumps the version on every save, so a caching client notices', async () => {
    const v0 = (await served(appAs('admin'))).version;
    await put(appAs('content'), { ...EDIT, draft: true });
    const v1 = (await served(appAs('admin'))).version;
    await put(appAs('content'), { ...EDIT, draft: true });
    const v2 = (await served(appAs('admin'))).version;
    expect(v1).toBeGreaterThan(v0);
    expect(v2).toBeGreaterThan(v1);
  });

  it('a draft is stored but NOT served — the reader keeps the shipped text', async () => {
    const res = await put(appAs('content'), { ...EDIT, draft: true });
    expect(res.statusCode).toBe(200);
    expect(res.json().draft).toBe(true);

    const s = (await served(appAs('admin'))).scenarios.find((x) => x.id === ID)!;
    expect(s.ru.do).toBe(base().ru.do);

    // ...and the editor still sees her own draft, or an afternoon's work is
    // retyped every time the tab is reopened.
    const admin = await appAs('content').inject({ method: 'GET', url: '/admin/emergency-help' });
    const row = admin.json().scenarios.find((x: { id: string }) => x.id === ID);
    expect(row.ru.do).toBe(EDIT.ru.do);
    expect(row.draft).toBe(true);
    expect(row.live).toBe(false);
  });

  it('«вернуть исходный текст» is a draft, not a delete — the contract shows through again', async () => {
    await publishEdit();
    expect((await served(appAs('admin'))).scenarios.find((s) => s.id === ID)!.ru.do).toBe(EDIT.ru.do);

    const v = (await served(appAs('admin'))).version;
    await put(appAs('content'), { ...EDIT, draft: true });
    const after = await served(appAs('admin'));
    expect(after.scenarios.find((s) => s.id === ID)!.ru.do).toBe(base().ru.do);
    // The version still goes UP. A client that cached the edited scenario has
    // to be told the text moved back, and a version going backwards is the one
    // thing it cannot survive.
    expect(after.version).toBeGreaterThan(v);
    // ...and the row is still there, with its author and its counter.
    const row = (await repo.emergencyHelpOverrides()).find((o) => o.id === ID)!;
    expect(row).toBeTruthy();
    expect(row.rev).toBeGreaterThan(1);
  });

  it('reordering moves the scenario in the served list', async () => {
    // Triage order is a clinical decision, so it is editable — and a `sort`
    // that changed nothing about the order would be a field that lies.
    await put(appAs('content'), { ...EDIT, sort: 1, draft: true });
    await approve(appAs('clinician'));
    await put(appAs('content'), { ...EDIT, sort: 1 });
    expect((await served(appAs('admin'))).scenarios[0].id).toBe(ID);
  });

  it('a scenario the contract does not have is refused, not stored', async () => {
    const res = await put(appAs('content'), EDIT, 'invented-scenario');
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('unknown_scenario');
    expect(await repo.emergencyHelpOverrides()).toEqual([]);
  });
});

describe('when the overrides table cannot be read', () => {
  it('the app still gets the whole list, from the contract', async () => {
    // The screen that must never be blank. One unreadable table takes the
    // edits, not the first aid.
    const broken = withoutOverridesTable(repo);
    const res = await appAs('admin', broken).inject({ method: 'GET', url: '/emergency-help' });
    expect(res.statusCode).toBe(200);
    expect(res.json().scenarios).toHaveLength(emergencyHelp.scenarios.length);
  });

  it('the staff list answers too, and says the edit state is unknown', async () => {
    const broken = withoutOverridesTable(repo);
    const res = await appAs('admin', broken).inject({ method: 'GET', url: '/admin/emergency-help' });
    expect(res.statusCode).toBe(200);
    expect(res.json().editsKnown).toBe(false);
    expect(res.json().scenarios).toHaveLength(emergencyHelp.scenarios.length);
  });

  it('says so honestly rather than reporting nine untouched scenarios', async () => {
    await publishEdit();
    const ok = (await appAs('admin').inject({ method: 'GET', url: '/admin/emergency-help' })).json();
    expect(ok.editsKnown).toBe(true);
    expect(ok.scenarios.find((s: { id: string }) => s.id === ID).edited).toBe(true);
  });

  it('refuses the SAVE instead of quietly dropping the clinician\'s sign-off', async () => {
    await publishEdit();
    const signed = (await repo.emergencyHelpOverrides()).find((o) => o.id === ID)!;
    expect(signed.review!.by).toBe('clinician-1');

    const res = await put(appAs('content', withoutOverridesTable(repo)), { ...EDIT, draft: true });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe('overrides_unavailable');
    expect(res.json().message).toContain('проверка врача');

    const after = (await repo.emergencyHelpOverrides()).find((o) => o.id === ID)!;
    expect(after.review).toEqual(signed.review);
    expect(after.rev).toBe(signed.rev); // nothing was written at all
  });
});

describe('both languages, or it does not go live', () => {
  it('refuses a save with no Kazakh, naming the field', async () => {
    const res = await put(appAs('content'), {
      ...EDIT, kk: { title: '', what: '', do: '' },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json();
    expect(body.error).toBe('translation_required');
    expect(body.message).toContain('казахской');
    expect(body.problems).toHaveLength(3); // title, what, do
  });

  it('refuses a DRAFT with no Kazakh too', async () => {
    const res = await put(appAs('content'), {
      ...EDIT, draft: true, kk: { title: 'бар', what: '', do: '' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
  });

  it('whitespace is not a translation', async () => {
    const res = await put(appAs('content'), {
      ...EDIT, kk: { title: '   ', what: '  ', do: ' ' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
  });

  it('nothing was written when a save is refused', async () => {
    await put(appAs('content'), { ...EDIT, kk: { title: '', what: '', do: '' } });
    expect(await repo.emergencyHelpOverrides()).toEqual([]);
  });
});

describe('medical text needs a second person', () => {
  it('refuses to publish an unreviewed scenario with 409 review_required', async () => {
    const res = await put(appAs('content'), EDIT);
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('review_required');
    expect(res.json().message).toContain('черновик');
  });

  it('the author cannot approve her own text — approving needs `health`', async () => {
    await put(appAs('content'), { ...EDIT, draft: true });
    expect((await approve(appAs('content'))).statusCode).toBe(403);
    // ...and a clinician, who holds `health` and no `content`, cannot author.
    expect((await put(appAs('clinician'), { ...EDIT, draft: true })).statusCode).toBe(403);
  });

  it('publishes once a clinician has signed the same text', async () => {
    await put(appAs('content'), { ...EDIT, draft: true });
    const signed = await approve(appAs('clinician'));
    expect(signed.statusCode).toBe(200);
    expect(signed.json().review.by).toBe('clinician-1');
    // Approving does NOT publish: two decisions, two people.
    expect(signed.json().draft).toBe(true);

    const res = await put(appAs('content'), EDIT);
    expect(res.statusCode).toBe(200);
    expect(res.json().reviewed).toBe(true);
  });

  it('editing approved text takes the approval away', async () => {
    await publishEdit();
    const rewritten = { ...EDIT, ru: { ...EDIT.ru, do: 'Совсем другая инструкция.' } };
    const res = await put(appAs('content'), rewritten);
    expect(res.statusCode).toBe(409);
    expect(res.json().problems[0].reason).toBe('stale');
  });

  it('downgrading red to amber ALONE takes the approval away', async () => {
    // The field that decides whether somebody dials an ambulance or waits until
    // morning. A reviewed scenario quietly turned amber afterwards is
    // unreviewed advice under a reviewed headline.
    await publishEdit();
    const res = await put(appAs('content'), { ...EDIT, severity: 'amber' });
    expect(res.statusCode).toBe(409);
    expect(res.json().problems[0].reason).toBe('stale');
  });

  it('REORDERING does not take the approval away', async () => {
    // The other side of the same rule. Moving a row changes nothing about what
    // it says, and a rule that fires on a drag is a rule everybody works
    // around.
    await publishEdit();
    const res = await put(appAs('content'), { ...EDIT, sort: 5 });
    expect(res.statusCode).toBe(200);
    expect(res.json().reviewed).toBe(true);
  });

  it('re-saving the identical text keeps the approval', async () => {
    await publishEdit();
    const res = await put(appAs('content'), EDIT);
    expect(res.statusCode).toBe(200);
    expect(res.json().reviewed).toBe(true);
  });

  it('a review cannot be self-granted through the request body', async () => {
    const forged = {
      ...EDIT,
      review: {
        by: 'content-1', at: '2026-01-01T00:00:00Z',
        fingerprint: textFingerprint(scenarioAsReviewable(ID, { ...EDIT, draft: false })),
      },
    };
    expect((await put(appAs('content'), forged)).statusCode).toBe(409);
  });

  it('there is nothing to review on a scenario nobody has edited', async () => {
    const res = await approve(appAs('clinician'), 'breathing');
    expect(res.statusCode).toBe(404);
    expect(res.json().error).toBe('not_edited');
  });
});

describe('the journal', () => {
  it('records the edit and the sign-off as separate, named actions', async () => {
    await publishEdit();
    const log = await repo.listAudit(50);
    const actions = log.map((e) => e.action);
    expect(actions).toContain('edit_emergency_help_draft');
    expect(actions).toContain('emergency_help_review');
    expect(actions).toContain('edit_emergency_help');
    const signed = log.find((e) => e.action === 'emergency_help_review')!;
    expect(signed.staffId).toBe('clinician-1');
    expect(signed.target).toBe('emergency-bleeding');
  });
});

// ---- The dispatcher's address, the other half of screen 37 ----------------

describe('the address an ambulance is sent to', () => {
  const profile = (over: Record<string, unknown> = {}) => ({
    displayName: 'Aigerim',
    city: 'Алматы',
    address: 'мкр. Самал-2, д. 33, кв. 12, домофон 12К',
    ...over,
  });

  it('survives PUT /profile and comes back on GET — which is what a reinstall does', async () => {
    const app = appAs('admin');
    const saved = await app.inject({ method: 'PUT', url: '/profile', payload: profile() as never });
    expect(saved.statusCode).toBe(200);

    const got = await appAs('admin').inject({ method: 'GET', url: '/profile' });
    expect(got.statusCode).toBe(200);
    expect(got.json().profile.address).toBe('мкр. Самал-2, д. 33, кв. 12, домофон 12К');
    // The city is a different field and stays a different field: screen 37
    // falls back to it, and conflating the two would put «Алматы» on the card
    // as though it were an address.
    expect(got.json().profile.city).toBe('Алматы');
  });

  it('null is a supported answer, not a missing field', async () => {
    // She declined. The screen says «Добавьте адрес» — it does not invent one,
    // and it must not be handed an empty string that renders as a blank card.
    await appAs('admin').inject({
      method: 'PUT', url: '/profile', payload: profile({ address: null }) as never,
    });
    const got = await appAs('admin').inject({ method: 'GET', url: '/profile' });
    expect(got.json().profile.address).toBeNull();
  });

  it('an app that has never heard of the field still saves a profile', async () => {
    // Older builds send no `address` at all. Zod's optional keeps them working
    // rather than 400ing every phone that has not updated.
    const res = await appAs('admin').inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Aigerim' } as never,
    });
    expect(res.statusCode).toBe(200);
  });
});

// ---- The merge itself ------------------------------------------------------

describe('mergeEmergencyHelp', () => {
  const contract = {
    version: 3,
    tel: '103',
    scenarios: [
      { id: 'a', severity: 'red' as const, sort: 10, ru: { title: 'A', what: 'w', do: 'd' }, kk: { title: 'Ä', what: 'w̌', do: 'ď' } },
      { id: 'b', severity: 'amber' as const, sort: 20, ru: { title: 'B', what: 'w', do: 'd' }, kk: { title: 'B̌', what: 'w̌', do: 'ď' } },
    ],
  };
  const row = {
    id: 'a', severity: 'amber' as const, sort: 30,
    ru: { title: 'NEW', what: 'w', do: 'd' },
    kk: { title: 'ЖАҢА', what: 'w̌', do: 'ď' },
    draft: false, review: null, rev: 2, updatedAt: '2026-08-10T00:00:00Z', updatedBy: 's1',
  };

  it('never drops a scenario the contract covers', () => {
    expect(mergeEmergencyHelp(contract, []).scenarios.map((s) => s.id)).toEqual(['a', 'b']);
    expect(mergeEmergencyHelp(contract, [row]).scenarios.map((s) => s.id).sort()).toEqual(['a', 'b']);
  });

  it('an override for an id the contract does not have is ignored, not appended', () => {
    // Adding a scenario is a contract change. One invented here would appear on
    // a phone that has just fetched and vanish on one that has not.
    const stray = { ...row, id: 'zzz' };
    expect(mergeEmergencyHelp(contract, [stray]).scenarios.map((s) => s.id)).toEqual(['a', 'b']);
  });

  it('a draft leaves the contract text in place but still moves the version', () => {
    const drafted = mergeEmergencyHelp(contract, [{ ...row, draft: true }]);
    expect(drafted.scenarios.find((s) => s.id === 'a')!.ru.title).toBe('A');
    expect(drafted.scenarios.find((s) => s.id === 'a')!.severity).toBe('red');
    expect(drafted.version).toBe(3 + 2);
  });

  it('an edited sort re-orders the served list', () => {
    expect(mergeEmergencyHelp(contract, [row]).scenarios.map((s) => s.id)).toEqual(['b', 'a']);
  });

  it('an edit does not change who a scenario is written for', () => {
    // `audience` decides whether the app shows a scenario to a reader who is
    // not pregnant («после 20 недель» cannot apply to her). It is a clinical
    // property of the scenario, it is not on the editor's form, and the row
    // does not carry one — so it has to come off the BASELINE. Built from the
    // row alone it would be undefined here, and a wording fix in the back
    // office would quietly put pregnancy triage back in front of everybody.
    const pregnancyOnly = {
      ...contract,
      scenarios: [{ ...contract.scenarios[0], audience: 'pregnancy' as const }, contract.scenarios[1]],
    };
    const served = mergeEmergencyHelp(pregnancyOnly, [row]);
    expect(served.scenarios.find((s) => s.id === 'a')!.ru.title).toBe('NEW');
    expect(served.scenarios.find((s) => s.id === 'a')!.audience).toBe('pregnancy');
    // …and a contract entry that names no audience stays that way rather than
    // acquiring one.
    expect(served.scenarios.find((s) => s.id === 'b')!.audience).toBeUndefined();
  });

  it('the shipped contract files the pregnancy-only scenarios as such', () => {
    // The three the app used to hide from the only readers they are written
    // for. The app filters on this field; if the file stopped saying it, the
    // filter would silently become a no-op and nobody would see a failure.
    const byId = new Map(emergencyHelp.scenarios.map((s) => [s.id, s]));
    expect(byId.get('preeclampsia')!.audience).toBe('pregnancy');
    expect(byId.get('fetal_movements')!.audience).toBe('pregnancy');
    // Bleeding after birth happens once the due date is gone, so it is not
    // pregnancy-only — hiding it from a postpartum reader would be the one
    // failure this field must never cause.
    expect(byId.get('bleeding')!.audience).toBe('all');
  });

  it('two scenarios sharing a sort still come out in a stable order', () => {
    // `sort` is editable, so a collision is a matter of time, and an order that
    // depended on which row the database returned first would reshuffle
    // between reads of the same data.
    const clash = { ...row, sort: 20 };
    expect(mergeEmergencyHelp(contract, [clash]).scenarios.map((s) => s.id)).toEqual(['a', 'b']);
  });
});
