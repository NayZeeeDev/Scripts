/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V3 · Wig Studio
   Built like the nayzeee-backpack icon studio: the head floats in a lit
   chroma box under the map, you frame it with the orbit camera between the
   two panels, and each shot is keyed here (keyer.js) into a small PNG.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const SD = {
  on: false, model: 'f', d: 0, t: 0, list: [], names: {}, shots: new Set(), thumbs: {}, recent: [],
  chroma: 'green', orbit: { yaw: 200, elev: 8, zoom: 1, lift: 0 }, batch: null, screenshot: true,
  size: 256, search: '', textures: false, missing: true, v: Date.now(), saveToInventory: true,
};
const sdRoot = $('#studio');

const shotName = (m, d, t) => `wig_${m}_${d}_${t}`;
const shotKey = (m, d, t) => `${m}/${d}_${t}`;
function styleName(m, d, t) {
  return SD.names[`${m}:${d}:${t}`] || SD.names[`${m}:${d}`] || '';
}
function thumbFor(m, d, t) {
  const n = shotName(m, d, t);
  if (SD.thumbs[n]) return SD.thumbs[n];
  if (SD.shots.has(shotKey(m, d, t))) return `../shots/${n}.png?v=${SD.v}`;
  return null;
}
const sdImg = (src) => src
  ? `<img src="${src}" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-image'}))">`
  : '<i class="fa-solid fa-user"></i>';

/* ─────────────── open / close ─────────────── */
function studioOpen(d) {
  S.view = 'studio';
  SD.on = true;
  SD.names = d.names || {};
  SD.shots = new Set(arr(d.shots));
  SD.size = d.size || 256;
  SD.screenshot = d.screenshot !== false;
  SD.saveToInventory = d.saveToInventory !== false;
  SD.textures = !!d.allTextures;
  SD.search = '';
  sdRoot.hidden = false;
  sdRoot.classList.remove('shooting');
  sdRender();
}
function studioClose(silent) {
  if (!SD.on) return;
  SD.on = false;
  S.view = null;
  sdRoot.hidden = true;
  if (!silent) post('st:close');
}

// game → studio state. Orbit-only changes don't rebuild the panels (that would drop a slider mid-drag).
const sdSig = () => JSON.stringify([SD.model, SD.d, SD.t, SD.list.length, SD.chroma, SD.batch, SD.screenshot]);
function studioState(d) {
  const before = sdSig();
  if (d.model) SD.model = d.model;
  if (d.d !== undefined) SD.d = d.d;
  if (d.t !== undefined) SD.t = d.t;
  if (d.list) SD.list = arr(d.list);
  if (d.chroma) SD.chroma = d.chroma;
  if (d.orbit) SD.orbit = d.orbit;
  SD.batch = d.batch || null;
  if (d.screenshot !== undefined) SD.screenshot = d.screenshot;
  if (!SD.on) return;
  if (sdSig() !== before) sdRender();
  else sdOrbitUi();
}

const sdNear = (y, e) => Math.abs(((SD.orbit.yaw - y + 540) % 360) - 180) < 3 && Math.abs(SD.orbit.elev - e) < 3;
function sdOrbitUi() {
  const o = SD.orbit;
  $$('[data-sd="angle"]', sdRoot).forEach((b) => b.classList.toggle('on', sdNear(+b.dataset.yaw, +b.dataset.elev)));
  [['sdZoom', 'zoom'], ['sdLift', 'lift']].forEach(([id, k]) => {
    const el = $('#' + id);
    if (!el) return;
    if (document.activeElement !== el) el.value = o[k];
    $('#' + id + 'V').textContent = (+o[k]).toFixed(2);
  });
}

/* ─────────────── render ─────────────── */
function sdRender() {
  sdLeft();
  sdRight();
}

