/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · Jewelry store
   The chains float over the counter (game side); this is the glass
   around them: the name above the chain, the tabs, buy / craft / repair.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const ST = { on: false, d: null, tab: 'buy', i: 0, letter: {}, mode: 'counter', busy: false };
const stEl = $('#store');

const money = (n) => '$' + Math.floor(n || 0).toLocaleString('en-US');
const stList = () => {
  const items = arr(ST.d && ST.d.items);
  return ST.tab === 'craft' ? items.filter((x) => x.recipe) : items;
};
const stCur = () => stList()[ST.i];
const stLetter = (it) => (it ? ST.letter[it.key] || (arr(it.variants)[0] || {}).letter : null);

function stSendView(dir) {
  const list = stList();
  if (!list.length) return post('store:view', { dir: 0 });
  const at = (k) => { const it = list[(k + list.length) % list.length]; return it ? { key: it.key, letter: stLetter(it) } : null; };
  post('store:view', {
    dir,
    prev: list.length > 1 ? at(ST.i - 1) : null,
    cur: at(ST.i),
    next: list.length > 1 ? at(ST.i + 1) : null,
  });
}

function stStep(d) {
  const n = stList().length;
  if (n < 2 || ST.busy) return;
  ST.i = (ST.i + d + n) % n;
  stSendView(d);
  stRender();
}

H['store:open'] = (d) => {
  ST.on = true; ST.d = d; ST.tab = 'buy'; ST.i = 0; ST.letter = {}; ST.mode = 'counter'; ST.busy = false;
  stEl.hidden = false;
  stRender();
  stSendView(0);
};
H['store:close'] = () => { ST.on = false; stEl.hidden = true; stEl.innerHTML = ''; };
H['store:label'] = (p) => {
  const el = $('.st-float', stEl);
  if (!el) return;
  el.style.left = `${p.x * 100}%`;
  el.style.top = `${p.y * 100}%`;
  el.classList.add('show');
};
H['store:mode'] = (d) => { ST.mode = d.mode; stRender(); };
H['store:result'] = (d) => {
  ST.busy = false;
  if (d.items) {
    const key = stCur() && stCur().key;
    ST.d.items = d.items;
    const idx = stList().findIndex((x) => x.key === key);
    ST.i = idx >= 0 ? idx : Math.min(ST.i, Math.max(0, stList().length - 1));
  }
  if (d.repairs) ST.d.repairs = d.repairs;
  if (d.wallet) ST.d.wallet = d.wallet;
  stRender();
};
H['store:working'] = (d) => {
  ST.busy = true;
  stRender();
  const bar = $('.st-work i', stEl);
  if (bar) bar.animate([{ width: '0%' }, { width: '100%' }], { duration: d.ms || 3000, easing: 'linear', fill: 'forwards' });
};

