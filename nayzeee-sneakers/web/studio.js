/* ═══════════════════════════════════════════════════════════
   NAYZEEE SNEAKERS · Sneaker Studio
   Built like the wig snatch and backpack studios: the shoe floats in a lit
   chroma box under the map, you frame it with the orbit camera between the
   two panels, and each shot is keyed here (keyer.js) into a small PNG.
   Names, prices, boxes and "on sale" are set here too.
   ═══════════════════════════════════════════════════════════ */
'use strict';

Object.assign(PATHS, {
  image: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><circle cx="9" cy="10" r="1.8"/><path d="M20.5 16 15 11l-9 8.5"/>',
  pen: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
  play: '<path d="M7 5v14l11-7z"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="1.5"/>',
  cube: '<path d="M12 3.5 20 8v8l-8 4.5L4 16V8z"/><path d="M4 8l8 4.5L20 8M12 12.5v8"/>',
  refresh: '<path d="M20 11a8 8 0 0 0-14.5-4.5L4 8M4 4v4h4M4 13a8 8 0 0 0 14.5 4.5L20 16M20 20v-4h-4"/>',
  left: '<path d="M15 6l-6 6 6 6"/>',
  save: '<path d="M5 4h11l3 3v13H5z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/>',
  layers: '<path d="M12 4 3.5 8.5 12 13l8.5-4.5z"/><path d="M3.5 12.5 12 17l8.5-4.5M3.5 16.5 12 21l8.5-4.5"/>',
});

const SD = {
  on: false, data: null, entries: {}, list: [], key: null, letter: 'a', subject: 'loose', mode: 'none',
  chroma: 'green', orbit: { yaw: 215, elev: 24, zoom: 1, lift: 0 }, batch: null, screenshot: true,
  size: 256, search: '', gender: 'all', filter: 'all', source: 'packs', shots: new Set(), thumbs: {}, recent: [],
  kit: null, kitRun: null, confirm: false, edit: null, saveToInventory: true, version: '1.0.0',
  opts: { colours: false, loose: true, box: false, missing: true },
};
const sdRoot = $('studio');
const sdEl = (sel, root) => (root || document).querySelector(sel);
const sdAll = (sel, root) => [...(root || document).querySelectorAll(sel)];
const clampN = (v, a, b) => Math.max(a, Math.min(b, v));
const GEN = { male: 'Male', female: 'Female' };
const BOXN = { shoe: 'Shoe box', heel: 'Heel box', boot: 'Boot box' };

const shotName = (e, l, sub) => `nzs_${e.id}_${l}${sub === 'box' ? '_box' : ''}`;
const hasShot = (e, l, sub) => !!e && !!e.id && (SD.shots.has(shotName(e, l, sub)) || !!SD.thumbs[shotName(e, l, sub)]);
function thumb(e, l) {
  if (!e || !e.id) return `<span class="ic">${icon('shoe')}</span>`;
  const n = shotName(e, l || 'a');
  return `<img src="${SD.thumbs[n] || img(n)}" alt="" loading="lazy">`;
}
const packOf = (e) => (e.gta ? 'Default GTA' : e.link ? (e.link.collection || 'base game') : (e.pack || ''));
// where a shoe comes from: one of your clothing packs, or GTA itself (base game and Rockstar's DLCs)
const sourceOf = (e) => (e.gta ? 'gta' : 'packs');
const numOf = (e) => (e.link && e.link.index != null ? `#${e.link.index}` : '');

/* ─────────────── data ─────────────── */
function sdIndex() {
  const d = SD.data || {};
  SD.entries = {};
  SD.list = [];
  (d.shoes || []).forEach((e) => { SD.entries[e.key] = e; SD.list.push(e); });
  (d.fresh || []).forEach((f) => {
    const colours = Array.from({ length: Math.min(26, f.textures || 1) }, (_, i) => ({ letter: String.fromCharCode(97 + i), name: `Texture ${i + 1}` }));
    const e = { key: f.key, fresh: true, gta: !!f.gta, gender: f.gender, colours, link: { collection: f.collection, index: f.index },
      label: f.gta ? `GTA shoe ${String(f.index).padStart(3, '0')}` : `${f.collection || 'Base game'} ${String(f.index).padStart(3, '0')}` };
    SD.entries[e.key] = e;
    SD.list.push(e);
  });
  SD.shots = new Set(d.shots || []);
  if (d.kit) SD.kit = d.kit;
}
const cur = () => SD.entries[SD.key] || null;

function sdEditFor(e) {
  if (!e || e.fresh) return null;
  const colours = {};
  (e.colours || []).forEach((c) => { colours[c.letter] = c.name || ''; });
  return { key: e.key, label: e.label || '', retail: e.retail || 0, level: e.level || 1, enabled: !!e.enabled,
    box: e.box || 'shoe', gender: e.gender || 'male', colours, link: e.link || null, dirty: false };
}

