# Adding lessons and products to the timeline

The app shows video lessons and shop products matched to where a family is:
a **week of pregnancy** (1–40) or a **month of the child's life** (0–60, birth
to five years). Week 20 shows week 20's material; a four-month-old shows
month 4's.

All of that content lives in **one file** — no code change is needed to publish
it.

```
app/assets/content/catalog.json
```

## Adding content

1. **Edit `app/assets/content/catalog.json`.** It already contains every stage
   with placeholder text, so you are filling in rather than starting blank.
2. **Check it** before committing:
   ```
   cd app && dart run tool/verify_content_catalog.dart
   ```
3. Rebuild the app. The new content appears immediately.

If that file is ever missing or unreadable, the app falls back to the seeded
demo catalogue rather than showing nothing. That is a safety net, not the
check — the validator is the check.

To regenerate the template from scratch (it refuses to overwrite existing work
unless you pass `--force`):

```
cd app && dart run tool/export_catalog_template.dart
```

## The shape

Keys are stages: `w1`…`w40` for pregnancy weeks, `m0`…`m60` for child months
(`m0` is a newborn). Each holds a list of items.

```json
{
  "w20": [
    {
      "id": "w20-nutrition",
      "kind": "lesson",
      "title":   { "ru": "Питание на 20-й неделе", "kk": "20-аптадағы тамақтану", "en": "Nutrition at week 20" },
      "summary": { "ru": "Что важно есть сейчас.", "kk": "Қазір не жеу маңызды.", "en": "What matters to eat now." },
      "url": "https://youtu.be/XXXXXXXXXXX",
      "durationMin": 6
    },
    {
      "id": "w20-cream",
      "kind": "product",
      "title":   { "ru": "Крем от растяжек", "kk": "Созылу іздеріне қарсы крем", "en": "Stretch-mark cream" },
      "summary": { "ru": "Подобрано для 20-й недели.", "kk": "20-аптаға таңдалған.", "en": "Chosen for week 20." },
      "url": "https://shop.example.kz/cream",
      "priceMinor": 990000,
      "currency": "KZT"
    }
  ]
}
```

| Field | Applies to | Notes |
|---|---|---|
| `id` | both | **Must be unique across the whole file.** Two items sharing an id break list rendering and merge in analytics. |
| `kind` | both | `lesson` or `product`. |
| `title` / `summary` | both | Per locale: `ru`, `kk`, `en`. A missing language falls back to Russian, then English — so a partly translated item still shows. |
| `url` | both | Where the video plays or the product is bought. Must be `http(s)`. **Leave it out and the item shows as "Скоро"** rather than offering a dead button. |
| `priceMinor` | products | **In tiyn, not tenge** — `990000` is 9 900 ₸. Integer on purpose: money in floating point drifts. |
| `currency` | products | `KZT`, `USD`, `RUB`. |
| `durationMin` | lessons | Shown as a chip. |

## What the validator catches

`dart run tool/verify_content_catalog.dart` fails the build on:

- a **stage key the app cannot resolve** (`w41`, `m61`, a typo) — content under
  one of those is dropped on load and would simply never appear
- **duplicate ids**
- **missing Russian text** (the default language)
- **a product with no usable price**, or one priced under 100 ₸ — almost always
  tenge typed where tiyn was meant
- **a lesson carrying a price**
- **a link that is not http(s)**

It *reports without failing*: stages with no content yet, and fields not yet
translated. Publishing week by week is a normal way to work, and neither should
block a commit.

## Notes

- **Pregnancy takes precedence** over a child's age. Someone expecting sees this
  week's material even if an older child is also tracked.
- **After five years the timeline ends.** Repeating month 60 forever would be
  worse than showing nothing.
- **Products link out.** There is no in-app payment, so a product opens its page
  in the browser.
- Order matters: items appear in the order you list them, and the dashboard card
  previews the first few (lessons first, then a product) before offering
  "Смотреть все".
