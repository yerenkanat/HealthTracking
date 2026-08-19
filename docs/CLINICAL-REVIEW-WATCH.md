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
| Ring "healthy fraction" | device BP counted as healthy — refused, #23. **Coverage closed 2026-08-18** — see "A shape cannot be qualified" below |
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
   **What it also did, and was not noticed for a month:** a two-metric ring that
   still drew itself as a whole one. See below.
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

**Implemented 2026-08-17** in `app/lib/domain/advisory_layout.dart`, and the
shape is better than the ruling asked for. A plain prefix would have put the
sentence that must never be hidden — the red flags and 103, which sit at the END
— behind the tap. So the split takes sentences from BOTH ends:

    lead  sentences from the front  → the card, as body text
    flags sentences from the back   → the card, as the amber red-flag block
    the middle                      → behind «Подробнее»

`flags: 0` degrades to a plain prefix for a card with no red-flag tail. This
also satisfies `docs/CLAUDE-app-design.md` ЧАСТЬ 4 rule 6 — «Красные флаги
отдельным блоком, не под "читать дальше". 103 внизу» — which was found after the
ruling was written and independently requires the same thing. Amber, not red,
per rule 5: «Красный только SOS».

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

## A shape cannot be qualified — the ring's coverage, CLOSED 2026-08-18

A **design** ruling, made by the designer, on TODO §2.2. The clinical content of
the ring is unchanged: nothing here lets a wrist estimate become healthy, and
nothing here removes a warning.

**The reported defect** was `withData == 0 ? 1.0 : healthy / withData` — a
complete green circle on a day when NOTHING could be graded. It was fixed in
`6b24dce`: the fraction is nullable, null draws no arc, and `db_ring_ungraded`
explains it in the paint and in the semantics tree.

**The defect that was still live** is the same one a step milder, and it shipped
every day rather than occasionally. `healthy / withData` divides by a pool the
loop had already thinned: a card the gates refused was `continue`d, which took
it out of the numerator AND the denominator, and the arc closed anyway. Point 4
above states the arithmetic without naming its consequence — a band-only day has
**two gradeable cards of four**, so the everyday state of this product was the
complete circle of a day on which everything was checked and everything was
fine. `goldens/home_dashboard.png` was a photograph of it, and passed for a
month, because a golden blesses whatever it is shown.

**Ruled:**

1. **The pool is stated, never thinned.** `domain/peace_ring.dart` grades all
   four cards of the grid — every one gets `healthy`, `concerning`, `ungraded`
   or `missing`, and nothing leaves silently. Four CARDS, not the five entries
   of `metricKeys`: the grid draws blood pressure as one card, and a denominator
   the reader cannot check by counting her own screen is a number she has no way
   to catch. It also stopped one instrument owning two thirds of a cuff day.
2. **The arc spans the assessed share of the circle, and the rest is drawn as
   not-assessed** — a dashed arc in `Palette.text`. Dashed rather than a second
   colour, because a solid second accent would be a verdict and this is the
   absence of one; ink rather than `Palette.textDim` on the tile's own
   precedent, since dim ink means STALE and «old» is a different claim from «not
   judged». The vocabulary is `MetricStatus.ungraded`'s, deliberately: one idea,
   one appearance, on the same screen.
3. **A closed circle now means what it looks like** — all four cards assessed
   and all four healthy. A cuff reading and a thermometer reading still close
   it, so nothing is achieved here by making the ring unfillable.
4. **The partial day says so, in words**: `db_ring_partial`, «Учтены не все
   показатели: 2 из 4.» It names a count the reader can verify against the cards
   below and says nothing whatever about her body — no «недостаточно данных»,
   which reads as a fault of hers, and no «всё в порядке по 2 из 4», which is
   the reassurance this review exists to remove. The nothing-assessed day keeps
   `db_ring_ungraded` and does NOT also get this one: «not everything was
   counted» is false when nothing was.
5. **A day with no readings at all draws no ring**, and that was already true —
   `_PeaceOfMindBanner` renders only when `samples.isNotEmpty`. It is the right
   answer and it is recorded here so nobody "completes" the states by adding an
   empty banner: with no readings the screen owes her the stage hero and the
   quick actions, not a grey circle.

A side effect worth keeping: before this, **«I could assess nothing» and «I
assessed everything and it is bad» drew the identical bare ring** and differed
only by the colour of the badge in the middle. They no longer do.

The Kazakh of `db_ring_partial` is a designer's draft and is **flagged for the
language gate** — the construction «4 ішінен 2» was chosen to avoid the numeral
possessive («2-уі» but «1-еуі»), which no placeholder can get right for both.
The Russian and the English are settled.

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

## The labour hole — the guard was scoped to the wrong thing, 2026-08-18

Everything above this line is about the watch. So was `isMedicalKey`, the
predicate in `app/test/reviewed_medical_copy_test.dart` that decides which
strings the fingerprint manifest has to cover. It matched four prefixes and one
key — `ADV_`, `em_`, `repeat_`, the triage codes, `temp_device_estimate_note` —
and **every one of them came out of the vitals pipeline this document reviewed.**

