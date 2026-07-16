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
4. `flutter test` + `dart run tool/verify_*.dart` → all green.

> If a reviewer/user finds a defect this list would have caught, add a line here
> so it never recurs.
