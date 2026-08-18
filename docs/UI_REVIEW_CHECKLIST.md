# UI Self-Review Checklist (run before every UI delivery)

A short, mandatory pass to catch the "junior mistakes" — the kind a careful
designer would never ship. Go screen by screen; every box must be checked, or
the issue fixed, before saying a screen is done.

## 1. No duplicate or redundant controls
- [ ] **One entry per destination per screen.** A screen must not offer the same
      navigation/action twice (e.g. a Settings gear in the AppBar **and** an
      "Open settings" card in the body — pick one; the AppBar icon is the
      convention). _This is the mistake that triggered this checklist._
- [ ] No control repeats what a floating layer already shows (e.g. map placeholder
      listing zones that the floating zone pills already show).
- [ ] Each icon/button has exactly one obvious meaning; no two buttons do the same thing.

## 1b. Destructive actions always confirm
- [ ] **Every delete / remove / unpair / reset asks for confirmation first** via
      `confirmDestructive(...)` — a single mis-tap must never silently lose data.
      _This is the mistake that added this rule (a child was deleted on a mis-tap
      with no prompt)._
- [ ] The confirm dialog names what's affected and warns when it can't be undone.
- [ ] Delete affordances have a tooltip/semantics label.

## 2. Navigation integrity
- [ ] Bottom nav ≤ 5 tabs, each with a distinct icon + label.
- [ ] Back behaviour is predictable; no dead ends, no navigation loops that trap the user.
- [ ] Tapping a tab you're already on doesn't stack duplicate routes.

## 3. Visual hierarchy & consistency
- [ ] One primary action per screen, visually dominant.
- [ ] Consistent card radius, spacing scale, and iconography across screens.
- [ ] No emoji used as UI icons (use vector/Material icons).
- [ ] Merged/real-world groupings where clinics/users expect them (e.g. BP = "138 / 77").

## 4. Touch & accessibility
- [ ] Interactive targets ≥ 48×48 dp with ≥ 8 dp spacing.
      _Text links inside dense cards are the usual offenders — a 12dp label with
      `vertical: 2` padding renders ~20dp and looks fine by eye. Measure, don't
      squint: `test/touch_targets_test.dart` asserts rendered heights, and new
      inline tap targets should be added to it._
- [ ] Every icon-only button has a semantics label / tooltip.
- [ ] Text contrast is legible for tired eyes; no gray-on-gray body text.
- [ ] **Text on an accent tint uses the `*Text` token, never the fill token.**
      `Ds.mintText` / `Ds.amberText` / `Ds.blueText` / `Ds.coralText` exist for
      exactly this pairing. _This is the mistake that added this rule: the child
      map's freshness badge painted its label in the fill colour on a 14 % tint
      of that same colour —_
      ```
      live    #17A97A on its own tint — 2.62:1
      delayed #E08A00 on its own tint — 2.38:1
      recent  #1F5FBF on its own tint — 4.96:1   ← the only one that passed
      ```
      _13 px bold needs 4.5:1, so the one claim that screen exists to make — how
      current a child's position is — was illegible in exactly «she is fine» and
      «this is late». The blue middle state passed, which is why it never looked
      obviously broken and shipped anyway._ An icon may keep the fill: 4.5:1 is
      a rule about text. `test/accent_contrast_test.dart` computes the ratio
      arithmetically, because the framework's `textContrastGuideline` samples
      what is on screen and can be satisfied by a label that happens to sit over
      an opaque parent — a different question from whether the PAIRING is sound.
- [ ] Live/critical status regions use Semantics(liveRegion: true).
- [ ] **A primary or repeated action sits in the thumb zone (bottom of the
      screen), not the top.** She holds the phone in one hand and taps with the
      other's thumb; a top-anchored button forces a re-grip every time. Put the
      list/content up top and pin the action at the bottom (Expanded fills the
      middle, button last) — as the Contractions timer and the emergency call
      button already do. _This is the mistake that added this rule: the
      Contractions "Start" button, tapped every contraction through labour, was
      pinned to the top of the screen._