/* ─────────────── open / close ─────────────── */
function studioOpen(m) {
  SD.on = true;
  SD.data = m.data || {};
  SD.size = m.size || 256;
  SD.screenshot = m.screenshot !== false;
  SD.saveToInventory = m.saveToInventory !== false;
  SD.version = m.version || SD.version;
  SD.kitRun = null;
  SD.confirm = false;
  SD.search = '';
  sdIndex();
  sdRoot.hidden = false;
  document.body.classList.add('studio-open');
  sdRender();
}
function studioClose(silent) {
  if (!SD.on) return;
  SD.on = false;
  sdRoot.hidden = true;
  document.body.classList.remove('studio-open', 'shooting');
  if (!silent) post('st:close');
}

// game → studio state. Orbit-only changes don't rebuild the panels (that would drop a slider mid-drag).
// what each panel shows, so a click only redraws the panel that changed
const sdLeftSig = () => JSON.stringify([SD.key, !!SD.batch]);
const sdSig = () => JSON.stringify([SD.key, SD.letter, SD.subject, SD.mode, SD.chroma, SD.batch, SD.screenshot]);
function studioState(s) {
  const before = sdSig(), beforeLeft = sdLeftSig();
  const keyChanged = s.key !== undefined && s.key !== SD.key;
  Object.assign(SD, {
    key: s.key ?? SD.key, letter: s.letter || SD.letter, subject: s.subject || SD.subject, mode: s.mode || SD.mode,
    chroma: s.chroma || SD.chroma, orbit: s.orbit || SD.orbit, batch: s.batch || null,
    screenshot: s.screenshot !== undefined ? s.screenshot : SD.screenshot,
  });
  if (keyChanged || !SD.edit || SD.edit.key !== SD.key) SD.edit = sdEditFor(cur());
  if (!SD.on) return;
  if (sdLeftSig() !== beforeLeft) sdLeft();
  if (sdSig() !== before) sdRight();
  else sdOrbitUi();
}

function studioData(d) {
  SD.data = d || {};
  sdIndex();
  const e = cur();
  if (!SD.edit || !SD.edit.dirty || !e || SD.edit.key !== e.key) SD.edit = sdEditFor(e);
  if (SD.on) sdRender();
}

const sdNear = (y, e) => Math.abs(((SD.orbit.yaw - y + 540) % 360) - 180) < 3 && Math.abs(SD.orbit.elev - e) < 3;
function sdOrbitUi() {
  const o = SD.orbit;
  sdAll('[data-sd="angle"]', sdRoot).forEach((b) => b.classList.toggle('on', sdNear(+b.dataset.yaw, +b.dataset.elev)));
  [['sdZoom', 'zoom'], ['sdLift', 'lift']].forEach(([id, k]) => {
    const el = $(id);
    if (!el) return;
    if (document.activeElement !== el) el.value = o[k];
    $(id + 'V').textContent = (+o[k]).toFixed(2);
  });
}

/* ─────────────── render ─────────────── */
function sdRender() {
  sdLeft();
  sdRight();
}

function sdRows() {
  const q = SD.search.trim().toLowerCase();
  return SD.list.filter((e) => {
    if (SD.gender !== 'all' && e.gender !== SD.gender) return false;
    if (sourceOf(e) !== SD.source) return false;
    if (SD.filter === 'on' && !(e.enabled && !e.removed && !e.fresh)) return false;
    if (SD.filter === 'off' && (e.enabled || e.fresh || e.removed)) return false;
    if (SD.filter === 'new' && !e.fresh) return false;
    if (SD.filter === 'gone' && !e.removed) return false;
    if (!q) return true;
    return (e.label || '').toLowerCase().includes(q) || packOf(e).toLowerCase().includes(q) || (e.key || '').toLowerCase().includes(q);
  });
}

