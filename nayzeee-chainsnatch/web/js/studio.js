/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · Chain Studio
   Left: every chain. Right: Fit (neck + hand), Look, Icon, Convert.
   The character stands between the panels; drag to orbit, scroll to zoom.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const SD = {
  on: false, d: null, tab: 'fit', search: '', move: 0.005, rot: 5,
  kit: null, prog: null, icon: null, shots: [],
};
const sdRoot = $('#studio');

const MOVES = [[0.001, '1mm'], [0.005, '5mm'], [0.01, '1cm'], [0.05, '5cm']];
const ROTS = [[1, '1°'], [5, '5°'], [15, '15°'], [45, '45°']];
const ANGLES = [['Top', 180, 85], ['¾', 200, 55], ['Front', 180, 12], ['Side', 270, 20]];
const CHROMA = [['green', '#00b140'], ['magenta', '#ff00ff'], ['blue', '#0047bb']];

const cur = () => SD.d && arr(SD.d.chains).find((c) => c.key === SD.d.current);
const n4 = (v) => (+v || 0).toFixed(4);
const n2 = (v) => (+v || 0).toFixed(2);

/* ─────────────── open / close ─────────────── */
H['studio:open'] = (d) => {
  SD.on = true;
  SD.d = d;
  SD.search = '';
  SD.icon = d.icon || null;
  sdRoot.hidden = false;
  document.body.classList.add('studio-on');
  sdRender();
};
H['studio:refresh'] = (d) => { if (!SD.on) return; SD.d = d; if (d.icon) SD.icon = d.icon; sdRender(); };
H['studio:close'] = () => {
  SD.on = false;
  sdRoot.hidden = true;
  document.body.classList.remove('studio-on');
  $('#root').classList.remove('shooting');
};
H['studio:tune'] = (d) => {
  if (!SD.on || !SD.d) return;
  SD.d.tune = d.tune;
  sdValues();
};
H['studio:kit'] = (d) => {
  if (d.kind === 'status') { SD.kit = d.status; if (!SD.kit.running) SD.prog = null; }
  else if (d.kind === 'start') { SD.prog = { i: 0, n: 0, label: d.mode === 'scan' ? 'Checking…' : 'Starting…', mode: d.mode }; if (SD.kit) SD.kit.running = d.mode; }
  else if (d.kind === 'progress') SD.prog = { i: d.i, n: d.n, label: d.label || d.key, mode: SD.prog && SD.prog.mode };
  else if (d.kind === 'done') { SD.prog = null; SD.kit = d.status || SD.kit; S.v = Date.now(); }
  if (SD.on && SD.tab === 'convert') sdRight();
};

/* icon studio */
H['icon:state'] = (d) => {
  const was = SD.icon && SD.icon.active;
  SD.icon = d;
  $('#sdGuide').hidden = !d.active;
  if (!SD.on) return;
  if (was !== d.active || SD.tab === 'icon') sdRight();
};
H['icon:hide'] = () => $('#root').classList.add('shooting');
H['icon:show'] = () => $('#root').classList.remove('shooting');
H['icon:saved'] = (d) => { if (d.ok) { S.v = Date.now(); if (SD.on) sdLeft(); } };
window.addEventListener('nzc:icon', (e) => {
  SD.shots.unshift({ name: e.detail.name, png: e.detail.png });
  SD.shots = SD.shots.slice(0, 8);
  if (SD.on && SD.tab === 'icon') sdRight();
});

/* ─────────────── render ─────────────── */
function sdRender() { sdLeft(); sdRight(); sdKeys(); }