The guard therefore matched by ORIGIN, not by what a sentence does to a reader.
Everything clinical the app says that did not come out of a wearable was outside
it, and this document said nothing about any of it. It does not mention labour
at all, which is why the hole survived five reviews.

**72 strings were pinned. 436 more were not, and were live.**

### The string that showed it

`lab_go_five_one_one`, on LabourSignsScreen:

> «Схватки примерно каждые 5 минут по ~1 минуте в течение часа (правило 5-1-1).»
> «Толғақ шамамен әр 5 минут сайын, ~1 минуттан, бір сағат бойы (5-1-1 ережесі).»

It sits in a list headed «Свяжитесь с роддомом или поезжайте, если появится
что-то из этого:». It tells a woman in labour when to leave her house. It is
reachable from the contraction timer info icon
(`contraction_timer_screen.dart:205`) and from «Экстренная помощь» via
`guides_screen.dart:353`. It shipped in ru and kk with **no fingerprint and no
verdict**, and it was found by accident while building a guard for the same rule
on a different screen.

### What the widened predicate covers, and the rule it applies

The test is now: **does the sentence make a clinical claim, give a clinical
instruction, name a threshold, or tell the reader to seek or delay care?** Not:
what is its prefix.

Two mechanisms, deliberately:

- a **prefix** where the whole screen is clinical — a red-flag list, a validated
  instrument, a protocol transcribed from a contract;
- an **explicit key** where one clinical sentence sits among UI chrome.

The second exists so this guard does not cry wolf. `bag_` is 26 keys and two of
them are clinical, so `bag_intro` is named and «Ночная рубашка» is not. That is
the calibration a token rule banning «роддом» failed earlier the same day when
it fired on «Сумка в роддом». A guard that fails on a packing list stops being
believed, and then somebody loosens it.

Prefixes: `ADV_ CS_ an_ contr_511_ eh_ em_ epds_ hs_ ill_ lab_ pp_note_
pp_warn_ preg_note_ preg_warn_ pwg_ repeat_ sol_ ss_ teeth_not_ vac_`.

**Deliberately excluded, and why**, because the boundary is the load-bearing
part: `fet_` (22 fetal-development sentences — «Лёгкие почти готовы к первому
вдоху» describes, it does not triage), `bsize_` (fruit), `sym_` and `mood_`
(diary labels), `nightfeed_` and `nb_` (a timer and a tally), the `bag_` item
names, `cyc_` statistics, `vitals_err_` (input validation, not a claim about her
body). Excluding these is a ruling, not an oversight; re-including any of them
needs an argument.

### PINNED IS NOT APPROVED

Every one of the 436 is frozen at the wording **already live on 2026-08-18**.
A fingerprint means "this text has not changed since we noticed it". It does not
mean a reviewer has read it. Do not cite manifest membership as clearance.

Nothing was rewritten and nothing was deleted. Removing clinical content is as
much a clinical decision as adding it.

### Ranked by danger — what needs a verdict first

**1. `kick_low_action` — the app contradicts itself on reduced fetal movement,
and the weakest wording sits on the screen where she is already worried.**

Four strings cover the same red flag and they do not agree:

| key | what it says | strength |
|---|---|---|
| `preg_note_movement_pattern` | «сразу сообщите в консультацию, **в любое время суток**» | immediate |
| `preg_warn_movement` | in the list headed «Свяжитесь с консультацией **или скорой**» | immediate |
| `lab_go_reduced_movements` | in the «Когда ехать или звонить» list | immediate |
| **`kick_low_action`** | «свяжитесь с консультацией **сегодня**, не ждите до завтра» | **today** |

`kick_low_action` is the one that fires off an actual count — the woman who
tapped ten times and got six. At 23:00 «сегодня» reads as «утром». The other
three say «в любое время суток». Reduced fetal movement is the antenatal red
flag with the shortest useful window, and the softest sentence the app has about
it is the one attached to its own trigger.

Who reads it and when: a woman past 28 weeks who opened the kick counter because
something already felt wrong, and then sat through two hours of it.
Wrong too eager: a night call to a consultation that tells her to come in the
morning anyway. Wrong too slow: a stillbirth a night call would have caught.

**This is the item to take to the owner first.** It is a one-sentence
divergence, not a rewrite, and I have not made it.

**2. `lab_go_five_one_one` — the benchmark.** Too eager sends her to be turned
away in early labour; too slow is a birth in a car. Compounding it:
`contr_511_ready` hedges the same rule («Многие врачи советуют связаться с ними
на этом этапе — следуйте своему плану родов») while `lab_go_five_one_one` states
it flat inside a «go in» list. Same rule, two strengths, two screens, one woman.

**3. `epds_` — 68 strings, and the questions ARE the instrument.** A softened
answer option changes the score, and the score drives `epds_band_high` («13
баллов и выше»). `epds_harm_flag` and `pp_warn_harm` are the only two self-harm
paths in the product. To the credit of whoever wrote it, `epds_not_validated`
already says the ru and kk thresholds were derived on other language versions —
that is the honest disclosure and it must not be edited away.

