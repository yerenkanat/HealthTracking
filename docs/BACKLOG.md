# Ana-Bala — the open backlog

Everything found and not yet fixed, in one place, so it stops living in chat
scrollback. Compiled 2026-08-13 from four audits run that day: an admin function
sweep, an admin design conformance review, an app design review, and an app
navigation audit — plus what running the app on a device turned up.

**Ranking rule.** ana-bala.kz is the monetisation surface; the app and the rest
serve marketing and retention. A defect on the buying/ordering path costs money
the day it ships. Safety defects outrank both — this product tells a mother her
child is fine.

Every line carries `file:line` where it is known, and what the user loses.
Where a claim was checked, it says so; where it was reported but not
reproduced, it says that too.

---

## SHIPPED — do not re-schedule these

Struck through below rather than deleted, because the reasoning is why each one
was wrong and a deleted line comes back. Every item here is **deployed to
ana-bala.kz and verified against the live site**, not merely merged.

| Item | Shipped as | Note |
|---|---|---|
| 1.2 mother card «as of», English labels, raw severity | `32632a8` | |
| 1.3 frame 19 prints the constant `EMERGENCY` | `8d7dec8` | reason re-derived from the reading that fired it, by the same `assessTelemetry` that classified it |
| 1.4 SOS drawn like a zone crossing; `outcome` never selected | `7a15f49` + `8d7dec8` | the column had existed since migration 032 and **no query ever selected it** |
| 1.5 acknowledging a refused emergency says nothing | `0f1ceb5` | |
| 1.6 clinical wording for the watch surfaces | `254ee71`, `0f1ceb5`, `ed2a0d0` | **three of six metrics REFUSED** — see `CLINICAL-REVIEW-WATCH.md`; blood sugar, temperature day-average and BP day-average were withdrawn, not reworded |
| 2.2 / 2.3 course tab, staff password | `0f1ceb5` | `data-cap` now accepts an any-of list |
| §11 «Сводка» capless; «Финансы» under `stock` | `8d7dec8` | plus the root cause: block 2 of the panel had no `AccessDenied` at all |
| 4.x silent writes | `0f1ceb5` | includes blocking a **stolen tracker** |
| 5.4 `.formmsg.err` is not a class | — | **REFUTED.** It is defined. |
| 6.2 pairing has 2 states, needs 6 | `875821a` | seven, and three the spec asked for were refused as unreachable from that step |
| 9 · frames 07a «Поставки» / 07g «Поставщики» | `8d7dec8` | |

Also shipped, and not previously on this list:

- **Device temperature may no longer raise an emergency** from any wrist path
  (`ed2a0d0`), in both triage twins, so the SERVER stops pushing wrist-fever
  emergencies too. `ADV_TEMP_STEADY` no longer reassures off a device sample —
  it was telling a woman «температура держится ровно» from one wrist reading.
- **The Starmax temperature had no plausibility gate at all** — a corrupt frame
  reading 4000 became 400 °C and took over the screen. Same hole in the history
  sync. Both bounded 20–45 (`ed2a0d0`).
- **The ingest guard/CHECK agreement is now a test** (`b4fb99a`), and the
  "255 vs 260" ticket it came from is **REFUTED**: both fields are a single byte
  on the wire, so the gap is unreachable.
- **The deploy now checks what the internet can reach**, not only what the
  backend serves (`627356d`).

## 1 · Safety — a screen states something untrue about a person

