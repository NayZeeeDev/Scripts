/* 14 · TAILOR
   SendNUIMessage({ action = 'open', data = {
     mode  = 'store',                 -- 'store' | 'barber' | 'creator'  (creator hides prices)
     title = 'Suburban', sub = 'Rockford Hills',          -- optional, defaults by mode
     price = { torso = 85, legs = 60, shoes = 45, hair = 40, face = 0 },   -- cost per changed category
     categories = { {
       id = 'torso', label = 'Torso', icon = 'shirt',
       drawable = 12, drawables = 140,   -- 0-based index, total count
       texture  = 2,  textures  = 8,
       min = 0,                          -- optional, -1 for props (hat / glasses) so "off" is allowed
       cam = 'body',                     -- optional camera view when this tab opens: face | body | feet
     } },
     hair = { style = 12, styles = 74, color = 3, highlight = 0, colors = { '#1c1611', '#2b1f17', ... } },
     face = { {id = 'nose_width', label = 'Nose width', value = 0.0} },     -- values -1..1
   } })
   SendNUIMessage({ action = 'close' })

   Callbacks (every change posts immediately so Lua can apply it live):
     change  { category, drawable, texture }   → optionally return { textures = n } for the new drawable
     hair    { style, color, highlight }
     face    { id, value }
     camera  { view }                          -- 'face' | 'body' | 'feet'
     rotate  { dir }                           -- 'left' | 'right'
     save    { name }                          -- save current outfit to the wardrobe
     confirm { total }                         → return { ok = true } or { ok = false, error = '...' }
     cancel                                    -- revert to the original look
     close                                     -- always sent after confirm / cancel so Lua can release focus
*/
NZ.addIcons({
  tank: '<path d="M8.5 3v3.5a3.5 3.5 0 0 0 7 0V3M8.5 3 6 4v6l1 1v10h10V11l1-1V4l-2.5-1"/>',
  pants: '<path d="M6 3h12l1 18h-5l-2-11-2 11H5L6 3z"/><path d="M6 6.5h12"/>',
  glove: '<path d="M7 21v-6L4.5 11.5a1.5 1.5 0 0 1 2.4-1.8L8.5 12V5a1.5 1.5 0 0 1 3 0v5V4a1.5 1.5 0 0 1 3 0v6V5.5a1.5 1.5 0 0 1 3 0V16l-1 5H7z"/>',
  backpack: '<path d="M6 9a6 6 0 0 1 12 0v10.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19.5V9z"/><path d="M9.5 3.5h5M9 14h6v4H9z"/>',
  chain: '<path d="M5 4c0 6 3 10 7 10s7-4 7-10"/><path d="M12 14v2.5"/><path d="m12 16.5 2.5 2.5-2.5 2.5-2.5-2.5 2.5-2.5z"/>',
  scissors: '<circle cx="6.5" cy="17.5" r="2.8"/><circle cx="17.5" cy="17.5" r="2.8"/><path d="M8.5 15.5 18 4M15.5 15.5 6 4"/>',
  hanger: '<path d="M12 8.5a2 2 0 1 0-2-2"/><path d="M12 8.5v1L3 16a1 1 0 0 0 .6 1.8h16.8A1 1 0 0 0 21 16l-9-6.5"/>',
  'rot-l': '<path d="M4 12a8 8 0 1 0 2.3-5.7M4 5v5h5"/>',
  'rot-r': '<path d="M20 12a8 8 0 1 1-2.3-5.7M20 5v5h-5"/>',
  face: '<path d="M12 3c-4 0-6.5 3-6.5 7.5 0 5.5 3 10.5 6.5 10.5s6.5-5 6.5-10.5C18.5 6 16 3 12 3z"/><path d="M9.5 10v.5M14.5 10v.5M10 16c1.2.8 2.8.8 4 0"/>',
});

const app = NZ.$('#app');
const MODES = { store: ['Clothing store', 'Store'], barber: ['Barber shop', 'Barber'], creator: ['Character creator', 'Creator'] };
const CAM = { hat: 'face', mask: 'face', glasses: 'face', ears: 'face', hair: 'face', face: 'face', shoes: 'feet', feet: 'feet' };

let d = null;            // open payload
let sections = [];       // [{ kind:'cloth'|'hair'|'face', id, label, icon, ref }]
let at = 0;              // active section index
let init = {};           // original values per section id
let view = 'body';
let busy = false;

