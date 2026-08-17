# Clinical gate — the watch vitals · 2026-08-13

The verdict on the readings the watch pipeline put on screen. Recorded here
rather than left in a task result, because three of six were **refused** and a
refusal that lives in chat gets rebuilt by the next person who thinks it would
be nice to show.

Checked against the sources this product already cites — the RK MOH 8-visit
protocol (`packages/contract/antenatal_protocol.json`), its own triage
thresholds (`packages/shared/src/triage.ts`), the reviewed bilingual danger-sign
list (`packages/contract/emergency_help.json`), and the vendor's own
`docs/UniappSDKDocumentation.md`. Where none of those covers a number, that is
said rather than a number being supplied.

## Verdicts

| Metric | Verdict | Why |
|---|---|---|
| Heart rate + day min/max | **CHANGES** | The extremes are unlabelled. A day min is the sleeping minimum and sits under our own `HR_BRADY_WARNING = 50`; a max sits over `HR_TACHY_EMERGENCY = 140`. Both are ordinary — sleep, and stairs. Label them; never colour them. |
| SpO2 + day minimum | **CHANGES** | Renders as `(88–—)`, which reads as a truncated range rather than a floor. And a nadir with no duration and no sleep flag cannot support the sentence the migration comment gives it. |
| **Blood pressure (day average)** | **REFUSED** | No maximum column exists, and the peak is the clinical object: a day touching 158/104 and sitting at 105/68 prints «118/76» and looks reassuring while failing. Our own `emergency_confirmation.dart` puts wrist PPG BP at ±10–15 mmHg against a 140 threshold — the uncertainty is the size of the decision. Calibration state is not on the row. |
| **Temperature (day average)** | **REFUSED** | A four-hour fever at 38.6 inside an otherwise-36.6 day averages to 36.9 — the statistic hides what it would be opened to find. And nobody can say what the degrees are relative to: the OEM band path applies `skinToCoreTempC`, the Starmax path does not, and the vendor states no reference site and no accuracy. Two code paths in one product disagree about the meaning of the number. |
| **Blood sugar** | **REFUSED** | The vendor documents `血糖（0.1）` with **no unit stated anywhere**. We divide by ten and print «ммоль/л» — a unit our source never claims — on a diabetes number, to pregnant women, in a country where GDM screening is a scheduled protocol item. It also displaces the OGTT window at 24–28 weeks, which closes. |
| The min/max construct | **CHANGES** | Right idea, inverted priority: extremes were stored for the two metrics where a mean is least misleading (HR, SpO2) and omitted for the two where it is most (BP, temperature). Fix the columns before the copy. |

## The qualifier was insufficient on four counts

1. **Unactionable for its reader.** «Сверяйте с тонометром» tells someone in an
   office to measure a woman who is not in the room.
2. **It qualifies the sensor, not the statistic.** Nothing said these are daily
   MEANS, which is the more dangerous omission — it makes an inadequate figure
   look adequate.
3. **Once per card is not once per reading.** It scrolls off by about day five
   of fourteen. The place a claim is made is the row.
4. **The app has no qualifier at all**, in any language. The vitals grid states
   freshness, span and connectivity, and never that the numbers are estimates.
   «Не медицинский прибор» exists only on the legal screen in Settings — a
   footer three taps from the number is not a qualifier on the number.

Also corrected: the panel's own docstring said this block answers a support
operator's question. `/admin/users/:id/wearable` requires `health`, which
`operator`, `support` and `seller` do not hold. The untrained reader is the
**owner**, and the wording has to be written for them.

## Freshness must differ per metric

A step count from nine hours ago is a complete fact about a finished period. A
blood pressure from nine hours ago is a claim about a body that has since moved,
eaten and slept. One ladder for both is a category error, and the current
arrangement gets both ends wrong: the panel dims only past **48 h**, so a stale
preeclampsia-range reading is drawn at full strength for forty-two hours.

| Metric | Full colour | Grey, age shown | Not shown as current |
|---|---|---|---|
| Blood pressure | ≤ 4 h **and** calibration ≤ 8 days | 4–12 h | > 12 h, always when calibration is stale |
| Heart rate | ≤ 6 h | 6–24 h | > 24 h |
| SpO2 | ≤ 6 h, sub-95 only with the sleep flag | 6–24 h | > 24 h |
| Temperature | never coloured — recommended removal, and **barred from `emergency` severity at any freshness** (see below) | — | — |
| Blood sugar | never shown | — | — |
| Steps · distance · calories · sleep | 48 h is fine | — | — |