function sdLeft() {
  const prev = sdEl('.sd-list', $('sdLeft'));
  if (prev) sdLeft.top = prev.scrollTop;
  const shoes = SD.list.filter((e) => !e.fresh && !e.gta);
  const photographed = shoes.filter((e) => hasShot(e, 'a')).length;
  const bySource = (s) => SD.list.filter((e) => (SD.gender === 'all' || e.gender === SD.gender) && sourceOf(e) === s).length;
  const n = (f) => SD.list.filter((e) => (SD.gender === 'all' || e.gender === SD.gender) && sourceOf(e) === SD.source && f(e)).length;
  const counts = {
    all: n(() => true), on: n((e) => e.enabled && !e.removed && !e.fresh), off: n((e) => !e.enabled && !e.fresh && !e.removed),
    new: n((e) => e.fresh), gone: n((e) => e.removed),
  };
  const rows = sdRows();
  const dis = SD.batch ? 'disabled' : '';
  $('sdLeft').innerHTML = `<div class="ch-frame"><div class="ch-in sd-in">
    <div class="sd-head"><div class="mark sm"></div><div class="sd-ht"><b>Sneaker Studio</b><span>${shoes.length} shoes · ${photographed} photographed</span></div><span class="ver">v${esc(SD.version)}</span></div>
    <div class="seg sd-seg">${[['all', 'All'], ['male', 'Male'], ['female', 'Female']].map(([k, l]) => `<button class="${SD.gender === k ? 'on' : ''}" data-sd="gender" data-v="${k}">${l}</button>`).join('')}</div>
    <div class="sd-src">${[['packs', 'Clothing packs'], ['gta', 'Default GTA']].map(([k, l]) =>
      `<button class="${SD.source === k ? 'on' : ''} ${k}" data-sd="source" data-v="${k}"><b>${l}</b><em>${bySource(k)}</em></button>`).join('')}</div>
    ${SD.source === 'gta' ? `<div class="sd-gta-note"><span class="ic">${icon('alert')}</span><span>Shoes that come with GTA. Customers' packs are under <b>Clothing packs</b>; these are kept apart so they aren't photographed or put on sale by mistake.</span></div>` : ''}
    <div class="sd-filters">${[['all', 'All'], ['on', 'On sale'], ['off', 'Off'], ['new', 'New'], ['gone', 'Gone']].map(([k, l]) =>
      `<button class="sd-chip sm ${SD.filter === k ? 'on' : ''} ${k === 'new' && counts.new ? 'hot' : ''}" data-sd="filter" data-v="${k}">${l}<em>${counts[k]}</em></button>`).join('')}</div>
    <label class="field"><span class="ic">${icon('search')}</span><input id="sdSearch" placeholder="Search by name or pack" value="${esc(SD.search)}" autocomplete="off"></label>
    <div class="sd-list">${rows.length ? rows.map((e) => {
      const tags = [];
      if (e.gta) tags.push('<span class="sd-tag gta">GTA</span>');
      else if (e.fresh) tags.push('<span class="sd-tag new">NEW</span>');
      if (e.removed) tags.push('<span class="sd-tag red">GONE</span>');
      if (!e.fresh && !e.removed && !e.enabled) tags.push('<span class="sd-tag">OFF</span>');
      if (e.props) tags.push('<span class="sd-3d" title="Has a 3D prop">3D</span>');
      const sub = [GEN[e.gender] || '', packOf(e), numOf(e), `${(e.colours || []).length} colourway${(e.colours || []).length === 1 ? '' : 's'}`].filter(Boolean).join(' · ');
      return `<button class="sd-row ${e.key === SD.key ? 'on' : ''}" data-sd="pick" data-v="${esc(e.key)}" ${dis}>
        <span class="sd-th">${thumb(e)}</span>
        <span class="sd-rt"><b>${esc(e.label || 'Shoe')}</b><span>${esc(sub)}</span></span>
        ${tags.join('')}<span class="dot ${hasShot(e, 'a') ? 'on' : ''}"></span></button>`;
    }).join('') : `<div class="empty"><span class="ic">${icon('search')}</span>${SD.source === 'gta' && SD.filter === 'all' ? 'No GTA shoes listed.' : SD.filter === 'new' ? 'Nothing new. Every shoe on the server is in the studio.' : 'Nothing matches'}</div>`}</div>
    <button class="btn sm wide" data-sd="rescan" ${dis}><span class="ic">${icon('refresh')}</span>Look for new shoes again</button>
  </div></div>`;
  const list = sdEl('.sd-list', $('sdLeft'));
  if (list) list.scrollTop = sdLeft.top || 0;
  const on = sdEl('.sd-row.on', list);
  if (on) on.scrollIntoView({ block: 'nearest' });
}

