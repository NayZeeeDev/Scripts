/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V2 · the salon
   Doing hair in first person. The hair itself goes on for real
   (props on the client's head, client/salon.lua); this file only
   draws small guides where to work (projected by Lua) and plays
   the move: trace · cornrow · braid · dab · sew · sweep · stroke ·
   circle · drag · hold.
   Also: the client's view while sitting, and the reveal.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const SL = {
  on: false, d: null, m: null, g: null, head: null, dec: [], mouse: { x: -999, y: -999, down: false, vx: 0, vy: 0 },
  keys: {}, braid: null, fx: [], sent: false, lastAct: 0, ends: 0, timer: 0,
};
const sl = {
  root: $('#salon'), cv: $('#slCanvas'), top: $('#slTop'), steps: $('#slSteps'), obj: $('#slObj'),
  tray: $('#slTray'), cursor: $('#slCursor'), keys: $('#slKeys'), flash: $('#slFlash'),
};
const ctx = sl.cv.getContext('2d');

/* ─────────────── tools (the cursor, and the tray art) ─────────────── */
const SL_TOOL = {
  hands: '<svg viewBox="0 0 64 64"><path d="M24 58V30c0-3 4-3 4 0v12V14c0-3 4-3 4 0v26V10c0-3 4-3 4 0v30V16c0-3 4-3 4 0v30c4-6 8-8 10-6s-4 8-8 16-8 8-14 8c-5 0-8-3-8-6z" fill="#e8c9ad" stroke="#8a6a52" stroke-width="2"/></svg>',
  rat_comb: '<svg viewBox="0 0 64 64"><rect x="6" y="20" width="34" height="9" rx="2" fill="#1d2023" stroke="currentColor" stroke-width="2"/><path d="M9 29v8M13 29v8M17 29v8M21 29v8M25 29v8M29 29v8M33 29v8M37 29v8" stroke="#1d2023" stroke-width="2.2"/><path d="M40 24 L62 22" stroke="#1d2023" stroke-width="3" stroke-linecap="round"/></svg>',
  paddle_brush: '<svg viewBox="0 0 64 64"><rect x="10" y="6" width="26" height="30" rx="11" fill="#1d2023" stroke="currentColor" stroke-width="2"/><g fill="#e8eef1">' + Array.from({ length: 15 }, (_, i) => `<circle cx="${16 + (i % 5) * 3.6}" cy="${13 + Math.floor(i / 5) * 7}" r="1.2"/>`).join('') + '</g><rect x="20" y="35" width="7" height="25" rx="3.5" fill="#1d2023" stroke="currentColor" stroke-width="2"/></svg>',
  edge_brush: '<svg viewBox="0 0 64 64"><rect x="28" y="22" width="7" height="38" rx="3" fill="#1d2023" stroke="currentColor" stroke-width="2"/><rect x="24" y="6" width="15" height="18" rx="3" fill="#2b2f33" stroke="currentColor" stroke-width="2"/><path d="M26 6V1M30 6V0M34 6V0M38 6V1" stroke="#e8eef1" stroke-width="1.6"/></svg>',
  c_needle: '<svg viewBox="0 0 64 64"><path d="M10 54 C 14 18, 46 10, 54 26" fill="none" stroke="#e6ecef" stroke-width="3.5" stroke-linecap="round"/><path d="M54 26 C 60 40, 30 52, 20 60" fill="none" stroke="#d7a63a" stroke-width="1.5" stroke-dasharray="3 2"/><circle cx="52" cy="22" r="2.5" fill="none" stroke="#9aa3a8" stroke-width="1.5"/></svg>',
  crochet_hook: '<svg viewBox="0 0 64 64"><path d="M16 58 L48 10" stroke="#c9ced2" stroke-width="4" stroke-linecap="round"/><path d="M48 10 q6 -2 4 6 l-4 -2" fill="none" stroke="#c9ced2" stroke-width="3"/><rect x="14" y="40" width="10" height="20" rx="4" transform="rotate(34 19 50)" fill="#e35b9f"/></svg>',
  flat_iron: '<svg viewBox="0 0 64 64"><path d="M22 60 L26 8 L32 8 L32 60 Z" fill="#1d2023" stroke="currentColor" stroke-width="2"/><path d="M34 60 L38 8 L44 8 L40 60 Z" fill="#1d2023" stroke="currentColor" stroke-width="2"/><rect x="25" y="10" width="17" height="20" rx="2" fill="#c9693a" opacity=".85"/></svg>',
  curl_wand: '<svg viewBox="0 0 64 64"><rect x="27" y="36" width="10" height="24" rx="4" fill="#1d2023" stroke="currentColor" stroke-width="2"/><rect x="29" y="4" width="6" height="34" rx="3" fill="#d48a5c" stroke="#9a5c38" stroke-width="1.5"/></svg>',
  blow_dryer: '<svg viewBox="0 0 64 64"><path d="M6 18 h30 a12 12 0 0 1 0 24 h-30 z" fill="#1d2023" stroke="currentColor" stroke-width="2"/><rect x="26" y="40" width="10" height="20" rx="3" fill="#1d2023" stroke="currentColor" stroke-width="2"/><circle cx="40" cy="30" r="5" fill="#2b2f33"/><path d="M2 22h4M2 30h4M2 38h4" stroke="#9aa3a8" stroke-width="2"/></svg>',
  shears: '<svg viewBox="0 0 64 64"><path d="M30 34 L54 6 Q57 5 56 9 L35 37 Z" fill="#e6ecef" stroke="#9aa3a8"/><path d="M34 34 L10 6 Q7 5 8 9 L29 37 Z" fill="#d4dbdf" stroke="#9aa3a8"/><circle cx="18" cy="49" r="7.5" fill="none" stroke="currentColor" stroke-width="4"/><circle cx="46" cy="49" r="7.5" fill="none" stroke="currentColor" stroke-width="4"/></svg>',
  braid_gel: '<svg viewBox="0 0 64 64"><rect x="12" y="20" width="40" height="34" rx="6" fill="#6fb6e8" opacity=".85" stroke="currentColor" stroke-width="2"/><rect x="10" y="12" width="44" height="10" rx="3" fill="#1d2023" stroke="currentColor" stroke-width="2"/><path d="M20 30 q12 8 24 0" stroke="#fff" stroke-width="2" opacity=".7" fill="none"/></svg>',
  edge_control: '<svg viewBox="0 0 64 64"><ellipse cx="32" cy="36" rx="24" ry="14" fill="#e3b34f" stroke="currentColor" stroke-width="2"/><ellipse cx="32" cy="30" rx="24" ry="10" fill="#1d2023" stroke="currentColor" stroke-width="2"/></svg>',
  mousse: '<svg viewBox="0 0 64 64"><rect x="20" y="18" width="24" height="42" rx="5" fill="#f2f2f2" stroke="currentColor" stroke-width="2"/><rect x="24" y="8" width="12" height="11" rx="2" fill="#1d2023"/><path d="M36 10 h10" stroke="#1d2023" stroke-width="4"/><rect x="20" y="32" width="24" height="12" fill="#e35b9f"/></svg>',
  spray: '<svg viewBox="0 0 64 64"><rect x="20" y="22" width="24" height="38" rx="6" fill="#d9e7ec" stroke="currentColor" stroke-width="2"/><path d="M26 22 v-8 h14 v6" fill="#1d2023"/><path d="M40 14 h8" stroke="#1d2023" stroke-width="3"/><rect x="20" y="34" width="24" height="10" fill="#08afa2"/></svg>',
  hair: '<svg viewBox="0 0 64 64"><path d="M14 8 C 10 30, 18 46, 12 60 M22 6 C 20 30, 26 46, 22 60 M30 6 C 30 30, 34 46, 32 60 M38 6 C 40 30, 42 46, 42 60 M46 8 C 50 30, 50 46, 52 60" stroke="var(--hc,#3a2418)" stroke-width="4" fill="none" stroke-linecap="round"/><rect x="10" y="4" width="44" height="8" rx="2" fill="#e8eef1" stroke="#9aa3a8"/></svg>',
  elastics: '<svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="18" fill="none" stroke="#1d2023" stroke-width="7"/><circle cx="32" cy="32" r="18" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>',
  bobby_pins: '<svg viewBox="0 0 64 64"><path d="M14 14 L50 50 M18 10 L54 46" stroke="#1d2023" stroke-width="3.2" stroke-linecap="round"/><circle cx="52" cy="48" r="3" fill="#1d2023"/></svg>',
  hair_beads: '<svg viewBox="0 0 64 64"><circle cx="22" cy="24" r="10" fill="#d6a43a" stroke="#8a6416" stroke-width="2"/><circle cx="42" cy="40" r="10" fill="#8a5a2b" stroke="#4d3014" stroke-width="2"/><circle cx="19" cy="21" r="3" fill="#fff" opacity=".6"/></svg>',
  wig_cap: '<svg viewBox="0 0 64 64"><path d="M8 44 C 8 14, 56 14, 56 44 Z" fill="#c9b49a" stroke="currentColor" stroke-width="2"/><path d="M14 40 L50 22 M20 44 L54 30 M10 32 L40 18 M30 44 L56 38" stroke="#8a7458" stroke-width="1"/></svg>',
  hot_water: '<svg viewBox="0 0 64 64"><path d="M14 22 h32 v26 a10 10 0 0 1 -10 10 h-12 a10 10 0 0 1 -10 -10 z" fill="#e8eef1" stroke="currentColor" stroke-width="2"/><path d="M46 28 h4 a6 6 0 0 1 0 12 h-4" fill="none" stroke="currentColor" stroke-width="2"/><path d="M22 16 q-4 -6 0 -10 M30 16 q-4 -6 0 -10 M38 16 q-4 -6 0 -10" stroke="#c9d6dc" stroke-width="2" fill="none"/></svg>',
  lace_closure: '<svg viewBox="0 0 64 64"><path d="M6 40 Q32 6 58 40 Q32 30 6 40z" fill="#e8c9ad" stroke="#a7866b" stroke-width="2"/><path d="M14 34 L50 34 M20 26 L44 26" stroke="#a7866b" stroke-width="1" stroke-dasharray="2 2"/></svg>',
  wig_thread: '<svg viewBox="0 0 64 64"><rect x="18" y="10" width="28" height="44" rx="4" fill="#1d2023" stroke="currentColor" stroke-width="2"/><path d="M18 18h28M18 24h28M18 30h28M18 36h28M18 42h28" stroke="#555" stroke-width="2"/></svg>',
};
SL_TOOL.heat_protect = SL_TOOL.spray; SL_TOOL.shine_spray = SL_TOOL.spray; SL_TOOL.moisturizer = SL_TOOL.spray;