const isFree = () => d.mode === 'creator' || !Object.values(d.price || {}).some(v => v > 0);
const priceOf = id => (d.price && d.price[id]) || 0;
const pad = n => String(n).padStart(2, '0');

function changed(s) {
  const o = init[s.id];
  if (s.kind === 'cloth') return s.ref.drawable !== o.drawable || s.ref.texture !== o.texture;
  if (s.kind === 'hair') return s.ref.style !== o.style || s.ref.color !== o.color || s.ref.highlight !== o.highlight;
  return s.ref.some(f => Math.abs((f.value || 0) - (o[f.id] || 0)) > 0.001);
}
const total = () => sections.filter(changed).reduce((a, s) => a + priceOf(s.id), 0);

/* ── rail ── */
function renderRail() {
  NZ.$('#rail').innerHTML = sections.map((s, i) =>
    (s.kind !== 'cloth' && i > 0 && sections[i - 1].kind === 'cloth' ? '<span class="rail-sep"></span>' : '') +
    `<button class="rb ${i === at ? 'on' : ''}" data-i="${i}" title="${NZ.esc(s.label)}">${NZ.icon(s.icon)}<span>${NZ.esc(s.label)}</span>${changed(s) ? '<i class="chg"></i>' : ''}</button>`
  ).join('');
  NZ.$$('.rb').forEach(b => b.onclick = () => go(+b.dataset.i));
}

/* ── main column ── */
function head(s, canReset) {
  return `<div class="sec-head"><div><div class="idx">${pad(at + 1)} / ${pad(sections.length)}</div><h1>${NZ.esc(s.label)}</h1></div>
    <button class="nz-btn line sm" id="reset" ${canReset ? '' : 'disabled'}>${NZ.icon('refresh')}Reset</button></div>
    <div class="sec-sub" id="sec-sub">${subText(s)}</div>`;
}
function subText(s) {
  const p = priceOf(s.id);
  return !isFree() && p ? `<span>Changing this costs <b>${NZ.money(p)}</b></span>` : `<span>${changed(s) ? 'Changed from your original look' : 'Original look'}</span>`;
}

function stepper(key, label, value, count, min, right) {
  const span = Math.max(1, count - 1 - min);
  const v = ((value - min) / span) * 100;
  return `<div class="stp" data-k="${key}">
    <div class="stp-top"><span>${label}</span><span>${right || ''}</span></div>
    <div class="stp-row">
      <button class="arr" data-d="-1">${NZ.icon('chev-l')}</button>
      <div class="val">${value < 0 ? '<span class="none">Off</span>' : `<input type="text" inputmode="numeric" value="${value}" data-in="${key}"><span class="of">/ ${count}</span>`}</div>
      <button class="arr" data-d="1">${NZ.icon('chev-r')}</button>
    </div>
    <div class="track" style="--v:${Math.max(0, Math.min(100, v))}%"><i></i><b></b></div>
    ${key === 'texture' && count > 1 && count <= 26 ? `<div class="pips">${Array.from({ length: count }, (_, k) => `<button class="pip ${k === value ? 'on' : ''}" data-t="${k}">${k}</button>`).join('')}</div>` : ''}
  </div>`;
}

function sheet() {
  const rows = sections.filter(s => s.kind === 'cloth');
  if (!rows.length) return '';
  return `<div class="sheet"><div class="sheet-h">Outfit sheet</div>${rows.map(s => {
    const i = sections.indexOf(s), c = changed(s);
    return `<button class="sh-row ${c ? 'chg' : ''} ${i === at ? 'on' : ''}" data-i="${i}">${NZ.icon(s.icon)}<span>${NZ.esc(s.label)}</span>
      <span class="v">${s.ref.drawable < 0 ? 'Off' : s.ref.drawable}<i>·</i>${s.ref.texture}</span>
      <span class="c">${c ? (!isFree() && priceOf(s.id) ? NZ.money(priceOf(s.id)) : 'Changed') : '—'}</span></button>`;
  }).join('')}</div>`;
}

function swatches(key, label, value, colors) {
  return `<div class="sw-block"><div class="sw-label"><span>${label}</span><b><i style="background:${NZ.esc(colors[value] || '#000')}"></i>${value + 1} / ${colors.length}</b></div>
    <div class="sws">${colors.map((c, k) => `<button class="sw ${k === value ? 'on' : ''}" style="--c:${NZ.esc(c)}" data-${key}="${k}" title="${k + 1}"></button>`).join('')}</div></div>`;
}

