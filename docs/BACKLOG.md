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

## How this list was checked

Every item above was reproduced or read in the source; where an agent reported
something it could not reproduce, it is not here. Two claims WERE removed while
compiling this: a report that the takeover test was decorative (it was not), and
one that `/opt/umay` had no `deploy/` directory (it did — the checkout was 142
commits behind).

The lesson worth keeping: **a failing check is not proof of a failure.** Confirm
independently, in one command, before diagnosing what it blames.