| # | What | Where | What it costs |
|---|---|---|---|
| 1.1 | Vitals tiles carry no per-metric age, and «Всё стабильно» renders over readings the app knows are old. Freshness is computed per SAMPLE, but the watch sends `tempRaw = 0` when it did not measure — so the newest sample can be 2 min old while the newest temperature is 9 h old, and the screen says «2 мин назад» over last night's 36.9. | `app/lib/ui/dashboard/health_dashboard_screen.dart` ~314, `_MetricCard` ~691 | A reassurance about yesterday, in the calmest possible voice. The freshness ladder is already specified — scratchpad `today-watch-states.html` |
| 1.2 | The mother card's vitals have **no "as of" at all** — `adminUserHealth` selects the latest row `ORDER BY recorded_at DESC` and discards `recorded_at`. Labels are in **English** («Heart rate», «bpm», «mmHg») under a Russian heading. «История триажа» prints the raw `triage_severity` (`emergency`) and a raw ISO string. | `packages/admin/index.html:4167-4183`, `pgRepository.ts:1226` | 162/108 from three weeks ago and 162/108 from four minutes ago are the same pixels to a clinician |
| 1.3 | Frame 19 «Экстренные» is one card. `recentEmergencies` hard-codes `code: 'EMERGENCY'` and has no `detail` field, so **every row reads «EMERGENCY»** while the clinical reason sits in the columns the query already reads. No metrics, no SOS card, no 4-step instruction, no «Мы не служба спасения» plate. | `packages/admin/index.html:1087-1089`, `pgRepository.ts:1172` | The safety promise the product is sold on, unusable |
| 1.4 | On «SOS и зоны» an SOS renders identically to a child walking into the school zone. Five raw English kinds (`entered`, `sos`, `lowBattery`). `outcome` — the column that exists to close an SOS — is never selected. | `packages/admin/index.html:1176-1183`, rows ~7768 | The false-alarm rate is computable today and is not computed |
| 1.5 | Acknowledging an emergency that the server refuses says **nothing**: `if(r.ok||r.status===409)` with no `else`, and `catch(e){}`. | `packages/admin/index.html:3264-3272` | She cannot tell "my click missed" from "the server refused"; the row stays unacknowledged through shift hand-over |
| 1.6 | Clinical wording for BP, SpO2, temperature, stress, breathing rate and blood sugar has not been through the clinician gate. These are PPG estimates from a wrist. | new watch surfaces | A consumer estimate read as a clinical measurement |

## 2 · Authorization — the UI and the server disagree

| # | What | Where | What it costs |
|---|---|---|---|
| 2.1 | Three tabs are visible to roles the server 403s: Курс Ма!Ма! (`content` → `/admin/entitlements` needs `orders`), Магазин's stock block (`operator` → needs `stock`), Магазин's settings card (no `data-cap` at all → needs `staff`). Each paints the refusal as a load failure. | `index.html` 6174 / 5365 / 5170 | An operator reads «Не удалось загрузить» and files a bug against a working server |
| 2.2 | The inverse: a `seller` gets 200 on `/admin/entitlements` but the tab is `data-cap="content"` and hidden from her — so **only owner/admin can grant course access**, on a screen the person taking the order cannot reach. | `index.html` course tab | The sale completes and the access does not |
| 2.3 | Nobody but an owner can change their own password. The nav item is `data-cap="staff"`, so `applyCaps` hides the whole tab — and the password form inside it, which `requireStaff` allows any role to use. The code comment says this must not happen. | `index.html:910`, `staffAdmin.ts:193`, comment at `index.html:6700` | A leaked password cannot be rotated by its owner |
| 2.4 | The panel keeps its own `ROLE_CAPS` in JS; the server's `capsOf()` has **no production caller**. Two matrices, one enforced. | `index.html:6170-6180`, `auth/capabilities.ts:111` | They agree today. The day they do not, a tab paints an empty feed indistinguishable from "nothing is wrong" |

## 3 · Built and wired to nothing

