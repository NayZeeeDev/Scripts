/* ═══════════════════════════════════════════════════════════
   NAYZEEE OPTIMIZER — app.js
   Version: 1.1.0 (UI v7)
   ═══════════════════════════════════════════════════════════ */

const $  = id => document.getElementById(id);
const $$ = sel => Array.from(document.querySelectorAll(sel));

const app        = $('app');
const navs       = $$('.nav');
const presetBtns = $$('.preset');
const settingRows= $$('.row[data-setting]');
const effectRows = $$('.row[data-effect]');

/* ═══════════════ STAGE SCALING ═══════════════
   The menu is a fixed 1200 × 720 canvas. It is zoomed to fit the screen
   (never larger than the screen, scaled up on 1440p/4K), so nothing ever
   scrolls vertically or sideways at any resolution. */
const CANVAS_W = 1200, CANVAS_H = 720;
function fitStage() {
  const vw = window.innerWidth, vh = window.innerHeight;
  const fit = Math.min(vw * 0.95 / CANVAS_W, vh * 0.93 / CANVAS_H);
  const pref = Math.max(1, Math.min(vw / 1920, vh / 1080));
  const z = Math.max(0.5, Math.min(fit, pref));
  app.style.zoom = z.toFixed(4);
}
window.addEventListener('resize', fitStage);
fitStage();

/* ═══════════════ CONSTANTS ═══════════════ */
const ALL_TOGGLES = ['optimizePeds','optimizeVehicles','optimizeObjects','removeParticles',
  'optimizeShadows','optimizeLights','lowTextures','disableDecals','disableBloodStains',
  'disableFireEffects','disableRain','disableWind','clearBrokenGlass','cleanPedEffects',
  'clearUnnecessary','entityCleanup','ultraMode'];
const PERF_KEYS = ['optimizePeds','optimizeVehicles','optimizeObjects','removeParticles'];
const VIS_KEYS  = ['optimizeShadows','optimizeLights','lowTextures','disableDecals'];

const P = (...keys) => { const o = {}; ALL_TOGGLES.forEach(k => o[k] = keys.includes(k)); return o; };
let PRESET_STATE = {
  quality: P(),
  balanced: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles','optimizeLights','disableDecals','clearBrokenGlass','cleanPedEffects','clearUnnecessary','entityCleanup'),
  performance: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles','optimizeShadows','optimizeLights','lowTextures','disableDecals','disableBloodStains','disableRain','disableWind','clearBrokenGlass','cleanPedEffects','clearUnnecessary','entityCleanup','ultraMode'),
  potato: P(...ALL_TOGGLES),
  streaming: P('optimizePeds','optimizeObjects','optimizeLights','disableDecals','clearBrokenGlass','cleanPedEffects','clearUnnecessary','entityCleanup'),
  shooter: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles','optimizeShadows','optimizeLights','disableDecals','disableBloodStains','disableFireEffects','disableRain','disableWind','clearBrokenGlass','cleanPedEffects','clearUnnecessary','entityCleanup'),
};
const PRESET_LABEL = { quality:'Quality', balanced:'Balanced', performance:'Performance', potato:'Potato', streaming:'Streaming', shooter:'Shooter', custom:'Custom' };
const GRADE_LABEL = { excellent:'Excellent', good:'Good', ok:'OK', poor:'Poor', bad:'Bad' };
const GRADE_ORDER = { excellent:1, good:2, ok:3, poor:4, bad:5 };
const VERDICT_LABEL = { healthy:'Healthy', monitor:'Monitor', edit:'Edit recommended', 'edit-required':'Edit required', remove:'Remove or replace' };

const FX_LABEL = {
  DeathFailOut:'Death Flash', FocusIn:'Focus In', FocusOut:'Focus Out', RampageOut:'Rampage',
  SwitchHUDIn:'HUD Flash', MinigameEndNeutral:'End Neutral', MinigameEndTrevor:'End Trevor',
  CamPushInFranklin:'Franklin Push', DrugsMichaelAliensFightIn:'Alien Fight',
  SuccessFranklin:'Success Green', SuccessMichael:'Success Blue', SuccessTrevor:'Success Orange',
};
const SOUND_LABEL = { noscope:'No Scope', multikill:'Multi Kill', killingspree:'Killing Spree' };
const titleCase = s => String(s).replace(/[_-]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
const soundLabel = s => SOUND_LABEL[s] || titleCase(s);
const fxLabel = s => FX_LABEL[s] || String(s).replace(/([a-z])([A-Z])/g, '$1 $2');

/* ═══════════════ STATE ═══════════════ */
let currentSettings = {};
let isOpen = false;
let lockedKeys = new Set();
let impactMap = {};
let conflictMap = {};
let uiFlags = {};
let isAdmin = false;
let benchResults = {};
let benchDuration = 30;
let activePreset = null;
let bgSystems = {};
let liveSystems = {};
let poolLimits = { vehicles: 180, peds: 180 };
let killSounds = [];
const fpsHist = [];

/* ═══════════════ NUI ═══════════════ */
const RESOURCE = (typeof GetParentResourceName === 'function')
  ? GetParentResourceName()
  : (window.location.hostname || 'nayzeee-optimizerv2');

function post(action, data = {}) {
  return fetch(`https://${RESOURCE}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).then(r => r.text()).then(t => {
    try { return JSON.parse(t); } catch (e) { return t; }
  }).catch(err => {
    console.error(`[optimizer] NUI callback "${action}" failed:`, err);
    return null;
  });
}

function esc(s) {
  return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
const setTxt = (id, v) => { const e = $(id); if (e) e.textContent = v; };
const setHtml = (id, v) => { const e = $(id); if (e) e.innerHTML = v; };
const fmt = (v, d = 0) => (v == null || isNaN(v)) ? '—' : Number(v).toFixed(d);

/* ═══════════════ SPARKLINES ═══════════════ */
function drawSpark(svg, data, opts = {}) {
  if (!svg) return null;
  const vb = svg.viewBox.baseVal;
  const W = vb.width, H = vb.height, pad = opts.pad != null ? opts.pad : 3;
  if (!data || data.length < 2) { svg.innerHTML = ''; return null; }
  let lo = Math.min(...data), hi = Math.max(...data);
  if (opts.zero) lo = 0;
  const span = Math.max(hi - lo, opts.minSpan || 1);
  lo = opts.zero ? 0 : lo - span * 0.12;
  hi = lo + span * (opts.zero ? 1.12 : 1.24);
  const n = data.length, step = W / (opts.slots ? opts.slots - 1 : n - 1);
  const x0 = opts.slots ? W - (n - 1) * step : 0;
  const pts = data.map((v, i) => [x0 + i * step, H - pad - (v - lo) / (hi - lo) * (H - pad * 2)]);
  const line = pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
  const area = `M${pts[0][0].toFixed(1)},${H} L${line.replace(/ /g, ' L')} L${pts[n - 1][0].toFixed(1)},${H} Z`;
  let ref = '';
  if (opts.ref && opts.ref > lo && opts.ref < hi) {
    const y = H - pad - (opts.ref - lo) / (hi - lo) * (H - pad * 2);
    ref = `<line class="sp-ref" x1="0" x2="${W}" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}"/>`;
  }
  svg.innerHTML = `${ref}<path class="sp-area" d="${area}"/><polyline class="sp-line" points="${line}"/><line class="sp-ref" id="${svg.id}-cursor" x1="0" x2="0" y1="0" y2="${H}" style="display:none"/>`;
  return { pts, W, H };
}

/* ═══════════════════════════════════════════════════════════
   HARDWARE DETECTION
   ═══════════════════════════════════════════════════════════ */
const TIER_INFO = {
  ultra:  { name:'High-end',    preset:'quality',     note:'Your hardware handles GTA comfortably. Visual quality over raw frames.' },
  high:   { name:'Strong',      preset:'balanced',    note:'Plenty of headroom. Balanced keeps things sharp with a solid frame rate.' },
  mid:    { name:'Mid-range',   preset:'balanced',    note:'A good all-rounder. Balanced trims the expensive effects and keeps the look.' },
  low:    { name:'Entry-level', preset:'performance', note:'Performance strips the heavy effects so busy areas stay playable.' },
  potato: { name:'Low-end',     preset:'potato',      note:'Integrated or older graphics. Potato cuts everything it can for frames.' },
};

function detectGPU() {
  try {
    const c = document.createElement('canvas');
    const gl = c.getContext('webgl') || c.getContext('experimental-webgl');
    if (!gl) return null;
    const dbg = gl.getExtension('WEBGL_debug_renderer_info');
    if (!dbg) return null;
    return gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) || null;
  } catch (e) { return null; }
}