function sdShoeCard(e, busy) {
  const dis = busy ? 'disabled' : '';
  if (e.fresh && e.gta) {
    return `<div class="card sd-card">
      <div class="sd-ch">Default GTA shoe <em>${esc(numOf(e))}</em></div>
      <div class="sd-gta-note"><span class="ic">${icon('alert')}</span><span>This shoe comes with GTA, not from a clothing pack. You can still add it, but it won't have its own 3D prop.</span></div>
      <button class="btn wide" data-sd="add" ${dis}><span class="ic">${icon('plus')}</span>Add it anyway</button>
    </div>`;
  }
  if (e.fresh) {
    return `<div class="card sd-card">
      <div class="sd-ch">New on the server <em>${esc(packOf(e))} ${esc(numOf(e))}</em></div>
      <p class="sd-p">This shoe is in your clothing but not in the shop yet. <b>3D props</b> below gives it its own prop and icons (it's picked up on its own when the server starts), or add it now and it uses a stand-in prop until then.</p>
      <button class="btn teal wide" data-sd="add" ${dis}><span class="ic">${icon('plus')}</span>Add it as a shoe</button>
    </div>`;
  }
  const ed = SD.edit || sdEditFor(e);
  const max = (SD.data && SD.data.maxLevel) || 10;
  const looseLike = e.manual || e.loose;
  return `<div class="card sd-card">
    <div class="sd-ch">Shoe <em>${e.builtin ? 'comes with the script' : e.gta ? 'Default GTA shoe' : e.manual ? 'added in game' : 'from your clothing'}</em></div>
    ${e.removed ? `<div class="sd-warn-in red"><span class="ic">${icon('alert')}</span><span>Its clothing isn't on the server any more. Pairs players own keep working.</span></div>` : ''}
    <label class="sd-switch"><input type="checkbox" id="sdOn" ${ed.enabled ? 'checked' : ''} ${dis}><span class="sw2"></span><span><b>On sale</b>Players can make it, wear it and sell it</span></label>
    <label class="field"><span class="ic">${icon('pen')}</span><input id="sdLabel" maxlength="40" placeholder="Name this shoe" value="${esc(ed.label)}" ${dis}></label>
    <div class="sd-pair">
      <label class="field"><span class="ic cur">$</span><input id="sdPrice" type="number" min="1" step="10" value="${ed.retail}" ${dis}></label>
      <div class="sd-lvl"><span>Level</span><button class="btn sm" data-sd="lvl" data-v="-1" ${dis || (ed.level <= 1 ? 'disabled' : '')}>−</button><b id="sdLvl">${ed.level}</b><button class="btn sm" data-sd="lvl" data-v="1" ${dis || (ed.level >= max ? 'disabled' : '')}>+</button></div>
    </div>
    ${e.builtin ? '' : `<div class="sd-axis2"><span>Box</span><div class="seg sd-seg">${['shoe', 'heel', 'boot'].map((b) => `<button class="${ed.box === b ? 'on' : ''}" data-sd="box" data-v="${b}" ${dis}>${b[0].toUpperCase() + b.slice(1)}</button>`).join('')}</div></div>`}
    ${e.loose ? sdLinkRow(e, ed, dis) : ''}
    ${looseLike ? `<div class="sd-axis2"><span>For</span><div class="seg sd-seg">${['male', 'female'].map((g) => `<button class="${ed.gender === g ? 'on' : ''}" data-sd="sex" data-v="${g}" ${dis}>${GEN[g]}</button>`).join('')}</div></div>` : ''}
    <div class="sd-row2">
      ${e.manual ? `<button class="btn red sm" data-sd="forget" ${dis}><span class="ic">${icon('x')}</span>Forget it</button>` : `<span></span>`}
      <button class="btn teal sm" data-sd="save" ${dis}><span class="ic">${icon('save')}</span>Save</button>
    </div>
  </div>`;
}

// plain downloads: which drawable on the server they are (picked from the drawables nobody has yet)
function sdLinkRow(e, ed, dis) {
  const opts = [];
  const val = ed.link ? `${ed.link.collection}|${ed.link.index}` : '';
  if (ed.link) opts.push([val, `${ed.link.collection || 'base game'} #${ed.link.index}`]);
  ((SD.data && SD.data.fresh) || []).forEach((f) => {
    const v = `${f.collection}|${f.index}`;
    if (v !== val) opts.push([v, `${f.collection || 'base game'} #${f.index} (${GEN[f.gender]})`]);
  });
  return `<div class="sd-axis2"><span>Drawable</span><select id="sdLink" ${dis}>
      ${ed.link ? '' : '<option value="">Pick the drawable it is on your server</option>'}
      ${opts.map(([v, l]) => `<option value="${esc(v)}" ${v === val ? 'selected' : ''}>${esc(l)}</option>`).join('')}
    </select></div>
    ${ed.link ? '' : '<div class="sd-warn-in"><span class="ic">' + icon('alert') + '</span><span>A plain download: pick which drawable it is so players can wear it. The model shows what you picked.</span></div>'}`;
}

function sdColourCard(e, busy) {
  const dis = busy ? 'disabled' : '';
  const cols = e.colours || [];
  const i = Math.max(0, cols.findIndex((c) => c.letter === SD.letter));
  const c = cols[i] || { letter: 'a', name: '' };
  const ed = SD.edit;
  const name = ed && ed.colours[c.letter] !== undefined ? ed.colours[c.letter] : c.name;
  return `<div class="card sd-card">
    <div class="sd-ch">Colourway <em>${c.letter.toUpperCase()} · ${i + 1} of ${cols.length}</em></div>
    <div class="sd-cols ${e.fresh ? 'plain' : ''}">${cols.map((x) => `<button class="sd-col ${x.letter === SD.letter ? 'on' : ''}" data-sd="tex" data-v="${x.letter}" ${dis} title="${esc(x.name || '')}">
      ${e.id && !e.fresh ? `<img src="${SD.thumbs[shotName(e, x.letter)] || img(shotName(e, x.letter))}" alt="">` : ''}<i>${x.letter.toUpperCase()}</i>${hasShot(e, x.letter) ? '<s></s>' : ''}</button>`).join('')}</div>
    ${e.fresh ? '' : `<div class="sd-name"><label class="field"><span class="ic">${icon('pen')}</span><input id="sdColName" data-letter="${c.letter}" maxlength="30" placeholder="Colour name" value="${esc(name || '')}" ${dis}></label></div>`}
    <div class="sd-step">
      <button class="btn sm" data-sd="step" data-v="-1" ${dis}><span class="ic">${icon('left')}</span>Prev shoe</button>
      <span class="grow"></span>
      <button class="btn sm" data-sd="step" data-v="1" ${dis}>Next shoe<span class="ic">${icon('chevron')}</span></button>
    </div>
  </div>`;
}