| # | What | Where |
|---|---|---|
| 3.1 | The **whole vaccination editor**: 7 routes, 0 panel callers — `PUT /schedule/:id/:dose`, `POST .../review`, `PUT /settings`, `GET /coverage`, `/impact`, `/log`, `/schedule`. `admin.ts:449` even says «the immunisation calendar is now editable». It is editable by curl. | `routes/admin.ts` 1367–1760 |
| 3.2 | `DELETE /admin/shop/categories/:id` — finished, audited, 409-guarded, no caller. A mistyped category is permanent. | `routes/admin.ts:2298` |
| 3.3 | `PUT /admin/inventory/products/:id/parts` — the panel prints «Комплект из: X + Y» and offers no way to change it. | `inventory.ts:252` |
| 3.4 | Skin temperature is parsed by the OEM band parser and synced, and rendered nowhere. | `app/lib/ble/parsers/band_parser.dart:123` |
| 3.5 | `/app/version` sends `latestBuild`, the app parses it and drops it; `appUpdateAvailable()` has no caller in `lib/`. The soft-update nudge described in its own header does not exist. | `app/lib/main.dart:463`, `domain/app_version.dart:23` |
| 3.6 | Support: `customerReadAt` and `assigneeId` ride in every ticket and are never displayed. Two operators answer the same woman; a third chases her about a reply she has read. | `index.html` supRow ~7361 |
| 3.7 | `fillTemplate` — exported, tested, no production caller. Operators hand-edit `{status}` and `{eta}` on every reply. | `admin/support.ts:158` |
| 3.8 | Product `photoUrl` and the three SEO fields are edited in a card promising «Изменения сразу видны в витрине и в приложении». Nothing renders the photo; there is no per-product page for a slug. | `index.html:1747-1787`, `shop_catalogue.dart:80` |
| 3.9 | Seven `Ds*` widgets with no user in `lib/`; four "used" only by their own test. `DsBottomActionBar` implements the thumb-zone rule and nothing uses it, so the rule survives on memory. | `app/lib/ui/ds_widgets.dart` |
| 3.10 | `antenatalStatusForWeek` has no caller; the panel re-implements the visit schedule as a hard-coded `AN_VISITS` table while already fetching the real protocol. | `antenatal/protocol.ts:78`, `index.html:4389` |

## 4 · A write that fails and says nothing

| # | What | Where |
|---|---|---|
| 4.1 | Revoking course access: `await fetch(…DELETE)` with `r.ok` never read. The row stays; there is no message. | `index.html:6169` |
| 4.2 | **Blocking a stolen tracker** — `POST /admin/device-registry/:serial/status` — same shape. | `index.html:6292` |
| 4.3 | `moveLesson`'s two PUTs. Reordering a published lesson with no Kazakh title 400s; the operator clicks ↑ and nothing moves, with no explanation. | `index.html:6088-6098` |
| 4.4 | The content editor deletes items and publishes an emptied stage **with no confirmation**, wiping a live week for every reader. Every neighbour asks. | `index.html:7780`, publish at `7680` |

## 5 · A number that is not what it says

| # | What | Where |
|---|---|---|
| 5.1 | Lead backlog and the nav badge count `status === 'new'` in the **first 100 rows only**; the route returns no total. With 140 leads the header says «не обработано: 12» when it could be 50. | `index.html:5373`, `GET /admin/shop/leads` |
| 5.2 | `/admin/users` returns a real `count(*)` total that the panel never reads. No footer, no pager, row 51 unreachable. Same in Журнал (`?limit=100`, no footer) — an investigation silently reads the last 100 entries. | `index.html:3307`, `repository.ts:1107` |
| 5.3 | Two definitions of «online»: `/admin/stats.devicesOnline` uses 15 minutes, frame 11 uses 24 hours. Frame 11 prints its threshold; the dashboard tile does not. | `pgRepository`, `index.html` |
| 5.4 | `.formmsg.err` is not a class — only `.bad`/`.ok` exist — so `#finMsg` and friends render grey where they mean red. | `index.html` |

## 6 · App structure and state

| # | What | Where |
|---|---|---|
| 6.1 | The manual diary **deletes its own front door**: gated on `samples.isEmpty`, and hand-typed readings go into the same store, so it vanishes after the first entry. The only remaining route is an unlabelled app-bar icon. | `health_dashboard_screen.dart:415` |
| 6.2 | The pairing step has two states where it needs six. `band_scan.dart` collapses radio-off, permission-declined, nothing-nearby and timeout into an empty list, so the page spins «Поиск устройств…» forever. Copy specified in scratchpad `pairing-step-states.html`. | `onboarding_flow.dart:409-453` |
| 6.3 | Screen 08's 2×2 grid is dissolved across three surfaces with three different affordances; `HospitalBagScreen` has **no caller at all** before week 32; BP calibration lives in a different tab from the blood pressure. | `womens_health_screen.dart`, `settings_screen.dart:218` |
| 6.4 | `_recordBandSleep` (the live path) can still overwrite a manually logged night entered in the same session. | `app_controller.dart` |
| 6.5 | `ChildGrowthScreen.childName` is passed by every caller and rendered by nothing. | `child_growth_screen.dart` |