function prettyGPU(raw) {
  if (!raw) return null;
  let s = String(raw);
  const angle = s.match(/^ANGLE\s*\(([^,]+),\s*(.+?)(?:\s+Direct3D\d+|\s+vs_\d|\s*,\s*D3D\d+)/i);
  if (angle) s = angle[2];
  return s.replace(/\((?:R|TM|C)\)/gi, '').replace(/[™®]/g, '').replace(/\s*Direct3D\d+.*$/i, '')
          .replace(/\s*vs_\d.*$/i, '').replace(/\s+/g, ' ').trim() || null;
}

function classifyGPU(raw) {
  if (!raw) return null;
  const s = String(raw).toLowerCase().replace(/\((?:r|tm|c)\)/g, ' ').replace(/[™®]/g, ' ').replace(/\s+/g, ' ');
  let m;
  if ((m = s.match(/rtx\s*(\d{4})/))) {
    const n = +m[1], gen = Math.floor(n / 1000), t = n % 1000;
    if (gen >= 4) return t >= 70 ? 'ultra' : 'high';
    if (gen === 3) return t >= 70 ? 'ultra' : t >= 60 ? 'high' : 'mid';
    if (gen === 2) return t >= 70 ? 'high' : 'mid';
    return 'mid';
  }
  if ((m = s.match(/gtx\s*(\d{3,4})/))) { const n = +m[1]; return n >= 1060 ? 'mid' : n >= 950 ? 'low' : 'potato'; }
  if ((m = s.match(/arc\s*[ab](\d{3})/))) return +m[1] >= 750 ? 'high' : 'mid';
  if ((m = s.match(/rx\s*(\d{4})/))) {
    const n = +m[1], gen = Math.floor(n / 1000), t = n % 1000;
    if (gen >= 7) return t >= 800 ? 'ultra' : t >= 700 ? 'high' : 'mid';
    if (gen === 6) return t >= 800 ? 'ultra' : t >= 700 ? 'high' : t >= 600 ? 'mid' : 'low';
    if (gen === 5) return t >= 700 ? 'high' : 'mid';
    return 'low';
  }
  if ((m = s.match(/rx\s*(\d{3})\b/))) return +m[1] >= 580 ? 'low' : 'potato';
  if (/(uhd graphics|iris|hd graphics|vega \d|radeon graphics|intel graphics)/.test(s)) return 'potato';
  if (/\bintel\b/.test(s) && !/arc/.test(s)) return 'potato';
  return null;
}

function measureRefresh() {
  return new Promise(resolve => {
    const times = [];
    let last = performance.now(), frames = 0;
    function tick(now) {
      times.push(now - last); last = now;
      if (++frames < 40) return requestAnimationFrame(tick);
      const sorted = times.slice(5).sort((a, b) => a - b);
      const med = sorted[Math.floor(sorted.length / 2)];
      if (!med || med <= 0) return resolve(null);
      const hz = 1000 / med;
      const common = [60, 75, 90, 100, 120, 144, 165, 180, 240, 360];
      let best = common[0];
      for (const c of common) if (Math.abs(c - hz) < Math.abs(best - hz)) best = c;
      resolve(Math.abs(best - hz) <= 8 ? best : Math.round(hz));
    }
    requestAnimationFrame(tick);
  });
}

async function detectSpecs() {
  const rawGpu = detectGPU();
  const hz = await measureRefresh();
  const threads = navigator.hardwareConcurrency || null;
  const memRaw  = navigator.deviceMemory || null;
  let tier = classifyGPU(rawGpu);
  let guessed = false;
  if (!tier && threads) {
    guessed = true;
    tier = threads >= 16 ? 'high' : threads >= 8 ? 'mid' : threads >= 4 ? 'low' : 'potato';
  }
  return {
    gpu: prettyGPU(rawGpu), threads,
    ram: memRaw ? (memRaw >= 8 ? '8 GB+' : memRaw + ' GB') : null,
    width: window.screen ? window.screen.width : null,
    height: window.screen ? window.screen.height : null,
    hz, tier, guessed,
  };
}

function gfxRecommendations(spec) {
  const t = spec.tier || 'mid';
  const hi = (t === 'ultra' || t === 'high');
  const lo = (t === 'potato' || t === 'low');
  const R = [];
  const add = (name, value, why, off) => R.push({ name, value, why, off: !!off });
  add('Texture Quality', hi ? 'Very High' : t === 'mid' ? 'High' : 'Normal', 'Costs VRAM, not frames. Keep it high unless textures stutter.');
  add('Shader Quality', hi ? 'Very High' : t === 'mid' ? 'High' : 'Normal', 'Affects surface detail across the whole world.');
  add('Shadow Quality', hi ? 'High' : 'Normal', 'One of the most expensive settings in GTA.');
  add('Reflection Quality', hi ? 'High' : t === 'mid' ? 'Normal' : 'Low', 'Heavy in cities with lots of glass and water.');
  add('Water Quality', hi ? 'High' : 'Normal', 'Only matters near water; cheap to leave up.');
  add('Particles Quality', hi ? 'High' : 'Normal', 'Explosions and smoke in firefights.');
  add('Grass Quality', hi ? 'High' : t === 'mid' ? 'Normal' : 'Low', 'Big cost off-road, none downtown.');
  add('Anti-Aliasing (FXAA)', 'On', 'Cheap edge smoothing. Leave it on.');
  add('MSAA', hi ? 'x2' : 'Off', hi ? 'Sharper edges; drop to Off for more frames.' : 'Very expensive. Off is the right call here.', !hi);
  add('Population Density', t === 'mid' ? '~50%' : hi ? '~66%' : '~33%', 'The Optimizer already trims this in-game.');
  add('Population Variety', hi ? '~66%' : '~33%', 'Fewer unique models means less streaming stutter.');
  add('Distance Scaling', hi ? '~66%' : t === 'mid' ? '~50%' : '~33%', 'Directly drives how much world is drawn each frame.');
  add('Extended Distance Scaling', lo ? 'Off' : '~25%', 'Big cost for detail most players never look at.', lo);
  add('High Detail Streaming While Flying', 'Off', 'Only helps in aircraft and costs a lot of memory.', true);
  add('Long Shadows', 'Off', 'Pure cosmetic cost at dawn and dusk.', true);
  add('DirectX Version', 'DirectX 11', 'Most stable for FiveM. DX12 can stutter on some drivers.');
  add('Pause Game On Focus Loss', 'Off', 'Stops the game hitching when you alt-tab.', true);
  add('VSync', spec.hz ? 'On' : 'On', spec.hz ? `Locks frames to your ~${spec.hz}Hz display. Biggest single win for GPU heat.` : 'Locks frames to your display. Biggest single win for GPU heat.');
  return R;
}

/* ═══════════════ THEME ═══════════════ */
function hexToRgb(hex) {
  const h = String(hex || '').replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
  const n = parseInt(full, 16);
  if (isNaN(n) || full.length !== 6) return null;
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function applyTheme(theme) {
  if (!theme) return;
  const root = document.documentElement;
  const set = (name, val) => { if (val) root.style.setProperty(name, val); };
  set('--teal', theme.Primary); set('--teal-hi', theme.PrimaryHi); set('--teal-lo', theme.PrimaryLo);
  set('--red', theme.Danger); set('--red-lo', theme.DangerLo); set('--amber', theme.Amber);
  set('--base', theme.Base); set('--panel', theme.Panel); set('--raise', theme.Raise); set('--inset', theme.Inset);
  set('--ink', theme.Text); set('--ink-2', theme.TextMuted); set('--ink-3', theme.TextDim);
  const p = hexToRgb(theme.Primary);
  if (p) {
    root.style.setProperty('--teal-wash', `rgba(${p[0]}, ${p[1]}, ${p[2]}, .11)`);
    root.style.setProperty('--teal-edge', `rgba(${p[0]}, ${p[1]}, ${p[2]}, .34)`);
  }
  const d = hexToRgb(theme.Danger);
  if (d) {
    root.style.setProperty('--red-wash', `rgba(${d[0]}, ${d[1]}, ${d[2]}, .11)`);
    root.style.setProperty('--red-edge', `rgba(${d[0]}, ${d[1]}, ${d[2]}, .36)`);
  }
}

/* ═══════════════ SOUND ═══════════════ */
const soundCache = {};
function playSound(soundId, volume) {
  if (!/^[a-z0-9_-]+$/i.test(String(soundId || ''))) return;
  const vol = Math.min(100, Math.max(0, volume == null ? 50 : volume)) / 100;
  const isKill = killSounds.includes(soundId);
  Object.keys(soundCache).forEach(key => {
    if (killSounds.includes(key) === isKill && soundCache[key]) {
      soundCache[key].pause();
      soundCache[key].currentTime = 0;
    }
  });
  const audio = new Audio(`sounds/${soundId}.mp3`);
  audio.volume = vol;
  audio.play().catch(() => {});
  soundCache[soundId] = audio;
}

/* ═══════════════ MESSAGES ═══════════════ */
window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.action) {
    case 'open':               applyTheme(d.theme); openMenu(d); break;
    case 'close':              hideUI(); break;
    case 'updateSettings':     applySettings(d.settings); setPresetUI(d.preset || null); break;
    case 'playSound':          playSound(d.soundId, d.volume); break;
    case 'stats':              updateStats(d); break;
    case 'admin':              setAdmin(d.isAdmin); break;
    case 'benchResult':        benchResults = d.results || benchResults; renderBench(); break;
    case 'healthServer':       health.server = d; renderHealth(); break;
    case 'healthClient':       health.client = d; if (health.view === 'mine') renderResources(); break;
    case 'healthClientFrames': health.clientFrames = d; break;
    case 'healthStatus':       toast(d.message, d.kind); break;
  }
});

/* ═══════════════ OPEN / CLOSE ═══════════════ */
function fillSelect(id, items) {
  const el = $(id);
  if (!el || !Array.isArray(items) || !items.length) return;
  const cur = el.value;
  el.innerHTML = items.map(it => `<option value="${esc(it.value)}">${esc(it.label)}</option>`).join('');
  if (cur) el.value = cur;
}

function applyOptions(o) {
  if (!o) return;
  if (Array.isArray(o.screenFx)) {
    const fx = o.screenFx.map(v => ({ value: v, label: fxLabel(v) }));
    fillSelect('killFxSelect', fx); fillSelect('hitFxSelect', fx);
  }
  if (Array.isArray(o.killSounds)) { killSounds = o.killSounds.slice(); fillSelect('killSoundSelect', o.killSounds.map(v => ({ value: v, label: soundLabel(v) }))); }
  if (Array.isArray(o.hitSounds)) fillSelect('hitSoundSelect', o.hitSounds.map(v => ({ value: v, label: soundLabel(v) })));
  if (Array.isArray(o.particles)) fillSelect('hitParticleSelect', o.particles.map(p => ({ value: p.id, label: p.label || titleCase(p.id) })));
}

function openMenu(d) {
  const settings = d.settings || {};
  const meta = d.meta || {};
  uiFlags = d.ui || {};
  lockedKeys = new Set(Array.isArray(d.locked) ? d.locked : []);
  impactMap = d.impact || {};
  conflictMap = d.conflicts || {};
  benchResults = d.bench || {};
  benchDuration = meta.benchDuration || 30;
  bgSystems = d.background || {};
  if (d.limits) poolLimits = d.limits;

  if (d.presets && typeof d.presets === 'object') {
    const next = {};
    Object.keys(d.presets).forEach(k => {
      const o = {};
      ALL_TOGGLES.forEach(t => o[t] = d.presets[k][t] === true);
      next[k] = o;
    });
    if (Object.keys(next).length) PRESET_STATE = next;
  }

  applyOptions(d.options);
  if (d.version) { setTxt('verTag', 'v' + d.version); setTxt('aboutVer', 'v' + d.version); }
  if (d.command) setTxt('cmdOpen', '/' + d.command);

  applyUiFlags(meta);
  decorateRows();
  applySettings(settings);
  setPresetUI(meta.preset || null);
  renderBench();
  renderSystems();
  renderLocks();

  if (settings.specTier && !detectedSpec) {
    detectedSpec = {
      gpu: settings.specGpu || null, threads: settings.specThreads || null, ram: settings.specRam || null,
      width: settings.specWidth || null, height: settings.specHeight || null, hz: settings.specHz || null,
      tier: settings.specTier || null, guessed: !!settings.specGuessed,
    };
    renderSpecs(detectedSpec);
  }

  if (settings.setupDone === false) openSetup();
  updateStats(meta);
  setAdmin(!!meta.isAdmin);
  fitStage();
  app.classList.add('open');
  isOpen = true;
}

