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
- [ ] Every icon-only button has a semantics label / tooltip.
- [ ] Text contrast is legible for tired eyes; no gray-on-gray body text.
- [ ] Live/critical status regions use Semantics(liveRegion: true).

## 5. State coverage
- [ ] Empty, loading, and error states designed — not just the happy path.
- [ ] Warm, reassuring, non-alarming copy (amber over red for "delayed", etc.).

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
- `onboarding_flow.dart`: `Radio.groupValue`/`onChanged` are deprecated in favour
  of a `RadioGroup` ancestor. It's a structural widget change in the onboarding
  flow with no widget-test coverage, so it needs an emulator pass to verify —
  deliberately deferred rather than changed blind.

> If a reviewer/user finds a defect this list would have caught, add a line here
> so it never recurs.