## 7 · System-wide app rendering

| # | What | Scale |
|---|---|---|
| 7.1 | 458 raw `fontWeight:` sites on **variable** fonts. `TextStyle.merge` keeps the parent's `fontVariations`, so a child saying `w700` renders at the inherited 500. Headings across the app are not the weight they claim. Only 2 files outside the design system read `context.ds`. | 85 files |
| 7.2 | `DsCard` and 167 other sites use `Border.all(Ds.ink)`; the spec retires that for a 1 px `#EADFD9` hairline. `no_band_card.dart`已 wrote its own card primitive to escape it — the system is being routed around. | 168 sites |
| 7.3 | `narrow_phone_test` covers 40 screens; the whole 39–48 block and the entire child-care hub are outside it — the newest screens and the least-checked layouts. | ~24 screens |
| 7.4 | Empty states: five different shapes, three with **no action**, against the spec's own rule. `DsEmptyState` has one user. | 5 shapes |
| 7.5 | Section headers: seven private widgets, four type specs, for one thing the spec defines exactly. | 8 sites |
| 7.6 | 22 distinct `BorderRadius.circular` values for 4 tokens. `DsLayout` is fully dead and its `screenPaddingH = 20` contradicts both the spec (16) and the app's own dominant practice. | tree-wide |
| 7.7 | `FittedTitle` exists and is used on 5 of 104 AppBars; staff-typed lesson titles ellipsize in the app bar. | 99 AppBars |

## 8 · Consistency in the panel

| # | What |
|---|---|
| 8.1 | Five chip vocabularies. **`.chip.crit` does not exist**, so `<span class='chip crit'>списание</span>` renders as white chrome — a status that reads as decoration. |
| 8.2 | Six money formatters (one prints `390,5 ₸`), two relative-time functions that disagree by an hour on the same instant, three date shapes plus a raw ISO slice. |
| 8.3 | Native `confirm` ×16, `prompt` ×1, `alert` ×3 — while the spec's modal exists and is used correctly elsewhere. The `prompt` accepts an empty reason and writes «без причины» into a ledger whose own footer promises «Списание без причины не проводится». |
| 8.4 | Order status is an inline `<select>` in 25 rows, and «Отменён» is reachable from three places for one order. |
| 8.5 | Serials are recorded in two places on one screen; the receipt card's own comment says the split was already fixed once. |

## 9 · Missing frames and screens

**Admin:** 07a Поставки · 07g Поставщики · 02b CSV export · 25 Уведомления ·
26 Настройки · 26b Служебные страницы · 27 Карта действий · 20a Когорты ·
09b Сегменты · 08c диалоги · 16b экстренная помощь · 17a расписание аудио.
Also 16a «Проверка врачом» asks for a signature **without showing the text**
being signed — the route deliberately sends only the title.

**App:** 27 «Гиды» (a library gathering the seven guide screens that exist and
are each buried under a different parent) · 30's actionable half (mood + EPDS) ·
13's enter/exit toggles (`GeofenceShape.polygon` exists in the domain, unused
in the UI) · 24's head circumference · 52's «Печать» and «Добавить своё».

## 10 · Waiting on the owner

- **SMS gateway.** `REQUIRE_PHONE_CODE=1` is built and tested. Until then the
  phone number IS the credential: anyone holding a customer's number can open
  her pregnancy, her children and their live locations.
- **Firebase.** No route registers a push token and there is no config in the
  repo, so `push_tokens` is only ever read and **every** server-sent push —
  emergency, geofence, SOS, support reply, broadcast — reaches zero devices.
  Local notifications scheduled on the phone do work.

---

## 11 · Added by the audit of 2026-08-13

An independent read-only sweep. Two findings outrank everything above them and
were on nobody's list; several items already here were confirmed, one was
refuted, and one was reclassified down.

### The two that outrank the rest

- **«Сводка» — the landing view — tells six of eight roles the backend is
  down.** The nav button carries no `data-cap` while `/admin/dashboard` requires
  `finance`, which only owner and admin hold. The catch paints «Сводка
  недоступна — бэкенд не ответил». A support operator's first screen every
  morning asserts an outage that is not happening; she cannot tell a refusal
  from a failure, and the sentence tells her the wrong one. Fires on every
  sign-in for operator, support, seller, warehouse, content and clinician.
