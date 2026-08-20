# Where the app deliberately differs from the design system

`design-system-app.md` is the spec. This is the short list of places the built
app does something else **on purpose**, so that a reader comparing the two does
not "fix" a decision that was already made.

Anything not listed here is either implemented as specified or is an oversight
worth reporting.

The tab bar itself is **not** on this list. It used to carry an entry reading
"four tabs, not five", which was wrong twice over: `CLAUDE-app-design.md` §2.15
specifies exactly «Сегодня ☀ · Календарь ▦ · Ребёнок ◎ · Профиль ☺», in that
order, so the build matches the spec — and the reason the entry gave for having
no «Курс» tab (that the course is reached from the dashboard timeline) had
stopped being true: the course is reached from Профиль. Filing a correct build
as a compromise is how a later reader "fixes" it back. `tab_bar_test.dart` now
drives the real `HomeShell` and asserts those four, their order and their
labels.

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

Everywhere else the rule holds for the content cards, which use photos.

**It does NOT hold for the map, and this file said it did.** Corrected
2026-08-13 after checking rather than trusting the sentence:

- `app/lib/ui/tracking/tracking_map.dart:73` paints `surfaceContainerHighest` —
  a flat pink fill. `DsMapPlaceholder`, which draws the spec's
  `repeating-linear-gradient` from `Ds.mapStripeA/B`, has **no user in `lib/`
  at all**; it is referenced only by its own definition and by tests. The whole
  point of the stripe is that an unloaded map must not read as a broken one,
  and a flat pink rectangle reads as broken.
- The empty states are five different shapes, not one, and three of them offer
  no action — against the spec's own rule that every list's empty state carries
  a reason and one action.

Neither is a deviation anybody decided on; both are gaps. They are written here
as gaps so the next reader does not take this section as a clean bill of
health — which is what it was, for as long as the sentence stood unchecked.

_A note on this file's purpose: it records decisions taken deliberately AGAINST
the spec, with the reason. A line that asserts conformance is doing something
different, and is only worth its ink if somebody has just verified it. Prefer
"checked on <date>, holds" over a bare claim._

## Some rows are deliberately not `DsRow`

`DsRow` is the list row: a leading mark, a label, an optional second line, a
value or a trailing control. Settings and the reminders centre use it, and
`GlassCard` is gone — every card in the app is a `DsCard`.

Several screens keep their own row widget, and should:

| Widget | Screen | Why it is not a list row |
|---|---|---|
| `_ItemRow` | hospital bag | a checklist item — the tick IS the control |
| `_FreqRow` | cycle insights | label plus a proportional frequency bar |
| `_SignRow` | labour signs | a bullet of prose, not a label/value pair |
| `_MenuRow` | appointments | a popup-menu entry, not a row in a card |
| `_CycleRow` | cycle insights | a dated event with a trailing measurement |

Converting these would mean deleting the thing that makes each one useful. A
shared primitive is worth having where the pattern actually repeats; forcing it
where it does not is how a design system starts making screens worse.

## Screen 43 has no operator's name in its header

**Spec:** «43 · Поддержка · оператор — шапка **с именем оператора** → диалог →
действие в чате → чипы → поле».

The header says «Оператор Ana-Bala» and no first name.

The schema records which member of staff wrote a reply — `support_replies.staff_id`
— and the app is never told. That is on purpose in two directions. A
customer-facing screen naming a person makes that person the address for
everything afterwards: she asks for Айгуль next time, Айгуль is on leave, and
the shift that answers instead reads as a downgrade. And a name shown over an
answer somebody else wrote — a colleague picking up the ticket, which is the
normal case on a desk of three — is a small lie the screen tells every time it
opens.

So the header carries the role, which is true whoever is on shift, and the
timestamps under each bubble carry the rest. Showing a made-up first name to
satisfy the frame would have been the one thing worse than omitting it.

Everything else in the frame is built: the dialogue, «действие в чате» (offered
only when this build can really perform one), the topic chips and the input with
its round `↑`.

## Screen 21 has no «Позвонить Алие»

**Spec:** «21 · SOS — … → «Позвонить Алие» (белая) → «Открыть карту» →
«Сообщить Нуржану и Әже».»

Two of those three are built. The first is not, and the screen says so.

Nothing in the schema holds a telephone number for a child or for the tracker
she wears. `children` carries a name, a gender and a date of birth;
`child_devices` carries an id, a kind and a battery level. There is no column
anywhere that could answer «какой номер у Алии», and there is no source that
could fill one in — the app has never asked for it and the back office has
never shown it.

