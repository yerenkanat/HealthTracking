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
});