- **«Финансы» is shown to warehouse and seller under `data-cap="stock"`** while
  its route requires `finance`. They get `Не загрузилось: 403 {"error":…}` — a
  raw status and a JSON blob — and file a bug against a working server.
  Twenty-seven lines earlier the same file gets it right: «Дашборд владельца» is
  `data-cap="finance"`.

**The mechanism, worth fixing once at the root:** the panel has two `<script>`
IIFEs, each with its own `api()`. The first defines `class AccessDenied` and
branches on 403; the second does not, and throws the raw status. Every view
below that line — Финансы, Поддержка, Интеграции, Каталог, Устройства,
Безопасность — is structurally unable to render a refusal as a refusal.

**The test that would have caught both, and is still missing:** existing tests
assert each `data-cap` names a REAL capability (`stock` is real, so it passes)
and which tabs each role sees. Nothing asserts the thing that matters — *a tab
shown to a role must have a data source that role can read.* Derive it from the
nav caps, the view's fetch, and that route's `requireCap`.

### Data the server computes and no screen shows

Cheap to finish; each is a number someone is already paying to produce.

- **`missingCost`** — finance returns the NAMES of products sold with no cost
  recorded. The panel shows only «посчитана по 74 % выручки». The owner is told
  a quarter of his margin is unmeasured and not told which products to price.
- **`averageCheckMinor`** — computed over earned orders only, rendered nowhere,
  while the dashboard shows a *different* average (`revenue / shipped`). An
  owner pricing a bundle has two averages with different denominators and cannot
  see the one computed for that decision.
- **`users.newToday` / `new7d`** — computed, never rendered; only `new30d`
  reaches a screen, so a campaign launched Monday is judged on a 30-day figure.
  `memoryRepository` hard-codes all three to 0 while `pgRepository` computes
  them, so this cannot even be developed against the memory repo until the fake
  is made faithful.
- **Support: `assigneeId`, `customerReadAt`, `closedAt`** — selected per ticket,
  never drawn. Two operators answer the same woman a minute apart and neither
  can see the other did; a third rings her to chase a reply she read yesterday.
- **`soldInWindow`** — the panel shows «хватит на 9 дн. · 2.4 шт/день» and hides
  the 72 units behind it, so a buyer cannot tell a steady rate from one bulk
  order that will not repeat.

### Also confirmed

- **`GET /admin/users/:id/health` has no caller and is redundant** — the mother
  card uses `/detail`, which calls it internally. A live unused endpoint
  returning latest vitals and 20 triage events: low functional cost, non-zero
  PHI surface on a route nothing exercises or watches.
- **Skin temperature is a write-only column** — inserted, never selected. The
  mother is not missing a temperature (the converted `coreTempC` is shown); what
  is lost is the ability to ever check `skinToCoreTempC` against its own input.
- **Two indexes exist in migrations and not in `schema.sql`** — a database built
  from the schema file sequential-scans `shop_orders` on every mother-card open
  and on every child's safety history, in a way nobody will connect to a missing
  index.
- The vaccination editor (7 routes), `DELETE /admin/shop/categories/:id`,
  `PUT /admin/inventory/products/:id/parts`, `latestBuild`/`appUpdateAvailable`,
  the lead badge, and the missing `/admin/users` pager — all still unwired. The
  lead badge is worse than recorded: the correct figure is **already computed
  and already served**, and already rendered correctly two clicks away.

### Refuted and reclassified — do not re-schedule

- **`.formmsg.err` is not a class — REFUTED.** It is defined.
- **`capsOf()` — reclassified DOWN.** It is dead code (zero production callers),
  but the stated risk, that the panel's duplicate `ROLE_CAPS` could silently
  diverge, is guarded: a test extracts the panel's literal and compares it to
  the server's for every role. The extraction was checked and is not vacuous —
  8 roles parsed, real capability sets on both sides. **However** the comment
  beside it names `adminCapsMatrix.test.ts`, a file that does not exist; the
  guard lives in `adminRoleUiRender.test.ts`. Fix the comment before someone
  greps for the named file, concludes the matrix is unguarded, and deletes the
  panel's copy.
