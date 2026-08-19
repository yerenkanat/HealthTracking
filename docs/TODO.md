# Ana-Bala — what is open, and who can move it

Compiled 2026-08-18 from the working session of 13–18 August. Everything here is
either **verified by reading the code**, **observed on a running device**, or
**ruled on by the clinical gate** — and each item says which. Nothing is here on
a hunch.

**Ordering rule, unchanged from BACKLOG.md.** ana-bala.kz is the monetisation
surface; a defect on the buying path costs money the day it ships. Safety
defects outrank both, because this product tells a mother her child is fine.

**How to read the status column.** *Verified* means someone reproduced it.
*Ruled* means the clinical gate decided and the decision is recorded in
`CLINICAL-REVIEW-WATCH.md`. *Reported* means an agent found it and it has not
been independently confirmed.

---

## 1 · Needs the owner — nobody else can decide these

| # | What | Why it is yours |
|---|---|---|
| 1.1 | **37.8 / 38.5 / 135 / 85 have no cited source** for pregnancy anywhere in this repository, while 140/90 beside them is attributed to ACOG. They still fire cards. | The gate refused to substitute numbers from memory, correctly. An OB-GYN must record a source or replace them. *Ruled.* |
| 1.2 | **There is no fever emergency, from any source.** Removing hand entry made `HIGH_FEVER` / `LOW_FEVER` unreachable — they sat behind `source == manual`. | The gate recorded that the only thing that buys it back is a **single-number thermometer entry**, not the diary. Your objection was to entering readings the WATCH produces; a thermometer number is not one. *Ruled.* |
| 1.3 | **A child's zone crossings are kept for ever.** `geofence_events` and `safety_alerts` have no retention sweep; only `location_history` is pruned at 90 days — while the app tells her «Маршруты хранятся 90 дней». | Two questions, both yours: does that promise cover crossings, and is 90 days right for them? A sweep would also silently change the admin dashboard's all-time counters. *Verified.* |
| 1.4 | **`graphify` is installed nowhere**, though `CLAUDE.md` mandates `graphify query` before every search and a hook repeats it on every grep. Its graph is days and dozens of commits stale. | Reinstalling and rebuilding is a repo-wide write and your tool choice. Every agent that tried got `command not found`. *Verified.* |
| 1.5 | **The design spec says the manual diary is what makes the app complete without a device** — ЧАСТЬ 4 rule 3, «Без устройства приложение полноценно — ручной дневник, а не заглушка с апселлом» — which pulls against removing hand entry. | Raised before the removal and again after. Your call; recorded so it is not rediscovered as a defect. *Verified.* |
| 1.6 | **SMS gateway** — `REQUIRE_PHONE_CODE=1` is built and tested. Until it is on, the phone number IS the credential: anyone holding a customer's number can open her pregnancy, her children and their live locations. | Owner-blocked. *Verified.* |
| 1.7 | **Firebase** — no route registers a push token and there is no config in the repo, so `push_tokens` is only ever read and **every** server-sent push reaches zero devices. | Owner-blocked. This is why the emergency-push work is untestable end to end. *Verified.* |

---

## 2 · Safety — a screen states something untrue, or a warning cannot arrive

| # | What | Status |
|---|---|---|
| 2.1 | **`metricStatus`'s systolic/diastolic branch still grades against the uncited 135/85**, so a tile can be amber or green on a band nothing cites. Refused sentence #23's second half. | Reported by the agent that fixed the ungraded colour; deliberately out of that scope. |
| 2.2 | ~~**The peace ring's empty-pool default is `1.0`** — a day whose only readings are a wrist BP now skips every metric and draws FULL.~~ The `1.0` itself was already fixed in `6b24dce` (nullable fraction, no arc, a sentence). What was still live was **the partial pool**: `healthy / withData` over a denominator the gates had thinned, so the everyday band day — two gradeable cards of four — went on drawing a complete circle. | **Ruled and closed 2026-08-18.** The pool is stated per card in `domain/peace_ring.dart`, the arc spans only the assessed share, the rest is dashed «not assessed» ink, and `db_ring_partial` names the count. Reasoning in CLINICAL-REVIEW-WATCH.md, «A shape cannot be qualified». The Kazakh string is flagged for the language gate. |
| 2.3 | ~~`handleNotificationTap` has no staleness check.~~ Gated on the app existing 6 h freshness constant, aliased not restated. A tap it cannot date is treated as past: «not knowing is not permission to assume». **A second defect it depended on:** no emergency push had EVER carried a timestamp, so an app-side-only gate would have silenced the takeover for everyone. | **Fixed.** ⚠ **Ship the backend FIRST** — a new app against an old server would go quiet. |
| 2.7 | **A concurrent agent edit was swept into an unrelated commit.** `770ae06`, titled for the export fix, also carries six lines of the notification work in `app_controller.dart`. Explicit `git add <path>` did NOT prevent it: the other agent had already edited the same file. Already pushed, so not rewritten. | Recorded. See the new trap in §6. |
| 2.4 | **There is no `FirebaseMessaging.onMessage` listener in `app/lib` at all**, so a server push is drawn by the OS tray with no in-app coordination — and the phone and server can alarm her about the same reading with nothing connecting them. | Verified. |
| 2.5 | **Six advisories and two triage branches are unreachable** since hand entry went: `ADV_BP_ELEVATED`, `ADV_BP_STEADY`, `ADV_TEMP_ELEVATED`, `ADV_TEMP_STEADY`, `ADV_GLUCOSE_HIGH`, `ADV_GLUCOSE_LOW`, plus `HIGH_FEVER`/`LOW_FEVER`. The gate ruled they should be DELETED — «a dead key is a live key to the next person who finds a call site». | **Attempted and cancelled.** Half-done work was reverted to keep the tree coherent. See §6 for the trap that makes this harder than it looks. |
| 2.6 | **The server pushes an emergency on the FIRST crossing** with no confirmation gate. One-alert-per-episode shipped, so repeats are suppressed — but the gate left a question open: *is the first-crossing push the backstop that must survive precisely because the in-app prompt is only visible in the foreground?* | **Ruled in part.** The remaining question is recorded and unanswered. |