function sdRight() {
  const e = cur();
  const b = SD.batch, busy = !!b;
  const o = SD.orbit;
  const dis = busy ? 'disabled' : '';
  const chip = (attrs, label, on, extra) => `<button class="sd-chip ${on ? 'on' : ''}" ${attrs} ${busy || extra ? 'disabled' : ''}>${label}</button>`;
  const canShoot = SD.mode === 'loose' || SD.mode === 'box';
  const col = e && (e.colours || []).find((c) => c.letter === SD.letter);
  const head = e ? `<b>${esc(e.label || 'Shoe')}</b><span>${[GEN[e.gender], packOf(e), numOf(e), col ? `colourway ${SD.letter.toUpperCase()}` : ''].filter(Boolean).map(esc).join(' · ')}</span>`
    : '<b>Sneaker Studio</b><span>Pick a shoe on the left</span>';
  $('sdRight').innerHTML = `<div class="ch-frame"><div class="ch-in sd-in">
    <div class="sd-head"><div class="sd-ht">${head}</div>
      <button class="pill-close" data-sd="close" ${dis}>Close</button></div>
    <div class="sd-scroll">
      ${SD.screenshot ? '' : `<div class="card sd-warn"><span class="ic">${icon('alert')}</span><span><b>screenshot-basic</b> isn't running. You can still frame, name and price shoes.</span></div>`}
      ${e && SD.mode === 'feet' ? `<div class="card sd-warn"><span class="ic">${icon('cube')}</span><span>No 3D prop for this shoe yet, so it's shown on a model. Build it in <b>3D props</b> to photograph it.</span></div>` : ''}
      ${e ? sdShoeCard(e, busy) : ''}
      ${e ? sdColourCard(e, busy) : ''}

      <div class="card sd-card">
        <div class="sd-ch">Backdrop <em>pick one the shoe doesn't use</em></div>
        <div class="sd-chips">${[['green', 'Green', '#00b140'], ['magenta', 'Magenta', '#ff00ff'], ['blue', 'Blue', '#0047bb']].map(([k, l, c]) =>
          chip(`data-sd="chroma" data-v="${k}"`, `<i class="sd-sw" style="background:${c}"></i>${l}`, SD.chroma === k)).join('')}</div>
      </div>

      <div class="card sd-card">
        <div class="sd-ch">Framing <em>drag to orbit · scroll to zoom</em></div>
        <div class="seg sd-seg">${[['loose', 'The pair'], ['box', 'In its box']].map(([k, l]) =>
          `<button class="${SD.subject === k ? 'on' : ''}" data-sd="subject" data-v="${k}" ${busy || SD.mode === 'feet' ? 'disabled' : ''}>${l}</button>`).join('')}</div>
        <div class="sd-chips">
          ${chip('data-sd="angle" data-yaw="215" data-elev="24"', 'Three quarter', sdNear(215, 24))}
          ${chip('data-sd="angle" data-yaw="270" data-elev="6"', 'Side', sdNear(270, 6))}
          ${chip('data-sd="angle" data-yaw="180" data-elev="10"', 'Front', sdNear(180, 10))}
          ${chip('data-sd="angle" data-yaw="235" data-elev="55"', 'High', sdNear(235, 55))}
          ${chip('data-sd="angle" data-yaw="180" data-elev="85"', 'Top', sdNear(180, 85))}
        </div>
        <div class="sd-axis"><span>Zoom</span><input type="range" id="sdZoom" min="0.4" max="3" step="0.02" value="${o.zoom}" ${dis}><b id="sdZoomV">${(+o.zoom).toFixed(2)}</b></div>
        <div class="sd-axis"><span>Height</span><input type="range" id="sdLift" min="-0.3" max="0.3" step="0.01" value="${o.lift}" ${dis}><b id="sdLiftV">${(+o.lift).toFixed(2)}</b></div>
      </div>

      <div class="card sd-card">
        <div class="sd-ch">Capture <em>${SD.size} × ${SD.size} png</em></div>
        <div class="sd-row2">
          <button class="btn" data-sd="shoot" ${busy || !SD.screenshot || !canShoot ? 'disabled' : ''}><span class="ic">${icon('camera')}</span>This photo</button>
          <button class="btn teal" data-sd="batch" ${busy || !SD.screenshot ? 'disabled' : ''}><span class="ic">${icon('layers')}</span>Every shoe</button>
        </div>
        <div class="sd-name-hint">${e && e.id && !e.fresh ? `Saves as <b>${esc(shotName(e, SD.letter, SD.subject))}.png</b>` : 'Shoes need a 3D prop before they can be photographed'}</div>
        <label class="sd-check"><input type="checkbox" data-opt="colours" ${SD.opts.colours ? 'checked' : ''} ${dis}><span>Every colourway, not just the first</span></label>
        <label class="sd-check"><input type="checkbox" data-opt="loose" ${SD.opts.loose ? 'checked' : ''} ${dis}><span>The pair (nzs_shoe_a.png)</span></label>
        <label class="sd-check"><input type="checkbox" data-opt="box" ${SD.opts.box ? 'checked' : ''} ${dis}><span>In its box (nzs_shoe_a_box.png)</span></label>
        <label class="sd-check"><input type="checkbox" data-opt="missing" ${SD.opts.missing ? 'checked' : ''} ${dis}><span>Skip ones that already have a photo</span></label>
        ${SD.confirm && !busy ? `<div class="sd-confirm"><p>Every ${SD.gender === 'all' ? '' : GEN[SD.gender].toLowerCase() + ' '}shoe with a 3D prop${SD.opts.colours ? ', every colourway,' : ''} gets photographed with this framing and backdrop${SD.opts.missing ? ', skipping ones that already have a photo' : ''}. Backspace stops it.</p>
          <div class="sd-row2"><button class="btn ghost sm" data-sd="nobatch">Cancel</button><button class="btn teal sm" data-sd="gobatch"><span class="ic">${icon('play')}</span>Start</button></div></div>` : ''}
        ${busy ? `<div class="sd-prog"><div class="sd-pt"><span>Shooting ${b.i} of ${b.n}</span><b>${Math.round((b.i / Math.max(1, b.n)) * 100)}%</b></div>
          <div class="sd-bar"><i style="width:${(b.i / Math.max(1, b.n)) * 100}%"></i></div>
          <button class="btn red sm wide" data-sd="cancel"><span class="ic">${icon('stop')}</span>Stop batch <span class="kc">BACKSPACE</span></button></div>` : ''}
      </div>

      ${sdKitCard(busy)}

      <div class="card sd-card">
        <div class="sd-ch">Recent <em>${SD.saveToInventory ? 'saved to shots/ and ox_inventory' : 'saved to shots/'}</em></div>
        <div class="note">New icons show in the inventory after ox_inventory restarts.</div>
        <div class="sd-shots">${SD.recent.length ? SD.recent.map((r) => `<div class="sd-shot ${r.ok === false ? 'bad' : ''}"><img src="${r.png}" alt=""><span>${esc(r.name)}</span></div>`).join('')
          : '<div class="empty" style="grid-column:1/-1;padding:16px"><b>No photos yet</b></div>'}</div>
      </div>
    </div>
    <div class="sd-foot"><span class="kc">ESC</span>Close<span class="kc">↑</span><span class="kc">↓</span>Shoe<span class="kc">←</span><span class="kc">→</span>Colour</div>
  </div></div>`;
}

/* ─────────────── 3D props (sneakerkit) ─────────────── */
function sdKitCard(busy) {
  const h = SD.kit;
  if (!h || !h.enabled) return '';
  const run = SD.kitRun, running = h.running || (run && run.running);
  const todo = (h.new || 0) + (h.changed || 0) + (h.removed || 0);
  let body;
  if (!h.kit) body = `<div class="sd-warn-in"><span class="ic">${icon('alert')}</span><span>sneakerkit isn't installed for this server (${esc(h.platform || '?')}). Put it in <b>tools/sneakerkit</b>.</span></div>`;
  else body = `<div class="sd-hk">
      <div><b>${h.props}</b><span>shoe props</span></div>
      <div class="${h.new ? 'new' : ''}"><b>${h.new}</b><span>new</span></div>
      <div class="${h.changed ? 'new' : ''}"><b>${h.changed}</b><span>changed</span></div>
      <div><b>${h.removed}</b><span>gone</span></div></div>
    ${running && run && run.n ? `<div class="sd-prog"><div class="sd-pt"><span>Building ${run.i} of ${run.n}${run.key ? ` · ${esc(run.key)}` : ''}</span><b>${Math.round((run.i / Math.max(1, run.n)) * 100)}%</b></div>
      <div class="sd-bar"><i style="width:${(run.i / Math.max(1, run.n)) * 100}%"></i></div></div>` : ''}
    <div class="sd-row2">
      <button class="btn ${todo ? 'teal' : ''}" data-sd="kit" data-v="build" ${running || busy ? 'disabled' : ''}><span class="ic">${icon('cube')}</span>${running ? 'Working…' : todo ? `Build ${todo}` : 'Up to date'}</button>
      <button class="btn" data-sd="kit" data-v="scan" ${running || busy ? 'disabled' : ''}><span class="ic">${icon('refresh')}</span>Check again</button>
    </div>
    <button class="btn ghost sm wide" data-sd="kit" data-v="rebuild" ${running || busy ? 'disabled' : ''}>Rebuild every shoe</button>`;
  return `<div class="card sd-card">
    <div class="sd-ch">3D props <em>your server's shoes, as props</em></div>
    ${body}
    <div class="note">Every shoe your clothing packs stream becomes a prop for the shop, boxes and crafting, with icons. New and changed shoes are found when the server starts.</div>
  </div>`;
}