4 h is ACOG's repeat-reading interval, already cited in
`emergency_confirmation.dart`. 8 days is `bpCalibrationMaxAgeDays`. 6 h is
`latestTelemetryMaxAge`. None of these is invented here.

## Sentences that must never appear

Refused in advance, with the reason, so they are not re-proposed:

1. «Ваше давление сегодня 118/76» — asserts a measurement.
2. **«Ваши показатели в пределах нормы» — this SHIPS TODAY** as
   `db_peace_stable_b`, in all three languages. It is a normality verdict on a
   body, from an uncalibrated wrist estimate of unknown age. Replace with a
   statement about the readings: «Часы не увидели ничего необычного в этих
   оценках.»
3. «Давление в норме, преэклампсии нет» — the protocol pairs BP with urine
   protein at every visit from the second. A wrist estimate cannot exclude it.
4. «Температуры нет» — from a daily mean.
5. «Сахар в норме» — from an optical estimate in an undocumented unit.
6. Anything that could defer the OGTT at 24–28 weeks.
7. Any invented "normal range". `triage.ts` publishes ACTION thresholds and its
   header explains why.
8. «Низкий кислород ночью» / «апноэ» — a nadir with no duration cannot support
   either word.
9. «Мы сообщили вашему врачу» — no such channel exists.
10. «Мы вызвали скорую» — the app is not a rescue service. The reviewed pattern
    is «Звоните 103», imperative to her.
11. «Мы следим за вашими показателями круглосуточно» — the watch stops the
    moment she takes it off.
12. **«Если что-то будет не так, приложение вас предупредит»** — the strongest
    false reassurance available here: it turns every gap in coverage into an
    implied all-clear. Refused in every phrasing, including softened ones.
13. «Показатели в норме — визит можно перенести», in a mother's card.
14. Any of the above added as a `medical: true` card on the strength of "the
    panel already says something like it".
15. **«Температура по браслету держится ровно» — `ADV_TEMP_STEADY`, from a
    device-derived sample. SHIPS TODAY** at `l10n.dart:102`. A normality verdict
    on a body, from a wrist estimate whose dominant error term is the room, and
    it fires off ONE sample. The same defect as #2, and worse in effect: the
    woman whose wrist reads 35.9 while her core is 39 is not met with silence,
    she is reassured by name. It may remain for a thermometer reading she typed
    in, where it is true.
16. «Температура повышена» — `ADV_TEMP_ELEVATED` — from a device-derived sample.
    Asserts her temperature. And «измерьте снова» does not name the instrument,
    when the only one to hand is the same wrist; re-reading it is not a second
    measurement.
17. **«Давление повышено» — `ADV_BP_ELEVATED_b` — from a device sample.** The
    card's own firing window (135–139 / 85–89) sits ENTIRELY INSIDE the
    ±10–15 mmHg the wrist estimate carries, so the sentence states as fact the
    one thing the reading cannot establish. «Измерьте снова» repeats #16, and is
    worse here: a wrist BP also depends on a calibration that expires at 8 days,
    so the repeat can be wrong in the same direction indefinitely.
18. **«Выпейте воды» as a response to raised blood pressure.** Hydration is not
    a treatment for hypertension, no cited source offers it, and beside «при
    стойком повышении» it produces wait-and-see on the one condition this
    product exists to catch. A woman with a wrist 137 and a headache with visual
    sparks was being told to rest and drink water.
19. **A bare unitless systolic as a card badge.** Half a reading, no unit, in
    bold, beside copy explaining it is not a measurement.
20. **A cuff threshold printed beside a wrist estimate.** Numeric permission
    follows the SOURCE, not the metric — see the asymmetry ruling below.
21. **«Всё стабильно» / «Всё стабильно, {name}» / «Ваши показатели в пределах
    нормы» — `ADV_ALL_STEADY`, `db_peace_stable`, `db_peace_stable_noname`,
    `db_peace_stable_b`. LIVE.** `db_peace_stable_b` is refused sentence #2
    shipping **unchanged, one day after it was written down here**, and the
    banner attaches her NAME to a normality verdict. Replaced by
    `ADV_NOTHING_UNUSUAL`; the old keys are deleted so no call site can keep
    rendering them.
22. **«Сахар в норме» — `ADV_GLUCOSE_STEADY`. LIVE, and it is refused sentence
    #5 word for word** — on an optical estimate in a unit the vendor never
    states, in the app, after the same metric was withdrawn from the panel.
    **«Низкий сахар» — `ADV_GLUCOSE_LOW`** asserts hypoglycaemia from that same
    undocumented unit.