const SL_VERB = {
  trace: 'Hold and follow the line', cornrow: 'A / D stitch by stitch · keep the cursor on the braid', braid: 'Press the strand keys on the beat',
  dab: 'Click each spot', sew: 'Click to push the needle in, flick up to pull the thread', sweep: 'Hold and cover the area',
  stroke: 'Hold at the root and drag to the tip', circle: 'Hold and turn around the spot', drag: 'Drag the hair to the ring',
  hold: 'Hold, let go in the green band',
};
const SL_ICON = { trace: 'fa-pen-nib', cornrow: 'fa-grip-lines', braid: 'fa-bars-staggered', dab: 'fa-hand-pointer', sew: 'fa-reply', sweep: 'fa-spray-can-sparkles', stroke: 'fa-hand', circle: 'fa-rotate', drag: 'fa-hand-back-fist', hold: 'fa-hourglass-half' };
const TOKEN = {
  R: ['D', 'Right over middle'], L: ['A', 'Left over middle'], r: ['D', 'Right under middle'], l: ['A', 'Left under middle'],
  A: ['A', 'Left piece across'], B: ['D', 'Right piece across'], D: ['SPACE', 'Drop the bottom strand'],
};

/* ─────────────── geometry in screen space ─────────────── */
let W = innerWidth, H = innerHeight, DPR = 1;
function fit() {
  DPR = Math.min(2, window.devicePixelRatio || 1);
  W = innerWidth; H = innerHeight;
  sl.cv.width = Math.round(W * DPR); sl.cv.height = Math.round(H * DPR);
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
}
addEventListener('resize', fit);
fit();

const P = (p) => ({ x: p[0] * W, y: p[1] * H, v: p[2] !== 0 });
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
function headR() {
  const h = SL.head;
  if (!h) return 220;
  return Math.max(60, Math.hypot((h[2] - h[0]) * W, (h[3] - h[1]) * H));
}
function geoPaths() { return SL.g && SL.g.kind === 'paths' ? SL.g.list.map((p) => p.map(P)) : []; }
function geoPoints() { return SL.g && SL.g.kind === 'points' ? SL.g.list.map(P) : []; }
function geoPairs() { return SL.g && SL.g.kind === 'pairs' ? SL.g.list.map((pr) => [P(pr[0]), P(pr[1])]) : []; }

function lengths(pts) {
  const L = [0];
  for (let i = 1; i < pts.length; i++) L.push(L[i - 1] + dist(pts[i - 1], pts[i]));
  return L;
}
// the point (and direction) a fraction t along a polyline
function along(pts, t) {
  if (!pts.length) return { x: 0, y: 0, dx: 0, dy: 1, v: false };
  const L = lengths(pts), tot = L[L.length - 1] || 1, want = clamp(t, 0, 1) * tot;
  for (let i = 1; i < pts.length; i++) {
    if (L[i] >= want) {
      const a = pts[i - 1], b = pts[i], k = (want - L[i - 1]) / Math.max(1e-6, L[i] - L[i - 1]);
      const len = Math.max(1e-6, dist(a, b));
      return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, dx: (b.x - a.x) / len, dy: (b.y - a.y) / len, v: a.v || b.v, i };
    }
  }
  const a = pts[pts.length - 2] || pts[0], b = pts[pts.length - 1], len = Math.max(1e-6, dist(a, b));
  return { x: b.x, y: b.y, dx: (b.x - a.x) / len, dy: (b.y - a.y) / len, v: b.v, i: pts.length - 1 };
}
// closest index on a polyline to a point
function nearestOn(pts, q) {
  let best = 0, bd = Infinity;
  for (let i = 0; i < pts.length; i++) { const d = dist(pts[i], q); if (d < bd) { bd = d; best = i; } }
  return { i: best, d: bd };
}

/* ─────────────── drawing ─────────────── */
function hairColour() { return SL.feeding ? SL.d.feedColour : SL.d.colour; }

function shade(hex, k) {
  const m = /rgb\((\d+),(\d+),(\d+)\)/.exec(hex);
  let r, g, b;
  if (m) { r = +m[1]; g = +m[2]; b = +m[3]; } else { [r, g, b] = hexRgb(hex || '#3a2418'); }
  const f = (v) => clamp(Math.round(k > 0 ? v + (255 - v) * k : v * (1 + k)), 0, 255);
  return `rgb(${f(r)},${f(g)},${f(b)})`;
}

function guidePath(pts, opts = {}) {
  ctx.save();
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.setLineDash(opts.dash || [2, 9]);
  ctx.lineWidth = opts.w || 3;
  ctx.strokeStyle = opts.c || 'rgba(255,255,255,.75)';
  ctx.shadowColor = 'rgba(0,0,0,.6)'; ctx.shadowBlur = 4;
  let open = false;
  ctx.beginPath();
  for (const p of pts) {
    if (!p.v) { open = false; continue; }
    if (!open) { ctx.moveTo(p.x, p.y); open = true; } else ctx.lineTo(p.x, p.y);
  }
  ctx.stroke();
  ctx.restore();
}

function ring(p, r, col, w = 2, frac = 1) {
  ctx.save(); ctx.strokeStyle = col; ctx.lineWidth = w; ctx.shadowColor = col; ctx.shadowBlur = 8;
  ctx.beginPath(); ctx.arc(p.x, p.y, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); ctx.stroke(); ctx.restore();
}
function dot(p, r, col) { ctx.save(); ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 10; ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, Math.PI * 2); ctx.fill(); ctx.restore(); }

function burst() { /* the effects are in game (spray, steam, clippings) */ }

/* ═══════════════ the moves ═══════════════ */
// every move: start(), tick(dt), draw(), down(), up(), key(e). It calls done(score) once.
const MOVES = {};
let MV = null;     // the running move's own state

