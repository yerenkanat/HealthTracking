# There is no review seed any more, and that is deliberate

This directory used to hold `seed-reviews.json` and `apply-reviews.sh`: three
testimonials — «Айгерим, 34 · Алматы», «Мадина, 41 · Астана», «Динара, 29 ·
Шымкент» — with five-star ratings, ready to be written into
`shop_settings.reviews`.

The README that shipped beside them said, in as many words, that nobody had
shown these people exist and the stars were chosen by whoever wrote the page.
They were live on ana-bala.kz in both languages, above the fold, in the section
a mother screenshots for her sister.

Both files are gone, and the landing now carries three statements the product
can actually back — family sharing, working without a band, and full Kazakh —
instead of quotes from people who do not exist. The hero badge «Уже с 12 400
семьями Казахстана» is gone too: no query in this repository derives that
number, and nothing ever did.

## When you have real reviews

Put them in the admin panel: **Магазин → Настройки → Отзывы**. They are stored
in `shop_settings.reviews` and read by the storefront, so nothing needs a
deploy.

A real review has a person behind it who agreed to be quoted. If that is not
true of a line, it does not go on the page — a fabricated testimonial on a
health product is the fastest way to lose a market where mothers ask each other
before they buy, and it is the kind of claim a regulator reads as advertising.
