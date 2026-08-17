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
| 2.2 | **The peace ring's empty-pool default is `1.0`** — a day whose only readings are a wrist BP now skips every metric and draws FULL. A reassurance arriving from an ABSENCE of data, and the provenance gating made it more frequent. | Reported. Needs a ruling on what an ungradeable day should draw. |
| 2.3 | **`handleNotificationTap` has no staleness check.** Tapping an emergency notification hours later re-raises the full emergency takeover for a crossing long past. | Reported during the episode-suppression work; out of that agent's boundary. |
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
| 3.3 | **Denying the Bluetooth permission bounces back a step and clears the name and phone**, while keeping the pregnancy toggle and due date. Partial loss is worse than total: the survivors make the losses look deliberate. | Open. Verified on device. |
| 3.4 | **The name requirement is not re-applied after that bounce** — «Далее» is enabled with an empty name and advances, though the same empty field disabled it minutes earlier with «Напишите имя, чтобы продолжить». | Open. Verified on device. |
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
| 4.1 | **The whole vaccination editor** — seven routes, zero panel callers. `admin.ts` says «the immunisation calendar is now editable»; it is editable by curl. A vaccine wording error or a Ministry schedule change needs a developer and a release. | **Attempted twice, both agents died.** Largest remaining user-facing gap. |
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
- **Never `git add <dir>` on this tree.** Four commits this week swept in work from other agents: a `REVERT PROBE` that silently disabled a staleness gate, seven scratch probes, a finished Kazakh guard labelled «partial», and a 439-line removal under a commit titled for something else. Name paths.

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
5. **What should an ungradeable day draw** in the peace ring — see 2.2.
6. **Should the server require the phone's persistence before pushing** — see 2.6.