**4. `ill_young_body` — «В этом возрасте любая температура 38 °C и выше».**
Read by a parent of a newborn, at night, on a phone. Agrees with the newborn
fever entry in `packages/contract/emergency_help.json`, which is also 38 °C.
Wrong too eager: an unnecessary night trip. Wrong too slow: neonatal sepsis.
The number is right; what was missing was any guard against it drifting.

**5. `pp_warn_` — postpartum haemorrhage, sepsis, DVT, wound infection,
self-harm.** Read in the first six weeks by someone who has just given birth and
who will discount her own symptoms because everything hurts.
`pp_warn_bleeding` («прокладка полностью промокает за час, или крупные сгустки»)
is a quantified threshold and matches `emergency_help.json`.

**6. `preg_warn_`** — the preeclampsia triad, bleeding, fluid loss, reduced
movement, fever. This is the list the reviewed ADVISORY cards point AT. The
cards had a verdict; the list they send her to did not.

**7. `an_` — the RK MOH protocol, transcribed into the app.** Checked item by
item against `packages/contract/antenatal_protocol.json` today: **the Russian
matches verbatim, all 40 items and all 6 windows.** Pinning freezes that
agreement. The exposure was silent drift — «Фолиевая кислота 400 мкг в день»,
«Аспирин с 12 до 36 нед. при риске преэклампсии», «Анти-D иммуноглобулин в
28–30 нед.», «Тест на толерантность к глюкозе (24–28 нед.)» are drug and window
instructions, and nothing sat between the app string and the contract.

**8. `vac_` — the national schedule and the catch-up wording.** Names and doses
match `packages/contract/vaccination_schedule.json`. `vac_disclaimer` is
load-bearing and correct: the app does not know which vaccines have been given,
and it says so. `vac_catchup` («Стоит уточнить или наверстать») is the softest
possible framing of an overdue immunisation; it is now frozen, and it deserves a
verdict of its own.

**9. `sol_`, `ss_`, `hs_`, `teeth_not_`, `ill_care_`** — infant death and injury
copy: back-sleeping, never on a sofa, honey before one year, whole grapes, tap
water not above ~50 °C, «не давайте аспирин детям», «Высокая температура —
прорезывание её не вызывает». Each is standard guidance and none of it cites a
source on screen.

**10. `eh_` — the emergency screen furniture.** `eh_sev_red` («Звоните 103
сейчас») and `eh_sev_amber` («Позвоните врачу сегодня») are triage verdicts
rendered as section headings. `eh_call_body` is the sentence this app must never
overstate: «Скорая помощь — бесплатно, круглосуточно, с любого телефона»
describes the ambulance service and does **not** claim that we summon it. The
emergency path is intact, and that wording is now pinned, which is the point.

**11. `pwg_` — numeric weight-gain ranges by BMI band.** The figures come from
`app/lib/domain/pregnancy_weight_guide.dart`, which attributes them to the
Institute of Medicine. **The screen cites nothing.** CHANGES, not a refusal: the
numbers are traceable, the citation is missing from the copy a reader sees.

**12. `kick_goal_reached` — «Цель достигнута».** Two words, and they are a
reassurance verdict on fetal movement. Formal kick-counting fell out of guidance
partly because hitting the target reassures. `kick_goal_reached_slow` qualifies
the over-two-hours case; the plain one qualifies nothing. Pinned.

### Kazakh checked against Russian on the highest-danger items

`lab_go_five_one_one`, `ill_young_body`, `pp_warn_bleeding`, `pp_warn_harm`,
`epds_band_high`, `epds_harm_flag`, `preg_warn_movement`, `kick_low_action`,
`sol_avoid_honey`, `an_term_note`, `pwg_weekly_body`, `eh_sev_red`,
`eh_sev_amber`, `vac_disclaimer`: **the Kazakh says the same thing.** Numbers,
thresholds and urgency verbs all survive the crossing.

One divergence for `anabala-kazakh`, and it is a modal one:

- `lab_intro` — ru «когда **пора** ехать» (it is time to go) against kk «қашан
  баруға **болатыны**» (when it is permissible to go). Permission rather than
  prompting, on the sentence that introduces the whole «when to go in» screen.
  Not a changed threshold; still a softened instruction, and it is one of the
  two keys `app/test/contraction_timer_test.dart` already lists as
  `knownUnreviewed`.

### Verified by reverting

Both directions, 2026-08-18:

1. Narrow predicate restored, five probe keys (`lab_go_five_one_one`,
   `epds_band_high`, `pp_warn_bleeding`, `ill_young_body`, `eh_sev_red`) deleted
   from the manifest. Result: **`All tests passed!`** That is the hole
   reproduced exactly — five unreviewed clinical strings, unpinned, green.
2. Widened predicate, the same five still unpinned. Result: **fails**, naming
   them: `Medical keys with no reviewed fingerprint: [eh_sev_red,
   epds_band_high, ill_young_body, lab_go_five_one_one, pp_warn_bleeding]`.
3. Manifest restored, then the Kazakh of `lab_go_five_one_one` softened from
   «әр 5 минут сайын» to «әр 10 минут сайын», Russian untouched. Result:
   **fails** — `lab_go_five_one_one: cd3966cb6a5688e7 -> 41e58a6cf8b4fe5b`.