23. **A device blood pressure counted as "healthy"** in the dashboard ring or
    graded green on a tile. It may turn the ring RED — the product does escalate
    device BP at 140/90 — but it may not contribute reassurance, and the 135/85
    it would be graded against is uncited.
24. **Any advisory title that needs its body to be true.** The clipboard export
    sends titles only; a title is a standalone published sentence.

## Triage changed once — here is what did not

`assessTelemetry` is fed by the live snapshot; backfilled days go to
`wearable_days` and never enter triage. That is correct — an emergency raised
from an eleven-day-old reading is a false alarm by construction. The three
tempting next commits, all refused:

1. **Never feed a day extreme into triage.** The SpO2 branch depends on
   `duringSleep` to choose between warning and info; a day nadir has no such
   flag and would lie to it.
2. **Never let a backfill retro-fire an emergency.** Days arrive progressively
   during a sync; a woman pairing a watch on Tuesday would get last Thursday's
   emergency screen.
3. **No trend rule.** «Давление растёт третий день» from three daily means, each
   ±10–15 mmHg and possibly uncalibrated, is a diagnosis dressed as an
   observation.
4. **Never unify the three temperature sources into one rule.** A patch that
   lowers manual entry to `warning`, or raises a device reading to `emergency`,
   is a rejection of this review and must not ship. The correct shape is a
   branch on provenance inside the fever block, in `app/lib/core/triage.dart`
   and `packages/shared/src/triage.ts` together, kept as behavioural twins.

## Device temperature — closed 2026-08-13

The first open ticket below, deferred by the review above, came back for a
verdict. Four rulings, and the reason each one is not merely about precision:

1. **No device path may raise `emergency`.** Not because a wrist sensor is
   imprecise, but because *the error source the conversion must correct for is
   not one of its inputs*: `skinToCoreTempC` takes one argument, while the room,
   the bedding and the strap are the dominant terms. Worked against our own
   constants, the emergency line sits at skin 37.86 °C and the warning at 35.86;
   `verify_calibration.dart`'s own «a wrist warmed by bedding is not a fever»
   case clears the warning by **0.36 °C of skin**, against a documented ambient
   swing of "several degrees". The uncertainty is the size of the decision —
   the same finding as blood pressure.
2. **The two-minute confirmation gate does not rescue it.**
   `EmergencyConfirmation` was built against *transient* artifacts — movement,
   stress, position. Temperature's dominant error is *systematic*: a warm room,
   a duvet, a banya persist for hours and confirm themselves at two minutes with
   near-certainty. The gate was designed against noise; this is bias.
3. **Warning only, under a NEW code** — never `LOW_FEVER`/`HIGH_FEVER`, because
   `emergencyFamily` sweeps anything matching `endsWith('FEVER')` into the
   escalation path. The instruction «измерьте термометром» is the one qualifier
   that passes finding #1 above: the reader IS the woman, the instrument IS a
   household item, and the product can act on the result — a thermometer reading
   typed in carries full emergency weight. It routes her to the one measurement
   path this product is entitled to escalate on.
4. **Manual entry is unchanged, at full emergency weight.** Stated explicitly so
   no one "simplifies" the three sources into one rule and disarms the only one
   that deserves to fire.

The Starmax raw value is additionally **refused as a `coreTempC` value** until
the vendor states a site and an accuracy. The vendor names the quantity
(`当前体温`) but not where it is measured, so there is no defensible conversion —
applying `skinToCoreTempC` to it would be inventing a calibration, which is
worse than leaving it raw. The precedent is in the same file: `glucoseMmol` is
carried and graded but never triaged.