function done(score) {
  if (SL.sent || !SL.m) return;
  SL.sent = true;
  score = Math.round(clamp(score, 0, 100));
  const keep = MV && MV.keep ? MV.keep() : null;
  post('salonMoveDone', { i: SL.m.i, score, keep });
  const word = score >= 92 ? 'Perfect' : score >= 75 ? 'Clean' : score >= 50 ? 'Okay' : 'Messy';
  flash(word, score >= 75 ? 'good' : score >= 50 ? '' : 'bad');
  if (score >= 75) SFX.hit(); else SFX.tick();
  burst(SL.mouse.x, SL.mouse.y, 'spark', score >= 92 ? 16 : 6);
}
function flash(text, cls) {
  sl.flash.textContent = text;
  sl.flash.className = 'sl-flash ' + (cls || '');
  void sl.flash.offsetWidth; sl.flash.classList.add('go');
}
let partAt = 0;
function part(f) {
  const t = performance.now();
  if (t - partAt < 400) return;
  partAt = t;
  post('salonPart', { i: SL.m.i, f: clamp(f, 0, 1) });
}
function act(kind) {
  const t = performance.now();
  if (t - SL.lastAct < 380) return;
  SL.lastAct = t;
  post('salonAct', { kind });
}
function progress(p, label) {
  const bar = $('#slBar'); if (bar) bar.style.width = Math.round(clamp(p, 0, 1) * 100) + '%';
  const tx = $('#slProg'); if (tx && label !== undefined) tx.textContent = label;
}
function keyPills(list) {
  sl.keys.innerHTML = (list || []).map((k) => `<span class="sl-pill ${k.on ? 'on' : ''} ${k.bad ? 'bad' : ''}" style="left:${Math.round(k.x)}px;top:${Math.round(k.y)}px"><span class="kc">${esc(k.key)}</span>${k.label ? `<em>${esc(k.label)}</em>` : ''}</span>`).join('');
}

/* trace: hold and follow the dotted line, path after path */
MOVES.trace = {
  target() { const pts = geoPaths()[MV.path]; if (!pts) return null; const j = Math.min(pts.length - 1, MV.prog + 2); return { k: MV.path, j, p: pts[j] }; },
  start() { MV = { path: 0, prog: 0, err: 0, samples: 0, slips: 0, keep: () => ({ k: 'part' }) }; },
  tick() {
    const paths = geoPaths(); const pts = paths[MV.path]; if (!pts) return;
    const tol = headR() * 0.2;
    if (SL.mouse.down) {
      const n = nearestOn(pts, SL.mouse);
      if (n.d < tol && n.i <= MV.prog + 3 && n.i >= MV.prog - 1) {
        if (n.i > MV.prog) { MV.prog = n.i; SFX.tick(); }
        MV.err += n.d / tol; MV.samples++;
      } else if (n.d > tol * 1.8 && MV.prog > 0 && !MV.slipped) { MV.slips++; MV.slipped = true; flash('Slipped', 'bad'); SFX.miss(); }
      if (n.d < tol) MV.slipped = false;
    }
    if (MV.prog >= pts.length - 1) {
      MV.path++; MV.prog = 0; SFX.hit();
      if (MV.path >= paths.length) {
        const acc = MV.samples ? 1 - MV.err / MV.samples : 0.6;
        return done(acc * 100 - MV.slips * 8 + 8);
      }
    }
    progress((MV.path + MV.prog / Math.max(1, (pts.length - 1))) / Math.max(1, paths.length), `${MV.path + 1} / ${paths.length}`);
  },
  draw() {
    const paths = geoPaths(), R = headR();
    paths.forEach((pts, i) => {
      if (i < MV.path) guidePath(pts, { c: 'rgba(8,175,162,.35)', dash: [1, 0], w: 1.5 });
      else if (i === MV.path) {
        guidePath(pts);
        guidePath(pts.slice(0, MV.prog + 1), { c: 'rgba(8,175,162,.9)', dash: [1, 0], w: 2 });
        const s = pts[MV.prog]; if (s && s.v) { ring(s, R * 0.06 + Math.sin(performance.now() / 160) * 3, '#08afa2', 2.5); dot(s, 4, '#08afa2'); }
        const e = pts[pts.length - 1]; if (e && e.v) ring(e, R * 0.035, 'rgba(255,255,255,.6)', 1.5);
      } else guidePath(pts, { c: 'rgba(255,255,255,.25)' });
    });
  },
};

/* cornrow: A / D alternating on the beat, cursor kept on the braid as it moves down the row */
// the beat: the ring closes on the braid one beat after the last stitch. Press then.
const BEAT = 620;
function beatPhase(t0) { return Math.min(1.3, (performance.now() - t0) / BEAT); }
function beatGood(t0, first) {
  if (first) return true;          // the first stitch of a move: you were reading the step
  const e = (performance.now() - t0) / BEAT;
  if (e < 0.6) { flash('Too fast', 'bad'); return false; }
  return e < 1.6;
}
function beatRing(h, R, ok) {
  const ph = Math.min(1, beatPhase(MV.t0));
  ring(h, R * 0.2 * (1 - ph) + R * 0.06, ph >= 0.75 ? '#ffe9a8' : ok ? '#08afa2' : '#e5484d', 2);
}
MOVES.cornrow = {
  target() { const pts = geoPaths()[MV.row]; if (!pts) return null; const j = Math.min(pts.length - 1, Math.round((MV.st / (SL.m.stitches || 6)) * (pts.length - 1)) + 1); return { k: MV.row, j, p: pts[j] }; },
  start() {
    const m = SL.m;
    MV = { row: 0, st: 0, want: 'A', t0: performance.now(), hits: 0, good: 0, misses: 0, off: 0, frames: 0, feed: null, slice: null, feeds: 0, feedGood: 0,
      keep: () => ({ k: 'row', c: m.feed ? SL.d.feedColour : SL.d.colour }) };
  },
  head() {
    const pts = geoPaths()[MV.row]; if (!pts) return null;
    return along(pts, MV.st / Math.max(1, SL.m.stitches || 6));
  },
  tick(dt) {
    const m = SL.m, paths = geoPaths();
    if (!paths[MV.row]) return;
    const h = this.head(), tol = headR() * 0.18;
    MV.frames++;
    MV.onBraid = h && dist(h, SL.mouse) < tol;
    if (!MV.onBraid) MV.off++;
    if (MV.feed) feedTick(dt);
    progress((MV.row + MV.st / (m.stitches || 6)) / paths.length, `Row ${MV.row + 1} / ${paths.length} · stitch ${MV.st} / ${m.stitches || 6}`);
  },
  key(e) {
    if (e.type !== 'keydown' || e.repeat) return false;
    const k = e.key.toLowerCase();
    if (MV.feed) return feedKey(e);
    if (k !== 'a' && k !== 'd') return false;
    const m = SL.m;
    if (MV.slice) { flash('Slice the row first', 'bad'); return true; }
    if (!MV.onBraid) { flash('Hands on the braid', 'bad'); SFX.miss(); MV.misses++; return true; }
    if (k !== MV.want.toLowerCase()) { MV.misses++; SFX.miss(); flash('Wrong hand', 'bad'); return true; }
    MV.hits++; if (beatGood(MV.t0, MV.hits === 1 || MV.st === 0)) MV.good++;
    MV.st++; MV.want = MV.want === 'A' ? 'D' : 'A'; MV.t0 = performance.now();
    SFX.key();
    const h = this.head(); if (h) burst(h.x, h.y, 'bits', 3);
    part((MV.row + MV.st / (m.stitches || 6)) / Math.max(1, geoPaths().length));
    if (m.feed && MV.st % 3 === 1) startFeed(m.feed);
    if (m.slice && MV.st % 2 === 0 && MV.st < (m.stitches || 6)) MV.slice = this.head();
    if (MV.st >= (m.stitches || 6)) {
      MV.row++; MV.st = 0; MV.want = 'A';
      if (MV.row >= geoPaths().length) {
        const timing = MV.hits ? MV.good / MV.hits : 0.5, hands = 1 - MV.off / Math.max(1, MV.frames);
        const feed = MV.feeds ? MV.feedGood / MV.feeds : 1;
        done(timing * 45 + hands * 30 + feed * 25 - MV.misses * 4);
      }
    }
    return true;
  },
  down() {
    if (MV.slice && dist(SL.mouse, MV.slice) < headR() * 0.12) { MV.slice = null; SFX.snip(); flash('Stitch line', 'good'); }
  },
  draw() {
    const m = SL.m, paths = geoPaths(), R = headR(), col = m.feed ? SL.d.feedColour : SL.d.colour;
    paths.forEach((pts, i) => {
      if (i === MV.row) {
        guidePath(pts, { c: 'rgba(255,255,255,.45)' });
        const L = lengths(pts), upTo = L[L.length - 1] * MV.st / (m.stitches || 6);
        guidePath(pts.filter((_, k) => L[k] <= upTo), { c: 'rgba(8,175,162,.9)', dash: [1, 0], w: 2 });
      } else if (i > MV.row) guidePath(pts, { c: 'rgba(255,255,255,.18)' });
    });
    const h = this.head();
    if (h && h.v) {
      beatRing(h, R, MV.onBraid);
      ring(h, R * 0.05, 'rgba(255,255,255,.8)', 1.5);
      if (MV.slice) { ring(MV.slice, R * 0.08 + Math.sin(performance.now() / 120) * 2, '#f0d3bb', 2); }
      keyPills(MV.feed ? feedPills(h) : [
        { key: 'A', x: h.x - R * 0.32, y: h.y, on: MV.want === 'A', label: MV.want === 'A' ? 'stitch' : '' },
        { key: 'D', x: h.x + R * 0.32, y: h.y, on: MV.want === 'D', label: MV.want === 'D' ? 'stitch' : '' },
      ].concat(MV.slice ? [{ key: 'CLICK', x: MV.slice.x, y: MV.slice.y - R * 0.16, on: true, label: 'slice' }] : []));
    } else keyPills([]);
    if (MV.feed) drawFeed();
  },
};