So the screen prints «Позвонить ребёнку из приложения нельзя: номера брелока в
карточке нет» and puts 103 immediately under it, using the same
`CallAmbulanceFooter` every red-flag screen in the app ends with. The
alternative was a white button labelled «Позвонить Алие» wired to the first
number in reach — the mother's own emergency contact, or the doctor on the
child's medical card — which on this screen, at this moment, is the worst thing
the product could do.

«Сообщить Нуржану» IS built, from `child_emergency.contact_name` /
`contact_phone`, which the parent fills in on the child's medical-ID card. When
that card is empty the button is absent and a note says the contact is not
filled in, rather than a dead control.

Adding a child/tracker phone number is a real feature — a migration, both
repositories, the route, the sync and an editor to type it into — and it should
be built. It is not something to invent inside a screen.

## Screen 21's location card draws no live map by default

The card shows the map when the build has a Maps key
(`--dart-define=MAPS_ENABLED=true`), and the position with its freshness stamp
when it does not — the same behaviour as the tracking tab, from the same
`buildTrackingMap`. With no fix at all it says the app has not received one
instead of centring a map on a default coordinate, which would draw a pin in
Almaty for a child in Shymkent.

## Детектор плача — four numbers and two promises that are not built

Frames 15a–15e were supplied with a five-frame visual reference. Its layout is
adopted. Six things in it are not, and each is refused for a reason that lives
in this repository's own code.

### «работает без интернета — звук не уходит на сервер» (15b) and «Всё считается на телефоне» (15d)

**Refused, permanently, until an on-device build exists.**

The audio is uploaded. `app/lib/data/cry_recorder.dart` writes a clip,
`app/lib/data/cry_classifier_client.dart:52` posts it,
`packages/backend/src/server.ts:778` proxies it, and
`packages/cry-classifier/app/main.py` classifies it. Nothing on the phone does
inference.

Three things make this non-negotiable rather than a preference:

1. `app/test/cry_privacy_test.dart:81` forbids «не уходит» / «на телефоне» /
   "never leaves" in this copy, and `:93` requires the string to say **both**
   halves — that it is sent, and that it is not kept.
2. The published privacy policy (`legal_priv_cry_b`, live in ru/kk/en) states
   that the sound leaves the phone and is stored nowhere. A screen contradicting
   the policy is worse than either document alone.
3. It is a promise about a mother's baby's voice.

The shipped wording is `cry_privacy`, and it stays above the record button.
`docs/CLAUDE-app-design.md` §7 used to carry the on-device claim as product
logic; it has been corrected in place. Tracked as `docs/TODO.md` §9.11.

### «15 секунд» (15b) / «из 15 секунд» (15c) → **5 seconds**

`packages/cry-classifier/cry_features.py:33` sets `DURATION_SEC = 5.0` and
`fix_length` truncates or pads every input to exactly five seconds. A
fifteen-second capture would send ten extra seconds of a crying baby to a server
and then discard them. The number on screen equals `cryRecordSeconds`
(`app/lib/ui/tracking/cry_insight_screen.dart:22`), which equals the model's
window. If the window ever changes, all three change together.

The recorder does stop itself — `Timer(Duration(seconds: cryRecordSeconds),
_finish)` at `cry_insight_screen.dart:117` — so the counter is a real countdown,
not decoration.

### «Обычно занимает 5–7 секунд» (15d)

**Not printed.** That is a claim about the classifier's latency, and nothing in
this product measures it: `packages/backend/src/cry/` contains only
`settings.ts`, there is no timing column, no metric and no percentile. A
duration nobody measures is a promise the first slow night breaks. The frame
keeps its progress indicator and loses its number.

### «62 перцентиль» on the «Рост и вес» tile (15a)

**Refused.** `app/lib/domain/child_growth.dart:12-21` declines WHO percentile
bands by an existing, written decision: they require the WHO LMS tables, and a
band that is 300 g off tells a mother her healthy child is underweight. The tile
shows the last measurement and its date instead — real, and it doubles as the
freshness stamp.

### «1 просрочена» on the «Прививки» tile (15a)

**Reworded, not removed.** The count is real —
`vaccinesToCatchUp(ageMonths, vaccinesDoneFor(id))` — but the word is not.
`app/lib/domain/vaccination.dart:126` names the state `passed` and says in as
many words: *NOT "missed": the app has no idea what the child has received.* The
tile reads «Стоит уточнить: N».