- **No genuine silent write remains** in the panel: both `api()` helpers throw
  on `!r.ok` and every write site handles it.

### 161 fixed sleeps are one busy machine away from lying

Found while making the role-access test deterministic, and larger than the file
that surfaced it. **47 admin panel test files contain 161 waits of the form
`submit` → `setTimeout(120)` → read the DOM** — `adminSupplyRender` has 16,
`adminStaffRender` 11, `adminCourseRender` 10. Each one decides its verdict on
elapsed wall-clock rather than on the work being finished, so every one of them
changes answer under load. This is not theoretical: the same tree produced
`1 failed | 165 passed` and `165 passed` on consecutive full runs, and the
failure moved when another agent's file added ~30 s of jsdom CPU to the run.

The replacement pattern now exists in `adminRoleRouteAccess.test.ts`: count the
requests issued and in flight, return when nothing is in flight and nothing new
has been issued for several consecutive turns, and **throw** rather than proceed
on a half-drawn screen. Its companion test makes load an INPUT — it boots the
same role twice, once with the transport slowed to 40 ms per request, and
asserts the two observation sets are byte-identical, with a non-vacuity floor so
two empty maps cannot be what passes. Porting that to 47 files is the work.

Related, and deliberately not fixed: `anKpiTiles`, `renderFinance`,
`renderSerials` and `renderStock` read their payloads with no shape guard, while
`/admin/dashboard` has `dashUsable()` for precisely this. Unreachable today —
every one of those handlers sends its key unconditionally, and a 401/403 throws
in `api()` before a renderer sees a body — so it is a latent trap, not a live
defect: it becomes reachable the day one of those fields is made conditional.

### Every panel render test boots through the FAILURE path

`drawBiTrend` does `const ctx = c.getContext("2d"); ctx.scale(dpr, dpr);` with no
guard. Under jsdom `getContext("2d")` returns **null**, so `ctx.scale` throws —
and the stack is `drawBiTrend → drawOps → render → boot`, where `boot()` catches
everything and takes its degraded branch, logging «boot failed».

So in every jsdom test that boots the panel, `LIVE` never becomes true, the mode
pill never says «Live», and the catch's "the invented patients go first" cleanup
runs. **The suite has been asserting against a panel in its boot-failure state**
while believing it was testing the live one. Tests still pass, which is the
uncomfortable part: either they assert things drawn before the throw, or they
assert things true in both states — and nobody can tell which without checking
each one.

Worth reading two lines below the throw, where someone already recorded this
exact lesson for the neighbouring case:

> «a payload that arrives without the array is exactly that case — but
> dereferencing it first threw instead, inside the boot() chain, so one missing
> field took the whole panel down rather than one chart»

The same unguarded dereference survived one line above the comment describing
it. `if (!ctx) return;` is the fix, and it is deliberately NOT a test-only
concern: a canvas that fails to give a context in a real browser would take the
whole panel down for the same reason, which is the failure mode that comment
exists to prevent.

Expect this to CHANGE test outcomes rather than merely quieten a log line —
several suites will start seeing a fully-booted panel for the first time. That
is a reason to do it deliberately and read the diff, not a reason to leave it.

### What that audit could NOT establish

It had no write tools, so it performed **no** break-and-restore verification. It
substituted one independent check, on the single test a claim depended on, and
reported the rest as unverified rather than implying otherwise. Findings 1 and 2
above are read off the source — `requireCap`, `ROLE_CAPS`, `applyCaps` and the
catch branches — and were not confirmed by signing in as `warehouse` against a
running server. Every link is cited; a jsdom test that opens the panel as an
operator and asserts the Сводка cards do not claim an outage would settle it in
one run, and should ship with the fix.

---

## How this list was checked

Every item above was reproduced or read in the source; where an agent reported
something it could not reproduce, it is not here. Two claims WERE removed while
compiling this: a report that the takeover test was decorative (it was not), and
one that `/opt/umay` had no `deploy/` directory (it did — the checkout was 142
commits behind).

The lesson worth keeping: **a failing check is not proof of a failure.** Confirm
independently, in one command, before diagnosing what it blames.
