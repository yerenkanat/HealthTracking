/**
 * Full layout audit of the REAL admin panel, in real Chrome.
 *
 * jsdom has no layout engine, so every existing panel test is blind to
 * overflow — which is why a screenshot caught what 2000 tests did not. This
 * builds a self-contained copy of packages/admin/index.html with fetch stubbed
 * (so it boots without a server) plus a measuring pass, and reports every
 * element wider than its container at each width.
 *
 * Usage: node ui-audit.js <panel.html> <out.html>
 */
const fs = require('fs');

const [, , panelPath, outPath] = process.argv;
let html = fs.readFileSync(panelPath, 'utf8');

// Everything the panel asks for on the way in. Shapes copied from the jsdom
// suites so the panel renders a populated screen rather than empty states —
// empty tables do not overflow, and would make this audit lie by passing.
const STUB = `<script>
(function(){
  const ORDERS = Array.from({length:8},(_,i)=>({
    id:'ord-'+i, customerName:'Мадина Ержанова', phone:'+7 701 000 00 0'+i,
    city:'Астана', address:'проспект Мангилик Ел 55, кв. 120', status:'new',
    totalMinor:3900000, discountMinor:0, createdAt:'2026-08-01T10:00:00Z',
    items:[{productName:'Смарт-часы Ana-Bala',color:'Розовое золото',qty:1}]
  }));
  const VARIANTS = [
    {id:'w-black',label:'Смарт-часы Ana-Bala · Чёрный',stock:12},
    {id:'w-gold',label:'Смарт-часы Ana-Bala · Розовое золото',stock:3},
    {id:'w-lilac',label:'Смарт-часы Ana-Bala · Сиреневый',stock:0},
    {id:'t-teal',label:'Детский трекер Ana-Bala · Бирюзовый',stock:7},
    {id:'t-blue',label:'Детский трекер Ana-Bala · Синий',stock:21},
    {id:'t-pink',label:'Детский трекер Ana-Bala · Розовый',stock:5}
  ];
  const USERS = Array.from({length:12},(_,i)=>({
    id:'u'+i, displayName:'Айгерим Досжанова', phone:'+7 707 345 22 4'+i,
    dueDate:'2026-11-14', lastMetricAt:'2026-08-12T09:41:00Z', latestSeverity:'warning'
  }));
  const J = (b)=>({ok:true,status:200,json:async()=>b,text:async()=>JSON.stringify(b)});
  window.fetch = async (p)=>{
    p = String(p);
    if(p.includes('/admin/me')) return J({staffId:'s1',role:'owner',displayName:'Ерен'});
    if(p.includes('/admin/stats')) return J({activeUsers:1284,devicesOnline:1071,alertsToday:3,ingestLastHour:9420,alertsConfigured:true});
    if(p.includes('/admin/shop/orders')) return J({orders:ORDERS,total:284,counts:{new:14,confirmed:9,shipped:4,delivered:250,cancelled:7},limit:25,offset:0});
    if(p.includes('/admin/shop/leads')) return J({leads:[{id:'l1',customerName:'Гүлнара Сейтқали',phone:'+7 705 900 77 31',package:'Комплект',locale:'kz',status:'new',createdAt:'2026-08-01T10:00:00Z'}]});
    if(p.includes('/admin/shop/variants')) return J({variants:VARIANTS});
    if(p.includes('/admin/shop/products')) return J({products:[],categories:[]});
    if(p.includes('/admin/users')) return J({users:USERS,total:1284});
    if(p.includes('/admin/inventory')) return J({items:VARIANTS.map(v=>({...v,sku:'AB-'+v.id,daysOfCover:4})),moves:[],windowDays:30,leadTimeDays:12});
    if(p.includes('/admin/emergencies')) return J({emergencies:[]});
    if(p.includes('/admin/devices')) return J({devices:[],metrics:{}});
    return J({});
  };
})();
</script>`;

// Before the panel's own scripts.
html = html.replace(/<script/i, STUB + '\n<script');