function sdLeft() {
  const d = SD.d;
  const prev = $('.sd-list', $('#sdLeft'));
  const top = prev ? prev.scrollTop : 0;
  const all = arr(d.chains);
  const q = SD.search.trim().toLowerCase();
  const rows = all.filter((c) => !q || c.label.toLowerCase().includes(q) || c.key.toLowerCase().includes(q));
  const fitted = all.filter((c) => c.fitted && c.fitted.worn).length;
  const busy = SD.icon && SD.icon.batch;
  $('#sdLeft').innerHTML = `<div class="ch-frame"><div class="ch-in sd-in">
    <div class="sd-head"><div class="mark sm"></div><div class="sd-ht"><b>Chain Studio</b><span>${all.length} chain${all.length === 1 ? '' : 's'} · ${fitted} fitted on the ${d.female ? 'female' : 'male'} body</span></div><span class="ver">v1.0.0</span></div>
    <label class="field">${icon('search')}<input id="sdSearch" placeholder="Search chains" value="${esc(SD.search)}"></label>
    <div class="sd-list">${rows.length ? rows.map((c) => {
      const v0 = arr(c.variants)[0] || {};
      return `<button class="sd-row ${c.key === d.current ? 'on' : ''}" data-sd="pick" data-v="${esc(c.key)}" ${busy ? 'disabled' : ''}>
        <span class="th">${chainImg(v0.prop, 'gem')}</span>
        <span class="sd-rt"><b>${esc(c.label)}</b><span>${c.origin === 'server' ? 'clothing pack' : c.origin === 'config' ? 'config.lua' : 'converted'} · ${arr(c.variants).length} texture${arr(c.variants).length === 1 ? '' : 's'}</span></span>
        <span class="sd-flags"><span class="sd-flag ${c.fitted.worn ? 'on' : ''}" title="Neck fit saved">N</span><span class="sd-flag ${c.fitted.hold ? 'on' : ''}" title="Hand fit saved">H</span></span></button>`;
    }).join('') : `<div class="empty">${icon(all.length ? 'search' : 'folder')}${all.length ? 'Nothing matches' : 'No chains yet.<br>Put chain clothing in the chains/ folder and press Build in the Convert tab.'}</div>`}</div>
  </div></div>`;
  const list = $('.sd-list', $('#sdLeft'));
  if (list) list.scrollTop = top;
}

function chip(attrs, label, on, dis) { return `<button class="sd-chip ${on ? 'on' : ''}" ${attrs} ${dis ? 'disabled' : ''}>${label}</button>`; }

function sdRight() {
  const d = SD.d, c = cur();
  const busy = SD.icon && SD.icon.batch;
  const v = c && arr(c.variants).find((x) => x.letter === d.variant);
  const tabs = [['fit', 'Fit'], ['look', 'Look'], ['icon', 'Icon'], ['convert', 'Convert']];
  let body = '';
  if (!c && SD.tab !== 'convert') body = `<div class="card empty">${icon('folder')}Convert a chain first (Convert tab).</div>`;
  else if (SD.tab === 'fit') body = sdFit(c);
  else if (SD.tab === 'look') body = sdLook(c);
  else if (SD.tab === 'icon') body = sdIcon(c);
  else body = sdConvert();

  $('#sdRight').innerHTML = `<div class="ch-frame"><div class="ch-in sd-in">
    <div class="sd-head"><div class="sd-ht"><b>${c ? esc(c.label) : 'Chain Studio'}</b><span>${c ? `${d.female ? 'Female' : 'Male'} body · texture ${esc((d.variant || 'a').toUpperCase())}${v && v.label ? ` (${esc(v.label)})` : ''} of ${arr(c.variants).length}` : '—'}</span></div>
      <button class="pill-close" data-sd="close" ${busy ? 'disabled' : ''}>Close</button></div>
    <div class="seg sd-seg">${tabs.map(([k, l]) => `<button class="${SD.tab === k ? 'on' : ''}" data-sd="tab" data-v="${k}" ${busy ? 'disabled' : ''}>${l}</button>`).join('')}</div>
    ${c && arr(c.variants).length > 1 && SD.tab !== 'convert' ? `<div class="sd-tex">${arr(c.variants).map((x) => `<button class="${x.letter === d.variant ? 'on' : ''}" data-sd="variant" data-v="${x.letter}" ${busy ? 'disabled' : ''}>${esc(x.label || x.letter.toUpperCase())}</button>`).join('')}</div>` : ''}
    <div class="sd-scroll">${body}</div>
  </div></div>`;
  sdValues();
}