---

## 3 · The device audit — observed on a running phone, 2026-08-18

Three attempts by agents died; the fourth was done by hand. Everything below was
**seen**, not inferred. Two are already fixed.

| # | What | Status |
|---|---|---|
| 3.1 | ~~Onboarding offered «Пока нет — буду записывать вручную», a screen removed the same day.~~ | **Fixed** `ad7b5e6` — now `onb_pair_skip`, which existed and had no caller. |
| 3.2 | ~~A Kazakh speaker got a Russian app back after one phone call.~~ | **Fixed** `78a47b5` — `restore()` discarded the persisted language when onboarding was unfinished. |
| 3.3 | ~~Denying the Bluetooth permission bounces back a step and clears the name and phone.~~ **REFUTED — and my description was the reason it looked unexplainable.** Nothing was cleared. None of the three onboarding `TextField`s had a controller, so a rebuilt page painted blank over a model that still held the name. The field was lying about what the app had. | **Fixed**, `f109da3`. |
| 3.4 | ~~The name requirement is not re-applied after that bounce.~~ **Same defect, not a second one.** «Далее» stayed enabled because `canProceed` reads the model, which was intact all along. | **Fixed** with 3.3. |
| 3.5 | ~~The splash is a coral circle with a white heart, not the brand.~~ **The drawable was never at fault.** Android 12+ draws the splash itself and IGNORES `windowBackground`; with no `values-v31` the platform fell back to the adaptive launcher icon — whose foreground is still commented «Umay heart», a previous brand. | **Fixed**, `a611d08`. APK builds; the splash is transient so this is fixed-pending-device, not verified. |
| 3.6 | ~~The pairing screen spins for ever when permission is denied.~~ | **REFUTED — my error.** The scan window is 15s; I read it at 4s. Permission was never denied (`dumpsys`: `granted=true`), and `noneNearby` is the truthful answer. Kept in BACKLOG.md because it is the stopwatch mistake, made by hand. |

**Seen working, and worth keeping:** every Kazakh string in onboarding renders
with no tofu and no overflow; the Material date picker localises fully («2027 ж.
қаңтар», «Бас тарту»/«Иә»); the phone auto-formats; failed reads say «refresh
failed, keeping what we have» rather than blanking; and the disabled-button
reason changes as the blocking condition changes.

---

## 4 · Built and wired to nothing — the remainder

| # | What | Status |
|---|---|---|
| 4.1 | ~~**The whole vaccination editor** — seven routes, zero panel callers.~~ | **STALE — the entry outlived the defect, and cost two more agents.** `2d8d127` wired it: all seven routes have panel callers (`loadVac`, `loadVacCoverage`, `loadVacLog`, `vacSave`, `vacApprove`, `vacSaveWindow`, `vacLoadImpact`), both repository implementations carry the four methods, migration 038 and `schema.sql` agree, the app reads `/vaccination/schedule` through `vaccination_schedule_repository.dart`, and `adminVaccinationRender.test.ts` drives it under jsdom. **Verify §4 entries against the tree before starting one.** What was actually missing is below. |
| 4.1a | ~~Frame 15's «провал по пневмококку 76 % с объяснением» was never built~~ — the per-row coverage column shipped, the callout naming the injection that has fallen behind did not. | **Fixed.** `coverageOf` now selects `lowest` (+ `measured`); the route supplies `lowestRule`; the panel prints tiles and the sentence. Ties go to the larger denominator. |
| 4.1b | ~~«Сохранить черновиком» retired a live vaccine on one click~~ — drafting is what takes a row off every phone, and only «Вернуть к контракту» asked; an ADDED vaccine has no such button, so the one way to retire one never asked. | **Fixed.** `vacSave` asks in the card modal, and only when the row is actually on phones. |
| 4.1c | ~~The calendar's audit trail printed raw English keys~~ — `edit_vaccine`, `edit_vaccine_draft`, `vaccine_review`, `edit_vaccination_settings` had no entry in `AUDIT_ACTIONS`. | **Fixed.** ~20 other server-written actions are still unlabelled — see §4.6. |
| 4.6 | ~~`AUDIT_ACTIONS` is missing ~20 labels.~~ **28, not 20.** `broadcast_send` does not exist — the route writes `broadcast_publish`, so the guessed label would have shipped dead while the real action still printed raw; and `device_${status}` is a template literal expanding to three keys no grep for quoted strings finds. | **Fixed**, `1e25233`. The test now derives the expected set from the `writeAudit` call sites, so a NEW unlabelled action fails the build. |
| 4.2 | ~~`latestBuild` is parsed, carried and dropped — no soft-update nudge.~~ Wired as a dismissible strip, never a launch dialog. **The half that was missing:** the snooze was written and read but never restored on launch, so dismissing it lasted one process and it came back — the shape of a nag, which is how the HARD block gets dismissed unread later. | **Fixed**, `f8eefdd`. |
| 4.3 | **`db_empty_body`** still reads «Наденьте браслет — и данные появятся здесь» — the band upsell the spec forbids — but no `lib/` file asks for that key. Invisible today; a trap for whoever wires an empty state next. | Reported. |
| 4.4 | ~~Журнал has no pager~~ — the log served its newest 100 rows and the panel drew no footer, so everything older was unreachable from the UI. **The deferral was right about the repository and wrong about the total:** `audit_log` is append-only and grows with every back-office action, so `count(*)` would be a full scan on every open of the tab. The signal is `hasMore` — one row past the page — and the footer says on screen that the log is not counted rather than printing a number nobody paid for. | **Fixed.** `listAudit(limit, offset)` returns `{entries, hasMore}` in both implementations, ordered `at DESC, id DESC` so a row cannot cross a page boundary; `#auditPrev`/`#auditNext` in the panel. Route + jsdom tests in `adminAuditPager.test.ts`. |
| 4.5 | **`/admin/inventory/moves` has no truncation flag consumer.** The day bound made 200/500 per-day caps; an `exact: false` field would be honest, but nothing in the panel would read it — which is the uncalled-code defect in miniature. | Reported; worth adding the day it gets a consumer. |

