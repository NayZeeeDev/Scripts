/* ═══════════════════════════════════════════════════════════
   NAYZEEE OPTIMIZER — app.js
   Version: 1.1.0
   ═══════════════════════════════════════════════════════════ */

const app        = document.getElementById('app');
const closeBtn   = document.getElementById('closeBtn');
const navs       = document.querySelectorAll('.nav');
const presetBtns = document.querySelectorAll('.preset');
const settingRows= document.querySelectorAll('.row[data-setting]');
const effectRows = document.querySelectorAll('.row[data-effect]');

const $ = id => document.getElementById(id);

// Mirrors Config.Presets for instant UI feedback. Replaced by the real
// presets from config.lua on open, so server edits are reflected.
const ALL_TOGGLES = ['optimizePeds','optimizeVehicles','optimizeObjects','removeParticles',
  'optimizeShadows','optimizeLights','lowTextures','disableDecals','disableBloodStains',
  'disableFireEffects','disableRain','disableWind','clearBrokenGlass','cleanPedEffects',
  'clearUnnecessary','entityCleanup','ultraMode'];

const P = (...keys) => {
  const o = {};
  ALL_TOGGLES.forEach(k => o[k] = keys.includes(k));
  return o;
};

let PRESET_STATE = {
  quality: P(),
  balanced: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles',
    'optimizeLights','disableDecals','clearBrokenGlass','cleanPedEffects',
    'clearUnnecessary','entityCleanup'),
  performance: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles',
    'optimizeShadows','optimizeLights','lowTextures','disableDecals','disableBloodStains',
    'disableRain','disableWind','clearBrokenGlass','cleanPedEffects','clearUnnecessary',
    'entityCleanup','ultraMode'),
  potato: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles',
    'optimizeShadows','optimizeLights','lowTextures','disableDecals','disableBloodStains',
    'disableFireEffects','disableRain','disableWind','clearBrokenGlass','cleanPedEffects',
    'clearUnnecessary','entityCleanup','ultraMode'),
  streaming: P('optimizePeds','optimizeObjects','optimizeLights','disableDecals',
    'clearBrokenGlass','cleanPedEffects','clearUnnecessary','entityCleanup'),
  shooter: P('optimizePeds','optimizeVehicles','optimizeObjects','removeParticles',
    'optimizeShadows','optimizeLights','disableDecals','disableBloodStains',
    'disableFireEffects','disableRain','disableWind','clearBrokenGlass','cleanPedEffects',
    'clearUnnecessary','entityCleanup'),
};

const PRESET_LABEL = {
  quality:'Quality', balanced:'Balanced', performance:'Performance',
  potato:'Potato', streaming:'Streaming', shooter:'Shooter', custom:'Custom'
};

const GRADE_LABEL = { excellent:'Excellent', good:'Good', ok:'OK', poor:'Poor', bad:'Bad' };
const VERDICT_LABEL = {
  healthy:'Healthy', monitor:'Monitor', edit:'Edit recommended',
  'edit-required':'Edit required', remove:'Remove or replace'
};

let currentSettings = {};
let isOpen = false;
let sessionMinutes = 0;
let lockedKeys = new Set();
let impactMap = {};
let conflictMap = {};
let uiFlags = {};
let isAdmin = false;
let benchResults = {};
let benchDuration = 30;

/* ═══════════════ NUI ═══════════════ */
// FiveM injects GetParentResourceName(); never define our own.
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
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/* ═══════════════════════════════════════════════════════════
   HARDWARE DETECTION
   NUI runs in Chromium: GPU string via WEBGL_debug_renderer_info, CPU
   threads, memory (capped at 8 by Chrome), resolution, refresh estimate.
   The refresh estimate follows the NUI frame pacing, so it is a hint.
   ═══════════════════════════════════════════════════════════ */

const TIER_INFO = {
  ultra:  { name:'High-end',     preset:'quality',     note:'Your hardware handles GTA comfortably. Visual quality over raw frames.' },
  high:   { name:'Strong',       preset:'balanced',    note:'Plenty of headroom. Balanced keeps things sharp with a solid frame rate.' },
  mid:    { name:'Mid-range',    preset:'balanced',    note:'A good all-rounder. Balanced trims the expensive effects and keeps the look.' },
  low:    { name:'Entry-level',  preset:'performance', note:'Performance strips the heavy effects so busy areas stay playable.' },
  potato: { name:'Low-end',      preset:'potato',      note:'Integrated or older graphics. Potato cuts everything it can for frames.' },
};

function detectGPU() {
  try {
    const c = document.createElement('canvas');
    const gl = c.getContext('webgl') || c.getContext('experimental-webgl');
    if (!gl) return null;
    const dbg = gl.getExtension('WEBGL_debug_renderer_info');
    if (!dbg) return null;
    const raw = gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL);
    return raw || null;
  } catch (e) { return null; }
}

function prettyGPU(raw) {
  if (!raw) return null;
  let s = String(raw);
  const angle = s.match(/^ANGLE\s*\(([^,]+),\s*(.+?)(?:\s+Direct3D\d+|\s+vs_\d|\s*,\s*D3D\d+)/i);
  if (angle) s = angle[2];
  return s.replace(/\((?:R|TM|C)\)/gi, '')
          .replace(/[™®]/g, '')
          .replace(/\s*Direct3D\d+.*$/i, '')
          .replace(/\s*vs_\d.*$/i, '')
          .replace(/\s+/g, ' ')
          .trim() || null;
}

function classifyGPU(raw) {
  if (!raw) return null;
  const s = String(raw).toLowerCase()
    .replace(/\((?:r|tm|c)\)/g, ' ')
    .replace(/[™®]/g, ' ')
    .replace(/\s+/g, ' ');
  let m;

  if ((m = s.match(/rtx\s*(\d{4})/))) {
    const n = +m[1], gen = Math.floor(n / 1000), t = n % 1000;
    if (gen >= 4) return t >= 70 ? 'ultra' : 'high';
    if (gen === 3) return t >= 70 ? 'ultra' : t >= 60 ? 'high' : 'mid';
    if (gen === 2) return t >= 70 ? 'high' : 'mid';
    return 'mid';
  }
  if ((m = s.match(/gtx\s*(\d{3,4})/))) {
    const n = +m[1];
    if (n >= 1060) return 'mid';
    if (n >= 950)  return 'low';
    return 'potato';
  }
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
    gpu: prettyGPU(rawGpu),
    gpuRaw: rawGpu,
    threads,
    ram: memRaw ? (memRaw >= 8 ? '8 GB+' : memRaw + ' GB') : null,
    ramExact: memRaw,
    width: window.screen ? window.screen.width : null,
    height: window.screen ? window.screen.height : null,
    hz,
    tier,
    guessed,
  };
}

/* ═══════════════ GRAPHICS RECOMMENDATIONS ═══════════════ */