function sdFit(c) {
  const d = SD.d, t = d.tune || { pos: {}, rot: {} };
  const hold = d.mode === 'hold';
  const groups = {};
  arr(d.bones).forEach((b) => { (groups[b.group] = groups[b.group] || []).push(b); });
  const bone = arr(d.bones).find((b) => b.id === t.bone);
  return `
    <div class="seg sd-seg">${[['worn', 'On the neck'], ['hold', 'In the hand']].map(([k, l]) => `<button class="${d.mode === k ? 'on' : ''}" data-sd="mode" data-v="${k}">${icon(k === 'worn' ? 'gem' : 'hand')}${l}</button>`).join('')}</div>
    <div class="card sd-card">
      <div class="sd-ch">Start from <em>${hold ? 'then nudge it into the hand' : 'converted chains: From clothing'}</em></div>
      <div class="sd-chips">${arr(d.presets).map((p) => chip(`data-sd="preset" data-v="${p.key}"`, esc(p.label), false, p.from === 'clothing' && !c.hasCentre)).join('')}</div>
      ${!hold ? `<button class="btn sm" data-sd="fitAll">${icon('wand')}From clothing for every unfitted chain</button>` : ''}
    </div>
    ${hold ? `<div class="card sd-card"><div class="sd-ch">Pose <em>preview only · default is Config.Hold.Anim</em></div>
      <div class="sd-chips">${arr(d.anims).map((a) => chip(`data-sd="pose" data-v="${a.key}"`, esc(a.label), a.key === d.holdAnim)).join('')}</div></div>` : ''}
    <div class="card sd-card">
      <div class="sd-ch">Move <em>character's left / right, forward / back, up / down</em></div>
      <div class="pad">
        <button data-move="r" data-s="-1">${icon('left')}Left</button><button data-move="f" data-s="1">${icon('up')}Forward</button><button data-move="r" data-s="1">Right${icon('right')}</button>
        <button data-move="u" data-s="-1">${icon('down')}Down</button><button data-move="f" data-s="-1">${icon('down')}Back</button><button data-move="u" data-s="1">${icon('up')}Up</button>
      </div>
      <div class="steps"><span>Step</span>${MOVES.map(([v, l]) => chip(`data-sd="mstep" data-v="${v}"`, l, SD.move === v)).join('')}</div>
    </div>
    <div class="card sd-card">
      <div class="sd-ch">Rotate <em>around the chain's own centre</em></div>
      <div class="pad">
        <button data-rot="yaw" data-s="-1">${icon('rotate')}Turn −</button><button data-rot="pitch" data-s="-1">${icon('tilt')}Tilt −</button><button data-rot="roll" data-s="-1">${icon('tilt')}Lean −</button>
        <button data-rot="yaw" data-s="1">${icon('rotate')}Turn +</button><button data-rot="pitch" data-s="1">${icon('tilt')}Tilt +</button><button data-rot="roll" data-s="1">${icon('tilt')}Lean +</button>
      </div>
      <div class="steps"><span>Step</span>${ROTS.map(([v, l]) => chip(`data-sd="rstep" data-v="${v}"`, l, SD.rot === v)).join('')}</div>
    </div>
    <div class="card sd-card">
      <div class="sd-ch">Bone <em>${bone ? esc(bone.label) : t.bone}</em></div>
      ${Object.entries(groups).map(([g, list]) => `<div class="sd-chips">${list.map((b) => chip(`data-sd="bone" data-v="${b.id}"`, esc(b.label), b.id === t.bone)).join('')}</div>`).join('')}
    </div>
    <div class="card sd-card">
      <div class="sd-ch">Exact values <span class="sd-calib"><span class="dot ${d.calibrated ? 'on' : 'warn'}"></span>${d.calibrated ? 'calibrated' : 'measured mode'}</span></div>
      <div class="vals">${['x', 'y', 'z'].map((k) => `<label>pos ${k}<input data-val="pos" data-k="${k}" value="${n4(t.pos[k])}"></label>`).join('')}
        ${['x', 'y', 'z'].map((k) => `<label>rot ${k}<input data-val="rot" data-k="${k}" value="${n2(t.rot[k])}"></label>`).join('')}</div>
      <div class="sd-row3"><button class="btn sm" data-sd="copy">${icon('copy')}config.lua</button><button class="btn sm" data-sd="revert">${icon('undo')}Last saved</button><button class="btn sm" data-sd="default">${icon('undo')}Default</button></div>
    </div>
    <div class="card sd-card">
      <div class="sd-ch">Camera</div>
      <div class="sd-chips">${[['front', 'Front'], ['left', 'Left'], ['right', 'Right'], ['back', 'Back'], ['top', 'Top']].map(([k, l]) => chip(`data-sd="cam" data-v="${k}"`, l)).join('')}
        ${chip('data-sd="focus"', `${icon('eye')}Follow chain`, d.cam && d.cam.focus > 0.5)}</div>
    </div>
    <div class="sd-foot">
      <button class="btn teal" data-sd="save">${icon('save')}Save ${hold ? 'hand' : 'neck'} fit · ${d.female ? 'female' : 'male'}</button>
      <button class="btn sm red" data-sd="clearFit" title="Forget the saved fit">${icon('x')}</button>
    </div>`;
}