---

## 5 · Data, and fakes that disagree with production

| # | What | Status |
|---|---|---|
| 5.1 | **`memoryRepository.listAlerts` ignores its `userId`** (`async (_u, limit, …)`). A real fake infidelity, unrelated to any current defect. | Reported. This class of bug produced the invented mother-card vitals, so it is not cosmetic. |
| 5.2 | **Two indexes exist in migrations and not in `schema.sql`** — a fresh install lacks what every migrated server has. `pgSchema.test.ts` cannot see it: **it parses tables and columns, not indexes.** | Verified. One divergence was found and fixed this week; the guard gap remains. |
| 5.3 | **`deviceTempC` is stored but has no read path**, deliberately — storing it was the brief, surfacing it is where the ruling gets undone. It must never appear under «температура» or in a triage grade. | Verified; recorded so nobody "finishes" it. |

---

## 6 · Traps — things that look like defects and are not, or that will bite the next person

Read this section before starting anything above.

- **Do NOT delete the fever branches from `packages/shared/src/triage.ts`.** The app and server deploy independently. Every phone still on a build from before 2026-08-18 has hand entry and still sends `source: 'manual'` to `/ingest`, where the server re-runs `assessTelemetry`. Removing them would silently stop fever emergencies for those users, from a change in a different package. `minBuild` is what eventually clears them. **The twins will legitimately diverge for the first time** — everything in this repo has so far treated divergence as a defect, and that was correct only while both served the same build.
- **`ReadingSource.manual` and the provenance branch STAY**, even though the entry path is gone. Rows already typed on real phones are labelled manual and still restore from `/vitals/manual`. Deleting the entry path is not deleting the concept, and conflating them would silently re-grade every reading an existing user has.
- **`vac_bcg`, `vac_adt`, `vac_opv` are identical in ru and kk ON PURPOSE** — they are the abbreviations printed on the RK immunisation card a mother carries to the polyclinic. A Kazakh rendering she cannot match to the card is worse than the Russian one. The reasoning is in `verify_l10n.dart`'s exception list.
- **`temp_device_estimate_note` keeps «Нақты…»** though `нақты` was deleted from the device cards two keys away. That sentence is a claim about the THERMOMETER — the opposite construction to the defect. Do not harmonise it.
- **jsdom has no layout engine.** All 190 backend test files report every size as zero, so every overflow assertion passes by construction. Use `tools/ui-audit-*.cjs` against real Chrome. It had three fatal faults and had never run before 2026-08-17.
- **`packages/admin/index.html` is LF, not CRLF**, and `app/lib/l10n/l10n.dart` is CRLF. A needle with the wrong endings silently matches nothing and reports a pass. This has cost time three times.
- **Backticks inside the injected script in `ui-audit-prepare.cjs`** close its template literal and make the file unparseable — the same fault that once took the whole admin panel's script down.
- **Never `git add <dir>` on this tree. **And explicit paths are not enough either** — when a subagent is editing the same file concurrently, `git add <exact/path>` still stages its half-finished work. `770ae06` proves it. Before committing a file an agent may hold, diff it and check nothing unrelated is in there; when several agents are out, commit files none of them touch, or wait.** Four commits this week swept in work from other agents: a `REVERT PROBE` that silently disabled a staleness gate, seven scratch probes, a finished Kazakh guard labelled «partial», and a 439-line removal under a commit titled for something else. Name paths.

---

## 7 · The suite is green about things it does not check

Seven distinct instances found this week. The pattern is not that the tests are
bad — it is that **nothing in them looks at the product**.

| Found | What was not being checked |
|---|---|
| 161 fixed sleeps across 47 files | verdicts decided on a stopwatch. **44 files converted**; ~13 remain |
| A 17-minute suite | measured a tree that moved underneath it |
| Every panel test | booted through the failure path — `getContext` returns null under jsdom |
| `verify_l10n` | never compared kk to ru; «two languages» meant «three map entries» for the life of the project |
| `verify_wearable_metrics` | had not compiled in four days, and asserted the mmol/L conversion the gate REFUSED |
| `tools/ui-audit-*` | had never run once: `.mjs` over `require()`, a missing dependency, and the wrong Chrome tab |
| A test named «the cycle is hidden completely, not one tap away» | passed while the chip that opened one sat at the top of the screen |
| The cycle calendar, in the golden AND in `narrow_phone_test` | both built cycle mode from a controller with **no period logged**, so the phase card never existed in either. It overflowed its title row by 131px at 402dp — wider than the narrow sweep measures — for every user with a period logged, in Russian. Found 2026-08-18 by a test that logged one; the row is a `Wrap` now, and a logged-period case is in the sweep at 320dp/130%/kk |
| `narrow_phone_test`'s 640dp viewport | proves the FIRST SCREENFUL and no more. Below the fold on the same cycle screen, `_PredRow` (womens_health_screen.dart:2744) overflows **70px at 320dp / 130 % / Kazakh** — the accuracy badge sits after an `Expanded` column with nothing bounding it. Found 2026-08-18 by rendering the screen 900dp tall and looking at the image; **not fixed**, because every fix that cannot overflow also moves the badge at normal widths (a `Wrap` under the value, or a `Flexible` that squeezes the column via flex share). Needs a layout decision, then a taller case here |

**Remaining work:** convert the last ~13 files off fixed sleeps using
`helpers/panelSettle.ts`; teach `pgSchema.test.ts` to parse indexes; and build
the **reviewed-titles manifest's** sibling — a per-key load-bearing-token
assertion already exists (`medical_copy_tokens_test.dart`), and the fingerprint
manifest exists (`reviewed_medical_copy_test.dart`), so what is left is keeping
them fed as copy changes.

---

## 8 · Open questions for the clinical gate

Each of these was raised and deliberately not answered by an implementer.