function hideUI() {
  app.classList.remove('open');
  isOpen = false;
  closeModal();
  health.open = false;
}

function closeMenu() {
  hideUI();
  post('close');
}

function applyUiFlags(meta) {
  $('navGraphics').hidden = uiFlags.graphicsTab === false;
  if (uiFlags.graphicsTab === false && $('page-graphics').classList.contains('on')) goPage('boost');
  $('fixTexturesBtn').hidden = uiFlags.textureFix === false;

  const fc = uiFlags.frameCap || {};
  $('frameCapBlock').hidden = fc.enabled === false;
  const sel = $('frameCapSelect');
  if (Array.isArray(fc.targets)) {
    const cur = sel.value;
    sel.innerHTML = '<option value="0">Uncapped</option>' + fc.targets.map(t => `<option value="${+t}">${+t} fps</option>`).join('');
    sel.value = cur;
  }

  $('telemetryRow').hidden = uiFlags.telemetry === false;
  $('telemetryInfo').hidden = uiFlags.telemetry === false;
  const setup = uiFlags.setup || {};
  $('optAuto').hidden = setup.allowAutoDetect === false;
  $('setupSkip').hidden = setup.allowSkip === false;

  if (meta.key) setTxt('keyLabel', meta.key);
  setTxt('benchDur', benchDuration);
}

// Impact badges inline with the title, padlocks and conflict lines.
function decorateRows() {
  [...settingRows, ...effectRows].forEach(r => {
    const k = r.dataset.setting || r.dataset.effect;
    const b = r.querySelector('.row-txt b');
    const txt = r.querySelector('.row-txt');
    if (!b || !txt) return;
    b.querySelectorAll('.tag').forEach(el => el.remove());
    txt.querySelectorAll('.warn-line').forEach(el => el.remove());

    const imp = impactMap[k];
    if (imp && r.dataset.setting) {
      const short = v => v === 'medium' ? 'med' : v;
      if (imp.fps && imp.fps !== 'none') b.insertAdjacentHTML('beforeend', `<i class="tag fps-${esc(imp.fps)}" title="Frame rate gain: ${esc(imp.fps)}">+fps ${esc(short(imp.fps))}</i>`);
      if (imp.visual && imp.visual !== 'none') b.insertAdjacentHTML('beforeend', `<i class="tag vis-${esc(imp.visual)}" title="Visual change: ${esc(imp.visual)}">vis ${esc(short(imp.visual))}</i>`);
    }
    const locked = lockedKeys.has(k);
    r.classList.toggle('locked', locked);
    if (locked) b.insertAdjacentHTML('afterbegin', '<i class="tag lock" title="Locked by the server"><svg><use href="#i-lock"/></svg></i>');

    const c = conflictMap[k];
    r.classList.toggle('conflict', !!c);
    if (c) txt.insertAdjacentHTML('beforeend', `<span class="warn-line" title="${esc(c.message)}">${esc(c.resource)}: ${esc(c.message)}</span>`);
  });

  const fix = $('fixTexturesBtn');
  const ftxt = fix.querySelector('.row-txt');
  ftxt.querySelectorAll('.warn-line').forEach(el => el.remove());
  const c = conflictMap.fixTextures;
  fix.classList.toggle('conflict', !!c);
  if (c) ftxt.insertAdjacentHTML('beforeend', `<span class="warn-line" title="${esc(c.message)}">${esc(c.resource)}: ${esc(c.message)}</span>`);
}