All three reverted. `flutter test` in `app/`: **2215 passing.**

Worth recording, because it is the reason a plain revert was not enough: undoing
the widening on its own leaves the suite GREEN. The completeness test only fires
when a key the predicate matches is missing from the manifest, so extra pins are
invisible to it. The hole had to be probed by removing pins, not by removing the
fix.

### What this leaves open

- The 436 are pinned and **unreviewed**, less the four the movement ruling
  below closed on 2026-08-19. Pinning bought time; it did not buy safety, and
  nobody should read the manifest as though it did.
- ~~`kick_low_action` against `preg_note_movement_pattern`~~ — **CLOSED
  2026-08-19**, see «Reduced fetal movement» below. The protocol, not the other
  three screens, decided it. What that ruling opened instead: the same protocol
  paragraph says movement COUNTING has no evidence base, and this product ships
  a counter that says «Цель достигнута».
- `contr_511_ready` and `lab_go_five_one_one` state the same rule at two
  different strengths on two screens.
- `pwg_` states Institute of Medicine numbers with no on-screen citation.
- `an_source` («По клиническому протоколу МЗ РК «Антенатальный уход» (2025)») is
  the only clinical screen in the app that names its source. It is the model the
  other eleven do not follow.

## Reduced fetal movement — CLOSED, 2026-08-19

The item ranked #1 above («the app contradicts itself, and the weakest wording
sits on the screen where she is already worried») came back with a decision from
the owner: align `kick_low_action` to the strictest wording already live. The
gate ruled on it as one item, all four keys together.

| key | verdict | against what |
|---|---|---|
| `preg_note_movement_pattern` | **APPROVED**, unchanged | RK MOH «Антенатальный уход» (2025), § «Дальнейшее ведение» |
| `preg_warn_movement` | **APPROVED**, unchanged | same, plus `emergency_help.json` `fetal_movements` |
| `lab_go_reduced_movements` | **APPROVED**, unchanged | same |
| `kick_low_action` | **CHANGES**, made | the protocol; it was weaker than all three |

**The source, and it is not "the other three screens agree".** The RK MOH
clinical protocol «Антенатальный уход» (2025) — `docs/Антенатальный уход.docx`,
the document `an_source` cites on screen and `domain/antenatal_protocol.dart`
names — says, verbatim:

> «Проводить опрос беременной пациентки по поводу характера шевелений плода при
> каждом визите после 20 недель беременности. […] Пациентке должны быть даны
> рекомендации, что при субъективном изменении активности и/или частоты
> шевелений плода, ей следует **незамедлительно** обратиться в
> родовспомогательную организацию для проведения дополнительного обследования
> (УД-С).»

*Незамедлительно*, to a maternity facility, with no hour attached. «Свяжитесь с
консультацией **сегодня**, не ждите до завтра» was weaker than the protocol this
product cites, so the protocol won. That is the whole justification; the other
three screens agreeing with it is corroboration, not the reason.

Second corroboration, in-repo and canonical: the **red** `fetal_movements`
scenario in `packages/contract/emergency_help.json` already fires on the
identical numeric trigger and gives the identical instruction — «меньше десяти
за два часа […] звоните 103 или сразу в роддом, не ждите следующего дня». The
app was therefore already making this claim on one screen while making a softer
one on the screen that computes the trigger.

**What shipped** (`kick_low_action`, ru):

> «Если за два часа вы не насчитали десяти шевелений — свяжитесь с консультацией
> или роддомом в любое время суток, не ждите до утра. Если дозвониться не
> удаётся — звоните 103.»

103 is named as a fallback and imperative to HER: refused sentence #10 is
untouched, and nothing here says the app summons anyone.

**The finding that outranks the wording, and it is not closed.** The same
protocol paragraph states: «**Нет доказательных данных по эффективности
профилактики неблагоприятных перинатальных исходов на основании подсчета числа
движений плода.**» The app's own cited protocol says formal movement counting is
not evidenced to prevent adverse outcomes, while the product ships a counter
that teaches «считай до десяти», rings a goal and prints «Цель достигнута».
Three consequences, one applied and two open:

1. Applied: the count may not be the gate. `kick_low_action` routes and never
   reassures, and the subjective trigger (`preg_note_movement_pattern`) is
   printed directly under it at equal weight — the protocol's actual trigger is
   the subjective change, not the tally.
2. Open: `kick_goal_reached` — «Цель достигнута» — is a reassurance verdict on
   fetal movement produced by a method the cited protocol says has no evidence
   base behind it. Ranked #12 above; this sharpens it from "two words to look
   at" to "two words the protocol contradicts".
3. Open: whether the counter should carry the protocol's own sentence about the
   evidence, the way `epds_not_validated` carries its instrument's. Not written,
   deliberately — new user-facing clinical copy needs the owner, not the gate.

**Not done, deliberately: no gestational-age qualifier was added.** The
`emergency_help.json` card scopes itself «после 28 недель» and the protocol asks
about movements «после 20 недель»; picking either as the gate for this sentence
would have been a new claim about when the instruction stops applying, and the
protocol attaches no window to the *action*. The counter does not know the
gestational week at this call site either.