function renderMain() {
  const s = sections[at], m = NZ.$('#main');
  if (!s) { m.innerHTML = `<div class="nz-empty">${NZ.icon('hanger')}<b>Nothing to edit</b></div>`; return; }
  const keep = m.dataset.sec === s.id ? m.scrollTop : 0;
  m.classList.toggle('face', s.kind === 'face');
  m.dataset.sec = s.id;
  if (s.kind === 'cloth') {
    const c = s.ref, min = c.min != null ? c.min : 0, o = init[s.id];
    m.innerHTML = head(s, changed(s)) +
      stepper('drawable', 'Drawable', c.drawable, c.drawables, min, c.drawable !== o.drawable ? `<em>was ${o.drawable < 0 ? 'off' : o.drawable}</em>` : '') +
      (c.drawable < 0 ? '' : stepper('texture', 'Texture', c.texture, c.textures || 1, 0, c.texture !== o.texture ? `<em>was ${o.texture}</em>` : '')) +
      sheet();
  } else if (s.kind === 'hair') {
    const h = s.ref, colors = h.colors || [];
    m.innerHTML = head(s, changed(s)) +
      stepper('style', 'Style', h.style, h.styles || 1, 0, h.style !== init.hair.style ? `<em>was ${init.hair.style}</em>` : '') +
      (colors.length ? swatches('color', 'Colour', h.color, colors) + swatches('highlight', 'Highlight', h.highlight, colors) : '');
  } else {
    m.innerHTML = head(s, changed(s)) + s.ref.map(f => `<div class="sl" data-f="${NZ.esc(f.id)}">
      <div class="sl-top"><span>${NZ.esc(f.label)}</span><b></b></div>
      <div class="rng"><input type="range" min="-1" max="1" step="0.01" value="${+f.value || 0}"></div></div>`).join('');
    NZ.$$('.sl', m).forEach(paintSlider);
  }
  m.scrollTop = keep;
  wire(s);
}