function renderLocks() {
  const info = $('lockInfo');
  if (!lockedKeys.size) { info.hidden = true; return; }
  info.hidden = false;
  const names = [...lockedKeys].map(k => {
    const row = document.querySelector(`.row[data-setting="${k}"] .row-txt b, .row[data-effect="${k}"] .row-txt b`);
    return row ? [...row.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('').trim() || k : k;
  });
  setTxt('lockList', names.join(', '));
}

/* ═══════════════ SETTINGS STATE ═══════════════ */
function applySettings(settings) {
  currentSettings = settings || {};
  settingRows.forEach(r => {
    const k = r.dataset.setting;
    if (currentSettings[k] !== undefined) r.classList.toggle('on', currentSettings[k] === true);
  });
  effectRows.forEach(r => {
    const k = r.dataset.effect;
    if (currentSettings[k] !== undefined) r.classList.toggle('on', currentSettings[k] === true);
  });
  setVal('killFxSelect', currentSettings.killFx);
  setVal('killSoundSelect', currentSettings.killSoundId);
  setVal('hitFxSelect', currentSettings.hitFx);
  setVal('hitParticleSelect', currentSettings.hitParticleId);
  setVal('hitSoundSelect', currentSettings.hitSoundId);
  setSlider('killVolumeSlider', 'killVolumeValue', currentSettings.killSoundVolume);
  setSlider('hitVolumeSlider', 'hitVolumeValue', currentSettings.hitSoundVolume);
  if (currentSettings.frameCapTarget !== undefined) { capTarget = currentSettings.frameCapTarget || 0; $('frameCapSelect').value = String(capTarget); renderGuide(); renderCapNote(); }
  refreshCounts();
}

function setVal(id, v) { const el = $(id); if (el && v !== undefined && v !== null) el.value = v; }
function setSlider(sliderId, valId, v) {
  const s = $(sliderId), l = $(valId);
  if (s && v !== undefined) { s.value = v; if (l) l.textContent = v + '%'; }
}

function refreshCounts() {
  let active = 0;
  settingRows.forEach(r => { if (ALL_TOGGLES.includes(r.dataset.setting) && r.classList.contains('on')) active++; });
  const tally = $('activeTally');
  tally.textContent = active;
  tally.classList.toggle('live', active > 0);
  setHtml('statActive', `${active}<em>/ ${ALL_TOGGLES.length}</em>`);
  $('statActiveBar').style.width = `${Math.round(active / ALL_TOGGLES.length * 100)}%`;
  const on = keys => keys.filter(k => currentSettings[k] === true).length;
  setTxt('cntPerf', `${on(PERF_KEYS)} of 4 on`);
  setTxt('cntVis', `${on(VIS_KEYS)} of 4 on`);
  $('killDot').classList.toggle('on', currentSettings.killEnabled === true);
  $('hitDot').classList.toggle('on', currentSettings.hitEnabled === true);
}

function setPresetUI(preset) {
  activePreset = preset && PRESET_LABEL[preset] ? preset : null;
  presetBtns.forEach(b => b.classList.toggle('on', b.dataset.preset === activePreset));
  setHtml('statusText', activePreset ? `Running <b>${PRESET_LABEL[activePreset]}</b> profile` : '<b>Custom</b> configuration');
  setTxt('statProfile', activePreset ? PRESET_LABEL[activePreset] : 'Custom');
  setTxt('sideProfile', activePreset ? PRESET_LABEL[activePreset] : 'Custom');
  setTxt('benchProfile', `Testing: ${activePreset ? PRESET_LABEL[activePreset] : 'Custom'}`);
  renderProfileSub();
}

function renderProfileSub() {
  const key = activePreset || 'custom';
  const r = benchResults[key], base = benchResults.quality;
  let sub = 'Run a benchmark to measure it';
  if (r && base && key !== 'quality' && base.avgFps) {
    const d = Math.round((r.avgFps - base.avgFps) / base.avgFps * 100);
    sub = `Measured ${d >= 0 ? '+' : ''}${d}% vs Quality`;
  } else if (r) {
    sub = `Measured ${r.avgFps} fps average`;
  }
  setTxt('statProfileSub', sub);
  renderInsights();
}

/* ═══════════════ LIVE STATS ═══════════════ */
function updateStats(d) {
  if (d.overshootMargin !== undefined) capOvershoot = d.overshootMargin;
  if (d.frameCapTarget !== undefined && d.frameCapTarget !== capTarget) {
    capTarget = d.frameCapTarget;
    $('frameCapSelect').value = String(capTarget);
    renderGuide();
  }
  if (d.fps !== undefined) {
    lastFps = d.fps;
    if (d.fps > 0) { fpsHist.push(d.fps); if (fpsHist.length > 60) fpsHist.shift(); }
    renderCapNote();
    renderFps();
  }
  if (d.sessionMinutes !== undefined) {
    const m = d.sessionMinutes;
    setHtml('statSession', m >= 60 ? `${Math.floor(m / 60)}<em>h</em> ${m % 60}<em>m</em>` : `${m}<em>m</em>`);
  }
  if (d.preset !== undefined) setPresetUI(d.preset);
  if (d.systems) { liveSystems = d.systems; renderLiveSystems(); }
  if (d.pools) renderWorld(d.pools, d.systems || {});
}

function renderFps() {
  const n = fpsHist.length;
  const now = lastFps || 0;
  setHtml('statFps', `${now || '—'}<em>fps</em>`);
  setHtml('barFps', `<svg><use href="#i-bolt"/></svg><b>${now || '—'}</b> fps`);
  setTxt('sideFps', now ? `${now}` : '—');
  if (n >= 2) {
    const lo = Math.min(...fpsHist), hi = Math.max(...fpsHist);
    const avg = Math.round(fpsHist.reduce((a, b) => a + b, 0) / n);
    setTxt('statFpsSub', `${lo}–${hi} over the last ${n}s`);
    setTxt('sideRange', `${lo}–${hi} fps`);
    setTxt('liveNow', now); setTxt('liveAvg', avg); setTxt('liveMin', lo); setTxt('liveMax', hi);
    setTxt('liveRange', `last ${n} s`);
  }
  const cap = capTarget || 0;
  drawSpark($('statSpark'), fpsHist, { slots: 60 });
  drawSpark($('sideSpark'), fpsHist, { slots: 60 });
  liveGeom = drawSpark($('liveSpark'), fpsHist, { slots: 60, ref: cap || null });
}

let liveGeom = null;
(function liveHover() {
  const wrap = document.querySelector('.live-chart');
  const tip = $('liveTip');
  if (!wrap) return;
  wrap.addEventListener('mousemove', e => {
    if (!liveGeom || fpsHist.length < 2) return;
    const r = wrap.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width * liveGeom.W;
    let best = 0;
    liveGeom.pts.forEach((p, i) => { if (Math.abs(p[0] - x) < Math.abs(liveGeom.pts[best][0] - x)) best = i; });
    const p = liveGeom.pts[best];
    const cur = $('liveSpark-cursor');
    if (cur) { cur.setAttribute('x1', p[0]); cur.setAttribute('x2', p[0]); cur.style.display = ''; }
    tip.hidden = false;
    tip.style.left = `${p[0] / liveGeom.W * 100}%`;
    const ago = fpsHist.length - 1 - best;
    tip.textContent = `${fpsHist[best]} fps · ${ago === 0 ? 'now' : ago + 's ago'}`;
  });
  wrap.addEventListener('mouseleave', () => {
    tip.hidden = true;
    const cur = $('liveSpark-cursor');
    if (cur) cur.style.display = 'none';
  });
})();

const vehHist = [], pedHist = [];
function renderWorld(p, s) {
  vehHist.push(p.vehicles); pedHist.push(p.peds);
  if (vehHist.length > 60) { vehHist.shift(); pedHist.shift(); }
  const rng = a => a.length ? `${Math.min(...a)}–${Math.max(...a)} · now ${a[a.length - 1]}` : '—';
  setTxt('wVehRange', rng(vehHist));
  setTxt('wPedRange', rng(pedHist));
  drawSpark($('wVehSpark'), vehHist, { slots: 60, zero: true, ref: poolLimits.vehicles });
  drawSpark($('wPedSpark'), pedHist, { slots: 60, zero: true, ref: poolLimits.peds });
  const meter = (id, v, max) => {
    setTxt(id, v);
    const pct = Math.min(100, Math.round(v / Math.max(1, max) * 100));
    const bar = $(id + 'Bar');
    bar.style.width = pct + '%';
    bar.classList.toggle('warn', pct >= 85);
  };
  meter('wVeh', p.vehicles, poolLimits.vehicles);
  meter('wPed', p.peds, poolLimits.peds);
  setTxt('wVehNote', `${Math.min(100, Math.round(p.vehicles / poolLimits.vehicles * 100))}% of the ${poolLimits.vehicles} cleanup threshold`);
  setTxt('wPedNote', `${Math.min(100, Math.round(p.peds / poolLimits.peds * 100))}% of the ${poolLimits.peds} cleanup threshold`);
  setTxt('wObj', p.objects);
  setTxt('wScr', p.scripted);
  setTxt('wAmb', `${s.ambient != null ? s.ambient : 100}%`);
  setTxt('wPrb', s.probes != null ? s.probes : '—');
}

/* ═══════════════ BOOST INSIGHTS ═══════════════ */
function renderInsights() {
  const spec = detectedSpec;
  const info = spec && TIER_INFO[spec.tier];
  if (info) {
    setTxt('inHwTitle', `${info.name} PC${spec.guessed ? ' (estimated)' : ''}`);
    setTxt('inHwBody', `${spec.gpu || 'GPU masked'} · suggests ${PRESET_LABEL[info.preset]}`);
  } else {
    setTxt('inHwTitle', 'Hardware not scanned');
    setTxt('inHwBody', 'Detect your specs for a matched profile');
  }
  const ic = $('inCapIc');
  if (!capTarget) {
    ic.classList.add('warn');
    setTxt('inCapTitle', 'Running uncapped');
    setTxt('inCapBody', lastFps ? `${lastFps} fps now · a cap cuts GPU heat` : 'Set a frame cap to cut GPU heat');
  } else if (lastFps && lastFps > capTarget + capOvershoot) {
    ic.classList.add('warn');
    setTxt('inCapTitle', `Cap of ${capTarget} not active`);
    setTxt('inCapBody', `${lastFps} fps now · see the setup steps`);
  } else {
    ic.classList.remove('warn');
    setTxt('inCapTitle', `Capped at ~${capTarget} fps`);
    setTxt('inCapBody', 'Frame rate matches your target');
  }
  const key = activePreset || 'custom';
  const r = benchResults[key];
  if (r) {
    setTxt('inBenchTitle', `${PRESET_LABEL[key]}: ${r.avgFps} fps average`);
    setTxt('inBenchBody', `1% low ${r.low1Fps} fps · worst frame ${r.maxFt} ms`);
  } else {
    setTxt('inBenchTitle', `${PRESET_LABEL[key]} not measured yet`);
    setTxt('inBenchBody', `Benchmark this profile in ${benchDuration} seconds`);
  }
}
$$('.insight').forEach(b => b.addEventListener('click', () => goPage(b.dataset.goto)));

/* ═══════════════ BACKGROUND SYSTEMS ═══════════════ */
const SYSTEMS = [
  { key:'textureStreamFix', name:'Texture streaming fix', desc:'Keeps HD textures anchored around you' },
  { key:'entityPoolMonitor', name:'Entity pool monitor', desc:'Trims ambient entities near engine limits' },
  { key:'assetCleanup', name:'Asset cleanup', desc:'Frees memory from distant vehicle models' },
  { key:'ambientScaling', name:'Ambient scaling', desc:'Fewer NPCs when many players are near', live: s => s.ambient != null && s.ambient < 100 ? `${s.ambient}% density` : null },
  { key:'cpu', name:'CPU load reduction', desc:'Lighter AI and ragdoll for distant NPCs' },
  { key:'idle', name:'AFK throttle', desc:'Cuts load while you are away or paused', live: s => s.afk ? 'AFK now' : s.paused ? 'Paused' : null },
  { key:'adaptive', name:'Adaptive optimizer', desc:'Boosts automatically when FPS drops', live: s => s.adaptive ? `Level ${s.adaptive}` : null },
  { key:'session', name:'Session maintenance', desc:'Memory reclaim and break reminders' },
  { key:'luaGC', name:'Lua garbage collection', desc:'Scheduled memory cleanup' },
];

function renderSystems() {
  const list = $('sysList');
  list.innerHTML = SYSTEMS.map(sy => {
    const on = bgSystems[sy.key] === true;
    return `<div class="sy${on ? ' on' : ''}" data-sys="${sy.key}"><i></i><div><b>${sy.name}</b><span>${sy.desc}</span></div><em>${on ? 'On' : 'Off'}</em></div>`;
  }).join('');
  renderLiveSystems();
}

function renderLiveSystems() {
  SYSTEMS.forEach(sy => {
    const el = document.querySelector(`.sy[data-sys="${sy.key}"]`);
    if (!el || !sy.live) return;
    const on = bgSystems[sy.key] === true;
    const live = on ? sy.live(liveSystems) : null;
    el.classList.toggle('active', !!live);
    el.querySelector('em').textContent = live || (on ? 'On' : 'Off');
  });
  const lvl = liveSystems.adaptive || 0;
  $('barAdaptive').hidden = !lvl;
  if (lvl) setHtml('barAdaptive', `<svg><use href="#i-wand"/></svg>Adaptive <b>L${lvl}</b>`);
  $('barBench').hidden = !liveSystems.benchmark;
  setTxt('statSessionSub', lvl ? `Adaptive boost at level ${lvl}` : liveSystems.afk ? 'AFK throttle active' : 'Adaptive boost idle');
}

/* ═══════════════ NAV ═══════════════ */
function goPage(page) {
  const leavingHealth = $('page-health').classList.contains('on') && page !== 'health';
  navs.forEach(x => x.classList.toggle('on', x.dataset.page === page));
  $$('.page').forEach(p => p.classList.toggle('on', p.id === 'page-' + page));
  if (page === 'health') { health.open = true; post('healthOpen'); }
  else if (leavingHealth) { health.open = false; post('healthClose'); }
}
navs.forEach(n => n.addEventListener('click', () => goPage(n.dataset.page)));
$('closeBtn').addEventListener('click', closeMenu);

/* ═══════════════ TOGGLES ═══════════════ */
function flashLocked(row) { row.classList.add('shake'); setTimeout(() => row.classList.remove('shake'), 300); }

settingRows.forEach(r => {
  r.addEventListener('click', () => {
    const k = r.dataset.setting;
    if (lockedKeys.has(k)) { flashLocked(r); return; }
    const on = r.classList.toggle('on');
    currentSettings[k] = on;
    refreshCounts();
    setPresetUI(null);
    post('toggle', { setting: k, value: on }).then(res => {
      if (res && res.ok === false) { r.classList.toggle('on', !on); currentSettings[k] = !on; refreshCounts(); }
    });
  });
});

effectRows.forEach(r => {
  r.addEventListener('click', () => {
    const k = r.dataset.effect;
    if (lockedKeys.has(k)) { flashLocked(r); return; }
    const on = r.classList.toggle('on');
    currentSettings[k] = on;
    refreshCounts();
    post('setEffectValue', { setting: k, value: on }).then(res => {
      if (res && res.ok === false) { r.classList.toggle('on', !on); currentSettings[k] = !on; refreshCounts(); }
    });
  });
});

/* ═══════════════ PRESETS ═══════════════ */
function applyPresetLocally(p) {
  if (!PRESET_STATE[p]) return;
  settingRows.forEach(r => {
    const k = r.dataset.setting;
    if (PRESET_STATE[p][k] !== undefined && !lockedKeys.has(k)) {
      r.classList.toggle('on', PRESET_STATE[p][k] === true);
      currentSettings[k] = PRESET_STATE[p][k];
    }
  });
  refreshCounts();
}

presetBtns.forEach(b => {
  b.addEventListener('click', () => {
    const p = b.dataset.preset;
    post('preset', { preset: p });
    applyPresetLocally(p);
    setPresetUI(p);
  });
});

/* ═══════════════ SELECTS / SLIDERS / PREVIEWS ═══════════════ */
[['killFxSelect','killFx'], ['hitFxSelect','hitFx'], ['killSoundSelect','killSoundId'],
 ['hitSoundSelect','hitSoundId'], ['hitParticleSelect','hitParticleId']].forEach(([id, key]) => {
  const el = $(id);
  el.addEventListener('change', e => { currentSettings[key] = e.target.value; post('setEffectValue', { setting: key, value: e.target.value }); });
});

[['killVolumeSlider','killVolumeValue','killSoundVolume'], ['hitVolumeSlider','hitVolumeValue','hitSoundVolume']].forEach(([sId, vId, key]) => {
  $(sId).addEventListener('input', e => {
    const v = parseInt(e.target.value);
    setTxt(vId, v + '%');
    currentSettings[key] = v;
    post('setEffectValue', { setting: key, value: v });
  });
});

const val = id => { const el = $(id); return el ? el.value : null; };
$$('.icon-btn[data-preview]').forEach(btn => {
  btn.addEventListener('click', e => {
    e.stopPropagation();
    const t = btn.dataset.preview;
    if (t === 'killFx') post('previewScreenFx', { fx: val('killFxSelect') });
    else if (t === 'hitFx') post('previewScreenFx', { fx: val('hitFxSelect') });
    else if (t === 'hitParticle') post('previewParticle', { id: val('hitParticleSelect') });
    else if (t === 'killSound') playSound(val('killSoundSelect'), parseInt(val('killVolumeSlider')));
    else if (t === 'hitSound') playSound(val('hitSoundSelect'), parseInt(val('hitVolumeSlider')));
    btn.classList.add('flash');
    setTimeout(() => btn.classList.remove('flash'), 260);
  });
});

/* ═══════════════ FIX TEXTURES ═══════════════ */
const fixBtn = $('fixTexturesBtn');
fixBtn.addEventListener('click', () => {
  const btn = fixBtn.querySelector('.btn-teal');
  const label = btn.querySelector('span');
  if (fixBtn.dataset.busy === '1') return;
  fixBtn.dataset.busy = '1';
  fixBtn.classList.add('done');
  btn.classList.add('busy');
  label.textContent = 'Working';
  post('fixTextures');
  closeMenu();
  setTimeout(() => {
    fixBtn.classList.remove('done');
    btn.classList.remove('busy');
    label.textContent = 'Run';
    fixBtn.dataset.busy = '0';
  }, 9000);
});

/* ═══════════════ BENCHMARK ═══════════════ */
$('benchRunBtn').addEventListener('click', () => {
  post('benchmark').then(res => {
    if (res && res.ok === false) setModal('Benchmark busy', 'A benchmark or frame sample is already running. Try again in a few seconds.', null, null);
  });
});
$('benchClear').addEventListener('click', () => {
  setModal('Clear benchmark results', 'Removes every saved result on this PC.', null, 'Clear', () => {
    benchResults = {};
    post('clearBenchmarks');
    renderBench();
    closeModal();
  }, { danger: true });
});

const BENCH_ORDER = ['quality','balanced','performance','potato','streaming','shooter','custom'];
function renderBench() {
  const keys = BENCH_ORDER.filter(k => benchResults[k]).concat(Object.keys(benchResults).filter(k => !BENCH_ORDER.includes(k)));
  const chart = $('benchChart'), empty = $('benchEmpty');
  $('benchClear').hidden = !keys.length;
  const tally = $('benchTally');
  tally.hidden = !keys.length;
  tally.textContent = keys.length;

  $$('.preset .pg').forEach(el => el.textContent = '');
  if (!keys.length) { chart.innerHTML = ''; empty.hidden = false; renderProfileSub(); return; }
  empty.hidden = true;

  const base = benchResults.quality;
  const maxAvg = Math.max(...keys.map(k => benchResults[k].avgFps || 0), 1);
  const bestKey = keys.reduce((a, k) => (benchResults[k].avgFps || 0) > (benchResults[a].avgFps || 0) ? k : a, keys[0]);
  chart.innerHTML = keys.map(k => {
    const r = benchResults[k];
    let sub = r.frames ? `${r.frames} frames` : '';
    let cls = '';
    if (base && k !== 'quality' && base.avgFps) {
      const d = Math.round((r.avgFps - base.avgFps) / base.avgFps * 100);
      sub = `${d >= 0 ? '+' : ''}${d}% vs Quality`;
      cls = d >= 0 ? 'up' : 'down';
    } else if (k === 'quality') {
      sub = 'Baseline';
    }
    const avgW = (r.avgFps / maxAvg * 100).toFixed(1);
    const lowW = (Math.min(r.low1Fps, r.avgFps) / maxAvg * 100).toFixed(1);
    const title = `${PRESET_LABEL[k] || k}: average ${r.avgFps} fps, 1% low ${r.low1Fps} fps, worst frame ${r.maxFt} ms, ${r.stutters || 0} stutters over 50 ms`;
    return `
      <div class="bc-row${k === bestKey ? ' best' : ''}" title="${esc(title)}">
        <div class="bc-name"><b>${esc(PRESET_LABEL[k] || k)}</b><span class="${cls}">${esc(sub)}</span></div>
        <div class="bc-track"><i class="bc-avg" style="width:${avgW}%"></i><i class="bc-low" style="width:${lowW}%"></i></div>
        <div class="bc-nums">
          <div><b>${r.avgFps}</b><span>avg fps</span></div>
          <div><b>${r.low1Fps}</b><span>1% low</span></div>
          <div><b class="${r.maxFt >= 50 ? 'hot' : ''}">${r.maxFt}</b><span>worst ms</span></div>
        </div>
      </div>`;
  }).join('');

  if (base && base.avgFps) {
    keys.forEach(k => {
      if (k === 'quality' || k === 'custom') return;
      const el = document.querySelector(`.pg[data-gain="${k}"]`);
      if (el) { const d = Math.round((benchResults[k].avgFps - base.avgFps) / base.avgFps * 100); el.textContent = `${d >= 0 ? '+' : ''}${d}%`; }
    });
  }
  renderProfileSub();
}

/* ═══════════════ MODAL ═══════════════ */
let modalAction = null;
function setModal(title, sub, code, primaryLabel, onPrimary, opts = {}) {
  setTxt('modalTitle', title);
  setTxt('modalSub', sub || '');
  const ta = $('modalCode');
  ta.hidden = code === null;
  ta.readOnly = !opts.editable;
  ta.value = code || '';
  ta.placeholder = opts.placeholder || '';
  const pb = $('modalPrimary');
  pb.hidden = !primaryLabel;
  pb.querySelector('span').textContent = primaryLabel || '';
  pb.classList.toggle('red', !!opts.danger);
  setTxt('modalMsg', '');
  $('modalMsg').classList.remove('err');
  modalAction = onPrimary || null;
  $('codeModal').hidden = false;
  if (opts.editable) setTimeout(() => ta.focus(), 30);
}
function closeModal() { $('codeModal').hidden = true; modalAction = null; }
function modalMsg(text, isErr) { setTxt('modalMsg', text); $('modalMsg').classList.toggle('err', !!isErr); }
$('modalClose').addEventListener('click', closeModal);
$('modalPrimary').addEventListener('click', () => { if (modalAction) modalAction(); });

/* ═══════════════ EXPORT / IMPORT / RESET ═══════════════ */
const EXPORT_SKIP = new Set(['setupDone','specGpu','specThreads','specRam','specWidth','specHeight','specHz','specTier','specGuessed','shareTelemetry']);
function buildExportCode() {
  const out = {};
  Object.keys(currentSettings).forEach(k => { if (!EXPORT_SKIP.has(k)) out[k] = currentSettings[k]; });
  return 'NZ1-' + btoa(unescape(encodeURIComponent(JSON.stringify(out))));
}
function parseImportCode(code) {
  const s = String(code || '').trim();
  if (!s.startsWith('NZ1-')) throw new Error('Not an Optimizer code');
  const obj = JSON.parse(decodeURIComponent(escape(atob(s.slice(4)))));
  if (!obj || typeof obj !== 'object') throw new Error('Invalid code');
  return obj;
}

$('exportBtn').addEventListener('click', () => {
  setModal('Export settings', 'Share this code. Importing it applies every toggle and effect setting, not your hardware scan.', buildExportCode(), 'Copy', () => {
    const ta = $('modalCode');
    ta.focus(); ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) {}
    modalMsg(ok ? 'Copied to clipboard.' : 'Select the code and press Ctrl+C.', !ok);
  });
});