function sdLeft() {
  const prev = $('.sd-list', $('#sdLeft'));
  if (prev) sdLeft.top = prev.scrollTop;
  const m = SD.model, q = SD.search.trim().toLowerCase();
  const done = SD.list.filter((x) => SD.shots.has(shotKey(m, x.d, 0))).length;
  const rows = SD.list.filter((x) => {
    if (!q) return true;
    return String(x.d) === q || styleName(m, x.d, 0).toLowerCase().includes(q);
  });
  $('#sdLeft').innerHTML = `<div class="ch-frame"><div class="ch-in sd-in">
    <div class="sd-head"><div class="mark sm"></div><div class="sd-ht"><b>Wig Studio</b><span>${SD.list.length} hairstyles · ${done} photographed</span></div><span class="ver">v${esc(S.cfg.version)}</span></div>
    <div class="seg sd-seg">${[['f', 'Female'], ['m', 'Male']].map(([k, l]) => `<button class="${m === k ? 'on' : ''}" data-sd="model" data-v="${k}" ${SD.batch ? 'disabled' : ''}>${l}</button>`).join('')}</div>
    <label class="field"><i class="fa-solid fa-magnifying-glass"></i><input id="sdSearch" placeholder="Search by name or number" value="${esc(SD.search)}"></label>
    <div class="sd-list">${rows.length ? rows.map((x) => {
      const nm = styleName(m, x.d, 0), has = SD.shots.has(shotKey(m, x.d, 0)) || !!SD.thumbs[shotName(m, x.d, 0)];
      return `<button class="sd-row ${x.d === SD.d ? 'on' : ''}" data-sd="pick" data-v="${x.d}" ${SD.batch ? 'disabled' : ''}>
        <span class="sd-th">${sdImg(thumbFor(m, x.d, 0))}</span>
        <span class="sd-rt"><b>${nm ? esc(nm) : `Hairstyle ${x.d}`}</b><span>#${x.d} · ${x.n} texture${x.n === 1 ? '' : 's'}${x.bald ? ' · bald' : ''}</span></span>
        <span class="dot ${has ? 'on' : ''}"></span></button>`;
    }).join('') : '<div class="empty"><i class="fa-solid fa-magnifying-glass"></i>Nothing matches</div>'}</div>
  </div></div>`;
  const list = $('.sd-list', $('#sdLeft'));
  if (list) list.scrollTop = sdLeft.top || 0;
  const on = $('.sd-row.on', list);
  if (on) on.scrollIntoView({ block: 'nearest' });
}

