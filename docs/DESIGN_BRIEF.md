# Ana-Bala — design brief

*Paste the whole of this into Claude and ask for the design. It describes the
product, who uses it, and every screen that exists today.*

---

## 1. What this is

**Ana-Bala** ("mother–child" in Kazakh) is a mobile app for **Kazakhstan**. It
follows a woman from trying to conceive, through pregnancy, birth and the
postpartum weeks, and on into her child's first five years — and it keeps her
child physically safe with a GPS tracker.

It is sold **with hardware**:

| Product | Price | What it is |
|---|---|---|
| Часы / band | 24 900 ₸ | A wristband the **mother** wears — heart rate, blood pressure (PPG), sleep stages, steps |
| Брелок / tracker | ~4 900 ₸ | A keyfob **tag on the child** — GPS location, safe-zone alerts, SOS button |
| **Комплект «Мама и ребёнок»** | **39 000 ₸** | Both devices **plus the Ма!Ма! video course** (the course is the entire reason the bundle costs more than the two devices) |

Ordering is **cash on delivery via WhatsApp** and Kaspi (the Kazakh payment
app). There is no card checkout.

## 2. Who is holding the phone

Design for **her**, not for a dashboard user:

- A woman aged roughly 20–40 in Almaty, Astana, Shymkent or a smaller town.
- She reads **Russian or Kazakh**. English exists but is third.
- She is often **one-handed** — a baby on the other arm — and often **at 3am**
  in a dark room next to someone asleep.
- Her phone is frequently a **cheap Android**: assume **360 dp wide**, not an
  iPhone. Assume the system font may be scaled to **130%**.
- She may be anxious. Nothing should feel clinical, alarming, or like a
  hospital chart. Warm, calm, reassuring — but never cute to the point of
  being untrustworthy, because some of this is genuinely medical.

## 3. Current visual language (keep or improve — say which)

- **Neo-brutalist warm**: cream/blush background, **2 px black borders**, hard
  black drop-shadows on cards, generous rounded corners (12–20 px).
- Palette: warm cream background, **crimson/rose** primary (`#E8114B`-ish),
  soft pink fills, mint green and violet accents, near-black ink for text.
- Chunky, friendly headline type; high contrast; big tap targets (**48 dp
  minimum**, always).
- Only the **Rubik** font family covers the Kazakh alphabet (ә, ғ, қ, ң, ө, ұ,
  ү, һ, і) — any typeface you propose must support Cyrillic **and** these.
- Cards, not tables. Sparklines, not grids.

## 4. Structure — four tabs

### Tab 1 · Здоровье (Health) — *the mother's own body*
- Today's vitals from the band: heart rate, blood pressure, SpO₂, steps,
  sleep. Sparkline history per metric, with a detail screen each.
- **Manual entry** for everyone without a band — vitals, sleep, weight — with
  camera scan of a tonometer/glucometer display.
- **Blood-pressure calibration**: she enters a cuff reading, the app learns the
  offset from the band's optical estimate.
- Water tracker, weight tracker with a goal.
- **Daily audio** — a short calming clip per day.
- **AI assistant chat** — she can ask questions in her own language.
- **Setup checklist** — a progress nudge (sign in → name → health mode → child
  → safe zone → details → backup).

### Tab 2 · Календарь (Calendar) — *three calendars behind one switch*
She picks the mode; all three are always reachable.
1. **Cycle** — month grid, period logging, predicted period and fertile
   window with a confidence chip, phase card, symptoms usually logged in this
   phase, cycle insights and history.
2. **Pregnancy** — week-by-week hero (baby size, weekly highlight), antenatal
   visit plan, warning signs, pregnancy weight curve, **kick counter**,
   **contraction timer**, hospital-bag checklist, labour signs, week detail
   content.
3. **Child development** — what the baby can do at this month.

Shared across all three: **day log** (mood, symptoms, flow, kicks, free-text
note), **appointments/reminders**, **medications with adherence tracking**,
notes browser, **postpartum recovery** screen after birth.

### Tab 3 · Ребёнок (Child) — *safety and the baby's health*
- **Live map** of the child with the tracker, last-seen freshness badge.
- **Safe zones** (circles and polygons drawn on a map) with enter/leave alerts.
- **Safety alert feed** including **SOS**.
- **Growth** — weight/height over time against percentile curves.
- **Newborn log** — feeds, nappies, sleep.
- **Vaccination schedule** — the Kazakh national immunisation calendar, with
  what is due now and what was missed.
- **Emergency medical ID** — blood type, allergies, conditions, doctor's phone.
- **Cry insight** — records a cry and classifies it (hungry / tired / pain…)
  with a confidence percentage.
- Illness, teething, solids, safe sleep and home-safety guides.
- Device pairing over Bluetooth.

### Tab 4 · Профиль (Profile) — *account and everything else*
- Avatar, name, phone.
- Counts of children and devices.
- Reminders.
- **Курс Ма!Ма!** — the video course. Shows "watched 2 of 12" and one button
  that continues the lesson she was in the middle of. Lessons play **inside the
  app** in YouTube's embedded player, remember her position, and tick when
  finished. Someone who has not bought the комплект sees an offer instead.
- **Settings**: sign-in, children, devices, notifications and quiet hours,
  BP calibration, backup/export, language, legal, help.

### Plus
- **Onboarding** — 5 steps: consent → language → name + phone + "expecting?" →
  child → device.
- **Sign-in**: phone number → **6-digit SMS code**.
- **Emergency rescue screen**.

## 5. Beyond the app (same brand)
- **Landing page** at ana-bala.kz — sells the комплект.
- **Storefront** `/shop` — product pages, WhatsApp/Kaspi ordering.
- **Admin back office** — orders, stock ledger, customers, content CMS,
  course lessons, analytics dashboard. Staff-facing, dense, different rules.

## 6. What I want from you

Design the **mobile app**. Please cover:

1. A refreshed **visual system** — colour, type scale, spacing, elevation,
   iconography, component library (cards, rows, chips, buttons, sheets,
   empty states, badges).
2. **Key screens redrawn**: Health dashboard, the three calendars, the child
   map, the course, Profile, Settings.
3. **States, not just the happy path** — loading, empty, error, offline, and
   "she has no device yet" (a large share of users will never own the band).
4. How it holds together at **360 dp** and at **130% font scale**.
5. **Dark mode**, if you think it earns its place at 3am.

### Constraints, please respect them
- Russian, Kazakh and English must all fit. **Kazakh strings run ~20% longer
  than Russian** — a layout that only fits Russian is broken.
- Text contrast must pass **WCAG AA (4.5:1)**. The current crimson on cream
  fails at small sizes; fix it rather than keeping it.
- **One-handed reach**: a primary or repeated action belongs at the *bottom*.
- Never alarming. Amber before red. This app tells people about miscarriage
  warning signs and a missing child — the tone has to hold under that weight.
- It must not look like a fitness tracker or a hospital EMR.