$('importBtn').addEventListener('click', () => {
  setModal('Import settings', 'Paste a code from a friend. Locked options stay as the server set them.', '', 'Apply', () => {
    let obj;
    try { obj = parseImportCode($('modalCode').value); }
    catch (e) { modalMsg(e.message || 'Invalid code', true); return; }
    post('importSettings', { settings: obj }).then(res => {
      if (res && res.ok) {
        modalMsg(`Applied ${res.applied} setting${res.applied === 1 ? '' : 's'}${res.rejected ? `, ${res.rejected} skipped` : ''}.`);
        setTimeout(closeModal, 900);
      } else {
        modalMsg((res && res.error) || 'Nothing could be applied from that code.', true);
      }
    });
  }, { editable: true, placeholder: 'NZ1-…' });
});

$('resetBtn').addEventListener('click', () => {
  setModal('Reset to defaults', 'Every performance option and effect goes back to the server defaults. Your hardware scan and benchmark results are kept.', null, 'Reset', () => {
    post('resetDefaults');
    closeModal();
  }, { danger: true });
});

/* ═══════════════ FRAME CAP ═══════════════ */
const GUIDES = {
  nvidia: t => [
    'Open <b>NVIDIA Control Panel</b> &rarr; <b>Manage 3D settings</b> &rarr; <b>Program Settings</b>.',
    'Select <b>FiveM</b> (the FiveM_b____ GTAProcess executable).',
    `Set <b>Max Frame Rate</b> to <b>${t}</b>, then apply.`,
    'Fully restart FiveM for it to take effect.',
  ],
  amd: t => [
    'Open <b>AMD Software: Adrenalin</b> &rarr; <b>Gaming</b> &rarr; <b>FiveM</b>.',
    'Turn on <b>Frame Rate Target Control</b> or <b>Radeon Chill</b>.',
    `Set the target to <b>${t}</b> fps (Chill: min and max both ${t}).`,
    'Fully restart FiveM for it to take effect.',
  ],
  gta: t => [
    'Press <b>ESC</b> &rarr; <b>Settings</b> &rarr; <b>Graphics</b>.',
    'Turn <b>VSync On</b> to lock frames to your monitor.',
    `VSync uses your display refresh, not exactly ${t}. Use the GPU tab for an exact cap.`,
  ],
};
let capTarget = 0, capGpu = 'nvidia', lastFps = 0, capOvershoot = 25;