### The cry banner above the «Каждый день» grid (15a)

**Dropped.** The grid's first tile is «Почему плачет». A banner one scroll above
a tile to the same destination is two entries to one screen on one screen, which
is the defect that shipped as a «Вес» quick action beside a «Вес» pill. The tile
keeps the banner's content (last check, with its date) and its prominence
(first position).

### «Прививки» is listed once, not twice (15a)

**Deviation, taken when 15a was built.** §15a lists Прививки in the «Каждый
день» grid *and* again among «пять инструментов, привязанных к возрасту»
(Развитие, Прикорм, Безопасность дома, Болезни, Прививки). Both readings of the
spec cannot be satisfied without printing the same destination twice on one
screen, which is what the cry banner was dropped for four paragraphs above.

The tile wins: it carries a count, it is the only one of the two the spec gives
a no-birth-date state to («Укажите дату рождения»), and it therefore does not
need the age gate the other four do. The age-keyed list is Развитие, Прикорм,
Безопасность дома, Болезни — four rows, under the existing `tr_tools` heading —
and the «Укажите дату рождения» repair row still replaces all four when there is
no birth date. `child_hub_test.dart` asserts `vac_title` is found exactly once.

### The segment label «Сегодня» is also the first tab's label

**Noted, not changed.** `child_seg_today` and `nav_today` are the same word in
all three languages (Сегодня / Бүгін / Today), so the «Ребёнок» tab draws it
twice: once in the segmented control at the top and once on the bottom tab bar,
for two different destinations. Both labels are the ones their own specs name,
they sit in visually distinct zones, and renaming either changes reviewed copy
on a screen this frame does not own. Flagged here so the next reader does not
have to rediscover it; `child_hub_test.dart` scopes its finders to
`DsSegmented` for exactly this reason, and a test that did not would have
matched the tab bar and passed for the wrong reason.

### The signed-out cry tile leads to sign-in, not to the cry screen

§15a says the tile «не прячется — она объясняет и ведёт на вход», and the sheet
this replaced dropped the row entirely when signed out. The tile now stays, its
subline is `cry_signed_out`, and tapping it opens `openSignIn` — **not**
`openCryInsight`. The cry screen has no signed-out state yet (that is 15b), so
sending her there would be a dead end that says nothing until she has recorded
her baby for five seconds.

## Onboarding step 4 keeps its field order, and drops the gender icons

**Spec:** frame 35 (`CLAUDE-app-design.md:371`) — «поля Имя, Пол (два сегмента),
Дата рождения с бейджем возраста».

**App:** Имя → Дата рождения → Пол → зоны, and the two segments carry no icon.

Two deliberate calls, both about what the field is worth.

*Order.* Gender is the least consequential thing on the screen: it is nullable
everywhere (`ChildProfile.gender`, and `copyWith` carries an explicit
`clearGender`), the whole step is skippable, and it drives exactly one thing —
which glyph the avatar falls back to when there is no photo. The date of birth
drives the age badge, the growth screen, the development milestones and the
vaccination catch-up. An optional cosmetic field does not sit between the name
and the date that everything downstream reads.

*Icons.* The `ChoiceChip`s this replaced carried `Icons.boy` / `Icons.girl` in
`Palette.violet` — Material's own glyphs, in a colour the design system does not
use, on the one control the spec names by component. «Мальчик»/«Девочка» and
«Ұл»/«Қыз» are not ambiguous words, and the icons cost width on the axis that is
already 10 dp short at 320 dp/130 % (see the table in `design-system-app.md`).
Dropped, not moved.

## Gender stays clearable, and a segmented control had to learn how

A segmented control normally cannot be emptied. This one can, per call site,
because the field it was adopted for is optional and the `ChoiceChip` row it
replaced could be tapped back to null. Swapping the widget must not quietly
change what the form permits — so `DsSegmented.onClear` is opt-in and absent by
default, and a tab-like use (§9.13's «Где ребёнок / Сегодня») stays
un-emptiable. `ds_widgets_test.dart` asserts both halves.

The reason to keep it clearable rather than "tidy up" an optional demographic
question into a required one: a mis-tap would otherwise be the only irreversible
thing on that screen, for the least consequential field on it — and a parent who
does not want to answer should not have to invent an answer to get past.