/* feeding in extension hair: hold F, let go when the bundle is the right size */
function startFeed(kind) {
  const st = (MV.feeds || 0);
  const target = kind === 'thin' ? [0.12, 0.3] : kind === 'grow' ? [clamp(0.2 + st * 0.12, 0.2, 0.62), clamp(0.38 + st * 0.12, 0.38, 0.82)] : [0.4, 0.62];
  MV.feed = { v: 0, hold: false, band: target };
  SL.feeding = true;
}
function feedTick(dt) { if (MV.feed && MV.feed.hold) MV.feed.v = Math.min(1, MV.feed.v + dt * 0.75); }
function feedKey(e) {
  if (e.key.toLowerCase() !== 'f') return true;
  if (e.type === 'keydown' && !e.repeat) { MV.feed.hold = true; MV.feed.v = 0; }
  if (e.type === 'keyup' && MV.feed.hold) {
    const f = MV.feed, ok = f.v >= f.band[0] && f.v <= f.band[1];
    MV.feeds = (MV.feeds || 0) + 1; if (ok) MV.feedGood = (MV.feedGood || 0) + 1;
    flash(ok ? 'Fed in' : f.v < f.band[0] ? 'Too thin' : 'Too thick', ok ? 'good' : 'bad');
    if (ok) SFX.hit(); else SFX.miss();
    MV.feed = null; SL.feeding = false;
    act('feed');
  }
  return true;
}
function feedPills(h) { const R = headR(); return [{ key: 'F', x: h.x, y: h.y - R * 0.3, on: true, label: MV.feed.hold ? 'feeding…' : 'hold to feed in hair' }]; }
function drawFeed() {
  const f = MV.feed, el = $('#slMeter');
  el.hidden = false;
  el.innerHTML = `<div class="slm-h"><i class="fa-solid fa-plus"></i>Feed in hair<span>${f.band[1] < 0.35 ? 'a very thin piece' : f.band[0] > 0.45 ? 'a thick piece' : 'a medium piece'}</span></div>
    <div class="slm-bar"><i class="band" style="left:${f.band[0] * 100}%;width:${(f.band[1] - f.band[0]) * 100}%"></i><i class="fill" style="width:${f.v * 100}%;background:${SL.d.feedColour}"></i></div>`;
}

/* braid: the strand keys on the beat, with pick-ups, feeds, curls and drops in the sequence */
MOVES.braid = {
  target() { const pts = this.pts(); if (!pts.length) return null; const j = Math.min(pts.length - 1, Math.round((SL.braid.st / Math.max(1, SL.braid.chain)) * (pts.length - 1))); return { k: SL.braid.path, j, p: pts[j] }; },
  start() {
    const m = SL.m;
    if (!m.cont || !SL.braid) SL.braid = { path: 0, st: 0, chain: m.chain || m.stitches || 6, curls: [] };
    MV = { tok: 0, t0: performance.now(), hits: 0, good: 0, misses: 0, pick: null, curl: null, feed: null, feeds: 0, feedGood: 0, done: 0,
      keep: () => ({ k: 'braid', t: SL.braid.st / SL.braid.chain, path: SL.braid.path, c: SL.d.colour }) };
    this.prep();
  },
  token() { const s = SL.m.seq || ['R', 'L']; return s[MV.tok % s.length]; },
  prep() {
    // what the next token needs first: a pick-up, a feed, a curl
    const t = this.token();
    const pre = t.length > 1 ? t[0] : '';
    MV.need = pre === '+' ? 'pick' : pre === 'F' ? 'feed' : pre === 'C' ? 'curl' : null;
    MV.cross = t.length > 1 ? t.slice(1) : t;
    MV.pick = null; MV.curl = null;
    if (MV.need === 'feed') startFeed(SL.m.feed || 'even');
  },
  pts() { return geoPaths()[SL.braid.path] || geoPaths()[0] || []; },
  head() { return along(this.pts(), SL.braid.st / Math.max(1, SL.braid.chain)); },
  tick(dt) {
    if (MV.feed) feedTick(dt);
    const h = this.head(), R = headR();
    if (MV.need === 'pick' && !MV.pick && h) {
      const side = MV.cross === 'R' || MV.cross === 'r' ? 1 : -1;
      MV.pick = { x: h.x - h.dy * side * R * 0.42 + h.dx * R * 0.1, y: h.y + h.dx * side * R * 0.42 + h.dy * R * 0.1 };
    }
    if (MV.need === 'curl' && !MV.curl && h) MV.curl = { x: h.x + R * 0.28, y: h.y + R * 0.05 };
    const m = SL.m, all = m.cont ? m.stitches : m.stitches * Math.max(1, geoPaths().length);
    progress(MV.done / Math.max(1, all || 6), `${TOKEN[MV.cross] ? TOKEN[MV.cross][1] : ''}`);
  },
  down() {
    const R = headR();
    if (MV.need === 'pick' && MV.pick && dist(SL.mouse, MV.pick) < R * 0.13) { MV.need = null; SFX.tick(); flash('Picked up', 'good'); burst(MV.pick.x, MV.pick.y, 'bits', 5); }
    else if (MV.need === 'curl' && MV.curl && dist(SL.mouse, MV.curl) < R * 0.13) {
      MV.need = null; SFX.tick(); flash('Curl left out', 'good');
      const h = this.head(); SL.braid.curls.push({ t: SL.braid.st / SL.braid.chain, path: SL.braid.path });
      burst(h.x, h.y, 'bits', 4);
    }
  },
  key(e) {
    if (MV.feed) {
      const r = feedKey(e);
      if (!MV.feed) MV.need = null;
      return r;
    }
    if (e.type !== 'keydown' || e.repeat) return false;
    const k = e.key === ' ' ? 'space' : e.key.toLowerCase();
    const want = TOKEN[MV.cross] ? TOKEN[MV.cross][0].toLowerCase() : 'd';
    if (k !== 'a' && k !== 'd' && k !== 'space') return false;
    if (MV.need) { flash(MV.need === 'pick' ? 'Pick up the hair first' : MV.need === 'curl' ? 'Leave a curl out first' : 'Feed in the hair first', 'bad'); SFX.miss(); MV.misses++; return true; }
    if (k !== want) { MV.misses++; SFX.miss(); flash('Wrong strand', 'bad'); return true; }
    MV.hits++; if (beatGood(MV.t0, MV.hits === 1)) MV.good++;
    MV.t0 = performance.now(); MV.tok++; MV.done++;
    SFX.key();
    // drops don't add a stitch: the strand falls through
    if (MV.cross !== 'D') SL.braid.st++;
    if (SL.braid.st >= SL.braid.chain && SL.braid.path < geoPaths().length - 1) { SL.braid.path++; SL.braid.st = 0; }
    const m = SL.m, all = m.cont ? m.stitches : m.stitches * Math.max(1, geoPaths().length);
    part(MV.done / Math.max(1, all || 6));
    if (MV.done >= (all || 6)) {
      const timing = MV.hits ? MV.good / MV.hits : 0.5, feed = MV.feeds ? MV.feedGood / MV.feeds : 1;
      return done(timing * 60 + feed * 30 + 10 - MV.misses * 5), true;
    }
    this.prep();
    return true;
  },
  draw() {
    const paths = geoPaths(), R = headR(), col = SL.d.colour, b = SL.braid;
    paths.forEach((pts, i) => {
      if (i === b.path) {
        guidePath(pts, { c: 'rgba(255,255,255,.4)' });
        const L = lengths(pts), upTo = L[L.length - 1] * b.st / b.chain;
        guidePath(pts.filter((_, k) => L[k] <= upTo), { c: 'rgba(8,175,162,.9)', dash: [1, 0], w: 2 });
      } else if (i > b.path) guidePath(pts, { c: 'rgba(255,255,255,.18)' });
    });
    const h = this.head();
    if (!h) return;
    const hl = TOKEN[MV.cross] ? TOKEN[MV.cross][0] : 'D';
    beatRing(h, R, true);
    const pills = [];
    if (MV.feed) pills.push(...feedPills(h));
    else if (MV.need === 'pick' && MV.pick) { ring(MV.pick, R * 0.08 + Math.sin(performance.now() / 120) * 2, '#ffe9a8', 2); dot(MV.pick, 4, '#ffe9a8'); pills.push({ key: 'CLICK', x: MV.pick.x, y: MV.pick.y - R * 0.15, on: true, label: 'pick up loose hair' }); }
    else if (MV.need === 'curl' && MV.curl) { ring(MV.curl, R * 0.08 + Math.sin(performance.now() / 120) * 2, '#e35b9f', 2); pills.push({ key: 'CLICK', x: MV.curl.x, y: MV.curl.y - R * 0.15, on: true, label: 'leave a curl out' }); }
    else pills.push({ key: TOKEN[MV.cross] ? TOKEN[MV.cross][0] : 'D', x: h.x + (hl === 'A' ? -1 : hl === 'D' ? 1 : 0) * R * 0.42, y: h.y + R * 0.28, on: true, label: TOKEN[MV.cross] ? TOKEN[MV.cross][1] : '' });
    keyPills(pills);
    if (MV.feed) drawFeed();
  },
};