// The measuring pass, appended so it runs last.
html += `
<script>
window.__audit = async function(){
  const vw = document.documentElement.clientWidth;
  // An element inside a horizontally scrollable box is NOT overflowing the
  // page — it is doing exactly what the scroll container is for. A table of
  // eight order columns has a floor and is allowed to scroll inside its card.
  // Without this the audit reports its own design decision back as a defect.
  const inScroller = (el) => {
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const ox = getComputedStyle(p).overflowX;
      if (ox === 'auto' || ox === 'scroll') return true;
    }
    return false;
  };

  const out = [];
  const seen = new Set();
  for (const el of document.querySelectorAll('#appShell *')) {
    if (!el.getClientRects().length) continue;          // not painted
    const r = el.getBoundingClientRect();
    if (r.width === 0) continue;
    if (inScroller(el)) continue;
    const over = Math.round(r.right - vw);
    if (over > 1) {
      // Report the OUTERMOST offender only; its children spill because it does.
      let p = el.parentElement, covered = false;
      while (p) { if (seen.has(p)) { covered = true; break; } p = p.parentElement; }
      if (covered) continue;
      seen.add(el);
      const id = el.id ? '#' + el.id : '';
      const cls = el.className && typeof el.className === 'string'
        ? '.' + el.className.trim().split(/\\s+/).slice(0,2).join('.') : '';
      out.push('OVERFLOW ' + over + 'px  <' + el.tagName.toLowerCase() + id + cls + '>  "'
        + (el.textContent||'').replace(/\\s+/g,' ').trim().slice(0,40) + '"');
    }
  }
  // WHEN THE PAGE SCROLLS BUT NOTHING IS REPORTED.
  //
  // The loop above skips anything inside a horizontal scroller, which is right:
  // a wide table inside its own overflow-x:auto card is a design decision,
  // not a defect. But it means that when the DOCUMENT scrolls, the audit knows
  // it and cannot say why — which is exactly the state «PAGE SCROLLS: 932 > 900»
  // left a reader in. (No backticks in this comment: it lives inside a template
  // literal, and one would close it — the same fault that once took the whole
  // panel script down.)
  //
  // So: name the three widest right-edges regardless of scroller, as a
  // diagnostic rather than a verdict. It answers "what should I look at",
  // which is the only question worth asking once the page is already known to
  // scroll.
  if (document.documentElement.scrollWidth > vw + 1) {
    const widest = [];
    // body, not #appShell: the page can be pushed wide by something OUTSIDE the
    // shell — a toast, a dialog, a fixed bar — and scanning only the shell is
    // how this reported a scrolling page with no cause.
    for (const el of document.querySelectorAll('body *')) {
      if (!el.getClientRects().length) continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.right <= vw + 1) continue;
      // A position:fixed element cannot create document scroll, however far off
      // screen it sits. The closed drawer is translateX(100%) by design and was
      // the loudest thing here — a false lead that would have sent someone to
      // fix correct code.
      if (getComputedStyle(el).position === 'fixed') continue;
      const id = el.id ? '#' + el.id : '';
      const cls = el.className && typeof el.className === 'string'
        ? '.' + el.className.trim().split(/\\s+/).slice(0,2).join('.') : '';
      widest.push({ over: Math.round(r.right - vw), scroller: inScroller(el),
        what: '<' + el.tagName.toLowerCase() + id + cls + '> "'
          + (el.textContent||'').replace(/\\s+/g,' ').trim().slice(0,36) + '"' });
    }
    widest.sort((a,b) => b.over - a.over);
    for (const w of widest.slice(0,3)) {
      out.push('WIDEST +' + w.over + 'px' + (w.scroller ? ' (in a scroller)' : '') + '  ' + w.what);
    }
  }

  // Controls a person must reach: are they inside the viewport?
  const unreachable = [];
  for (const el of document.querySelectorAll('#appShell input, #appShell select, #appShell button, #appShell textarea')) {
    if (!el.getClientRects().length) continue;
    const r = el.getBoundingClientRect();
    if (r.right > vw + 1 && !inScroller(el)) {
      unreachable.push((el.id ? '#'+el.id : el.tagName.toLowerCase()) + ' cut by ' + Math.round(r.right - vw) + 'px');
    }
  }
  // Content flush against a card's edge — the thing that reads as "cut off".
  // .card carries no padding of its own, so every child must supply 18px and
  // the ones that forget touch the border.
  const flush = [];
  for (const card of document.querySelectorAll('#appShell .card')) {
    if (!card.getClientRects().length) continue;
    const cr = card.getBoundingClientRect();
    for (const kid of card.children) {
      if (!kid.getClientRects().length) continue;
      const kr = kid.getBoundingClientRect();
      // The CONTENT edge, not the box edge: .sec-h sits flush as a box and
      // pads its own text by 18px, which is correct. What reads as "cut off"
      // is text whose own padding is zero.
      const pl = parseFloat(getComputedStyle(kid).paddingLeft) || 0;
      const gap = Math.round(kr.left + pl - cr.left);
      const text = (kid.textContent || '').replace(/\\s+/g, ' ').trim();
      if (!text) continue;                       // spacers and empty slots
      if (gap <= 4) {
        const id = kid.id ? '#' + kid.id : '';
        const cls = kid.className && typeof kid.className === 'string'
          ? '.' + kid.className.trim().split(/\\s+/)[0] : '';
        flush.push('FLUSH ' + gap + 'px  <' + kid.tagName.toLowerCase() + id + cls
          + '>  in ' + (card.id ? '#' + card.id : '.card') + '  "' + text.slice(0, 36) + '"');
      }
    }
  }
  return { page: document.documentElement.scrollWidth > vw
      ? 'PAGE SCROLLS: ' + document.documentElement.scrollWidth + ' > ' + vw : 'page ok',
    overflow: out, unreachable, flush };
};
</script>`;

fs.writeFileSync(outPath, html);
console.log('wrote ' + outPath + ' (' + html.length + ' bytes)');