The resulting gap — a real fever seen only by a watch now raises nothing — is
accepted, because it is not created by this decision: a genuine fever in a cool
room reads low on the wrist today and raises nothing today. The change makes the
silence honest rather than arbitrary. It is accepted **conditional on** removing
the false reassurance that currently fills it (refused sentence #15).

## The absorber rule — 2026-08-14

The rule exists because of a specific mistake, and the mistake was mine.
Silencing `ADV_BP_STEADY` for device readings did not produce silence. A day of
normal wrist readings fell through to `ADV_ALL_STEADY` — «Всё стабильно» — so a
blood-pressure reassurance was **promoted into a whole-body one**, which also
travels to the clipboard, because the export sends titles only. The narrow
claim was replaced by a wider one.

> **A reassurance may claim no more than the reading it was computed from, and
> no more than the product is entitled to say about that reading's source. When
> a positive claim is silenced for provenance, every aggregate that can include
> that metric must be given the same filter IN THE SAME COMMIT — otherwise the
> reassurance survives as a broader one, and a broader reassurance is worse than
> the specific one that was removed.**
>
> Corollary, and it is the shape of every ruling in this file: **gate the
> positives, never the warnings.** The costs are not symmetric. A missed warning
> is a woman at home with preeclampsia. A missed reassurance is a woman not told
> she is fine — which is what the product owes her anyway.

So a partial provenance fix can be **worse than none**, and the question to ask
in the same commit is: *what else on this product can say she is fine?*

Every surface that answers "is anything wrong?" is an absorber:

| Absorber | State |
|---|---|
| `ADV_ALL_STEADY` fallback | refused — see #21 |
| Dashboard peace banner headline + sub | refused — #2 was live here |
| Ring "healthy fraction" | device BP counted as healthy — refused, #23 |
| Tile grade / colour / out-of-range label | **closed 2026-08-17** — see "Green is a claim" below |
| Clipboard summary | BP row refused; titles rule #24 |
| Visit summary | **already correct — the model for the rest** |

When a new metric is silenced, that table is the checklist.

### Titles are published sentences

> Every advisory title must be true, non-misleading and complete **with no body
> text, no number, and no surrounding screen**: it must make no assertion about
> her body that only the body qualifies, name the instrument whenever the claim
> depends on it, claim no wider scope than the metric it was computed from, and
> survive being read by a stranger she forwarded it to.

Not a preference — the clipboard export maps advisories to their titles and
never touches the body, so **every title already ships without its qualifier,
out of the app, to an unknown reader.** `ADV_TEMP_DEVICE_HIGH` passes only
because it names the sensor in the title; that was deliberate and must not be
treated as incidental.

Two checks are worth building, and neither can judge truth: a **reviewed-titles
manifest** pinning each title by hash with a review date, so changing medical
copy without re-review is a build failure; and a **deny-list regression guard**
asserting the refused phrasings above are absent from every string in every
locale. Crude, but refused sentences have now re-entered or persisted unnoticed
**twice**.

## Device blood pressure — closed 2026-08-14

The reassurance half shipped at 21a0a01: `ADV_BP_STEADY` no longer fires from a
wrist estimate. This is the warning half, and it is not symmetric with it —
the warning still fires from every source, under a new code with new copy,
because refusing to reassure is not refusing to warn.

**The live contradiction found on the way** and fixed first, independently of
any wording: the elevated card fires on `sysElevated || diaElevated`, so a
reading of **150/86** produced a calm "rest and re-measure" advisory while
`assessTelemetry` raised `PREECLAMPSIA_BP` at emergency severity on the same
sample. Two screens in one app disagreeing about whether she is in danger.

**The number rule is asymmetric on purpose, and must not be "harmonised".**
140/90 MAY be printed on the cuff card — it is attributed to ACOG in this
repository and is the threshold the product actually acts on, so it gives her a
checkable rule instead of an adjective. It may NOT appear on the device card:
not a citation gap this time but a validity one, since a cuff threshold beside a
wrist estimate invites precisely the comparison the estimate cannot support.
135/85 may never appear anywhere — they fire the card and appear in no cited
source. **The temperature "no numbers" rule was a consequence of ITS citation
gap and does not generalise; do not carry it across by analogy.**

«Измерьте тонометром» was approved only as one branch of three. The instrument
ground that carried the thermometer instruction does not hold — a cuff is not as
common in a Kazakh household — so the copy also names the route that needs no
equipment (blood pressure is measured at every antenatal visit, per the
protocol) and, unconditionally for both, the reviewed preeclampsia red flags and
103. That last branch is the only part that helps the woman whose wrist reads
137 while her true pressure is 160.

## Hand entry removed — 2026-08-17, and what it costs

A product decision by the owner, taken with the consequences put to him first and
confirmed. Recorded here because it **supersedes a clinical ruling**, and a
ruling overtaken by a product decision must be marked as such rather than left
standing to be read later as still in force.

> **Ruling #4 of "Device temperature — closed 2026-08-13" is SUPERSEDED.** It
> read: *"manual entry is unchanged, at full emergency weight… stated explicitly
> so no one 'simplifies' the three sources into one rule and disarms the only one
> that deserves to fire."* The disarming has now happened — not by an
> implementer simplifying, which is what that sentence guarded against, but by
> the entry path being removed. The clinical argument behind it is unchanged and
> still correct; what changed is that there is no longer a manual source.

**What the product has lost, precisely:**

1. **There is no fever emergency, from any source.** `HIGH_FEVER` and
   `LOW_FEVER` sit behind `source == manual` and are now unreachable. A woman
   with a thermometer reading of 40.0 °C receives, at most, a warning-tone card
   saying «позвоните врачу сегодня».
2. **Blood pressure keeps escalation and loses CORRECTION.** This corrects an
   error in my own framing of the question: the BP branch has no provenance
   check, so a wrist 140/90 still raises `PREECLAMPSIA_BP` and always did. What
   is gone is the cuff reading that could refute it — in both directions. A
   wrist 137 hiding a true 155 escalates nothing and cannot be checked; a wrist
   145 over a true 125 escalates and **cannot be refuted**. False preeclampsia
   alarms are not a lesser cost: they are how a woman learns to dismiss the one
   that is real.
3. **Six advisories become unreachable** — `ADV_BP_ELEVATED`, `ADV_BP_STEADY`,
   `ADV_TEMP_ELEVATED`, `ADV_TEMP_STEADY`, `ADV_GLUCOSE_HIGH`,
   `ADV_GLUCOSE_LOW`. `calibrateBp` stores only an offset and creates no
   `HealthSample`, so calibration does not keep them alive. Per the precedent of
   `ADV_ALL_STEADY`, an unreachable medical key is DELETED, not left warm: a
   dead key is a live key to the next person who finds a call site.
4. **The BP and temperature tiles are permanently ungraded**, so the peace ring
   is now a two-metric ring — heart rate and SpO2. That is the safe direction,
   and nobody may later "fix" it by letting a device BP count as healthy (#23).
5. **The doctor-facing visit summary contains only wrist estimates**, since its
   BP and temperature rows filter on provenance.
6. **The confirmation-repeat card lost its destination.** `repeat_body` promised
   «приложение подскажет, что делать» over a button wired to the deleted sheet —
   refused sentence #12 with a dead control under it, on the card shown ABOVE
   everything else at the one moment a threshold has been crossed. Rewritten to
   send her to a second BAND reading, which is what that gate exists to wait for,
   and `repeat_cta` deleted rather than made a no-op: where there is no action
   she can take, a button is worse than no button.

**What would buy the fever emergency back**, recorded so the option is not lost:
a single-number thermometer entry — not the diary. The objection was to users
entering readings the watch produces; a thermometer number is not one, and a
cuff number is the correction the watch requires. A product decision, not a
clinical one.

**BLOCKING, and it held:** `bp_calibration_sheet.dart` must survive any removal
of "hand entry". It is opened from Settings, stores an offset rather than a
reading, and creates no `HealthSample`. Without it `bpCalibrationIsStale` is
permanently true past 8 days, which by the freshness table means a blood
pressure is «not shown as current, always» — silently removing the tile and
leaving an uncorrectable wrist estimate as the sole input to the one device path
still able to open the emergency screen.

## Long cards: a declared PREFIX, never a summary — 2026-08-17

The advisory body is too long for a home card. The fix is **not** a short second
string per key:

> The home card renders a declared PREFIX of the approved body. «Подробнее»
> opens the whole body, INCLUDING the sentences the card already showed. The
> split point is metadata — a sentence count — not text.

A per-card summary would be a third independently-authored claim per key per
language, kept in sync forever and re-reviewed on every edit to either. That is
the mechanism that already cost this product a reviewed clinical claim, once.
The prefix carries no such risk: every word that ships is still covered by the
fingerprints in `reviewed_medical_copy_test.dart`.

**Prefix integrity, all four to be pinned:**

1. **A conditional and its consequent may never be split.** «Measure with a
   cuff» on the card and «if it shows 140/90 or higher, contact your doctor
   immediately» behind a tap is worse than no split at all — it sends her to
   take a measurement and withholds the rule for reading it.
2. **A 103 branch may never be last in the prefix.**
3. **No forward reference** — no sentence on the card may depend on one below.
4. **Every sentence in the prefix must be true with nothing after it** — the
   titles rule, one level down.

And the standing rule that follows from it:

> **A 103 branch may never be the last element of a card body, and may never be
> the first thing a summary drops.** Bodies are cut from the end — by
> summarisation, by `maxLines`, and by the next person who finds the card too
> long.

**No split, ever, for a card whose tone is `positive` or `info`.** Their closing
sentence is the counterweight that stops them reading as an all-clear; putting
it behind a tap turns each into the reassurance it was written to prevent.
Abbreviating a reassurance widens it — the absorber rule, restated for this
feature.

The clipboard export may carry the title plus the same prefix. A third,
separately-authored summary is REFUSED. Rule #24 is unchanged regardless: every
title must still be true and complete with no body at all.

## Medical Kazakh is reviewed, not translated — the standing rule

> No string in a `medical` content card, an `ADV_*` advisory, a triage message,
> an `em_*` emergency key or a vitals qualifier may ship in Kazakh until someone
> has read the Kazakh and the Russian against each other, sentence by sentence,
> and recorded that they make the same clinical claim. That read-back belongs to
> the gate that approved the Russian — not the implementer, not the translator.
> **Approving one language is not approving the copy: the verdict does not exist
> until it names every language it covers.**
>
> 1. **A verdict names its languages** — "APPROVED (ru, kk, en)". An approval
>    that names none approved one.
> 2. **Editing any language re-opens the key in all of them**, the same
>    discipline `carryReview` applies to content cards.
> 3. **The reviewer names the load-bearing words, per key, per language** — the
>    ones whose removal changes the claim. For the two device cards they are:
>    ru «а не измерение», «на запястье», present «показывает»; kk «өлшем емес»
>    (and **never** «нақты өлшем емес»), «білезік», «көрсетіп тұр».

Two things to build and one **not** to build:

- **Do not grow the kk≠ru guard toward semantics.** It catches copy-paste, and
  should keep doing exactly that. `vac_hib` is the proof it cannot go further —
  a Russian parenthetical inside a Kazakh string was invisible to it because the
  rest of the string differed. No string comparison will ever detect "conceded
  that it is a measurement".
- **Build the per-key load-bearing-token assertion:** for each reviewed medical
  key, the substrings each language must contain and must not contain. Cheap,
  and it would have caught both of today's body defects on the day they landed —
  `нақты өлшем` present, `білезік` absent — with nobody reading Kazakh.
- **Build the reviewed-titles manifest, hashed across all three languages.**
  Asked for on 2026-08-14, still not built. Hashing Russian alone would have let
  today's Kazakh title through.

## The Kazakh said something weaker than the Russian — CLOSED, 2026-08-17

The read-back this document asked for was finally done, and it found that **a
reviewed clinical claim was reviewed in one language and shipped in two.**

Both device cards — `ADV_TEMP_DEVICE_HIGH_b` and `ADV_BP_DEVICE_HIGH_b`:

| | text | what it says |
|---|---|---|
| RU | «Это оценка датчика на запястье, **а не измерение**» | it is **not a measurement** |
| KK | «...**нақты өлшем емес**» | not an **accurate** measurement |

The Russian denies that the number is a measurement at all. The Kazakh concedes
that it is one and disputes only its precision.

That denial is not decoration — it is the card. Ruling #1 of "Device temperature
— closed 2026-08-13" rests on the sensor value not being the quantity, and the
blood-pressure verdict rests on the firing window sitting entirely inside the
estimate's own error. A card that concedes «this is a measurement, just not a
precise one» invites exactly the comparison both rulings refused.

The reading is not a guess: the catalogue fixes it two keys away, where
`temp_device_estimate_note` ends «**Нақты** дене қызуын тек термометр көрсетеді»
— "only a thermometer shows the **accurate** temperature".

**Second divergence, same sentence.** RU «датчика **на запястье**» → KK
«**қолыңыздағы**» = "on your hand/arm". Kazakh has `білезік` / `білек` for
wrist. Naming the instrument is deliberate under the titles rule; the body
drops from *wrist* to *arm*.

**Third, reported as a nit rather than a defect:** both device titles move from
the Russian present «показывает» to the Kazakh past «көрсетті» — "the sensor
showed". Titles ship alone through the clipboard export.

**Corrected 2026-08-17, by the gate that approved the Russian.** The diff is one
word deleted and one corrected, in one clause of each body, plus the tense of
both titles. Everything after that clause is unchanged by a character:

| | before (kk) | after (kk) |
|---|---|---|
| both bodies | «Бұл — **қолыңыздағы** датчиктің болжамы, **нақты** өлшем емес» | «Бұл — **білезіктегі** датчиктің болжамы, өлшем емес» |
| both titles | «Датчик … **көрсетті**» (showed) | «Датчик … **көрсетіп тұр**» (is showing) |

`өлшем` was already the translator's chosen equivalent of «измерение» — deleting
the hedge makes the sentence deny the CATEGORY rather than the precision. If
anyone proposes re-adding a qualifier here — `нақты`, `дәл`, `толық` — **that is
the defect returning and must be refused.** `білезік` over `білек`: the latter
is the forearm, which would repeat the error, and `білезік` is the word the rest
of the Kazakh app already uses for the band.

The title tense was ruled a defect rather than a nit: a title ships alone and
undated through the clipboard export, so tense is the only temporal information
it carries. «көрсетті» reads as a closed episode — a warning that reads as
concluded is a warning weakened, and weakened only for Kazakh readers. Bare
`көрсетеді` is refused as the fix: the aorist reads habitual, a claim about what
sensors do in general.

`temp_device_estimate_note` deliberately KEEPS «Нақты дене қызуын тек термометр
көрсетеді» — stated here so nobody "harmonises" it after seeing `нақты` deleted
two keys away. That sentence is a claim about the THERMOMETER, and the denial in
that note is carried by the sentence before it. It is the opposite construction
to the defect.

Confirmed by a repo-wide sweep that these four strings are the complete change:
the text exists in exactly one file, and nothing in `packages/` mirrors it. That
was the one way this could have been a partial fix.

**What read back CLEAN**, sentence by sentence, so the scope of the problem is
bounded rather than feared: `ADV_NOTHING_UNUSUAL` including its third
load-bearing sentence; `ADV_BP_ELEVATED` with 140/90 twice, 103, the three red
flags, «қайта өлшеуді күтпей», and no 135 or 85 anywhere; `ADV_BP_DEVICE_HIGH_b`
carrying its no-equipment branch and correctly carrying no number;
`temp_device_estimate_note`; all 7 triage messages; all 17 `em_*` emergency
keys; and the confirmation-gate copy.

**And the guard that let this through is now closed** — but only for the case it
can see. `verify_l10n` checked that three locales were DEFINED and never
compared them, so Kazakh that was a copy-paste of the Russian passed for the
life of the project (measured: 82/0 with a known-bad key in the catalogue).
kk≠ru is now enforced with 50 named exceptions, each carrying its reason.

That catches a copy-paste. It cannot catch this: `vac_hib` shipped
«(ревакцинация)» inside an otherwise-Kazakh string and the check never saw it,
because the rest of the string differed. **Semantic divergence in medical copy
is invisible to any automated check, and the only thing that finds it is a
person reading both languages against each other.**

## Green is a claim — CLOSED, 2026-08-17

Three rulings, landed together because the absorber rule makes them one commit.

**1. The colour outlived the grade.** The device-temperature verdict removed a
wrist estimate's grade by answering `MetricStatus.normal`, on the reasoning —
written into `metricStatus` itself — that normal renders as "plain ink, no
raised step, no suffix". Two of those three held.
`_statusColor(MetricStatus.normal)` returned the palette's teal, so an UNGRADED
reading went on being painted in the same green as a healthy heart rate.

An ungraded metric now renders its value in `Palette.text` — ordinary body ink,
and **not** `Palette.textDim`, which is the STALE appearance and would say "old"
about a reading two minutes fresh. No raised step, no out-of-range suffix in the
semantics label, no band shading, sparkline unchanged, age line unchanged. Ink is
correct from both sides: it is the colour the app uses when it is not judging, so
it reads as neither an alarm nor an all-clear.

Green survives only where the grade is real — a current reading, on a cited band,
from a source the product may reassure from. That is heart rate, SpO2, a MANUAL
temperature and a cuff blood pressure. `MetricStatus` therefore has a fourth
state; collapsing "ungraded" onto "normal" is what caused this, and a future
patch that re-collapses them is this defect returning.

**2. The device-BP tile was refused sentence #23, shipping.** `_BloodPressureCard`
graded by calling `metricStatus('systolic', …)` with no `source`, and
`metricStatus` had no provenance branch for either half — so a fresh, calibrated
wrist 118/76 was drawn in mint. The ring beside it already had the rule and is
the model: **a device BP may pull the grade DOWN and never up.** Danger and watch
fire from every source and come FIRST in the branch; only the positive tier reads
provenance. The card's unconditional `raised: true` went with it, for the same
reason the four tiles beside it are raised only when they warn.

Two traps the gate named in advance, both now pinned by tests:

- `worstStatus` picked the max ENUM INDEX and cannot express "an ungraded half
  makes the pair ungraded" — a blood pressure with one ungraded half must not
  come out `normal`. The ranking is written down explicitly and no longer depends
  on how the enum is declared: `normal < ungraded < watch < danger`.
- the source-passing scan test only enforced its rule where the metric *could be*
  temperature, so it never saw the BP card. It now covers every metric whose
  grade reads provenance, and a second test checks that list against
  `metricStatus`'s actual behaviour so the mirror cannot rot.

**3. `ADV_GATHERING_b` was a band upsell** — «Наденьте браслет — советы появятся
после нескольких измерений.» — shown to a woman who types her readings in by
hand, plus a promise that advice arrives once she owns the hardware. The
dashboard's empty state had this exact sentence family removed for exactly this
reason («Апселла браслета здесь нет», «Без устройства приложение полноценно»);
the advisory was the surviving instance. Replaced, with the title, by approved
copy that names no instrument.

And a NEW code, `ADV_NO_CURRENT_READINGS`, for the case where readings exist and
none is current — where «Собираем данные» is simply untrue: nothing is being
gathered, the data exists and is out of date. **Its closing sentence is
deliberately identical to `ADV_NOTHING_UNUSUAL_b`'s in all three languages.** It
is the counterweight that stops an absence-of-data card from reading as an
all-clear, and it is not to be paraphrased.

Two things landed in the SAME commit, and they are the absorber discipline
rather than tidiness: the `fallThroughs` set in `current_advisories.dart` gained
the new code, or «Свежих измерений нет» prints underneath a warning; and the
clipboard filter in `health_summary.dart`, which excluded only `ADV_GATHERING`,
now reads the same constant — `noDataAdvisories`, declared once.

**Also:** `AdviceTone.info` rendered in `Palette.violet` = `Ds.coralCta` =
#D6004A, a near-crimson louder than the app's actual warning amber, under an
hourglass meaning "coming". The calmest state the banner has was drawn in the
loudest colour it owns. It is dim ink now, on both the banner and the advisor
screen, and `ADV_NO_CURRENT_READINGS` does not get the hourglass — nothing is on
its way to a woman whose band is in a drawer. No check mark and no warning
triangle either: it is neither.

## The verdict has one regression path, and it is open

**`GET /vitals/manual` does not say that its readings are manual.** Confirmed by
reading, 2026-08-14:

- `listManualVitals` selects `WHERE user_id = $1 AND device_id IS NULL` — so
  every row it returns is hand-typed **by construction**. The server already
  knows. It just never says so: the returned object carries `recordedAt`,
  `heartRateBpm`, `spo2Pct`, `systolicMmHg`, `diastolicMmHg`, `coreTempC`,
  `glucoseMmol` and no provenance.
- `HealthSample.fromJson` reads an absent `source` as **sensor**, deliberately
  and correctly — an unlabelled stored row is not a thermometer, and defaulting
  the other way would hand a wrist estimate the emergency entitlement.

Put together: a woman changes handset, her readings restore, and **every
thermometer reading she ever typed comes back labelled as a wrist estimate.**
The consequence is precisely the thing this whole review protected:

1. A real 38.6 she measured no longer escalates — the one source entitled to
   raise an emergency silently loses that entitlement on a new phone.
2. Her typed readings drop out of the visit summary, which now filters on
   provenance before showing a doctor anything.
3. The manual-diary card vanishes for exactly the woman who has been using it,
   because that card is now keyed on whether a BAND is supplying readings.

Not a design question — the fix is to emit what the WHERE clause already
guarantees, in both repository implementations plus the interface. Written down
here rather than in a task result because it defeats a clinical ruling silently,
and the failure is invisible on the phone where the readings were typed: it only
appears on the next one.

## Open tickets this raised

- The **server-side** emergency path re-runs `assessTelemetry` and pushes on the
  FIRST crossing, with no equivalent of `EmergencyConfirmation` and no source
  check — for every metric, not only temperature. It already reads `t.source`
  for attribution. The on-device confirmation gate is therefore not the last
  word on any vital.
- The Starmax temperature has **no plausibility range at all**: `tempRaw` is a
  u16, `tempCelsius => tempRaw / 10.0`, fed straight to `assessTelemetry`. A
  corrupt frame reading 4000 becomes 400 °C and takes over the screen. The band
  path has this gate; the watch path does not. Independent of the verdict above.
- **37.8 / 38.5 are uncited.** No source this product already cites supports
  either number for pregnancy: the antenatal protocol contains no fever item at
  all, and `emergency_help.json`'s only two fever entries are newborn and
  postpartum, both at 38 °C. The neighbouring thresholds in the same file *are*
  attributed (140/90 to ACOG, 95 % to the spec); temperature is the one uncited
  entry in the block. The numbers stay for the manual path — disarming the only
  real-thermometer escalation over a documentation gap would be worse — but no
  user-facing string may state either number until the owner records a source,
  which is why the approved copy is non-numeric.
- `server.ts` bounds `systolicAvg` and `bloodSugarTenths` at 255 while the
  ingest handler and CHECK constraints allow 260 and 300; values in the gap fail
  the whole wearable item at the wire. Harmless until a max column arrives.
- Hard-coded l10n medical strings have no equivalent of `carryReview`, which
  revokes a content card's review when its text changes. The same discipline
  should apply.