function studioKit(d) {
  SD.kitRun = SD.kitRun || {};
  if (d.kind === 'start') { SD.kitRun = { running: true }; if (SD.kit) SD.kit.running = d.mode; }
  if (d.kind === 'progress') Object.assign(SD.kitRun, { running: true, i: d.i, n: d.n, key: d.key });
  if (d.kind === 'done' || d.kind === 'status') { SD.kitRun = null; if (d.status) SD.kit = d.status; }
  if (SD.on) sdRight();
}

/* ─────────────── input ─────────────── */
function sdSave() {
  const e = cur(), ed = SD.edit;
  if (!e || !ed || e.fresh) return;
  const fields = { label: ed.label, retail: +ed.retail || 0, level: ed.level, enabled: ed.enabled, colours: ed.colours };
  if (!e.builtin) fields.box = ed.box;
  if (e.manual || e.loose) fields.gender = ed.gender;
  if (e.loose && ed.link) fields.link = ed.link;
  ed.dirty = false;
  post('st:save', { key: e.key, fields });
}

function sdStep(d) {
  const rows = sdRows();
  const i = rows.findIndex((x) => x.key === SD.key);
  const n = rows[clampN(i + d, 0, rows.length - 1)];
  if (n && n.key !== SD.key) post('st:pick', { key: n.key, letter: 'a' });
}