## 5. State coverage
- [ ] Empty, loading, and error states designed — not just the happy path.
- [ ] Warm, reassuring, non-alarming copy (amber over red for "delayed", etc.).
- [ ] A card that hides itself when empty still leaves a way IN. The sleep card
      returned `SizedBox.shrink()` with no nights, which is the permanent state
      for anyone without a band — the users the hand-entry path exists for saw
      no sleep feature at all. Ask who lives in the empty state forever.
- [ ] Anything the user types by hand is persisted. Band/sensor data is
      transient because the device re-supplies it; nothing re-supplies a
      hand-entered reading, so it must survive a restart.
- [ ] A feature that grades user input only asks for what the user can know.
      Judging a hand-logged night on deep sleep — unmeasurable without a band —
      scored a perfect 8 hours as "fair".
- [ ] Capped lists drop the right thing. The 50-alert feed trimmed purely by
      age, so routine zone crossings silently erased older SOS alerts. If a
      list has a cap, ask what the most important entry in it is.
- [ ] **A shape cannot be qualified — an aggregate must show its coverage, not
      just its verdict.** A ring, a bar, a percentage or a score computed over a
      FILTERED pool must say how much of the whole it speaks for; the sentence
      beside it is not enough, because the shape is read first and read alone.
      _Two releases came from one line._ The dashboard's peace ring was
      `withData == 0 ? 1.0 : healthy / withData`: with nothing gradeable it drew
      a complete, reassuring circle out of an ABSENCE, and once that was fixed
      it went on drawing the same complete circle from **two cards of four**,
      because every card the clinical gates refused was `continue`d out of the
      numerator and the denominator together. Ask of any aggregate: what is in
      the denominator, what silently left it, and does the picture change when
      something does? The answers now live in `domain/peace_ring.dart` and
      `test/peace_ring_coverage_test.dart`.
- [ ] **«Not assessed» is a state, and it looks like neither of the other two.**
      Ungraded is not healthy and it is not a warning; `MetricStatus.ungraded`
      draws it in body ink on the tiles and the ring dashes it in the same ink.
      It is deliberately NOT the dim ink that means stale — «old» is a different
      claim from «not judged», and a reading two minutes fresh must not be told
      it is old.
- [ ] **A `??` that reaches the paint or the label is an invented number.**
      The aggregate rule above is about denominators; this is its scalar twin,
      and it hid for longer because one character is easier to miss than a
      formula. The cycle ring drew `(info.cycleDay ?? 1) / avgCycleLength` and
      printed the same `1` in its middle, so a woman whose cycle day the app did
      not know was told she was on **day 1** — the first day of bleeding, a
      specific clinical claim, chosen by a fallback operator. Grep any
      health-bearing widget for `??` before shipping it. If the value can be
      absent, the ABSENCE is a state to design: the shape drops to
      `fraction: null, assessed: 0`, the number becomes «—», and the copy says
      why — naming the cause where the cause is knowable, and offering the fix.
      See `womens_health_screen.dart` `_CycleHeader` and
      `test/cycle_unknown_day_test.dart`.
- [ ] **A fallback in a `switch` is the same defect with a longer name.**
      `cycleBandFor` mapped `null => CycleBand.follicular`, so the dashboard hero
      headlined «Спокойные дни» over a lit segment of five for **every account
      with nothing logged**, and a test blessed it because follicular was the
      softest wrong answer available. A default that must be chosen is a default
      that will be chosen wrong: make the return type nullable and let the
      caller draw the absence.
- [ ] **A golden blesses whatever you draw.** `home_dashboard.png` was a
      photograph of the full-ring defect and passed for a month. When a golden
      changes, look at the image and say in the commit why the NEW one is right;
      when one does not change and you expected it to, that is a finding.

## 6. Localisation
- [ ] Every user-facing string goes through l10n (ru/kk/en) — no baked-in language.
- [ ] `dart run tool/verify_l10n.dart` passes (all keys have all three locales).

## What only LOOKING catches
The automated checks pass on things that are still wrong, because they are
legal layout:
- **Ellipsis is not overflow.** No test fails when a title renders as "Ваше
  здоров…". The dashboard and calendar titles were truncated on the first two
  screens of the app, in its default language, with every test green.