function sdRight() {
  const m = SD.model, cur = SD.list.find((x) => x.d === SD.d) || { d: SD.d, n: 1 };
  const nk = `${m}:${SD.d}`, nm = SD.names[nk] || '';
  const b = SD.batch, busy = !!b;
  const o = SD.orbit;
  const chip = (attrs, label, on) => `<button class="sd-chip ${on ? 'on' : ''}" ${attrs} ${busy ? 'disabled' : ''}>${label}</button>`;
  const near = sdNear;
  $('#sdRight').innerHTML = `<div class="ch-frame"><div class="ch-in sd-in">
    <div class="sd-head"><div class="sd-ht"><b>${nm ? esc(nm) : `Hairstyle ${SD.d}`}</b><span>${m === 'm' ? 'Male' : 'Female'} · #${SD.d} · texture ${SD.t + 1} of ${cur.n}</span></div>
      <button class="pill-close" data-sd="close" ${busy ? 'disabled' : ''}>Close</button></div>
    <div class="sd-scroll">
      ${SD.screenshot ? '' : `<div class="card sd-warn"><i class="fa-solid fa-triangle-exclamation"></i><span><b>screenshot-basic</b> isn't running. You can still frame and name hairstyles.</span></div>`}

      <div class="card sd-card">
        <div class="sd-ch">Hairstyle <em>the name every wig made from it uses</em></div>
        <div class="sd-name"><label class="field"><i class="fa-solid fa-pen"></i><input id="sdName" maxlength="40" placeholder="Name this hairstyle" value="${esc(nm)}" ${busy ? 'disabled' : ''}></label>
          <button class="btn teal sm" data-sd="name" ${busy ? 'disabled' : ''}><i class="fa-solid fa-floppy-disk"></i>Save</button></div>
        <div class="sd-step">
          <button class="btn sm" data-sd="step" data-v="-1" ${busy ? 'disabled' : ''}><i class="fa-solid fa-chevron-left"></i>Prev</button>
          <div class="sd-tex">${Array.from({ length: Math.min(cur.n, 12) }, (_, i) => `<button class="${i === SD.t ? 'on' : ''}" data-sd="tex" data-v="${i}" ${busy ? 'disabled' : ''}>${i + 1}</button>`).join('')}${cur.n > 12 ? `<span>+${cur.n - 12}</span>` : ''}</div>
          <button class="btn sm" data-sd="step" data-v="1" ${busy ? 'disabled' : ''}>Next<i class="fa-solid fa-chevron-right"></i></button>
        </div>
      </div>

      <div class="card sd-card">
        <div class="sd-ch">Backdrop <em>pick one the hair doesn't use</em></div>
        <div class="sd-chips">${[['green', 'Green', '#00b140'], ['magenta', 'Magenta', '#ff00ff'], ['blue', 'Blue', '#0047bb']].map(([k, l, c]) =>
          chip(`data-sd="chroma" data-v="${k}"`, `<i class="sd-sw" style="background:${c}"></i>${l}`, SD.chroma === k)).join('')}</div>
      </div>

      <div class="card sd-card">
        <div class="sd-ch">Framing <em>drag to orbit · scroll to zoom</em></div>
        <div class="sd-chips">
          ${chip('data-sd="angle" data-yaw="200" data-elev="8"', 'Three quarter', near(200, 8))}
          ${chip('data-sd="angle" data-yaw="180" data-elev="4"', 'Front', near(180, 4))}
          ${chip('data-sd="angle" data-yaw="270" data-elev="4"', 'Side', near(270, 4))}
          ${chip('data-sd="angle" data-yaw="0" data-elev="8"', 'Back', near(0, 8))}
          ${chip('data-sd="angle" data-yaw="200" data-elev="40"', 'High', near(200, 40))}
        </div>
        <div class="sd-axis"><span>Zoom</span><input type="range" id="sdZoom" min="0.4" max="3" step="0.02" value="${o.zoom}" ${busy ? 'disabled' : ''}><b id="sdZoomV">${(+o.zoom).toFixed(2)}</b></div>
        <div class="sd-axis"><span>Height</span><input type="range" id="sdLift" min="-0.5" max="0.25" step="0.01" value="${o.lift}" ${busy ? 'disabled' : ''}><b id="sdLiftV">${(+o.lift).toFixed(2)}</b></div>
      </div>

      <div class="card sd-card">
        <div class="sd-ch">Capture <em>${SD.size} × ${SD.size} png</em></div>
        <div class="sd-row2">
          <button class="btn" data-sd="shoot" ${busy || !SD.screenshot ? 'disabled' : ''}><i class="fa-solid fa-camera"></i>This hairstyle</button>
          <button class="btn teal" data-sd="batch" ${busy || !SD.screenshot ? 'disabled' : ''}><i class="fa-solid fa-camera-retro"></i>Every hairstyle</button>
        </div>
        <label class="sd-check"><input type="checkbox" id="sdTex" ${SD.textures ? 'checked' : ''} ${busy ? 'disabled' : ''}><span>Every texture too (saved as wig_${m}_12_1.png …)</span></label>
        <label class="sd-check"><input type="checkbox" id="sdMissing" ${SD.missing ? 'checked' : ''} ${busy ? 'disabled' : ''}><span>Skip hairstyles that already have a photo</span></label>
        ${SD.confirm && !busy ? `<div class="sd-confirm"><p>Every ${m === 'm' ? 'male' : 'female'} hairstyle${SD.textures ? ' and texture' : ''} gets photographed with this framing and backdrop${SD.missing ? ', skipping ones that already have a photo' : ''}. Backspace stops it.</p>
          <div class="sd-row2"><button class="btn ghost sm" data-sd="nobatch">Cancel</button><button class="btn teal sm" data-sd="gobatch"><i class="fa-solid fa-play"></i>Start</button></div></div>` : ''}
        ${busy ? `<div class="sd-prog"><div class="sd-pt"><span>Shooting ${b.i} of ${b.n}</span><b>${Math.round((b.i / Math.max(1, b.n)) * 100)}%</b></div>
          <div class="sd-bar"><i style="width:${(b.i / Math.max(1, b.n)) * 100}%"></i></div>
          <button class="btn red sm wide" data-sd="cancel"><i class="fa-solid fa-stop"></i>Stop batch <span class="kc">BACKSPACE</span></button></div>` : ''}
      </div>

      <div class="card sd-card">
        <div class="sd-ch">Recent <em>${SD.saveToInventory ? 'saved to shots/ and ox_inventory' : 'saved to shots/'}</em></div>
        <div class="sd-shots">${SD.recent.length ? SD.recent.map((r) => `<div class="sd-shot ${r.ok === false ? 'bad' : ''}"><img src="${r.png}" alt=""><span>${esc(r.name)}</span></div>`).join('')
          : '<div class="empty" style="grid-column:1/-1;padding:16px"><b>No captures yet</b></div>'}</div>
      </div>
    </div>
    <div class="sd-foot"><span class="kc">ESC</span>Close<span class="kc">BACKSPACE</span>Stop a batch<span class="grow"></span>New photos load after a restart</div>
  </div></div>`;
}

/* ─────────────── input ─────────────── */
sdRoot.addEventListener('click', (e) => {
  const b = e.target.closest('[data-sd]');
  if (!b || b.disabled) return;
  const v = b.dataset.v;
  switch (b.dataset.sd) {
    case 'close': return studioClose();
    case 'model': sdLeft.top = 0; return post('st:model', { m: v });
    case 'pick': return post('st:pick', { d: Number(v), t: 0 });
    case 'tex': return post('st:pick', { d: SD.d, t: Number(v) });
    case 'step': {
      const i = SD.list.findIndex((x) => x.d === SD.d);
      const n = SD.list[clamp(i + Number(v), 0, SD.list.length - 1)];
      if (n) post('st:pick', { d: n.d, t: 0 });
      return;
    }
    case 'chroma': return post('st:chroma', { color: v });
    case 'angle': return post('st:orbit', { yaw: Number(b.dataset.yaw), elev: Number(b.dataset.elev) });
    case 'name': {
      const val = $('#sdName').value.trim();
      SD.names[`${SD.model}:${SD.d}`] = val || undefined;
      post('st:name', { key: `${SD.model}:${SD.d}`, name: val });
      return sdRender();
    }
    case 'shoot': return post('st:capture');
    case 'batch': SD.confirm = true; return sdRight();
    case 'nobatch': SD.confirm = false; return sdRight();
    case 'gobatch': SD.confirm = false; return post('st:batch', { textures: SD.textures, missing: SD.missing });
    case 'cancel': return post('st:cancel');
  }
});
sdRoot.addEventListener('input', (e) => {
  const t = e.target;
  if (t.id === 'sdSearch') { SD.search = t.value; sdLeft(); const s = $('#sdSearch'); s.focus(); s.setSelectionRange(s.value.length, s.value.length); }
  if (t.id === 'sdZoom') { $('#sdZoomV').textContent = (+t.value).toFixed(2); post('st:zoom', { set: +t.value }); }
  if (t.id === 'sdLift') { $('#sdLiftV').textContent = (+t.value).toFixed(2); post('st:lift', { set: +t.value }); }
});
sdRoot.addEventListener('change', (e) => {
  if (e.target.id === 'sdTex') SD.textures = e.target.checked;
  if (e.target.id === 'sdMissing') SD.missing = e.target.checked;
});

// orbit + zoom on the empty middle of the screen
(function () {
  const c = $('#sdOrbit');
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

function studioKey(e) {
  if (!SD.on || e.type !== 'keydown') return false;
  if (e.target && e.target.tagName === 'INPUT' && e.key !== 'Escape') return true;
  if (e.key === 'Backspace' && SD.batch) { post('st:cancel'); return true; }
  if (e.key === 'Escape') { if (SD.confirm) { SD.confirm = false; sdRight(); } else if (!SD.batch) studioClose(); return true; }
  if (SD.batch) return true;
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    const i = SD.list.findIndex((x) => x.d === SD.d);
    const n = SD.list[clamp(i + (e.key === 'ArrowDown' ? 1 : -1), 0, SD.list.length - 1)];
    if (n) post('st:pick', { d: n.d, t: 0 });
    return true;
  }
  return false;
}

/* ─────────────── shooting ─────────────── */
// hide every bit of UI for the frame the screenshot is taken on
function studioHide() { $('#root').classList.add('shooting'); }
function studioShow() { $('#root').classList.remove('shooting'); }

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
  if (d.ok && d.key) SD.shots.add(d.key);
  if (SD.on) sdRender();
}
