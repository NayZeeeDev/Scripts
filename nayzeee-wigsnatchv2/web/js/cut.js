/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V3 · first person cutting HUD
   The cursor is the tool. Lua does the raycast onto the head,
   this file draws the tool, the objective and the progress.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const TOOL_SVG = {
  scissors: `<svg viewBox="0 0 64 64" class="tool-svg scissors">
      <g class="blade a"><path d="M30 34 L54 6 Q57 5 56 9 L35 37 Z" fill="#e6ecef" stroke="#9aa3a8" stroke-width="1"/>
        <path d="M30 34 L22 43" stroke="currentColor" stroke-width="4" stroke-linecap="round"/><circle cx="18" cy="49" r="7.5" fill="none" stroke="currentColor" stroke-width="4"/></g>
      <g class="blade b"><path d="M34 34 L10 6 Q7 5 8 9 L29 37 Z" fill="#d4dbdf" stroke="#9aa3a8" stroke-width="1"/>
        <path d="M34 34 L42 43" stroke="currentColor" stroke-width="4" stroke-linecap="round"/><circle cx="46" cy="49" r="7.5" fill="none" stroke="currentColor" stroke-width="4"/></g>
      <circle cx="32" cy="34" r="2.6" fill="#fff" stroke="#9aa3a8"/></svg>`,
  clippers: `<svg viewBox="0 0 64 64" class="tool-svg clippers">
      <rect x="20" y="16" width="24" height="44" rx="10" fill="#1b1e20" stroke="currentColor" stroke-width="2.5"/>
      <rect x="18" y="6" width="28" height="12" rx="3" fill="#dfe6ea" stroke="#9aa3a8"/>
      <path d="M20 6 v-3 M24 6 v-4 M28 6 v-3 M32 6 v-4 M36 6 v-3 M40 6 v-4 M44 6 v-3" stroke="#dfe6ea" stroke-width="1.6"/>
      <rect x="28" y="28" width="8" height="14" rx="2" fill="currentColor" opacity=".85"/>
      <circle cx="32" cy="50" r="2.4" fill="currentColor"/></svg>`,
  razor: `<svg viewBox="0 0 64 64" class="tool-svg razor">
      <path d="M8 26 L44 14 Q50 13 50 19 L50 22 L12 33 Q7 34 8 26 Z" fill="#e8eef1" stroke="#9aa3a8" stroke-width="1.2"/>
      <path d="M12 31 L48 21" stroke="#ffffff" stroke-width="1" opacity=".8"/>
      <circle cx="47" cy="19" r="2" fill="#6b7377"/>
      <path d="M47 19 L60 50 Q61 55 56 54 L44 24" fill="#1b1e20" stroke="currentColor" stroke-width="2.2"/></svg>`,
};

const REGION_LABEL = { top: 'Top', left: 'Left side', right: 'Right side', back: 'Back', brows: 'Eyebrows', beard: 'Beard' };
const REGION_ORDER = ['top', 'left', 'right', 'back', 'brows', 'beard'];
const MODE_HINT = { click: 'Click to interact', hold: 'Hold and move around', stroke: 'Hold and stroke up and down' };

const K = { on: false, d: null, tool: null, holding: false, hover: null, ends: 0, timer: 0 };
const ke = { root: $('#cut'), cursor: $('#cutCursor'), top: $('#cutTop'), tray: $('#cutTray'), obj: $('#cutObj'), side: $('#cutSide') };

function toolDef(id) { return arr(K.d && K.d.tools).find((t) => t.id === id) || {}; }

function cutStart(d) {
  Object.assign(K, { on: true, d, tool: d.tool, holding: false, hover: null, ends: Date.now() + (d.max || 120) * 1000, work: d.work || {} });
  ke.top.innerHTML = `<div class="ch-frame"><div class="ch-in">
      <div class="mark sm"></div>
      <div class="ct-tx"><small>${d.forced ? 'Forced cut' : 'Haircut'}</small><b>${esc(d.name)}</b></div>
      ${d.forced ? `<span class="chip t-error"><i class="fa-solid fa-user-slash"></i>Restrained</span>` : `<span class="chip t-success"><i class="fa-solid fa-handshake"></i>Agreed</span>`}
      <div class="ct-clock"><i class="fa-regular fa-clock"></i><span id="cutClock">2:00</span></div></div></div>`;
  renderTray();
  renderSide();
  ke.root.hidden = false;
  clearInterval(K.timer);
  K.timer = setInterval(() => {
    const s = Math.max(0, Math.round((K.ends - Date.now()) / 1000));
    const el = $('#cutClock'); if (el) el.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }, 500);
  setCursorTool(K.tool);
}