function stRender() {
  if (!ST.on) return;
  const d = ST.d, t = d.text || {}, it = stCur(), list = stList();
  const letter = stLetter(it);
  const v = it && arr(it.variants).find((x) => x.letter === letter);
  const tabs = [['buy', 'Buy', 'gem'], ...(d.craft ? [['craft', 'Craft', 'wand']] : []), ['repair', `Repair${arr(d.repairs).length ? ` · ${arr(d.repairs).length}` : ''}`, 'rotate']];
  const tryon = ST.mode === 'tryon';
  const canCraft = it && it.recipe && it.recipe.every((m) => m.have >= m.count);

  const float = it && ST.tab !== 'repair' && !tryon ? `<div class="st-float">
      ${it.exclusive ? `<span class="st-excl">${icon('user')}Made for ${esc(it.madeFor || 'you')}</span>` : ''}
      <b>${esc(it.label)}</b>
      <span>${v && v.label ? esc(v.label) + ' · ' : ''}${ST.tab === 'craft' ? 'crafted from materials' : money(it.price)}</span>
    </div>` : '';

  let bottom = '';
  if (ST.tab === 'repair') {
    const rows = arr(d.repairs);
    bottom = `<div class="st-panel scaled"><div class="ch-frame"><div class="ch-in">
      <div class="sd-ch">Repairs <em>chains that snapped in a snatch</em></div>
      ${rows.length ? rows.map((r) => `<div class="mn-row"><span class="th">${chainImg(r.image, 'gem')}</span>
          <div class="mn-rt"><b>${esc(r.label)}</b><span>broken</span></div>
          <button class="btn sm teal" data-st="repair" data-slot="${r.slot}" ${ST.busy ? 'disabled' : ''}>${icon('rotate')}${money(r.price)}</button></div>`).join('')
        : `<div class="empty">${icon('check')}Nothing to repair</div>`}
      ${ST.busy ? '<div class="st-work"><i></i></div>' : ''}
    </div></div></div>`;
  } else if (it) {
    bottom = `<div class="st-bar scaled"><div class="ch-frame"><div class="ch-in">
      <button class="st-arrow" data-st="prev" ${list.length < 2 ? 'disabled' : ''}>${icon('left')}</button>
      <div class="st-mid">
        <div class="st-count">${ST.i + 1} / ${list.length}</div>
        ${arr(it.variants).length > 1 ? `<div class="sd-tex">${arr(it.variants).map((x) => `<button class="${x.letter === letter ? 'on' : ''}" data-st="variant" data-v="${x.letter}">${esc(x.label || x.letter.toUpperCase())}</button>`).join('')}</div>` : ''}
        ${ST.tab === 'craft' ? `<div class="st-mats">${it.recipe.map((m) => `<span class="${m.have >= m.count ? 'ok' : 'no'}">${esc(m.label)} <b>${m.have}/${m.count}</b></span>`).join('')}</div>` : ''}
      </div>
      <div class="st-acts">
        <button class="btn" data-st="tryon">${icon('user')}${tryon ? 'Counter' : 'Try on'} <span class="kc">T</span></button>
        ${ST.tab === 'craft'
          ? `<button class="btn teal" data-st="craft" ${!canCraft || ST.busy ? 'disabled' : ''}>${icon('wand')}Craft <span class="kc">ENTER</span></button>`
          : `<button class="btn teal" data-st="buy" ${ST.busy || (d.wallet && d.wallet.amount < it.price) ? 'disabled' : ''}>${icon('gem')}Buy ${money(it.price)} <span class="kc">ENTER</span></button>`}
      </div>
      <button class="st-arrow" data-st="next" ${list.length < 2 ? 'disabled' : ''}>${icon('right')}</button>
      ${ST.busy ? '<div class="st-work"><i></i></div>' : ''}
    </div></div></div>`;
  } else {
    bottom = `<div class="st-bar scaled"><div class="ch-frame"><div class="ch-in"><div class="empty">${icon('gem')}${ST.tab === 'craft' ? 'Nothing can be crafted here' : 'Nothing for sale'}</div></div></div></div>`;
  }

  stEl.innerHTML = `<div class="st-drag" id="stDrag"></div>
    <div class="st-top scaled">
      <div class="st-title"><div class="mark"></div><div><b>${esc(d.title || t.store_title)}</b><span>Fine jewellery · custom pieces</span></div></div>
      <div class="seg st-tabs">${tabs.map(([k, l, ic]) => `<button class="${ST.tab === k ? 'on' : ''}" data-st="tab" data-v="${k}" ${ST.busy ? 'disabled' : ''}>${icon(ic)}${l}</button>`).join('')}</div>
      <div class="st-wallet"><span>${esc(d.wallet ? d.wallet.currency : 'Cash')}</span><b>${money(d.wallet && d.wallet.amount)}</b></div>
      <button class="pill-close" data-st="close">Leave</button>
    </div>
    ${float}${bottom}
    <div class="sd-keys scaled st-keys"><span><span class="kc">A</span><span class="kc">D</span>browse</span><span><span class="kc">DRAG</span>spin</span><span><span class="kc">T</span>try on</span><span><span class="kc">ENTER</span>${ST.tab === 'craft' ? 'craft' : 'buy'}</span><span><span class="kc">ESC</span>leave</span></div>`;
}

stEl.addEventListener('click', (e) => {
  const b = e.target.closest('[data-st]');
  if (!b || b.disabled) return;
  const it = stCur();
  switch (b.dataset.st) {
    case 'close': return post('store:close');
    case 'prev': return stStep(-1);
    case 'next': return stStep(1);
    case 'tab':
      ST.tab = b.dataset.v; ST.i = 0;
      if (ST.mode === 'tryon') post('store:mode', { mode: 'counter' });
      stRender(); return stSendView(0);
    case 'variant':
      ST.letter[it.key] = b.dataset.v;
      post('store:variant', { key: it.key, letter: b.dataset.v });
      return stRender();
    case 'tryon': return post('store:mode', { mode: ST.mode === 'tryon' ? 'counter' : 'tryon' });
    case 'buy': if (it) { ST.busy = true; stRender(); post('store:buy', { key: it.key, letter: stLetter(it) }); } return;
    case 'craft': if (it) post('store:craft', { key: it.key, letter: stLetter(it) }); return;
    case 'repair': return post('store:repair', { slot: +b.dataset.slot });
  }
});

let stDrag = null;
stEl.addEventListener('mousedown', (e) => { if (e.target.id === 'stDrag') stDrag = e.clientX; });
window.addEventListener('mousemove', (e) => {
  if (stDrag === null || !ST.on) return;
  const dx = e.clientX - stDrag;
  stDrag = e.clientX;
  if (dx) post('store:spin', { delta: dx * 0.6 });
});
window.addEventListener('mouseup', () => { stDrag = null; });
stEl.addEventListener('wheel', (e) => { if (ST.tab !== 'repair') stStep(e.deltaY > 0 ? 1 : -1); }, { passive: true });

window.addEventListener('keydown', (e) => {
  if (!ST.on) return;
  const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
  if (k === 'Escape' || k === 'Backspace') return post('store:close');
  if (ST.tab === 'repair') return;
  if (k === 'a' || k === 'ArrowLeft') return stStep(-1);
  if (k === 'd' || k === 'ArrowRight') return stStep(1);
  if (k === 't') return post('store:mode', { mode: ST.mode === 'tryon' ? 'counter' : 'tryon' });
  if (k === 'Enter') { const b = $(ST.tab === 'craft' ? '[data-st="craft"]' : '[data-st="buy"]', stEl); if (b && !b.disabled) b.click(); }
});