function renderGuide() {
  const guide = $('capGuide');
  if (!capTarget) { guide.hidden = true; return; }
  guide.hidden = false;
  $('guideSteps').innerHTML = GUIDES[capGpu](capTarget).map(s => `<li>${s}</li>`).join('');
}

function renderCapNote() {
  const note = $('capNote');
  note.classList.remove('good', 'warn');
  if (!capTarget) {
    setTxt('capNoteTitle', 'Running uncapped');
    setTxt('capNoteBody', 'Your GPU renders frames your monitor never shows. Pick your refresh rate for setup steps.');
  } else if (!lastFps) {
    setTxt('capNoteTitle', `Target ${capTarget} fps`);
    setTxt('capNoteBody', 'Follow the steps below, then restart FiveM and check back here.');
  } else if (lastFps > capTarget + capOvershoot) {
    note.classList.add('warn');
    setTxt('capNoteTitle', `Not capped yet: ${lastFps} fps`);
    setTxt('capNoteBody', `Well above your ${capTarget} fps target. Follow the steps below and restart FiveM.`);
  } else {
    note.classList.add('good');
    setTxt('capNoteTitle', `Capped at ~${capTarget} fps`);
    setTxt('capNoteBody', 'Frame rate matches your target. Best single thing for GPU temperature.');
  }
  renderInsights();
}

$('frameCapSelect').addEventListener('change', e => {
  capTarget = parseInt(e.target.value) || 0;
  post('setFrameCapTarget', { target: capTarget });
  renderCapNote();
  renderGuide();
  renderFps();
});

$$('#capGuide .gt').forEach(b => {
  b.addEventListener('click', () => {
    $$('#capGuide .gt').forEach(x => x.classList.remove('on'));
    b.classList.add('on');
    capGpu = b.dataset.gpu;
    renderGuide();
  });
});

/* ═══════════════ FIRST-RUN SETUP + GRAPHICS ═══════════════ */
let detectedSpec = null;
let recommendedPreset = null;

function showStep(id) { $$('.setup-step').forEach(s => s.classList.toggle('on', s.id === id)); }
function openSetup() { $('setupOverlay').hidden = false; showStep('setupChoose'); }
function finishSetup() { $('setupOverlay').hidden = true; post('setupDone'); }

function renderSpecs(spec) {
  const res = (spec.width && spec.height) ? `${spec.width} × ${spec.height}` : 'Unknown';
  setTxt('specGpu', spec.gpu || 'Not detected');
  $('specGpu').title = spec.gpu || '';
  setTxt('specCpu', spec.threads ? `${spec.threads} threads` : 'Unknown');
  setTxt('specRam', spec.ram || 'Unknown');
  setTxt('specRes', res);
  setTxt('specHz', spec.hz ? `~${spec.hz} Hz` : 'Unknown');
  const info = TIER_INFO[spec.tier] || null;
  const tierEl = $('specTier');
  if (info) {
    setTxt('tierName', info.name + (spec.guessed ? ' (est.)' : ''));
    setTxt('tierNote', spec.guessed
      ? 'Your graphics card was masked by the driver, so the tier is estimated from CPU threads. Adjust if it feels off.'
      : `${info.note} Suggested profile: ${PRESET_LABEL[info.preset]}.`);
    tierEl.classList.toggle('warn', !!spec.guessed);
  } else {
    setTxt('tierName', 'Not detected');
    setTxt('tierNote', 'Your hardware could not be read. Pick a profile that feels right and adjust from there.');
    tierEl.classList.add('warn');
  }
  $('specEmpty').hidden = true;
  $('specList').hidden = false;
  $('rescanBtn').hidden = false;
  const recs = gfxRecommendations(spec);
  $('gfxList').innerHTML = recs.map(r => `
    <div class="gfx" title="${esc(r.name)}: ${esc(r.value)}. ${esc(r.why)}">
      <div class="gfx-top"><b>${esc(r.name)}</b><span class="gfx-val${r.off ? ' off' : ''}">${esc(r.value)}</span></div>
      <span>${esc(r.why)}</span>
    </div>`).join('');
  setTxt('gfxCount', `${recs.length} settings for ${info ? info.name.toLowerCase() : 'your'} hardware`);
  renderInsights();
}

async function runScan(onDone) {
  showStep('setupScan');
  const bar = $('scanBar'), status = $('scanStatus');
  const steps = [[18, 'Checking graphics card…'], [42, 'Reading CPU and memory…'], [70, 'Measuring display refresh rate…'], [92, 'Matching a profile…']];
  let i = 0;
  const timer = setInterval(() => { if (i >= steps.length) return; bar.style.width = steps[i][0] + '%'; status.textContent = steps[i][1]; i++; }, 380);
  const spec = await detectSpecs();
  clearInterval(timer);
  bar.style.width = '100%';
  detectedSpec = spec;
  const info = TIER_INFO[spec.tier];
  recommendedPreset = info ? info.preset : 'balanced';
  post('saveSpec', { gpu: spec.gpu || '', threads: spec.threads || 0, ram: spec.ram || '', width: spec.width || 0, height: spec.height || 0, hz: spec.hz || 0, tier: spec.tier || '', guessed: !!spec.guessed });
  renderSpecs(spec);
  if (onDone) onDone(spec, info);
}

function runGraphicsScan() {
  const btn = $('rescanBtn');
  btn.classList.add('busy');
  detectSpecs().then(spec => {
    detectedSpec = spec;
    post('saveSpec', { gpu: spec.gpu || '', threads: spec.threads || 0, ram: spec.ram || '', width: spec.width || 0, height: spec.height || 0, hz: spec.hz || 0, tier: spec.tier || '', guessed: !!spec.guessed });
    renderSpecs(spec);
    btn.classList.remove('busy');
  });
}

function showResult(spec, info) {
  const res = (spec.width && spec.height) ? `${spec.width} × ${spec.height}` : 'Unknown';
  const rows = [['Graphics card', spec.gpu || 'Not detected', true], ['CPU threads', spec.threads ? `${spec.threads}` : 'Unknown'], ['Memory', spec.ram || 'Unknown'], ['Resolution', res], ['Refresh rate', spec.hz ? `~${spec.hz} Hz` : 'Unknown']];
  $('resultSpecs').innerHTML = rows.map(([l, v, wide]) => `<div class="rs${wide ? ' span2' : ''}"><label>${esc(l)}</label><b>${esc(v)}</b></div>`).join('');
  setTxt('pickName', info ? (PRESET_LABEL[info.preset] || info.preset) : 'Balanced');
  setTxt('pickWhy', info ? info.note : 'A safe starting point you can tune from.');
  setTxt('resultTitle', info ? `${info.name} system detected` : 'Could not read your hardware');
  setTxt('resultSub', info ? 'Based on what we found, this profile should give you the best balance. You can change it any time.' : 'Pick a profile that feels right. You can change it any time.');
  showStep('setupResult');
}

$('optAuto').addEventListener('click', () => runScan(showResult));
$('optManual').addEventListener('click', finishSetup);
$('setupSkip').addEventListener('click', finishSetup);
$('pickOwn').addEventListener('click', finishSetup);
$('applyRec').addEventListener('click', () => {
  const p = recommendedPreset || 'balanced';
  post('preset', { preset: p });
  applyPresetLocally(p);
  setPresetUI(p);
  finishSetup();
});
$('scanBtn').addEventListener('click', runGraphicsScan);
$('rescanBtn').addEventListener('click', runGraphicsScan);

/* ═══════════════════════════════════════════════════════════
   HEALTH (admins)
   ═══════════════════════════════════════════════════════════ */
const PAGE_SIZE = 12;
const health = { server: null, client: null, clientFrames: null, view: 'server', tab: 'overview', page: 0, filter: 'all', search: '', sel: null, open: false };

function setAdmin(flag) {
  isAdmin = !!flag;
  $('grpServer').hidden = !isAdmin;
  $('navHealth').hidden = !isAdmin;
  if (!isAdmin && $('page-health').classList.contains('on')) goPage('boost');
}

function fmtAgo(sec) {
  if (sec == null || isNaN(sec)) return '';
  if (sec < 60) return `${Math.floor(sec)}s ago`;
  if (sec < 3600) return `${Math.floor(sec / 60)} min ago`;
  return `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m ago`;
}

let toastTimer = null;
function toast(message, kind) {
  const n = $('hStatus');
  if (!message) { n.hidden = true; return; }
  n.className = `toast ${kind || 'info'}`;
  setTxt('hStatusBody', message);
  $('hStatusBody').title = message;
  n.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { n.hidden = true; }, kind === 'error' ? 15000 : 7000);
}

function setHTab(tab) {
  health.tab = tab;
  $$('#hTabs .gt').forEach(b => b.classList.toggle('on', b.dataset.htab === tab));
  $$('.htab').forEach(t => t.classList.toggle('on', t.id === 'htab-' + tab));
}
$$('#hTabs .gt').forEach(b => b.addEventListener('click', () => setHTab(b.dataset.htab)));

function renderHealth() {
  renderOverview();
  renderResources();
  renderProbes();
  const d = health.server;
  const tally = $('healthTally');
  const bad = d ? (d.resources || []).concat((d.clients && d.clients.rows) || []).filter(r => r.grade === 'bad' || r.grade === 'poor').length : 0;
  tally.hidden = bad === 0;
  tally.textContent = bad;
  tally.classList.toggle('bad', bad > 0);
}