function gfxRecommendations(spec) {
  const t = spec.tier || 'mid';
  const hi = (t === 'ultra' || t === 'high');
  const lo = (t === 'potato' || t === 'low');

  const R = [];
  const add = (name, value, why, off) => R.push({ name, value, why, off: !!off });

  add('Texture Quality', hi ? 'Very High' : t === 'mid' ? 'High' : 'Normal',
      'Costs VRAM, not frames. Keep it high unless textures stutter.');
  add('Shader Quality', hi ? 'Very High' : t === 'mid' ? 'High' : 'Normal',
      'Affects surface detail across the whole world.');
  add('Shadow Quality', hi ? 'High' : 'Normal',
      'One of the most expensive settings in GTA.');
  add('Reflection Quality', hi ? 'High' : t === 'mid' ? 'Normal' : 'Low',
      'Heavy in cities with lots of glass and water.');
  add('Water Quality', hi ? 'High' : 'Normal',
      'Only matters near water; cheap to leave up.');
  add('Particles Quality', hi ? 'High' : 'Normal',
      'Explosions and smoke in firefights.');
  add('Grass Quality', hi ? 'High' : t === 'mid' ? 'Normal' : 'Low',
      'Big cost off-road, none downtown.');
  add('Anti-Aliasing (FXAA)', 'On',
      'Cheap edge smoothing. Leave it on.');
  add('MSAA', hi ? 'x2' : 'Off', hi
      ? 'Sharper edges; drop to Off if you want more frames.'
      : 'Very expensive. Off is the right call here.', !hi);
  add('Population Density', t === 'mid' ? '~50%' : hi ? '~66%' : '~33%',
      'The Optimizer already trims this in-game, so a mid slider is fine.');
  add('Population Variety', hi ? '~66%' : '~33%',
      'Fewer unique models means less streaming and less stutter.');
  add('Distance Scaling', hi ? '~66%' : t === 'mid' ? '~50%' : '~33%',
      'Directly drives how much world is drawn each frame.');
  add('Extended Distance Scaling', lo ? 'Off' : '~25%',
      'Big cost for detail most players never look at.', lo);
  add('High Detail Streaming While Flying', 'Off',
      'Only helps in aircraft and costs a lot of memory.', true);
  add('Long Shadows', 'Off',
      'Pure cosmetic cost at dawn and dusk.', true);
  add('DirectX Version', 'DirectX 11',
      'Most stable for FiveM. DX12 can stutter on some drivers.');
  add('Pause Game On Focus Loss', 'Off',
      'Stops the game hitching when you alt-tab.', true);
  if (spec.hz) {
    add('VSync', 'On',
        `Locks frames to your ${spec.hz}Hz display. The single biggest thing you can do for GPU heat.`);
  }
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

  set('--teal',    theme.Primary);
  set('--teal-hi', theme.PrimaryHi);
  set('--teal-lo', theme.PrimaryLo);
  set('--red',     theme.Danger);
  set('--red-lo',  theme.DangerLo);
  set('--amber',   theme.Amber);
  set('--base',    theme.Base);
  set('--panel',   theme.Panel);
  set('--raise',   theme.Raise);
  set('--inset',   theme.Inset);
  set('--ink',     theme.Text);
  set('--ink-2',   theme.TextMuted);
  set('--ink-3',   theme.TextDim);

  const p = hexToRgb(theme.Primary);
  if (p) {
    root.style.setProperty('--primary-rgb', p.join(', '));
    root.style.setProperty('--teal-wash', `rgba(${p[0]}, ${p[1]}, ${p[2]}, .11)`);
    root.style.setProperty('--teal-edge', `rgba(${p[0]}, ${p[1]}, ${p[2]}, .34)`);
  }
  const d = hexToRgb(theme.Danger);
  if (d) root.style.setProperty('--red-wash', `rgba(${d[0]}, ${d[1]}, ${d[2]}, .11)`);
}

/* ═══════════════ SOUND ═══════════════ */
const soundCache = {};
const KILL_SOUNDS = ['hitmarker','headshot','eliminated','takedown','frag','noscope',
  'collateral','multikill','unstoppable','godlike','domination','rampage',
  'killingspree','savage','brutal','lethal','execution','finisher'];