**Kazakh.** Written, NOT language-gate reviewed — `docs/TODO.md` §9.12, and the
line in the manifest says so. Assembled from clauses already live rather than
translated fresh: «тәуліктің кез келген уақытында … хабарласыңыз» is
`preg_note_movement_pattern`'s own (already checked against its Russian in this
document), «перзентханаға», «103-ке қоңырау шалыңыз» and the do-not-wait clause
are the `emergency_help.json` `fetal_movements` kk pair's. It was written rather
than left alone because the alternative was shipping a corrected Russian beside
the old Kazakh — «бүгін … ертеңге қалдырмаңыз», i.e. the 23:00 problem in
Kazakh — and a softened translation is a different clinical claim. Look at
«таңға дейін күтпеңіз» first.

**Verified by reverting**, each change on its own, exact messages:

1. The **Russian alone** put back to «свяжитесь с консультацией сегодня, не ждите
   до завтра», Kazakh and English left corrected. Result: **fails** —
   `kick_low_action: 00677ac9fd6a374c -> 2ce8e30ebf042c0f`. Worth recording:
   `kick_session_test` PASSED on that revert, because its assertions read the
   English. A one-language softening is caught by the fingerprint and by nothing
   else, which is the reason the fingerprint spans all three.
2. New text kept, the manifest entry put back to the pinned 2026-08-18 hash.
   Result: **fails** in the other direction —
   `kick_low_action: 050b3c54e387cd8f -> 00677ac9fd6a374c`.
3. New text kept, the new assertion in `app/test/kick_session_test.dart` put
   back to the old one. Result: **fails** — `Found 0 widgets with text
   containing contact your clinic today`, i.e. the softened wording cannot
   return unnoticed.

## The four uncited numbers — 2026-08-19: two stopped grading, two refused

`docs/TODO.md` §1.1 records 37.8 °C, 38.5 °C, 135 and 85 mmHg as numbers that
grade a tile or fire a card with no cited source. The owner's decision: every
number that grades must carry a citation, or stop grading.

**Where the gate looked, so nobody repeats it.**
`packages/contract/antenatal_protocol.json` — the RK MOH schedule shared by app,
backend and panel — contains no temperature and no blood-pressure threshold at
all; it is a visit plan, and its only BP line is «Измерение давления и пульса».
The source document `docs/Антенатальный уход.docx` was extracted and searched:
**none of 37.8, 38.5, 135 or 85 appears in it**, in any form. `docs/92
бұйрық.docx` likewise. `packages/contract/emergency_help.json` carries **38 °C**
twice (a newborn under three months; the first six weeks postpartum) and no
other number in this family. `packages/contract/triage_thresholds.json` holds
all four and cites nothing — it is the file that needs a citation, not one that
can provide it.

### 135 / 85 mmHg — could not source. STOPPED GRADING.

No source names them. `health_advisor.dart` already admitted as much in a
comment — «135/85 fire the card and appear in NO source this product cites,
which is why no user-facing string may state either of them» — and
`medical_copy_tokens_test` enforces that on the copy. **The colour was the hole
in that rule.** An amber tile, announced to a screen reader as «, вне
безопасного диапазона», publishes the band to the reader exactly as printing
«135» would. Refused sentence #23's second half.

Done: the `watch` tier is gone from `metricStatus`'s systolic and diastolic
branches (`app/lib/domain/health_series.dart`). Blood pressure now grades against
140/90 and nothing else — cited to ACOG in `packages/shared/src/triage.ts` and
pinned in the contract. A device reading below the cutoff is `ungraded` as
before; 140/90 still forces `danger` from every source.

**Verified by reverting.** `if (v >= 135) return watch` and `if (v >= 85) return
watch` put back into both branches: `metric_status_test` **fails**, on eight
assertions, the sweep naming the value and the source —
`systolic 135 (sensor) graded as a warning — on what cited band?` and
`diastolic 85 (sensor) graded as a warning — on what cited band?` — plus
`Expected: MetricStatus:<MetricStatus.ungraded> Actual: MetricStatus:<watch>` on
the wrist-137 case. Restored, and `flutter test` in `app/` is **2286 passing**,
`dart run tool/verify_all.dart` **82 runners · 3138 assertions**.

Narrowed, deliberately: `health_advisor.dart` still FIRES `ADV_BP_ELEVATED` /
`ADV_BP_DEVICE_HIGH` at 135/85. A trigger that decides who is shown a card which
describes and cites 140/90 is not the same act as a verdict painted on a tile,
and deleting those cards would delete the only sub-emergency blood-pressure
warning a wrist reading can raise. **Removing a warning is a clinical decision
and it is not this gate's** — it needs the OB-GYN, together with §1.1. The
reading below 140/90 is now unsaid by the tile and still spoken about by the
card, which is the right way round.

Recorded rather than silently fixed: a cuff reading she typed in at 137/88 now
grades `normal` — it is on the right side of the only band this product cites,
which is what `normal` means here — while `ADV_BP_ELEVATED` says «близки к
140/90». Hand entry is currently removed (§1.2, §2.5), so nothing reaches that
pair today. If it returns, the tile and the card must be settled together.

