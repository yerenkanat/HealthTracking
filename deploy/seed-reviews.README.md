# deploy/seed-reviews.json

The three testimonials **already printed on the landing page**, lifted verbatim
out of the exported artifact and put into `shop_settings.reviews` so they become
editable in the admin panel (Магазин → Настройки → Отзывы).

Applying this changes nothing a visitor sees. That is the point: it moves copy
that was frozen inside the export into a field staff can edit, without altering
the live page in the process.

## These are not verified customer quotes

They came with the design. Nobody has shown that Айгерим, Мадина or Динара
exist, and the star ratings were chosen by whoever wrote the page. Treat them as
placeholder marketing copy and replace them with real reviews when you have
them — the admin panel is now the place to do that.

## Applying it

    ./deploy/apply-reviews.sh            # on the server; loopback only

Or paste the file's contents into the Отзывы box in the admin panel and save.

## Shape

    [{ "name", "city", "text", "stars", "city_kz"?, "text_kz"? }]

`text_kz` / `city_kz` are optional and are shown to visitors reading the page in
Kazakh. Without them a Kazakh visitor sees the Russian text, so a review with no
`text_kz` is a downgrade from the authored page, which localised both. `name`
has no `_kz` form and falls back.

Leaving the setting empty — or saving something that is not valid JSON — leaves
the authored testimonials on the page rather than blanking the section.
