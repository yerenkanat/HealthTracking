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
| 3.5 | **The splash screen is a coral circle with a white heart**; the welcome screen one frame later is the crimson `#D6004A` lotus. The first thing anyone ever sees is a different mark. | Open. Verified on device. |
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
| 4.6 | **`AUDIT_ACTIONS` is missing ~20 labels** the server actually writes: `broadcast_*`, `category_upsert`/`category_delete`, `edit_cry_threshold`, `emergency_help_review`, `integration_check`, `pregnancy_week_review`, `product_photo_*`, `product_update`, `support_*`, `view_finance`, `view_wearable`. Frame 23 prints them in English. | Verified by diffing `writeAudit` call sites against the map. No guard exists to stop the next one drifting. |
| 4.2 | **`latestBuild` / `appUpdateAvailable`** — the server sends it, `api_client.dart` parses it, the predicate exists, and `main.dart:601` reads `v.minBuild` and never `v.latestBuild`. So there is no soft-update nudge: a mother sits on an old build until it drops below `minBuild` and is force-walled with no warning. | Verified, with the blocker named: the only update strings say «больше не поддерживается», so reusing them would tell a woman on a SUPPORTED build that hers is not. Needs new RU/KK/EN copy. |
| 4.3 | **`db_empty_body`** still reads «Наденьте браслет — и данные появятся здесь» — the band upsell the spec forbids — but no `lib/` file asks for that key. Invisible today; a trap for whoever wires an empty state next. | Reported. |
| 4.4 | **Журнал has no pager** — same shape as the caseload pager already fixed, but `/admin/audit` returns no total, so wiring it honestly needs a repository change. | Reported. |
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
5. ~~**What should an ungradeable day draw** in the peace ring~~ — **answered 2026-08-18**, see 2.2. Still open beside it: the cycle hero draws `(info.cycleDay ?? 1) / info.avgCycleLength` and prints «1» in the middle of the ring when the app does not know the day (`womens_health_screen.dart:1223`) — a fallback painted as a measurement, reachable when a period is logged with a future date.
6. **Should the server require the phone's persistence before pushing** — see 2.6.

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
| 9.8 | The panel prints «Журнал доступа — хранится 3 года» and nothing deletes `audit_log`, ever. | Open — a stated period with no mechanism, the same class as 9.6. |
| 9.9 | ~~Screen 47 prints «Маршруты хранятся 90 дней» beneath crossings and SOS events that are not routes and are not swept.~~ Two lines now: the route line only when a route was actually returned, the events line always and with **no number in any language**, pinned by a digit-level test. Wording taken from the policy, so the screen and the published document agree. | **Fixed**, `7ddf4cc`. Kazakh was written, not gate-reviewed — see §9.12. |
| 9.12 | **Kazakh written by a non-gate agent** in `day_retention_route` / `day_retention_events` and in `db_ring_partial` («4 ішінен 2», chosen to dodge the numeral possessive). Grammatical and `verify_l10n`-clean, but not reviewed. | Open — one pass by the language gate.  |
| 9.10 | ~~The landing lead form takes a name and phone under a bare consent line with no link to the policy.~~ Both forms now link «обработкой персональных данных» / «дербес деректерді өңдеуге» to /privacy in their own language. Both halves had to be true first: a real document, and a link to it where the data is taken. | **Fixed.** Pinned by `landingHonesty.test.ts`, which also fails if a form loses its consent line entirely. |
| 9.11 | `docs/CLAUDE-app-design.md:485` says «Плач считается на телефоне». The build does not do that. | Spec is wrong, not the code. Do not copy that sentence into anything. |
