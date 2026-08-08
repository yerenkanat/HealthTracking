/**
 * `/join/<token>` — where an invitation link lands.
 *
 * Screen 40 hands the mother a link to send to the father. Until this existed
 * the link went to a 404: the whole feature was built and the one thing a
 * relative actually touches did nothing.
 *
 * WHAT THIS PAGE DOES NOT DO. It does not accept the invitation. Accepting
 * requires knowing who is accepting, and the person opening this link in a
 * browser is not signed in to anything — a page that "accepted" would either
 * have to invent an account or accept on behalf of nobody. So it does the
 * honest thing: it shows the code, says what to do with it, and gets out of
 * the way.
 *
 * It also does not confirm that the code is valid. Checking would tell anyone
 * who guessed a token whether it existed, and the answer is worth nothing to
 * the person holding a real one — they are about to find out in the app, where
 * the refusal can be specific and where they are signed in.
 *
 * Russian and Kazakh only. Nobody reaches this page except by tapping a link
 * sent by a mother in Kazakhstan.
 */

import type { FastifyInstance } from 'fastify';

/** Tokens are base64url from randomBytes(32). Anything else is not one. */
const TOKEN = /^[A-Za-z0-9_-]{16,200}$/;

export function joinPageHtml(token: string): string {
  // Escaped even though the pattern above admits only base64url characters:
  // the guard and the escaping protect against different mistakes, and the
  // one that survives a careless edit to the other is the one worth keeping.
  const safe = token.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Приглашение · Ana-Bala</title>
<style>
  :root{--ink:#241A22;--cream:#FBF6F3;--coral:#D6004A;--dim:#6B5F66;--mint:#0E7A54}
  *{box-sizing:border-box}
  body{margin:0;background:var(--cream);color:var(--ink);
    font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
    padding:28px 20px;display:flex;justify-content:center}
  main{max-width:460px;width:100%}
  h1{font-size:24px;line-height:1.25;margin:0 0 10px}
  p{margin:0 0 16px;color:var(--dim)}
  .code{background:#fff;border-radius:16px;padding:16px;margin:22px 0;
    font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:14px;
    word-break:break-all;user-select:all;-webkit-user-select:all}
  ol{margin:0 0 22px;padding-left:22px}
  li{margin-bottom:8px}
  .note{background:#E4F5EC;color:var(--mint);border-radius:16px;padding:16px;
    font-size:14px}
  .kk{margin-top:28px;padding-top:22px;border-top:1px solid #E6DCD8}
  button{font:inherit;font-weight:600;background:var(--coral);color:#fff;
    border:0;border-radius:14px;padding:14px 18px;width:100%;min-height:48px;
    cursor:pointer}
</style>
</head>
<body>
<main>
  <h1>Вас пригласили следить за ребёнком</h1>
  <p>Чтобы принять приглашение, откройте приложение Ana-Bala на своём телефоне
     и введите этот код.</p>

  <div class="code" id="code">${safe}</div>
  <button type="button" id="copy">Скопировать код</button>

  <ol style="margin-top:22px">
    <li>Откройте приложение Ana-Bala и войдите по своему номеру.</li>
    <li>Профиль → Семейный доступ → «У меня есть приглашение».</li>
    <li>Вставьте код.</li>
  </ol>

  <p class="note">Вы увидите только ребёнка: карту, зоны и события.
     Здоровье, цикл и дневник мамы остаются закрытыми.</p>

  <div class="kk">
    <h1>Сізді баланы бақылауға шақырды</h1>
    <p>Қабылдау үшін телефоныңызда Ana-Bala қолданбасын ашып, осы кодты
       енгізіңіз: Профиль → Отбасылық қолжетімділік → «Менде шақыру бар».</p>
    <p class="note">Сіз тек баланы көресіз: карта, аймақтар және оқиғалар.
       Ананың денсаулығы мен күнделігі жабық болып қалады.</p>
  </div>
</main>
<script>
  document.getElementById('copy').addEventListener('click', function () {
    var t = document.getElementById('code').textContent;
    var done = function () { this.textContent = 'Код скопирован'; }.bind(this);
    if (navigator.clipboard) navigator.clipboard.writeText(t).then(done, function(){});
    else {
      // Older Android browsers. A select-all fallback beats a button that
      // silently does nothing on the phone half the recipients are holding.
      var r = document.createRange();
      r.selectNodeContents(document.getElementById('code'));
      var s = getSelection(); s.removeAllRanges(); s.addRange(r);
      done();
    }
  });
</script>
</body>
</html>`;
}

export function registerJoinPage(app: FastifyInstance): void {
  app.get('/join/:token', async (req, reply) => {
    const { token } = req.params as { token: string };
    if (!TOKEN.test(token)) {
      // A shape that is not a token gets the page's own 404 rather than the
      // API's JSON one — whoever is here opened a link in a browser.
      return reply.code(404).type('text/html').send(
        '<!doctype html><meta charset="utf-8"><title>Ana-Bala</title>' +
        '<p style="font:16px system-ui;padding:24px">Ссылка не подходит. ' +
        'Попросите новую — приглашения живут сутки.</p>');
    }
    return reply
      .type('text/html')
      // The code is in the URL. Caching it on a shared phone, or letting a
      // proxy keep a copy, is how a spent link ends up somewhere it should
      // not be.
      .header('cache-control', 'no-store')
      .send(joinPageHtml(token));
  });
}
