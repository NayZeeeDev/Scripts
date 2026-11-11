/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V2 · the Style Book
   Every salon style as a card (its look on your server's hair),
   the steps, what it needs, the hair packs to use, a price, Start.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const Book = { open: false, d: null, tab: 'all', sel: null, opts: {}, hair: null, extra: null, price: 0, need: null, q: '' };
const bk = { root: $('#skBook') };

const bkImg = (name) => `<img src="../INSTALL/images/${esc(name)}.png" alt="" onerror="if(!this.dataset.f){this.dataset.f=1;this.src='https://cfx-nui-ox_inventory/web/images/${esc(name)}.png'}else{this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-box'}))}">`;
const CAT_ICON = { braids: 'fa-bars-staggered', box: 'fa-table-cells', cornrows: 'fa-grip-lines', twists: 'fa-rotate', weaves: 'fa-reply' };

function bookOpen(d) {
  Object.assign(Book, { open: true, d, list: null, tab: 'all', opts: {}, hair: null, extra: null, price: 0, need: null, q: '' });
  const styles = bookStyles();
  Book.sel = (styles.find((s) => s.look && !s.locked) || styles[0] || {}).id || null;
  bk.root.hidden = false;
  document.body.classList.add('book-open');
  bookRender();
  bookNeeds();
}

function bookClose(silent) {
  if (!Book.open) return;
  Book.open = false;
  bk.root.hidden = true;
  document.body.classList.remove('book-open');
  if (!silent) post('salonBookClose');
}

// the static style list merged with what the server said about each one (look on this model, locked)
function bookStyles() {
  if (Book.list) return Book.list;
  const live = {};
  arr(Book.d.live).forEach((s) => { live[s.id] = s; });
  Book.list = arr(Book.d.styles).map((s) => Object.assign({}, s, live[s.id] || {}));
  return Book.list;
}
const bookStyle = (id) => bookStyles().find((s) => s.id === id);
const shadeOf = (id) => arr(Book.d.shades).find((s) => s.id === id);
const label = (item) => (Book.d.labels || {})[item] || item;
const have = (item) => (Book.d.have || {})[item] || 0;

function swatch(sh, big) {
  if (!sh) return `<i class="bk-sw${big ? ' big' : ''} nat"></i>`;
  const bg = sh.tip ? `linear-gradient(180deg,${sh.game} 30%,${sh.tip})` : sh.game || sh.rgb;
  return `<i class="bk-sw${big ? ' big' : ''}" style="background:${bg}"></i>`;
}

async function bookNeeds() {
  const s = bookStyle(Book.sel);
  if (!s) return;
  const opts = Object.assign({}, Book.opts);
  const r = await post('salonNeeds', { style: s.id, opts });
  if (Book.sel !== s.id) return;
  Book.need = r || null;
  // pick a pack group by default: the first with enough
  const pick = (h, cur) => {
    if (!h) return null;
    const groups = arr((Book.d.packs || {})[h.item]);
    if (cur && groups.some((g) => g.key === cur)) return cur;
    const g = groups.find((x) => x.count >= h.n) || groups[0];
    return g ? g.key : null;
  };
  Book.hair = pick(r && r.hair, Book.hair);
  Book.extra = pick(r && r.extra, Book.extra);
  bookRender();
}

function blockers(s) {
  const out = [];
  const t = Book.d.target;
  if (!t) out.push('Look at someone to do their hair');
  else if (t.wig) out.push(`${t.name} has a wig on`);
  if (s.locked) out.push(`Needs stylist level ${s.level}`);
  if (t && !s.look) out.push(`No look for ${t.model === 'm' ? 'male' : 'female'} hair yet (admins: /wigstudio)`);
  const n = Book.need;
  if (n) {
    const miss = arr(n.tools).concat(arr(n.uses)).filter((it) => have(it) < 1);
    if (miss.length) out.push(`Missing ${miss.map(label).join(', ')}`);
    for (const h of [n.hair, n.extra]) {
      if (!h) continue;
      const g = arr((Book.d.packs || {})[h.item]).find((x) => x.key === (h === n.hair ? Book.hair : Book.extra));
      if (!g || g.count < h.n) out.push(`Needs ${h.n} × ${label(h.item)} of one colour`);
    }
  }
  return out;
}

function bookRender() {
  const d = Book.d, styles = bookStyles();
  const cats = arr(d.cats).filter((c) => styles.some((s) => s.cat === c.id));
  const tabs = [{ id: 'all', label: 'All', icon: 'fa-border-all' }].concat(cats.map((c) => ({ id: c.id, label: c.label, icon: CAT_ICON[c.id] || 'fa-scissors' })));
  const list = styles.filter((s) => (Book.tab === 'all' || s.cat === Book.tab) && (!Book.q || s.label.toLowerCase().includes(Book.q.toLowerCase())));
  const t = d.target;
  $('#bkSub').textContent = t ? `Doing ${t.name}'s hair · stylist level ${d.level}` : `Browsing · stylist level ${d.level}`;
  $('#bkTabs').innerHTML = tabs.map((x) => `<button class="${x.id === Book.tab ? 'on' : ''}" data-bk="tab" data-v="${esc(x.id)}"><i class="fa-solid ${x.icon}"></i>${esc(x.label)}</button>`).join('')
    + `<label class="bk-search"><i class="fa-solid fa-magnifying-glass"></i><input id="bkQ" placeholder="Search styles" value="${esc(Book.q)}"></label>`;
  $('#bkGrid').innerHTML = list.map((s) => {
    const img = s.img ? `<img src="${esc(s.img)}" alt="" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid ${CAT_ICON[s.cat] || 'fa-scissors'}'}))">` : `<i class="fa-solid ${CAT_ICON[s.cat] || 'fa-scissors'}"></i>`;
    const badge = s.locked ? `<span class="bk-lock"><i class="fa-solid fa-lock"></i>Level ${s.level}</span>` : (t && !s.look) ? '<span class="bk-nolook">No look</span>' : '';
    return `<button class="bk-card ${s.id === Book.sel ? 'on' : ''} ${s.locked ? 'locked' : ''}" data-bk="pick" data-v="${esc(s.id)}">
      ${badge}<span class="bk-cimg">${img}</span>
      <b>${esc(s.label)}</b>
      <small>${s.hair ? (s.hair.ext ? 'Natural or extensions' : `${s.hair.n} × ${esc(label(s.hair.item))}`) : 'Natural hair'} · ${s.days} day${s.days === 1 ? '' : 's'}</small>
    </button>`;
  }).join('') || '<div class="bk-nores">Nothing matches</div>';
  bookDetail();
}

function bookDetail() {
  const s = bookStyle(Book.sel), el = $('#bkDetail');
  if (!s) { el.innerHTML = ''; return; }
  const n = Book.need || {};
  const d = Book.d;
  const stepRows = arr(s.steps).map((st, i) => {
    const off = st.opt && !(st.opt === 'ext' ? Book.opts.ext : Book.opts[st.opt]);
    return `${st.phase ? `<div class="bk-phase">${esc(st.phase)}</div>` : ''}<div class="bk-st ${off ? 'off' : ''}"><span>${i + 1}</span><p>${esc(st.text)}</p></div>`;
  }).join('');
  const optRows = [];
  if (s.hair && s.hair.ext) optRows.push(`<div class="bk-seg"><button class="${!Book.opts.ext ? 'on' : ''}" data-bk="ext" data-v="0">Natural hair</button><button class="${Book.opts.ext ? 'on' : ''}" data-bk="ext" data-v="1">With ${esc(label(s.hair.item))}</button></div>`);
  for (const [k, txt] of Object.entries(s.options || {})) {
    optRows.push(`<label class="bk-check"><input type="checkbox" data-bk="opt" data-v="${esc(k)}" ${Book.opts[k] ? 'checked' : ''}><span>${esc(txt)}</span></label>`);
  }
  const packRows = (h, cur, which) => {
    if (!h) return '';
    const groups = arr((d.packs || {})[h.item]);
    const rows = groups.map((g) => {
      const sh = shadeOf(g.shade);
      const ok = g.count >= h.n;
      return `<button class="bk-pack ${g.key === cur ? 'on' : ''} ${ok ? '' : 'short'}" data-bk="${which}" data-v="${esc(g.key)}">${swatch(sh)}
        <span><b>${esc(sh ? sh.label : (g.key === 'any' ? label(h.item) : g.shade))}</b><small>${[g.length ? g.length + '"' : '', g.texture || ''].filter(Boolean).join(' · ') || '&nbsp;'}</small></span>
        <em class="${ok ? 'ok' : 'bad'}">${g.count} / ${h.n}</em></button>`;
    }).join('');
    return `<div class="bk-sec"><div class="bk-hd">${esc(label(h.item))} <em>${h.n} pack${h.n === 1 ? '' : 's'} of one colour</em></div>
      ${rows || `<div class="bk-none"><i class="fa-solid fa-store"></i>None on you. The Hair Supply sells it in every colour and length.</div>`}</div>`;
  };
  const need = arr(n.tools).map((it) => ({ it, tool: true })).concat(arr(n.uses).map((it) => ({ it })));
  const needRows = need.map(({ it, tool }) => `<div class="bk-need ${have(it) > 0 ? 'ok' : 'bad'}"><span class="bk-ni">${bkImg(it)}</span><span>${esc(label(it))}<small>${tool ? 'tool, kept' : 'used up'}</small></span><i class="fa-solid ${have(it) > 0 ? 'fa-check' : 'fa-xmark'}"></i></div>`).join('');
  const blocks = blockers(s);
  el.innerHTML = `
    <div class="bk-dh">
      <div><small>${esc((arr(d.cats).find((c) => c.id === s.cat) || {}).label || '')}</small><h3>${esc(s.label)}</h3></div>
      <div class="bk-facts"><span><i class="fa-regular fa-clock"></i>~${n.minutes || '?'} min</span><span><i class="fa-solid fa-list-ol"></i>${n.moves || '?'} moves</span><span><i class="fa-regular fa-calendar"></i>${s.days} day${s.days === 1 ? '' : 's'}</span><span class="${s.locked ? 'bad' : ''}"><i class="fa-solid fa-signal"></i>Lv ${s.level}</span></div>
      <p>${esc(s.desc || '')}</p>
    </div>
    <div class="bk-scroll">
      ${optRows.length ? `<div class="bk-sec"><div class="bk-hd">Options</div>${optRows.join('')}</div>` : ''}
      ${packRows(n.hair, Book.hair, 'hair')}
      ${packRows(n.extra, Book.extra, 'extra')}
      ${needRows ? `<div class="bk-sec"><div class="bk-hd">You need <em>${need.filter(({ it }) => have(it) > 0).length} / ${need.length}</em></div><div class="bk-needs">${needRows}</div></div>` : ''}
      <div class="bk-sec"><div class="bk-hd">Steps</div>${stepRows}</div>
    </div>
    <div class="bk-foot">
      ${d.target ? `<div class="bk-price"><span>Price</span><div class="stepper"><button data-bk="price" data-v="-50"><i class="fa-solid fa-minus"></i></button><input id="bkPrice" value="${Book.price}" inputmode="numeric"><button data-bk="price" data-v="50"><i class="fa-solid fa-plus"></i></button></div><small>${Book.price > 0 ? `paid from their ${esc(d.account || 'cash')} when it's done` : 'free'}</small></div>` : ''}
      ${blocks.length ? `<div class="note err">${esc(blocks[0])}</div>` : ''}
      <button class="btn-teal wide" data-bk="start" ${blocks.length ? 'disabled' : ''}><i class="fa-solid fa-wand-magic-sparkles"></i>${d.target ? `Start on ${esc(d.target.name)}` : 'Pick someone first'}</button>
    </div>`;
}

bk.root.addEventListener('click', (e) => {
  const b = e.target.closest('[data-bk]');
  if (!b) { if (e.target.closest('#bkClose')) bookClose(); return; }
  const v = b.dataset.v;
  switch (b.dataset.bk) {
    case 'tab': Book.tab = v; return bookRender();
    case 'pick': if (Book.sel !== v) { Book.sel = v; Book.opts = {}; Book.hair = null; Book.extra = null; Book.need = null; bookRender(); bookNeeds(); } return;
    case 'ext': Book.opts.ext = v === '1'; bookRender(); return bookNeeds();
    case 'hair': Book.hair = v; return bookDetail();
    case 'extra': Book.extra = v; return bookDetail();
    case 'price': Book.price = clamp((Number(Book.price) || 0) + Number(v), 0, Book.d.maxPrice || 5000); return bookDetail();
    case 'start': {
      const s = bookStyle(Book.sel);
      if (!s || b.disabled || !Book.d.target) return;
      post('salonStart', { target: Book.d.target.id, style: s.id, opts: Book.opts, hair: Book.hair, extra: Book.extra, price: Book.price });
      return bookClose(true);
    }
  }
});
bk.root.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset && t.dataset.bk === 'opt') { Book.opts[t.dataset.v] = t.checked; bookRender(); bookNeeds(); }
  if (t.id === 'bkPrice') { Book.price = clamp(Math.floor(Number(t.value) || 0), 0, Book.d.maxPrice || 5000); bookDetail(); }
});
bk.root.addEventListener('input', (e) => {
  if (e.target.id === 'bkQ') { Book.q = e.target.value; const pos = e.target.selectionStart; bookRender(); const q = $('#bkQ'); q.focus(); q.setSelectionRange(pos, pos); }
});

function bookKey(e) {
  if (!Book.open) return false;
  if (e.type === 'keydown' && e.key === 'Escape') { bookClose(); return true; }
  return e.target && (e.target.tagName === 'INPUT');
}