1. **`ADV_BP_STEADY` and `ADV_TEMP_STEADY` claim steadiness from ONE reading** — title and body describe a series («держится ровно, без скачков») while the card fires on `latest`. Needs either a minimum sample count or copy about the latest reading only.
2. **`ADV_HYDRATED`** states «Водный баланс в норме» — a physiological verdict computed from a tally of glasses she tapped. Harmless on screen, not harmless in a clipboard summary a doctor reads.
3. **`ADV_SLEEP_OK`** infers sleep quality from the ABSENCE of an SpO2 dip. The review already found that a nadir with no duration cannot support a sleep claim; its absence supports even less.
4. **`bp_device_estimate_note`** does not exist. Temperature got one; the blood-pressure tile states no limitation at the place the claim is made. No copy has been written, deliberately.
5. ~~**What should an ungradeable day draw** in the peace ring~~ — **answered 2026-08-18**, see 2.2. ~~And beside it, the cycle ring's `(info.cycleDay ?? 1)`.~~ **Fixed 2026-08-18.** `cycleDay` is null with `hasData` true for exactly one reason — the last logged period start is still in the future — and the ring drew 1/28 of an arc and printed «1», i.e. «day 1», the first day of bleeding, from a `??`. It now draws NO arc and dashes the whole circle (`MetricRing(fraction: null, assessed: 0)`, the peace ring's own vocabulary), prints «—», and the card names the cause — «Месячные отмечены на 19.07» — and offers «Изменить отметку», which is the only route in the app to a future day's sheet. The same null reached `cycleBandFor` one screen along, where `null => CycleBand.follicular` put «Спокойные дни» at 21pt over a lit segment **for every brand-new account**; that band is now nullable too. Tests: `app/test/cycle_unknown_day_test.dart` (16), revert-verified — 11 fail when either fallback returns.
   **Still open, and a DIFFERENT defect:** the prediction itself rolls forward from a start that has not happened, so the same screen further down says «Месячные через 31 дн.» and «Фертильное окно через 12 дн.» while the header says the cycle day is unknown. That is a wrong ANCHOR in `computeCycle` (cycle_predictions.dart:158–160), not an invented number: the fix is to anchor on the last start **on or before today**, and it moves every prediction, every calendar colour and both cycle reminders. Needs a ruling before anyone touches it.
6. **Should the server require the phone's persistence before pushing** — see 2.6.



7. **The 5-1-1 rule already ships, unreviewed, on `LabourSignsScreen`.** Found while building the contraction timer (screen 10), which is where it was *asked* for. `lab_go_five_one_one` states «Схватки примерно каждые 5 минут по ~1 минуте в течение часа (правило 5-1-1)» in ru and kk, inside the «когда ехать или звонить» block; `lab_intro` says «когда пора ехать». This is a medical instruction — it tells a woman in labour when to leave her house — and the `lab_*` keys are **not matched by `isMedicalKey`** in `reviewed_medical_copy_test.dart`, so they carry no fingerprint and have never been through the gate. Two questions: (a) is the wording right, in all three languages, against the RK protocol rather than a foreign childbirth curriculum; (b) should `isMedicalKey` be widened to `lab_*` so it can never drift again. **Pinned meanwhile** by `app/test/contraction_timer_test.dart`, which fails both if a NEW key acquires the clause AND if these two keys are changed — so the exposure can neither grow nor be silently forgotten.

8. **The «пора в роддом» plate on screen 10 was NOT built, deliberately.** Frame 10 asks for a `#45162A` night plate reading «по минуте каждые 5 минут в течение часа — пора в роддом». The card is built and wired; its copy key `labourAlertBodyKey` is **null**, and the sentence is deliberately absent from `l10n.dart` rather than added behind a flag — a string in the catalogue is one `if` away from a screen; a string that does not exist is not. A verdict has to produce three things together: the wording in ru + kk + en pinned in the reviewed manifest, the key name, and **the threshold**, which is not assumed to be 5-1-1 as taught abroad. What ships instead is the existing non-directive 5-1-1 checklist, which reflects her own timings back and instructs nothing. See `app/lib/domain/labour_alert.dart`.

## 9 · The legal documents — written 2026-08-18, and what they cannot say yet

The 6-section DRAFT was replaced with real Privacy Policy and Terms of Use, 17 sections each, in ru/kk/en, served from `legal/legal.json` to both the app and ana-bala.kz. Writing them required an evidence-backed inventory of every category of personal data the product touches, and that inventory is what this section records.

**Three statements in the old DRAFT were false**, which is why they were replaced rather than expanded:

| # | The DRAFT said | The code does |
|---|---|---|
| 9.1 | «По умолчанию данные хранятся на вашем телефоне» | False across the whole schema. While signed in, the server holds a full copy — profile, children, diaries, screening scores, the child's emergency card, every band reading. Corrected in `legal_priv_storage_b`, which now says so as an admission rather than a softening. |
| 9.2 | Cloud use is "assistant messages, band readings, the cry recording" | Omitted the photo-to-vitals features, which upload a **photograph of a BP monitor, glucometer or lab slip** to Anthropic. A lab slip carries her surname. Now disclosed in `legal_priv_ai_b`. |
| 9.3 | «выгрузить копию всех данных» | The export file contained a **live 90-day bearer session token** — a key to the account, not a copy of data, handed straight to the share sheet. Being fixed rather than disclosed. |

**Blocking publication — owner only.** These promote to §1:

| # | What | Why it blocks |
|---|---|---|
| 9.4 | **БИН, registered address, and a contact e-mail.** The repo has only «ТОО «Ana-Bala», Алматы» and a mobile number. | ЗРК №94-V requires an identifiable operator, and Google Play rejects a policy without one. The documents carry visible blank slots `______________`; they are unfilled on purpose. "Write to us via in-app support" is not a channel for someone who has already uninstalled. |
| 9.5 | **Hosting country for 188.137.231.252.** The repo records the IP and nothing else. | Decides whether §7 of the policy is a domestic-processing paragraph or a cross-border-transfer one. Not guessed. |
| 9.6 | **Retention periods for everything that has none.** Only `location_history` is actually swept (90 days). Health tables, `safety_alerts`, orders with delivery addresses, `shop_leads`, support tickets and their bodies have no mechanism at all. | The policy currently says these are kept while the account exists, and says plainly that no number is written where no deleting code exists. Each number needs a sweep before it can be printed. |
| 9.7 | **Is an infant's cry, transmitted for classification but never stored, «биометрические данные» under №94-V?** | Changes whether separate written consent is required before the microphone opens. The code facts are settled; the classification is a lawyer's call. |