function sdStepColour(d) {
  const e = cur();
  if (!e) return;
  const cols = e.colours || [];
  const i = cols.findIndex((c) => c.letter === SD.letter);
  const n = cols[clampN(i + d, 0, cols.length - 1)];
  if (n && n.letter !== SD.letter) post('st:pick', { key: e.key, letter: n.letter });
}

sdRoot.addEventListener('click', (ev) => {
  const b = ev.target.closest('[data-sd]');
  if (!b || b.disabled) return;
  const v = b.dataset.v;
  const ed = SD.edit;
  switch (b.dataset.sd) {
    case 'close': return studioClose();
    case 'gender': SD.gender = v; sdLeft.top = 0; return sdLeft();
    case 'filter': SD.filter = v; sdLeft.top = 0; return sdLeft();
    case 'source': SD.source = v; SD.filter = 'all'; sdLeft.top = 0; return sdLeft();
    case 'pick': return post('st:pick', { key: v, letter: 'a' });
    case 'tex': return post('st:pick', { key: SD.key, letter: v });
    case 'step': return sdStep(Number(v));
    case 'rescan': return post('st:rescan');
    case 'add': return post('st:add', { key: SD.key });
    case 'forget': return post('st:forget', { key: SD.key });
    case 'save': return sdSave();
    case 'lvl': if (ed) { ed.level = clampN(ed.level + Number(v), 1, (SD.data && SD.data.maxLevel) || 10); ed.dirty = true; sdRight(); } return;
    case 'box': if (ed) { ed.box = v; ed.dirty = true; sdRight(); } return;
    case 'sex': if (ed) { ed.gender = v; ed.dirty = true; sdRight(); } return;
    case 'chroma': return post('st:chroma', { color: v });
    case 'subject': return post('st:subject', { subject: v });
    case 'angle': return post('st:orbit', { yaw: Number(b.dataset.yaw), elev: Number(b.dataset.elev) });
    case 'shoot': return post('st:capture');
    case 'batch': SD.confirm = true; return sdRight();
    case 'nobatch': SD.confirm = false; return sdRight();
    case 'gobatch': SD.confirm = false; return post('st:batch', { gender: SD.gender, ...SD.opts });
    case 'cancel': return post('st:cancel');
    case 'kit': return post('st:kit', { mode: v });
  }
});

