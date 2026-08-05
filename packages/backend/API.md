# Ana-Bala public content API (`/api/v1`)

Read-only API over the **pregnancy calendar**, the **child-development calendar**,
and the **MoH medical protocols** (antenatal + vaccination), for another service
to consume — e.g. a WhatsApp bot that sends a mother the right week's content on
the right day.

No personal data is stored or returned. Personalisation is derived from a date
passed in the request (a due date, or a child's birth date).

## Auth

Open by default. Set the `CONTENT_API_KEY` env var to require a key — then every
request must send it as the `x-api-key` header (else `401`).

## Discovery

`GET /api/v1` returns a self-describing index: coverage (week ranges, versions,
counts) and the full endpoint list. Start there.

## Endpoints

### Pregnancy calendar
- `GET /api/v1/pregnancy/weeks` — all gestational weeks (ru + kk).
- `GET /api/v1/pregnancy/weeks/:week` — one week (clamped to the covered range).
- `GET /api/v1/pregnancy/timeline?dueDate=YYYY-MM-DD&from=YYYY-MM-DD&weeks=N`
  — **personalised.** `dueDate` required; `from` defaults to today; `weeks` is
  1–20 (default 6). Returns `currentWeek` and a `timeline[]` of
  `{ week, weekStart, content }` — `weekStart` is the date that week begins for
  this pregnancy, i.e. when to send it.

### Child-development calendar
- `GET /api/v1/child/weeks` — all weeks (ru + kk, with the paediatrician note).
- `GET /api/v1/child/weeks/:week` — one week (clamped).
- `GET /api/v1/child/timeline?birthDate=YYYY-MM-DD&from=YYYY-MM-DD&weeks=N`
  — **personalised** by child age. Same shape as the pregnancy timeline.

### Medical protocols
- `GET /api/v1/protocols/antenatal` — the MoH 8-visit antenatal protocol.
- `GET /api/v1/protocols/antenatal/timeline?dueDate=YYYY-MM-DD`
  — **personalised.** Each visit mapped to real `fromDate`/`toDate` windows.
- `GET /api/v1/protocols/vaccination` — the childhood immunisation schedule.
- `GET /api/v1/protocols/vaccination/timeline?birthDate=YYYY-MM-DD&from=YYYY-MM-DD`
  — **personalised.** Each vaccine mapped to a `dueDate` and a `status`
  (`past` | `due` | `upcoming`) relative to `from`.

## Dates

All dates are `YYYY-MM-DD` (UTC). Gestational age follows the obstetric
convention EDD = LMP + 280 days (40 weeks); a week/date outside a calendar's
covered range is clamped to the nearest real entry.

## Example

```
GET /api/v1/pregnancy/timeline?dueDate=2026-12-09&from=2026-07-27&weeks=3
→ {
    "dueDate": "2026-12-09", "from": "2026-07-27", "currentWeek": 20,
    "timeline": [
      { "week": 20, "weekStart": "2026-07-22", "content": { "week": 20, "ru": {...}, "kk": {...} } },
      { "week": 21, "weekStart": "2026-07-29", "content": {...} },
      { "week": 22, "weekStart": "2026-08-05", "content": {...} }
    ]
  }
```