**Decided this session:** minimum age is **16**, not 18 — pregnancy under eighteen exists, and an 18 gate would not stop those users, only make them state a false age and go without support. Written into `legal_priv_age_b` with that reasoning, and it needs a consent path for 16–18 that does not exist yet.

**Established and worth keeping** (each verified from code, not assumed):

- The cry chain is honest and tested: recorded to a temp file, uploaded, proxied, decomposed in memory, **never written to disk anywhere**, only a reason word and confidence stored. `cryNotStored.test.ts` watches every repository method for the bytes rather than a whitelist. The policy states the uncomfortable half out loud — the sound *does* leave the phone — because the tempting sentence «звук не покидает телефон» would be a lie.
- **EPDS answers are never stored**, by schema design, because item 10 asks about self-harm. Only the score, readable only on an individual record, never sortable.
- **No analytics SDK and no crash reporter exist in the app.** Genuinely true, and now stated.
- Broadcast segmentation cannot express a rule over readings — a blood-pressure rule is refused with a message. It *does* use pregnancy status and child age, so the policy says that rather than the flattering version.
- Family sharing has **no expressible level** that reaches the mother's own record.
- Staff reads of an individual's health record require a written reason of 8+ characters, refused rather than auto-filled.

| # | Smaller, ours to fix | Status |
|---|---|---|
| 9.8 | ~~The panel prints «Журнал доступа — 3 года» and nothing deletes `audit_log`, ever.~~ It sat as a bare literal directly beneath a comment claiming the screen «cannot drift from what actually runs». The card now says «хранится бессрочно — срок не задан» and prints no number, so the one real sweep (90-day routes) is not flanked by a fictional peer. | **Fixed.** The PERIOD is still owner-only — see §9.6. |
| 9.9 | ~~Screen 47 prints «Маршруты хранятся 90 дней» beneath crossings and SOS events that are not routes and are not swept.~~ Two lines now: the route line only when a route was actually returned, the events line always and with **no number in any language**, pinned by a digit-level test. Wording taken from the policy, so the screen and the published document agree. | **Fixed**, `7ddf4cc`. Kazakh was written, not gate-reviewed — see §9.12. |
| 9.12 | **Kazakh written by a non-gate agent** in `day_retention_route` / `day_retention_events` and in `db_ring_partial` («4 ішінен 2», chosen to dodge the numeral possessive). Grammatical and `verify_l10n`-clean, but not reviewed. **Now five more, from the §8.5 fix (2026-08-18):** `cyc_day_unknown`, `cyc_future_mark_title`, `cyc_future_mark_body`, `cyc_future_mark_fix`, `cyc_no_phase`. Marked in place with a comment above the block in `l10n.dart`. **Now eight more, from the screen-10 rebuild (2026-08-18):** `contr_live_active`, `contr_live_rest`, `contr_start_big`, `contr_stop_big`, `contr_stop_sub`, `contr_recent`, `contr_history_short`, `contr_awake_note`. Marked in place with a comment above the block in `l10n.dart`. All eight are plain UI labels — none states a threshold, names a symptom or instructs anything clinical, which is why they were writable at all; the one string on that screen that WOULD have done so is absent from the catalogue entirely (§8.8). `contr_stop_sub` is the one to look at first: «Босаңсығанда басыңыз» renders "when it slackens", and a midwife should say whether that is what a labouring woman reads it as. Sixteen keys total on this list now. `cyc_future_mark_title` is the one to look at first: it interpolates a date into a case-bearing position («Етеккір {d} күніне белгіленген»). **And one more, 2026-08-18:** `cry_error` was rewritten (it told a mother to record «в тишине» for a failure that is a missing `model.pkl`, not noise) and its Kazakh — «Кеңес шықпады, жазба телефонда қалмады. Қайталау көмектеспесе — жылауды талдау қазір қолжетімсіз, мәселе сізде емес.» — was written, not gate-reviewed. Look at «мәселе сізде емес» first: it carries the whole point of the sentence, which is that she should stop retrying and that it is not her fault. **And five more, 2026-08-19, from the 502/503 split (§9.13):** `cry_unavailable`, `cry_clip_deleted`, `cry_not_sent`, `cry_checking`, `cry_recheck` — written with the widget that prints them, marked in place with a comment above the block in `l10n.dart`. `cry_unavailable` is the one to look at first: «бұл біздің жақта, сізде емес» has to land as "this is ours, not yours" and not as an accusation, and it is the string a mother reads every time she opens the detector until a `model.pkl` exists. `cry_not_sent` is second: it distinguishes «жіберілмеді» (never sent) from «талданбады» (not analysed), and that distinction is the whole point of the string. **And four more, 2026-08-19, from the SOS honesty fix (§10.1):** `sos_sending`, `sos_not_sent`, `child_checkin_local`, `alert_not_sent` — written with the widgets that print them, marked in place with a comment above the block in `l10n.dart`. `sos_not_sent` is the one to look at first, and it is the highest-stakes string on this list: it is what a mother reads on the worst minute of her year, and «жақындарыңыз хабарлама алмады» has to land as *the family were not told* — not as *a request failed* — because the sentence after it asks her to phone them herself. `alert_not_sent` is second: it is a feed-row label that must read as «this never left the phone», not as «this was cancelled». | Open — one pass by the language gate. Eighteen keys.  |
| 9.10 | ~~The landing lead form takes a name and phone under a bare consent line with no link to the policy.~~ Both forms now link «обработкой персональных данных» / «дербес деректерді өңдеуге» to /privacy in their own language. Both halves had to be true first: a real document, and a link to it where the data is taken. | **Fixed.** Pinned by `landingHonesty.test.ts`, which also fails if a form loses its consent line entirely. |
| 9.11 | ~~`docs/CLAUDE-app-design.md:485` says «Плач считается на телефоне». The build does not do that.~~ The spec sentence has been **corrected in place**: §7 now states that the recording goes to the server for analysis and is not kept, and says why the old sentence was wrong, so the next reader cannot re-derive it. The frames 15a–15e block carries the same prohibition, and `docs/DESIGN_DEVIATIONS.md` § «Детектор плача» records the refusal with the three reasons. `cry_privacy` itself is unchanged — it was already right, and `cry_privacy_test.dart` pins it. | **Fixed in the spec**, 2026-08-18. The trap remains real for the visual reference, which still carries both claims. |
| 9.13 | Frames 15a–15e are **specified but not built**. The screen exists (`cry_insight_screen.dart`); the remaining gaps are: no «Стоп» during recording (the button is nulled during `_Phase.recording`, so a recording of her own child cannot be aborted), no countdown, no mic-denied action, no bottom action bar, and 15a is a flat nine-row sheet with no counts. See `docs/CLAUDE-app-design.md` § «Что эти пять кадров означают построчно» for the decided order, states and copy. | **The 502/503 split is done**, 2026-08-19 — the rest is open. The proxy no longer flattens every upstream failure into 502: `packages/backend/src/cry/upstream.ts` maps the classifier's own 503 → 503 `cry_service_unavailable`, 400/413/415/422 → 400 `cry_audio_unreadable`, and a timeout / refused connection / 5xx → 502. The app shows a different state for each (`cry_unavailable` / `cry_error` / `cry_not_sent`), and — the part that matters — a new `GET /cry/availability` is asked BEFORE the microphone opens, so with no `model.pkl` her baby's cry is no longer recorded and uploaded for a guaranteed refusal. Pinned by `app/test/cry_service_state_test.dart` and `packages/backend/src/__tests__/cryServiceSplit.test.ts`; `cryNotStored.test.ts` gained the 503 branch so the new path cannot grow a retry queue. |