/* ── Overview ── */
function renderOverview() {
  const d = health.server;
  if (!d || !d.server) return;
  const s = d.server, t = s.tick || {};
  $('hGradeTile').className = `tile g-${s.grade}`;
  setTxt('hGrade', GRADE_LABEL[s.grade] || '—');
  setTxt('hGradeSub', `Up ${s.uptimeMin >= 60 ? Math.floor(s.uptimeMin / 60) + 'h ' + (s.uptimeMin % 60) + 'm' : s.uptimeMin + ' min'} · avg drift ${t.avgDrift} ms`);
  setHtml('hHitch', `${t.perHour}<em>/h</em>`);
  setTxt('hHitchSub', `${t.hitches} total · ${t.severe} severe · worst ${t.worst} ms`);
  setTxt('hMemLabel', s.memoryLabel || 'Memory');
  setHtml('hMem', `${s.memoryMB}<em>MB</em>`);
  const hist = (s.memoryHistory || []).filter(v => typeof v === 'number');
  if (hist.length >= 2) {
    const delta = hist[hist.length - 1] - hist[0];
    setTxt('hMemSub', `${delta >= 0 ? '+' : ''}${delta} MB over ${Math.round(hist.length * (s.memoryIntervalSec || 60) / 60)} min`);
  } else {
    setTxt('hMemSub', 'Trend after a few samples');
  }
  const c = d.clients || {};
  setHtml('hPlayers', `${s.players}<em>online</em>`);
  setTxt('hPlayersSub', c.reporting ? `${c.reporting} sharing · avg ${c.fpsAvg} fps` : `${s.resourcesStarted} resources running`);

  // timeline
  const tl = s.timeline || [];
  let max = 1, total = 0, severe = 0;
  tl.forEach(b => { total += b[0] || 0; severe += b[1] || 0; if ((b[0] || 0) > max) max = b[0]; });
  $('hTimeline').innerHTML = tl.map((b, i) => {
    const h = b[0] || 0, sv = b[1] || 0, n = h - sv, ago = tl.length - 1 - i;
    const when = ago === 0 ? 'this minute' : `${ago} min ago`;
    const title = h ? `${h} hitch${h === 1 ? '' : 'es'}${sv ? `, ${sv} severe` : ''} · ${when}` : `No hitches · ${when}`;
    return `<i title="${esc(title)}">${n ? `<b style="height:${Math.max(6, n / max * 100)}%"></b>` : ''}${sv ? `<em style="height:${Math.max(6, sv / max * 100)}%"></em>` : ''}</i>`;
  }).join('');
  setTxt('hTlCount', total ? `${total} hitches · ${severe} severe` : 'No hitches');
  setTxt('hTlInfo', t.lastSevereAgo != null ? `Last severe hitch ${fmtAgo(t.lastSevereAgo)}` : 'No severe hitches');

  // memory
  drawSpark($('hMemSpark'), hist, { minSpan: 8 });
  setTxt('hMemRange', hist.length ? `${Math.min(...hist)}–${Math.max(...hist)} MB` : 'Collecting');
  setTxt('hMemFrom', hist.length >= 2 ? `${hist[0]} → ${hist[hist.length - 1]} MB` : 'Samples every ' + (s.memoryIntervalSec || 60) + 's');
  const e = s.entities || {};
  setTxt('hEntities', `${e.vehicles ?? '—'} veh · ${e.peds ?? '—'} peds · ${e.objects ?? '—'} obj`);

  // needs attention
  const rows = (d.resources || []).map(r => ({ ...r, view: 'server' }))
    .concat(((c.rows) || []).map(r => ({ ...r, view: 'clients' })));
  const attn = rows.filter(r => r.verdict && r.verdict !== 'healthy' && r.verdict !== 'monitor')
    .sort((a, b) => (GRADE_ORDER[b.grade] - GRADE_ORDER[a.grade]) || (b.load - a.load));
  setTxt('hAttnCount', attn.length ? `${attn.length} resource${attn.length === 1 ? '' : 's'}` : '');
  $('hAttn').innerHTML = attn.length ? attn.slice(0, 6).map((r, i) => `
    <div class="at g-${esc(r.grade)}" data-i="${i}" title="${esc((r.hints || [])[0] || '')}">
      <div class="at-name"><b>${esc(r.name)}</b><span class="v-${esc(r.verdict)}">${VERDICT_LABEL[r.verdict] || r.verdict}</span></div>
      <span class="at-side">${r.view === 'server' ? 'Server' : 'Clients'}</span>
      <i class="pill g-${esc(r.grade)}">${GRADE_LABEL[r.grade]}</i>
      <span class="at-hint">${esc((r.hints || [])[0] || '')}</span>
    </div>`).join('')
    : `<div class="empty-mini"><svg><use href="#i-check"/></svg><b>Nothing needs attention</b><span>No resource is graded Poor or Bad${(d.probe && d.probe.covered) ? '' : ' yet. Install the probe or run a deep scan to grade resources'}.</span></div>`;
  $$('#hAttn .at').forEach(el => el.addEventListener('click', () => {
    const r = attn[+el.dataset.i];
    health.view = r.view;
    $$('#hSeg .gt').forEach(b => b.classList.toggle('on', b.dataset.view === r.view));
    health.filter = 'all'; health.search = ''; $('hSearch').value = '';
    $$('#hGradeFilter .gt').forEach(b => b.classList.toggle('on', b.dataset.grade === 'all'));
    health.sel = r.name;
    const list = currentRows();
    health.page = Math.max(0, Math.floor(list.findIndex(x => x.name === r.name) / PAGE_SIZE));
    setHTab('resources');
    renderResources();
  }));

  // players
  const pp = $('hPlayersPanel');
  if (!c.reporting) {
    setTxt('hPlCount', '');
    pp.innerHTML = `<div class="empty-mini"><svg><use href="#i-users"/></svg><b>No player reports yet</b><span>Players with "Share performance data" on report once a minute, starting about a minute after they join.</span></div>`;
  } else {
    setTxt('hPlCount', `${c.reporting} of ${c.players} sharing`);
    const tiers = c.tiers || {};
    const tierOrder = ['ultra','high','mid','low','potato'];
    const tierChips = tierOrder.filter(k => tiers[k]).map(k => `<span>${TIER_INFO[k] ? TIER_INFO[k].name : k} · ${tiers[k]}</span>`).join('') || '<span>No hardware scans yet</span>';
    pp.innerHTML = `
      <div class="pl-big">
        <div><span>Average FPS</span><b>${c.fpsAvg}<em>fps</em></b></div>
        <div><span>Average 1% low</span><b>${c.lowAvg}<em>fps</em></b></div>
      </div>
      <div class="hb"><div class="hb-top"><span>Under 45 fps</span><b>${c.under45}%</b></div><i class="bar-m"><u class="${c.under45 >= 40 ? 'warn' : ''}" style="width:${c.under45}%"></u></i></div>
      <div class="hb"><div class="hb-top"><span>Under 30 fps</span><b>${c.under30}%</b></div><i class="bar-m"><u class="${c.under30 >= 20 ? 'warn' : ''}" style="width:${c.under30}%"></u></i></div>
      <div class="chips">${tierChips}</div>`;
  }
}

/* ── Resources ── */
function currentRows() {
  let rows = [];
  if (health.view === 'server') rows = (health.server && health.server.resources) || [];
  else if (health.view === 'clients') rows = (health.server && health.server.clients && health.server.clients.rows) || [];
  else rows = (health.client && health.client.rows) || [];
  const q = health.search.trim().toLowerCase();
  return rows.filter(r => (!q || r.name.toLowerCase().includes(q)) && (health.filter === 'all' || r.grade === 'poor' || r.grade === 'bad'));
}

function renderResources() {
  const view = health.view;
  setTxt('hLegendNote', view === 'server' ? 'Load = % of server main thread' : view === 'clients' ? 'Load = median ms per frame across players' : 'Load = ms per frame on your PC');
  const rows = currentRows();
  const pages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
  if (health.page >= pages) health.page = pages - 1;
  const start = health.page * PAGE_SIZE;
  const slice = rows.slice(start, start + PAGE_SIZE);

  const empty = $('hTableEmpty');
  if (!rows.length) {
    $('hTable').innerHTML = '';
    empty.hidden = false;
    setTxt('hTableEmptyBody', health.search || health.filter !== 'all' ? 'No resources match this filter.'
      : view === 'server' ? 'Install the probe or run a deep scan from the Probes & scan tab.'
      : view === 'clients' ? 'No player reports yet.' : 'No probe reports from your PC yet. Resources need the probe line and a restart.');
  } else {
    empty.hidden = true;
    $('hTable').innerHTML = slice.map(r => {
      const peakCls = r.peakMs >= 50 ? 'bad' : r.peakMs >= 5 ? 'hot' : '';
      const evCls = r.eventsPs >= 200 ? 'bad' : r.eventsPs >= 50 ? 'hot' : '';
      const load = view === 'server' ? `${fmt(r.load, 2)}<em>%</em>` : `${fmt(r.load, 3)}<em>ms</em>`;
      const tag = view === 'clients' ? `${r.clients} pc` : r.source === 'scan' ? 'scan' : '';
      return `
        <div class="rt-row g-${esc(r.grade)}${health.sel === r.name ? ' sel' : ''}" data-name="${esc(r.name)}">
          <div class="rt-name" title="${esc(r.name)}">${esc(r.name)}${tag ? `<em>${esc(tag)}</em>` : ''}</div>
          <div class="rt-load">${load}</div>
          <div class="rt-m ${peakCls}">${fmt(r.peakMs, 1)} ms</div>
          <div class="rt-m ${evCls}">${fmt(r.eventsPs, 0)}</div>
          <div><i class="pill g-${esc(r.grade)}">${GRADE_LABEL[r.grade] || r.grade}</i></div>
          <div class="rt-verdict v-${esc(r.verdict)}">${VERDICT_LABEL[r.verdict] || r.verdict}</div>
        </div>`;
    }).join('');
    $$('#hTable .rt-row').forEach(el => el.addEventListener('click', () => { health.sel = el.dataset.name; renderResources(); }));
  }
  setTxt('hPageInfo', rows.length ? `${start + 1}–${Math.min(start + PAGE_SIZE, rows.length)} of ${rows.length}` : '0 resources');
  $('hPrev').disabled = health.page <= 0;
  $('hNext').disabled = health.page >= pages - 1;
  renderDetail(rows.find(r => r.name === health.sel) || null);
}