### 37.8 °C and 38.5 °C — could not source. REFUSED.

**I could not source either number**, and I will not name one from memory. The
widely published fever definition is 38.0 °C — which is also the number this
product's own canonical `emergency_help.json` publishes twice. 37.8 °C and
38.5 °C appear in no document in this repository, and the gate can point at no
guideline that sets a *pregnancy* fever warning at 37.8 or an emergency at 38.5.

**And the gate refuses to apply the other half of the decision to them.**
"Stop grading" is not a neutral act here:

* 38.5 °C is the ONLY fever emergency this product has — `HIGH_FEVER`, app and
  backend, pinned across `triage_thresholds.json` by the contract tests on both
  sides. Stopping it from grading would make §1.2's hole permanent: a pregnant
  woman typing 39.2 from a thermometer would get nothing at all.
* 37.8 °C is what fires `DEVICE_TEMP_HIGH` and `ADV_TEMP_DEVICE_HIGH` — the
  reachable card that tells her a wrist estimate is raised, to use a thermometer,
  and to call her doctor today. Removing it removes that card.

Both are removals of clinical content, which this document has held from the
start is as much a clinical decision as adding it. Neither is the gate's to make;
and substituting 38.0 °C, even though it is better attested and already used
elsewhere in this repo, would be moving an emergency cutoff on an inference.

**The question for the OB-GYN, in the form it can be answered:**

1. Does the RK protocol or another named guideline set a fever threshold in
   pregnancy? If yes, record it beside `temperatureC` in
   `packages/contract/triage_thresholds.json` and the numbers stay.
2. If no such threshold can be named, is the product's own 38.0 °C — already
   published to mothers for a newborn and for the puerperium — the number the
   pregnancy branch should use as well? That would make the app internally
   consistent, and it is the one change this gate would sign if a clinician
   proposes it.
3. Either answer must move BOTH twins (`app/lib/core/triage.dart` and
   `packages/shared/src/triage.ts`) and the contract together, or the phone and
   the server will disagree about a fever.

Until then 37.8 and 38.5 keep grading, uncited, and §1.1 stays open for them.
Recorded as a known and accepted gap, not as a solved one.

### One more, found while looking, and not among the owner's four

`health_advisor.dart` gates `ADV_BP_STEADY` — a REASSURANCE — on
`sys.latest < 130 && dia.latest < 85`. 130/85 is uncited in exactly the way
135/85 was, and it grades a positive claim, which this document ranks as the
worse direction. The card is unreachable today (hand entry removed), which is
the only reason this is a note rather than a change.

**CLOSED the same day — see «ADV_BP_STEADY — REFUSED, and the card with it»
below.** The owner ruled it now rather than later: unreachable today means
reachable the day hand entry returns, and §1.2 and §2.5 both record that
decision as still open, so this was a trap waiting for whoever reopens that
door.

### The tree was not green when this arrived, and it is not the gate's to fix

`reviewed_medical_copy_test` fails on `db_ring_partial` and `lab_intro`: both
were edited in the working tree by the concurrent Kazakh pass (§9.12), both are
pinned medical strings, and neither has a verdict. Their fingerprints were left
alone. An unreviewed item blocking a release is the system working — and
`lab_intro` is the modal softening this document already flagged, so the pass is
touching the right string; it still needs a verdict before the pin moves.

**Both have verdicts now**, 2026-08-19, below.

---

## Four items ruled 2026-08-19 (second sitting)

Two were decisions the owner had already made and sent here to be implemented
or refused; two were verdicts only this gate could give.

| item | verdict | against what |
|---|---|---|
| `kick_goal_reached` (+ `kick_goal_hits`, + two wordless siblings) | **REFUSED as written; CHANGES made** | RK MOH «Антенатальный уход» (2025), the paragraph on movement counting |
| `ADV_BP_STEADY` / `ADV_BP_STEADY_b` | **REFUSED, and the card with it** | no source; the same search that failed for 135/85 |
| `lab_intro` | **CHANGES** — kk only; ru + en **APPROVED unchanged** | the screen it introduces, and `lab_go_title` beside it |
| `db_ring_partial` | **CHANGES** — kk only; ru + en **APPROVED unchanged** | Kazakh negation scope; the claim the string exists to make |

### `kick_goal_reached` — REFUSED as written; CHANGES made

The owner ruled that the counter stays and the reassurance verdict goes, and
invited a refusal if the reasoning was wrong. **It is not wrong, and this gate
would have reached the same place from the protocol alone.** The counter earns
its keep because it produces the SUBJECTIVE trigger the protocol acts on and
because a woman who wants to count will count somewhere; «Цель достигнута» is a
positive clinical claim on a screen whose own cited protocol says the count
behind it predicts nothing:

> «Нет доказательных данных по эффективности профилактики неблагоприятных
> перинатальных исходов на основании подсчета числа движений плода.»
> — RK MOH «Антенатальный уход» (2025), `docs/Антенатальный уход.docx`, the
> document `an_source` cites on screen.