## 10 · Fresh audit, 2026-08-19 — the app

Two auditors swept the tree after 24 commits. Neither was allowed to change anything, and both declined the revert-probe step for the same reason: two agents held the tree, and §6 records four commits this week that swept in half-finished work. What the app auditor did instead was stronger — it **ran** the guards, and found four of them do not execute at all.

Everything below is new. Nothing here was in this document before.

### The SOS path — three defects, and they compound

| # | What | Status |
|---|---|---|
| 10.1 | **«Сигнал SOS отправлен» is printed without checking anything.** `onSos` is a `VoidCallback?` and structurally cannot report failure; the send routes through `sync_push.dart:55`, which returns silently for anything that is not a 4xx — so offline, 5xx, timeout and **401** are all silence — and `main.dart:874-877` records there is deliberately no replay, so nothing retries. A mother in a basement car park taps SOS, reads that it was sent, and no relative is pushed and no back-office row exists. A third path drops it before the request is even attempted: `main.dart:881`, an SOS for a child whose local name does not match a synced child. | **Fixed**, 2026-08-19. `logChildEvent` returns whether the SERVER took it, `pushed()` reports success as well as refusal, `onSos` is a `Future<bool> Function()?`, and the confirmation prints «Сигнал SOS отправлен» ONLY on an answer from the server — otherwise «Сигнал не ушёл… Позвоните им сами или в 103.» The unmatched-child path returns false and writes to the error log instead of `return;`. The feed row carries `delivered` and `alerts_screen.dart` marks it «Не отправлено — только на этом телефоне». A retry runs on reconnect and on sign-in, **bounded by `sosTakeoverMaxAge`** so it cannot become the first-sync replay `main.dart` already refused. Pinned by `sos_delivery_test.dart`. |
| 10.2 | **The push carries the child's coordinates; the app parses them, drops them, then prints «Приложение не получало координат».** `NotifyTap.coords` has no caller in `app/lib` — its only reference is a test. The server sends `lat`/`lng` with a comment saying the app parses them back. A mother tracking her elder child taps the younger's SOS and is told the app does not know where she is, **which is false** — the position was in the payload she just tapped. | **Fixed**, 2026-08-19. `handleNotificationTap` reads `tap.coords` and passes it to `raiseSosAlert(alert, coords:, coordsAt:)`; `_sosViewFor` picks whichever position it can PROVE is newer, so a sibling's polled fix is still never borrowed and «Приложение не получало координат» survives for the case where there genuinely are none. `coordsAt` is the push's own `at` — the card prints that age, and inventing it would be inventing a freshness. |
| 10.3 | **A tapped SOS raises the red takeover at any age.** `sosTakeoverMaxAge` exists and `mergeRemoteAlerts` honours it; `handleNotificationTap` calls `raiseSosAlert` directly, which does not. Resolved at 09:00, tray cleared at 21:00 → full-red takeover, heavy haptic, `canPop: false`. This is `e03f09d`'s alarm-fatigue defect, fixed for the mother's own emergency and left standing for her child's. | **Fixed**, 2026-08-19. `sosTapAge` — the same three-outcome decision as `emergencyTapAge`, undatable raises nothing — against `sosTakeoverMaxAge`, which moved to `notification_route.dart` so both the Flutter-free tap handler and `AppController` read ONE constant. Deliberately not the six-hour medical window; the reasoning is in the constant's doc. A past or undatable tap opens the notification centre instead. **The invented time is gone too:** `at: tap.at ?? DateTime.now()` no longer exists, so nothing writes a feed row it cannot date, and the false claim in `notification_route.dart:167` that screen 21 «falls back to the moment it opened, and says so» was deleted rather than made true. |

### The guards that do not run