function paintSlider(el) {
  const inp = el.querySelector('input'), v = +inp.value, p = (v + 1) * 50;
  const a = Math.min(50, p), b = Math.max(50, p);
  inp.style.setProperty('--fill', `linear-gradient(90deg,var(--raise) ${a}%,var(--teal) ${a}%,var(--teal) ${b}%,var(--raise) ${b}%)`);
  const lb = el.querySelector('.sl-top b');
  lb.textContent = (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(v).toFixed(2);
  lb.classList.toggle('zero', v === 0);
}

function wire(s) {
  const m = NZ.$('#main');
  NZ.$$('.stp', m).forEach(st => {
    const k = st.dataset.k;
    NZ.$$('.arr', st).forEach(b => b.onclick = () => step(k, +b.dataset.d));
    const inp = NZ.$('input', st);
    if (inp) {
      inp.onfocus = () => inp.select();
      inp.onkeydown = e => { if (e.key === 'Enter') inp.blur(); };
      inp.onchange = () => { const n = parseInt(inp.value, 10); if (!isNaN(n)) setVal(k, n); else renderMain(); };
    }
  });
  NZ.$$('.pip', m).forEach(b => b.onclick = () => setVal('texture', +b.dataset.t));
  NZ.$$('[data-color]', m).forEach(b => b.onclick = () => setVal('color', +b.dataset.color));
  NZ.$$('[data-highlight]', m).forEach(b => b.onclick = () => setVal('highlight', +b.dataset.highlight));
  NZ.$$('.sh-row', m).forEach(b => b.onclick = () => go(+b.dataset.i));
  NZ.$$('.sl', m).forEach(el => {
    const inp = el.querySelector('input'), f = s.ref.find(x => x.id === el.dataset.f);
    inp.oninput = () => {
      f.value = Math.round(+inp.value * 100) / 100;
      paintSlider(el);
      NZ.post('face', { id: f.id, value: f.value });
      refreshMeta();
    };
    inp.ondblclick = () => { inp.value = 0; inp.oninput(); };
  });
  const r = NZ.$('#reset');
  if (r) r.onclick = () => reset(s);
}

/* ── changes ── */
const wrap = (v, min, count) => { const n = count - min; return ((v - min) % n + n) % n + min; };

function step(k, dir) {
  const s = sections[at];
  if (s.kind === 'cloth') {
    const c = s.ref;
    if (k === 'drawable') setVal(k, wrap(c.drawable + dir, c.min != null ? c.min : 0, c.drawables));
    else if (c.drawable >= 0) setVal(k, wrap(c.texture + dir, 0, c.textures || 1));
  } else if (s.kind === 'hair') {
    const h = s.ref, n = (h.colors || []).length || 1;
    if (k === 'style') setVal(k, wrap(h.style + dir, 0, h.styles || 1));
    else setVal(k, wrap(h[k] + dir, 0, n));
  }
}

async function setVal(k, n) {
  const s = sections[at];
  if (s.kind === 'cloth') {
    const c = s.ref, min = c.min != null ? c.min : 0;
    if (k === 'drawable') {
      n = Math.max(min, Math.min(c.drawables - 1, n));
      if (n === c.drawable) return renderMain();
      c.drawable = n; c.texture = 0;
      if (!NZ.inGame) c.textures = fakeTextures(s.id, n);
    } else c.texture = Math.max(0, Math.min((c.textures || 1) - 1, n));
    refresh();
    const res = await NZ.post('change', { category: c.id, drawable: c.drawable, texture: c.texture });
    if (res && res.textures != null && res.textures !== c.textures) { c.textures = res.textures; if (sections[at] === s) renderMain(); }
  } else if (s.kind === 'hair') {
    const h = s.ref;
    if (k === 'style') h.style = Math.max(0, Math.min((h.styles || 1) - 1, n));
    else h[k] = Math.max(0, Math.min((h.colors || []).length - 1, n));
    refresh();
    NZ.post('hair', { style: h.style, color: h.color, highlight: h.highlight });
  }
}

function reset(s) {
  const o = init[s.id];
  if (s.kind === 'cloth') {
    Object.assign(s.ref, { drawable: o.drawable, texture: o.texture, textures: o.textures });
    NZ.post('change', { category: s.id, drawable: o.drawable, texture: o.texture });
  } else if (s.kind === 'hair') {
    Object.assign(s.ref, o);
    NZ.post('hair', { style: o.style, color: o.color, highlight: o.highlight });
  } else {
    s.ref.forEach(f => { if (f.value !== o[f.id]) { f.value = o[f.id]; NZ.post('face', { id: f.id, value: f.value }); } });
  }
  refresh();
}

function refresh() { renderMain(); refreshMeta(); }
function refreshMeta() {
  renderRail(); renderTally();
  const r = NZ.$('#reset'); if (r) r.disabled = !changed(sections[at]);
  const sub = NZ.$('#sec-sub'); if (sub) sub.innerHTML = subText(sections[at]);
}

function renderTally() {
  const t = total();
  const conf = NZ.$('#confirm');
  if (isFree()) { NZ.$('#tally').innerHTML = ''; conf.textContent = d.mode === 'creator' ? 'Confirm look' : 'Confirm'; return; }
  const lines = sections.filter(s => changed(s) && priceOf(s.id));
  NZ.$('#tally').innerHTML = `<div class="tl-lines">${lines.length ? lines.map(s => `<span class="nz-chip white">${NZ.esc(s.label)} ${NZ.money(priceOf(s.id))}</span>`).join('') : '<span class="none">No paid changes yet — browse freely, you only pay for what you keep.</span>'}</div>
    <div class="tl-tot"><span>${lines.length} change${lines.length === 1 ? '' : 's'} · total</span><b>${NZ.money(t)}</b></div>`;
  conf.textContent = t ? `Pay ${NZ.money(t)}` : 'Confirm';
}

/* ── navigation / camera ── */
function go(i) {
  if (!sections.length) return;
  at = (i + sections.length) % sections.length;
  renderRail(); renderMain();
  const on = NZ.$('.rb.on'); if (on) on.scrollIntoView({ block: 'nearest' });
  const s = sections[at];
  setView(s.ref && s.ref.cam ? s.ref.cam : CAM[s.id] || 'body');
}
function setView(v) {
  if (v === view) return;
  view = v;
  NZ.$$('#views button').forEach(b => b.classList.toggle('on', b.dataset.v === v));
  NZ.post('camera', { view: v });
}
function rotate(dir) {
  NZ.post('rotate', { dir });
  const b = NZ.$(`.rot[data-r="${dir}"]`);
  b.classList.add('hot'); clearTimeout(b._t); b._t = setTimeout(() => b.classList.remove('hot'), 160);
}
NZ.$$('#views button').forEach(b => b.onclick = () => setView(b.dataset.v));
NZ.$$('.rot').forEach(b => b.onclick = () => rotate(b.dataset.r));

/* ── footer actions ── */
function flash(text, ok) {
  const m = NZ.$('#msg');
  m.className = `t-msg ${ok ? 'ok' : 'err'}`;
  m.innerHTML = NZ.icon(ok ? 'check' : 'error') + NZ.esc(text);
  clearTimeout(m._t); m._t = setTimeout(() => { m.innerHTML = ''; }, 3500);
}
const saveBox = NZ.$('#save');
function saveOpen(on) {
  saveBox.classList.toggle('on', on);
  if (on) { NZ.$('#save-name').value = ''; NZ.$('#save-name').focus(); }
}
function saveGo() {
  const n = NZ.$('#save-name').value.trim();
  if (!n) { NZ.$('#save-name').focus(); return; }
  NZ.post('save', { name: n });
  saveOpen(false);
  flash(`Saved “${n}” to your wardrobe`, true);
}
NZ.$('#save-open').onclick = () => saveOpen(true);
NZ.$('#save-back').onclick = () => saveOpen(false);
NZ.$('#save-go').onclick = saveGo;
NZ.$('#save-name').onkeydown = e => { if (e.key === 'Enter') saveGo(); };

function doCancel() {
  NZ.post('cancel');
  NZ.close(app);
}
async function doConfirm() {
  if (busy) return;
  busy = true;
  const t = isFree() ? 0 : total();
  const res = await NZ.post('confirm', { total: t });
  busy = false;
  if (res && res.ok === false) { flash(res.error || 'Could not confirm', false); return; }
  NZ.close(app);
}
NZ.$('#cancel').onclick = doCancel;
NZ.$('#confirm').onclick = doConfirm;

window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const ae = document.activeElement;
  const typing = ae && ae.tagName === 'INPUT' && ae.type !== 'range';
  if (e.key === 'Escape') {
    if (saveBox.classList.contains('on')) saveOpen(false);
    else if (typing) ae.blur();
    else doCancel();
    return;
  }
  if (typing || saveBox.classList.contains('on')) return;
  const k = e.key.toLowerCase();
  if (k === 'q' || k === 'e') { rotate(k === 'q' ? 'left' : 'right'); return; }
  if (ae && ae.type === 'range' && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) return; // native slider keys
  const s = sections[at];
  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') { e.preventDefault(); go(at + (e.key === 'ArrowDown' ? 1 : -1)); }
  else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
    e.preventDefault();
    const dir = e.key === 'ArrowRight' ? 1 : -1;
    if (s.kind === 'cloth') step(e.shiftKey ? 'texture' : 'drawable', dir);
    else if (s.kind === 'hair') step(e.shiftKey ? 'color' : 'style', dir);
  }
});