function renderDetail(r) {
  $('hDetailEmpty').hidden = !!r;
  $('hDetailBody').hidden = !r;
  if (!r) return;
  const view = health.view;
  setTxt('dName', r.name);
  setTxt('dSource', view === 'clients' ? `Measured on ${r.clients} player PC${r.clients === 1 ? '' : 's'}` : view === 'mine' ? 'Measured on your PC' : r.source === 'scan' ? 'Graded by the deep scan' : `Graded by the probe${r.scanLoad != null ? ', scan agrees' : ''}`);
  const g = $('dGrade');
  g.className = `pill lg g-${r.grade}`;
  g.textContent = GRADE_LABEL[r.grade] || r.grade;
  const v = $('dVerdict');
  v.className = `d-verdict v-${r.verdict}`;
  v.textContent = VERDICT_LABEL[r.verdict] || r.verdict;

  const cell = (label, value, cls) => `<div><span>${label}</span><b class="${cls || ''}">${value}</b></div>`;
  const cells = [];
  if (view === 'server') {
    cells.push(cell('Main thread', `${fmt(r.load, 2)}%`));
    cells.push(cell(r.msPerTick != null ? 'Per tick' : 'Per second', r.msPerTick != null ? `${fmt(r.msPerTick, 3)} ms` : `${fmt(r.msPerSec, 1)} ms`));
  } else {
    cells.push(cell('Per frame', `${fmt(r.load, 3)} ms`));
    cells.push(cell('Loops / frame', fmt(r.loops, 1), r.loops >= 8 ? 'bad' : r.loops >= 3 ? 'hot' : ''));
  }
  cells.push(cell('Peak slice', `${fmt(r.peakMs, 1)} ms`, r.peakMs >= 50 ? 'bad' : r.peakMs >= 5 ? 'hot' : ''));
  cells.push(cell('Events / s', fmt(r.eventsPs, 0), r.eventsPs >= 200 ? 'bad' : r.eventsPs >= 50 ? 'hot' : ''));
  cells.push(cell('Lua memory', r.memMB != null ? `${fmt(r.memMB, 1)} MB` : '—'));
  cells.push(cell('Growth / h', r.memGrowth != null ? `${r.memGrowth >= 0 ? '+' : ''}${fmt(r.memGrowth, 1)} MB` : '—', r.memGrowth >= 50 ? 'bad' : r.memGrowth >= 10 ? 'hot' : ''));
  if (view === 'server' && r.slicesPs != null) cells.push(cell('Calls / s', fmt(r.slicesPs, 0)));
  if (view === 'server' && r.scanLoad != null) cells.push(cell('Scan load', `${fmt(r.scanLoad, 2)}%`));
  $('dGrid').innerHTML = cells.join('');

  const sev = r.grade === 'bad' ? 'bad' : r.grade === 'poor' ? 'warn' : '';
  $('dHints').innerHTML = (r.hints || []).map(h => `<li class="${sev}">${esc(h)}</li>`).join('');
}

$$('#hSeg .gt').forEach(b => b.addEventListener('click', () => {
  $$('#hSeg .gt').forEach(x => x.classList.toggle('on', x === b));
  health.view = b.dataset.view; health.page = 0; health.sel = null;
  renderResources();
}));
$$('#hGradeFilter .gt').forEach(b => b.addEventListener('click', () => {
  $$('#hGradeFilter .gt').forEach(x => x.classList.toggle('on', x === b));
  health.filter = b.dataset.grade; health.page = 0;
  renderResources();
}));
$('hSearch').addEventListener('input', e => { health.search = e.target.value; health.page = 0; renderResources(); });
$('hPrev').addEventListener('click', () => { health.page = Math.max(0, health.page - 1); renderResources(); });
$('hNext').addEventListener('click', () => { health.page += 1; renderResources(); });

/* ── Probes & scan ── */
function renderProbes() {
  const d = health.server;
  if (!d) return;
  const p = d.probe || {};
  const pct = p.total ? Math.round(p.covered / p.total * 100) : 0;
  setTxt('pCovPct', `${pct}% covered`);
  $('pRing').style.strokeDasharray = `${(pct / 100 * 100.5).toFixed(1)} 101`;
  setTxt('pCovered', `${p.covered || 0} / ${p.total || 0}`);
  setTxt('pReporting', p.reporting || 0);
  setTxt('pExcluded', `${p.excluded || 0} / ${p.legacy || 0}`);
  const pending = p.pending || [];
  setTxt('pPending', pending.length);
  $('pPending').classList.toggle('hot', pending.length > 0);
  const rb = $('hProbeRestart');
  rb.disabled = !pending.length;
  rb.querySelector('span').textContent = pending.length ? `Restart ${pending.length}` : 'Restart';
  const pn = $('pNote');
  if (p.canRefresh === false) {
    pn.className = 'note slim warn';
    pn.innerHTML = `<b>Needs one server.cfg line</b><span>Add <code>add_ace resource.${esc(RESOURCE)} command allow</code> so Restart can reload the changed manifests and the deep scan can run.</span>`;
  } else if (pending.length) {
    pn.className = 'note slim warn';
    pn.innerHTML = `<b>${pending.length} waiting for a restart</b><span>${esc(pending.slice(0, 6).join(', '))}${pending.length > 6 ? ', …' : ''}. Press Restart, or they activate on the next server restart.</span>`;
  } else {
    pn.className = 'note slim';
    pn.innerHTML = '<b>How it activates</b><span>Install adds one line to each manifest and keeps a backup. Restart then reloads those resources so they start measuring.</span>';
  }
  const missing = p.missing || [];
  setTxt('pMissCount', missing.length ? `${missing.length} resource${missing.length === 1 ? '' : 's'}` : 'All covered');
  const MAX = 26;
  $('pMissing').innerHTML = missing.length
    ? missing.slice(0, MAX).map(n => `<span title="${esc(n)}">${esc(n)}</span>`).join('') + (missing.length > MAX ? `<span class="more">+${missing.length - MAX} more</span>` : '')
    : '<span class="ok">Every started Lua resource has the probe</span>';
  setTxt('pAuto', p.autoInstall ? 'On' : 'Off');
  setTxt('pAutoNew', p.autoInstallNew ? 'On' : 'Off');
  const ib = $('hProbe');
  ib.disabled = !missing.length;
  ib.querySelector('span').textContent = missing.length ? `Install on ${missing.length}` : 'All installed';

  const sc = d.scan || {};
  const running = sc.status === 'running';
  setTxt('sStatus', running ? 'Recording…' : sc.status === 'done' ? 'Complete' : sc.status === 'error' ? 'Failed' : 'Not run');
  setTxt('sWhen', sc.at && sc.status !== 'idle' ? fmtAgo(Math.max(0, Date.now() / 1000 - sc.at)) : 'Never');
  setTxt('sFrames', sc.frames && sc.status !== 'idle' ? sc.frames : '—');
  setTxt('sCount', sc.count || '—');
  const sb = $('hScan');
  sb.disabled = running;
  sb.querySelector('span').textContent = running ? 'Scanning…' : 'Run deep scan';
  sb.classList.toggle('busy', running);
  const sn = $('sNote');
  if (sc.status === 'error') {
    sn.className = 'note slim warn';
    sn.innerHTML = `<b>Last scan failed</b><span>${esc(sc.error || 'Unknown error')}</span>`;
  } else {
    sn.className = 'note slim';
    sn.innerHTML = '<b>Covers JS and C# too</b><span>Uses the built-in FXServer profiler for 500 frames. Expect one short hitch while the trace is saved.</span>';
  }

  const u = d.update || {};
  $('hUpdate').hidden = !u.outdated;
  if (u.outdated) {
    setTxt('hUpdateTitle', `Update available: ${u.current} → ${u.latest}`);
    setTxt('hUpdateBody', `${u.notes || ''} ${u.url || ''}`.trim() || 'Download the latest version from your keymaster.');
  }
}

$('hRefresh').addEventListener('click', () => {
  post('healthRefresh');
  const b = $('hRefresh');
  b.classList.add('busy');
  setTimeout(() => b.classList.remove('busy'), 900);
});

$('hScan').addEventListener('click', () => {
  setModal('Run a deep scan', 'Records 500 server frames with the built-in FXServer profiler, then grades every resource including JS and C#. The server keeps running; expect one short hitch when the trace is saved.', null, 'Start scan', () => {
    post('healthAction', { what: 'scan' });
    toast('Deep scan requested…', 'info');
    closeModal();
  });
});

$('hProbe').addEventListener('click', () => {
  const missing = (health.server && health.server.probe && health.server.probe.missing) || [];
  if (!missing.length) return;
  setModal('Install probes', `Adds "shared_script '@${RESOURCE}/probe.lua'" to ${missing.length} manifest${missing.length === 1 ? '' : 's'} with a backup of each, then restarts them so they start measuring. Core scripts other resources depend on wait for the next server restart.`, missing.join('\n'), 'Install and restart', () => {
    post('healthAction', { what: 'probeInstall', arg: true });
    toast('Installing probes…', 'info');
    closeModal();
  });
});

$('hProbeRestart').addEventListener('click', () => {
  const pending = (health.server && health.server.probe && health.server.probe.pending) || [];
  if (!pending.length) return;
  setModal('Restart resources', `Reloads ${pending.length} resource${pending.length === 1 ? '' : 's'} so their probe starts measuring. Players may notice a brief hiccup in those scripts. Core scripts other resources depend on are skipped.`, pending.join('\n'), 'Restart now', () => {
    post('healthAction', { what: 'probeRestart' });
    toast('Restarting resources…', 'info');
    closeModal();
  });
});

$('hProbeRemove').addEventListener('click', () => {
  setModal('Remove all probes', 'Removes the probe line from every manifest and deletes the backups. Restart those resources to unload it.', null, 'Remove', () => {
    post('healthAction', { what: 'probeRemove' });
    toast('Removing probes…', 'info');
    closeModal();
  }, { danger: true });
});

/* ═══════════════ KEYBOARD ═══════════════ */
document.addEventListener('keyup', e => {
  if (e.key === 'Escape' && isOpen) {
    if (!$('codeModal').hidden) { closeModal(); return; }
    closeMenu();
  }
});