| # | What | Status |
|---|---|---|
| 10.0 | ~~CI has been red on every push and PR since 2026-08-14.~~ **GREEN.** `dart run tool/verify_all.dart` → exit 0, 82 runners, **3138 assertions, 0 failed** — up from 2756 with 2 failing. Both causes closed. | **Fixed**, `d250962` + this. |
| 10.4 | **Four verify runners have not compiled since 2026-08-14, and `verify_all` still prints «2756 assertions passed».** `verify_alerts`, `verify_app`, `verify_chat`, `verify_persistence` all die identically: `AppController` imports `vaccination_schedule_repository.dart`, which imports `package:flutter/foundation.dart` and `shared_preferences`, dragging `dart:ui` into a `dart run` VM. Zero assertions execute. **`f8eefdd` added seven assertions to `verify_persistence` yesterday guarding the nudge snooze round-trip. They have never run once.** | Open. `app_controller.dart:27`. |
| 10.5 | ~~`verify_datemath` is red — 3 hits stepping by elapsed time.~~ All three now use `addDays`. The load-bearing one is the due date: `Duration(days: 280)` is 280 × 24 h of ELAPSED time, and every pregnancy week, antenatal window and labour date anchors to it. | **Fixed.** |
| 10.6 | ~~`verify_destructive` is red on a false positive.~~ Exempted in the tool, keyed on the undo bar own label so it goes stale visibly if that moves. | **Fixed**, `d250962`. |

### Release hazards

| # | What | Status |
|---|---|---|
| 10.7 | **`currentAppBuild = 1` is hand-maintained, guarded by nothing, and unmentioned in `docs/RELEASE.md`.** Ship `0.1.0+2` without bumping it, raise `minBuild` to 2 to retire release 1, and `appUpdateRequired(1, 2)` is true on **every phone including the ones that just updated** — `ForceUpdateScreen` renders before onboarding and before the emergency screen, with no way past. Everyone is walled out of the current build. `f8eefdd` made the soft nudge read the same constant, so it matters more now than yesterday. | Open. `app_version.dart:14`. |
| 10.8 | **`docs/RELEASE.md:112`'s store-build command omits `API_BASE`.** `main.dart:600` defaults it to `http://localhost:8080`, so an `.aab` built by following the runbook verbatim talks to the handset itself: no sign-in, no sync, no catalogue, and the force-update gate and the new nudge both permanently silent. `GO_LIVE_APP_API.md` has the mirror-image error; only `DEPLOY.md:358-360` has both defines. | Open. |

### Numbers and last miles

| # | What | Status |
|---|---|---|
| 10.9 | **«Средний цикл: 28 дн.» is asserted after ONE logged period** — with one start there are no gaps, so `avgCycle` stays the default, `hasData` is still true, and the next-period date, fertile window and ovulation date are all rolled forward from a number she never provided. `predictionConfidence` already knows (`completedCycles <= 0 → low`) and `cycleBaselineDays` already distinguishes «she chose 28» from «nobody chose anything»; neither reaches this line. Same shape as the «день 1» fallback closed in `359fb8d`, one card lower on the same screen. | Open. `cycle_predictions.dart:111`. |
| 10.10 | **The SOS screen's «N минут назад» is computed once and never ticks.** `now: DateTime.now()` is evaluated in `_rootFor`; the screen has no ticker. It opens saying «2 мин назад» and still says it forty minutes later. The absolute time stays right, which is why it never looks broken. | Open. `app.dart:189`. |
| 10.11 | **The error screen tells her to go back and never draws the button.** `err_body` says «Вернитесь на главный экран»; the button is behind `if (onRestart != null)` and `onRestart` is passed nowhere in `app/lib`. `err_back` is translated into three languages and no user can ever see it. A screen that throws at the app root is a dead end whose own copy instructs an action it does not offer. | Open. `error_fallback.dart:57-62`. |
| 10.12 | **The newborn weekly card computes a sleep-per-day average and renders only feeds and nappies.** Sleep is loggable on that screen and summarised per day. A mother logging naps to answer «how much is she sleeping?» gets two of the three numbers it computed. | Open. `newborn_log.dart:196`. |
| 10.13 | **The whole battery-adaptive scan module has no caller** — four `ScanPlan`s, a debounced accelerometer gate, a foreground/background hook, and `BleDeviceManager.setScanMode` documented as "called by AdaptiveScanController.apply" and called by nothing. BLE and location never drop to low power when the phone is backgrounded and still. Battery, not safety. | Open. `adaptive_scan_controller.dart:35`. |
| 10.14 | Five public `Ds*` components — `DsHeroMetric`, `DsStatTile`, `DsSegmented`, `DsScreenHeader` — are finished, styled, tested, and built by no screen. Inventory, not harm. | Open. |
| 10.15 | **The Kazakh `upd_title` says the update is *required*** («Қолданбаны жаңарту қажет») on a build the server still supports; ru and en both read as optional. The key is shared by the hard block and the new soft strip. One key for the language gate. | Open — §9.12. |
| 10.16 | ~~«Выгода» can be computed from a compile-time watch or tracker price with `isApproximate` false and no freshness note.~~ `isApproximate` answers «is the КОМПЛЕКТ price confirmed»; it was being read as «is anything on this card confirmed». New `comparisonIsApproximate`, and the note fires only when the comparison is actually DRAWN — warning whenever a part is missing would fire on a shop that simply does not sell one. | **Fixed.** |

---

## 11 · Fresh audit, 2026-08-19 — backend, data and the panel

### Accountability — the mechanism that proves nobody read her record unexplained

These four are one story. Each under-reports alone; together the «Безопасность» page shows a reassuring zero while a named woman's vitals are read all month.