**What replaces it states her numbers and stops.** Not an alarm either: most
days ten movements is simply what happened, and a counter that ends in worry
every time is a counter she stops opening — the calibration
`kickSessionEndedEarly` was already written for.

| | before | after |
|---|---|---|
| ru | «Цель достигнута» | «Шевелений: {n}, время: {t}» |
| kk | «Мақсатқа жетті» | «Қимыл: {n}, уақыты: {t}» |
| en | «Goal reached» | «{n} movements in {t}» |

The clause is not translated fresh: it is `kick_low_body`'s own descriptive
half, minus «Записано», read clause for clause in all three languages by this
gate earlier the same day. `{n}` is interpolated because the counter does not
stop at ten — a hard-coded «10» under a circle reading «14 / 10» would be the
app misdescribing what she just did.

**Three more instances of the same verdict, and two of them carry no words at
all.** The item arrived as one string; it was four.

1. **The mint disc and ring** (`kick_session_screen.dart`). Both turned
   `Palette.good` — this app's «healthy» colour — the moment the count reached
   ten. That is «Цель достигнута» in the register a sentence cannot qualify, and
   it is exactly the hole the amber tile turned out to be for 135/85 («The
   colour was the hole in that rule», above). Stripping the words and leaving
   the mint would have moved the claim, not removed it. One colour throughout
   now, the control's own; the filled ring still shows the count against ten.
2. **The green tick per history row** (`womens_health_screen.dart`,
   `_KickHistoryRow`). Every saved session with ten or more movements ended in
   `Icons.check_rounded` in `Palette.good`. It carried no string, so no
   fingerprint and no token guard could ever have caught it — it was found by
   reading the widget beside `kick_goal_hits`. Removed, and nothing takes its
   place: the row already states the count and the duration.
3. **`kick_goal_hits`**, the label over «3/5» in the history strip, read «Цель
   достигнута» / «Goals met» — the identical Russian words, scoring her past
   sessions against the same target. It was NOT in the manifest and
   `isMedicalKey` did not match it, which is how it survived the same review
   twice. Now «10+ шевелений» / «10+ қимыл» / «10+ movements», and pinned. Ten is
   not a new threshold: it is the count-to-ten method's own number, already on
   the counter as «/ 10» and stated in `kick_method_note`.

**Not done, deliberately.** No sentence about the evidence base was added to the
counter (the `epds_not_validated` shape). That is new user-facing clinical copy
and needs the owner, not the gate — it is consequence 3 of the movement ruling
above and stays open.

### `ADV_BP_STEADY` — REFUSED, and the card with it

The owner ruled: apply the 135/85 treatment now, «either cite the band or stop
asserting on it». **No band could be cited**, so the assertion stops.

Where the gate looked is recorded above under «The four uncited numbers»: the RK
MOH protocol document, `92 бұйрық.docx`, `antenatal_protocol.json`,
`emergency_help.json` and `triage_thresholds.json`. None of them names 130/85
any more than they named 135/85.

**Two narrower fixes were considered and both are worse.**

