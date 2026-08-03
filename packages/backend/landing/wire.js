// Send the landing page's callback form to the backend.
//
// The landing is an exported artifact: its own submit handler only flips a bit
// of React state and paints "Заявка принята ✓". Nothing leaves the browser — a
// visitor who trusts that message is never called back. This file is the other
// half, kept OUTSIDE the artifact so re-exporting the landing (which regenerates
// index.html and everything in landing/a/) does not wipe it.
//
// It listens in the CAPTURE phase at the document, so it runs before React's
// own handler and survives every re-render — React replaces DOM nodes, not
// document-level listeners.
//
// Rebuild the landing with: node packages/backend/tools/build-landing.mjs
(function () {
  'use strict';

  // The page ships two copies of the form, one per language (Russian and
  // Kazakh), and renders one at a time. Whichever submits, we read it the same
  // way — by shape, not by id, since the artifact's markup carries no names.
  function readForm(form) {
    var inputs = form.querySelectorAll('input');
    var select = form.querySelector('select');
    if (inputs.length < 2) return null; // not the callback form
    // The package <option>s carry no value attribute, so .value IS the label the
    // visitor read ("Комплект «Мама и ребёнок» — 25 900 ₸").
    return {
      customerName: (inputs[0].value || '').trim(),
      phone: (inputs[1].value || '').trim(),
      package: select ? (select.value || '').trim() : '',
    };
  }

  // The language toggle persists to localStorage under this key (see the
  // artifact's own component). Staff call back in the language the visitor read.
  function currentLocale() {
    try {
      var l = localStorage.getItem('anabala-landing-lang');
      return l === 'kz' ? 'kz' : 'ru';
    } catch (e) {
      return 'ru';
    }
  }

  var MSG = {
    ru: {
      missing: 'Укажите имя и номер телефона',
      failed: 'Не удалось отправить. Напишите нам в WhatsApp — ответим сразу.',
    },
    kz: {
      missing: 'Атыңыз бен телефон нөміріңізді жазыңыз',
      failed: 'Жіберу мүмкін болмады. WhatsApp арқылы жазыңыз — бірден жауап береміз.',
    },
  };

  // The artifact's own handler paints success unconditionally. When the POST
  // fails we say so directly under the button, so nobody walks away believing
  // they are in the queue when they are not.
  function notice(form, text) {
    var el = form.querySelector('[data-lead-status]');
    if (!el) {
      el = document.createElement('div');
      el.setAttribute('data-lead-status', '');
      el.style.cssText =
        'font-size:14px;font-weight:700;line-height:1.4;text-align:center;' +
        'color:#8A1B3D;background:#FFD9E4;border-radius:12px;padding:10px 12px';
      form.appendChild(el);
    }
    el.textContent = text;
  }

  function clearNotice(form) {
    var el = form.querySelector('[data-lead-status]');
    if (el) el.remove();
  }

  // ---- The WhatsApp number ------------------------------------------------
  //
  // The artifact hardcodes one number into six wa.me links. `shop_settings` has
  // a `whatsapp` key that staff edit in the admin panel and that /shop/config
  // exposes — but nothing was reading it, so changing the number there moved
  // nothing and the page kept dialling whatever was current the day it was
  // exported.
  //
  // The hardcoded number stays as the fallback: if the setting is blank (as it
  // is today) or the request fails, the links are left exactly as authored.
  var waNumber = null; // digits, once /shop/config has answered

  /**
   * Point every wa.me link at the configured number.
   *
   * Must be idempotent and repeatable, NOT a one-shot: React rebuilds these
   * anchors from the template on every re-render — opening an FAQ row or
   * switching language is enough — and each rebuild restores the number baked
   * into the export. Rewriting once looked right in a screenshot and reverted
   * the moment anyone touched the page.
   *
   * Setting .href is itself a DOM mutation, so the "already correct" check is
   * what stops the observer below from re-entering forever.
   */
  function rewriteWaLinks() {
    if (!waNumber) return;
    var links = document.querySelectorAll('a[href*="wa.me/"]');
    for (var i = 0; i < links.length; i++) {
      // Swap only the number, keeping each link's own ?text= greeting — the
      // Russian and Kazakh sections pre-fill different messages.
      var next = links[i].href.replace(/wa\.me\/\d+/, 'wa.me/' + waNumber);
      if (next !== links[i].href) links[i].href = next;
    }
  }

  fetch('/shop/config')
    .then(function (r) {
      return r.ok ? r.json() : null;
    })
    .then(function (cfg) {
      var digits = cfg && typeof cfg.whatsapp === 'string' ? cfg.whatsapp.replace(/\D/g, '') : '';
      // Unset (the current state) or too short to dial: leave the authored
      // links exactly as they are rather than breaking them.
      if (digits.length < 8) return;
      waNumber = digits;
      rewriteWaLinks();
    })
    .catch(function () {
      /* offline or 500 — the authored number still works */
    });

  new MutationObserver(rewriteWaLinks).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });

  // Last line of defence for the click itself, in case a render lands between
  // the observer firing and the tap being delivered.
  document.addEventListener(
    'click',
    function (ev) {
      if (!waNumber || !ev.target || !ev.target.closest) return;
      var a = ev.target.closest('a[href*="wa.me/"]');
      if (a) a.href = a.href.replace(/wa\.me\/\d+/, 'wa.me/' + waNumber);
    },
    true,
  );

  document.addEventListener(
    'submit',
    function (ev) {
      var form = ev.target;
      if (!form || form.tagName !== 'FORM') return;
      var lead = readForm(form);
      if (!lead) return;

      var locale = currentLocale();
      var msg = MSG[locale];

      // Let React paint its own confirmation for a valid submission only; an
      // empty form must not read as accepted.
      if (!lead.customerName || lead.phone.replace(/\D/g, '').length < 5) {
        ev.preventDefault();
        ev.stopPropagation();
        notice(form, msg.missing);
        return;
      }
      clearNotice(form);

      lead.locale = locale;
      // Same-origin: the landing is served by the backend that owns this route,
      // which is why the storefront lives here rather than on a static host.
      fetch('/shop/leads', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(lead),
      })
        .then(function (res) {
          if (!res.ok) throw new Error('http ' + res.status);
        })
        .catch(function () {
          notice(form, msg.failed);
        });
    },
    true,
  );
})();