function sdLook(c) {
  return `
    <div class="card sd-card">
      <div class="sd-ch">Name <em>what players see</em></div>
      <label class="field">${icon('tag')}<input id="lkLabel" maxlength="48" value="${esc(c.label)}"></label>
      <div class="sd-ch">Value <em>shown on the item</em></div>
      <label class="field"><small>$</small><input id="lkValue" type="number" min="0" value="${+c.value || 0}"></label>
      ${arr(c.variants).length > 1 ? `<div class="sd-ch">Textures <em>Gold, Silver, Iced …</em></div>
        ${arr(c.variants).map((v) => `<label class="field"><small>${v.letter.toUpperCase()}</small><input data-vl="${v.letter}" maxlength="24" placeholder="Texture ${v.letter.toUpperCase()}" value="${esc(v.label || '')}"></label>`).join('')}` : ''}
      <button class="btn teal" data-sd="look">${icon('save')}Save</button>
    </div>
    <div class="card sd-card">
      <div class="sd-ch">Try it <em>texture ${esc((SD.d.variant || 'a').toUpperCase())}</em></div>
      <button class="btn" data-sd="give">${icon('gift')}Put one in my pockets</button>
      <div class="sd-note">Key <b>${esc(c.key)}</b> · /givechain id "${esc(c.label)}"</div>
    </div>`;
}

function sdIcon(c) {
  const ic = SD.icon || {};
  if (!ic.active) {
    return `${ic.hasScreenshot === false ? `<div class="card sd-warn">${icon('alert')}<span><b>screenshot-basic</b> isn't running. chainkit's drawn icons are used until you take real ones.</span></div>` : ''}
      <div class="card sd-card"><div class="sd-ch">Icon studio <em>${ic.size || 512}px transparent PNG</em></div>
        <div class="sd-note">The chain floats in a lit chroma box under the map. Frame it, then shoot this one or every chain (every texture). Saved as <b>${esc((arr(c.variants).find((x) => x.letter === SD.d.variant) || {}).prop || '')}.png</b> in icons/ and ox_inventory/web/images.</div>
        <button class="btn teal" data-sd="iconOn" ${ic.hasScreenshot === false ? 'disabled' : ''}>${icon('camera')}Enter icon studio</button></div>`;
  }
  const b = ic.batch, o = ic.orbit || {};
  const near = (y, e) => Math.abs(((o.yaw - y + 540) % 360) - 180) < 3 && Math.abs(o.elev - e) < 3;
  return `
    <div class="card sd-card"><div class="sd-ch">Backdrop <em>pick one the chain doesn't use</em></div>
      <div class="sd-chips">${CHROMA.map(([k, col]) => chip(`data-sd="chroma" data-v="${k}"`, `<span class="sd-sw" style="background:${col}"></span>${k}`, ic.chroma === k, b)).join('')}</div></div>
    <div class="card sd-card"><div class="sd-ch">Angle <em>or drag the view</em></div>
      <div class="sd-chips">${ANGLES.map(([l, y, e]) => chip(`data-sd="angle" data-yaw="${y}" data-elev="${e}"`, l, near(y, e), b)).join('')}</div>
      <div class="sd-axis"><span>Zoom</span><input type="range" id="icZoom" min="0.4" max="3" step="0.05" value="${o.zoom || 1}" ${b ? 'disabled' : ''}><b>${n2(o.zoom || 1)}</b></div></div>
    ${b ? `<div class="card sd-card sd-prog"><div class="sd-pt"><span>Shooting every chain</span><b>${b.i} / ${b.n}</b></div>
        <div class="sd-bar"><i style="width:${b.n ? (b.i / b.n) * 100 : 0}%"></i></div><button class="btn sm red" data-sd="iconCancel">${icon('x')}Stop</button></div>`
      : `<div class="sd-row2"><button class="btn teal" data-sd="shoot">${icon('camera')}This chain</button><button class="btn" data-sd="batch">${icon('box')}Every chain</button></div>`}
    ${SD.shots.length ? `<div class="card sd-card"><div class="sd-ch">Last shots</div><div class="sd-shots">${SD.shots.map((s) => `<div class="sd-shot"><img src="${s.png}" alt=""></div>`).join('')}</div></div>` : ''}
    <button class="btn" data-sd="iconOff" ${b ? 'disabled' : ''}>${icon('left')}Back to fitting</button>`;
}

