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
| Tile grade / colour / out-of-range label | temperature gated; BP still green on an uncited band |
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