| # | What | Status |
|---|---|---|
| 11.1 | **`view_wearable` is not in `PROTECTED_ACTIONS`.** Same `health` capability, same mandatory reason, and the route's own comment calls it special-category data about a named person. A clinician opens her heart rate, SpO2, blood pressure, stress and breathing fifty times and frame 22 reports `protectedReads: 0`; her name never appears in `recent`; `withoutReason` — the number that page exists to make non-zero — structurally cannot see the route. `security.test.ts:37-44` asserts four memberships and never that the map covers every reason-gated route. | **Being fixed.** `security.ts:21-30`. |
| 11.2 | **«без причины: 0 за 365 дней» is computed over the newest 5000 audit rows.** `listAudit` now returns `hasMore` and the call site discards it. Throttled feed writes from every open tab mean 5000 rows is days, not a year. Whoever answers a regulator reads a clean twelve months that was never queried. Same at `admin.ts:989` for the owner dashboard. `summarizeSecurity` itself is correct — the defect is at both call sites. | **Being fixed.** `admin.ts:1138`. |
| 11.3 | **The «зачем открываете карту» reason is cached per browser tab and never cleared** — not on drawer close, not on view change, not on sign-out. Against a 12-hour staff session that is a shift. Open her card at 09:03 with «Разбор жалобы», reopen at 17:40 for something unrelated, and three fresh audit rows are written at 17:40 carrying the 09:03 sentence. The published policy says «журнал, заполненный машиной, выглядит проверенным, будучи непроверяемым» — a cached reason is machine-filled for every read after the first. | **Being fixed.** `index.html:5227`. |
| 11.4 | **`/admin/finance` computes any window from the newest 1000 orders and 2000 stock moves.** A sale writes one move per order line, so 2000 is reached long before 1000 orders. Ask for last February and the CSV prints «Доля возвратов, % — 0,0» — a fabricated zero where the answer is unknown, under three confident caveats none of which is the true one. The right pattern exists in the same file: the mother card sends `ordersTruncated`. | **Being fixed.** `admin.ts:3426`. |

### The rest

| # | What | Status |
|---|---|---|
| 11.5 | **`createMemoryRepository` ignores `userId` on seven per-user reads and one write.** `upsertDayLog` is the sharp one and it is a WRITE: memory keys by date alone while pg is `ON CONFLICT (user_id, log_date)`, so a second mother saving her diary destroys the first's row. §5.1 recorded exactly one of these and called it unrelated to any current defect; it is eight, one destructive. Dev-only — but it means no isolation test written against this fake can fail. | Open. `memoryRepository.ts:1356`. |
| 11.6 | **`db/seed-staff.mjs` — the documented lockout-recovery path can only mint a full-power account.** It still validates against `['admin','clinician','support']` while `staffAdmin.ts` moved to all eight roles. The only accepted role that restores access is `admin` = ALL capabilities, so a warehouse hand seeded from the shell gets `health` and `finance` — a mother's record and a child's location — because the script refuses `warehouse`. | Open. `seed-staff.mjs:49-51`. |
| 11.7 | **The landing self-check in `landing-stack.sh` cannot fail.** Three `grep -q … && echo` lines inside `docker run … sh -c '…'`, where the outer `set -euo pipefail` does not reach, and the `sh -c` status is `printf`'s — always 0. Ship a landing page without `landing/wire.js` — the lead form's entire callback path on the monetisation surface — and it prints three lines instead of four, prints a byte count, says «Backend is up» and exits 0. Nobody notices until a week of zero leads. `verify-live.sh` and `update.sh` got this right; this file did not. | Open. |
| 11.8 | Four phone-keyed stores survive account deletion and are **not among the four the policy enumerates**: `phone_codes` (an abandoned sign-in leaves the row for ever), `user_login_attempts`/`staff_login_attempts`, `device_registry.activated_by_phone`, `shop_leads`. None is health data, so the harm is smaller than the omission implies — but `legal_priv_retention_b` is written as a complete list and is not one. | Open — owner, with §9.6. |
| 11.9 | `shop_orders_phone_normalized` is in migration 023 and not in `schema.sql`. Every migrated server has it; a fresh install does not. `pgSchema.test.ts` parses tables and columns only. **Every other migration was diffed: no other divergence exists.** | Open. Surviving half of §5.2. |
| 11.10 | **`.github/workflows/deploy.yml`'s "nothing ships unless the suites are green" gate cannot run as written** — `npm ci` in `packages/backend` with no lockfile there, and `npx vitest run` from that directory misses the root config whose own header records why the default timeout fails two jsdom suites. Fails closed, so no bad build ships — but the gate the file describes is not the gate that exists. | Open. |
| 11.11 | ~~`GET /account/entitlements` has no caller.~~ **NOT the usual defect — moved to §6 as a trap.** `FEATURES` has one entry, and `/course/lessons` answers the same question from the SAME `hasEntitlement(phone, MAMA_COURSE)` with the same normalisation, so the two cannot disagree and the app reads the one that also carries the lesson list. Nothing is broken for a user. Kept, not deleted: correct, authenticated, tested twice, and the right home the day FEATURES gains a second member. | **Ruled.** Annotated in the route so it is not re-reported. |
| 11.12 | **`npx tsc --noEmit` at the repo root checks nothing** — there is no root `tsconfig.json`, so it prints the compiler help and exits 1. `.claude/agents/anabala-auditor.md:40` instructs every auditor to run exactly that. The real command is `npm run typecheck`. | Open. |

### What the audits checked and found clean

Worth recording, because a list that only grows is one nobody trusts: `AUDIT_ACTIONS` drift is closed (68 written actions, zero unlabelled); **every one of 213 `/admin` routes has a panel caller**; no route returns personal data under the wrong capability; `x-staff-id` spoofing is refused whenever `DATABASE_URL` is set; the 90-day route sweep is real, scheduled, and logs its failures as loudly as its successes; entitlement grant-on-fulfilment agrees between both repositories; the dashboard's revenue, average check and city numbers all trace to filtered SQL with the right denominators; and `verify-live.sh`, `update.sh` and `landing-takeover.sh` all avoid the `grep -q`-under-`pipefail` inversion deliberately, with the reasoning written down.

On the app side: the weekly digest divides by nights-with-data rather than by seven; the newborn week prints its divisor; the shop's freshness note covers the empty, cached and withdrawn-bundle cases; and `soft_update_nudge_test.dart` drives every case from an HTTP response through the real refresh into painted widgets — it is not decorative.

Four things that look like defects and are not are recorded in §6 rather than here.