/* dab: click each spot */
MOVES.dab = {
  target() {
    const pts = geoPoints(); let k = pts.findIndex((p, i) => !MV.hit.includes(i) && p.v);
    if (k < 0) k = pts.findIndex((p, i) => !MV.hit.includes(i));
    return k < 0 ? null : { k, p: pts[k] };
  },
  start() { MV = { hit: [], err: 0, misses: 0, t0: performance.now(), keep: () => ({ k: 'dab', m: SL.m.mark, hit: MV.hit.slice() }) }; },
  down() {
    const pts = geoPoints(), R = headR(), tol = R * 0.11;
    let best = -1, bd = Infinity;
    pts.forEach((p, i) => { if (!MV.hit.includes(i) && p.v) { const d = dist(p, SL.mouse); if (d < bd) { bd = d; best = i; } } });
    if (best >= 0 && bd < tol) {
      MV.hit.push(best); MV.err += bd / tol;
      const kind = SL.m.mark;
      if (kind === 'snip') { SFX.snip(); burst(SL.mouse.x, SL.mouse.y, 'bits', 12); }
      else if (kind === 'gel') { SFX.tick(); burst(SL.mouse.x, SL.mouse.y, 'mist', 2); }
      else SFX.key();
      act(kind);
      if (MV.hit.length >= pts.length) done(100 - (MV.err / MV.hit.length) * 35 - MV.misses * 6);
    } else { MV.misses++; SFX.miss(); }
  },
  tick() { const n = geoPoints().length; progress(MV.hit.length / Math.max(1, n), `${MV.hit.length} / ${n}`); },
  draw() {
    const R = headR(), t = performance.now() / 200;
    const pills = [];
    geoPoints().forEach((p, i) => {
      if (MV.hit.includes(i)) { if (p.v) dot(p, 2.5, 'rgba(8,175,162,.8)'); return; }
      if (!p.v) return;
      ring(p, R * 0.055 + Math.sin(t + i) * 2, '#08afa2', 2);
      dot(p, 3, 'rgba(255,255,255,.9)');
    });
    keyPills(pills);
  },
};

/* sew: click the stitch, flick up to pull the thread through; the thread follows the track */
MOVES.sew = {
  target() {
    const tg = this.targets()[MV.st]; if (!tg) return null;
    if (SL.g.kind === 'points') return { k: MV.st, p: tg };
    const paths = geoPaths(), per = SL.m.stitches || 6, k = Math.floor(MV.st / per), pts = paths[k] || [];
    return { k, j: Math.max(0, Math.min(pts.length - 1, tg.i || 0)), p: tg };
  },
  start() {
    const m = SL.m;
    MV = { st: 0, phase: 'in', at: null, err: 0, slow: 0, keep: () => (SL.g.kind === 'paths' ? { k: 'track' } : { k: 'dab', m: 'stitch', hit: Array.from({ length: MV.st }, (_, i) => i) }) };
  },
  targets() {
    if (SL.g.kind === 'points') return geoPoints();
    const m = SL.m, out = [], n = m.stitches || 6;
    const paths = geoPaths();
    const first = m.cont ? 0.25 : 0;
    for (const pts of paths) for (let k = 0; k < n; k++) out.push(Object.assign(along(pts, first + (1 - first) * (k + 0.5) / n), { path: pts }));
    return out;
  },
  down() {
    const tg = this.targets()[MV.st], R = headR();
    if (!tg || MV.phase !== 'in') return;
    const d = dist(tg, SL.mouse);
    if (d < R * 0.11) { MV.phase = 'pull'; MV.at = { x: SL.mouse.x, y: SL.mouse.y, t: performance.now() }; MV.err += d / (R * 0.11); SFX.tick(); }
    else SFX.miss();
  },
  tick() {
    if (MV.phase === 'pull') {
      const up = MV.at.y - SL.mouse.y;
      if (up > headR() * 0.16) {
        const took = performance.now() - MV.at.t;
        if (took > 900) MV.slow++;
        MV.st++; MV.phase = 'in'; SFX.key(); act('stitch');
        part(MV.st / Math.max(1, this.targets().length));
        if (MV.st >= this.targets().length) return done(100 - (MV.err / MV.st) * 30 - MV.slow * 5);
      }
      if (!SL.mouse.down && up < headR() * 0.16) MV.phase = 'in';
    }
    const n = this.targets().length; progress(MV.st / Math.max(1, n), `Stitch ${MV.st} / ${n}`);
  },
  draw() {
    const R = headR(), tg = this.targets();
    if (SL.g.kind === 'paths') for (const pts of geoPaths()) guidePath(pts, { c: 'rgba(255,255,255,.3)' });
    for (let i = 0; i < MV.st; i++) { const p = tg[i]; if (p && p.v) dot(p, 2.5, 'rgba(8,175,162,.8)'); }
    const cur = tg[MV.st];
    if (cur && cur.v) {
      ring(cur, R * 0.06 + Math.sin(performance.now() / 140) * 2, MV.phase === 'pull' ? '#ffe9a8' : '#08afa2', 2);
      if (MV.phase === 'pull') {
        ctx.save(); ctx.strokeStyle = '#d7a63a'; ctx.setLineDash([3, 3]); ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(MV.at.x, MV.at.y); ctx.lineTo(SL.mouse.x, SL.mouse.y); ctx.stroke(); ctx.restore();
      }
      keyPills([{ key: MV.phase === 'pull' ? '↑' : 'CLICK', x: cur.x, y: cur.y - R * 0.17, on: true, label: MV.phase === 'pull' ? 'pull the thread up' : 'needle in' }]);
    } else keyPills([]);
  },
};