- **A number scales down; it never ellipsizes.** `TextOverflow.ellipsis` is for
  prose a person typed — a note, a lesson title. On a figure, a unit, a control
  label or a screen title it does not degrade the reading, it makes it *wrong*:
  "1 234 ша…" and "12 340 шагов" are indistinguishable, and «0 шевелений сег…»
  was found on a real 1080 px device with the whole suite green. Use
  `FittedBox(fit: BoxFit.scaleDown)`, as `_MetricCard` and `_ModeChip` already
  do. Better still, don't put a sentence in a value slot: the value line carries
  a number and at most one short word, and the long form lives in the label.
- **A hand-rolled formatter is not a missing translation.** verify_ui_strings
  checks literals in the source; it cannot see `'${h}h ${m}m'` built at
  runtime, which printed "уже 1m" inside a Russian sentence.
- **Two texts at the same weight are one paragraph.** Every lesson in the
  Ма!Ма! course took the default body style for both its title and its
  summary, so a two-line title ran straight into its summary and a
  thirty-item list could not be scanned. Nothing overflowed, nothing was
  truncated, every test was green. The fixtures were the reason: each was
  short enough to fit one line, so the two never met. **Give a list fixture
  the longest real content it will ever hold, then look at it** — staff type
  lesson titles, zone names and medication labels at whatever length they
  like, and one-line fixtures test a layout nobody will see.

And conversely, **the emulator is not a small phone**. The AVD here is 411dp
wide; the five real overflow bugs only appear at 360dp. Neither the eye nor the
test suite covers the other's blind spot — run both.

## How to run it
1. Build & launch on the emulator; **look at every screen** (don't just trust the code).
2. Walk this list per screen. Screenshot and compare against the spec.
3. `flutter analyze lib test` → zero errors/warnings.
   _Analyze the whole tree, not the files you touched: per-file analysis hid 33
   issues (incl. the entire `test/` tree) until the first full run._
4. `flutter test` + `dart run tool/verify_all.dart` → all green.

## Known follow-ups (don't re-discover these)
_(none open)_

## Running the on-device tests
`integration_test/` needs a real device or emulator:
```
adb shell pm grant com.fcs.fcs_app android.permission.POST_NOTIFICATIONS
flutter test integration_test/reminder_delivery_test.dart -d <device>
```
Granting once beforehand is NOT enough, and this bit me twice: `flutter test`
reinstalls the app as part of the run, which resets the runtime grant, so a
grant issued before the command is already gone by the time the app starts.
Run a re-granting loop alongside the test instead:
```
while :; do adb shell pm grant com.fcs.fcs_app android.permission.POST_NOTIFICATIONS; sleep 3; done &
```
Without it the consent dialog appears mid-run with nobody to tap it and hangs
the whole thing. If a run stalls with
no output, check `adb shell dumpsys window | grep mCurrentFocus`: a
GrantPermissionsActivity or an "Application Not Responding" window means the
emulator is blocking, not the app. A wedged emulator (`ANR: system`) makes
notifications undeliverable and looks exactly like an app bug — reboot it
before believing a delivery failure.

_Cleared: "medication reminders actually firing". Now verified on-device by
reminder_delivery_test.dart, which checks the permission, that a notification
really reaches the shade, that scheduleDaily registers with the OS, that cancel
deregisters, that rescheduling replaces rather than duplicates, and that a past
time is refused. It deliberately does NOT assert when a scheduled reminder
arrives: the app uses inexact alarms on purpose (so it needn't request
SCHEDULE_EXACT_ALARM, which the emulator refuses anyway), and Android batches
those freely. Asserting a delivery deadline would be asserting a guarantee the
platform never made._

_Cleared: the `onboarding_flow.dart` `RadioGroup` migration. It had been deferred
for needing an emulator, but the real blocker was missing coverage — the flow
test tapped straight past both radio pages. Writing tests for what selecting a
language and a band actually does made the change verifiable without a device:
the same tests passed before and after. When something is deferred as
"needs a device", check whether it's really "needs a test" first._

> If a reviewer/user finds a defect this list would have caught, add a line here
> so it never recurs.
