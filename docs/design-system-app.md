# Ana-Bala Mobile App — Design System

> The built app differs from this spec in a few places on purpose — the tab
> count and two label colours. They are listed in
> [DESIGN_DEVIATIONS.md](DESIGN_DEVIATIONS.md); read that before "fixing" a
> mismatch.

iOS-first, bright "neo-brutalist warm" style: cream screens, black-ink 2px outlines on every surface, hard offset shadows, saturated accent blocks. No dark theme (only the lock-screen/push view is dark), no gradients, no blur except the sticky tab bar and lock screen.

## Device & frame

- Canvas: **402 × 874** (iPhone 16 logical size), corner radius 48, Dynamic Island 126 × 37.
- Content starts at `padding-top: 62px` (under the status bar). Home-indicator area: keep 34px free at the bottom.
- Screen root: `min-height:874px; background:#FFF7F0; display:flex; flex-direction:column`, then `<div style="flex:1"></div>` before the bottom bar so content pins correctly.

## Fonts

```html
<link href="https://fonts.googleapis.com/css2?family=Unbounded:wght@500;700;800&family=Rubik:wght@500;600;700;800&family=Manrope:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500&display=swap" rel="stylesheet">
```

| Role | Family | Notes |
|---|---|---|
| Screen titles, big metrics (RU) | Unbounded 700/800 | `letter-spacing:-0.02em`, `line-height:1.05–1.12` |
| Same, Kazakh screens | Rubik 700/800 | **Unbounded lacks қ ң ә ү і ұ ө һ** — use Rubik for all Kazakh text, headings and body, or glyphs fall back mid-word |
| UI / body | Manrope 400–800 | labels & buttons 700–800 |
| Mono captions (placeholders) | JetBrains Mono 500 | 11–13px |

App type scale: screen title **21–24** · hero metric **26–46** (Unbounded/Rubik 700–800) · card title **15–19** · body **14–17** · caption **13** · micro label **11–12** uppercase `letter-spacing:.07–.08em`. Tap targets ≥ 44px.

## Colors

```
--ink        #26132E   text, ALL borders, hard shadows
--ink-2      #3A1F45   dark cards (push screen)
--cream      #FFF7F0   screen background
--coral      #FF3D71   primary CTA, active tab, alerts
--coral-deep #E8264F   destructive / link text
--yellow     #FFEA5C   highlight blocks, secondary CTA
--mint       #00C48C   success, "child in safe zone", measuring screen
--mint-deep  #0E9E6E   success text
--blue       #4C8BFF   info, second child, SpO2
--amber      #FFB020   warnings, battery, ratings

Pastel card fills: pink #FFD9E4 · mint #D6F5E7 · butter #FFEFC2 · sky #E2ECFF · lilac #EAE2FF
Map placeholder: repeating stripes #E4EEE8 / #D5E4DC
Text: #26132E primary · #4A3350 body · #8A7590 secondary · #A895B3 inactive tab / placeholder · #C0AECB chevrons
Dividers: #F0DFE7. On dark: #E4D3EC body, #CBB6D6 secondary, rgba(255,255,255,.18) hairline
```

Rule: one accent per screen dominates (coral for home, mint for measuring, pink for onboarding); pastels only as small stat cards.

## Shape & elevation

- Border `2px solid #26132E` on cards, inputs, chips, toggles, avatars, images. Dashed ink border = empty/add state.
- Radii: pills `999px` · inputs and list cards `20px` · content cards `22–26px` · icon tiles `12–16px` · avatar circles 50%.
- Shadow: hard offset only, no blur — `4px 4px 0 #26132E` on selected/primary elements. Most cards have no shadow, only the border.
- Icon tile: 38–46px, radius 12–14px, solid accent fill, white glyph (text glyph like ◎ ♥ ▶ ✿ ☺ — no custom SVG).

## Screen patterns