/* sweep: hold and cover the area (sprays, mousse, gel, the dryer); heat burns if you stay put */
MOVES.sweep = {
  target() {
    const pts = geoPoints();
    if (pts.some((p, i) => p.v && !MV.cov.has(i))) return null;
    const k = pts.findIndex((p, i) => !MV.cov.has(i));
    return k < 0 ? null : { k, p: pts[k] };
  },
  start() { MV = { cov: new Set(), heat: {}, burns: 0, keep: null }; },
  tick(dt) {
    const pts = geoPoints(), R = headR(), r = R * (SL.m.tool === 'blow_dryer' ? 0.42 : 0.32);
    if (SL.mouse.down) {
      act('spray');
      if (Math.random() < 0.6) burst(SL.mouse.x, SL.mouse.y, SL.m.tool === 'blow_dryer' ? 'steam' : 'mist', 1);
      pts.forEach((p, i) => {
        if (!p.v || dist(p, SL.mouse) > r) return;
        MV.cov.add(i);
        if (SL.m.heat) { MV.heat[i] = (MV.heat[i] || 0) + dt; if (MV.heat[i] > 1.4 && !MV.heat['b' + i]) { MV.heat['b' + i] = true; MV.burns++; flash('Too hot', 'bad'); SFX.miss(); } }
      });
    }
    const need = Math.ceil(pts.length * (SL.m.cover || 0.85));
    progress(MV.cov.size / Math.max(1, need), `${Math.min(100, Math.round(MV.cov.size / Math.max(1, need) * 100))}% covered`);
    if (MV.cov.size >= need) done(100 - MV.burns * 15);
  },
  draw() {
    const R = headR();
    geoPoints().forEach((p, i) => {
      if (!p.v) return;
      if (MV.cov.has(i)) dot(p, 3.5, MV.heat['b' + i] ? '#e5484d' : 'rgba(8,175,162,.95)');
      else dot(p, 2.2, 'rgba(255,255,255,.55)');
    });
    if (SL.mouse.down) ring(SL.mouse, R * (SL.m.tool === 'blow_dryer' ? 0.42 : 0.32), 'rgba(255,255,255,.35)', 1);
    keyPills([]);
  },
};

/* stroke: from the root to the tip along each strand, n times */
MOVES.stroke = {
  target() { const pts = geoPaths()[MV.path]; return pts ? { k: MV.path, j: 0, p: pts[0] } : null; },
  start() { MV = { path: 0, rep: 0, prog: 0, snag: 0, burns: 0, holding: false, keep: null }; },
  tick(dt) {
    const paths = geoPaths(), pts = paths[MV.path], m = SL.m, R = headR();
    if (!pts) return;
    if (SL.mouse.down) {
      const n = nearestOn(pts, SL.mouse);
      if (n.d < R * 0.22) {
        if (MV.prog === 0 && n.i > 2) { /* must start at the root */ }
        else if (n.i >= MV.prog) {
          const speed = Math.hypot(SL.mouse.vx, SL.mouse.vy);
          if (m.heat && speed < 1.2 && MV.prog > 0) { MV.dwell = (MV.dwell || 0) + dt; if (MV.dwell > 0.8) { MV.burns++; MV.dwell = 0; flash('Too hot', 'bad'); SFX.miss(); } }
          else MV.dwell = 0;
          if (n.i > MV.prog) { MV.prog = n.i; if (m.heat && Math.random() < 0.4) burst(SL.mouse.x, SL.mouse.y, 'steam', 1); act('stroke'); }
        }
      }
    } else if (MV.prog > 0 && MV.prog < pts.length - 2) { MV.prog = 0; MV.snag++; }
    if (MV.prog >= pts.length - 2) {
      MV.rep++; MV.prog = 0; SFX.tick();
      if (MV.rep >= (m.n || 1)) { MV.rep = 0; MV.path++; }
      if (MV.path >= paths.length) return done(100 - MV.snag * 8 - MV.burns * 15);
    }
    const total = paths.length * (m.n || 1);
    progress((MV.path * (m.n || 1) + MV.rep) / total, `Stroke ${MV.path * (m.n || 1) + MV.rep + 1} / ${total}`);
  },
  draw() {
    const R = headR();
    geoPaths().forEach((pts, i) => {
      guidePath(pts, { c: i === MV.path ? 'rgba(255,255,255,.75)' : 'rgba(255,255,255,.2)', dash: [1, 7] });
      if (i === MV.path) {
        const a = pts[0], b = pts[MV.prog];
        if (a && a.v) ring(a, R * 0.06, '#08afa2', 2);
        if (b) dot(b, 4, '#08afa2');
      }
    });
    keyPills([]);
  },
};

/* circle: hold and turn around the spot (twists, buns, wrapping, palm rolling) */
MOVES.circle = {
  target() { const p = geoPoints()[MV.pt]; return p ? { k: MV.pt, p } : null; },
  start() { MV = { pt: 0, ang: 0, last: null, wob: 0, samples: 0, keep: null }; },
  dir() { const d = SL.m.dir || 'cw'; return d === 'alt' ? (MV.pt % 2 ? -1 : 1) : d === 'ccw' ? -1 : 1; },
  tick() {
    const pts = geoPoints(), c = pts[MV.pt], R = headR();
    if (!c) return;
    const r0 = R * 0.2;
    if (SL.mouse.down) {
      const a = Math.atan2(SL.mouse.y - c.y, SL.mouse.x - c.x), rr = dist(SL.mouse, c);
      if (MV.last !== null && rr > r0 * 0.35 && rr < r0 * 2.6) {
        let d = a - MV.last; if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2;
        if (Math.sign(d) === this.dir()) { MV.ang += Math.abs(d); if (Math.random() < 0.08) act('twist'); }
        MV.wob += Math.abs(rr - r0) / r0; MV.samples++;
      }
      MV.last = a;
    } else MV.last = null;
    const need = Math.PI * 2 * (SL.m.turns || 1);
    if (MV.ang >= need) {
      MV.pt++; MV.ang = 0; MV.last = null; SFX.hit();
      part(MV.pt / pts.length);
      if (MV.pt >= pts.length) return done(100 - (MV.samples ? (MV.wob / MV.samples) * 40 : 10));
    }
    progress((MV.pt + MV.ang / need) / pts.length, `${MV.pt + 1} / ${pts.length} · ${this.dir() > 0 ? 'clockwise' : 'anticlockwise'}`);
  },
  draw() {
    const pts = geoPoints(), R = headR(), c = pts[MV.pt];
    pts.forEach((p, i) => { if (i < MV.pt && p.v) dot(p, 2.5, 'rgba(8,175,162,.8)'); });
    if (!c || !c.v) return keyPills([]);
    const r0 = R * 0.2, need = Math.PI * 2 * (SL.m.turns || 1), dir = this.dir();
    ctx.save(); ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.setLineDash([3, 6]); ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(c.x, c.y, r0, 0, Math.PI * 2); ctx.stroke(); ctx.restore();
    ctx.save(); ctx.strokeStyle = '#08afa2'; ctx.lineWidth = 4; ctx.shadowColor = '#08afa2'; ctx.shadowBlur = 10;
    ctx.beginPath(); ctx.arc(c.x, c.y, r0, -Math.PI / 2, -Math.PI / 2 + dir * Math.min(Math.PI * 2, (MV.ang / need) * Math.PI * 2), dir < 0); ctx.stroke(); ctx.restore();
    // the arrow
    const a0 = -Math.PI / 2 + dir * 0.6, ax = c.x + Math.cos(a0) * r0, ay = c.y + Math.sin(a0) * r0;
    ctx.save(); ctx.fillStyle = '#08afa2'; ctx.translate(ax, ay); ctx.rotate(a0 + dir * Math.PI / 2);
    ctx.beginPath(); ctx.moveTo(8, 0); ctx.lineTo(-5, -6); ctx.lineTo(-5, 6); ctx.closePath(); ctx.fill(); ctx.restore();
    dot(c, 3, 'rgba(255,255,255,.9)');
    keyPills([]);
  },
};