function sdConvert() {
  const k = SD.kit;
  if (!k) return `<div class="card empty">${icon('rotate')}Asking the server…</div>`;
  const p = SD.prog, running = !!k.running;
  const names = (list, tag, cls) => arr(list).map((x) => `<div class="${cls}"><em>${tag}</em>${esc(x.label || x.key || x)}${x.variants > 1 ? ` · ${x.variants} textures` : ''}</div>`).join('');
  const todo = arr(k.new).length + arr(k.changed).length + arr(k.removed).length;
  return `
    ${!k.enabled ? `<div class="card sd-warn">${icon('alert')}<span>The converter is off (Config.Convert.Enabled).</span></div>` : ''}
    ${k.enabled && !k.kit ? `<div class="card sd-warn">${icon('alert')}<span><b>chainkit</b> isn't installed for this server (${esc(k.platform || '?')}). Put it in tools/chainkit (see the README).</span></div>` : ''}
    <div class="sd-stats">
      <div><b>${k.chains || 0}</b><span>chains</span></div>
      <div class="${arr(k.new).length ? 'hot' : ''}"><b>${arr(k.new).length}</b><span>new</span></div>
      <div class="${arr(k.changed).length ? 'hot' : ''}"><b>${arr(k.changed).length}</b><span>changed</span></div>
      <div class="${arr(k.removed).length ? 'bad' : ''}"><b>${arr(k.removed).length}</b><span>removed</span></div>
    </div>
    ${todo ? `<div class="card sd-card"><div class="sd-ch">Waiting to build</div><div class="sd-names">
      ${names(k.new, 'NEW', 't-success')}${names(k.changed, 'CHANGED', 't-warning')}${names(k.removed, 'GONE', 't-error')}</div></div>` : ''}
    ${p ? `<div class="card sd-card sd-prog"><div class="sd-pt"><span>${p.mode === 'scan' ? 'Checking' : p.mode === 'icons' ? 'Drawing icons' : 'Converting'}</span><b>${esc(p.label || '')}</b></div>
      <div class="sd-bar"><i style="width:${p.n ? (p.i / p.n) * 100 : 8}%"></i></div><div class="sd-note">${p.n ? `${p.i} of ${p.n}` : 'working…'}</div></div>` : ''}
    <div class="card sd-card">
      <div class="sd-ch">Convert</div>
      <div class="sd-row2">
        <button class="btn" data-sd="kit" data-v="scan" ${running || !k.kit ? 'disabled' : ''}>${icon('search')}Check again</button>
        <button class="btn teal" data-sd="kit" data-v="build" ${running || !k.kit ? 'disabled' : ''}>${icon('bolt')}Build${todo ? ` (${todo})` : ''}</button>
        <button class="btn" data-sd="kit" data-v="rebuild" ${running || !k.kit ? 'disabled' : ''}>${icon('rotate')}Rebuild all</button>
        <button class="btn" data-sd="kit" data-v="icons" ${running || !k.kit ? 'disabled' : ''}>${icon('camera')}Redraw icons</button>
      </div>
      <div class="sd-note">Drop chains in <b>${esc(k.folder || 'chains')}/&lt;Chain Name&gt;/</b>: the <b>.ydd</b> and every <b>_diff_</b> .ytd texture. One prop is made per texture into <b>${esc(k.out || 'nayzeee-chainprops')}</b>, which restarts by itself.</div>
    </div>`;
}

function sdKeys() {
  const ks = [['↑ ↓ ← →', 'move'], ['PGUP PGDN', 'fwd / back'], ['Q E', 'turn'], ['R F', 'tilt'], ['Z C', 'lean'], ['SHIFT', '×5'], ['ALT', 'fine'], ['CTRL S', 'save'], ['ESC', 'close']];
  $('#sdKeys').innerHTML = ks.map(([k, l]) => `<span>${k.split(' ').map((x) => `<span class="kc">${x}</span>`).join('')}${l}</span>`).join('');
}

/* exact values without stealing focus mid-typing */
function sdValues() {
  const t = SD.d && SD.d.tune;
  if (!t) return;
  $$('[data-val]', $('#sdRight')).forEach((el) => {
    if (document.activeElement === el) return;
    const v = t[el.dataset.val] && t[el.dataset.val][el.dataset.k];
    el.value = el.dataset.val === 'pos' ? n4(v) : n2(v);
  });
}

/* ─────────────── input ─────────────── */
function stepMul(e) { return e && e.shiftKey ? 5 : e && e.altKey ? 0.2 : 1; }
const doMove = (axis, s, e) => post('studio:move', { axis, amount: s * SD.move * stepMul(e) });
const doRot = (axis, s, e) => post('studio:rotate', { axis, deg: s * SD.rot * stepMul(e) });

let repeat = null;
function stopRepeat() { clearTimeout(repeat); clearInterval(repeat); repeat = null; }
sdRoot.addEventListener('mousedown', (e) => {
  const m = e.target.closest('[data-move],[data-rot]');
  if (!m || e.button !== 0) return;
  const fire = () => (m.dataset.move ? doMove(m.dataset.move, +m.dataset.s, e) : doRot(m.dataset.rot, +m.dataset.s, e));
  fire();
  stopRepeat();
  repeat = setTimeout(() => { repeat = setInterval(fire, 70); }, 350);
});
window.addEventListener('mouseup', stopRepeat);

sdRoot.addEventListener('click', (e) => {
  const b = e.target.closest('[data-sd]');
  if (!b || b.disabled) return;
  const v = b.dataset.v;
  switch (b.dataset.sd) {
    case 'close': return post('studio:close');
    case 'pick': return post('studio:select', { key: v });
    case 'variant': return post('studio:variant', { letter: v });
    case 'tab':
      SD.tab = v;
      if (v !== 'icon' && SD.icon && SD.icon.active) post('icon:toggle', { on: false });
      if (v === 'convert') post('studio:kit', { mode: 'status' });
      return sdRight();
    case 'mode': return post('studio:mode', { mode: v });
    case 'preset': return post('studio:preset', { key: v });
    case 'fitAll': return post('studio:fitAll');
    case 'pose': return post('studio:pose', { key: v });
    case 'mstep': SD.move = +v; return sdRight();
    case 'rstep': SD.rot = +v; return sdRight();
    case 'bone': return post('studio:bone', { bone: +v });
    case 'revert': return post('studio:revert');
    case 'default': return post('studio:default');
    case 'cam': return post('studio:cam', { preset: v });
    case 'focus': SD.d.cam.focus = SD.d.cam.focus > 0.5 ? 0 : 1; post('studio:cam', { focus: SD.d.cam.focus > 0.5 }); return sdRight();
    case 'save': return post('studio:save');
    case 'clearFit': return post('studio:clearFit');
    case 'copy': return copyConfig();
    case 'look': {
      const vl = {};
      $$('[data-vl]', $('#sdRight')).forEach((el) => { vl[el.dataset.vl] = el.value.trim(); });
      return post('studio:look', { label: $('#lkLabel').value.trim(), value: +$('#lkValue').value || 0, vlabels: vl });
    }
    case 'give': return post('studio:give');
    case 'iconOn': return post('icon:toggle', { on: true });
    case 'iconOff': return post('icon:toggle', { on: false });
    case 'chroma': return post('icon:chroma', { color: v });
    case 'angle': return post('icon:orbit', { yaw: +b.dataset.yaw, elev: +b.dataset.elev });
    case 'shoot': return post('icon:capture');
    case 'batch': return post('icon:batch');
    case 'iconCancel': return post('icon:cancel');
    case 'kit': SD.prog = { i: 0, n: 0, label: '', mode: v }; sdRight(); return post('studio:kit', { mode: v });
  }
});

sdRoot.addEventListener('input', (e) => {
  if (e.target.id === 'sdSearch') { SD.search = e.target.value; sdLeft(); const s = $('#sdSearch'); s.focus(); s.setSelectionRange(s.value.length, s.value.length); }
  if (e.target.id === 'icZoom') post('icon:zoom', { set: +e.target.value });
});
sdRoot.addEventListener('change', (e) => {
  const el = e.target.closest('[data-val]');
  if (!el) return;
  const t = SD.d.tune, kind = el.dataset.val;
  const vals = {};
  $$(`[data-val="${kind}"]`, $('#sdRight')).forEach((x) => { vals[x.dataset.k] = parseFloat(x.value); });
  post(kind === 'pos' ? 'studio:pos' : 'studio:rot', { [kind]: Object.assign({}, t[kind], vals) });
});

function copyConfig() {
  const t = SD.d.tune, f = (o) => `{ x = ${n4(o.x)}, y = ${n4(o.y)}, z = ${n4(o.z)} }`;
  const txt = `${SD.d.mode} = { bone = ${t.bone}, pos = ${f(t.pos)}, rot = ${f(t.rot)} },`;
  const ta = document.createElement('textarea');
  ta.value = txt; document.body.appendChild(ta); ta.select();
  try { document.execCommand('copy'); post('studio:copied'); } catch (err) { /* no clipboard */ }
  ta.remove();
}

/* orbit + zoom on the free area */
const orbit = $('#sdOrbit');
let drag = null;
orbit.addEventListener('mousedown', (e) => { drag = { x: e.clientX, y: e.clientY }; orbit.classList.add('drag'); });
window.addEventListener('mousemove', (e) => {
  if (!drag) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  if (Math.abs(dx) + Math.abs(dy) < 2) return;
  drag = { x: e.clientX, y: e.clientY };
  if (SD.icon && SD.icon.active) post('icon:orbit', { dx, dy });
  else post('studio:cam', { dx, dy });
});
window.addEventListener('mouseup', () => { drag = null; orbit.classList.remove('drag'); });
orbit.addEventListener('wheel', (e) => {
  if (SD.icon && SD.icon.active) post('icon:zoom', { delta: e.deltaY > 0 ? 0.08 : -0.08 });
  else post('studio:cam', { zoom: e.deltaY > 0 ? 0.08 : -0.08 });
}, { passive: true });

/* keyboard */
window.addEventListener('keydown', (e) => {
  if (!SD.on) return;
  const typing = /INPUT|TEXTAREA/.test((document.activeElement || {}).tagName || '');
  if (e.key === 'Escape') {
    if (typing) return document.activeElement.blur();
    if (SD.icon && SD.icon.active) return post('icon:toggle', { on: false });
    return post('studio:close');
  }
  if (typing || SD.tab !== 'fit' || (SD.icon && SD.icon.active)) return;
  if (e.ctrlKey && (e.key === 's' || e.key === 'S')) { e.preventDefault(); return post('studio:save'); }
  const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
  const map = {
    ArrowLeft: () => doMove('r', -1, e), ArrowRight: () => doMove('r', 1, e),
    ArrowUp: () => doMove('u', 1, e), ArrowDown: () => doMove('u', -1, e),
    PageUp: () => doMove('f', 1, e), PageDown: () => doMove('f', -1, e),
    q: () => doRot('yaw', -1, e), e: () => doRot('yaw', 1, e),
    r: () => doRot('pitch', 1, e), f: () => doRot('pitch', -1, e),
    z: () => doRot('roll', -1, e), c: () => doRot('roll', 1, e),
  };
  if (map[k]) { e.preventDefault(); map[k](); }
});