**Header** — `‹` chevron (24px, #8A7590) + title (Unbounded 21–24) + optional right action in `#E8264F` weight 800; step caption below in 14px/600/#8A7590.

**Tab bar** (5 tabs: Главная · Здоровье · Дети · Курс · Я / Басты · Денсаулық · Балалар · Курс · Мен)
```
position:sticky; bottom:0; background:rgba(255,247,240,.94); backdrop-filter:blur(12px);
border-top:2px solid #26132E; padding:12px 16px 34px; display:flex
```
Each tab: glyph 19px + label 11px; active `#FF3D71` weight 800, inactive `#A895B3` weight 700.

**Hero metric card** — coral fill, white text, uppercase micro label, 46px number, unit caption, plus a mini bar chart of 9 bars (`rgba(255,255,255,.55)`, current bar `#FFEA5C`), heights 34–88%.

**Stat grid** — `grid-template-columns:1fr 1fr; gap:12px`, pastel fills, micro uppercase label + 26px number + 13px caption.

**List rows** — white card radius 24px, `padding: 4px 18px`, each row `padding:15px 0` with `1px solid #F0DFE7` divider except the last; label 15/700 left, value 14–15/600 #8A7590 right.

**Segmented control** — white pill, 6px padding, active chip `#26132E` + white text, inactive `#8A7590`.

**Toggle** — 48 × 28 pill, `#00C48C` on, 20px white knob, ink borders.

**Bottom action bar** — `padding:16px 20px 34px; border-top:2px solid #26132E; background:rgba(255,247,240,.94)` with a full-width coral pill button (`box-shadow:4px 4px 0 #26132E`).

**Map view** — striped placeholder block (400–480px tall), pins = accent pill with child's name + ink border, plus a 14px dot below; filter chips (`Сейчас / История дня / Зоны`) floating at top; caption aligned to the bottom so pins never overlap it.

**Timeline (history)** — 16px accent dot + 2px `#E5D5DE` connector, event title 15/800, meta 13/600/#8A7590.

**Push / lock screen** — dark gradient `#3A1F45 → #26132E → #1A0C22`, time in Unbounded 66px, notification cards `rgba(255,255,255,.14)` + 1px `rgba(255,255,255,.18)` + radius 20 + `backdrop-filter:blur(8px)`; each has accent icon tile, `ANA-BALA` + timestamp in 12/700/#CBB6D6, title 15/800, body 14/#E4D3EC.

**Pickers** — date wheel as three columns (день/месяц/год); selected value on `#FFD9E4` chip radius 10, neighbours `#C0AECB`.

**Empty / add state** — dashed ink border, `＋` glyph, one-line explanation in 14/600/#8A7590.

## Who plays each role

Every pattern above names a *role*, not a class name. An audit in §10.14 listed
five `Ds*` widgets as "built, styled, tested and drawn by no screen" and nearly
deleted all five. The count was right and the conclusion was not: they were four
different situations. This table exists so the next audit reads it instead of
re-deriving it.

| Pattern above | What actually draws it | Status |
| --- | --- | --- |
| **Header** (line 62) | the themed `AppBar` — `theme.dart`'s `appBarTheme`, `type.screenTitle` on cream/ink, at 71 call sites | `DsScreenHeader` **deleted**. It duplicated the role and lost the system back gesture, the route's pop semantics and the status-bar inset doing it. One entry per destination applies to components. |
| **Hero metric card** (line 71) | `_MetricCard` in `dashboard/health_dashboard_screen.dart`, built from `DsCard` | `DsHeroMetric` **deleted**. It had no slot for an "as of" age. Every hero figure in this app is a vital sign; a hero number with no freshness treatment is a reading that will be trusted when it should not be, so the component could never be adopted on the only screens that wanted it. |
| **Stat grid** (line 73) | `widgets/stat_tile.dart`'s `StatTile` (~20 call sites) and the dashboard's private tile, which adds a unit slot, a verdict colour and a Kazakh scale-down | `DsStatTile` **deleted**. Three tiles for one role; the unused one went. |
| **Map view** (line 82) | the real map, injected per screen via `mapBuilder` | `DsMapPlaceholder` **kept with no production caller.** It is the test double `children_golden_test.dart` and `narrow_phone_test.dart` pass, which is what lets those screens be covered at all, and it is the honest fallback the day a tile fetch fails on 2G. Annotated in the file. |
| **Segmented control** (line 77) | `DsSegmented` | **Now used.** Onboarding step 4's «Пол» (frame 35) and the child edit sheet drew Material `ChoiceChip`s in `Palette.violet` instead — the one control the spec names by component was the one not built from the system. |

Deleting is the right move for a component with no caller **only** when another
built thing already fills the role. A spec'd pattern with no implementation at
all stays. Git has the three that went.

### What a segmented control is, and is not

Two or three mutually exclusive labels, equal width, all visible. Measured at
320dp with text at 130 %:

| | wants | gets |
| --- | --- | --- |
| «Мальчик» / «Девочка» (2 up) | 129.1 dp | 119.0 dp |
| «Ұл» / «Қыз» (2 up) | 55.3 dp | 119.0 dp |
| «Сейчас» / «История» / «Зоны» (3 up) | 129.1 dp | 73.3 dp |

So the labels scale down rather than ellipsise — a gender control reading
«Маль…» is one nobody can identify — and **four segments is not a thing this
widget does.** A variable number of options, a scrolling row, or anything
multi-select is a chip strip (the alerts filters, the device→child pick), not
this.

Note which language is tight: **Russian**, not Kazakh. Kazakh runs longer almost
everywhere else and is what the 320 dp rule is written for, but «Ұл» and «Қыз»
are the short case. A segmented control has to be measured in both.

The empty state is a state. `index` is nullable, because the first field to
adopt this is optional on a step that can be skipped entirely; a control that
required an index would open pre-answered «Мальчик», which invents a fact about
someone's child.

## Screen inventory (17)

Auth & setup: вход по номеру телефона (+7, SMS, Apple ID, WhatsApp) · код из SMS (4 ячейки) · первый запуск с выбором языка (Қазақша / Русский).
Core: главная (пульс, сон, стресс, кислород, шаги, статус ребёнка, курс) · здоровье и цикл · замер 60 секунд · дети на карте · история дня · безопасная зона (радиус, входы/выходы) · push-уведомления.
Family & data: добавить ребёнка (фото, имя, пол, дата рождения → привязка брелока к имени) · устройства и семейный доступ · профиль (RU и KZ) · отчёт для врача (PDF) · курс Ма!Ма! (уроки, прогресс, трейлер).

## Content rules

- Bilingual RU/KZ; language switch lives in Профиль and on first launch; the whole KZ subtree uses Rubik.
- Devices are bound to a named child — the name appears on the map, in the device list and in every notification.
- Currency `₸`, thin-space grouping (`25 900 ₸`). Dates in Russian long form (`14 марта 2018`), age chip beside them.
- Voice: warm, concrete, short. No emoji except the 🇰🇿 flag in the phone input. No hand-drawn SVG illustrations — real photos or striped placeholders with mono captions.
- Product facts: Watch S5 — 0.96″ TFT, 145 mAh, IP68, BT 5.3, 10 дней, 9 ремешков. Kid tag AK-08B — 32 × 8 mm, 6.1 g, CR2032, 365 дней, без SIM и подписки, зуммер.