/* ── open ── */
function openTailor(data) {
  d = data || {};
  d.mode = MODES[d.mode] ? d.mode : 'store';
  sections = (d.categories || []).map(c => ({ kind: 'cloth', id: c.id, label: c.label, icon: c.icon || 'shirt', ref: c }));
  if (d.hair) sections.push({ kind: 'hair', id: 'hair', label: 'Hair', icon: 'scissors', ref: d.hair });
  if (d.face && d.face.length) sections.push({ kind: 'face', id: 'face', label: 'Face', icon: 'face', ref: d.face });
  init = {};
  sections.forEach(s => {
    if (s.kind === 'cloth') init[s.id] = { drawable: s.ref.drawable, texture: s.ref.texture, textures: s.ref.textures };
    else if (s.kind === 'hair') init.hair = { style: s.ref.style, color: s.ref.color, highlight: s.ref.highlight };
    else init.face = Object.fromEntries(s.ref.map(f => [f.id, f.value || 0]));
  });
  const [title, tag] = MODES[d.mode];
  NZ.$('#title').textContent = d.title || title;
  NZ.$('#sub').textContent = d.sub || (d.mode === 'creator' ? 'Free while you create' : '');
  NZ.$('#mode').textContent = tag;
  NZ.$('#save-open').style.display = d.mode === 'barber' ? 'none' : '';
  NZ.$('#msg').innerHTML = '';
  saveOpen(false);
  view = 'body';
  NZ.$$('#views button').forEach(b => b.classList.toggle('on', b.dataset.v === view));
  NZ.$('#main').dataset.sec = '';
  at = d.mode === 'barber' ? Math.max(0, sections.findIndex(s => s.kind === 'hair')) : 0;
  renderRail(); renderMain(); renderTally();
  NZ.open(app);
}
NZ.on('open', openTailor);
NZ.on('close', () => NZ.close(app, { notify: false }));

