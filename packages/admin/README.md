# Umay Back-office (admin dashboard)

A self-contained staff/clinician dashboard for the Umay backend.

- **Overview** — ops KPIs (active users, devices online, alerts today, ingest rate),
  a 7-day alerts sparkline, and the live emergency feed.
- **Emergencies** — full triage feed, most-severe first, with severity stripes + acknowledge.
- **Users** — searchable user table → a patient-health drawer (latest vitals + triage
  history). Read-only, and every access is written to the audit log.
- **Audit log** — staff actions on protected data.

## Running it

Start the backend, then open <http://localhost:8080/admin/ui>:

```bash
# from packages/backend — no Postgres/Redis needed, uses the in-memory repo
USE_MEMORY_DB=true npm start          # macOS / Linux / Git Bash
$env:USE_MEMORY_DB="true"; npm start  # PowerShell
```

Without `DATABASE_URL` the backend falls back to the in-memory repository on its
own, so plain `npm start` works too — it just warns that nothing is persisted.

Single HTML file, no build step. It talks to the backend's `/admin/*` API
(`src/routes/admin.ts`) same-origin with `x-staff-id` / `x-staff-role` headers.

- Served by the backend at **`GET /admin/ui`** (see `packages/backend/src/index.ts`).
- With the API reachable it shows **live** data; otherwise it falls back to **demo data**
  so the UI is always viewable.

## RBAC
The `/admin` API enforces roles: any staff can see stats / emergencies / patient
health; `admin` role is required for the user list and audit log. The dashboard's
staff identity is a dev stub (`STAFF` in `index.html`) — replace with a real staff
sign-in + the backend's token verification (`authAdmin`) before production.