function renderTray() {
  const tools = arr(K.d.tools);
  ke.tray.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="tray-h">Tools</div>
    <div class="tray">${tools.map((t) => `<button class="tray-tool ${t.id === K.tool ? 'on' : ''}" data-tool="${esc(t.id)}">
      <span class="tt-art">${TOOL_SVG[t.icon] || TOOL_SVG.scissors}</span>
      <span class="tt-tx"><b>${esc(t.label)}</b><small>${esc(MODE_HINT[t.mode] || '')}</small></span>
      <span class="kc">${esc(t.key || '')}</span></button>`).join('')}</div></div></div>`;
}

function regionBest(r) {
  const w = (K.work || {})[r] || {};
  let best = 0, by = null;
  for (const t of Object.keys(w)) if ((w[t] || 0) > best) { best = w[t]; by = t; }
  return { best, by, mine: w[K.tool] || 0 };
}

function renderSide() {
  const regions = K.d.regions || {};
  const rows = REGION_ORDER.filter((r) => regions[r] !== undefined).map((r) => {
    const avail = regions[r];
    const b = regionBest(r);
    const hov = K.hover === r ? 'hover' : '';
    return `<div class="rg ${avail ? '' : 'off'} ${hov}">
      <span>${REGION_LABEL[r]}</span>
      ${avail ? `<div class="rg-bar"><i style="width:${Math.round(b.mine)}%"></i></div><small>${Math.round(b.mine)}%</small>` : '<small>-</small>'}
    </div>`;
  }).join('');
  ke.side.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="tray-h">The head</div>
    <div class="rgs">${rows}</div>
    <div class="cut-keys">
      <div><span class="kc">A</span><span class="kc">D</span>Walk around</div>
      <div><span class="kc">W</span><span class="kc">S</span>Height</div>
      <div><span class="kc"><i class="fa-solid fa-computer-mouse"></i></span>Scroll to zoom</div>
    </div>
    <div class="cut-btns">
      <button class="btn red sm" data-cut="cancel"><i class="fa-solid fa-xmark"></i>Stop<span class="kc">ESC</span></button>
      <button class="btn teal sm" data-cut="finish"><i class="fa-solid fa-check"></i>Finish<span class="kc">↵</span></button>
    </div></div></div>`;
}

// the bar from the screenshots: "Fade the sides - Hold and move around" + progress
function renderObjective(o) {
  if (!o) return;
  const b = o.region ? regionBest(o.region) : { mine: 0 };
  const hint = MODE_HINT[o.mode] || '';
  ke.obj.innerHTML = `<div class="obj"><div class="obj-tx"><b>${esc(o.text)}</b>${o.region ? `<span>·</span><em>${esc(hint)}</em>` : ''}</div>
    <div class="obj-bar"><i style="width:${o.region ? Math.round(b.mine) : 0}%"></i></div></div>`;
}

function setCursorTool(tool) {
  const t = toolDef(tool);
  ke.cursor.innerHTML = TOOL_SVG[t.icon] || TOOL_SVG.scissors;
  ke.cursor.dataset.tool = t.icon || 'scissors';
}

function cutUpdate(d) {
  if (!K.on) return;
  K.work = d.work || K.work;
  K.holding = !!d.holding;
  const hover = d.hover || null;
  K.hover = hover && !String(hover).startsWith('x:') ? hover : null;
  ke.cursor.classList.toggle('bad', !!(hover && String(hover).startsWith('x:')));
  ke.cursor.classList.toggle('ok', !!K.hover);
  if (d.tool && d.tool !== K.tool) cutTool({ tool: d.tool });
  renderObjective(d.objective);
  renderSide();
  loopSound('clippers', K.holding && K.tool === 'clippers' && !!K.hover);
}

function cutTool(d) {
  K.tool = d.tool;
  setCursorTool(K.tool);
  renderTray();
  loopSound('clippers', false);
}

function cutFx(d) {
  const c = ke.cursor;
  c.classList.remove('snap'); void c.offsetWidth; c.classList.add('snap');
  if (d.tool === 'scissors') SFX.snip();
  else if (d.tool === 'razor') SFX.razor();
}

function cutEnd() {
  K.on = false;
  clearInterval(K.timer);
  loopSound('clippers', false);
  ke.root.hidden = true;
}

function cutSit(d) {
  const el = $('#cutsit');
  el.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="ti ${d.forced ? 't-error' : 't-success'}"><i class="fa-solid fa-scissors"></i></div>
    <div class="cs-tx"><b>${esc(d.name)} is ${d.forced ? 'going at your head' : 'cutting your hair'}</b><span>${d.forced ? "You can't move. Hope they're good." : 'Hold still.'}</span></div>
    ${d.forced ? '' : '<button class="btn sm ghost" data-cutsit="leave">Get up</button>'}</div></div>`;
  el.hidden = false;
}
function cutSitEnd() { $('#cutsit').hidden = true; }
$('#cutsit').addEventListener('click', (e) => { if (e.target.closest('[data-cutsit]')) post('cutLeave'); });

/* ─────────────── input ─────────────── */
ke.root.addEventListener('mousemove', (e) => {
  ke.cursor.style.transform = `translate(${e.clientX}px, ${e.clientY}px)`;
});
ke.root.addEventListener('mousedown', (e) => {
  if (e.button !== 0 || e.target.closest('button')) return;
  ke.cursor.classList.add('down');
  post('cutMouse', { down: true });
});
addEventListener('mouseup', (e) => {
  if (!K.on || e.button !== 0) return;
  ke.cursor.classList.remove('down');
  post('cutMouse', { down: false });
});
ke.root.addEventListener('wheel', (e) => { post('cutZoom', { delta: Math.sign(e.deltaY) }); }, { passive: true });
ke.root.addEventListener('click', (e) => {
  const t = e.target.closest('[data-tool]');
  if (t) return post('cutTool', { tool: t.dataset.tool });
  const b = e.target.closest('[data-cut]');
  if (b) post(b.dataset.cut === 'finish' ? 'cutFinish' : 'cutCancel');
});

function cutKey(e) {
  if (!K.on || e.type !== 'keydown') return false;
  const t = arr(K.d.tools).find((x) => e.key === String(x.key));
  if (t) { post('cutTool', { tool: t.id }); return true; }
  if (e.key === 'Enter') { post('cutFinish'); return true; }
  if (e.key === 'Escape' || e.key === 'Backspace') { post('cutCancel'); return true; }
  return true;
}
