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
- [ ] Live/critical status regions use Semantics(liveRegion: true).

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

## 6. Localisation
- [ ] Every user-facing string goes through l10n (ru/kk/en) — no baked-in language.
- [ ] `dart run tool/verify_l10n.dart` passes (all keys have all three locales).

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
Grant the permission FIRST and re-grant after any reinstall — `flutter test`
reinstalls the app itself, which resets the runtime grant, and the consent
dialog then has nobody to tap it and hangs the whole run. If a run stalls with
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
