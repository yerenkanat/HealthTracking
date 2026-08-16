/**
 * The in-memory repository is the backend that actually runs today (no Postgres
 * required), so its admin drilldown must return the same profile fields the
 * Postgres repo does — otherwise the admin panel renders a blank "Контакт врача"
 * / "Цикл (база)" even though the mother provided them. This guards the parity
 * gap that had adminUserDetail dropping doctorPhone/cycle baselines and nulling
 * out the child birth date.
 */
import { describe, it, expect } from 'vitest';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

describe('memory adminUserDetail parity', () => {
  it('surfaces the doctor phone, cycle baselines, and child birth dates', async () => {
    const repo = createMemoryRepository();
    await repo.upsertProfile(DEMO_USER, {
      displayName: 'Aigerim',
      // No phone: it is the sign-in identity and upsertProfile cannot set it.
      dueDate: null,
      locale: 'ru-KZ',
      birthDate: null,
      city: 'Алматы',
      address: null, doctorPhone: '+77007654321',
      avgCycleLength: 30,
      avgPeriodLength: 6,
    });

    const detail = await repo.adminUserDetail(DEMO_USER);
    expect(detail).not.toBeNull();
    expect(detail!.doctorPhone).toBe('+77007654321');
    expect(detail!.avgCycleLength).toBe(30);
    expect(detail!.avgPeriodLength).toBe(6);
    // The seeded demo child carries a real DOB; the drilldown was hardcoding null.
    expect(detail!.children[0]?.dateOfBirth).toBe('2019-03-08');
  });

  /**
   * Her vitals, and whether they are hers.
   *
   * `latest` and `triage` were a frozen literal here — `{hr: 80, spo2: 97,
   * 138/82, 36.7, 5.4}` and an empty triage list — for every mother, whatever
   * she had sent, while `pgRepository.adminUserDetail` built them by calling
   * `adminUserHealth`. So on the backend that actually runs, the card a
   * clinician reads printed six invented readings and «нет отметок» over a
   * woman whose last reading was an emergency.
   *
   * It survived because the only route serving the real numbers was
   * /admin/users/:id/health, and no screen called it (docs/BACKLOG.md §3).
   */
  it('reads her real vitals and triage history, not a fixture', async () => {
    const repo = createMemoryRepository();
    await repo.insertHealthMetric({
      deviceId: 'd1', userId: DEMO_USER, recordedAt: '2026-08-15T08:00:00.000Z',
      heartRateBpm: 122, spo2Pct: 91, systolicMmHg: 162, diastolicMmHg: 108,
      triageSeverity: 'emergency',
    } as never);

    const detail = await repo.adminUserDetail(DEMO_USER);
    expect(detail!.latest.systolic).toBe(162);
    expect(detail!.latest.hr).toBe(122);
    // The fixture's own numbers, which must no longer appear over a real row.
    expect(detail!.latest.systolic).not.toBe(138);
    expect(detail!.triage.length, 'an emergency reading left no triage history').toBe(1);
    expect(detail!.triage[0].severity).toBe('emergency');

    // …and it is the same answer the health view gives, which is the point:
    // both real repositories build this field from that one method.
    const health = await repo.adminUserHealth(DEMO_USER);
    expect(detail!.latest).toEqual(health!.latest);
    expect(detail!.triage).toEqual(health!.triage);
  });
});
