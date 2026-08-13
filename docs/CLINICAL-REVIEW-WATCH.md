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
| Temperature | never coloured — recommended removal | — | — |
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

## Triage is unchanged, and three guards keep it that way

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

## Open tickets this raised

- The **live** Starmax temperature reaches `assessTelemetry` as `coreTempC`
  unconverted, while the OEM path converts. A false-emergency risk in both
  directions, pre-existing and outside this review.
- `server.ts` bounds `systolicAvg` and `bloodSugarTenths` at 255 while the
  ingest handler and CHECK constraints allow 260 and 300; values in the gap fail
  the whole wearable item at the wire. Harmless until a max column arrives.
- Hard-coded l10n medical strings have no equivalent of `carryReview`, which
  revokes a content card's review when its text changes. The same discipline
  should apply.