function playSound(soundId, volume) {
  if (!/^[a-z0-9_-]+$/i.test(String(soundId || ''))) return;
  const vol = Math.min(100, Math.max(0, volume || 50)) / 100;
  const isKill = KILL_SOUNDS.includes(soundId);

  Object.keys(soundCache).forEach(key => {
    if (KILL_SOUNDS.includes(key) === isKill && soundCache[key]) {
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
    case 'updateSettings':     applySettings(d.settings); setStatus(d.preset || null); break;
    case 'playSound':          playSound(d.soundId, d.volume); break;
    case 'stats':              updateStats(d); break;
    case 'admin':              setAdmin(d.isAdmin); break;
    case 'benchResult':        benchResults = d.results || benchResults; renderBench(); break;
    case 'healthServer':       health.server = d; renderHealthServer(); break;
    case 'healthClient':       health.client = d; if (health.view === 'mine') renderResourceTable(); renderCoverage(); break;
    case 'healthClientFrames': health.clientFrames = d; if (health.view === 'mine') renderCoverage(); break;
    case 'healthStatus':       setHealthStatus(d.message, d.kind); break;
  }
});

/* ═══════════════ OPEN / CLOSE ═══════════════ */
function openMenu(d) {
  const settings = d.settings || {};
  const meta = d.meta || {};
  uiFlags = d.ui || {};
  lockedKeys = new Set(Array.isArray(d.locked) ? d.locked : []);
  impactMap = d.impact || {};
  conflictMap = d.conflicts || {};
  benchResults = d.bench || {};
  benchDuration = meta.benchDuration || 30;

  if (d.presets && typeof d.presets === 'object') {
    const next = {};
    Object.keys(d.presets).forEach(k => {
      const o = {};
      ALL_TOGGLES.forEach(t => o[t] = d.presets[k][t] === true);
      next[k] = o;
    });
    if (Object.keys(next).length) PRESET_STATE = next;
  }

  applyUiFlags(meta);
  decorateRows();
  currentSettings = settings;
  applySettings(currentSettings);
  setStatus(meta.preset || null);
  renderBench();

  if (settings.specTier && !detectedSpec) {
    detectedSpec = {
      gpu: settings.specGpu || null,
      threads: settings.specThreads || null,
      ram: settings.specRam || null,
      width: settings.specWidth || null,
      height: settings.specHeight || null,
      hz: settings.specHz || null,
      tier: settings.specTier || null,
      guessed: !!settings.specGuessed,
    };
    renderSpecs(detectedSpec);
  }

  if (settings.setupDone === false) openSetup();
  updateStats(meta);
  setAdmin(!!meta.isAdmin);
  app.classList.add('open');
  isOpen = true;
}

function hideUI() {
  app.classList.remove('open');
  isOpen = false;
  closeModal();
  if (health.open) { health.open = false; }
}

// Always releases NUI focus.
function closeMenu() {
  hideUI();
  post('close');
}

function applyUiFlags(meta) {
  const nav = $('navGraphics');
  if (nav) nav.hidden = uiFlags.graphicsTab === false;
  if (uiFlags.graphicsTab === false && $('page-graphics').classList.contains('on')) goPage('boost');

  const fix = $('fixTexturesBtn');
  if (fix) fix.hidden = uiFlags.textureFix === false;

  const fcBlock = $('frameCapBlock');
  const fc = uiFlags.frameCap || {};
  if (fcBlock) fcBlock.hidden = fc.enabled === false;
  const sel = $('frameCapSelect');
  if (sel && Array.isArray(fc.targets)) {
    const cur = sel.value;
    sel.innerHTML = '<option value="0">Uncapped</option>' +
      fc.targets.map(t => `<option value="${+t}">${+t} fps</option>`).join('');
    sel.value = cur;
  }

  const tele = $('telemetryRow');
  if (tele) tele.hidden = uiFlags.telemetry === false;

  const setup = uiFlags.setup || {};
  if ($('optAuto')) $('optAuto').hidden = setup.allowAutoDetect === false;
  if ($('setupSkip')) $('setupSkip').hidden = setup.allowSkip === false;

  if ($('keyLabel') && meta.key) $('keyLabel').textContent = meta.key;
  if ($('benchDur')) $('benchDur').textContent = benchDuration;
}

// Impact badges, locks and conflict warnings on every toggle row.
function decorateRows() {
  const all = [...settingRows, ...effectRows];
  all.forEach(r => {
    const k = r.dataset.setting || r.dataset.effect;
    const txt = r.querySelector('.row-txt');
    if (!txt) return;
    txt.querySelectorAll('.tags, .warn-line').forEach(el => el.remove());

    const tags = [];
    const imp = impactMap[k];
    if (imp) {
      if (imp.fps && imp.fps !== 'none') tags.push(`<i class="tag fps-${esc(imp.fps)}">+fps ${esc(imp.fps)}</i>`);
      if (imp.visual && imp.visual !== 'none') tags.push(`<i class="tag vis-${esc(imp.visual)}">visual ${esc(imp.visual)}</i>`);
    }
    const locked = lockedKeys.has(k);
    r.classList.toggle('locked', locked);
    if (locked) tags.push('<i class="tag lock">locked by server</i>');
    if (tags.length) {
      const wrap = document.createElement('span');
      wrap.className = 'tags';
      wrap.innerHTML = tags.join('');
      txt.appendChild(wrap);
    }

    const c = conflictMap[k];
    r.classList.toggle('conflict', !!c);
    if (c) {
      const w = document.createElement('span');
      w.className = 'warn-line';
      w.textContent = `${c.resource}: ${c.message}`;
      txt.appendChild(w);
    }
  });

  // Fix Textures conflict (action, not a setting)
  const fix = $('fixTexturesBtn');
  if (fix) {
    const txt = fix.querySelector('.row-txt');
    txt.querySelectorAll('.warn-line').forEach(el => el.remove());
    const c = conflictMap.fixTextures;
    if (c) {
      const w = document.createElement('span');
      w.className = 'warn-line';
      w.textContent = `${c.resource}: ${c.message}`;
      txt.appendChild(w);
    }
  }
}

/* ═══════════════ STATE ═══════════════ */
function applySettings(settings) {
  currentSettings = settings || {};

  settingRows.forEach(r => {
    const k = r.dataset.setting;
    if (k && currentSettings[k] !== undefined) r.classList.toggle('on', currentSettings[k] === true);
  });

  effectRows.forEach(r => {
    const k = r.dataset.effect;
    if (k && currentSettings[k] !== undefined) r.classList.toggle('on', currentSettings[k] === true);
  });

  setVal('killFxSelect',      currentSettings.killFx);
  setVal('killSoundSelect',   currentSettings.killSoundId);
  setVal('hitFxSelect',       currentSettings.hitFx);
  setVal('hitParticleSelect', currentSettings.hitParticleId);
  setVal('hitSoundSelect',    currentSettings.hitSoundId);

  setSlider('killVolumeSlider','killVolumeValue', currentSettings.killSoundVolume);
  setSlider('hitVolumeSlider', 'hitVolumeValue',  currentSettings.hitSoundVolume);

  refreshCounts();
}

function setVal(id, v) {
  const el = $(id);
  if (el && v !== undefined && v !== null) el.value = v;
}

function setSlider(sliderId, valId, v) {
  const s = $(sliderId);
  const l = $(valId);
  if (s && v !== undefined) { s.value = v; if (l) l.textContent = v + '%'; }
}

function refreshCounts() {
  let active = 0;
  settingRows.forEach(r => { if (r.classList.contains('on')) active++; });

  const tally = $('activeTally');
  const stat  = $('statActive');
  if (tally) { tally.textContent = active; tally.classList.toggle('live', active > 0); }
  if (stat)  stat.textContent = active;
}

function updateStats(d) {
  if (d.overshootMargin !== undefined) capOvershoot = d.overshootMargin;
  if (d.frameCapTarget !== undefined && d.frameCapTarget !== capTarget) {
    capTarget = d.frameCapTarget;
    const sel = $('frameCapSelect');
    if (sel) sel.value = String(capTarget);
    renderGuide();
  }
  if (d.fps !== undefined) {
    lastFps = d.fps;
    renderCapNote();
    const el = $('statFps');
    if (el) el.innerHTML = `${d.fps}<em>fps</em>`;
  }
  if (d.sessionMinutes !== undefined) {
    sessionMinutes = d.sessionMinutes;
    const el = $('statSession');
    if (el) {
      el.innerHTML = sessionMinutes >= 60
        ? `${Math.floor(sessionMinutes/60)}<em>h</em> ${sessionMinutes%60}<em>m</em>`
        : `${sessionMinutes}<em>m</em>`;
    }
  }
  if (d.preset !== undefined) setStatus(d.preset);
  if (d.pools) renderLive(d.pools, d.systems || {});
}

function renderLive(p, s) {
  const set = (id, v, cls) => { const e = $(id); if (!e) return; e.textContent = v; e.className = cls || ''; };
  set('lvVeh', p.vehicles);
  set('lvPed', p.peds);
  set('lvObj', p.objects);
  set('lvScr', p.scripted);
  set('lvAmb', `${s.ambient != null ? s.ambient : 100}%`, s.ambient != null && s.ambient < 100 ? 'hot' : '');
  set('lvAdp', s.adaptive ? `Level ${s.adaptive}` : 'Off', s.adaptive ? 'warn' : '');
  set('lvPrb', s.probes != null ? `${s.probes} active` : '—', s.probes ? 'hot' : '');
}

function setStatus(preset) {
  const t = $('statusText');
  if (!t) return;
  t.innerHTML = preset && PRESET_LABEL[preset]
    ? `Running <b>${PRESET_LABEL[preset]}</b> profile`
    : `<b>Custom</b> configuration`;
}

/* ═══════════════ NAV ═══════════════ */
function goPage(page) {
  const leavingHealth = $('page-health').classList.contains('on') && page !== 'health';
  navs.forEach(x => x.classList.toggle('on', x.dataset.page === page));
  document.querySelectorAll('.page').forEach(p => p.classList.remove('on'));
  const target = $('page-' + page);
  if (target) target.classList.add('on');
  if (page === 'health') { health.open = true; post('healthOpen'); }
  else if (leavingHealth) { health.open = false; post('healthClose'); }
}

navs.forEach(n => n.addEventListener('click', () => goPage(n.dataset.page)));

/* ═══════════════ CLOSE ═══════════════ */
closeBtn.addEventListener('click', () => { closeMenu(); });

/* ═══════════════ TOGGLES ═══════════════ */
function flashLocked(row) {
  row.classList.add('shake');
  setTimeout(() => row.classList.remove('shake'), 300);
}

settingRows.forEach(r => {
  r.addEventListener('click', () => {
    const k = r.dataset.setting;
    if (!k) return;
    if (lockedKeys.has(k)) { flashLocked(r); return; }
    const on = r.classList.toggle('on');
    currentSettings[k] = on;
    refreshCounts();
    setStatus(null);
    post('toggle', { setting:k, value:on }).then(res => {
      if (res && res.ok === false) {
        r.classList.toggle('on', !on);
        currentSettings[k] = !on;
        refreshCounts();
      }
    });
  });
});

effectRows.forEach(r => {
  r.addEventListener('click', () => {
    const k = r.dataset.effect;
    if (!k) return;
    if (lockedKeys.has(k)) { flashLocked(r); return; }
    const on = r.classList.toggle('on');
    currentSettings[k] = on;
    post('setEffectValue', { setting:k, value:on }).then(res => {
      if (res && res.ok === false) {
        r.classList.toggle('on', !on);
        currentSettings[k] = !on;
      }
    });
  });
});

/* ═══════════════ PRESETS ═══════════════ */
function applyPresetLocally(p) {
  if (!PRESET_STATE[p]) return;
  settingRows.forEach(r => {
    const k = r.dataset.setting;
    if (k && PRESET_STATE[p][k] !== undefined && !lockedKeys.has(k)) {
      r.classList.toggle('on', PRESET_STATE[p][k] === true);
      currentSettings[k] = PRESET_STATE[p][k];
    }
  });
  refreshCounts();
}

presetBtns.forEach(b => {
  b.addEventListener('click', () => {
    const p = b.dataset.preset;
    if (!p) return;
    post('preset', { preset:p });
    setStatus(p);
    applyPresetLocally(p);
    presetBtns.forEach(x => x.classList.remove('hot'));
    b.classList.add('hot');
    setTimeout(() => b.classList.remove('hot'), 900);
  });
});

/* ═══════════════ SELECTS ═══════════════ */
[['killFxSelect','killFx'], ['hitFxSelect','hitFx'],
 ['killSoundSelect','killSoundId'], ['hitSoundSelect','hitSoundId'],
 ['hitParticleSelect','hitParticleId']].forEach(([id, key]) => {
  const el = $(id);
  if (!el) return;
  el.addEventListener('change', e => {
    currentSettings[key] = e.target.value;
    post('setEffectValue', { setting:key, value:e.target.value });
  });
  el.addEventListener('click', e => e.stopPropagation());
});

/* ═══════════════ SLIDERS ═══════════════ */
[['killVolumeSlider','killVolumeValue','killSoundVolume'],
 ['hitVolumeSlider','hitVolumeValue','hitSoundVolume']].forEach(([sId, vId, key]) => {
  const el = $(sId);
  if (!el) return;
  el.addEventListener('input', e => {
    const v = parseInt(e.target.value);
    $(vId).textContent = v + '%';
    currentSettings[key] = v;
    post('setEffectValue', { setting:key, value:v });
  });
  el.addEventListener('click', e => e.stopPropagation());
});

/* ═══════════════ PREVIEWS ═══════════════ */
document.querySelectorAll('.icon-btn[data-preview]').forEach(btn => {
  btn.addEventListener('click', e => {
    e.stopPropagation();
    const t = btn.dataset.preview;

    if (t === 'killFx')            post('previewScreenFx', { fx: val('killFxSelect') });
    else if (t === 'hitFx')        post('previewScreenFx', { fx: val('hitFxSelect') });
    else if (t === 'hitParticle')  post('previewParticle', { id: val('hitParticleSelect') });
    else if (t === 'killSound')    playSound(val('killSoundSelect'), parseInt(val('killVolumeSlider')));
    else if (t === 'hitSound')     playSound(val('hitSoundSelect'), parseInt(val('hitVolumeSlider')));

    btn.style.background = 'rgba(8,175,162,.3)';
    setTimeout(() => { btn.style.background = ''; }, 260);
  });
});

function val(id) {
  const el = $(id);
  return el ? el.value : null;
}

/* ═══════════════ FIX TEXTURES ═══════════════ */
const fixBtn = $('fixTexturesBtn');
if (fixBtn) {
  fixBtn.addEventListener('click', () => {
    const btn   = fixBtn.querySelector('.btn-teal');
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
}

/* ═══════════════ BENCHMARK ═══════════════ */
const benchRun = $('benchRunBtn');
if (benchRun) {
  benchRun.addEventListener('click', () => {
    post('benchmark').then(res => {
      if (res && res.ok === false) {
        setModal('Benchmark busy', 'A benchmark or frame sample is already running. Try again in a few seconds.', null, 'Close');
      }
    });
  });
}
if ($('benchClear')) {
  $('benchClear').addEventListener('click', () => {
    benchResults = {};
    post('clearBenchmarks');
    renderBench();
  });
}

function renderBench() {
  const grid = $('benchGrid'), empty = $('benchEmpty'), count = $('benchCount'), clearWrap = $('benchClearWrap');
  if (!grid) return;
  const keys = Object.keys(benchResults || {});
  if (!keys.length) {
    grid.hidden = true; grid.innerHTML = '';
    if (empty) empty.hidden = false;
    if (count) count.textContent = '';
    if (clearWrap) clearWrap.hidden = true;
    return;
  }
  const rows = keys.map(k => ({ key: k, ...benchResults[k] })).sort((a, b) => (b.avgFps || 0) - (a.avgFps || 0));
  const base = benchResults.quality || rows[rows.length - 1];
  grid.innerHTML = rows.map((r, i) => {
    const delta = base && base.avgFps ? Math.round((r.avgFps - base.avgFps) / base.avgFps * 100) : 0;
    const showDelta = base && r.key !== (benchResults.quality ? 'quality' : rows[rows.length - 1].key);
    const tag = showDelta ? `<i class="${delta < 0 ? 'down' : ''}">${delta > 0 ? '+' : ''}${delta}%</i>` : (i === 0 ? '<i>best</i>' : '');
    return `
      <div class="bench${i === 0 ? ' best' : ''}">
        <div class="bench-top"><b>${esc(PRESET_LABEL[r.key] || r.key)}</b>${tag}</div>
        <div class="bench-nums">
          <div><span>Average</span><b>${r.avgFps}<em>fps</em></b></div>
          <div><span>1% low</span><b>${r.low1Fps}<em>fps</em></b></div>
          <div><span>Worst frame</span><b>${r.maxFt}<em>ms</em></b></div>
        </div>
        <div class="bench-foot">${r.frames} frames${r.stutters ? ` · ${r.stutters} stutter${r.stutters === 1 ? '' : 's'} over 50 ms` : ' · no stutters'}</div>
      </div>`;
  }).join('');
  grid.hidden = false;
  if (empty) empty.hidden = true;
  if (count) count.textContent = `${rows.length} profile${rows.length === 1 ? '' : 's'}${benchResults.quality ? ' · vs Quality' : ''}`;
  if (clearWrap) clearWrap.hidden = false;
}

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
  const json = decodeURIComponent(escape(atob(s.slice(4))));
  const obj = JSON.parse(json);
  if (!obj || typeof obj !== 'object') throw new Error('Invalid code');
  return obj;
}

let modalMode = null;
let modalAction = null;

function setModal(title, sub, code, primaryLabel, onPrimary, opts = {}) {
  const m = $('codeModal');
  $('modalTitle').textContent = title;
  $('modalSub').textContent = sub || '';
  const ta = $('modalCode');
  ta.hidden = code === null;
  ta.readOnly = !opts.editable;
  ta.value = code || '';
  ta.placeholder = opts.placeholder || '';
  const pb = $('modalPrimary');
  pb.hidden = !primaryLabel;
  pb.querySelector('span').textContent = primaryLabel || '';
  pb.classList.toggle('red', !!opts.danger);
  $('modalMsg').textContent = '';
  $('modalMsg').classList.remove('err');
  modalAction = onPrimary || null;
  m.hidden = false;
  if (opts.editable) setTimeout(() => ta.focus(), 30);
}

function closeModal() {
  const m = $('codeModal');
  if (m) m.hidden = true;
  modalAction = null;
}

function modalMsg(text, isErr) {
  const el = $('modalMsg');
  el.textContent = text;
  el.classList.toggle('err', !!isErr);
}

if ($('modalClose')) $('modalClose').addEventListener('click', closeModal);
if ($('modalPrimary')) $('modalPrimary').addEventListener('click', () => { if (modalAction) modalAction(); });

if ($('exportBtn')) {
  $('exportBtn').addEventListener('click', () => {
    const code = buildExportCode();
    setModal('Export settings', 'Share this code. Importing it applies every toggle and effect setting (not your hardware scan).', code, 'Copy', () => {
      const ta = $('modalCode');
      ta.focus(); ta.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch (e) {}
      if (!ok && navigator.clipboard) navigator.clipboard.writeText(ta.value).then(() => modalMsg('Copied to clipboard.')).catch(() => modalMsg('Select the code and press Ctrl+C.', true));
      else modalMsg(ok ? 'Copied to clipboard.' : 'Select the code and press Ctrl+C.', !ok);
    });
  });
}

if ($('importBtn')) {
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
}

if ($('resetBtn')) {
  $('resetBtn').addEventListener('click', () => {
    setModal('Reset to defaults', 'Every performance option and effect goes back to the server defaults. Your hardware scan and benchmark results are kept.', null, 'Reset', () => {
      post('resetDefaults');
      closeModal();
    }, { danger: true });
  });
}

/* ═══════════════ FRAME CAP HELPER ═══════════════ */
const GUIDES = {
  nvidia: t => [
    'Right-click your desktop and open <b>NVIDIA Control Panel</b>.',
    'Go to <b>Manage 3D settings</b> &rarr; <b>Program Settings</b>.',
    'Add or select <b>FiveM</b> (the FiveM_b____ GTAprocess executable).',
    `Set <b>Max Frame Rate</b> to <b>On</b> and enter <b>${t}</b>.`,
    'Apply, then fully restart FiveM — it will not take effect until you do.'
  ],
  amd: t => [
    'Open <b>AMD Software: Adrenalin Edition</b>.',
    'Go to <b>Gaming</b> and select your <b>FiveM</b> profile.',
    'Turn on <b>Frame Rate Target Control</b> (or <b>Radeon Chill</b>).',
    `Set the target to <b>${t}</b> fps. For Chill, set min and max both to <b>${t}</b>.`,
    'Apply, then fully restart FiveM.'
  ],
  gta: t => [
    'Press <b>ESC</b> and open <b>Settings</b> &rarr; <b>Graphics</b>.',
    'Scroll to <b>Frame Scaling Mode</b> / <b>VSync</b>.',
    `Turn <b>VSync On</b> — this locks frames to your monitor refresh rate.`,
    'Apply the settings and return to the game.',
    `Note: VSync locks to your display refresh, not an arbitrary ${t}. For an exact number use the GPU driver tab.`
  ]
};

let capTarget = 0;
let capGpu = 'nvidia';
let lastFps = 0;
let capOvershoot = 25;

function renderGuide() {
  const guide = $('capGuide');
  const steps = $('guideSteps');
  if (!guide || !steps) return;

  if (!capTarget) { guide.hidden = true; return; }
  guide.hidden = false;
  steps.innerHTML = GUIDES[capGpu](capTarget).map(s => `<li>${s}</li>`).join('');
}

function renderCapNote() {
  const note  = $('capNote');
  const title = $('capNoteTitle');
  const body  = $('capNoteBody');
  if (!note || !title || !body) return;

  note.classList.remove('good','warn');

  if (!capTarget) {
    title.textContent = 'Running uncapped';
    body.textContent  = 'Uncapped frames push your GPU flat out for frames your monitor never shows. Pick your refresh rate above for setup steps.';
    return;
  }

  if (!lastFps) {
    title.textContent = `Target ${capTarget} fps`;
    body.textContent  = 'Follow the steps below, then restart FiveM and check back here.';
    return;
  }

  if (lastFps > capTarget + capOvershoot) {
    note.classList.add('warn');
    title.textContent = `Not capped yet — ${lastFps} fps`;
    body.textContent  = `You're running well above your ${capTarget} fps target, so the cap isn't active. Follow the steps below and restart FiveM.`;
  } else {
    note.classList.add('good');
    title.textContent = `Capped at ~${capTarget} fps`;
    body.textContent  = 'Your frame rate matches your target. This is the single biggest thing you can do for GPU temperature.';
  }
}

const frameCapSelect = $('frameCapSelect');
if (frameCapSelect) {
  frameCapSelect.addEventListener('change', e => {
    capTarget = parseInt(e.target.value) || 0;
    post('setFrameCapTarget', { target: capTarget });
    renderCapNote();
    renderGuide();
  });
  frameCapSelect.addEventListener('click', e => e.stopPropagation());
}

document.querySelectorAll('.guide-tabs .gt').forEach(b => {
  b.addEventListener('click', () => {
    document.querySelectorAll('.guide-tabs .gt').forEach(x => x.classList.remove('on'));
    b.classList.add('on');
    capGpu = b.dataset.gpu;
    renderGuide();
  });
});

/* ═══════════════════════════════════════════════════════════
   FIRST-RUN SETUP + GRAPHICS PAGE
   ═══════════════════════════════════════════════════════════ */

let detectedSpec = null;
let recommendedPreset = null;

function showStep(id) {
  document.querySelectorAll('.setup-step').forEach(s => s.classList.remove('on'));
  const el = $(id);
  if (el) el.classList.add('on');
}

function openSetup() {
  const o = $('setupOverlay');
  if (!o) return;
  o.hidden = false;
  showStep('setupChoose');
}

function finishSetup() {
  const o = $('setupOverlay');
  if (o) o.hidden = true;
  post('setupDone');
}

function renderSpecs(spec) {
  const res = (spec.width && spec.height) ? `${spec.width} × ${spec.height}` : 'Unknown';
  const hz  = spec.hz ? `~${spec.hz} Hz` : 'Unknown';

  const setTxt = (id, v) => { const e = $(id); if (e) e.textContent = v; };
  setTxt('specGpu', spec.gpu || 'Not detected');
  setTxt('specCpu', spec.threads ? `${spec.threads} threads` : 'Unknown');
  setTxt('specRam', spec.ram || 'Unknown');
  setTxt('specRes', res);
  setTxt('specHz', hz);

  const info = TIER_INFO[spec.tier] || null;
  const tierEl = $('specTier');
  if (info) {
    setTxt('tierName', info.name + (spec.guessed ? ' (estimated)' : ''));
    setTxt('tierNote', spec.guessed
      ? 'Your graphics card was masked by the driver, so this is based on CPU threads. Adjust if it feels off.'
      : info.note);
    if (tierEl) tierEl.classList.toggle('warn', !!spec.guessed);
  } else {
    setTxt('tierName', 'Not detected');
    setTxt('tierNote', 'Your hardware could not be read. Pick a profile that feels right and adjust from there.');
    if (tierEl) tierEl.classList.add('warn');
  }

  const empty = $('specEmpty'), list = $('specList'), rescan = $('rescanBtn');
  if (empty)  empty.hidden = true;
  if (list)   list.hidden = false;
  if (rescan) rescan.hidden = false;

  renderGfx(spec);
}

function renderGfx(spec) {
  const list = $('gfxList'), intro = $('gfxIntro'), foot = $('gfxFoot'), count = $('gfxCount');
  if (!list) return;
  const recs = gfxRecommendations(spec);
  list.innerHTML = recs.map(r => `
    <div class="gfx">
      <div class="gfx-top">
        <b>${esc(r.name)}</b>
        <span class="gfx-val${r.off ? ' off' : ''}">${esc(r.value)}</span>
      </div>
      <span>${esc(r.why)}</span>
    </div>`).join('');
  list.hidden = false;
  if (intro) intro.hidden = true;
  if (foot) foot.hidden = false;
  if (count) count.textContent = `${recs.length} settings`;
}

async function runScan(onDone) {
  showStep('setupScan');
  const bar = $('scanBar'), status = $('scanStatus');
  const steps = [
    [18, 'Checking graphics card…'],
    [42, 'Reading CPU and memory…'],
    [70, 'Measuring display refresh rate…'],
    [92, 'Matching a profile…'],
  ];
  let i = 0;
  const timer = setInterval(() => {
    if (i >= steps.length) return;
    if (bar) bar.style.width = steps[i][0] + '%';
    if (status) status.textContent = steps[i][1];
    i++;
  }, 380);

  const spec = await detectSpecs();
  clearInterval(timer);
  if (bar) bar.style.width = '100%';

  detectedSpec = spec;
  const info = TIER_INFO[spec.tier];
  recommendedPreset = info ? info.preset : 'balanced';

  post('saveSpec', {
    gpu: spec.gpu || '', threads: spec.threads || 0,
    ram: spec.ram || '', width: spec.width || 0, height: spec.height || 0,
    hz: spec.hz || 0, tier: spec.tier || '', guessed: !!spec.guessed,
  });

  renderSpecs(spec);
  if (onDone) onDone(spec, info);
}

function showResult(spec, info) {
  const res = (spec.width && spec.height) ? `${spec.width} × ${spec.height}` : 'Unknown';
  const rows = [
    ['Graphics card', spec.gpu || 'Not detected', true],
    ['CPU threads', spec.threads ? `${spec.threads}` : 'Unknown', false],
    ['Memory', spec.ram || 'Unknown', false],
    ['Resolution', res, false],
    ['Refresh rate', spec.hz ? `~${spec.hz} Hz` : 'Unknown', false],
  ];
  const holder = $('resultSpecs');
  if (holder) {
    holder.innerHTML = rows.map(([l, v, wide]) =>
      `<div class="rs${wide ? ' span2' : ''}"><label>${esc(l)}</label><b>${esc(v)}</b></div>`).join('');
  }

  const label = info ? (PRESET_LABEL[info.preset] || info.preset) : 'Balanced';
  const pn = $('pickName'), pw = $('pickWhy'), rt = $('resultTitle'), rs = $('resultSub');
  if (pn) pn.textContent = label;
  if (pw) pw.textContent = info ? info.note : 'A safe starting point you can tune from.';
  if (rt) rt.textContent = info ? `${info.name} system detected` : 'Could not read your hardware';
  if (rs) rs.textContent = info
    ? 'Based on what we found, this profile should give you the best balance. You can change it any time.'
    : 'Pick a profile that feels right — you can change it any time.';

  showStep('setupResult');
}

if ($('optAuto'))   $('optAuto').addEventListener('click', () => runScan(showResult));
if ($('optManual')) $('optManual').addEventListener('click', finishSetup);
if ($('setupSkip')) $('setupSkip').addEventListener('click', finishSetup);
if ($('pickOwn'))   $('pickOwn').addEventListener('click', finishSetup);

if ($('applyRec')) {
  $('applyRec').addEventListener('click', () => {
    const p = recommendedPreset || 'balanced';
    post('preset', { preset: p });
    setStatus(p);
    applyPresetLocally(p);
    finishSetup();
  });
}

if ($('scanBtn'))   $('scanBtn').addEventListener('click', () => runScan(null));
if ($('rescanBtn')) $('rescanBtn').addEventListener('click', () => runScan(null));

/* ═══════════════════════════════════════════════════════════
   HEALTH PAGE (admins)
   ═══════════════════════════════════════════════════════════ */

const health = { server: null, client: null, clientFrames: null, view: 'server', open: false };

function setAdmin(flag) {
  isAdmin = !!flag;
  if ($('grpServer')) $('grpServer').hidden = !isAdmin;
  if ($('navHealth')) $('navHealth').hidden = !isAdmin;
  if (!isAdmin && $('page-health').classList.contains('on')) goPage('boost');
}

function fmtAgo(sec) {
  if (sec == null) return '';
  if (sec < 60) return `${Math.floor(sec)}s ago`;
  if (sec < 3600) return `${Math.floor(sec / 60)} min ago`;
  return `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m ago`;
}

function setHealthStatus(message, kind) {
  const n = $('hStatus');
  if (!n) return;
  n.hidden = !message;
  n.className = `note ${kind || 'info'}`;
  $('hStatusTitle').textContent = kind === 'error' ? 'Error' : kind === 'warn' ? 'Notice' : kind === 'ok' ? 'Done' : 'Working';
  $('hStatusBody').textContent = message || '';
  if (message && kind !== 'error') setTimeout(() => { if ($('hStatusBody').textContent === message) n.hidden = true; }, 12000);
}

function renderHealthServer() {
  const d = health.server;
  if (!d || !d.server) return;
  const s = d.server;

  const tile = $('hGradeTile');
  tile.className = `tile g-${s.grade}`;
  $('hGrade').textContent = GRADE_LABEL[s.grade] || '—';
  $('hHitch').innerHTML = `${s.tick.perHour}<em>/h</em>`;
  $('hMemLabel').textContent = s.memoryLabel || 'Memory';
  $('hMem').innerHTML = `${s.memoryMB}<em>MB</em>`;
  const c = d.clients || {};
  $('hClients').innerHTML = `${c.reporting || 0}<em>/ ${c.players != null ? c.players : s.players}</em>`;

  renderTimeline(s.timeline || [], s.tick);

  const tally = $('healthTally');
  if (tally) {
    const bad = (d.resources || []).filter(r => r.grade === 'bad' || r.grade === 'poor').length;
    tally.hidden = bad === 0;
    tally.textContent = bad;
    tally.classList.toggle('live', bad > 0);
  }

  const u = d.update || {};
  const un = $('hUpdate');
  if (un) {
    if (u.outdated) {
      un.hidden = false; un.className = 'note warn';
      $('hUpdateTitle').textContent = `Update available: ${u.current} → ${u.latest}`;
      $('hUpdateBody').textContent = `${u.notes || ''}${u.url ? ` ${u.url}` : ''}`.trim() || 'Download the latest version from your keymaster.';
    } else {
      un.hidden = true;
    }
  }

  const scanBtn = $('hScan');
  if (scanBtn) {
    const running = d.scan && d.scan.status === 'running';
    scanBtn.classList.toggle('busy', !!running);
    scanBtn.textContent = running ? 'Scanning…' : 'Deep scan';
  }
  const probeBtn = $('hProbe');
  if (probeBtn && d.probe) {
    probeBtn.textContent = d.probe.missing && d.probe.missing.length ? `Install probes (${d.probe.missing.length})` : 'Probes installed';
    probeBtn.classList.toggle('busy', !(d.probe.missing && d.probe.missing.length));
  }

  renderCoverage();
  renderResourceTable();
}

function renderTimeline(tl, tick) {
  const el = $('hTimeline');
  if (!el) return;
  let max = 1, total = 0, severe = 0;
  tl.forEach(b => { const h = b[0] || 0; total += h; severe += b[1] || 0; if (h > max) max = h; });
  el.innerHTML = tl.map((b, i) => {
    const h = b[0] || 0, s = b[1] || 0, n = h - s;
    const ago = tl.length - 1 - i;
    const title = h ? `${h} hitch${h === 1 ? '' : 'es'}${s ? ` (${s} severe)` : ''} · ${ago === 0 ? 'this minute' : `${ago} min ago`}` : `${ago === 0 ? 'this minute' : `${ago} min ago`} · clean`;
    return `<i title="${esc(title)}">${n ? `<b style="height:${Math.max(6, n / max * 100)}%"></b>` : ''}${s ? `<em style="height:${Math.max(6, s / max * 100)}%"></em>` : ''}</i>`;
  }).join('');
  $('hTlCount').textContent = total ? `${total} hitches · ${severe} severe` : 'no hitches';
  $('hTlInfo').textContent = tick ? `worst ${tick.worst} ms · avg drift ${tick.avgDrift} ms${tick.lastSevereAgo != null ? ` · last severe ${fmtAgo(tick.lastSevereAgo)}` : ''}` : '';
}

function renderCoverage() {
  const d = health.server;
  const title = $('hCovTitle'), body = $('hCovBody'), note = $('hCoverage'), legendNote = $('hLegendNote');
  if (!title) return;
  note.className = 'note';

  if (health.view === 'server') {
    legendNote.textContent = 'Load = % of server main thread';
    if (!d) { title.textContent = 'Waiting for data'; body.textContent = 'Requesting the server report…'; return; }
    const p = d.probe || {};
    const sc = d.scan || {};
    const missing = p.missing || [];
    title.textContent = `Probe active in ${p.covered || 0} of ${p.total || 0} started resources · ${p.reporting || 0} reporting now`;
    let txt = '';
    if (missing.length) {
      txt += `${missing.length} not covered: ${missing.slice(0, 12).join(', ')}${missing.length > 12 ? '…' : ''}. Click Install probes (adds one line to each manifest, backup kept), then restart those resources. `;
      note.classList.add('warn');
    } else if (p.total) {
      txt += 'Every Lua resource is covered. ';
    }
    if (p.legacy) txt += `${p.legacy} legacy __resource.lua manifest${p.legacy === 1 ? '' : 's'} need the line added by hand. `;
    if (sc.status === 'done') txt += `Deep scan: ${sc.count} resources over ${sc.frames} frames, ${fmtAgo(Math.max(0, Date.now() / 1000 - sc.at))}. `;
    else if (sc.status === 'running') txt += 'Deep scan running… ';
    else if (sc.status === 'error') { txt += `Deep scan failed: ${sc.error} `; }
    else txt += 'Run a Deep scan to grade JS/C# resources and anything without the probe. ';
    body.textContent = txt.trim();
  } else if (health.view === 'clients') {
    legendNote.textContent = 'Load = median ms per frame across players (resmon scale)';
    const c = d && d.clients;
    if (!c || !c.reporting) {
      title.textContent = 'No client data yet';
      body.textContent = 'Players send an anonymous FPS and script-load report every minute when "Share performance data" is on. Reports start about a minute after they join.';
      return;
    }
    title.textContent = `${c.reporting} of ${c.players} players sharing · avg ${c.fpsAvg} fps · avg 1% low ${c.lowAvg} fps`;
    body.textContent = `${c.under30}% of reporting players are under 30 fps, ${c.under45}% under 45 fps. A resource graded Poor or Bad here costs frame time on every player's PC, not just yours.`;
    if (c.under30 >= 25) note.classList.add('warn');
  } else {
    legendNote.textContent = 'Load = ms per frame on your PC (resmon scale)';
    const cl = health.client;
    const fr = health.clientFrames;
    if (!cl) { title.textContent = 'Waiting for probes'; body.textContent = 'Probe reports from your client arrive every 5 seconds.'; return; }
    const g = (fr && fr.grade) || cl.grade;
    title.textContent = `Your client: ${cl.fps} fps now${fr && fr.summary ? ` · 1% low ${fr.summary.low1Fps} fps · worst frame ${fr.summary.maxFt} ms` : ''}${g ? ` · ${GRADE_LABEL[g]}` : ''}`;
    const p = cl.pools || {};
    body.textContent = `${cl.probes} resources reporting on your client. Nearby: ${p.vehicles ?? '—'} vehicles, ${p.peds ?? '—'} peds, ${p.objects ?? '—'} objects (${p.scripted ?? 0} script-spawned). For a live per-frame view of every resource use the F8 console: resmon 1.`;
    if (g === 'poor' || g === 'bad') note.classList.add('warn');
  }
}

function loadCell(r, view) {
  if (view === 'server') return `${(r.load || 0).toFixed(2)}<em>%</em>`;
  return `${(r.load || 0).toFixed(3)}<em>ms</em>`;
}

function renderResourceTable() {
  const table = $('hTable'), empty = $('hTableEmpty');
  if (!table) return;
  const view = health.view;
  let rows = [];
  if (view === 'server') rows = (health.server && health.server.resources) || [];
  else if (view === 'clients') rows = (health.server && health.server.clients && health.server.clients.rows) || [];
  else rows = (health.client && health.client.rows) || [];

  if (!rows.length) {
    table.innerHTML = '';
    empty.hidden = false;
    $('hTableEmptyBody').textContent = view === 'server'
      ? 'Install the probe or run a deep scan to see server resources graded here.'
      : view === 'clients' ? 'No player reports yet.' : 'No probe reports from your client yet. Resources need the probe line and a restart.';
    return;
  }
  empty.hidden = true;

  const head = view === 'server'
    ? ['Resource','Load','Peak slice','Calls/s','Events/s','Lua mem','Grade','Verdict']
    : ['Resource','Load','Peak slice','Loops/frame','Events/s','Lua mem','Grade','Verdict'];

  const html = [`<div class="rt-head">${head.map(h => `<div>${h}</div>`).join('')}</div>`];
  rows.slice(0, 80).forEach(r => {
    const sub = view === 'clients' ? `${r.clients} client${r.clients === 1 ? '' : 's'}` : (r.source === 'scan' ? 'deep scan' : 'probe') + (r.scanLoad != null ? ` · scan ${r.scanLoad}%` : '');
    const peakCls = r.peakMs >= 50 ? 'bad' : r.peakMs >= 5 ? 'hot' : '';
    const third = view === 'server'
      ? `${Math.round(r.slicesPs || 0)}`
      : `${(r.loops || 0).toFixed(1)}`;
    const thirdCls = view !== 'server' && r.loops >= 8 ? 'bad' : view !== 'server' && r.loops >= 3 ? 'hot' : '';
    const evCls = r.eventsPs >= 200 ? 'bad' : r.eventsPs >= 50 ? 'hot' : '';
    const mem = r.memMB != null ? `${r.memMB.toFixed(1)} MB${r.memGrowth != null && r.memGrowth >= 10 ? ` ↑${r.memGrowth.toFixed(0)}/h` : ''}` : '—';
    const memCls = r.memGrowth != null && r.memGrowth >= 50 ? 'bad' : r.memGrowth != null && r.memGrowth >= 10 ? 'hot' : '';
    const hint = (r.hints && r.hints[0]) || '';
    const showHint = r.verdict !== 'healthy';
    html.push(`
      <div class="rt-row g-${esc(r.grade)}">
        <div class="rt-name"><b title="${esc(r.name)}">${esc(r.name)}</b><span>${esc(sub)}</span></div>
        <div class="rt-load">${loadCell(r, view)}</div>
        <div class="rt-m ${peakCls}">${(r.peakMs || 0).toFixed(1)} ms</div>
        <div class="rt-m ${thirdCls}">${third}</div>
        <div class="rt-m ${evCls}">${(r.eventsPs || 0).toFixed(0)}</div>
        <div class="rt-m ${memCls}">${mem}</div>
        <div><i class="pill g-${esc(r.grade)}">${GRADE_LABEL[r.grade] || r.grade}</i></div>
        <div class="rt-verdict v-${esc(r.verdict)}">${VERDICT_LABEL[r.verdict] || r.verdict}</div>
        ${showHint ? `<div class="rt-hint">${esc(hint)}</div>` : ''}
      </div>`);
  });
  table.innerHTML = html.join('');
}

document.querySelectorAll('#hSeg .gt').forEach(b => {
  b.addEventListener('click', () => {
    document.querySelectorAll('#hSeg .gt').forEach(x => x.classList.remove('on'));
    b.classList.add('on');
    health.view = b.dataset.view;
    renderCoverage();
    renderResourceTable();
  });
});

if ($('hRefresh')) $('hRefresh').addEventListener('click', () => { post('healthRefresh'); setHealthStatus('Refreshing…', 'info'); });

if ($('hScan')) {
  $('hScan').addEventListener('click', () => {
    setModal('Run a deep scan', 'Records 500 server frames with the built-in FXServer profiler (a few seconds), then grades every resource including JS and C#. The server keeps running normally; expect a small hitch when the trace is saved.', null, 'Start scan', () => {
      post('healthAction', { what: 'scan' });
      setHealthStatus('Deep scan requested…', 'info');
      closeModal();
    });
  });
}

if ($('hProbe')) {
  $('hProbe').addEventListener('click', () => {
    const d = health.server;
    const missing = (d && d.probe && d.probe.missing) || [];
    if (!missing.length) {
      setModal('Probes', 'Every started Lua resource already has the probe line. To remove it everywhere, run optimizerprobe remove in the server console.', null, null);
      return;
    }
    setModal('Install probes', `Adds "shared_script '@nayzeee-optimizerv2/probe.lua'" to the manifest of ${missing.length} resource${missing.length === 1 ? '' : 's'}. A backup of each manifest is written next to it. Nothing restarts automatically: run "refresh" and restart those resources (or the server) to activate. Remove any time with optimizerprobe remove.`, missing.join('\n'), 'Install', () => {
      post('healthAction', { what: 'probeInstall' });
      setHealthStatus('Installing probes…', 'info');
      closeModal();
    });
  });
}

/* ═══════════════ KEYBOARD ═══════════════ */
document.addEventListener('keyup', e => {
  if (e.key === 'Escape' && isOpen) {
    if (!$('codeModal').hidden) { closeModal(); return; }
    closeMenu();
  }
});