/* drag: grab the hair at one spot, bring it to the ring */
MOVES.drag = {
  target() { const pr = geoPairs()[MV.k]; return pr ? { k: MV.k, j: MV.grab ? 2 : 1, p: MV.grab ? pr[1] : pr[0] } : null; },
  start() { MV = { k: 0, grab: false, err: 0, keep: null }; },
  down() { const pr = geoPairs()[MV.k]; if (pr && dist(pr[0], SL.mouse) < headR() * 0.14) { MV.grab = true; SFX.tick(); } },
  up() {
    const pairs = geoPairs(), pr = pairs[MV.k];
    if (!MV.grab || !pr) return;
    MV.grab = false;
    const d = dist(pr[1], SL.mouse), tol = headR() * 0.14;
    if (d < tol) {
      MV.err += d / tol; MV.k++; SFX.hit(); act('drag');
      if (MV.k >= pairs.length) done(100 - (MV.err / MV.k) * 30);
    } else { flash('Not there', 'bad'); SFX.miss(); MV.err += 0.5; }
  },
  tick() { const n = geoPairs().length; progress(MV.k / Math.max(1, n), `${MV.k} / ${n}`); },
  draw() {
    const R = headR(), pr = geoPairs()[MV.k];
    if (!pr) return keyPills([]);
    ctx.save(); ctx.strokeStyle = 'rgba(255,255,255,.45)'; ctx.setLineDash([4, 6]); ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(pr[0].x, pr[0].y); ctx.lineTo(pr[1].x, pr[1].y); ctx.stroke(); ctx.restore();
    ring(pr[1], R * 0.1 + Math.sin(performance.now() / 150) * 2, '#08afa2', 2.5);
    if (!MV.grab) ring(pr[0], R * 0.07, '#ffe9a8', 2);
    keyPills([{ key: MV.grab ? 'DROP' : 'GRAB', x: (MV.grab ? pr[1] : pr[0]).x, y: (MV.grab ? pr[1] : pr[0]).y - R * 0.18, on: true }]);
  },
};

/* hold: fill the meter, let go in the band */
MOVES.hold = {
  start() { MV = { v: 0, n: 0, held: false, err: 0, keep: null }; this.render(); $('#slMeter').hidden = false; },
  down() { MV.held = true; MV.v = 0; if (SL.m.tool === 'hot_water') act('dip'); },
  up() {
    if (!MV.held) return;
    MV.held = false;
    const b = SL.m.band || [0.6, 0.8], ok = MV.v >= b[0] && MV.v <= b[1];
    MV.err += ok ? Math.abs(MV.v - (b[0] + b[1]) / 2) / (b[1] - b[0]) : 1;
    flash(ok ? 'Just right' : MV.v < b[0] ? 'Too soon' : 'Too long', ok ? 'good' : 'bad');
    if (ok) { MV.n++; SFX.hit(); } else SFX.miss();
    if (MV.n >= (SL.m.n || 1)) { $('#slMeter').hidden = true; done(100 - MV.err * 30); }
  },
  tick(dt) { if (MV.held) { MV.v = Math.min(1, MV.v + dt * 0.55); if (MV.v >= 1) this.up(); } this.render(); progress(MV.n / (SL.m.n || 1), `${MV.n} / ${SL.m.n || 1}`); },
  render() {
    const b = SL.m.band || [0.6, 0.8], el = $('#slMeter');
    const what = { hot_water: 'Dip the ends', c_needle: 'Thread the needle', hair: 'Fold the track over' }[SL.m.tool] || 'Hold';
    el.innerHTML = `<div class="slm-h"><i class="fa-solid fa-hourglass-half"></i>${what}<span>hold the mouse, let go in the green</span></div>
      <div class="slm-bar"><i class="band" style="left:${b[0] * 100}%;width:${(b[1] - b[0]) * 100}%"></i><i class="fill" style="width:${MV.v * 100}%"></i></div>`;
  },
  draw() { keyPills([]); },
};

/* ═══════════════ the HUD ═══════════════ */
function slStart(d) {
  SL.on = true; SL.d = d; SL.dec = []; SL.braid = null; SL.fx = [];
  SL.ends = Date.now() + (d.max || 1500) * 1000;
  sl.root.hidden = false;
  document.documentElement.style.setProperty('--hc', d.colour);
  sl.top.innerHTML = `<div class="ch-frame"><div class="ch-in">
      <div class="mark sm"><i class="fa-solid fa-wand-magic-sparkles"></i></div>
      <div class="ct-tx"><small>Hair appointment</small><b>${esc(d.label)} <em>for ${esc(d.name)}</em></b></div>
      ${d.shade ? `<span class="chip sl-shade"><i style="background:${d.colour}${d.tip ? `;background:linear-gradient(90deg,${d.colour},${d.tip})` : ''}"></i>${esc(d.shade)}</span>` : '<span class="chip">Natural hair</span>'}
      <div class="ct-clock"><i class="fa-regular fa-clock"></i><span id="slClock"></span></div></div></div>`;
  clearInterval(SL.timer);
  SL.timer = setInterval(() => {
    const s = Math.max(0, Math.round((SL.ends - Date.now()) / 1000));
    const el = $('#slClock'); if (el) el.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }, 500);
  requestAnimationFrame(frame);
}

function slMove(m) {
  SL.m = m; SL.sent = false; SL.feeding = false;
  $('#slMeter').hidden = true;
  const MOVE = MOVES[m.a];
  if (!MOVE) return post('salonMoveDone', { i: m.i, score: 50 });
  MOVE.start();
  // the side: every step of the style, this one open
  sl.steps.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="tray-h">${m.phase ? esc(m.phase) : 'Step by step'}</div>
    <div class="sl-step"><span class="sl-no">${m.step}<em>/${m.steps}</em></span><p>${esc(m.stepText)}</p></div>
    <div class="sl-movebar"><span>Move ${m.i} of ${m.total}</span><div><i style="width:${((m.i - 1) / m.total) * 100}%"></i></div></div>
    <div class="cut-keys sl-keys">
      <div><span class="kc">Q</span><span class="kc">E</span>Walk around</div>
      <div><span class="kc">W</span><span class="kc">S</span>Height</div>
      <div><span class="kc"><i class="fa-solid fa-computer-mouse"></i></span>Scroll to zoom</div>
    </div>
    <button class="btn red sm wide" data-sl="stop"><i class="fa-solid fa-xmark"></i>Stop<span class="kc">ESC</span></button>
  </div></div>`;
  sl.tray.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="tray-h">In hand</div>
    <div class="sl-tool"><span class="sl-art">${SL_TOOL[m.tool] || SL_TOOL.hands}</span><span><b>${esc(m.toolLabel || 'Hands')}</b><small>${esc(SL_VERB[m.a] || '')}</small></span></div>
  </div></div>`;
  sl.obj.innerHTML = `<div class="obj"><div class="obj-tx"><i class="fa-solid ${SL_ICON[m.a] || 'fa-hand'}"></i><b>${esc(m.text || moveTitle(m))}</b><span>·</span><em id="slProg"></em></div>
    <div class="obj-bar"><i id="slBar" style="width:0%"></i></div></div>`;
  sl.cursor.innerHTML = SL_TOOL[m.tool] || SL_TOOL.hands;
  sl.cursor.dataset.tool = m.tool;
  SFX.start();
}

function moveTitle(m) {
  switch (m.a) {
    case 'trace': return m.tool === 'shears' ? 'Cut along the line' : m.tool === 'edge_brush' ? 'Lay the edges' : m.tool === 'hair' ? 'Lay the weft along the track' : 'Part along the line';
    case 'cornrow': return m.feed ? 'Cornrow the rows, feeding in hair' : 'Cornrow the rows';
    case 'braid': return 'Braid it down';
    case 'dab': return { gel: 'Gel each spot', pin: 'Pin it', elastic: 'Put the elastic on', bead: 'Slide the beads on', clip: 'Clip it away', snip: 'Snip the ends', tack: 'Tack the ends down', pick: 'Pick up each section', curl: 'Leave the curls out', wrap: 'Secure the wrapping hair', slice: 'Slice the stitch lines', knot: 'Knot it' }[m.mark] || 'Click each spot';
    case 'sew': return 'Sew it down';
    case 'sweep': return { blow_dryer: 'Blow-dry it all', braid_gel: 'Smooth the gel in', mousse: 'Mousse the ends', heat_protect: 'Heat protectant on', shine_spray: 'Finish with shine spray', moisturizer: 'Moisturize it' }[m.tool] || 'Cover it all';
    case 'stroke': return m.tool === 'flat_iron' ? 'Flat iron it smooth' : m.tool === 'paddle_brush' ? 'Brush it through' : 'Smooth it down';
    case 'circle': return { hair: 'Loop it around the root', crochet_hook: 'Hook the hair in at the root' }[m.tool] || (m.turns >= 2 ? (m.dir === 'alt' ? 'Palm-roll the ends' : 'Twist it into a bun') : 'Twist it');
    case 'drag': return 'Move the hair into place';
    case 'hold': return 'Hold it just long enough';
  }
  return 'Do it';
}

