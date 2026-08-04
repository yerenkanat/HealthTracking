# Where the app deliberately differs from the design system

`design-system-app.md` is the spec. This is the short list of places the built
app does something else **on purpose**, so that a reader comparing the two does
not "fix" a decision that was already made.

Anything not listed here is either implemented as specified or is an oversight
worth reporting.

## Four tabs, not five

**Spec:** Главная · Здоровье · Дети · Курс · Я
**App:** Здоровье · Календарь · Ребёнок · Профиль

The «Курс» tab has no content behind it. The app does have a lesson catalogue
and a player, but they are reached from the dashboard's timeline, where they sit
next to the week they belong to — moving them to a tab of their own would take
them away from that context for no gain until there is a course to structure.

Owner decision, 2026-08-04: keep four tabs. Revisit if a real course is built.

Everything else about the tab bar follows the spec — see `tab_bar_test.dart`.

## Two tab-bar colours are darker than specified

**Spec:** active `#FF3D71`, inactive `#A895B3`
**App:** active `#B30030`, inactive `#70597C`

The spec's two colours measure **3.6:1** and **2.9:1** against cream. An 11px
label is small text, which needs **4.5:1**. The app uses the darkened
equivalents of the same hues.

This is the one deviation that is not negotiable on preference: the labels name
the only navigation in the app, and at 2.9:1 the inactive ones are not readable
by a large share of the people this product is sold to. `tab_bar_test.dart`
asserts the contrast ratio rather than the hex, so the reason survives an edit.

## No «замер 60 секунд» screen

The spec's feature list names a 60-second measurement as a core screen. It does
not exist and is not being built.

The band streams continuously and the app already shows live heart rate, SpO₂,
temperature and stress from that stream; a "stand still for 60 seconds" flow is
a different measurement contract with the hardware — what it samples, what it
rejects, what it does with a reading taken while walking. None of that is
specified anywhere, and guessing it would produce a screen that looks finished
and reports numbers nobody has validated. On a health product that is worse than
not shipping it.

Owner decision, 2026-08-04: not built. Needs a hardware spec first.

## The pregnancy hero keeps its illustration

**Spec:** "No hand-drawn SVG illustrations — real photos or striped
placeholders."

The pregnancy screen's baby-size disc stays. The rule is aimed at decoration —
spot illustrations used to warm up a screen that could have shown something
real — and this is not that: the disc *is* the datum, drawing the current week's
size the way a chart draws a number. Replacing it with a photo would mean using
someone else's foetal imagery, and a striped placeholder would say nothing.

Everywhere else the rule holds: the map, the empty states and the content cards
all use photos or the striped placeholder.

## The design-system widget set is only partly adopted

`ds_widgets.dart` exports fifteen primitives. As of 2026-08-04 six are in use
(`DsCard`, `DsPrimaryButton`, `DsSecondaryButton`, `DsIconTile`,
`DsMapPlaceholder`, `DsTabBarSurface`) and the rest are being adopted screen by
screen, replacing `GlassCard` and hand-built rows.

Until that finishes, the same surface can look slightly different on two
screens. That is migration state, not a decision — a screen still using
`GlassCard` has simply not been converted yet.