* *Re-base it on the elevated card's own trigger* (`else if (belowEmergency &&
  !bpFromDevice)`, i.e. fire below 135/85). That does not remove an uncited
  number from a positive claim; it moves the claim onto the other uncited pair.
* *Cite 140/90* — the one attributed number this product has (ACOG, via
  `packages/shared/src/triage.ts`). It would call 139/89 «ровное».

So the branch is gone from `generateAdvisories` and both keys are DELETED from
the catalogue, on `repeat_cta`'s precedent and §2.5's rule that «a dead key is a
live key to the next person who finds a call site». A cuff day now ends at
`ADV_NOTHING_UNUSUAL`, which was written for exactly this absence and claims no
more than the readings support.

**This is not the first step of silencing the metric, and the code says so.**
`ADV_BP_ELEVATED` and `ADV_BP_DEVICE_HIGH` still fire from both sources, triage
still escalates at 140/90 from both, the cuff reading still travels to the
clipboard with its number in it, and a wrist estimate in the danger band still
pulls the ring down. `bp_advisory_provenance_test.dart` asserts all of that in
the same group as the removal, so neither half can be lost while the other is
being defended. Its «a cuff reading she typed in still does» expectation was
REVERSED with this verdict behind it — the old test's fear was that the fix
becomes «say nothing about blood pressure», and the answer is that only the
verdict went.

Unreachable today (hand entry removed, §1.2/§2.5), which is why no user sees a
change; the point is that it cannot come back the day that door reopens.

### `lab_intro` — CHANGES (kk only)

ru «когда **пора** ехать» and en «when it's **time** to go» both prompt. kk
«қашан баруға **болатыны**» is PERMISSION — «when one is allowed to go» — on the
sentence that introduces the entire «when to go in» screen, above a list that
holds ruptured membranes, bleeding, preterm contractions and reduced movements.
A softened translation is a different clinical claim, and this is the direction
that costs hours: a woman who reads that she MAY go decides later.

**The language gate's proposal is accepted: «қашан бару керегі».** The question
referred here was whether necessity overshoots the Russian. It does not, for two
reasons that are on the screen rather than in a dictionary: the modal is bounded
by «қашан» and by the list it introduces — it never says go NOW, the `lab_go_*`
items say on what — and the section heading immediately below it,
`lab_go_title` «Қашан бару немесе қоңырау шалу», already uses the bare
infinitive with no permissive modal. The Kazakh was the outlier among its own
neighbours, not the Russian.

ru and en **APPROVED unchanged**. `lab_disclaimer` sits directly below and is
what keeps the screen from reading as instruction from us.

`lab_intro` stays in `contraction_timer_test.dart`'s `knownUnreviewed` set for a
different reason than before, and the comment there now says which: its Russian
contains «пора ехать», which that scan matches as a fragment. That scan is about
the 5-1-1 THRESHOLD clause, and this string states no number.

### `db_ring_partial` — CHANGES (kk only)

**In remit, and not for the reason it was referred.** The owner offered that this
may fall outside the clinical gate because it counts metrics rather than
describing a body. The count is not the issue; the negation is. This string
exists to stop a full ring from claiming that everything was assessed, and
Kazakh «Барлық көрсеткіш ескерілмеді» puts the negation on the verb after «every
metric» — a reading of «NONE of them was counted» is available, which is the
opposite absence and the one `db_ring_ungraded` already means. Russian is safe
because «Учтены не все» negates «все» directly. That is a claim about what the
app assessed, so it is this gate's.

**Accepted as proposed: «Барлығы ескерілмеді: {total} көрсеткіштің ішінен {n}.»**
The negation now sits on «барлығы» and the arithmetic after the colon says what
WAS counted. The grammar half — «{total} ішінен» rendered «4 ішінен 2», a bare
numeral with no noun for «ішінен» to govern — is the language gate's and is
accepted with it; it changes no claim. The numeral-possessive dodge is intact
({n} stays bare, so no locale needs a rule for n = 1), it still names a count
and not a feeling, and `peace_ring_coverage_test` still pins that it is neither
an alarm nor a reassurance in all three languages. Fits at 320 dp / 130 % in
Kazakh (`narrow_phone_test`). ru and en **APPROVED unchanged**.

### Verified by reverting — each change on its own, exact messages

1. `kick_goal_reached` restored in all three languages. **Fails**
   `reviewed_medical_copy_test` — `kick_goal_reached: 942b0082b689e064 ->
   f0f87b2a5e8b7ade`, the exact hash it was pinned at on 2026-08-18 — and
   `kick_session_test`: `Found 0 widgets with text containing 10 movements in`.
2. **The KAZAKH alone** restored to «Мақсатқа жетті», ru and en left corrected.
   **Fails** the fingerprint only — `kick_goal_reached: 942b0082b689e064 ->
   c2e284e9511f9aee` — and `kick_session_test` PASSES, because its assertions
   read the English. The same lesson as `kick_low_action`: a one-language
   softening is caught by the fingerprint and by nothing else.
3. Mint put back on the ring. **Fails** — `Expected: Color:<…red: 0.8392, green:
   0.0000, blue: 0.2902…> Actual: <…red: 0.0902, green: 0.6627, blue: 0.4784…>`,
   `mint at ten is «Цель достигнута» drawn instead of written`.
4. The green tick put back in the history row. **Fails** — `Expected: no matching
   candidates / Actual: Found 1 widget with icon "IconData(U+0F636)"`.
5. `kick_goal_hits` restored. **Fails** three guards at once —
   `kick_goal_hits: 894aa4be4d4149c2 -> 0c77634fe370d76f`, `Expected: not
   contains 'Цель' / Actual: 'Цель достигнута'`, and `Found 0 widgets with text
   "10+ movements"`.
6. `ADV_BP_STEADY` / `_b` put back in the CATALOGUE only, the branch left
   deleted. **Fails** — `Medical keys with no reviewed fingerprint:
   [ADV_BP_STEADY, ADV_BP_STEADY_b]`, plus the new catalogue-absence test. Worth
   recording: an `ADV_*` key cannot be re-added without a verdict even when
   nothing renders it.
7. The advisor branch put back as well. **Fails** —
   `Expected: not contains 'ADV_BP_STEADY' / Actual: ['ADV_NOTHING_UNUSUAL',
   'ADV_BP_STEADY']` on the cuff path, and `verify_advisor.dart`: `FAIL  normal →
   no blood-pressure reassurance, from any source`, `32 passed, 1 failed`.
8. Both Kazakh strings restored. **Fails** — `db_ring_partial:
   4826097ffa3b6a87 -> 0233d3702667aff9` and `lab_intro: 1853663aac4db948 ->
   f3aa307c7e323c3b`, both the exact hashes they were pinned at.
   `narrow_phone_test` and `peace_ring_coverage_test` PASS on the old Kazakh —
   they measure fit and placeholders, not meaning — so the fingerprint is the
   only guard these two have, which is the argument for it.

All eight reverted. `flutter test` in `app/`: **2288 passing** (2286 plus the two
tests added here). `dart run tool/verify_all.dart`: **82 runners · 3138
assertions**.

