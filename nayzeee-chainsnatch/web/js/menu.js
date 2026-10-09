/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · chain menu
   ═══════════════════════════════════════════════════════════ */
'use strict';

const menuEl = $('#menu');
let MN = null;

function menuRender() {
  const d = MN, t = d.text || {};
  const w = d.worn;
  const pockets = arr(d.pockets);
  const worn = w ? `
    <div class="mn-worn">
      <span class="th">${chainImg(w.image, 'gem')}</span>
      <div class="mn-wt"><small>${w.holding ? 'Holding up' : 'Wearing'}</small><b>${esc(w.label)}</b>
        <em>${esc(w.value || '')}${w.owner ? ` · made for ${esc(w.owner)}` : ''}${w.stolenFrom ? ` · snatched from ${esc(w.stolenFrom)}` : ''}</em></div>
    </div>
    <div class="mn-acts">
      <button class="mn-act red" data-act="takeoff">${icon('off')}${esc(t.take_off)}</button>
      <button class="mn-act" data-act="hold">${icon('hand')}${esc(t.hold_up)}</button>
      ${d.canPlace ? `<button class="mn-act" data-act="place">${icon('place')}${esc(t.set_down)}</button>` : ''}
    </div>
    ${d.canGive ? `<div class="mn-acts two">
      <button class="mn-act" data-act="give">${icon('gift')}${esc(t.give)}</button>
      <button class="mn-act" data-act="puton">${icon('user')}${esc(t.put_on_them)}</button>
      <button class="mn-act" data-act="swap">${icon('rotate')}${esc(t.swap)}</button>
    </div>` : ''}` : `<div class="card empty">${icon('gem')}${esc(t.no_chain)}</div>`;

  const list = pockets.length ? pockets.map((p) => `
    <div class="mn-row">
      <span class="th">${chainImg(p.image, 'gem')}</span>
      <div class="mn-rt"><b>${esc(p.label)}${p.broken ? '<span class="mn-broken">BROKEN</span>' : ''}</b><span>${esc(p.broken ? 'repair it at the jewelry store' : t.in_pockets)}</span></div>
      ${d.canGive ? `<button class="btn sm ghost" data-act="giveSlot" data-slot="${p.slot}" title="${esc(t.give)}">${icon('gift')}</button>` : ''}
      ${d.canPlace ? `<button class="btn sm ghost" data-act="placeSlot" data-slot="${p.slot}" data-key="${esc(p.key)}" data-variant="${esc(p.variant)}" title="${esc(t.set_down)}">${icon('place')}</button>` : ''}
      <button class="btn sm teal" data-act="wear" data-slot="${p.slot}" ${p.broken ? 'disabled' : ''}>${esc(t.put_on)}</button>
    </div>`).join('') : '';

  menuEl.innerHTML = `<div class="mn-frame scaled"><div class="mn-edge"><div class="mn-shell">
    <div class="mn-bar"><div class="mark"></div><div class="mn-title"><b>${esc(t.menu_title || 'Chain')}</b><span>${w ? esc(w.label) : esc(t.no_chain)}</span></div>
      <button class="pill-close" data-act="close">Close</button></div>
    <div class="mn-body">${worn}
      ${pockets.length ? `<div class="mn-h">${esc(t.in_pockets)}<em>${pockets.length}</em></div><div class="mn-list">${list}</div>` : ''}
    </div>
    <div class="mn-status"><span><span class="kc">ESC</span>Close</span>${w ? '<span><span class="kc">G</span>Throw while holding</span>' : ''}</div>
  </div></div></div>`;
  menuEl.hidden = false;
}

H['menu:open'] = (d) => { MN = d; menuRender(); };
H['menu:close'] = () => { MN = null; menuEl.hidden = true; menuEl.innerHTML = ''; };

menuEl.addEventListener('click', (e) => {
  const b = e.target.closest('[data-act]');
  if (!b) {
    if (e.target === menuEl) post('menu:close');
    return;
  }
  const act = b.dataset.act;
  if (act === 'close') return post('menu:close');
  post('menu:action', { act, slot: b.dataset.slot ? +b.dataset.slot : undefined, key: b.dataset.key, variant: b.dataset.variant });
});

window.addEventListener('keydown', (e) => {
  if (!MN) return;
  if (e.key === 'Escape' || e.key === 'Backspace') post('menu:close');
});