sdRoot.addEventListener('input', (ev) => {
  const t = ev.target, ed = SD.edit;
  if (t.id === 'sdSearch') {
    SD.search = t.value;
    sdLeft();
    const s = $('sdSearch');
    s.focus();
    s.setSelectionRange(s.value.length, s.value.length);
    return;
  }
  if (t.id === 'sdZoom') { $('sdZoomV').textContent = (+t.value).toFixed(2); return post('st:zoom', { set: +t.value }); }
  if (t.id === 'sdLift') { $('sdLiftV').textContent = (+t.value).toFixed(2); return post('st:lift', { set: +t.value }); }
  if (!ed) return;
  if (t.id === 'sdLabel') { ed.label = t.value; ed.dirty = true; }
  if (t.id === 'sdPrice') { ed.retail = t.value; ed.dirty = true; }
  if (t.id === 'sdColName') { ed.colours[t.dataset.letter] = t.value; ed.dirty = true; }
});

sdRoot.addEventListener('change', (ev) => {
  const t = ev.target;
  if (t.dataset.opt) SD.opts[t.dataset.opt] = t.checked;
  if (t.id === 'sdOn' && SD.edit) { SD.edit.enabled = t.checked; SD.edit.dirty = true; }
  if (t.id === 'sdLink' && SD.edit && t.value) {
    const [collection, index] = t.value.split('|');
    SD.edit.link = { collection, index: Number(index) };
    SD.edit.dirty = true;
    post('st:preview', { key: SD.key, link: SD.edit.link, letter: SD.letter });
  }
});

// Enter in a text field saves
sdRoot.addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter' && ['sdLabel', 'sdPrice', 'sdColName'].includes(ev.target.id)) { ev.preventDefault(); ev.target.blur(); sdSave(); }
});

// orbit + zoom on the empty middle of the screen
(function () {
  const c = $('sdOrbit');
  let drag = false, lx = 0, ly = 0, ax = 0, ay = 0, raf = null;
  const flush = () => {
    raf = null;
    if (!ax && !ay) return;
    post('st:orbit', { dx: ax, dy: ay });
    ax = 0; ay = 0;
  };
  c.addEventListener('pointerdown', (e) => { drag = true; lx = e.clientX; ly = e.clientY; c.classList.add('drag'); c.setPointerCapture(e.pointerId); });
  c.addEventListener('pointerup', () => { drag = false; c.classList.remove('drag'); });
  c.addEventListener('pointermove', (e) => {
    if (!drag || SD.batch) return;
    ax += e.clientX - lx; ay += e.clientY - ly; lx = e.clientX; ly = e.clientY;
    if (!raf) raf = requestAnimationFrame(flush);
  });
  c.addEventListener('wheel', (e) => {
    e.preventDefault();
    if (!SD.batch) post('st:zoom', { delta: e.deltaY * 0.001 });
  }, { passive: false });
})();

addEventListener('keydown', (e) => {
  if (!SD.on) return;
  if (e.target && e.target.tagName === 'INPUT' && e.target.type !== 'checkbox' && e.target.type !== 'range') {
    if (e.key === 'Escape') e.target.blur();
    return;
  }
  if (e.key === 'Backspace' && SD.batch) { e.preventDefault(); post('st:cancel'); return; }
  if (e.key === 'Escape') { e.preventDefault(); if (SD.confirm) { SD.confirm = false; sdRight(); } else if (!SD.batch) studioClose(); return; }
  if (SD.batch) return;
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); sdStep(e.key === 'ArrowDown' ? 1 : -1); }
  if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') { e.preventDefault(); sdStepColour(e.key === 'ArrowRight' ? 1 : -1); }
});

/* ─────────────── shooting ─────────────── */
// hide every bit of UI for the frame the screenshot is taken on
function studioHide() { document.body.classList.add('shooting'); }
function studioShow() { document.body.classList.remove('shooting'); }

async function studioProcess(job) {
  try {
    const png = await Keyer.run(job);
    SD.thumbs[job.name] = png;
    SD.recent.unshift({ name: job.name, png });
    if (SD.recent.length > 8) SD.recent.pop();
    post('st:processed', { name: job.name, png: png.slice(png.indexOf(',') + 1) });
  } catch (err) {
    post('st:failed', { name: job.name, reason: (err && err.message) || String(err) });
  }
}

function studioSaved(d) {
  const r = SD.recent.find((x) => x.name === d.name);
  if (r) r.ok = d.ok;
  if (d.ok) SD.shots.add(d.name);
  if (SD.on) sdRender();
}

function studioMessage(m) {
  switch (m.action) {
    case 'studio:open': return studioOpen(m);
    case 'studio:close': return studioClose(true);
    case 'studio:state': return studioState(m.state || {});
    case 'studio:data': return studioData(m.data);
    case 'studio:kit': return studioKit(m.kit || {});
    case 'studio:hide': return studioHide();
    case 'studio:show': return studioShow();
    case 'studio:process': return studioProcess(m.job || {});
    case 'studio:saved': return studioSaved(m);
  }
}