/* preview: texture counts vary per drawable like real GTA components */
function fakeTextures(id, n) { let h = 0; for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) % 997; return 1 + ((n * 7 + h) % 12); }

NZ.preview(() => {
  const hairColors = ['#0e0b09', '#1c1611', '#2b1f17', '#3b2a1e', '#4a3423', '#5a3f2a', '#6b4b31', '#7c5838', '#8c6643', '#9e7650', '#b0875e',
    '#c29a6e', '#d4b083', '#e0c59c', '#ead7b6', '#f3e7d0', '#3a2a24', '#5b2e22', '#7a3322', '#943a24', '#b04528', '#c9562f', '#dc6a3a', '#e88a52',
    '#5e5e5e', '#7d7d7d', '#9e9e9e', '#c2c2c2', '#e0e0e0', '#3d2a52', '#5b3a82', '#7e4fb6', '#1d3b6b', '#2559a8', '#3a86d9', '#0f5c55',
    '#08afa2', '#2f8f3a', '#6aa936', '#c9c43a', '#e5a50a', '#d9612c', '#b02a2a', '#e5484d', '#c23a7a', '#e46aa6'];
  openTailor({
    mode: 'store', title: 'Suburban', sub: 'Rockford Hills · Portola Dr',
    price: { hat: 35, mask: 60, glasses: 45, torso: 120, undershirt: 40, arms: 25, legs: 85, shoes: 70, bag: 55, accessories: 90, hair: 40 },
    categories: [
      { id: 'hat', label: 'Hat', icon: 'hat', drawable: -1, drawables: 152, texture: 0, textures: 1, min: -1 },
      { id: 'mask', label: 'Mask', icon: 'mask', drawable: 0, drawables: 196, texture: 0, textures: 1 },
      { id: 'glasses', label: 'Glasses', icon: 'glasses', drawable: 5, drawables: 46, texture: 2, textures: 9, min: -1 },
      { id: 'torso', label: 'Torso', icon: 'shirt', drawable: 12, drawables: 140, texture: 2, textures: 8 },
      { id: 'undershirt', label: 'Undershirt', icon: 'tank', drawable: 15, drawables: 188, texture: 0, textures: 4 },
      { id: 'arms', label: 'Arms', icon: 'glove', drawable: 4, drawables: 196, texture: 0, textures: 1 },
      { id: 'legs', label: 'Legs', icon: 'pants', drawable: 24, drawables: 142, texture: 5, textures: 11 },
      { id: 'shoes', label: 'Shoes', icon: 'shoe', drawable: 10, drawables: 98, texture: 0, textures: 6 },
      { id: 'bag', label: 'Bag', icon: 'backpack', drawable: 0, drawables: 88, texture: 0, textures: 1 },
      { id: 'accessories', label: 'Accessories', icon: 'chain', drawable: 0, drawables: 152, texture: 0, textures: 1 },
    ],
    hair: { style: 12, styles: 74, color: 3, highlight: 9, colors: hairColors },
    face: [
      { id: 'nose_width', label: 'Nose width', value: 0.1 }, { id: 'nose_peak', label: 'Nose peak height', value: -0.2 },
      { id: 'nose_length', label: 'Nose length', value: 0 }, { id: 'brow_height', label: 'Brow height', value: 0.35 },
      { id: 'brow_depth', label: 'Brow depth', value: 0 }, { id: 'cheek_height', label: 'Cheekbone height', value: -0.15 },
      { id: 'cheek_width', label: 'Cheekbone width', value: 0.2 }, { id: 'eyes', label: 'Eye opening', value: 0 },
      { id: 'lips', label: 'Lip thickness', value: 0.4 }, { id: 'jaw_width', label: 'Jaw width', value: -0.3 },
      { id: 'jaw_length', label: 'Jaw length', value: 0 }, { id: 'chin', label: 'Chin length', value: 0.1 },
      { id: 'neck', label: 'Neck thickness', value: 0 },
    ],
  });
  go(3);
  setVal('drawable', 31);
  NZ.$$('.rb')[6].click(); setVal('texture', 2);
  go(3);
});
