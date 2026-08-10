# The Ana-Bala team

Agents live one per file in this directory and are picked up when a session
starts — a file written mid-session will not resolve until the next one.

## Who does what

| Agent | Owns | Called when |
|---|---|---|
| `anabala-pm` | Deciding what to build next, and what "done" means | Start of any unit of work |
| `anabala-builder` | Backend + admin panel, full stack | Every backend/panel frame |
| `anabala-app` | The Flutter app and its on-device tests | Anything under `app/` |
| `anabala-auditor` | Adversarial verification of finished work | After every build, always |
| `anabala-clinician` | Medical sign-off | Any health copy, threshold, red flag or protocol |
| `anabala-kazakh` | ҚАЗ coverage, meaning, fonts and layout | Before anything user-visible publishes |
| `anabala-privacy` | Health and child-location data | Any route touching a family; any export or segment |
| `anabala-nudge` | Reminders, notifications, timing, the right to stop | Any scheduled or triggered message |
| `anabala-growth` | Funnel, referral, pricing presentation, retention | Acquisition and conversion work |
| `anabala-release` | Edge config, migrations, artifacts, Play | Before a deploy is proposed |
| `anabala-integrator` | Running the suites and committing | End of every unit of work |

## The order that actually matters

    pm → builder / app → auditor → clinician? → kazakh? → privacy? → integrator

The three middle ones are conditional but not optional when they apply:

- **clinician** if the change touches health copy, a threshold, a red flag, or
  the antenatal/vaccination protocol. Nothing medical publishes unreviewed.
- **kazakh** if the change adds a user-visible string. Publication is blocked
  without ҚАЗ, so skipping this just moves the failure later.
- **privacy** if the change touches a route that can reach a family, an export,
  or a segment.

`auditor` runs on *everything*. Its job is to assume the builder is not
finished, and it is usually right.

## Where growth and nudge sit

They report to the product, not to a metric. Two orderings matter:

- `anabala-growth` never writes notifications — `anabala-nudge` does, and the
  nudge rule wins: a message exists to make something happen in her life, not
  to raise a session count.
- Both pass through `anabala-privacy` before anything targets or segments, and
  through `anabala-clinician` if a message says anything clinical.

## Two rules no agent may override

1. **Never deploy to production** without an explicit, current go-ahead from the
   user. Green tests are not consent, and yesterday's approval is not today's.
2. **Never loosen a test to go green.** `adminAuthorization`, `adminAudit` and
   `pgSchema` are governance: they exist to catch what a hurried change breaks.
   Satisfy them, or add an allowlist entry with a written reason. Deleting an
   assertion is not a fix.

## Still uncovered

Worth adding when the work calls for it, and honestly not needed yet:

- **Data/analytics** — the BI numbers are computed but nobody interrogates
  whether they mean anything.
- **Design conformance** — the admin spec §2/§3 is prescriptive (40px rows,
  radius 10, colour only for status) and only a human has checked it.
- **Support responder** — becomes real once frame 12 «Поддержка» ships and
  there are actual tickets to answer.