function slGeo(d) {
  if (!SL.on || !SL.m || d.i !== SL.m.i) return;
  SL.g = { kind: SL.m.kind, list: d.g || [] };
  if (d.head) SL.head = d.head;
  if (d.dec) SL.dec = d.dec;
}

let lastT = 0;
function frame(t) {
  if (!SL.on) return;
  const dt = Math.min(0.05, (t - (lastT || t)) / 1000); lastT = t;
  ctx.clearRect(0, 0, W, H);
  if (SL.g && SL.m) {
    const MOVE = MOVES[SL.m.a];
    if (MOVE && !SL.sent) { MOVE.tick && MOVE.tick(dt); MOVE.draw && MOVE.draw(); follow(MOVE, t); }
  }
  SL.mouse.vx *= 0.8; SL.mouse.vy *= 0.8;
  requestAnimationFrame(frame);
}

// the camera follows the work: when the next thing to do is round the back, swing round to it
let focusAt = 0, focusKey = '';
function follow(MOVE, t) {
  if (!MOVE.target || !SL.g || !SL.g.list.length) return;
  const tg = MOVE.target();
  if (!tg || !tg.p || tg.p.v) return;
  const key = `${SL.m.i}:${tg.k}:${tg.j}`;
  if (t - focusAt < 450 && key === focusKey) return;
  focusAt = t; focusKey = key;
  post('salonFocus', { k: tg.k, j: tg.j });
}

function slWait() { SL.m = null; keyPills([]); sl.obj.innerHTML = '<div class="obj"><div class="obj-tx"><i class="fa-solid fa-spinner fa-spin"></i><b>Finishing up</b></div></div>'; }

function slEnd(r) {
  SL.on = false; SL.m = null;
  clearInterval(SL.timer);
  keyPills([]);
  ctx.clearRect(0, 0, W, H);
  sl.root.hidden = true;
  $('#slMeter').hidden = true;
  if (r && r.done) {
    const box = $('#slResult');
    box.innerHTML = `<div class="ch-frame"><div class="ch-in">
      <div class="slr-top"><div class="mark"><i class="fa-solid fa-wand-magic-sparkles"></i></div><div><small>Done on ${esc(r.name || '')}</small><b>${esc(r.label)}</b></div></div>
      <div class="slr-q"><div class="slr-stars">${stars(r.q)}</div><b>${r.q}%</b></div>
      <div class="slr-row">${r.xp ? `<span class="chip t-success"><i class="fa-solid fa-star"></i>+${r.xp} XP</span>` : ''}${r.paid ? `<span class="chip"><i class="fa-solid fa-sack-dollar"></i>${money(r.paid)}</span>` : ''}</div>
    </div></div>`;
    box.hidden = false; box.classList.remove('out');
    SFX.win();
    setTimeout(() => { box.classList.add('out'); setTimeout(() => { box.hidden = true; }, 300); }, 5000);
  }
}

function stars(q) {
  const n = q >= 95 ? 5 : q >= 82 ? 4 : q >= 65 ? 3 : q >= 45 ? 2 : 1;
  return Array.from({ length: 5 }, (_, i) => `<i class="fa-${i < n ? 'solid' : 'regular'} fa-star"></i>`).join('');
}

/* ─────────────── input ─────────────── */
sl.root.addEventListener('mousemove', (e) => {
  SL.mouse.vx = e.clientX - SL.mouse.x; SL.mouse.vy = e.clientY - SL.mouse.y;
  SL.mouse.x = e.clientX; SL.mouse.y = e.clientY;
  sl.cursor.style.transform = `translate(${e.clientX}px, ${e.clientY}px)`;
});
sl.root.addEventListener('mousedown', (e) => {
  if (e.button !== 0 || e.target.closest('button')) return;
  SL.mouse.down = true; sl.cursor.classList.add('down');
  const M = SL.m && MOVES[SL.m.a]; if (M && M.down && !SL.sent) M.down();
});
addEventListener('mouseup', (e) => {
  if (!SL.on || e.button !== 0) return;
  SL.mouse.down = false; sl.cursor.classList.remove('down');
  const M = SL.m && MOVES[SL.m.a]; if (M && M.up && !SL.sent) M.up();
});
sl.root.addEventListener('wheel', (e) => post('salonZoom', { delta: Math.sign(e.deltaY) }), { passive: true });
sl.root.addEventListener('click', (e) => { if (e.target.closest('[data-sl="stop"]')) post('salonStop'); });

function salonKey(e) {
  if (SL.on) {
    if (e.type === 'keydown' && (e.key === 'Escape' || e.key === 'Backspace')) { post('salonStop'); return true; }
    const M = SL.m && MOVES[SL.m.a];
    if (M && M.key && !SL.sent) M.key(e);
    return true;
  }
  if (Book.open) return bookKey(e);
  return false;
}

/* ═══════════════ the client, sitting ═══════════════ */
const SIT = { d: null };
function salonSit(d) {
  SIT.d = d;
  const el = $('#salonSit');
  el.hidden = false;
  renderSit(1, 0);
}
function renderSit(step, idx) {
  const d = SIT.d; if (!d) return;
  const el = $('#salonSit');
  const steps = arr(d.steps);
  el.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="ss-top"><div class="ti t-success"><i class="fa-solid fa-wand-magic-sparkles"></i></div>
      <div class="cs-tx"><b>${esc(d.name)} is doing your hair</b><span>${esc(d.label)}${d.price ? ` · ${money(d.price)}` : ''}</span></div></div>
    <div class="ss-step"><span>Step ${step} of ${steps.length}</span><p>${esc(steps[step - 1] || '')}</p></div>
    <div class="ss-bar"><i style="width:${(idx / Math.max(1, d.total)) * 100}%"></i></div>
    <div class="ss-keys"><span class="cs-key"><span class="kc">M</span>Mirror${SIT.mirror ? ' (on)' : ''}</span><span class="cs-key"><span class="kc">X</span>Get up</span></div>
  </div></div>`;
}
function salonProgress(p) { SIT.idx = p.idx - 1; SIT.step = p.step; renderSit(p.step, p.idx - 1); }
function salonMirror(d) { SIT.mirror = !!d.on; renderSit(SIT.step || 1, SIT.idx || 0); }
function salonSitEnd() { $('#salonSit').hidden = true; SIT.d = null; }

/* the reveal: NEW LOOK, letterboxed, while the camera turns around your head */
function salonReveal(r) {
  $('#salonSit').hidden = true; SIT.d = null;
  const el = $('#salonReveal');
  const days = r.minutes ? Math.max(1, Math.round(r.minutes / 1440)) : null;
  const lasts = r.minutes ? (r.minutes >= 1440 ? `${days} day${days === 1 ? '' : 's'}` : `${Math.max(1, Math.round(r.minutes / 60))} h`) : null;
  el.innerHTML = `<div class="rvl-bar top"></div><div class="rvl-bar bottom"></div>
    <div class="rvl-card">
      <span class="rvl-kicker">New look</span>
      <h1>${esc(r.label)}</h1>
      <div class="rvl-stars">${stars(r.q)}</div>
      <div class="rvl-meta"><span>by <b>${esc(r.by || '')}</b></span><span>${r.q}% quality</span>${lasts ? `<span>lasts ${lasts}</span>` : ''}</div>
    </div>
    <div class="rvl-spark"></div>`;
  el.hidden = false; el.classList.remove('out');
  SFX.reveal(4);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => { el.hidden = true; }, 600); }, 6400);
}

// for the screenshot harness
window.SalonDebug = { SL, MOVES, get MV() { return MV; }, along, geoPaths, geoPoints, geoPairs, headR };
