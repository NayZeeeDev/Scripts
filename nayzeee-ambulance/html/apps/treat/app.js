/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · treat app (first aid module)

   Modes (Lua NZA.UI.Open('treat', data) with data.mode):
     bleed   STOP BLEEDING   pressure → pack (deep wounds) → wrap (limbs) | dressing (torso)
     tq      TOURNIQUET      place high & tight + pull the slack → twist the windlass → lock the clip
     collar  CERVICAL COLLAR measure & size → fasten while holding the head in line
     meds    MEDICATION      dose panel: drug, dose, route, live warnings, administer
     kit     FIRST AID       pick one of your first aid items to use on the patient

   The game camera is a close-up on the patient (NZA.Cam.Close); this app draws the wound,
   blood, gauze, bandage and tourniquet over it from world anchors:
     limbs  j0 j1 j2 (shoulder/hip → elbow/knee → wrist/ankle)
     torso  wound, pel, neck          collar  head, neck, chest

   Lua → JS   open(data) · anchors · vitals { hr, sys, dia, spo2, rr } · result(outcome)
              meds(info) refresh · given { ok, msg }
   JS → Lua   treat:finish { result } · treat:abort · treat:tqPlace { seg, frac }
              treat:give { drug, dose, route } · treat:use { key } · treat:close (core)
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const NZ = window.NZ;
  const { el, esc, clamp, rich } = NZA;
  const TAU = Math.PI * 2;
  const lerp = (a, b, t) => a + (b - a) * t;
  const now = () => performance.now();
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const sub = (a, b) => ({ x: a.x - b.x, y: a.y - b.y });
  const add = (a, b) => ({ x: a.x + b.x, y: a.y + b.y });
  const mul = (a, s) => ({ x: a.x * s, y: a.y * s });
  const norm = v => { const l = Math.hypot(v.x, v.y) || 1; return { x: v.x / l, y: v.y / l }; };
  const perp = v => ({ x: -v.y, y: v.x });
  const mix = (a, b, t) => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t) });
  const angDiff = (a, b) => { let d = (a - b) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; };
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  function rng(seed) { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  const hash = s => { let h = 2166136261; for (const ch of String(s)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };

  NZ.addIcons({
    'tq-strap': '<path d="M4 9.5c2.5-2 13.5-2 16 0v5c-2.5 2-13.5 2-16 0z"/><path d="M12 5v14"/><path d="M9.5 5h5"/>',
    'tq-clip': '<path d="M7 7a5 5 0 1 0 10 0"/><path d="M12 12v8M9 20h6"/>',
    'o2': '<circle cx="9" cy="12" r="4.5"/><path d="M15.5 14.5c.4-1 3.5-1 3.5.6 0 1.3-3.6 2.2-3.6 3.9h3.8"/>',
    'gauze-roll': '<ellipse cx="16" cy="9.5" rx="3" ry="5.5"/><path d="M16 4H7.5C5.6 4 4.5 6.5 4.5 9.5S5.6 15 7.5 15H16"/><path d="M9 15l1.5 5.5h5L14 15"/><ellipse cx="16" cy="9.5" rx="1" ry="2"/>',
    'dressing-pad': '<rect x="3.5" y="5.5" width="17" height="13" rx="2"/><rect x="8" y="9" width="8" height="6" rx="1"/><path d="M3.5 9h2M18.5 9h2M3.5 15h2M18.5 15h2"/>',
  });

  /* ── holographic body glyph (front view: the patient's left is on the viewer's right) ── */
  const BODY_SEGS = [
    ['head', '<ellipse cx="32" cy="11" rx="7.2" ry="8.8"/>'],
    ['neck', '<rect x="28.6" y="20.2" width="6.8" height="5.8" rx="2"/>'],
    ['chest', '<path d="M21.5 26.6h21a5 5 0 0 1 5 5v11.6h-31V31.6a5 5 0 0 1 5-5z"/>'],
    ['abdomen', '<rect x="18.8" y="44.6" width="26.4" height="10.8" rx="2.6"/>'],
    ['pelvis', '<path d="M18.8 56.8h26.4v5.6a4.6 4.6 0 0 1-4.6 4.6H23.4a4.6 4.6 0 0 1-4.6-4.6z"/>'],
    ['r_upper_arm', '<rect x="10.8" y="28.4" width="6.4" height="17" rx="3.2" transform="rotate(9 14 28.4)"/>'],
    ['r_lower_arm', '<rect x="8.3" y="46.4" width="5.8" height="18" rx="2.9" transform="rotate(5 11.2 46.4)"/>'],
    ['l_upper_arm', '<rect x="46.8" y="28.4" width="6.4" height="17" rx="3.2" transform="rotate(-9 50 28.4)"/>'],
    ['l_lower_arm', '<rect x="49.9" y="46.4" width="5.8" height="18" rx="2.9" transform="rotate(-5 52.8 46.4)"/>'],
    ['r_upper_leg', '<rect x="20.4" y="68.4" width="10.2" height="27" rx="5"/>'],
    ['r_lower_leg', '<rect x="21.4" y="96.8" width="8.2" height="28.4" rx="4"/>'],
    ['l_upper_leg', '<rect x="33.4" y="68.4" width="10.2" height="27" rx="5"/>'],
    ['l_lower_leg', '<rect x="34.4" y="96.8" width="8.2" height="28.4" rx="4"/>'],
  ];
  const BODY_ALIAS = { face: 'head', back: 'chest' };
  const BODY_PT = {
    head: [32, 11], face: [32, 13], neck: [32, 23], chest: [32, 35], back: [32, 35], abdomen: [32, 50], pelvis: [32, 61.5],
    r_upper_arm: [12.7, 37], r_lower_arm: [10.4, 55.4], l_upper_arm: [51.3, 37], l_lower_arm: [53.6, 55.4],
    r_upper_leg: [25.5, 81.5], r_lower_leg: [25.5, 110], l_upper_leg: [38.5, 81.5], l_lower_leg: [38.5, 110],
  };
  // states: { region: 'red' | 'amber' | 'teal' }  focus: region with the pulsing diamond
  function bodyGlyph(states, focus) {
    const st = {};
    Object.entries(states || {}).forEach(([r, v]) => { st[BODY_ALIAS[r] || r] = v; });
    const segs = BODY_SEGS.map(([r, shape]) => `<g class="bs ${st[r] || ''} ${focus && (BODY_ALIAS[focus] || focus) === r ? 'fx' : ''}" data-r="${r}">${shape}</g>`).join('');
    const p = focus && BODY_PT[focus];
    const dia = p ? `<g class="hot ${st[BODY_ALIAS[focus] || focus] || 'red'}" transform="translate(${p[0]} ${p[1]})"><circle class="pl" r="4.6"/><path class="dm" d="M0 -3.4 3.4 0 0 3.4 -3.4 0z"/></g>` : '';
    return `<svg class="bglyph" viewBox="0 0 64 132" aria-hidden="true">
      <defs><pattern id="tr-scan" width="4" height="2.2" patternUnits="userSpaceOnUse"><rect width="4" height="1" fill="rgba(255,255,255,.07)"/></pattern></defs>
      <ellipse class="pad" cx="32" cy="128.4" rx="17" ry="2.6"/>
      ${segs}<rect x="0" y="0" width="64" height="132" fill="url(#tr-scan)" pointer-events="none"/>${dia}${focus === 'back' ? '<text class="bk" x="32" y="40">BACK</text>' : ''}</svg>`;
  }
  // a status ring (HUD design): value in the middle, track + fill, label under it
  const RING_C = 2 * Math.PI * 18;
  function vring({ value, frac = 0, tone = '', label: lb = '', unit = '', beat = 0 }) {
    const f = clamp(frac, 0, 1);
    return `<div class="vr ${tone}"${beat ? ` style="--beat:${beat.toFixed(2)}s"` : ''}><span class="rg"><svg viewBox="0 0 44 44"><circle class="b" cx="22" cy="22" r="18"/><circle class="f" cx="22" cy="22" r="18" stroke-dasharray="${RING_C.toFixed(1)}" stroke-dashoffset="${(RING_C * (1 - f)).toFixed(1)}"/></svg><b>${esc(String(value))}</b>${beat ? '<i class="bt"></i>' : ''}</span><em>${esc(lb)}${unit ? `<small>${esc(unit)}</small>` : ''}</em></div>`;
  }
  const initialsOf = n => String(n || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase();

  let LOC = {};
  const T = (k, fb, ...args) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; args.forEach(a => { s = s.replace(/%[sd]|%\.\df/, a); }); return s; };

  const KEY = { confirm: 'Space', lock: 'KeyE', done: 'Enter' };
  const keyLabel = code => (code === 'Space' ? 'Space' : code === 'Enter' ? 'Enter' : String(code || '').replace(/^Key|^Digit/, ''));

  // in-game colours on the stage
  const C = {
    blood: '#b3121b', bloodHi: '#e0343b', bloodDark: '#4e070b', stain: '78,6,10',
    gauze: '#f3f2ec', gauzeShade: '#d9d6cb', glove: '#5b8fc6', gloveDark: '#3d6d9f',
    strap: '#25282c', strapHi: '#3a3e44', teal: '#08afa2', tealHi: '#0fd4c4', red: '#e5484d', amber: '#e5a50a', white: '#ffffff',
  };

  /* ═════════════════════════════ BLOOD FX ═════════════════════════════ */
  const FX = {
    parts: [], stains: [],
    reset() { this.parts = []; this.stains = []; },
    emit(p) { if (this.parts.length < 480) this.parts.push(p); },
    stain(dx, dy, r, a) {
      // wound-relative, in centimetres (stays put when the camera zooms or the wound drifts)
      const s = this.stains;
      for (let i = s.length - 1; i >= Math.max(0, s.length - 40); i--) {
        const o = s[i];
        if (Math.hypot(o.dx - dx, o.dy - dy) < Math.min(o.r, r) * 0.5) { o.r = Math.min(o.r + r * 0.06, 7); o.a = Math.min(0.8, o.a + a * 0.2); return; }
      }
      s.push({ dx, dy, r, a: Math.min(0.8, a), seed: Math.random(), rot: Math.random() * 3 });
      if (s.length > 360) s.splice(0, s.length - 360);
    },
    update(dt, w) {
      for (let i = this.parts.length - 1; i >= 0; i--) {
        const p = this.parts[i];
        if (p.kind === 'jet') {
          // a jet seen from above: flies outward, swells toward the camera at mid-flight, lands
          p.t += dt;
          const u = clamp(p.t / p.T, 0, 1), e = 1 - (1 - u) * (1 - u);
          p.x = p.x0 + p.dx * p.d * e; p.y = p.y0 + p.dy * p.d * e;
          p.sc = 1 + 0.9 * Math.sin(Math.PI * u);
          if (u >= 1) { this.stain((p.x - w.x) / w.cm, (p.y - w.y) / w.cm, (p.r * 1.5) / w.cm, 0.34); this.parts.splice(i, 1); }
        } else {
          // rivulet running off the wound toward the ground
          p.life -= dt;
          p.x += p.vx * dt; p.y += p.vy * dt;
          p.vx *= 1 - 0.6 * dt; p.vy *= 1 - 0.6 * dt;
          p.x += Math.sin(p.life * 7 + p.seed * 9) * 0.25 * w.cm * dt;
          p.trail -= dt;
          if (p.trail <= 0) { p.trail = 0.05; this.stain((p.x - w.x) / w.cm, (p.y - w.y) / w.cm, (p.r * 0.95) / w.cm, 0.2); }
          if (p.life <= 0) this.parts.splice(i, 1);
        }
      }
    },
    drawStains(c, w) {
      for (const s of this.stains) {
        const x = w.x + s.dx * w.cm, y = w.y + s.dy * w.cm, r = s.r * w.cm;
        const gr = c.createRadialGradient(x, y, 0, x, y, r);
        gr.addColorStop(0, `rgba(${C.stain},${(s.a * 0.92).toFixed(3)})`);
        gr.addColorStop(0.65, `rgba(${C.stain},${(s.a * 0.6).toFixed(3)})`);
        gr.addColorStop(1, `rgba(${C.stain},0)`);
        c.fillStyle = gr;
        c.beginPath(); c.ellipse(x, y, r, r * (0.7 + s.seed * 0.35), s.rot, 0, TAU); c.fill();
      }
    },
    drawParts(c, w) {
      c.save(); c.lineCap = 'round';
      for (const p of this.parts) {
        if (p.kind === 'jet') {
          const r = p.r * p.sc;
          c.strokeStyle = 'rgba(150,10,18,.55)'; c.lineWidth = r * 1.1;
          c.beginPath(); c.moveTo(p.x - p.dx * r * 2.2, p.y - p.dy * r * 2.2); c.lineTo(p.x, p.y); c.stroke();
          c.fillStyle = '#b5131c'; c.beginPath(); c.arc(p.x, p.y, r, 0, TAU); c.fill();
          c.fillStyle = 'rgba(255,150,150,.45)'; c.beginPath(); c.arc(p.x - r * 0.3, p.y - r * 0.35, r * 0.32, 0, TAU); c.fill();
        } else {
          const a = clamp(p.life / 0.4, 0, 1);
          c.fillStyle = `rgba(140,10,18,${0.85 * a})`; c.beginPath(); c.arc(p.x, p.y, p.r, 0, TAU); c.fill();
          c.fillStyle = `rgba(255,120,120,${0.25 * a})`; c.beginPath(); c.arc(p.x - p.r * 0.3, p.y - p.r * 0.3, p.r * 0.35, 0, TAU); c.fill();
        }
      }
      c.restore();
    },
  };

  /* ═════════════════════════════ DRAW HELPERS ═════════════════════════════ */
  function roundRect(c, x, y, w, h, r) {
    c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
  }

  function drawWound(c, w, d, b, t) {
    const inj = d.injury || {}; const type = inj.type || 'gunshot'; const sev = inj.severity || 2;
    const cm = w.cm; const R = rng(hash(inj.id || type));
    c.save(); c.translate(w.x, w.y); c.rotate(w.ang);
    // wet, blood-soaked cloth around the wound
    const soak = c.createRadialGradient(0, 0, cm * 0.3, 0, 0, cm * (2.2 + sev * 0.5));
    soak.addColorStop(0, `rgba(70,4,8,${0.75 * (0.5 + 0.5 * b)})`); soak.addColorStop(0.6, `rgba(80,6,10,${0.45 * (0.5 + 0.5 * b)})`); soak.addColorStop(1, 'rgba(80,6,10,0)');
    c.fillStyle = soak; c.beginPath(); c.ellipse(0, 0, cm * (2.6 + sev * 0.5), cm * (2 + sev * 0.4), 0.3, 0, TAU); c.fill();
    const wet = (x, y, rx, ry) => { c.fillStyle = 'rgba(255,255,255,.2)'; c.beginPath(); c.ellipse(x, y, rx, ry, -0.4, 0, TAU); c.fill(); };
    const hole = (x, y, rr, ring) => {
      if (ring) { const g1 = c.createRadialGradient(x, y, rr * 0.7, x, y, rr * ring); g1.addColorStop(0, 'rgba(120,30,28,.95)'); g1.addColorStop(0.75, 'rgba(110,34,30,.5)'); g1.addColorStop(1, 'rgba(110,34,30,0)'); c.fillStyle = g1; c.beginPath(); c.arc(x, y, rr * ring, 0, TAU); c.fill(); }
      const g = c.createRadialGradient(x - rr * 0.2, y - rr * 0.2, 0, x, y, rr);
      g.addColorStop(0, '#0d0102'); g.addColorStop(0.65, '#33050a'); g.addColorStop(1, '#6e0f16');
      c.fillStyle = g; c.beginPath();
      for (let i = 0; i <= 18; i++) { const a = (i / 18) * TAU; const rr2 = rr * (0.84 + 0.2 * R()); c.lineTo(x + Math.cos(a) * rr2, y + Math.sin(a) * rr2); }
      c.fill();
      c.fillStyle = `rgba(165,14,22,${0.25 + 0.6 * b})`; c.beginPath(); c.arc(x, y + rr * 0.12, rr * 0.5, 0, TAU); c.fill();
      wet(x - rr * 0.25, y - rr * 0.38, rr * 0.34, rr * 0.15);
    };
    if (type === 'gunshot') hole(0, 0, cm * (0.42 + sev * 0.12), 1.8);
    else if (type === 'shrapnel') {
      const n = 3 + Math.min(3, sev);
      for (let i = 0; i < n; i++) hole((R() - 0.5) * cm * 4.5, (R() - 0.5) * cm * 3, cm * (0.2 + R() * 0.28), 1.5);
    } else if (type === 'abrasion') {
      const g = c.createRadialGradient(0, 0, 0, 0, 0, cm * 3);
      g.addColorStop(0, 'rgba(160,44,38,.9)'); g.addColorStop(0.7, 'rgba(170,64,52,.5)'); g.addColorStop(1, 'rgba(170,64,52,0)');
      c.fillStyle = g; c.beginPath(); c.ellipse(0, 0, cm * 3.2, cm * 2.1, 0.2, 0, TAU); c.fill();
      c.strokeStyle = 'rgba(90,10,14,.6)'; c.lineWidth = Math.max(1, cm * 0.07);
      for (let i = 0; i < 11; i++) { const y = (R() - 0.5) * cm * 2.8; c.beginPath(); c.moveTo(-cm * 2.6 + R() * cm, y); c.lineTo(cm * 2.6 - R() * cm, y + (R() - 0.5) * cm * 0.4); c.stroke(); }
    } else {
      // stab = short deep slit, laceration = long ragged cut
      const len = type === 'stab' ? cm * (1.8 + sev * 0.45) : cm * clamp((inj.length || 50) / 10, 3, 10);
      const gape = type === 'stab' ? cm * 0.38 : cm * (0.3 + sev * 0.08);
      const rot = type === 'stab' ? 0.35 : Math.PI / 2 + 0.25;
      c.rotate(rot);
      const top = [], bot = [];
      const n = 16;
      for (let i = 0; i <= n; i++) {
        const u = i / n, x = (u - 0.5) * len, env = Math.sin(u * Math.PI) ** 0.8;
        const j = type === 'laceration' ? (R() - 0.5) * gape * 0.5 : 0;
        top.push([x, -gape * env + j]); bot.push([x, gape * env * 0.9 + j]);
      }
      c.fillStyle = 'rgba(120,32,30,.55)'; c.beginPath(); c.ellipse(0, 0, len * 0.58, gape * 2.4, 0, 0, TAU); c.fill();
      const g = c.createLinearGradient(0, -gape, 0, gape); g.addColorStop(0, '#5d0b10'); g.addColorStop(0.5, '#160103'); g.addColorStop(1, '#6a0d13');
      c.fillStyle = g; c.beginPath(); top.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); [...bot].reverse().forEach(([x, y]) => c.lineTo(x, y)); c.closePath(); c.fill();
      c.fillStyle = `rgba(170,16,24,${0.25 + 0.6 * b})`; c.beginPath(); c.ellipse(0, gape * 0.12, len * 0.34, gape * 0.42, 0, 0, TAU); c.fill();
      wet(-len * 0.12, -gape * 0.5, len * 0.1, gape * 0.16);
    }
    c.restore();
  }

  function gauzeTexture(c, x, y, w, h, alpha) {
    c.save(); c.globalAlpha *= alpha; c.strokeStyle = 'rgba(150,145,130,.35)'; c.lineWidth = 1;
    const step = Math.max(3, w / 9);
    for (let i = x + step; i < x + w; i += step) { c.beginPath(); c.moveTo(i, y + 2); c.lineTo(i, y + h - 2); c.stroke(); }
    for (let j = y + step; j < y + h; j += step) { c.beginPath(); c.moveTo(x + 2, j); c.lineTo(x + w - 2, j); c.stroke(); }
    c.restore();
  }

  function drawPad(c, x, y, s, rot, soak, pressing) {
    c.save(); c.translate(x, y); c.rotate(rot);
    const k = pressing ? 0.93 : 1; c.scale(k, k);
    c.fillStyle = 'rgba(0,0,0,.35)'; roundRect(c, -s / 2 + (pressing ? 2 : 6), -s / 2 + (pressing ? 3 : 9), s, s, s * 0.08); c.fill();
    const g = c.createLinearGradient(-s / 2, -s / 2, s / 2, s / 2); g.addColorStop(0, '#fbfaf5'); g.addColorStop(1, C.gauzeShade);
    c.fillStyle = g; roundRect(c, -s / 2, -s / 2, s, s, s * 0.08); c.fill();
    gauzeTexture(c, -s / 2, -s / 2, s, s, 0.9);
    if (soak > 0.01) {
      const rg = c.createRadialGradient(s * 0.04, s * 0.06, 0, 0, 0, s * (0.2 + 0.5 * soak));
      rg.addColorStop(0, `rgba(150,10,18,${0.75 * clamp(soak * 1.6, 0, 1)})`); rg.addColorStop(0.7, `rgba(170,20,26,${0.45 * soak})`); rg.addColorStop(1, 'rgba(170,20,26,0)');
      c.fillStyle = rg; roundRect(c, -s / 2, -s / 2, s, s, s * 0.08); c.fill();
    }
    c.restore();
  }

  function capsule(c, x, y, wdt, len, ang) {
    c.save(); c.translate(x, y); c.rotate(ang);
    roundRect(c, -wdt / 2, -len, wdt, len, wdt / 2);
    c.restore();
  }

  function drawGlove(c, x, y, s, rot, pressing) {
    // a gloved hand from above, heel of the palm on the pad, fingers pointing away
    c.save(); c.translate(x, y); c.rotate(rot);
    const k = pressing ? 0.94 : 1.03; c.scale(k, k);
    const sh = pressing ? 0.05 : 0.14;
    const parts = () => {
      const f = [[-0.27, 0.40, -0.16], [-0.09, 0.47, -0.05], [0.09, 0.45, 0.05], [0.26, 0.37, 0.16]];
      f.forEach(([fx, fl, fa]) => { capsule(c, fx * s, -0.24 * s, 0.17 * s, fl * s, fa); c.fill(); });
      capsule(c, -0.36 * s, 0.1 * s, 0.19 * s, 0.4 * s, -1.05); c.fill();
      roundRect(c, -0.39 * s, -0.3 * s, 0.78 * s, 0.68 * s, 0.24 * s); c.fill();
    };
    c.fillStyle = 'rgba(0,0,0,.32)'; c.save(); c.translate(sh * s, sh * 1.4 * s); parts(); c.restore();
    const g = c.createLinearGradient(-0.4 * s, -0.7 * s, 0.4 * s, 0.4 * s);
    g.addColorStop(0, '#8ab6e2'); g.addColorStop(0.55, C.glove); g.addColorStop(1, C.gloveDark);
    c.fillStyle = g; parts();
    c.strokeStyle = 'rgba(20,45,80,.45)'; c.lineWidth = Math.max(1, s * 0.012);
    [[-0.18, -0.28], [0, -0.3], [0.18, -0.28]].forEach(([fx, fy]) => { c.beginPath(); c.moveTo(fx * s, fy * s); c.lineTo(fx * s, (fy - 0.07) * s); c.stroke(); });
    c.strokeStyle = 'rgba(255,255,255,.22)'; c.lineWidth = Math.max(1, s * 0.016);
    c.beginPath(); c.moveTo(-0.3 * s, -0.22 * s); c.quadraticCurveTo(0, -0.3 * s, 0.3 * s, -0.22 * s); c.stroke();
    c.fillStyle = 'rgba(25,55,95,.55)'; roundRect(c, -0.34 * s, 0.28 * s, 0.68 * s, 0.12 * s, 0.05 * s); c.fill();
    c.restore();
  }

  function drawRoll(c, x, y, s, rot, tail) {
    c.save(); c.translate(x, y); c.rotate(rot);
    c.fillStyle = 'rgba(0,0,0,.3)'; c.beginPath(); c.ellipse(s * 0.1, s * 0.62, s * 0.9, s * 0.2, 0, 0, TAU); c.fill();
    const g = c.createLinearGradient(0, -s * 0.5, 0, s * 0.5); g.addColorStop(0, '#ffffff'); g.addColorStop(0.55, '#e9e6dc'); g.addColorStop(1, '#bdb8aa');
    c.fillStyle = g; c.fillRect(-s * 0.7, -s * 0.45, s * 1.4, s * 0.9);
    c.fillStyle = '#d8d4c7'; c.beginPath(); c.ellipse(s * 0.7, 0, s * 0.18, s * 0.45, 0, 0, TAU); c.fill();
    c.strokeStyle = 'rgba(150,145,130,.6)'; c.lineWidth = 1;
    for (let i = 1; i < 4; i++) { c.beginPath(); c.ellipse(s * 0.7, 0, s * 0.18 * i / 4, s * 0.45 * i / 4, 0, 0, TAU); c.stroke(); }
    c.fillStyle = '#f7f6f0'; c.beginPath(); c.ellipse(-s * 0.7, 0, s * 0.18, s * 0.45, 0, 0, TAU); c.fill();
    if (tail) { c.fillStyle = '#f4f2ea'; c.beginPath(); c.moveTo(-s * 0.2, s * 0.45); c.lineTo(s * 0.35, s * 0.45); c.lineTo(s * 0.5, s * 1.05); c.lineTo(-s * 0.1, s * 1.1); c.closePath(); c.fill(); }
    c.restore();
  }

  function drawBand(c, center, axis, across, bw, soak, idx) {
    // one turn of bandage across the limb
    const a = Math.atan2(axis.y, axis.x);
    c.save(); c.translate(center.x, center.y); c.rotate(a);
    c.fillStyle = 'rgba(0,0,0,.25)'; roundRect(c, -bw / 2 + 2, -across / 2 + 4, bw, across, bw * 0.18); c.fill();
    const g = c.createLinearGradient(0, -across / 2, 0, across / 2);
    g.addColorStop(0, '#b9b5a8'); g.addColorStop(0.18, '#efede5'); g.addColorStop(0.5, '#fbfaf6'); g.addColorStop(0.82, '#e6e3d9'); g.addColorStop(1, '#aaa598');
    c.fillStyle = g; roundRect(c, -bw / 2, -across / 2, bw, across, bw * 0.16); c.fill();
    c.strokeStyle = 'rgba(140,135,120,.35)'; c.lineWidth = 1;
    for (let i = 1; i < 4; i++) { const x = -bw / 2 + (bw * i) / 4; c.beginPath(); c.moveTo(x, -across / 2 + 3); c.lineTo(x, across / 2 - 3); c.stroke(); }
    c.strokeStyle = 'rgba(255,255,255,.7)'; c.beginPath(); c.moveTo(-bw / 2 + 1, -across / 2 + 4); c.lineTo(-bw / 2 + 1, across / 2 - 4); c.stroke();
    if (soak > 0.02) {
      const rg = c.createRadialGradient(0, across * 0.04 * ((idx % 2) ? 1 : -1), 0, 0, 0, across * (0.12 + 0.3 * soak));
      rg.addColorStop(0, `rgba(150,12,20,${0.7 * clamp(soak * 1.4, 0, 1)})`); rg.addColorStop(1, 'rgba(150,12,20,0)');
      c.fillStyle = rg; roundRect(c, -bw / 2, -across / 2, bw, across, bw * 0.16); c.fill();
    }
    c.restore();
  }

  // plain guide circle (dashed path the hand follows)
  function ringDash(c, x, y, r, col, wdt, dash) {
    c.save(); c.strokeStyle = col; c.lineWidth = wdt; if (dash) c.setLineDash(dash);
    c.beginPath(); c.arc(x, y, r, 0, TAU); c.stroke(); c.restore();
  }

  // target reticle: four bracket arcs that turn slowly, cardinal ticks, soft glow (no dashed circles)
  function ring(c, x, y, r, col, wdt, dash) {
    if (!dash) return ringDash(c, x, y, r, col, wdt);
    const t = now() / 1000;
    c.save(); c.translate(x, y);
    c.lineCap = 'round';
    c.strokeStyle = col; c.globalAlpha *= 0.22; c.lineWidth = wdt * 0.6;
    c.beginPath(); c.arc(0, 0, r, 0, TAU); c.stroke();
    c.globalAlpha /= 0.22;
    c.rotate(t * 0.55);
    c.shadowColor = col; c.shadowBlur = wdt * 4;
    c.lineWidth = wdt * 1.35;
    for (let i = 0; i < 4; i++) { const a = i * TAU / 4 + Math.PI / 4; c.beginPath(); c.arc(0, 0, r, a - 0.44, a + 0.44); c.stroke(); }
    c.shadowBlur = 0; c.lineWidth = wdt;
    for (let i = 0; i < 4; i++) {
      const a = i * TAU / 4 + Math.PI / 4;
      c.beginPath(); c.moveTo(Math.cos(a) * (r - wdt * 2), Math.sin(a) * (r - wdt * 2)); c.lineTo(Math.cos(a) * (r - wdt * 5.5), Math.sin(a) * (r - wdt * 5.5)); c.stroke();
    }
    c.restore();
  }

  // dark label chip on the stage: tone diamond + tinted hairline, readable over any scene
  const TONE = {
    red: ['#ff5a60', 'rgba(255,90,96,.55)'], teal: ['#0fd4c4', 'rgba(15,212,196,.55)'],
    amber: ['#f3c35a', 'rgba(243,195,90,.55)'], '': ['rgba(255,255,255,.75)', 'rgba(255,255,255,.14)'],
  };
  function label(c, x, y, text, tone, U) {
    c.save();
    const [col, edge] = TONE[tone || ''] || TONE[''];
    c.font = `600 ${Math.round(12 * U)}px Lexend, system-ui, sans-serif`;
    const dm = 4.2 * U, padL = 11 * U, padR = 12 * U, gap = 8 * U;
    const w = padL + dm * 2 + gap + c.measureText(text).width + padR, h = 27 * U;
    const x0 = Math.round(x - w / 2), y0 = Math.round(y - h / 2);
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 16 * U; c.shadowOffsetY = 5 * U;
    const g = c.createLinearGradient(0, y0, 0, y0 + h); g.addColorStop(0, 'rgba(26,28,32,.95)'); g.addColorStop(1, 'rgba(10,11,13,.95)');
    c.fillStyle = g; roundRect(c, x0, y0, w, h, 7 * U); c.fill();
    c.shadowColor = 'transparent'; c.shadowBlur = 0; c.shadowOffsetY = 0;
    c.strokeStyle = edge; c.lineWidth = Math.max(1, U); roundRect(c, x0 + 0.5, y0 + 0.5, w - 1, h - 1, 7 * U); c.stroke();
    c.strokeStyle = 'rgba(255,255,255,.09)'; c.beginPath(); c.moveTo(x0 + 7 * U, y0 + 1.5); c.lineTo(x0 + w - 7 * U, y0 + 1.5); c.stroke();
    const dx = x0 + padL + dm;
    c.fillStyle = col; c.shadowColor = col; c.shadowBlur = 8 * U;
    c.beginPath(); c.moveTo(dx, y - dm); c.lineTo(dx + dm, y); c.lineTo(dx, y + dm); c.lineTo(dx - dm, y); c.closePath(); c.fill();
    c.shadowBlur = 0;
    c.fillStyle = '#f4f6f2'; c.textAlign = 'left'; c.textBaseline = 'middle'; c.fillText(text, dx + dm + gap, y + 0.5 * U);
    c.restore();
  }

  /* ═════════════════════════════ PREVIEW BACKDROP ═════════════════════════════
     Browser preview only: a stylised close-up of the patient so the overlay can be judged.
     In game the real camera image is behind the (transparent) page. */
  const Backdrop = {
    preset: null, t0: now(), cache: null,
    base(preset) {
      const P = (x, y) => ({ x, y, visible: true });
      if (preset === 'leg') return { j0: P(0.27, 0.26), j1: P(0.6, 0.5), j2: P(0.86, 0.72) };
      if (preset === 'legfar') return { j0: P(0.27, 0.27), j1: P(0.47, 0.44), j2: P(0.65, 0.62) };
      if (preset === 'torso') return { wound: P(0.47, 0.41), pel: P(0.62, 0.78), neck: P(0.36, 0.06) };
      if (preset === 'neck') return { head: P(0.47, 0.22), neck: P(0.49, 0.4), chest: P(0.52, 0.66) };
      return {};
    },
    breath() { return Math.sin(((now() - this.t0) / 1000) * TAU / 4.2) * 0.0025; },
    anchors(preset) {
      const b = this.base(preset), br = this.breath(), out = {};
      Object.keys(b).forEach(k => { out[k] = { x: b[k].x, y: b[k].y + br, visible: true }; });
      return out;
    },
    draw(c, W, H, anc, preset) {
      const key = `${preset}|${W}|${H}`;
      if (!this.cache || this.cache.key !== key) this.cache = { key, ground: this.paintGround(W, H), body: this.paintBody(W, H, preset) };
      c.drawImage(this.cache.ground, 0, 0);
      c.drawImage(this.cache.body, 0, Math.round(this.breath() * H * 10) / 10);
      const v = c.createRadialGradient(W / 2, H / 2, H * 0.3, W / 2, H / 2, H * 0.98); v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,.5)');
      c.fillStyle = v; c.fillRect(0, 0, W, H);
    },
    canvas(W, H) { const cv = document.createElement('canvas'); cv.width = W; cv.height = H; return cv; },
    // wet asphalt: aggregate speckle, tar blotches, a worn lane line, an oil stain, glass grit
    paintGround(W, H) {
      const cv = this.canvas(W, H), c = cv.getContext('2d'), U = H / 1080, R = rng(11);
      const g = c.createLinearGradient(0, 0, W, H); g.addColorStop(0, '#3b3d3f'); g.addColorStop(0.55, '#2c2e30'); g.addColorStop(1, '#1f2022');
      c.fillStyle = g; c.fillRect(0, 0, W, H);
      for (let i = 0; i < 40; i++) {
        const x = R() * W, y = R() * H, r = (60 + R() * 260) * U, rg = c.createRadialGradient(x, y, 0, x, y, r);
        const dark = R() < 0.6; rg.addColorStop(0, dark ? 'rgba(0,0,0,.16)' : 'rgba(255,255,255,.04)'); rg.addColorStop(1, 'rgba(0,0,0,0)');
        c.fillStyle = rg; c.fillRect(x - r, y - r, r * 2, r * 2);
      }
      // worn lane marking across the far corner
      c.save(); c.translate(W * 0.9, -H * 0.05); c.rotate(0.62);
      c.fillStyle = 'rgba(214,210,196,.42)'; c.fillRect(-26 * U, 0, 52 * U, H * 1.6);
      c.restore();
      // aggregate: tiny stones, light and dark, a few bigger ones
      const n = Math.round((W * H) / 70);
      for (let i = 0; i < n; i++) {
        const x = R() * W, y = R() * H, s = (R() < 0.9 ? 1 : 2) * Math.max(1, U);
        const l = R();
        c.fillStyle = l < 0.55 ? `rgba(0,0,0,${0.15 + R() * 0.25})` : `rgba(255,255,255,${0.025 + R() * 0.08})`;
        c.fillRect(x, y, s, s);
      }
      // oil stain and a damp patch
      [[0.14, 0.8, 120], [0.78, 0.18, 90]].forEach(([x, y, r]) => {
        const rg = c.createRadialGradient(x * W, y * H, 0, x * W, y * H, r * U);
        rg.addColorStop(0, 'rgba(8,8,10,.42)'); rg.addColorStop(0.7, 'rgba(8,8,10,.18)'); rg.addColorStop(1, 'rgba(8,8,10,0)');
        c.fillStyle = rg; c.beginPath(); c.ellipse(x * W, y * H, r * U * 1.4, r * U, 0.4, 0, TAU); c.fill();
      });
      for (let i = 0; i < 70; i++) { c.fillStyle = `rgba(200,225,230,${0.15 + R() * 0.3})`; c.fillRect(W * (0.2 + R() * 0.6), H * (0.15 + R() * 0.7), 1.5 * U, 1.5 * U); }
      return cv;
    },
    paintBody(W, H, preset) {
      const cv = this.canvas(W, H), c = cv.getContext('2d'), U = H / 1080, R = rng(5);
      const b = this.base(preset); const px = id => ({ x: b[id].x * W, y: b[id].y * H });
      const MAT = {
        denim: { base: '#1d3050', mid: '#2b4670', hi: '#4a6b98', dark: '#0c1420', twill: 'rgba(255,255,255,.05)', seam: 'rgba(214,170,92,.6)' },
        denim2: { base: '#18283f', mid: '#223a5c', hi: '#3a5880', dark: '#0a111b', twill: 'rgba(255,255,255,.04)', seam: 'rgba(214,170,92,.45)' },
        jacket: { base: '#1a1c20', mid: '#25292f', hi: '#3c424b', dark: '#08090b', twill: 'rgba(255,255,255,.03)' },
        shirt: { base: '#39414d', mid: '#48525f', hi: '#66707f', dark: '#1a1f26', twill: 'rgba(255,255,255,.035)' },
        skin: { base: '#a8765a', mid: '#c08c6c', hi: '#dcb091', dark: '#6e4733' },
      };
      const capsule = (a, e, wa, wb) => {
        const d = norm(sub(e, a)), n = perp(d), p = new Path2D();
        const A0 = Math.atan2(n.y, n.x);
        p.arc(a.x, a.y, wa, A0, A0 + Math.PI);
        p.arc(e.x, e.y, wb, A0 + Math.PI, A0 + TAU);
        p.closePath();
        return { p, d, n };
      };
      const cloth = (a, e, wa, wb, m, opt = {}) => {
        const { p, d, n } = capsule(a, e, wa, wb);
        c.save(); c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 34 * U; c.shadowOffsetX = 8 * U; c.shadowOffsetY = 16 * U; c.fillStyle = m.base; c.fill(p); c.restore();
        const lg = c.createLinearGradient(a.x + n.x * wa, a.y + n.y * wa, a.x - n.x * wa, a.y - n.y * wa);
        lg.addColorStop(0, m.hi); lg.addColorStop(0.3, m.mid); lg.addColorStop(0.75, m.base); lg.addColorStop(1, m.dark);
        c.fillStyle = lg; c.fill(p);
        c.save(); c.clip(p);
        const L = dist(a, e) + Math.max(wa, wb) * 2, ang = Math.atan2(d.y, d.x);
        if (m.twill) {
          c.save(); c.translate((a.x + e.x) / 2, (a.y + e.y) / 2); c.rotate(ang + 1.05);
          c.strokeStyle = m.twill; c.lineWidth = Math.max(1, U);
          for (let k = -L; k < L; k += 3.2 * U) { c.beginPath(); c.moveTo(-L, k); c.lineTo(L, k); c.stroke(); }
          c.restore();
          for (let i = 0; i < L * 0.6; i++) { const u = R(), v2 = (R() - 0.5) * 2, q = add(mix(a, e, u), mul(n, v2 * lerp(wa, wb, u))); c.fillStyle = `rgba(255,255,255,${0.03 + R() * 0.05})`; c.fillRect(q.x, q.y, (2 + R() * 4) * U, Math.max(1, U * 0.8)); }
        } else {
          for (let i = 0; i < L * 1.4; i++) { const u = R(), v2 = (R() - 0.5) * 2, q = add(mix(a, e, u), mul(n, v2 * lerp(wa, wb, u))); c.fillStyle = R() < 0.5 ? 'rgba(90,50,30,.08)' : 'rgba(255,230,210,.05)'; c.fillRect(q.x, q.y, 1.5 * U, 1.5 * U); }
        }
        if (m.seam && opt.seam !== false) {
          const off = (opt.seamSide || 1) * 0.66;
          c.strokeStyle = 'rgba(0,0,0,.35)'; c.lineWidth = 3 * U;
          c.beginPath(); c.moveTo(a.x + n.x * wa * off, a.y + n.y * wa * off); c.lineTo(e.x + n.x * wb * off, e.y + n.y * wb * off); c.stroke();
          c.strokeStyle = m.seam; c.lineWidth = 1.4 * U; c.setLineDash([5 * U, 4 * U]);
          [-3.2, 3.2].forEach(o => { c.beginPath(); c.moveTo(a.x + n.x * (wa * off + o * U), a.y + n.y * (wa * off + o * U)); c.lineTo(e.x + n.x * (wb * off + o * U), e.y + n.y * (wb * off + o * U)); c.stroke(); });
          c.setLineDash([]);
        }
        (opt.folds || []).forEach(([u, s]) => {
          const q = mix(a, e, u), w2 = lerp(wa, wb, u);
          c.strokeStyle = 'rgba(0,0,0,.28)'; c.lineWidth = 5 * U * s;
          c.beginPath(); c.moveTo(q.x + n.x * w2 * 0.9, q.y + n.y * w2 * 0.9); c.quadraticCurveTo(q.x + d.x * w2 * 0.35 * s, q.y + d.y * w2 * 0.35 * s, q.x - n.x * w2 * 0.6, q.y - n.y * w2 * 0.6); c.stroke();
          c.strokeStyle = 'rgba(255,255,255,.07)'; c.lineWidth = 2 * U;
          c.beginPath(); c.moveTo(q.x + n.x * w2 * 0.85 - d.x * 6 * U, q.y + n.y * w2 * 0.85 - d.y * 6 * U); c.quadraticCurveTo(q.x + d.x * w2 * 0.3 * s - d.x * 6 * U, q.y + d.y * w2 * 0.3 * s - d.y * 6 * U, q.x - n.x * w2 * 0.5 - d.x * 6 * U, q.y - n.y * w2 * 0.5 - d.y * 6 * U); c.stroke();
        });
        c.restore();
        c.strokeStyle = 'rgba(255,255,255,.08)'; c.lineWidth = 1.5 * U; c.stroke(p);
        return { p, d, n };
      };
      const boot = (at, dir, s) => {
        c.save(); c.translate(at.x, at.y); c.rotate(Math.atan2(dir.y, dir.x));
        c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 20 * U; c.shadowOffsetY = 10 * U;
        const bg = c.createLinearGradient(0, -s * 0.5, 0, s * 0.5); bg.addColorStop(0, '#2b2622'); bg.addColorStop(1, '#0d0c0b');
        c.fillStyle = bg; c.beginPath(); c.ellipse(s * 0.25, 0, s * 0.62, s * 0.4, 0, 0, TAU); c.fill(); c.shadowBlur = 0; c.shadowOffsetY = 0;
        c.fillStyle = '#070707'; c.beginPath(); c.ellipse(s * 0.32, 0, s * 0.66, s * 0.44, 0, -0.5, 0.5); c.lineTo(s * 0.3, 0); c.fill();
        c.strokeStyle = 'rgba(255,255,255,.18)'; c.lineWidth = 1.5 * U;
        for (let i = 0; i < 4; i++) { c.beginPath(); c.moveTo(-s * 0.05 + i * s * 0.12, -s * 0.14); c.lineTo(-s * 0.05 + i * s * 0.12, s * 0.14); c.stroke(); }
        c.restore();
      };
      if (preset === 'leg' || preset === 'legfar') {
        const j0 = px('j0'), j1 = px('j1'), j2 = px('j2'), L1 = dist(j0, j1), f = preset === 'leg' ? 1 : 0.95;
        const up = norm(sub(j0, j1)), n0 = perp(norm(sub(j1, j0)));
        cloth(add(j0, mul(up, L1 * 0.15)), add(j0, mul(up, L1 * 1.45)), L1 * 0.42, L1 * 0.46, MAT.jacket, { seam: false, folds: [[0.3, 1], [0.55, 0.7]] });
        // the other leg, half under the treated one
        const o0 = add(j0, mul(n0, -L1 * 0.36)), o1 = add(j1, mul(n0, -L1 * 0.5)), o2 = add(j2, mul(n0, -L1 * 0.52));
        cloth(o1, o2, L1 * 0.15, L1 * 0.12, MAT.denim2, { seamSide: -1 });
        cloth(o0, o1, L1 * 0.21, L1 * 0.16, MAT.denim2, { seamSide: -1 });
        boot(add(o2, mul(norm(sub(o2, o1)), L1 * 0.12)), norm(sub(o2, o1)), L1 * 0.22);
        cloth(j1, j2, L1 * 0.16 * f, L1 * 0.12 * f, MAT.denim, { folds: [[0.08, 0.9], [0.9, 0.6]] });
        cloth(j0, j1, L1 * 0.22 * f, L1 * 0.165 * f, MAT.denim, { folds: [[0.9, 1], [0.78, 0.6]] });
        boot(add(j2, mul(norm(sub(j2, j1)), L1 * 0.12)), norm(sub(j2, j1)), L1 * 0.23);
        // belt across the hip
        c.save(); c.translate(j0.x, j0.y); c.rotate(Math.atan2(n0.y, n0.x));
        c.fillStyle = '#121212'; c.fillRect(-L1 * 0.3, -L1 * 0.06 - L1 * 0.12, L1 * 0.6, L1 * 0.07);
        c.fillStyle = '#8d8a80'; c.fillRect(-L1 * 0.04, -L1 * 0.07 - L1 * 0.12, L1 * 0.06, L1 * 0.09);
        c.restore();
      } else if (preset === 'torso') {
        const nk = px('neck'), pl = px('pel'), wd = px('wound'), L = dist(nk, pl), d = norm(sub(pl, nk)), n = perp(d);
        const sh = add(nk, mul(d, L * 0.08));
        cloth(add(sh, mul(n, L * 0.36)), add(add(sh, mul(n, L * 0.6)), mul(d, L * 0.5)), L * 0.1, L * 0.08, MAT.jacket, { seam: false, folds: [[0.5, 0.8]] });
        cloth(add(sh, mul(n, -L * 0.36)), add(add(sh, mul(n, -L * 0.62)), mul(d, L * 0.48)), L * 0.1, L * 0.08, MAT.jacket, { seam: false, folds: [[0.45, 0.8]] });
        const tor = cloth(add(nk, mul(d, L * 0.1)), pl, L * 0.3, L * 0.26, MAT.shirt, { seam: false, folds: [[0.75, 1], [0.86, 0.7]] });
        // the shirt is cut open up the middle: bare chest around the wound, flaps folded back
        c.save(); c.clip(tor.p);
        const top = add(nk, mul(d, L * 0.12)), bot = add(wd, mul(d, L * 0.22));
        const half = L * 0.2, flap = new Path2D();
        flap.moveTo(top.x + n.x * half * 0.7, top.y + n.y * half * 0.7);
        for (let i = 0; i <= 10; i++) { const u = i / 10, q = mix(top, bot, u); const w2 = half * (0.7 + 0.35 * Math.sin(u * Math.PI)) + (R() - 0.5) * 6 * U; flap.lineTo(q.x + n.x * w2, q.y + n.y * w2); }
        for (let i = 10; i >= 0; i--) { const u = i / 10, q = mix(top, bot, u); const w2 = half * (0.7 + 0.35 * Math.sin(u * Math.PI)) + (R() - 0.5) * 6 * U; flap.lineTo(q.x - n.x * w2, q.y - n.y * w2); }
        flap.closePath();
        const sg = c.createLinearGradient(top.x + n.x * half, top.y + n.y * half, top.x - n.x * half, top.y - n.y * half);
        sg.addColorStop(0, MAT.skin.hi); sg.addColorStop(0.45, MAT.skin.mid); sg.addColorStop(1, MAT.skin.dark);
        c.fillStyle = sg; c.fill(flap);
        c.save(); c.clip(flap);
        for (let i = 0; i < 900; i++) { const q = add(mix(top, bot, R()), mul(n, (R() - 0.5) * half * 2)); c.fillStyle = R() < 0.5 ? 'rgba(90,50,30,.1)' : 'rgba(255,230,210,.06)'; c.fillRect(q.x, q.y, 1.4 * U, 1.4 * U); }
        c.strokeStyle = 'rgba(90,50,35,.25)'; c.lineWidth = 3 * U; c.beginPath(); c.moveTo(top.x, top.y); c.lineTo(bot.x, bot.y); c.stroke();
        c.restore();
        c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 14 * U; c.strokeStyle = 'rgba(120,130,145,.55)'; c.lineWidth = 3 * U; c.stroke(flap); c.shadowBlur = 0;
        c.restore();
        // head
        const hd = add(nk, mul(d, -L * 0.1));
        const hg = c.createRadialGradient(hd.x - L * 0.04, hd.y - L * 0.05, L * 0.02, hd.x, hd.y, L * 0.16);
        hg.addColorStop(0, MAT.skin.hi); hg.addColorStop(1, MAT.skin.dark);
        c.save(); c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 24 * U; c.shadowOffsetY = 10 * U;
        c.fillStyle = hg; c.beginPath(); c.ellipse(hd.x, hd.y, L * 0.13, L * 0.15, 0, 0, TAU); c.fill(); c.restore();
        c.fillStyle = '#1d140f'; c.beginPath(); c.ellipse(hd.x - d.x * L * 0.05, hd.y - d.y * L * 0.05, L * 0.135, L * 0.11, Math.atan2(d.y, d.x), Math.PI * 0.5, Math.PI * 1.5); c.fill();
      } else if (preset === 'neck') {
        const hd = px('head'), nk = px('neck'), ch = px('chest'), L = dist(hd, ch), d = norm(sub(ch, hd)), n = perp(d);
        cloth(add(nk, mul(n, L * 0.2)), add(ch, mul(n, L * 0.62)), L * 0.12, L * 0.1, MAT.jacket, { seam: false, folds: [[0.4, 0.9]] });
        cloth(add(nk, mul(n, -L * 0.2)), add(ch, mul(n, -L * 0.62)), L * 0.12, L * 0.1, MAT.jacket, { seam: false, folds: [[0.4, 0.9]] });
        cloth(add(nk, mul(d, L * 0.12)), add(ch, mul(d, L * 0.5)), L * 0.42, L * 0.4, MAT.jacket, { seam: false, folds: [[0.3, 1], [0.6, 0.8]] });
        // T-shirt neckline under the open jacket
        c.save(); c.translate(nk.x + d.x * L * 0.16, nk.y + d.y * L * 0.16); c.rotate(Math.atan2(d.y, d.x) - Math.PI / 2);
        c.fillStyle = '#4a5260'; c.beginPath(); c.ellipse(0, 0, L * 0.2, L * 0.13, 0, 0, Math.PI); c.fill();
        c.restore();
        cloth(hd, add(nk, mul(d, L * 0.12)), L * 0.11, L * 0.12, MAT.skin, { seam: false });
        // ears, head, hair
        c.save(); c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 26 * U; c.shadowOffsetY = 12 * U;
        const hg = c.createRadialGradient(hd.x - L * 0.06, hd.y - L * 0.1, L * 0.02, hd.x, hd.y, L * 0.26);
        hg.addColorStop(0, MAT.skin.hi); hg.addColorStop(0.6, MAT.skin.mid); hg.addColorStop(1, MAT.skin.dark); c.fillStyle = hg;
        c.beginPath(); c.ellipse(hd.x, hd.y - L * 0.05, L * 0.2, L * 0.24, 0, 0, TAU); c.fill(); c.restore();
        c.fillStyle = MAT.skin.mid; [[-1], [1]].forEach(([s2]) => { c.beginPath(); c.ellipse(hd.x + s2 * L * 0.2, hd.y - L * 0.02, L * 0.035, L * 0.06, 0, 0, TAU); c.fill(); });
        const hair = c.createLinearGradient(0, hd.y - L * 0.3, 0, hd.y - L * 0.05); hair.addColorStop(0, '#2b1e16'); hair.addColorStop(1, '#130d09');
        c.fillStyle = hair; c.beginPath(); c.ellipse(hd.x, hd.y - L * 0.14, L * 0.21, L * 0.17, 0, Math.PI, TAU); c.fill();
        c.strokeStyle = 'rgba(255,255,255,.06)'; c.lineWidth = 1.2 * U;
        for (let i = 0; i < 26; i++) { const a0 = Math.PI + R() * Math.PI; c.beginPath(); c.moveTo(hd.x + Math.cos(a0) * L * 0.2, hd.y - L * 0.14 + Math.sin(a0) * L * 0.16); c.lineTo(hd.x + Math.cos(a0) * L * 0.08, hd.y - L * 0.14 + Math.sin(a0) * L * 0.06); c.stroke(); }
        // closed eyes, brow, nose shadow
        c.strokeStyle = 'rgba(60,35,25,.7)'; c.lineWidth = 2.2 * U;
        [-1, 1].forEach(s2 => { c.beginPath(); c.arc(hd.x + s2 * L * 0.075, hd.y - L * 0.02, L * 0.035, 0.2, Math.PI - 0.2); c.stroke(); });
        c.fillStyle = 'rgba(90,55,40,.35)'; c.beginPath(); c.ellipse(hd.x + L * 0.012, hd.y + L * 0.06, L * 0.025, L * 0.045, 0, 0, TAU); c.fill();
        c.strokeStyle = 'rgba(120,60,50,.55)'; c.lineWidth = 2.5 * U; c.beginPath(); c.moveTo(hd.x - L * 0.05, hd.y + L * 0.13); c.quadraticCurveTo(hd.x, hd.y + L * 0.145, hd.x + L * 0.05, hd.y + L * 0.13); c.stroke();
      }
      return cv;
    },
  };

  /* ═════════════════════════════ THE APP ═════════════════════════════ */
  const app = NZA.app('treat', {
    escClose: false,

    init(root) {
      root.innerHTML = `
        <canvas class="tr-stage int"></canvas>
        <div class="tr-card nza-hud"></div>
        <div class="tr-dev"><div class="hx">
          <i class="hx-sc a"></i><i class="hx-sc b"></i><i class="hx-sc c"></i><i class="hx-sc d"></i>
          <div class="hx-head"><span class="hx-model"><b class="hx-code">--</b><span class="hx-name"></span></span><span class="hx-stat"><span class="hx-led"><span class="dev-led"></span></span><em class="hx-st">RUN</em></span></div>
          <div class="dev-screen"></div>
          <div class="hx-keys"><span class="hx-btn"><i></i><em>MODE</em></span><span class="hx-btn"><i></i><em>ZERO</em></span><span class="hx-btn t"><i></i><em>MUTE</em></span></div>
          <div class="hx-foot"><span class="hx-warn"><i></i><span class="hx-wt"></span></span><span class="hx-sn"></span></div>
        </div></div>
        <div class="tr-tag"></div>
        <div class="tr-meds nza-hud solid"></div>
        <div class="tr-kit nza-hud solid"></div>`;
      this.root = root;
      this.cv = root.querySelector('.tr-stage');
      this.card = root.querySelector('.tr-card');
      this.dev = root.querySelector('.tr-dev');
      this.devScreen = root.querySelector('.tr-dev .dev-screen');
      this.tag = root.querySelector('.tr-tag');
      this.medsEl = root.querySelector('.tr-meds');
      this.kitEl = root.querySelector('.tr-kit');
      this.anc = NZA.ui.Anchors('treat');
      this.cv.addEventListener('pointerdown', e => this.pDown(e));
      window.addEventListener('pointermove', e => { if (this.G) this.pMove(e); });
      window.addEventListener('pointerup', e => { if (this.G) this.pUp(e); });
    },

    open(data) {
      this.teardown();
      LOC = Object.assign({}, data.locale || {});
      if (data.keys) Object.assign(KEY, data.keys);
      this.d = data;
      this.mode = data.mode || 'bleed';
      FX.reset();
      this.G = { t: 0, start: now(), lost: 0, b: 1, ptr: null, down: false, steps: {}, beatT: 0, hr: (data.vitals && data.vitals.hr) || 90, sys: (data.vitals && data.vitals.sys) || 120 };
      this.result = null; this.sent = false; this.vit = data.vitals || {}; this.tipText = ''; this.tipTone = '';
      this.cv.style.display = (this.mode === 'meds' || this.mode === 'kit') ? 'none' : '';
      if (this.mode === 'meds') return this.openMeds(data);
      if (this.mode === 'kit') return this.openKit(data);
      this.card.classList.add('on');
      this.dev.classList.add('on');
      this.pp = NZA.ui.ProcPanel(this.root, { onAbort: () => this.abort(), onTool: () => {} });
      if (this.mode === 'bleed') this.initBleed(); else if (this.mode === 'tq') this.initTq(); else this.initCollar();
      this.renderCard();
      this.last = now();
      const loop = () => { this.raf = requestAnimationFrame(loop); this.frame(); };
      this.raf = requestAnimationFrame(loop);
    },

    close() { this.teardown(); },

    teardown() {
      cancelAnimationFrame(this.raf); this.raf = 0;
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      if (this.holdBtn) { this.holdBtn.destroy(); this.holdBtn = null; }
      this.card && this.card.classList.remove('on');
      this.dev && this.dev.classList.remove('on');
      this.medsEl && this.medsEl.classList.remove('on', 'busy');
      this.kitEl && this.kitEl.classList.remove('on');
      this.tag && this.tag.classList.remove('on');
      if (this.cv) { this.cv.className = 'tr-stage int'; const c = this.cv.getContext('2d'); c.clearRect(0, 0, this.cv.width, this.cv.height); }
      this.G = null; this.ph = null;
    },

    abort() {
      if (!this.G || this.sent) return;
      this.sent = true;
      NZA.post('treat:abort', {});
      NZA.close('treat');
    },

    /* ─────────────── messages from Lua ─────────────── */
    msg: {
      vitals(d) { const a = app; if (!a.G || !d) return; a.G.hr = d.hr || a.G.hr; a.G.sys = d.sys || a.G.sys; a.vit = d; a.renderVitals(); },
      result(o) { app.showResult(o || {}); },
      meds(info) { if (app.mode === 'meds' && info) { app.d.info = info; app.medsEl.classList.remove('busy'); app.renderMeds(); } },
      given(d) {
        const a = app; if (a.mode !== 'meds') return;
        a.medsEl.classList.remove('busy');
        if (d && d.ok) { NZA.audio.success(); if (d.drugs) a.d.drugs = d.drugs; } else NZA.audio.fail();
        a.renderMeds();
      },
    },

    /* ─────────────── keys ─────────────── */
    keys: {
      Escape(e) {
        const a = app;
        if (a.mode === 'meds' || a.mode === 'kit') { NZA.close('treat'); return true; }
        if (a.result) { a.closeDone(); return true; }
        return false;   // ProcPanel hold-to-abort
      },
      Enter(e) {
        const a = app;
        if (a.result && a.pp) return a.pp.key(e);
        if (a.mode === 'meds') { a.giveSelected(); return true; }
        if (a.ph && a.ph.key) return a.ph.key(e) !== false;
        return false;
      },
      ' '(e) { const a = app; if (a.ph && a.ph.key && !e.repeat) return a.ph.key(e) !== false; return a.ph ? true : false; },
      KeyE(e) { const a = app; if (a.ph && a.ph.key) return a.ph.key(e) !== false; return false; },
      ArrowUp(e) { const a = app; if (a.mode === 'meds') { a.moveDrug(-1); return true; } if (a.mode === 'kit') { a.moveKit(-1); return true; } return false; },
      ArrowDown(e) { const a = app; if (a.mode === 'meds') { a.moveDrug(1); return true; } if (a.mode === 'kit') { a.moveKit(1); return true; } return false; },
      Digit1(e) { return app.digit(1, e); }, Digit2(e) { return app.digit(2, e); }, Digit3(e) { return app.digit(3, e); },
      Digit4(e) { return app.digit(4, e); }, Digit5(e) { return app.digit(5, e); }, Digit6(e) { return app.digit(6, e); },
      KeyQ(e) { return app.routeKey(0); }, KeyW(e) { return app.routeKey(1); }, KeyR(e) { return app.routeKey(2); },
    },
    keysUp: {
      ' '(e) { const a = app; if (a.ph && a.ph.keyUp) { a.ph.keyUp(e); return true; } return false; },
    },

    digit(n, e) {
      if (this.mode === 'kit') { this.useKit(n - 1); return true; }
      if (this.mode === 'meds') { const dr = this.curDrug(); if (dr && dr.doses[n - 1]) { this.ms.dose = n; this.renderMeds(); } return true; }
      if (this.ph && this.ph.key) return this.ph.key(e) !== false;
      return false;
    },

    /* ─────────────── pointer ─────────────── */
    pt(e) { const p = NZA.pointer(e); const W = this.cv.width || 1, H = this.cv.height || 1; return { x: p.x * W, y: p.y * H }; },
    pDown(e) {
      if (!this.G || e.button !== 0 || this.result) return;
      this.G.ptr = this.pt(e); this.G.down = true;
      if (this.ph && this.ph.down) this.ph.down(this.G.ptr);
    },
    pMove(e) { const p = this.pt(e); this.G.ptr = p; if (this.ph && this.ph.move) this.ph.move(p); },
    pUp(e) { if (e.button !== 0) return; const was = this.G.down; this.G.down = false; if (was && this.ph && this.ph.up) this.ph.up(this.G.ptr); },

    /* ─────────────── frame ─────────────── */
    frame() {
      const t = now(); const dt = Math.min(0.05, (t - this.last) / 1000); this.last = t;
      const G = this.G; if (!G) return;
      G.t += dt;
      const fit = NZA.fitCanvas(this.cv); const W = fit.w, H = fit.h;
      const c = this.cv.getContext('2d');
      let anc = this.anc.all();
      if (!NZA.inGame && this.preset) { anc = Backdrop.anchors(this.preset); }
      G.anc = anc; G.W = W; G.H = H; G.U = H / 1080;
      const w = this.geo();
      c.clearRect(0, 0, W, H);
      if (!NZA.inGame && this.preset) Backdrop.draw(c, W, H, anc, this.preset);
      if (!w) { this.pp && this.statusTick(dt); return; }
      G.w = w;
      if (this.ph && this.ph.update) this.ph.update(dt, w);
      this.bleedTick(dt, w);
      FX.update(dt, w);
      if (this.ph && this.ph.draw) this.ph.draw(c, w); else this.drawDefault(c, w);
      if (this.mode === 'bleed' && this.trace) this.drawTrace();
      this.statusTick(dt);
    },

    // geometry from the anchors → wound point, limb axis, scale. Sizes are real centimetres:
    // w.cm = screen px per cm at the wound (from the limb / torso length on screen)
    geo() {
      const G = this.G, d = this.d, W = G.W, H = G.H, U = G.U;
      const A = id => { const p = G.anc && G.anc[id]; return p && p.visible !== false && p.x !== undefined ? { x: p.x * W, y: p.y * H } : null; };
      const drift = G.drift || { x: 0, y: 0 };
      const breath = Math.sin(G.t * TAU / 4.4) * 2.2 * U;
      const sev = (d.injury && d.injury.severity) || 2;
      const finish = g => {
        g.U = U; g.k = g.cm / 7;
        g.rw = g.cm * (0.5 + sev * 0.14);
        g.tr = Math.max(g.rw * 2.4, g.cm * 2.6, 30 * U);
        return g;
      };
      if (this.mode === 'collar') {
        const hd = A('head'), nk = A('neck'), ch = A('chest');
        if (!hd || !nk) return null;
        const axis = norm(sub(nk, hd)), L = dist(hd, nk);
        return finish({ head: hd, neck: nk, chest: ch || add(nk, mul(axis, L)), axis, n: perp(axis), L, cm: L / 18, x: nk.x, y: nk.y, ang: Math.atan2(axis.y, axis.x) });
      }
      const limbSeg = this.limbSeg();
      if (limbSeg) {
        const j0 = A('j0'), j1 = A('j1'), j2 = A('j2');
        if (!j0 || !j1 || !j2) return null;
        const leg = (d.limb || (d.injury && d.injury.limb)) === 'leg';
        const L1 = dist(j0, j1), L2 = dist(j1, j2);
        const seg = limbSeg.seg, frac = limbSeg.frac;
        const a = seg === 'upper' ? j0 : j1, b = seg === 'upper' ? j1 : j2;
        const axis = norm(sub(b, a));
        // segment lengths: thigh 44 cm, lower leg 42, upper arm 30, forearm 26 · widths 16 / 11 / 10 / 8 cm
        const segCm = leg ? (seg === 'upper' ? 44 : 42) : (seg === 'upper' ? 30 : 26);
        const widCm = leg ? (seg === 'upper' ? 16 : 11) : (seg === 'upper' ? 10 : 8);
        const cm = Math.max(2.5 * U, (seg === 'upper' ? L1 : L2) / segCm);
        const limbW = widCm * cm;
        const base = mix(a, b, frac);
        const n = perp(axis);
        const side = d.injury && d.injury.spot ? (d.injury.spot.x - 0.5) * limbW * 0.35 : 0;
        const p = add(add(base, mul(n, side)), { x: drift.x, y: drift.y + breath });
        return finish({ x: p.x, y: p.y, axis, n, ang: Math.atan2(axis.y, axis.x), cm, limbW, j0, j1, j2, L1, L2, leg, seg });
      }
      const wd = A('wound'), pel = A('pel'), nk = A('neck');
      if (!wd) return null;
      const axis = pel && nk ? norm(sub(pel, nk)) : { x: 0, y: 1 };
      const L = pel && nk ? dist(pel, nk) : 480 * U;
      const cm = Math.max(2.5 * U, L / 55), limbW = cm * 34, n = perp(axis);
      const side = d.injury && d.injury.spot ? (d.injury.spot.x - 0.5) * limbW * 0.5 : 0;
      const p = add(add(wd, mul(n, side)), { x: drift.x, y: drift.y + breath });
      return finish({ x: p.x, y: p.y, axis, n, ang: Math.atan2(axis.y, axis.x), cm, limbW, torso: true });
    },

    limbSeg() {
      const d = this.d;
      if (this.mode === 'tq') return { seg: d.woundSeg || 'upper', frac: d.woundFrac || 0.5 };
      const inj = d.injury;
      if (!inj || !inj.limb) return null;
      return { seg: /upper/.test(inj.region) ? 'upper' : 'lower', frac: inj.frac || 0.5 };
    },

    // shared bleeding simulation: emits blood according to G.b (0..1 of the wound's bleed)
    bleedTick(dt, w) {
      const G = this.G, d = this.d;
      if (this.mode === 'collar') return;
      const inj = d.injury; if (!inj) return;
      const bleed = Math.max(0, inj.bleed || 0);
      const flow = bleed * G.b * (G.cover ? 0.15 : 1);
      G.lost += flow * dt / 60;
      G.flowNow = flow;
      // heartbeat clock (also drives the device trace and the distal pulse)
      G.beatT -= dt;
      const beatNow = G.beatT <= 0;
      if (beatNow) { G.beatT = 60 / clamp(G.hr || 90, 30, 200); G.beat = 1; }
      G.beat = Math.max(0, (G.beat || 0) - dt * 4);
      const intensity = clamp(Math.log10(1 + bleed) / 2.4, 0.15, 1) * G.b * (G.cover ? 0.1 : 1);
      if (intensity < 0.01) return;
      const cm = w.cm;
      // the ground side: blood runs off the limb sideways (patient lying down)
      const down = w.n ? mul(w.n, (d.injury && d.injury.spot && d.injury.spot.x < 0.5) ? -1 : 1) : { x: 0, y: 1 };
      if (beatNow && inj.arterial) {
        const n = Math.round(3 + 9 * intensity);
        for (let i = 0; i < n; i++) {
          const a = Math.random() * TAU;
          const dir = norm(add({ x: Math.cos(a), y: Math.sin(a) }, mul(down, 0.6)));
          FX.emit({ kind: 'jet', x0: w.x, y0: w.y, x: w.x, y: w.y, dx: dir.x, dy: dir.y, d: cm * (1.5 + Math.random() * 7 * (0.4 + intensity)), T: 0.18 + Math.random() * 0.22, t: 0, r: cm * (0.1 + Math.random() * 0.18), sc: 1 });
        }
      }
      G.oozeT = (G.oozeT || 0) - dt;
      if (G.oozeT <= 0) {
        G.oozeT = lerp(0.7, 0.07, intensity);
        const a = Math.random() * TAU;
        const sp = cm * (1.5 + Math.random() * 3) * (0.5 + intensity);
        const dir = norm(add(mul(down, 1), { x: (Math.random() - 0.5) * 0.7, y: (Math.random() - 0.5) * 0.7 }));
        FX.emit({ kind: 'run', x: w.x + Math.cos(a) * w.rw * 0.7, y: w.y + Math.sin(a) * w.rw * 0.6, vx: dir.x * sp, vy: dir.y * sp, r: cm * (0.16 + Math.random() * 0.14), life: 0.8 + intensity * 2.2, trail: 0, seed: Math.random() });
      }
      // the soaked patch around the wound grows with the blood lost
      G.stainT = (G.stainT || 0) - dt;
      if (G.stainT <= 0) {
        G.stainT = 0.22;
        const grow = 1 + Math.min(2.5, G.lost / 140), a = Math.random() * TAU, r = (0.6 + Math.random() * 1.6) * grow;
        FX.stain(Math.cos(a) * r + down.x * grow * 0.8, Math.sin(a) * r * 0.75 + down.y * grow * 0.8, (0.8 + Math.random() * 0.9) * grow, 0.1 + 0.16 * intensity);
      }
    },

    // gauze folds packed into the wound, soaking red over time (stay visible in later steps)
    drawPacking(c, w) {
      const G = this.G;
      (G.strips || []).forEach((st, i) => {
        const soak = clamp((G.t - st.born) / 6, 0, 1) * (0.4 + 0.6 * G.b);
        const x = w.x + Math.cos(st.a) * w.cm * st.r * 0.9, y = w.y + Math.sin(st.a) * w.cm * st.r * 0.7;
        c.save(); c.translate(x, y); c.rotate(st.a + i);
        c.fillStyle = `rgb(${Math.round(lerp(244, 160, soak))},${Math.round(lerp(242, 30, soak))},${Math.round(lerp(236, 36, soak))})`;
        c.beginPath(); c.ellipse(0, 0, w.cm * (0.95 + 0.18 * (i % 3)), w.cm * 0.55, 0, 0, TAU); c.fill();
        c.strokeStyle = 'rgba(120,110,95,.35)'; c.lineWidth = 1; c.beginPath(); c.ellipse(0, 0, w.cm * 0.6, w.cm * 0.28, 0, 0, TAU); c.stroke();
        c.restore();
      });
    },

    drawDefault(c, w) {
      FX.drawStains(c, w);
      drawWound(c, w, this.d, this.G.b, this.G.t);
      FX.drawParts(c, w);
    },

    statusTick(dt) {
      this.G.statusT = (this.G.statusT || 0) - dt;
      if (this.G.statusT > 0) return;
      this.G.statusT = 0.1;
      if (this.ph && this.ph.panel) this.ph.panel();
      if (this.ph && this.ph.device) { this.ph.device(); this.devTones(); }
    },

    /* ─────────────── top-left context card ───────────────
       corner bracket · avatar status ring · holographic body glyph with the wound diamond ·
       instrument list (type / site / flow / grade) · four vital rings · glowing-bar note */
    renderCard() {
      const d = this.d, inj = d.injury, pt = d.patient || {};
      const sev = inj ? (inj.severity || 0) : 0;
      const sevTone = sev >= 3 ? 'red' : sev === 2 ? 'amber' : 'teal';
      const region = inj ? inj.region : (this.mode === 'collar' ? 'neck' : d.region);
      const states = {};
      if (region) states[region] = this.mode === 'collar' ? 'amber' : sevTone;
      const rows = inj
        ? [
          [T('c_type', 'Wound'), esc(inj.typeLabel || ''), ''],
          [T('c_site', 'Site'), esc(inj.regionLabel || ''), ''],
          [T('c_flow', 'Flow'), `${(inj.bleed || 0).toFixed(1)}<small>mL/min</small>`, (inj.bleed || 0) > 20 ? 'red' : (inj.bleed || 0) > 3 ? 'amber' : 'teal'],
          [T('c_sev', 'Severity'), esc(inj.sevLabel || ''), sevTone],
        ]
        : [
          [T('c_site', 'Site'), esc(d.regionLabel || ''), ''],
          [T('c_reason', 'Reason'), esc(this.mode === 'collar' ? (d.spinal ? T('spinal_short', 'Spinal pain') : T('precaution_short', 'Mechanism')) : T('no_bleed_short', 'Precaution')), d.spinal ? 'amber' : ''],
        ];
      this.card.innerHTML = `
        <div class="tc-hd">
          <span class="tc-av ${this.mode === 'collar' ? 'teal' : sevTone}"><svg viewBox="0 0 44 44"><circle class="b" cx="22" cy="22" r="19"/><circle class="f" cx="22" cy="22" r="19"/></svg><b>${esc(initialsOf(pt.name || T('patient', 'Patient')))}</b></span>
          <div class="tc-who"><span class="k">${esc(this.title())}</span><b>${esc(pt.name || T('patient', 'Patient'))}</b></div>
          ${inj ? `<span class="tc-sev ${sevTone}"><i></i>${esc(inj.sevLabel || '')}</span>` : ''}
        </div>
        <div class="tc-body">
          <div class="tc-map">${bodyGlyph(states, region)}</div>
          <div class="tc-list">${rows.map(([k, v, t]) => `<div class="tc-row" data-t="${t}"><span>${esc(k)}</span><b>${v}</b></div>`).join('')}</div>
        </div>
        <div class="tc-vit"></div>
        <div class="tc-tip ${this.tipTone || ''}">${rich(this.tipText || '')}</div>`;
      this.renderVitals();
    },
    renderVitals() {
      const box = this.card.querySelector('.tc-vit'); if (!box) return;
      const v = this.vit || {};
      const hr = v.hr ? Math.round(v.hr) : 0, sys = v.sys ? Math.round(v.sys) : 0, sp = v.spo2 ? Math.round(v.spo2) : 0, rr = v.rr ? Math.round(v.rr) : 0;
      box.innerHTML = [
        vring({ value: hr || '--', frac: hr / 180, tone: !hr ? '' : hr > 130 || hr < 45 ? 'red' : hr > 110 ? 'amber' : 'green', label: 'HR', beat: hr ? 60 / clamp(hr, 30, 200) : 0 }),
        vring({ value: sys || '--', frac: sys / 180, tone: !sys ? '' : sys < 90 ? 'red' : sys < 100 ? 'amber' : 'white', label: 'SYS' }),
        vring({ value: sp || '--', frac: (sp - 70) / 30, tone: !sp ? '' : sp < 90 ? 'red' : sp < 94 ? 'amber' : 'cyan', label: 'SpO₂' }),
        vring({ value: rr || '--', frac: rr / 40, tone: !rr ? '' : rr < 8 || rr > 28 ? 'red' : rr > 22 || rr < 10 ? 'amber' : 'yellow', label: 'RR' }),
      ].join('');
    },
    setTip(text, tone) { this.tipText = text; this.tipTone = tone || ''; const t = this.card.querySelector('.tc-tip'); if (t) { t.className = `tc-tip ${this.tipTone}`; t.innerHTML = rich(text); } },
    title() { return this.mode === 'tq' ? T('title_tq', 'Tourniquet') : this.mode === 'collar' ? T('title_collar', 'Cervical collar') : T('title_bleed', 'Bleed control'); },

    /* ─────────────── device shell ─────────────── */
    // generic device labelling: model code, type name, warning sticker, serial (no brand on device faces)
    devBrand(code, name, warn) {
      const q = s => this.dev.querySelector(s);
      q('.hx-code').textContent = code;
      q('.hx-name').textContent = name;
      q('.hx-wt').textContent = warn || T('dev_warn_single', 'Single patient use');
      q('.hx-sn').textContent = `SN ${String(hash(code) % 9000 + 1000)}-${String(hash(name) % 9000 + 1000)}`;
      this.dev.dataset.model = code;
    },
    devLed(tone) {
      this.dev.querySelector('.dev-led').className = `dev-led ${tone || ''}`;
      const st = this.dev.querySelector('.hx-st');
      st.textContent = tone === 'red' ? T('dev_alarm', 'ALARM') : tone === 'off' ? T('dev_stby', 'STBY') : T('dev_run', 'RUN');
      st.className = `hx-st ${tone || ''}`;
    },
    // mirror each instrument row's value tone onto the row (tone notch on the left)
    devTones() {
      this.devScreen.querySelectorAll('.row').forEach(r => {
        const b = r.querySelector('b'); if (!b) return;
        const t = /\bred\b/.test(b.className) ? 'red' : /\bamber\b/.test(b.className) ? 'amber' : /\bteal\b/.test(b.className) ? 'teal' : '';
        if (r.dataset.t !== t) r.dataset.t = t;
      });
    },

    /* ═════════════════════════════ STOP BLEEDING ═════════════════════════════ */
    initBleed() {
      const d = this.d, G = this.G;
      this.steps = d.steps || ['pressure', 'wrap'];
      this.tune = Object.assign({ pressureTarget: 0.3, pressureHold: 2.5, packStrips: 4, wrapTurns: 4, tensionBand: [0.38, 0.72] }, d.tune || {});
      G.b = d.underTq ? 0.12 : 1;
      G.maxB = G.b;
      G.strips = [];
      this.devBrand('HM-2', T('dev_hm', 'Haemostat monitor'), T('dev_warn_hm', 'Check circulation below'));
      this.devScreen.innerHTML = `
        <div class="scr-h"><span class="md">${esc(T('dev_flow', 'Wound flow'))}</span><span class="st">LIVE</span></div>
        <div class="big"><span class="fv"></span><small>mL/min</small><span class="tr-arrow"></span></div>
        <div class="trw"><canvas class="trace"></canvas><span class="ax">0</span></div>
        <div class="rows">
          <div class="row"><span>${esc(T('dev_lost', 'Lost during care'))}</span><b class="lost">0 mL</b></div>
          <div class="row"><span>${esc(T('dev_hr', 'Heart rate'))}</span><b class="hr teal">--</b></div>
          <div class="row"><span class="sx-l">${esc(T('dev_pressure', 'Pressure'))}</span><b class="sx">--</b></div>
        </div>
        <div class="gauge"><div class="gl"><span class="g-l"></span><b class="g-v"></b></div><div class="g-m"></div></div>`;
      this.trace = { cv: this.devScreen.querySelector('.trace'), hist: [] };
      this.flowOdo = NZA.ui.FlipClock(this.devScreen.querySelector('.fv'), { value: '0.0' });
      if (d.underTq) this.setTip(T('tip_under_tq', 'A tourniquet is holding this bleed. Pack and dress it now so it can come off later.'), 'amber');
      else if (d.deep) this.setTip(T('tip_deep', '**Deep wound.** Pressure alone will not hold it: pack it with gauze, then dress it.'), 'red');
      else this.setTip(T('tip_shallow', 'Firm, direct pressure first. Then cover it so it stays controlled.'));
      this.stepIdx = -1;
      this.nextStep();
    },

    nextStep() {
      this.stepIdx += 1;
      const name = this.steps[this.stepIdx];
      if (!name) return this.finishBleed();
      const make = { pressure: () => this.phPressure(), pack: () => this.phPack(), wrap: () => this.phWrap(), dressing: () => this.phDressing() }[name];
      this.ph = make();
      this.ph.name = name;
      this.ph.t0 = this.G.t;
      const names = { pressure: T('sn_pressure', 'Press on the wound'), pack: T('sn_pack', 'Pack the wound'), wrap: T('sn_wrap', 'Wrap the limb'), dressing: T('sn_dressing', 'Seal a dressing') };
      this.pp.set(Object.assign({ step: this.stepIdx + 1, total: this.steps.length, tag: `${T('tag_bleed', 'Bleed control')} · ${(this.d.injury && this.d.injury.regionLabel) || ''}`.replace(/ · $/, ''), steps: this.steps.map(s => names[s] || s) }, this.ph.panelInit()));
      this.updateTools();
    },

    updateTools() {
      const icons = { pressure: 'gauze', pack: 'gauze-roll', wrap: 'bandage', dressing: 'dressing-pad' };
      const names = { pressure: T('tool_pad', 'Gauze pad'), pack: T('tool_roll', 'Gauze roll'), wrap: T('tool_bandage', 'Bandage'), dressing: T('tool_dressing', 'Pressure dressing') };
      this.pp.set({ tools: this.steps.map((s, i) => ({ key: String(i + 1), label: names[s], icon: icons[s], state: i < this.stepIdx ? 'done' : i === this.stepIdx ? 'active' : 'locked' })) });
    },

    stepDone(score, flash) {
      const name = this.ph && this.ph.name;
      if (!name || this.ph.finished) return;
      this.ph.finished = true;
      this.G.steps[name] = Math.round(clamp(score, 0, 100));
      NZA.audio.success();
      if (flash) this.pp.flash('ok', flash, 1800);
      setTimeout(() => { if (this.G && this.ph && this.ph.name === name) this.nextStep(); }, 650);
    },

    bleedStats(extra) {
      const G = this.G, inj = this.d.injury || {};
      const flow = (inj.bleed || 0) * G.b;
      return [
        { id: 'bleed', label: T('st_bleed', 'Bleed'), value: flow.toFixed(1), unit: 'mL/min', tone: flow > 20 ? 'red' : flow > 3 ? 'amber' : 'teal' },
        { id: 'lost', label: T('st_lost', 'Lost'), value: String(Math.round(G.lost)), unit: 'mL' },
      ].concat(extra || []);
    },

    devBleed(gLabel, gValue, meter, sxLabel, sxValue, sxTone) {
      const G = this.G, inj = this.d.injury || {};
      const flow = (inj.bleed || 0) * G.b * (G.cover ? 0.15 : 1);
      const s = this.devScreen;
      const fv = s.querySelector('.fv'); if (!fv || !this.flowOdo) return;
      this.flowOdo.set(flow.toFixed(1));
      const big = s.querySelector('.big'); big.className = `big ${flow < 1 ? 'teal' : flow < 8 ? 'amber' : ''}`;
      const prev = this.trace.prevFlow === undefined ? flow : this.trace.prevFlow;
      s.querySelector('.tr-arrow').className = `tr-arrow ${flow < prev - 0.05 ? 'dn' : flow > prev + 0.05 ? 'up' : ''}`;
      this.trace.prevFlow = lerp(prev, flow, 0.3);
      s.querySelector('.lost').textContent = `${Math.round(G.lost)} mL`;
      s.querySelector('.hr').textContent = `${Math.round(G.hr || 0)} bpm`;
      s.querySelector('.sx-l').textContent = sxLabel || T('dev_pressure', 'Pressure');
      const sx = s.querySelector('.sx'); sx.textContent = sxValue === undefined ? '--' : sxValue; sx.className = `sx ${sxTone || ''}`;
      s.querySelector('.g-l').textContent = gLabel || '';
      s.querySelector('.g-v').textContent = gValue || '';
      s.querySelector('.g-m').innerHTML = meter ? NZA.ui.meterHTML(meter) : '';
      this.devLed(flow < 1 ? '' : 'red');
      s.querySelector('.scr-h .st').className = `st ${flow < 1 ? '' : flow < 8 ? 'amber' : 'red'}`;
      s.querySelector('.scr-h .st').textContent = flow < 1 ? T('dev_held', 'Held') : T('dev_live', 'Bleeding');
    },

    drawTrace() {
      const tr = this.trace; if (!tr || !tr.cv) return;
      const fit = NZA.fitCanvas(tr.cv); const c = tr.cv.getContext('2d'); const W = fit.w, H = fit.h, k = fit.scale;
      const G = this.G, inj = this.d.injury || {};
      const amp = clamp(G.b * (G.cover ? 0.15 : 1), 0, 1);
      const beat = G.beat || 0;
      const v = inj.arterial ? amp * (0.35 + 0.65 * beat * beat) : amp * (0.55 + 0.08 * Math.sin(G.t * 9));
      const N = 200;
      if (!tr.hist.length) for (let i = 0; i < N; i++) tr.hist.push(null);
      tr.hist.push(v); while (tr.hist.length > N) tr.hist.shift();
      c.clearRect(0, 0, W, H);
      // grid: fine minor lines, brighter major lines
      c.lineWidth = 1;
      for (let i = 1; i < 8; i++) { c.strokeStyle = i % 2 ? 'rgba(255,255,255,.025)' : 'rgba(255,255,255,.06)'; c.beginPath(); c.moveTo(0, Math.round((H * i) / 8) + 0.5); c.lineTo(W, Math.round((H * i) / 8) + 0.5); c.stroke(); }
      for (let i = 1; i < 12; i++) { c.strokeStyle = i % 3 ? 'rgba(255,255,255,.02)' : 'rgba(255,255,255,.05)'; c.beginPath(); c.moveTo(Math.round((W * i) / 12) + 0.5, 0); c.lineTo(Math.round((W * i) / 12) + 0.5, H); c.stroke(); }
      const col = amp < 0.05 ? [15, 212, 196] : amp < 0.35 ? [243, 195, 90] : [255, 90, 96];
      const rgb = a => `rgba(${col[0]},${col[1]},${col[2]},${a})`;
      const pts = [];
      tr.hist.forEach((y, i) => { if (y === null) return; pts.push([(i / (N - 1)) * W, H - 5 * k - y * (H - 12 * k)]); });
      if (pts.length > 1) {
        const fill = c.createLinearGradient(0, 0, 0, H); fill.addColorStop(0, rgb(0.28)); fill.addColorStop(1, rgb(0));
        c.fillStyle = fill; c.beginPath(); c.moveTo(pts[0][0], H); pts.forEach(([x, y]) => c.lineTo(x, y)); c.lineTo(pts[pts.length - 1][0], H); c.closePath(); c.fill();
        c.strokeStyle = rgb(1); c.lineWidth = 2 * k; c.lineJoin = 'round'; c.shadowColor = rgb(0.9); c.shadowBlur = 7 * k;
        c.beginPath(); pts.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); c.stroke(); c.shadowBlur = 0;
        const [hx, hy] = pts[pts.length - 1];
        c.fillStyle = '#fff'; c.beginPath(); c.arc(hx - 2 * k, hy, 2.6 * k, 0, TAU); c.fill();
        c.fillStyle = rgb(0.35); c.beginPath(); c.arc(hx - 2 * k, hy, 6 * k, 0, TAU); c.fill();
      }
    },

    /* ── 1. direct pressure ── */
    phPressure() {
      const a = this, G = this.G, tune = this.tune, deep = !!this.d.deep;
      const floor = deep ? 0.2 : 0.04;
      const ph = {
        onT: 0, pressT: 0, holdT: 0, soak: 0, wander: { x: 0, y: 0, vx: 0, vy: 0 },
        panelInit() {
          return {
            title: T('ph_pressure', 'Apply direct pressure'),
            text: T('ph_pressure_t', 'Put the gauze pad on the wound and **hold the mouse button** to press. Keep the pad on the wound as the patient moves. Let go and it bleeds again.'),
            hints: [{ keys: [T('k_lmb', 'Hold LMB')], label: T('h_press', 'press') }, { keys: [T('k_move', 'Move')], label: T('h_follow', 'follow the wound') }],
          };
        },
        onTarget(w) { return G.ptr && dist(G.ptr, w) <= w.tr; },
        update(dt, w) {
          // the patient shifts: the wound wanders a little
          const wd = this.wander;
          wd.vx += (Math.random() - 0.5) * 140 * w.U * dt - wd.x * 1.4 * dt; wd.vy += (Math.random() - 0.5) * 140 * w.U * dt - wd.y * 1.4 * dt;
          wd.vx *= 0.96; wd.vy *= 0.96; wd.x += wd.vx * dt; wd.y += wd.vy * dt;
          const lim = w.cm * 2.4; wd.x = clamp(wd.x, -lim, lim); wd.y = clamp(wd.y, -lim, lim);
          G.drift = { x: wd.x, y: wd.y };
          const on = G.down && this.onTarget(w);
          if (G.down) { this.pressT += dt; if (on) this.onT += dt; }
          if (on) G.b = Math.max(floor, G.b - (deep ? 0.22 : 0.34) * dt);
          else G.b = Math.min(G.maxB, G.b + (G.down ? 0.1 : 0.2) * dt * G.maxB);
          G.cover = false;
          this.soak = Math.min(1, this.soak + (on ? 0.05 : 0.02) * dt * (1 + G.b));
          if (G.b <= tune.pressureTarget && on) this.holdT += dt; else this.holdT = Math.max(0, this.holdT - dt * 2);
          if (this.holdT >= tune.pressureHold && !this.finished) {
            const total = G.t - this.t0;
            const acc = this.pressT > 0 ? this.onT / this.pressT : 0;
            const speed = clamp(1 - (total - 5) / 14, 0, 1);
            a.stepDone(100 * (0.62 * acc + 0.38 * speed), T('ok_pressure', 'Bleeding slowed under pressure.'));
          }
          a.cv.classList.toggle('nocur', !!G.ptr);
        },
        draw(c, w) {
          FX.drawStains(c, w);
          drawWound(c, w, a.d, G.b, G.t);
          FX.drawParts(c, w);
          const on = this.onTarget(w);
          if (!G.down || !on) {
            const pulse = 1 + 0.08 * Math.sin(G.t * 6);
            ring(c, w.x, w.y, w.tr * pulse, on ? C.tealHi : 'rgba(229,72,77,.85)', 2 * w.U, [6 * w.U, 5 * w.U]);
          }
          if (G.ptr) {
            const s = w.cm * 8.5;
            drawPad(c, G.ptr.x, G.ptr.y, s, w.ang * 0.2 + 0.12, this.soak, G.down);
            drawGlove(c, G.ptr.x + s * 0.04, G.ptr.y + s * 0.12, s * 1.0, w.ang - Math.PI / 2, G.down);
          }
          if (!G.ptr || dist(G.ptr, w) > w.tr * 2.5) label(c, w.x, w.y - w.tr - 26 * w.U, T('lbl_press', 'Press here'), 'red', w.U);
        },
        panel() {
          const hold = this.holdT / tune.pressureHold;
          a.pp.set({
            stats: a.bleedStats([{ id: 'hold', label: T('st_hold', 'Held'), value: (Math.min(this.holdT, tune.pressureHold)).toFixed(1), unit: 's' }]),
            wide: { label: T('w_bleed', 'Bleeding'), value: `${Math.round(G.b * 100)}`, unit: '%', tone: G.b > 0.6 ? 'red' : '', meter: { value: G.b, zone: [0, tune.pressureTarget], tone: G.b > tune.pressureTarget ? 'red' : '' }, caption: hold > 0 ? T('cap_hold', 'Keep it there…') : (G.down ? T('cap_pressing', 'Pressing') : T('cap_release', 'Not pressing: bleeding')), captionTone: hold > 0 ? 'teal' : (G.down ? '' : 'red') },
          });
        },
        device() {
          const on = G.down && G.w && this.onTarget(G.w);
          a.devBleed(T('g_hold', 'Pressure hold'), `${Math.min(this.holdT, tune.pressureHold).toFixed(1)} / ${tune.pressureHold}s`, { value: clamp(this.holdT / tune.pressureHold, 0, 1) },
            T('dev_pressure', 'Pressure'), on ? T('firm', 'Firm') : G.down ? T('off_wound', 'Off wound') : T('none', 'None'), on ? 'teal' : G.down ? 'amber' : 'red');
        },
      };
      return ph;
    },

    /* ── 2. pack the wound ── */
    phPack() {
      const a = this, G = this.G, tune = this.tune;
      const ph = {
        packed: 0, strips: G.strips, waste: 0, accs: [], drag: null, holdT: 0, phase: 'feed',
        panelInit() {
          return {
            title: T('ph_pack', 'Pack the wound'),
            text: T('ph_pack_t', '**Drag gauze from the roll** deep into the wound, again and again, until it is packed tight. Drops outside the wound are wasted.'),
            hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_feed', 'roll → wound') }],
          };
        },
        rollPos(w) { const side = w.n ? w.n : { x: 1, y: 0 }; const off = (w.limbW * 0.78 + 46 * w.U); const p = add({ x: w.x, y: w.y }, mul(side, off)); return { x: clamp(p.x, 60 * w.U, G.W - 60 * w.U), y: clamp(p.y, 60 * w.U, G.H - 320 * w.U) }; },
        down(p) {
          const w = G.w; if (!w) return;
          if (this.phase === 'feed' && dist(p, this.rollPos(w)) < Math.max(w.cm * 4, 40 * w.U)) { this.drag = { path: [this.rollPos(w), p] }; NZA.audio.click(520); }
        },
        move(p) { if (this.drag) { const last = this.drag.path[this.drag.path.length - 1]; if (dist(last, p) > 6) this.drag.path.push(p); if (this.drag.path.length > 80) this.drag.path.splice(1, 1); } },
        up(p) {
          const w = G.w; if (!this.drag || !w) return;
          this.drag = null;
          const dd = dist(p, w), lim = w.tr * 0.9;
          if (dd <= lim) {
            const acc = clamp(1 - dd / lim, 0, 1);
            const gain = (0.5 + 0.5 * acc) / tune.packStrips;
            this.packed = Math.min(1, this.packed + gain);
            this.accs.push(acc);
            this.strips.push({ a: Math.random() * TAU, r: 0.25 + Math.random() * 0.5, born: G.t });
            G.b = Math.max(0.12, G.b - 0.14 * (0.5 + acc));
            NZA.audio.click(acc > 0.6 ? 760 : 600);
            if (acc < 0.35) a.pp.flash('warn', T('pack_edge', 'Too close to the edge: push it into the deepest part.'), 1600);
            if (this.packed >= 1) { this.phase = 'hold'; a.pp.set({ title: T('ph_pack_hold', 'Hold pressure on the packing'), text: T('ph_pack_hold_t', 'Packed tight. **Hold the mouse button** on the wound to press the packing down until the bleeding stops.') }); a.pp.flash('ok', T('ok_packed', 'Wound packed.'), 1500); }
          } else {
            this.waste += 1;
            NZA.audio.fail();
            a.pp.flash('bad', T('pack_miss', 'Missed the wound. That gauze is contaminated.'), 1600);
          }
        },
        update(dt, w) {
          G.drift = G.drift ? mul(G.drift, Math.pow(0.1, dt)) : { x: 0, y: 0 };
          if (this.phase === 'feed') { G.b = Math.min(G.maxB, G.b + 0.05 * dt); G.cover = false; a.cv.className = `tr-stage int ${this.drag ? 'grabbing' : 'grab'}`; return; }
          a.cv.className = 'tr-stage int nocur';
          const on = G.down && G.ptr && dist(G.ptr, w) <= w.tr;
          if (on) G.b = Math.max(0.04, G.b - 0.32 * dt); else G.b = Math.min(0.5, G.b + 0.06 * dt);
          if (on && G.b <= 0.16) this.holdT += dt; else this.holdT = Math.max(0, this.holdT - dt);
          if (this.holdT >= 1.6 && !this.finished) {
            const acc = this.accs.length ? this.accs.reduce((s, x) => s + x, 0) / this.accs.length : 0.5;
            const total = G.t - this.t0;
            const sc = 100 * (0.7 * (0.35 + 0.65 * acc) + 0.3 * clamp(1 - (total - 9) / 20, 0, 1)) - this.waste * 9;
            a.stepDone(sc, T('ok_pack', 'Packing holds.'));
          }
        },
        draw(c, w) {
          FX.drawStains(c, w);
          drawWound(c, w, a.d, G.b, G.t);
          a.drawPacking(c, w);
          FX.drawParts(c, w);
          const lim = w.tr * 0.9;
          if (this.phase === 'feed') {
            const rp = this.rollPos(w);
            drawRoll(c, rp.x, rp.y, w.cm * 3.2, -0.3, !this.drag);
            ring(c, w.x, w.y, lim, this.drag ? C.tealHi : 'rgba(229,72,77,.8)', 2 * w.U, [5 * w.U, 5 * w.U]);
            if (!this.drag) label(c, rp.x, rp.y + w.cm * 4.6 + 16 * w.U, T('lbl_drag_gauze', 'Drag gauze'), 'teal', w.U);
            if (this.drag) {
              const pts = this.drag.path;
              c.save(); c.lineCap = 'round'; c.lineJoin = 'round';
              c.strokeStyle = 'rgba(0,0,0,.25)'; c.lineWidth = w.cm * 1.8; c.beginPath(); pts.forEach((p, i) => (i ? c.lineTo(p.x + 3, p.y + 5) : c.moveTo(p.x + 3, p.y + 5))); c.stroke();
              c.strokeStyle = '#f5f3ec'; c.lineWidth = w.cm * 1.6; c.beginPath(); pts.forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y))); c.stroke();
              c.strokeStyle = 'rgba(160,150,130,.5)'; c.lineWidth = 1.5; c.setLineDash([4, 4]); c.beginPath(); pts.forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y))); c.stroke();
              c.restore();
            }
          } else {
            if (G.ptr) drawGlove(c, G.ptr.x, G.ptr.y, w.cm * 9, w.ang - Math.PI / 2, G.down);
            if (!G.down) ring(c, w.x, w.y, w.tr, 'rgba(229,72,77,.85)', 2 * w.U, [6 * w.U, 5 * w.U]);
          }
        },
        panel() {
          const extra = this.phase === 'feed'
            ? [{ id: 'packed', label: T('st_packed', 'Packed'), value: String(Math.round(this.packed * 100)), unit: '%' }, { id: 'waste', label: T('st_waste', 'Wasted'), value: String(this.waste), tone: this.waste ? 'amber' : '' }]
            : [{ id: 'hold', label: T('st_hold', 'Held'), value: Math.min(this.holdT, 1.6).toFixed(1), unit: 's' }];
          a.pp.set({
            stats: a.bleedStats(extra),
            wide: this.phase === 'feed'
              ? { label: T('w_packed', 'Wound packed'), value: `${Math.round(this.packed * 100)}`, unit: '%', meter: { value: this.packed, segs: true }, caption: T('cap_pack', 'Every feed that lands deep fills it faster'), captionTone: 'teal' }
              : { label: T('w_bleed', 'Bleeding'), value: `${Math.round(G.b * 100)}`, unit: '%', meter: { value: G.b, zone: [0, 0.16], tone: G.b > 0.16 ? 'red' : '' }, caption: G.down ? T('cap_hold', 'Keep it there…') : T('cap_release', 'Not pressing: bleeding'), captionTone: G.down ? 'teal' : 'red' },
          });
        },
        device() { a.devBleed(T('g_packed', 'Packing'), `${Math.round(this.packed * 100)}%`, { value: this.packed, segs: true }, T('dev_strips', 'Gauze feeds'), String(this.strips.length), 'teal'); },
      };
      return ph;
    },

    /* ── 3a. wrap a limb ── */
    phWrap() {
      const a = this, G = this.G, tune = this.tune;
      const band = tune.tensionBand || [0.38, 0.72];
      const ph = {
        turns: [], acc: 0, lastAng: null, samples: [], omega: 0, tension: 0, phase: 'wrap', dir: 0, quiet: 0,
        panelInit() {
          return {
            title: T('ph_wrap', 'Wrap the limb'),
            text: T('ph_wrap_t', '**Circle the mouse around the wound** to roll the bandage around the limb. Keep a steady pace: even tension, %s turns.', tune.wrapTurns),
            hints: [{ keys: [T('k_circle', 'Circle')], label: T('h_wrap', 'wrap') }, { keys: [keyLabel(KEY.lock)], label: T('h_secure', 'secure the end') }],
          };
        },
        key(e) {
          if ((e.code === KEY.lock || e.code === KEY.confirm) && this.phase === 'secure') { this.secure(); return true; }
          return false;
        },
        down(p) { if (this.phase === 'secure' && G.w && dist(p, this.clipPos(G.w)) < 34 * G.U) this.secure(); },
        clipPos(w) { const n = this.turns.length; const off = (n - 1) / 2 * w.cm * 7 * 0.55; return add(add({ x: w.x, y: w.y }, mul(w.axis, off)), mul(w.n, w.limbW * 0.62)); },
        secure() {
          if (this.finished) return;
          const q = this.turns.length ? this.turns.reduce((s, t) => s + t.q, 0) / this.turns.length : 0.5;
          const tight = this.turns.filter(t => t.kind === 'tight').length;
          G.cover = true;
          a.stepDone(100 * q - tight * 6, T('ok_wrap', 'Bandage secured. Check the fingers / toes stay pink.'));
        },
        update(dt, w) {
          G.drift = G.drift ? mul(G.drift, Math.pow(0.1, dt)) : { x: 0, y: 0 };
          a.cv.className = 'tr-stage int nocur';
          if (this.phase !== 'wrap' || !G.ptr) return;
          const dd = dist(G.ptr, w);
          const ang = Math.atan2(G.ptr.y - w.y, G.ptr.x - w.x);
          if (dd < w.cm * 1.2 || dd > w.limbW * 2.6) { this.lastAng = null; this.omega *= 0.9; this.quiet += dt; return; }
          if (this.lastAng !== null) {
            const da = angDiff(ang, this.lastAng);
            if (!this.dir && Math.abs(da) > 0.02) this.dir = Math.sign(da);
            const fwd = da * (this.dir || 1);
            const inst = Math.abs(da) / Math.max(dt, 1e-3);
            this.omega = lerp(this.omega, fwd > 0 ? inst : 0, 0.12);
            if (fwd > 0) {
              this.acc += fwd;
              this.tension = clamp(this.omega / 10.5, 0, 1);
              this.samples.push(this.tension);
              this.quiet = 0;
            } else if (fwd < -0.05) { this.quiet += dt; }
          }
          this.lastAng = ang;
          if (this.acc >= TAU) {
            this.acc -= TAU;
            const s = this.samples; this.samples = [];
            const mean = s.length ? s.reduce((x, y) => x + y, 0) / s.length : 0.5;
            const inBand = s.length ? s.filter(x => x >= band[0] && x <= band[1]).length / s.length : 0.5;
            const kind = mean > band[1] ? 'tight' : mean < band[0] ? 'loose' : 'even';
            const q = clamp(inBand * 0.75 + (kind === 'even' ? 0.25 : 0.05), 0, 1);
            this.turns.push({ q, kind });
            G.b = Math.max(0.06, G.b * (kind === 'loose' ? 0.86 : 0.7));
            NZA.audio.click(kind === 'even' ? 700 : 480);
            if (kind === 'tight') a.pp.flash('warn', T('wrap_tight', 'Too tight: you are cutting off the circulation. Slow down.'), 1700);
            else if (kind === 'loose') a.pp.flash('warn', T('wrap_loose', 'Too loose: it will slip. A little faster and firmer.'), 1700);
            if (this.turns.length >= tune.wrapTurns) {
              this.phase = 'secure';
              a.pp.set({ title: T('ph_secure', 'Secure the end'), text: T('ph_secure_t', 'Tuck the end in and fix it with the clip: press {%s} or click the clip.', keyLabel(KEY.lock)) });
            }
          }
        },
        draw(c, w) {
          FX.drawStains(c, w);
          drawWound(c, w, a.d, G.b, G.t);
          a.drawPacking(c, w);
          FX.drawParts(c, w);
          const bw = w.cm * 7, across = w.limbW * 1.12;
          this.turns.forEach((t, i) => {
            const off = (i - (this.turns.length - 1) / 2) * bw * 0.55;
            drawBand(c, add({ x: w.x, y: w.y }, mul(w.axis, off)), w.axis, across, bw, i === this.turns.length - 1 ? G.b * 0.8 : 0, i);
          });
          if (this.phase === 'wrap') {
            const R = w.limbW * 0.95;
            ringDash(c, w.x, w.y, R, 'rgba(255,255,255,.28)', 2 * w.U, [5 * w.U, 7 * w.U]);
            const frac = this.acc / TAU;
            const tone = this.tension > band[1] ? C.red : this.tension < band[0] ? C.amber : C.tealHi;
            c.save(); c.strokeStyle = tone; c.lineWidth = 5 * w.U; c.lineCap = 'round'; c.shadowColor = tone; c.shadowBlur = 10 * w.U;
            const start = this.startAng === undefined ? (this.startAng = -Math.PI / 2) : this.startAng;
            c.beginPath(); c.arc(w.x, w.y, R, start, start + frac * TAU * (this.dir || 1), (this.dir || 1) < 0); c.stroke(); c.restore();
            // arrows showing the direction
            for (let i = 0; i < 3; i++) {
              const aa = G.t * 1.2 + (i * TAU) / 3, px = w.x + Math.cos(aa) * R, py = w.y + Math.sin(aa) * R;
              c.save(); c.translate(px, py); c.rotate(aa + Math.PI / 2); c.fillStyle = 'rgba(255,255,255,.4)';
              c.beginPath(); c.moveTo(6 * w.U, 0); c.lineTo(-4 * w.U, -5 * w.U); c.lineTo(-4 * w.U, 5 * w.U); c.fill(); c.restore();
            }
            if (G.ptr) {
              const ang = Math.atan2(G.ptr.y - w.y, G.ptr.x - w.x);
              drawRoll(c, G.ptr.x, G.ptr.y, w.cm * 2.6, ang + Math.PI / 2, false);
              c.strokeStyle = 'rgba(245,243,236,.85)'; c.lineWidth = w.cm * 1.1; c.lineCap = 'round';
              c.beginPath(); c.moveTo(G.ptr.x, G.ptr.y); c.lineTo(w.x + Math.cos(ang) * w.limbW * 0.45, w.y + Math.sin(ang) * w.limbW * 0.45); c.stroke();
            }
          } else if (this.phase === 'secure') {
            const cp = this.clipPos(w);
            c.save(); c.translate(cp.x, cp.y); c.rotate(w.ang);
            c.fillStyle = '#c9cdd1'; c.strokeStyle = '#7d8388'; c.lineWidth = 1.5;
            roundRect(c, -12 * w.U, -7 * w.U, 24 * w.U, 14 * w.U, 3 * w.U); c.fill(); c.stroke();
            c.restore();
            ring(c, cp.x, cp.y, 22 * w.U * (1 + 0.1 * Math.sin(G.t * 6)), C.tealHi, 2 * w.U, [5 * w.U, 4 * w.U]);
            label(c, cp.x, cp.y - 40 * w.U, T('lbl_clip', 'Clip it'), 'teal', w.U);
            if (G.ptr) { c.fillStyle = '#fff'; c.beginPath(); c.arc(G.ptr.x, G.ptr.y, 4 * w.U, 0, TAU); c.fill(); }
          }
        },
        panel() {
          const tn = this.tension;
          a.pp.set({
            stats: a.bleedStats([{ id: 'turns', label: T('st_turns', 'Turns'), value: `${this.turns.length}/${tune.wrapTurns}` }]),
            wide: { label: T('w_tension', 'Tension'), value: this.omega < 0.4 ? '--' : tn > band[1] ? T('tight', 'Tight') : tn < band[0] ? T('loose', 'Loose') : T('even', 'Even'), tone: tn > band[1] ? 'red' : '', meter: { value: tn, zone: band, mark: tn, noFill: true }, caption: T('cap_wrap', 'Each turn overlaps the last by half'), captionTone: '' },
          });
        },
        device() { const tn = this.tension; a.devBleed(T('g_tension', 'Wrap tension'), this.omega < 0.4 ? '--' : tn > band[1] ? T('tight', 'Tight') : tn < band[0] ? T('loose', 'Loose') : T('even', 'Even'), { value: tn, zone: band, mark: tn, noFill: true }, T('st_turns', 'Turns'), `${this.turns.length}/${tune.wrapTurns}`, 'teal'); },
      };
      return ph;
    },

    /* ── 3b. pressure dressing on the torso ── */
    phDressing() {
      const a = this, G = this.G;
      const ph = {
        phase: 'place', pad: null, drag: false, cov: 0, corners: [], hold: -1, holdT: 0,
        panelInit() {
          return {
            title: T('ph_dressing', 'Apply the pressure dressing'),
            text: T('ph_dressing_t', '**Drag the dressing** over the wound so the pad covers it completely, then **hold each corner** until it sticks.'),
            hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_place', 'place') }, { keys: [T('k_lmb', 'Hold LMB')], label: T('h_seal', 'seal a corner') }],
          };
        },
        size(w) { return { pw: w.cm * 11, ph: w.cm * 9 }; },
        home(w) { const p = add({ x: w.x, y: w.y }, mul(w.n, w.limbW * 0.95 + 40 * w.U)); return { x: clamp(p.x, 120 * w.U, G.W - 420 * w.U), y: clamp(p.y, 120 * w.U, G.H - 400 * w.U) }; },
        cornerPts(w) {
          const { pw, ph: hh } = this.size(w); const ax = w.axis, n = w.n, c0 = this.pad;
          return [[-1, -1], [1, -1], [1, 1], [-1, 1]].map(([u, v]) => add(add(c0, mul(n, (u * pw) / 2 * 0.86)), mul(ax, (v * hh) / 2 * 0.86)));
        },
        down(p) {
          const w = G.w; if (!w) return;
          if (this.phase === 'place') {
            const at = this.pad || this.home(w);
            const { pw } = this.size(w);
            if (dist(p, at) < pw * 0.7) { this.drag = true; this.off = sub(at, p); NZA.audio.click(520); }
          } else if (this.phase === 'seal') {
            const pts = this.cornerPts(w);
            pts.forEach((q, i) => { if (!this.corners[i] && dist(p, q) < Math.max(w.cm * 2, 24 * w.U)) { this.hold = i; this.holdT = 0; } });
          }
        },
        move(p) { if (this.drag) this.pad = add(p, this.off); },
        up() {
          const w = G.w; this.hold = -1;
          if (!this.drag || !w) return;
          this.drag = false;
          const d0 = dist(this.pad, w), { ph: hh } = this.size(w);
          this.cov = clamp(1 - d0 / (hh * 0.55), 0, 1);
          if (this.cov < 0.35) { this.pad = null; NZA.audio.fail(); a.pp.flash('bad', T('dress_miss', 'The pad is not over the wound. Try again.'), 1500); return; }
          this.phase = 'seal'; G.cover = true; G.b = Math.max(0.1, G.b * (1 - 0.4 * this.cov));
          NZA.audio.click(700);
          a.pp.set({ title: T('ph_seal', 'Seal the edges'), text: T('ph_seal_t', '**Hold the mouse button** on each corner until it sticks down. Pressure on the pad keeps the wound closed.') });
        },
        update(dt, w) {
          G.drift = G.drift ? mul(G.drift, Math.pow(0.1, dt)) : { x: 0, y: 0 };
          a.cv.className = `tr-stage int ${this.phase === 'place' ? (this.drag ? 'grabbing' : 'grab') : ''}`;
          if (this.phase === 'place') { G.b = Math.min(G.maxB, G.b + 0.04 * dt); return; }
          // the pad follows the wound once it is on
          if (!this.rel) this.rel = sub(this.pad, w);
          this.pad = add(w, this.rel);
          if (this.hold >= 0 && G.down) {
            const q = this.cornerPts(w)[this.hold];
            if (G.ptr && dist(G.ptr, q) < Math.max(w.cm * 2.4, 28 * w.U)) this.holdT += dt; else this.holdT = 0;
            if (this.holdT >= 0.55) { this.corners[this.hold] = true; this.hold = -1; G.b = Math.max(0.05, G.b * 0.75); NZA.audio.click(820); }
          }
          if (this.corners.filter(Boolean).length === 4 && !this.finished) {
            const total = G.t - this.t0;
            a.stepDone(100 * (0.6 * this.cov + 0.4 * clamp(1 - (total - 6) / 16, 0, 1)), T('ok_dressing', 'Dressing sealed.'));
          }
        },
        draw(c, w) {
          FX.drawStains(c, w);
          drawWound(c, w, a.d, G.b, G.t);
          a.drawPacking(c, w);
          FX.drawParts(c, w);
          const { pw, ph: hh } = this.size(w);
          const at = this.pad || this.home(w);
          if (this.phase === 'place') ring(c, w.x, w.y, hh * 0.55, this.drag ? C.tealHi : 'rgba(229,72,77,.8)', 2 * w.U, [6 * w.U, 5 * w.U]);
          c.save(); c.translate(at.x, at.y); c.rotate(w.ang - Math.PI / 2);
          c.fillStyle = 'rgba(0,0,0,.3)'; roundRect(c, -pw / 2 + 4, -hh / 2 + 7, pw, hh, 8 * w.U); c.fill();
          c.fillStyle = '#f6f5ef'; roundRect(c, -pw / 2, -hh / 2, pw, hh, 8 * w.U); c.fill();
          c.strokeStyle = 'rgba(0,0,0,.08)'; c.lineWidth = 1; roundRect(c, -pw / 2 + 0.5, -hh / 2 + 0.5, pw - 1, hh - 1, 8 * w.U); c.stroke();
          const ip = 0.56;
          c.fillStyle = '#e9e5d8'; roundRect(c, -pw * ip / 2, -hh * ip / 2, pw * ip, hh * ip, 5 * w.U); c.fill();
          gauzeTexture(c, -pw * ip / 2, -hh * ip / 2, pw * ip, hh * ip, 0.8);
          if (this.phase === 'seal') {
            const rg = c.createRadialGradient(0, 0, 0, 0, 0, hh * (0.12 + 0.3 * G.b)); rg.addColorStop(0, `rgba(150,12,20,${0.25 + 0.45 * G.b})`); rg.addColorStop(1, 'rgba(150,12,20,0)');
            c.fillStyle = rg; roundRect(c, -pw * ip / 2, -hh * ip / 2, pw * ip, hh * ip, 5 * w.U); c.fill();
          }
          c.restore();
          if (this.phase === 'seal') {
            this.cornerPts(w).forEach((q, i) => {
              const done = this.corners[i];
              if (done) { c.fillStyle = 'rgba(8,175,162,.9)'; c.beginPath(); c.arc(q.x, q.y, 7 * w.U, 0, TAU); c.fill(); return; }
              const pr = this.hold === i ? this.holdT / 0.55 : 0;
              ring(c, q.x, q.y, 14 * w.U, 'rgba(255,255,255,.8)', 2 * w.U, [4 * w.U, 3 * w.U]);
              if (pr > 0) { c.strokeStyle = C.tealHi; c.lineWidth = 4 * w.U; c.beginPath(); c.arc(q.x, q.y, 14 * w.U, -Math.PI / 2, -Math.PI / 2 + pr * TAU); c.stroke(); }
            });
            if (G.ptr) drawGlove(c, G.ptr.x, G.ptr.y, w.cm * 9, w.ang - Math.PI / 2, G.down);
          } else if (!this.pad) label(c, at.x, at.y + hh * 0.75, T('lbl_drag_dressing', 'Drag the dressing'), 'teal', w.U);
        },
        panel() {
          a.pp.set({
            stats: a.bleedStats([{ id: 'cover', label: T('st_cover', 'Cover'), value: String(Math.round(this.cov * 100)), unit: '%' }, { id: 'edges', label: T('st_edges', 'Edges'), value: `${this.corners.filter(Boolean).length}/4` }]),
            wide: { label: T('w_bleed', 'Bleeding'), value: `${Math.round(G.b * 100)}`, unit: '%', meter: { value: G.b, tone: G.b > 0.4 ? 'red' : '' }, caption: this.phase === 'place' ? T('cap_dress', 'Centre the pad on the wound') : T('cap_seal', 'Seal all four edges'), captionTone: 'teal' },
          });
        },
        device() { a.devBleed(T('g_edges', 'Edges sealed'), `${this.corners.filter(Boolean).length}/4`, { value: this.corners.filter(Boolean).length / 4, segs: true }, T('st_cover', 'Cover'), `${Math.round(this.cov * 100)}%`, 'teal'); },
      };
      return ph;
    },

    finishBleed() {
      const G = this.G;
      const vals = this.steps.map(s => G.steps[s] || 0);
      const score = vals.length ? vals.reduce((x, y) => x + y, 0) / vals.length : 0;
      this.ph = { draw: (c, w) => this.drawFinal(c, w), panel: () => {}, device: () => this.devBleed(T('g_done', 'Done'), '', null, T('dev_pressure', 'Pressure'), '--') };
      G.cover = true;
      this.submit({ score: Math.round(score), steps: Object.assign({}, G.steps), lost: Math.round(G.lost) });
    },

    drawFinal(c, w) {
      FX.drawStains(c, w);
      drawWound(c, w, this.d, this.G.b, this.G.t);
      this.drawPacking(c, w);
      const turns = this.steps.includes('wrap') ? (this.tune.wrapTurns || 4) : 0;
      const bw = w.cm * 7, across = w.limbW * 1.12;
      for (let i = 0; i < turns; i++) drawBand(c, add({ x: w.x, y: w.y }, mul(w.axis, (i - (turns - 1) / 2) * bw * 0.55)), w.axis, across, bw, i === turns - 1 ? 0.15 : 0, i);
      if (this.steps.includes('dressing')) {
        const pw = w.cm * 11, hh = w.cm * 9;
        c.save(); c.translate(w.x, w.y); c.rotate(w.ang - Math.PI / 2); c.fillStyle = '#f6f5ef'; roundRect(c, -pw / 2, -hh / 2, pw, hh, 8 * w.U); c.fill(); c.restore();
      }
    },

    /* ═════════════════════════════ TOURNIQUET ═════════════════════════════ */
    initTq() {
      const d = this.d, G = this.G;
      this.tune = Object.assign({ occlusion: 220, turnGain: 65, overMargin: 110, unwind: 22, clipWindow: 14, jointZone: 0.1, idealAbove: [5, 8], length: 80 }, d.tune || {});
      G.b = 1; G.maxB = 1;
      if (!d.injury) { d.injury = null; G.b = 0; }
      this.tq = { t: 0.93, placed: false, slack: 0, P: 0, theta: 0, locked: false, over: 0, misLocks: 0, misplaced: 0, placeScore: 100, slackScore: 0, twistT0: 0, time: d.time || '' };
      this.devBrand('TQ-1', T('dev_tq', 'Windlass gauge'), T('dev_warn_tq', 'Write the time on the strap'));
      this.devScreen.innerHTML = `
        <div class="scr-h"><span>${esc(T('dev_windlass', 'Windlass'))}</span><span class="st">--</span></div>
        <canvas class="dial"></canvas>
        <div class="rows">
          <div class="row"><span>${esc(T('dev_strap', 'Strap pressure'))}</span><b class="pr">0 mmHg</b></div>
          <div class="row"><span class="led"><span class="dev-led pl"></span>${esc(T('dev_distal', 'Distal pulse'))}</span><b class="dp teal">--</b></div>
          <div class="row"><span>${esc(T('dev_flow', 'Wound flow'))}</span><b class="fl red">--</b></div>
          <div class="row"><span>${esc(T('dev_time', 'Time on'))}</span><b class="tm">--:--</b></div>
        </div>`;
      this.dial = { cv: this.devScreen.querySelector('.dial') };
      this.setTip(T('tip_tq', '**High and tight:** 5–8 cm above the wound, never over a joint. If you are unsure, go high on the upper arm / thigh.'));
      this.stepIdx = -1;
      this.steps = ['place', 'twist', 'lock'];
      this.nextTq();
    },

    nextTq() {
      this.stepIdx += 1;
      const name = this.steps[this.stepIdx];
      if (!name) return this.finishTq();
      this.ph = ({ place: () => this.phPlace(), twist: () => this.phTwist(), lock: () => this.phLock() })[name]();
      this.ph.name = name; this.ph.t0 = this.G.t;
      this.pp.set(Object.assign({ step: this.stepIdx + 1, total: 3, tag: `${T('tag_tq', 'Tourniquet')} · ${this.d.regionLabel || ''}`.replace(/ · $/, ''), steps: [T('sn_place', 'Position the strap'), T('sn_twist', 'Turn the windlass'), T('sn_lock', 'Lock the rod')] }, this.ph.panelInit()));
      const names = [T('tool_strap', 'Strap'), T('tool_windlass', 'Windlass'), T('tool_clip', 'Clip')], icons = ['tq-strap', 'refresh', 'tq-clip'];
      this.pp.set({ tools: this.steps.map((s, i) => ({ key: String(i + 1), label: names[i], icon: icons[i], state: i < this.stepIdx ? 'done' : i === this.stepIdx ? 'active' : 'locked' })) });
    },

    // chain geometry: t (0..1 along the whole limb) ↔ screen point, segment + fraction
    chain(w) {
      const L1 = w.L1, L2 = w.L2, tot = L1 + L2, tj = L1 / tot;
      const at = t => (t <= tj ? mix(w.j0, w.j1, t / tj) : mix(w.j1, w.j2, (t - tj) / (1 - tj)));
      const segOf = t => (t <= tj ? { seg: 'upper', frac: t / tj } : { seg: 'lower', frac: (t - tj) / (1 - tj) });
      const tOf = (seg, frac) => (seg === 'upper' ? frac * tj : tj + frac * (1 - tj));
      const project = p => {
        let best = { t: 0, d: 1e9 };
        [[w.j0, w.j1, 0, tj], [w.j1, w.j2, tj, 1]].forEach(([a, b, t0, t1]) => {
          const ab = sub(b, a), l2 = ab.x * ab.x + ab.y * ab.y || 1;
          const u = clamp(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2, 0, 1);
          const q = add(a, mul(ab, u)), dd = dist(p, q);
          if (dd < best.d) best = { t: lerp(t0, t1, u), d: dd };
        });
        return best;
      };
      const dirAt = t => norm(t <= tj ? sub(w.j1, w.j0) : sub(w.j2, w.j1));
      return { tj, at, segOf, tOf, project, dirAt };
    },

    tqWidth(w, t, ch) { return (t <= ch.tj ? w.L1 * (w.leg ? 0.42 : 0.33) : w.L2 * (w.leg ? 0.32 : 0.27)) * (t <= ch.tj ? lerp(1.0, 0.8, t / ch.tj) : lerp(0.95, 0.75, (t - ch.tj) / (1 - ch.tj))); },

    // assessment of the current strap position
    tqSpot(w) {
      const ch = this.chain(w), d = this.d, q = this.tq, tune = this.tune;
      const tw = ch.tOf(d.woundSeg || 'upper', d.woundFrac || 0.5);
      const cm = (tw - q.t) * tune.length;
      const jz = tune.jointZone || 0.1;
      const s = ch.segOf(q.t);
      const onJoint = (s.seg === 'upper' && s.frac > 1 - jz) || (s.seg === 'lower' && s.frac < jz);
      const highTight = s.seg === 'upper' && s.frac < 0.35;
      const noWound = !d.injury;
      return { ch, tw, cm, onJoint, highTight, seg: s.seg, frac: s.frac, below: !noWound && cm < 1.5, noWound };
    },

    drawLimbTq(c, w, opts = {}) {
      const ch = this.chain(w), q = this.tq;
      const p = ch.at(q.t), dir = ch.dirAt(q.t), n = perp(dir);
      const width = this.tqWidth(w, q.t, ch) * 1.05;
      c.save(); c.translate(p.x, p.y); c.rotate(Math.atan2(dir.y, dir.x));
      const bw = Math.max(10 * w.U, width * 0.22);
      c.fillStyle = 'rgba(0,0,0,.3)'; roundRect(c, -bw / 2 + 3, -width / 2 + 5, bw, width, 4 * w.U); c.fill();
      const g = c.createLinearGradient(0, -width / 2, 0, width / 2);
      g.addColorStop(0, '#15171a'); g.addColorStop(0.2, C.strapHi); g.addColorStop(0.5, '#2f3338'); g.addColorStop(0.85, C.strapHi); g.addColorStop(1, '#121315');
      c.fillStyle = g; roundRect(c, -bw / 2, -width / 2, bw, width, 4 * w.U); c.fill();
      c.strokeStyle = 'rgba(8,175,162,.8)'; c.lineWidth = 1.5 * w.U; c.beginPath(); c.moveTo(-bw / 2 + 2, -width / 2 + 3); c.lineTo(-bw / 2 + 2, width / 2 - 3); c.stroke();
      // slack tail (pulled out to the side)
      if (opts.tail !== undefined) {
        const tl = opts.tail;
        c.fillStyle = '#2b2f34'; roundRect(c, -bw * 0.4, width / 2 - 2, bw * 0.8, tl, 3 * w.U); c.fill();
        c.fillStyle = C.teal; roundRect(c, -bw * 0.55, width / 2 + tl - 6 * w.U, bw * 1.1, 12 * w.U, 3 * w.U); c.fill();
      }
      // windlass rod (rotates while twisting)
      const rl = width * 0.62;
      c.save(); c.rotate(q.theta);
      c.fillStyle = 'rgba(0,0,0,.35)'; roundRect(c, -rl / 2 + 2, -4.5 * w.U + 4, rl, 9 * w.U, 4 * w.U); c.fill();
      const rg = c.createLinearGradient(0, -5 * w.U, 0, 5 * w.U); rg.addColorStop(0, '#2ce0d1'); rg.addColorStop(1, '#067d74');
      c.fillStyle = rg; roundRect(c, -rl / 2, -4.5 * w.U, rl, 9 * w.U, 4 * w.U); c.fill();
      c.restore();
      // clip
      c.strokeStyle = q.locked ? C.tealHi : '#9aa1a6'; c.lineWidth = 3 * w.U;
      c.beginPath(); c.arc(0, -width * 0.36, 7 * w.U, Math.PI, TAU); c.stroke();
      c.restore();
      return { p, dir, n, width };
    },

    /* ── 1. place high & tight, pull the slack ── */
    phPlace() {
      const a = this, G = this.G, q = this.tq, tune = this.tune;
      const ph = {
        phase: 'pos', drag: false, pull: 0, pullDrag: false, best: 0,
        panelInit() {
          return {
            title: T('ph_place', 'Place it high and tight'),
            text: T('ph_place_t', '**Drag the strap** along the limb to where it goes, then press {%s}. Above the wound, never over the elbow or knee.', keyLabel(KEY.confirm)),
            hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_slide', 'slide the strap') }, { keys: [keyLabel(KEY.confirm)], label: T('h_confirm', 'confirm') }],
          };
        },
        key(e) {
          if (e.code === KEY.confirm || e.code === KEY.lock || e.code === 'Enter') { if (this.phase === 'pos') this.confirm(); return true; }
          return false;
        },
        confirm() {
          const w = G.w; if (!w) return;
          const s = a.tqSpot(w);
          if (s.below) { q.misplaced += 1; a.pp.flash('bad', T('tq_below_wound', 'That is below the wound. The bleeding comes from above: move it up.'), 2200); NZA.audio.fail(); return; }
          if (s.onJoint) { q.misplaced += 1; a.pp.flash('bad', T('tq_joint', 'Never over a joint: it will not compress the artery. Move it off the %s.', w.leg ? T('knee', 'knee') : T('elbow', 'elbow')), 2200); NZA.audio.fail(); return; }
          let sc = 100;
          if (!s.noWound && !s.highTight) {
            const lo = tune.idealAbove[0], hi = tune.idealAbove[1];
            if (s.cm < lo) sc = 70; else if (s.cm > hi * 3) sc = 82; else if (s.cm > hi) sc = 92;
            if (s.seg === 'lower') sc -= 8;   // two bones: harder to compress
          }
          q.placeScore = clamp(sc - q.misplaced * 12, 0, 100);
          q.placed = true; q.seg = s.seg; q.frac = s.frac;
          NZA.post('treat:tqPlace', { seg: s.seg, frac: Math.round(s.frac * 1000) / 1000 });
          NZA.audio.click(700);
          this.phase = 'slack';
          a.pp.set({ title: T('ph_slack', 'Pull the strap tight'), text: T('ph_slack_t', '**Drag the teal tab** away from the limb to pull all the slack out. Release it in the green band.'), hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_pull', 'pull the strap') }] });
        },
        tabPos(w) { const ch = a.chain(w); const p = ch.at(q.t), dir = ch.dirAt(q.t), n = perp(dir); const width = a.tqWidth(w, q.t, ch) * 1.05; return add(p, mul(n, width / 2 + (18 + this.pull * 70) * w.U)); },
        down(p) {
          const w = G.w; if (!w) return;
          const ch = a.chain(w);
          if (this.phase === 'pos') { const pr = ch.project(p); if (pr.d < a.tqWidth(w, q.t, ch) * 1.2 && Math.abs(pr.t - q.t) < 0.12) { this.drag = true; NZA.audio.click(520); } else if (pr.d < 60 * w.U) { this.drag = true; } }
          else if (this.phase === 'slack' && dist(p, this.tabPos(w)) < 34 * w.U) { this.pullDrag = true; this.origin = p; this.base = this.pull; }
        },
        move(p) {
          const w = G.w; if (!w) return;
          if (this.drag) { const pr = a.chain(w).project(p); q.t = clamp(pr.t, 0.02, 0.98); }
          if (this.pullDrag) {
            const ch = a.chain(w), n = perp(ch.dirAt(q.t));
            const along = (p.x - this.origin.x) * n.x + (p.y - this.origin.y) * n.y;
            this.pull = clamp(this.base + along / (70 * w.U), 0, 1.25);
          }
        },
        up() {
          if (this.drag) { this.drag = false; NZA.audio.click(600); }
          if (this.pullDrag) {
            this.pullDrag = false;
            if (this.pull >= 0.62) {
              const good = this.pull >= 0.75 && this.pull <= 1.0;
              q.slack = clamp(this.pull, 0, 1);
              q.slackScore = good ? 100 : this.pull > 1.0 ? 70 : 78;
              q.P = q.slack * 0.38 * tune.occlusion;
              a.pp.flash(good ? 'ok' : 'warn', good ? T('ok_slack', 'Slack out. Now the windlass.') : this.pull > 1.0 ? T('slack_over', 'Yanked hard, the buckle slipped a little.') : T('slack_some', 'Some slack left: you will need more turns.'), 1500);
              NZA.audio.click(760);
              if (!this.finished) { this.finished = true; setTimeout(() => a.G && a.nextTq(), 500); }
            }
          }
        },
        update(dt, w) {
          a.cv.className = `tr-stage int ${this.drag || this.pullDrag ? 'grabbing' : 'grab'}`;
          if (!this.pullDrag && this.phase === 'slack') this.pull = Math.max(0, this.pull - dt * 0.6);
          G.b = a.d.injury ? 1 : 0;
        },
        draw(c, w) {
          const ch = a.chain(w), s = a.tqSpot(w);
          if (a.d.injury) { FX.drawStains(c, w); drawWound(c, w, a.d, G.b, G.t); FX.drawParts(c, w); }
          if (this.phase === 'pos') {
            // the rail along the limb
            c.save(); c.lineCap = 'round';
            c.strokeStyle = 'rgba(12,13,16,.55)'; c.lineWidth = 9 * w.U; c.beginPath(); c.moveTo(w.j0.x, w.j0.y); c.lineTo(w.j1.x, w.j1.y); c.lineTo(w.j2.x, w.j2.y); c.stroke();
            c.strokeStyle = 'rgba(255,255,255,.55)'; c.lineWidth = 2 * w.U; c.setLineDash([2 * w.U, 7 * w.U]); c.beginPath(); c.moveTo(w.j0.x, w.j0.y); c.lineTo(w.j1.x, w.j1.y); c.lineTo(w.j2.x, w.j2.y); c.stroke();
            c.restore();
            // joint zone
            const jz = tune.jointZone || 0.1;
            const ja = ch.at(ch.tOf('upper', 1 - jz)), jb = ch.at(ch.tOf('lower', jz));
            c.save(); c.strokeStyle = 'rgba(229,72,77,.55)'; c.lineWidth = 14 * w.U; c.lineCap = 'round'; c.beginPath(); c.moveTo(ja.x, ja.y); c.lineTo(w.j1.x, w.j1.y); c.lineTo(jb.x, jb.y); c.stroke(); c.restore();
            const jn = perp(ch.dirAt(ch.tj));
            label(c, w.j1.x + jn.x * 46 * w.U, w.j1.y + jn.y * 46 * w.U, w.leg ? T('knee_up', 'KNEE') : T('elbow_up', 'ELBOW'), 'red', w.U);
            // wound marker
            if (a.d.injury) { const wp = ch.at(s.tw); ring(c, wp.x, wp.y, w.tr * 0.75, 'rgba(229,72,77,.9)', 2 * w.U, [4 * w.U, 4 * w.U]); }
          }
          const tail = this.phase === 'slack' ? (18 + this.pull * 70) * w.U : undefined;
          const tqd = a.drawLimbTq(c, w, { tail });
          if (this.phase === 'pos') {
            const txt = s.noWound ? (s.highTight ? T('lbl_high', 'High and tight') : T('lbl_lower', 'Lower on the limb')) : s.below ? T('lbl_below', 'Below the wound') : s.onJoint ? T('lbl_joint', 'On the joint') : T('lbl_cm', '%s cm above the wound', Math.max(0, Math.round(s.cm)));
            const tone = s.below || s.onJoint ? 'red' : s.highTight || (s.cm >= tune.idealAbove[0] && s.cm <= tune.idealAbove[1]) ? 'teal' : '';
            label(c, tqd.p.x - tqd.n.x * (tqd.width / 2 + 34 * w.U), tqd.p.y - tqd.n.y * (tqd.width / 2 + 34 * w.U), txt, tone, w.U);
          } else {
            const tp = this.tabPos(w);
            ring(c, tp.x, tp.y, 20 * w.U * (1 + 0.08 * Math.sin(G.t * 6)), C.tealHi, 2 * w.U, [5 * w.U, 4 * w.U]);
            if (!this.pullDrag && this.pull < 0.1) label(c, tp.x + tqd.n.x * 40 * w.U, tp.y + tqd.n.y * 40 * w.U, T('lbl_pull', 'Pull'), 'teal', w.U);
          }
        },
        panel() {
          const w = G.w; if (!w) return;
          const s = a.tqSpot(w);
          if (this.phase === 'pos') {
            a.pp.set({
              stats: [
                { id: 'pos', label: T('st_pos', 'Position'), value: s.noWound ? (s.highTight ? T('high', 'High') : T('low', 'Low')) : s.below ? T('below', 'Below') : `${Math.max(0, Math.round(s.cm))}`, unit: s.noWound || s.below ? '' : T('cm_above', 'cm above'), tone: s.below || s.onJoint ? 'red' : '' },
                { id: 'seg', label: T('st_on', 'On'), value: s.seg === 'upper' ? (w.leg ? T('thigh', 'Thigh') : T('upper_arm', 'Upper arm')) : (w.leg ? T('calf', 'Lower leg') : T('forearm', 'Forearm')), small: true },
              ],
              wide: { label: T('w_place', 'Placement'), value: s.below ? T('bad', 'Bad') : s.onJoint ? T('joint', 'Joint') : T('ok', 'OK'), tone: s.below || s.onJoint ? 'red' : '', meter: { value: 1 - q.t, zone: [1 - s.tw + 0.04, Math.min(1, 1 - s.tw + 0.16)], mark: 1 - q.t, noFill: true }, caption: T('cap_place', '2–3 finger widths above the wound is ideal'), captionTone: 'teal' },
            });
          } else {
            const pull = this.pull;
            a.pp.set({ stats: [{ id: 'slack', label: T('st_slack', 'Slack out'), value: String(Math.round(clamp(pull, 0, 1) * 100)), unit: '%' }], wide: { label: T('w_strap', 'Strap tension'), value: pull > 1 ? T('hard', 'Hard') : pull >= 0.75 ? T('good', 'Good') : T('slack', 'Slack'), meter: { value: clamp(pull / 1.25, 0, 1), zone: [0.75 / 1.25, 1.0 / 1.25], tone: pull > 1 ? 'red' : '' }, caption: T('cap_slack', 'Release inside the green band'), captionTone: 'teal' } });
          }
        },
        device() { a.devTq(); },
      };
      return ph;
    },

    /* ── 2. twist the windlass ── */
    // circling is read from the turning of the mouse path itself (no centre needed):
    // every full circle of the cursor = one full turn of the windlass
    twistInput(ph, dt) {
      const G = this.G, q = this.tq, tune = this.tune;
      const minP = q.slack * 0.38 * tune.occlusion * 0.6, maxP = tune.occlusion + tune.overMargin * 1.7;
      let moved = false;
      const p = G.ptr;
      if (p && !q.locked) {
        if (ph.lp) {
          const dx = p.x - ph.lp.x, dy = p.y - ph.lp.y;
          if (Math.hypot(dx, dy) > 3 * G.U) {
            const ang = Math.atan2(dy, dx);
            if (ph.la !== null && ph.la !== undefined) {
              const da = clamp(angDiff(ang, ph.la), -0.75, 0.75);
              if (!ph.dir && Math.abs(da) > 0.06) ph.dir = da > 0 ? 1 : -1;
              const fwd = da * (ph.dir || 1);
              q.theta += fwd;
              q.P = clamp(q.P + (tune.turnGain * fwd) / TAU, minP, maxP);
              if (fwd > 0.01) moved = true;
              ph.tick = (ph.tick || 0) + Math.abs(fwd);
              if (ph.tick > 0.52) { ph.tick = 0; NZA.audio.tick(); }
            }
            ph.la = ang; ph.lp = p;
          }
        } else ph.lp = p;
      }
      if (moved) ph.idle = 0; else ph.idle = (ph.idle || 0) + dt;
      if (ph.idle > 0.35 && !q.locked) q.P = Math.max(minP, q.P - tune.unwind * dt);
      this.tqBleed(dt);
      if (q.P > tune.occlusion + tune.overMargin) {
        q.over += dt;
        if (!ph.warned) { ph.warned = true; this.pp.flash('bad', T('tq_over', 'Too tight! Nerves and muscle get crushed. Ease off a little.'), 2200); NZA.audio.alarm(1); }
      } else ph.warned = false;
    },

    phTwist() {
      const a = this, G = this.G, q = this.tq;
      const ph = {
        okT: 0, dir: 0, tick: 0, idle: 0, la: null, lp: null,
        panelInit() {
          return {
            title: T('ph_twist', 'Twist the windlass'),
            text: T('ph_twist_t', '**Draw circles with the mouse** to twist the rod, one circle per turn. Keep turning until the bleeding stops and the distal pulse is gone. Do not over-tighten.'),
            hints: [{ keys: [T('k_circle', 'Circle')], label: T('h_twist', 'twist') }, { keys: [T('k_reverse', 'Reverse')], label: T('h_ease', 'ease off') }],
          };
        },
        update(dt, w) {
          a.cv.className = 'tr-stage int';
          a.twistInput(this, dt);
          if (G.b <= 0.001) this.okT += dt; else this.okT = 0;
          if (this.okT > 0.7 && !this.finished) {
            this.finished = true; NZA.audio.success();
            a.pp.flash('ok', T('ok_twist', 'No distal pulse, bleeding stopped. Lock it before it unwinds!'), 1800);
            q.twistTime = G.t - this.t0;
            setTimeout(() => a.G && a.ph === this && a.nextTq(), 350);
          }
        },
        draw(c, w) { a.drawTqStage(c, w); },
        panel() { a.tqPanel(); },
        device() { a.devTq(); },
      };
      return ph;
    },

    tqBleed(dt) {
      const G = this.G, q = this.tq, tune = this.tune;
      const s = G.w ? this.tqSpot(G.w) : null;
      const covers = s && !s.below;
      if (!this.d.injury) { G.b = 0; return; }
      G.b = covers ? Math.pow(clamp(1 - q.P / tune.occlusion, 0, 1), 1.25) : 1;
      // a strap below arterial pressure but above venous pressure makes it bleed MORE
      if (covers && q.P > 30 && q.P < tune.occlusion * 0.55) G.b = Math.min(1.25, G.b * 1.18);
      G.pulseAmp = clamp(1 - q.P / tune.occlusion, 0, 1);
    },

    drawTqStage(c, w) {
      const G = this.G;
      if (this.d.injury) { FX.drawStains(c, w); drawWound(c, w, this.d, G.b, G.t); FX.drawParts(c, w); }
      const tqd = this.drawLimbTq(c, w, {});
      if (this.tq.locked && this.tq.time) {
        const p = tqd.p, n = tqd.n;
        const tp = add(p, mul(n, -(tqd.width / 2 + 16 * w.U)));
        const W = this.cv.width, H = this.cv.height;
        this.tag.style.left = `${(tp.x / W) * 100}%`; this.tag.style.top = `${(tp.y / H) * 100}%`;
      }
    },

    tqPanel() {
      const G = this.G, q = this.tq, tune = this.tune;
      const over = q.P > tune.occlusion + tune.overMargin;
      const occ = q.P >= tune.occlusion;
      const maxP = tune.occlusion + tune.overMargin * 1.7;
      const flow = (this.d.injury ? this.d.injury.bleed : 0) * G.b;
      this.pp.set({
        stats: [
          { id: 'bleed', label: T('st_bleed', 'Bleed'), value: flow.toFixed(1), unit: 'mL/min', tone: flow > 3 ? 'red' : 'teal' },
          { id: 'press', label: T('st_press', 'Pressure'), value: String(Math.round(q.P)), unit: 'mmHg', tone: over ? 'red' : occ ? 'teal' : '' },
          { id: 'pulse', label: T('st_distal', 'Distal pulse'), value: (G.pulseAmp || 0) > 0.04 ? T('present', 'Present') : T('absent', 'Absent'), small: true, tone: (G.pulseAmp || 0) > 0.04 ? 'amber' : 'teal' },
        ],
        wide: { label: T('w_occlusion', 'Occlusion'), value: over ? T('over', 'Over') : occ ? T('occluded', 'Occluded') : `${Math.round((q.P / tune.occlusion) * 100)}`, unit: over || occ ? '' : '%', tone: over ? 'red' : '', meter: { value: q.P / maxP, zone: [tune.occlusion / maxP, (tune.occlusion + tune.overMargin) / maxP], tone: over ? 'red' : '' }, caption: over ? T('cap_over', 'Ease off: over-tightened') : occ ? T('cap_occ', 'Artery closed') : T('cap_twist', 'Keep turning'), captionTone: over ? 'red' : occ ? 'teal' : '' },
      });
    },

    devTq() {
      const G = this.G, q = this.tq, tune = this.tune;
      const s = this.devScreen; if (!s.querySelector('.pr')) return;
      const over = q.P > tune.occlusion + tune.overMargin, occ = q.P >= tune.occlusion;
      const pr = s.querySelector('.pr'); pr.textContent = `${Math.round(q.P)} mmHg`; pr.className = `pr ${over ? 'red' : occ ? 'teal' : ''}`;
      const amp = G.pulseAmp === undefined ? 1 : G.pulseAmp;
      const dp = s.querySelector('.dp'); dp.textContent = amp > 0.04 ? T('present', 'Present') : T('absent', 'Absent'); dp.className = `dp ${amp > 0.04 ? 'amber' : 'teal'}`;
      const led = s.querySelector('.pl'); const on = amp > 0.04 && (G.beat || 0) > 0.5; led.className = `dev-led pl ${on ? '' : 'off'}`;
      const fl = s.querySelector('.fl'); const flow = (this.d.injury ? this.d.injury.bleed : 0) * G.b; fl.textContent = `${flow.toFixed(1)} mL/min`; fl.className = `fl ${flow > 1 ? 'red' : 'teal'}`;
      s.querySelector('.tm').textContent = q.locked ? (q.time || '--:--') : '--:--';
      const st = s.querySelector('.scr-h .st'); st.textContent = q.locked ? T('locked', 'Locked') : over ? T('over', 'Over') : occ ? T('occluded', 'Occluded') : q.placed ? T('loose', 'Loose') : T('ready', 'Ready');
      st.className = `st ${over ? 'red' : occ || q.locked ? '' : 'amber'}`;
      this.devLed(over ? 'red' : occ ? '' : 'off');
      if ((G.beat || 0) > 0.95 && amp > 0.04 && !this.beeped) { this.beeped = true; NZA.audio.beep(640 + 200 * amp, 40, 0.03 * amp); }
      if ((G.beat || 0) < 0.5) this.beeped = false;
      this.drawDial();
    },

    drawDial() {
      const dl = this.dial; if (!dl || !dl.cv) return;
      const fit = NZA.fitCanvas(dl.cv); const c = dl.cv.getContext('2d'); const W = fit.w, H = fit.h, s = fit.scale;
      const q = this.tq, tune = this.tune, G = this.G;
      c.clearRect(0, 0, W, H);
      const cx = W / 2, cy = H / 2, R = Math.min(W, H) * 0.44;
      const maxP = tune.occlusion + tune.overMargin * 1.7;
      const a0 = Math.PI * 0.75, a1 = Math.PI * 2.25, A = v => a0 + (a1 - a0) * clamp(v / maxP, 0, 1);
      c.lineCap = 'round';
      c.strokeStyle = 'rgba(255,255,255,.08)'; c.lineWidth = 8 * s; c.beginPath(); c.arc(cx, cy, R, a0, a1); c.stroke();
      c.strokeStyle = 'rgba(8,175,162,.35)'; c.beginPath(); c.arc(cx, cy, R, A(tune.occlusion), A(tune.occlusion + tune.overMargin)); c.stroke();
      c.strokeStyle = 'rgba(229,72,77,.45)'; c.beginPath(); c.arc(cx, cy, R, A(tune.occlusion + tune.overMargin), a1); c.stroke();
      const over = q.P > tune.occlusion + tune.overMargin, occ = q.P >= tune.occlusion;
      const col = over ? '#ff5a60' : occ ? '#0fd4c4' : '#f3c35a';
      c.strokeStyle = col; c.shadowColor = col; c.shadowBlur = 8 * s; c.lineWidth = 8 * s;
      c.beginPath(); c.arc(cx, cy, R, a0, A(q.P)); c.stroke(); c.shadowBlur = 0;
      // ticks
      c.strokeStyle = 'rgba(255,255,255,.35)'; c.lineWidth = 1.5 * s;
      for (let v = 0; v <= maxP; v += 50) { const a = A(v); c.beginPath(); c.moveTo(cx + Math.cos(a) * (R - 12 * s), cy + Math.sin(a) * (R - 12 * s)); c.lineTo(cx + Math.cos(a) * (R - 7 * s), cy + Math.sin(a) * (R - 7 * s)); c.stroke(); }
      const ao = A(tune.occlusion); c.strokeStyle = '#fff'; c.lineWidth = 2.5 * s; c.beginPath(); c.moveTo(cx + Math.cos(ao) * (R - 14 * s), cy + Math.sin(ao) * (R - 14 * s)); c.lineTo(cx + Math.cos(ao) * (R + 6 * s), cy + Math.sin(ao) * (R + 6 * s)); c.stroke();
      // strap ring (top view) + clip + windlass rod
      const r2 = R * 0.56;
      c.strokeStyle = '#2c3035'; c.lineWidth = 16 * s; c.beginPath(); c.arc(cx, cy, r2, 0, TAU); c.stroke();
      c.strokeStyle = 'rgba(255,255,255,.06)'; c.lineWidth = 1 * s; c.beginPath(); c.arc(cx, cy, r2 + 7 * s, 0, TAU); c.stroke();
      const clipA = -Math.PI / 2;
      const aligned = this.ph && this.ph.name === 'lock' && this.tqAligned();
      [clipA, clipA + Math.PI].forEach(ca => {
        c.save(); c.translate(cx + Math.cos(ca) * r2, cy + Math.sin(ca) * r2); c.rotate(ca + Math.PI / 2);
        c.strokeStyle = q.locked ? '#0fd4c4' : aligned ? '#0fd4c4' : '#9aa1a6'; c.lineWidth = 4 * s;
        c.beginPath(); c.arc(0, 0, 10 * s, Math.PI * 0.05, Math.PI * 0.95, true); c.stroke(); c.restore();
      });
      c.save(); c.translate(cx, cy); c.rotate(q.theta);
      const rl = r2 * 2.15;
      c.fillStyle = 'rgba(0,0,0,.45)'; roundRect(c, -rl / 2 + 2 * s, -6 * s + 3 * s, rl, 12 * s, 6 * s); c.fill();
      const rg = c.createLinearGradient(0, -6 * s, 0, 6 * s); rg.addColorStop(0, '#2ce0d1'); rg.addColorStop(1, '#067d74');
      c.fillStyle = rg; roundRect(c, -rl / 2, -6 * s, rl, 12 * s, 6 * s); c.fill();
      c.fillStyle = '#0a2f2c'; c.beginPath(); c.arc(0, 0, 5 * s, 0, TAU); c.fill();
      c.restore();
      // centre readout
      c.fillStyle = '#fff'; c.font = `700 ${Math.round(22 * s)}px "JetBrains Mono", monospace`; c.textAlign = 'center'; c.textBaseline = 'middle';
      c.fillText(String(Math.round(q.P)), cx, cy + R * 0.82);
      c.fillStyle = 'rgba(255,255,255,.45)'; c.font = `600 ${Math.round(9 * s)}px Lexend, sans-serif`; c.fillText('mmHg', cx, cy + R * 0.82 + 16 * s);
      // circling hint
      if (this.ph && (this.ph.name === 'twist' || this.ph.name === 'lock') && !q.locked) {
        c.strokeStyle = 'rgba(255,255,255,.3)'; c.setLineDash([4 * s, 6 * s]); c.lineWidth = 1.5 * s; c.beginPath(); c.arc(cx, cy, R * 0.86, G.t, G.t + Math.PI * 1.6); c.stroke(); c.setLineDash([]);
      }
    },

    /* ── 3. lock the clip ── */
    phLock() {
      const a = this, G = this.G, q = this.tq, tune = this.tune;
      const ph = {
        dir: 0, tick: 0, idle: 0, la: null, lp: null,
        panelInit() {
          return {
            title: T('ph_lock', 'Lock the windlass'),
            text: T('ph_lock_t', 'Keep circling until the rod sits in the **clip** (it lights up teal), then press {%s} or click. Keep it tight while you do it.', keyLabel(KEY.lock)),
            hints: [{ keys: [T('k_circle', 'Circle')], label: T('h_align', 'align') }, { keys: [keyLabel(KEY.lock)], label: T('h_lock', 'lock') }],
          };
        },
        key(e) { if (e.code === KEY.lock || e.code === KEY.confirm) { this.tryLock(); return true; } return false; },
        down() { this.tryLock(); },
        tryLock() {
          if (q.locked || this.finished) return;
          if (!a.tqAligned()) { q.misLocks += 1; NZA.audio.fail(); a.pp.flash('bad', T('lock_miss', 'The rod is not in the clip. Turn it until the clip lights up.'), 1600); return; }
          if (q.P < tune.occlusion) { q.misLocks += 1; NZA.audio.fail(); a.pp.flash('bad', T('lock_loose', 'It unwound: bleeding again. Twist it back first.'), 1600); return; }
          q.locked = true;
          if (!q.time) { const d = new Date(); q.time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; }
          a.tag.textContent = `T ${q.time}`; a.tag.classList.add('on');
          NZA.audio.click(900); NZA.audio.success();
          a.pp.flash('ok', T('ok_lock', 'Locked. Time written on the strap: %s', q.time), 2200);
          this.finished = true;
          setTimeout(() => a.G && a.finishTq(), 900);
        },
        update(dt, w) {
          a.cv.className = 'tr-stage int';
          if (q.locked) { a.tqBleed(dt); return; }
          a.twistInput(this, dt);
        },
        draw(c, w) { a.drawTqStage(c, w); },
        panel() { a.tqPanel(); },
        device() { a.devTq(); },
      };
      return ph;
    },

    tqAligned() {
      const q = this.tq, tune = this.tune, clipA = -Math.PI / 2;
      const m = x => ((x % Math.PI) + Math.PI) % Math.PI;
      return Math.abs(angDiff(m(q.theta), m(clipA))) * 180 / Math.PI <= tune.clipWindow || Math.abs(Math.abs(angDiff(m(q.theta), m(clipA))) - Math.PI) * 180 / Math.PI <= tune.clipWindow;
    },

    finishTq() {
      const q = this.tq, tune = this.tune;
      const twistScore = clamp(100 - q.over * 6 - Math.max(0, (q.twistTime || 10) - 14) * 1.5, 0, 100);
      const lockScore = clamp(100 - q.misLocks * 18, 0, 100);
      const score = Math.round(q.placeScore * 0.35 + q.slackScore * 0.1 + twistScore * 0.35 + lockScore * 0.2);
      this.ph = { draw: (c, w) => this.drawTqStage(c, w), panel: () => this.tqPanel(), device: () => this.devTq(), update: dt => this.tqBleed(dt) };
      this.submit({ score, seg: q.seg || 'upper', frac: Math.round((q.frac || 0.2) * 1000) / 1000, pressure: Math.round(q.P), over: Math.round(q.over * 10) / 10, misLocks: q.misLocks, time: q.time, steps: { place: q.placeScore, twist: Math.round(twistScore), lock: lockScore } });
    },

    /* ═════════════════════════════ CERVICAL COLLAR ═════════════════════════════ */
    initCollar() {
      const d = this.d, G = this.G;
      G.b = 0;
      this.tune = Object.assign({ fastenSeconds: 4, drift: 1 }, d.tune || {});
      this.col = { fingers: 0, measured: 0, size: null, align: 0, alignT: 0, holdT: 0, fasten: 0, bubble: { x: 0, y: 0, vx: 0, vy: 0 }, sizeScore: 0 };
      this.devBrand('CS-4', T('dev_cs', 'Neck sizer'), T('dev_warn_cs', 'Hold the head in line'));
      this.devScreen.innerHTML = `
        <div class="scr-h"><span class="ch-t">${esc(T('dev_sizing', 'Sizing'))}</span><span class="st">--</span></div>
        <canvas class="dial"></canvas>
        <div class="chart"></div>
        <div class="rows">
          <div class="row"><span class="r1">${esc(T('dev_measured', 'Measured'))}</span><b class="v1">--</b></div>
          <div class="row"><span class="r2">${esc(T('dev_size', 'Collar'))}</span><b class="v2">--</b></div>
        </div>`;
      this.dial = { cv: this.devScreen.querySelector('.dial') };
      this.setTip(d.spinal ? T('tip_spinal', '**Possible spinal injury.** Keep the head in line with the body the whole time.') : T('tip_collar', 'Measure from the top of the shoulder to the chin in finger widths, then pick the collar that matches.'), d.spinal ? 'amber' : '');
      this.stepIdx = -1; this.steps = ['measure', 'fasten'];
      this.nextCollar();
    },

    nextCollar() {
      this.stepIdx += 1;
      const name = this.steps[this.stepIdx];
      if (!name) return this.finishCollar();
      this.ph = name === 'measure' ? this.phMeasure() : this.phFasten();
      this.ph.name = name; this.ph.t0 = this.G.t;
      this.pp.set(Object.assign({ step: this.stepIdx + 1, total: 2, tag: T('tag_collar', 'C-spine'), steps: [T('sn_measure', 'Size the neck'), T('sn_fasten', 'Fit the collar')] }, this.ph.panelInit()));
      this.pp.set({ tools: [{ key: '1', label: T('tool_measure', 'Measure'), icon: 'ruler', state: this.stepIdx > 0 ? 'done' : 'active' }, { key: '2', label: T('tool_collar', 'Collar'), icon: 'collar', state: this.stepIdx > 0 ? 'active' : 'locked' }] });
    },

    sizes() { return [{ id: 'nonneck', f: 2, l: T('size_nonneck', 'No-neck') }, { id: 'short', f: 3, l: T('size_short', 'Short') }, { id: 'regular', f: 4, l: T('size_regular', 'Regular') }, { id: 'tall', f: 5, l: T('size_tall', 'Tall') }]; },

    phMeasure() {
      const a = this, G = this.G, col = this.col, d = this.d;
      const truth = d.fingers || 4;
      const ph = {
        phase: 'measure', drag: false, h: 0,
        panelInit() {
          return {
            title: T('ph_measure', 'Measure the neck'),
            text: T('ph_measure_t', '**Drag your fingers up** from the shoulder line to the chin, one finger width at a time. Stop at the chin, then pick the collar size with {1}–{4}.'),
            hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_measure', 'stack fingers') }, { keys: ['1', '4'], label: T('h_size', 'pick size') }],
          };
        },
        geom(w) {
          const base = add(w.neck, mul(w.axis, w.L * 0.42)); const top = add(w.head, mul(w.axis, w.L * 0.42));
          const span = dist(base, top); const fpx = span / truth; return { base, top, span, fpx, dir: norm(sub(top, base)) };
        },
        key(e) {
          const n = Number((e.code || '').replace('Digit', ''));
          if (n >= 1 && n <= 4) { this.pick(n); return true; }
          if ((e.code === KEY.confirm || e.code === 'Enter') && col.size) { this.done(); return true; }
          return false;
        },
        pick(n) {
          if (!col.measured) { a.pp.flash('warn', T('measure_first', 'Measure the neck first.'), 1400); return; }
          col.size = a.sizes()[n - 1].id; NZA.audio.click(640);
          this.done();
        },
        done() {
          if (this.finished) return;
          const s = a.sizes(), idx = s.findIndex(x => x.id === col.size), ti = s.findIndex(x => x.f === truth);
          col.sizeScore = idx === ti ? 100 : Math.abs(idx - ti) === 1 ? 45 : 0;
          col.measureAcc = clamp(1 - Math.abs(col.measured - truth) * 0.35, 0, 1);
          if (idx !== ti) a.pp.flash('warn', T('size_off', 'Hmm, that collar looks a size off.'), 1600);
          this.finished = true; NZA.audio.success();
          setTimeout(() => a.G && a.nextCollar(), 700);
        },
        down(p) { const w = G.w; if (!w) return; const g = this.geom(w); if (dist(p, g.base) < 60 * w.U || this.h > 0) { this.drag = true; this.start = p; this.h0 = this.h; } },
        move(p) {
          const w = G.w; if (!this.drag || !w) return;
          const g = this.geom(w);
          const along = (p.x - this.start.x) * g.dir.x + (p.y - this.start.y) * g.dir.y;
          this.h = clamp(this.h0 + along, 0, g.span * 1.5);
          const f = Math.round(this.h / g.fpx);
          if (f !== col.fingers) { col.fingers = f; NZA.audio.click(500 + f * 60); }
        },
        up() { if (this.drag) { this.drag = false; col.measured = col.fingers; } },
        update(dt, w) { a.cv.className = `tr-stage int ${this.drag ? 'grabbing' : 'grab'}`; },
        draw(c, w) {
          const g = this.geom(w);
          // shoulder line + chin line
          const n = perp(g.dir);
          const line = (p, col2, txt) => { c.save(); c.strokeStyle = col2; c.lineWidth = 2 * w.U; c.setLineDash([6 * w.U, 5 * w.U]); c.beginPath(); c.moveTo(p.x - n.x * 90 * w.U, p.y - n.y * 90 * w.U); c.lineTo(p.x + n.x * 90 * w.U, p.y + n.y * 90 * w.U); c.stroke(); c.restore(); label(c, p.x + n.x * 150 * w.U, p.y + n.y * 150 * w.U, txt, '', w.U); };
          line(g.base, 'rgba(255,255,255,.7)', T('lbl_shoulder', 'Shoulder line'));
          line(g.top, 'rgba(8,175,162,.9)', T('lbl_chin', 'Chin'));
          // finger stack
          const fingers = Math.round(this.h / g.fpx);
          for (let i = 0; i < Math.max(fingers, 0); i++) {
            const p = add(g.base, mul(g.dir, g.fpx * (i + 0.5)));
            c.save(); c.translate(p.x, p.y); c.rotate(Math.atan2(n.y, n.x));
            const fw = w.cm * 7.5, fh = g.fpx * 0.86;
            const gr = c.createLinearGradient(0, -fh / 2, 0, fh / 2); gr.addColorStop(0, '#80b0e0'); gr.addColorStop(1, C.gloveDark);
            c.fillStyle = gr; roundRect(c, -fw / 2, -fh / 2, fw, fh, fh / 2); c.fill();
            c.strokeStyle = 'rgba(255,255,255,.25)'; c.lineWidth = 1; roundRect(c, -fw / 2 + 2, -fh / 2 + 2, fw * 0.3, fh - 4, fh / 2); c.stroke();
            c.restore();
          }
          const tipP = add(g.base, mul(g.dir, this.h));
          if (!this.drag && !col.measured) { ring(c, g.base.x, g.base.y, 24 * w.U * (1 + 0.08 * Math.sin(G.t * 6)), C.tealHi, 2 * w.U, [5 * w.U, 4 * w.U]); label(c, g.base.x - n.x * 150 * w.U, g.base.y - n.y * 150 * w.U, T('lbl_start', 'Start here'), 'teal', w.U); }
          if (this.h > 0) label(c, tipP.x - n.x * 130 * w.U, tipP.y - n.y * 130 * w.U, T('lbl_fingers', '%s fingers', Math.max(0, fingers)), fingers === truth ? 'teal' : '', w.U);
        },
        panel() {
          a.pp.set({
            stats: [{ id: 'f', label: T('st_fingers', 'Fingers'), value: String(col.fingers || 0) }, { id: 'size', label: T('st_size', 'Size'), value: col.size ? a.sizes().find(s => s.id === col.size).l : '--', small: true }],
            wide: { label: T('w_measure', 'Neck'), value: String(col.fingers || 0), unit: T('fingers', 'fingers'), meter: { value: clamp((col.fingers || 0) / 6, 0, 1), segs: true }, caption: col.measured ? T('cap_pick', 'Now pick the size: 1 No-neck · 2 Short · 3 Regular · 4 Tall') : T('cap_measure', 'Stop exactly at the chin'), captionTone: 'teal' },
          });
        },
        device() { a.devCollar(); },
      };
      return ph;
    },

    phFasten() {
      const a = this, G = this.G, col = this.col, tune = this.tune;
      const ph = {
        holding: false, inT: 0, holdT: 0, origin: null,
        panelInit() {
          return {
            title: T('ph_fasten', 'Fit and fasten'),
            text: T('ph_fasten_t', '**Hold {%s}** to fasten the collar. The head keeps drifting: **move the mouse** to keep the bubble in the circle while you fasten.', keyLabel(KEY.confirm)),
            hints: [{ keys: [keyLabel(KEY.confirm)], label: T('h_fasten', 'hold to fasten') }, { keys: [T('k_move', 'Move')], label: T('h_inline', 'keep in line') }],
          };
        },
        key(e) { if (e.code === KEY.confirm) { this.holding = true; return true; } return false; },
        keyUp(e) { if (e.code === KEY.confirm) this.holding = false; },
        update(dt, w) {
          a.cv.className = 'tr-stage int';
          const bb = col.bubble, dr = tune.drift || 1;
          bb.vx += (Math.random() - 0.5) * 2.4 * dr * dt + Math.sin(G.t * 0.9) * 0.35 * dr * dt;
          bb.vy += (Math.random() - 0.5) * 2.4 * dr * dt + Math.cos(G.t * 0.7) * 0.35 * dr * dt;
          bb.vx *= 0.985; bb.vy *= 0.985;
          bb.x += bb.vx * dt; bb.y += bb.vy * dt;
          // the medic's hands (mouse) counter the drift
          if (G.ptr) {
            if (!this.origin) this.origin = G.ptr;
            this.ctrl = { x: (G.ptr.x - this.origin.x) / (160 * w.U), y: (G.ptr.y - this.origin.y) / (160 * w.U) };
          }
          const ctl = this.ctrl || { x: 0, y: 0 };
          col.pos = { x: clamp(bb.x - ctl.x, -1.2, 1.2), y: clamp(bb.y - ctl.y, -1.2, 1.2) };
          const off = Math.hypot(col.pos.x, col.pos.y);
          const inZone = off < 0.32;
          if (this.holding) { this.holdT += dt; if (inZone) { this.inT += dt; col.fasten += dt / tune.fastenSeconds; } }
          if (off > 0.9 && this.holding && !this.warned) { this.warned = true; a.pp.flash('bad', T('collar_twist', 'The head twisted out of line!'), 1500); NZA.audio.fail(); }
          if (off < 0.6) this.warned = false;
          if (col.fasten >= 1 && !this.finished) {
            this.finished = true;
            col.align = this.holdT > 0 ? clamp(this.inT / this.holdT, 0, 1) * 100 : 0;
            NZA.audio.success();
            a.pp.flash('ok', T('ui_collar_fitted', 'Collar fitted. Keep supporting the head.'), 1500);
            setTimeout(() => a.G && a.nextCollar(), 600);
          }
        },
        draw(c, w) {
          const p = col.pos || { x: 0, y: 0 };
          const fp = col.fasten;
          // collar outline around the neck while it is fastened
          const n = perp(w.axis), mid = mix(w.head, w.neck, 0.72);
          c.save(); c.translate(mid.x, mid.y); c.rotate(Math.atan2(n.y, n.x));
          const cw = w.L * 0.95, chh = w.L * 0.5;
          c.fillStyle = `rgba(240,242,240,${0.25 + 0.6 * clamp(fp, 0, 1)})`; roundRect(c, -cw / 2, -chh / 2, cw, chh, chh * 0.4); c.fill();
          c.strokeStyle = 'rgba(8,175,162,.85)'; c.lineWidth = 3 * w.U; c.beginPath(); c.moveTo(-cw / 2 + 8, chh / 2 - 6); c.lineTo(-cw / 2 + 8 + (cw - 16) * clamp(fp, 0, 1), chh / 2 - 6); c.stroke();
          c.restore();
          // head-in-line indicator on the head
          const tilt = Math.atan2(p.x, 1) * 0.6;
          c.save(); c.translate(w.head.x, w.head.y); c.rotate(Math.atan2(w.axis.y, w.axis.x) - Math.PI / 2 + tilt);
          c.strokeStyle = Math.hypot(p.x, p.y) < 0.32 ? C.tealHi : C.red; c.lineWidth = 2 * w.U; c.setLineDash([5 * w.U, 4 * w.U]);
          c.beginPath(); c.moveTo(0, -w.L * 0.6); c.lineTo(0, w.L * 1.2); c.stroke(); c.restore();
        },
        panel() {
          const off = col.pos ? Math.hypot(col.pos.x, col.pos.y) : 0;
          a.pp.set({
            stats: [{ id: 'fasten', label: T('st_fasten', 'Fastened'), value: String(Math.round(clamp(col.fasten, 0, 1) * 100)), unit: '%' }, { id: 'line', label: T('st_inline', 'In line'), value: off < 0.32 ? T('yes', 'Yes') : T('no', 'No'), small: true, tone: off < 0.32 ? 'teal' : 'red' }],
            wide: { label: T('w_fasten', 'Straps'), value: String(Math.round(clamp(col.fasten, 0, 1) * 100)), unit: '%', meter: { value: clamp(col.fasten, 0, 1) }, caption: this.holding ? (off < 0.32 ? T('cap_fasten', 'Fastening…') : T('cap_inline', 'Bring the head back in line')) : T('cap_hold_space', 'Hold %s', keyLabel(KEY.confirm)), captionTone: off < 0.32 ? 'teal' : 'red' },
          });
        },
        device() { a.devCollar(); },
      };
      return ph;
    },

    devCollar() {
      const s = this.devScreen, col = this.col; if (!s.querySelector('.chart')) return;
      const sizes = this.sizes(), fasten = this.ph && this.ph.name === 'fasten';
      s.querySelector('.ch-t').textContent = fasten ? T('dev_inline', 'In-line level') : T('dev_sizing', 'Sizing');
      const st = s.querySelector('.scr-h .st');
      const off = col.pos ? Math.hypot(col.pos.x, col.pos.y) : 0;
      st.textContent = fasten ? (off < 0.32 ? T('inline', 'In line') : T('drift', 'Drift')) : col.measured ? T('measured', 'Measured') : T('measure', 'Measure');
      st.className = `st ${fasten && off >= 0.32 ? 'red' : ''}`;
      s.querySelector('.chart').innerHTML = sizes.map(z => `<div class="${col.size === z.id ? 'on' : ''}"><b>${z.f}</b><span>${esc(z.l)}</span></div>`).join('');
      s.querySelector('.v1').textContent = col.measured ? T('n_fingers', '%s fingers', col.measured) : '--';
      s.querySelector('.v2').textContent = col.size ? sizes.find(z => z.id === col.size).l : '--';
      this.devLed(fasten && off >= 0.32 ? 'red' : '');
      // bubble level / sizing post
      const fit = NZA.fitCanvas(this.dial.cv); const c = this.dial.cv.getContext('2d'); const W = fit.w, H = fit.h, sc = fit.scale;
      c.clearRect(0, 0, W, H);
      const cx = W / 2, cy = H / 2, R = Math.min(W, H) * 0.4;
      if (fasten) {
        const g = c.createRadialGradient(cx, cy, R * 0.1, cx, cy, R); g.addColorStop(0, '#0d1f1d'); g.addColorStop(1, '#050807');
        c.fillStyle = g; c.beginPath(); c.arc(cx, cy, R, 0, TAU); c.fill();
        c.strokeStyle = 'rgba(255,255,255,.1)'; c.lineWidth = 1 * sc; for (let i = 1; i <= 3; i++) { c.beginPath(); c.arc(cx, cy, (R * i) / 3, 0, TAU); c.stroke(); }
        c.beginPath(); c.moveTo(cx - R, cy); c.lineTo(cx + R, cy); c.moveTo(cx, cy - R); c.lineTo(cx, cy + R); c.stroke();
        c.strokeStyle = '#0fd4c4'; c.lineWidth = 2.5 * sc; c.beginPath(); c.arc(cx, cy, R * 0.32, 0, TAU); c.stroke();
        const p = col.pos || { x: 0, y: 0 };
        const bx = cx + clamp(p.x, -1, 1) * R * 0.85, by = cy + clamp(p.y, -1, 1) * R * 0.85;
        const bg = c.createRadialGradient(bx - 5 * sc, by - 5 * sc, 1, bx, by, 16 * sc); bg.addColorStop(0, 'rgba(255,255,255,.95)'); bg.addColorStop(1, off < 0.32 ? 'rgba(15,212,196,.55)' : 'rgba(255,90,96,.6)');
        c.fillStyle = bg; c.beginPath(); c.arc(bx, by, 15 * sc, 0, TAU); c.fill();
        // fasten progress ring
        c.strokeStyle = 'rgba(255,255,255,.08)'; c.lineWidth = 6 * sc; c.beginPath(); c.arc(cx, cy, R + 12 * sc, 0, TAU); c.stroke();
        c.strokeStyle = '#0fd4c4'; c.beginPath(); c.arc(cx, cy, R + 12 * sc, -Math.PI / 2, -Math.PI / 2 + clamp(col.fasten, 0, 1) * TAU); c.stroke();
      } else {
        // collar side view with the sizing post
        c.save(); c.translate(cx, cy);
        c.fillStyle = '#e9ebea'; roundRect(c, -R * 0.9, -R * 0.55, R * 1.8, R * 1.1, R * 0.3); c.fill();
        c.fillStyle = '#0a9c90'; roundRect(c, -R * 0.9, -R * 0.08, R * 1.8, R * 0.16, R * 0.08); c.fill();
        c.fillStyle = '#c9cdcc'; c.beginPath(); c.ellipse(0, -R * 0.1, R * 0.32, R * 0.22, 0, 0, TAU); c.fill();
        // sizing post with 4 dots
        const px = R * 0.62;
        c.fillStyle = '#1a1c1e'; roundRect(c, px - 7 * sc, -R * 0.5, 14 * sc, R, 7 * sc); c.fill();
        sizes.forEach((z, i) => { const y = R * 0.36 - (i * R * 0.72) / 3; c.fillStyle = col.size === z.id ? '#0fd4c4' : 'rgba(255,255,255,.35)'; c.beginPath(); c.arc(px, y, 4.5 * sc, 0, TAU); c.fill(); });
        c.restore();
        c.fillStyle = 'rgba(255,255,255,.55)'; c.font = `600 ${Math.round(9 * sc)}px Lexend, sans-serif`; c.textAlign = 'center'; c.fillText(T('sizing_post', 'SIZING POST'), cx, cy + R * 0.85);
      }
    },

    finishCollar() {
      const col = this.col;
      const score = Math.round(col.sizeScore * 0.45 + col.align * 0.45 + (col.measureAcc || 0) * 10);
      this.ph = { draw: () => {}, panel: () => {}, device: () => this.devCollar() };
      this.submit({ score, size: col.size || 'regular', align: Math.round(col.align), measured: col.measured });
    },

    /* ═════════════════════════════ SUBMIT / RESULT ═════════════════════════════ */
    submit(result) {
      if (this.sent) return;
      this.sent = true;
      this.pendingResult = result;
      const G = this.G;
      this.pp.set({
        title: T('saving', 'Finishing up…'), titleTone: '', text: T('saving_t', 'Recording the treatment.'), tools: [], hints: [],
        stats: [{ id: 'score', label: T('st_score', 'Score'), value: String(Math.round(result.score || 0)) }].concat(this.mode === 'collar' ? [] : [{ id: 'lost', label: T('st_lost', 'Lost'), value: String(Math.round(G.lost || 0)), unit: 'mL' }]),
        wide: null,
      });
      this.cv.className = 'tr-stage int';
      NZA.post('treat:finish', { result });
    },

    showResult(o) {
      if (!this.pp) return;
      this.result = o;
      const score = Math.round(o.score !== undefined ? o.score : (this.pendingResult && this.pendingResult.score) || 0);
      const failed = !!o.failed;
      const steps = (this.pendingResult && this.pendingResult.steps) || {};
      const stepNames = { pressure: T('step_pressure', 'Pressure'), pack: T('step_pack', 'Packing'), wrap: T('step_wrap', 'Wrap'), dressing: T('step_dressing', 'Dressing'), place: T('step_place', 'Placement'), twist: T('step_twist', 'Windlass'), lock: T('step_lock', 'Clip'), measure: T('step_measure', 'Sizing'), fasten: T('step_fasten', 'Fit') };
      const tone = v => (v < 40 ? 'red' : v < 70 ? 'amber' : 'teal');
      const rows = Object.keys(steps).map(k => `<div class="tc-row bar" data-t="${tone(steps[k])}"><span>${esc(stepNames[k] || k)}</span><i class="mb"><i style="width:${clamp(steps[k], 0, 100)}%"></i></i><b>${Math.round(steps[k])}</b></div>`).join('');
      const C = 2 * Math.PI * 25;
      const st = failed ? 'red' : tone(score);
      this.card.innerHTML = `
        <div class="tc-hd res">
          <span class="tc-score ${st}"><svg viewBox="0 0 60 60"><circle class="b" cx="30" cy="30" r="25"/><circle class="f" cx="30" cy="30" r="25" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${C.toFixed(1)}" style="--off:${(C * (1 - clamp(score, 0, 100) / 100)).toFixed(1)}"/></svg><b>${score}</b><small>/100</small></span>
          <div class="tc-who"><span class="k">${esc(this.title())}</span><b>${esc(failed ? T('res_fail', 'Not controlled') : T('res_ok', 'Treatment recorded'))}</b><span class="sub">${esc(T('res_score', 'Score %s / 100', score))}</span></div>
        </div>
        ${rows ? `<div class="tc-list res">${rows}</div>` : ''}
        <div class="tc-tip ${failed ? 'red' : 'teal'}">${rich(o.msg || '')}</div>`;
      const ringF = this.card.querySelector('.tc-score .f');
      requestAnimationFrame(() => requestAnimationFrame(() => { if (ringF) ringF.style.strokeDashoffset = ringF.style.getPropertyValue('--off'); }));
      if (failed) NZA.audio.fail(); else NZA.audio.success();
      if (o.bleed !== undefined && this.d.injury && this.G) { this.d.injury.bleed = Number(o.bleed) || 0; this.G.b = 1; this.G.cover = false; }
      this.pp.complete({ title: failed ? T('res_fail', 'Not controlled') : T('res_done', 'Done'), text: o.msg || '', label: T('done', 'Done'), onDone: () => this.closeDone() });
      this.pp.set({ abort: false });
      if (failed) this.pp.set({ titleTone: 'bad' });
      clearTimeout(this.autoClose);
      this.autoClose = setTimeout(() => { if (this.result === o) this.closeDone(); }, 9000);
    },

    closeDone() { clearTimeout(this.autoClose); NZA.close('treat'); },

    /* ═════════════════════════════ MEDICATION PANEL ═════════════════════════════ */
    openMeds(data) {
      this.ms = { sel: 0, dose: 0, route: null };
      const drugs = data.drugs || [];
      let sel = Math.max(0, drugs.findIndex(dr => dr.id === data.preset));
      if (sel === 0 && !data.preset) { const firstHave = drugs.findIndex(dr => dr.have > 0); if (firstHave > 0) sel = firstHave; }
      this.ms.sel = sel;
      this.selectDrug(sel);
      this.medsEl.classList.add('on');
      this.renderMeds();
    },
    curDrug() { return (this.d.drugs || [])[this.ms.sel]; },
    selectDrug(i) {
      const dr = (this.d.drugs || [])[i]; if (!dr) return;
      this.ms.sel = i; this.ms.dose = dr.default || 1;
      const access = this.d.info && this.d.info.access;
      this.ms.route = (dr.routes || []).find(r => (r === 'iv' ? (!!access || !!this.d.easy) : true)) || (dr.routes || [])[0];
    },
    moveDrug(dir) { const n = (this.d.drugs || []).length; if (!n) return; this.selectDrug((this.ms.sel + dir + n) % n); this.renderMeds(); NZA.audio.click(); },
    routeKey(i) { if (this.mode !== 'meds') return false; const dr = this.curDrug(); const r = dr && dr.routes[i]; if (r) { this.ms.route = r; this.renderMeds(); } return true; },

    medWarnings(dr) {
      const info = this.d.info || {}, v = info.vitals || {}, act = info.active || {}, tune = this.d.tune || {};
      const out = []; let block = false;
      const W = (tone, title, text) => out.push({ tone, title, text });
      if (!dr) return { out, block: true };
      if ((dr.have || 0) < 1) { W('red', T('w_noitem', 'Not in your bag'), T('w_noitem_t', 'You carry no %s.', dr.label)); block = true; }
      const route = this.ms.route;
      if ((route === 'iv' || dr.access) && !info.access) {
        if (this.d.easy) W('teal', T('w_easy_access', 'Easy mode'), T('w_easy_access_t', 'No line needed in your department: the drug goes straight in.'));
        else { W('red', T('w_noaccess', 'No IV / IO access'), T('w_noaccess_t', 'Place a cannula or IO needle first, or pick another route.')); block = true; }
      }
      if (route === 'po' && (info.state === 'arrest' || (v.avpu && v.avpu !== 'A' && v.avpu !== 'V'))) { W('red', T('w_swallow', 'Cannot swallow'), T('w_swallow_t', 'Nothing by mouth for a patient who is not awake.')); block = true; }
      const ago = s => NZA.fmt.time(s);
      if (dr.id === 'morphine') {
        if (v.rr && v.rr < (tune.morphineRR || 10)) W('red', T('w_rr', 'Slow breathing: %s/min', v.rr), T('w_rr_t', 'Morphine depresses breathing further. Support the airway or give naloxone first.'));
        if (v.sys && v.sys < (tune.morphineSys || 90)) W('amber', T('w_bp', 'Low blood pressure: %s', v.sys), T('w_bp_t', 'Morphine drops the pressure. Treat the shock first.'));
        if (act.morphine) W('amber', T('w_stack', 'Morphine already working'), T('w_stack_t', 'Another dose stacks up (%s left) and risks an overdose.', ago(act.morphine)));
        if (act.naloxone) W('amber', T('w_nalox', 'Naloxone is active'), T('w_nalox_t', 'Morphine will not work for a while.'));
        if (info.pain !== undefined && info.pain < 20) W('teal', T('w_lowpain', 'Little pain'), T('w_lowpain_t', 'Pain score %s/100. Consider holding off.', info.pain));
      } else if (dr.id === 'adrenaline') {
        if (info.state === 'arrest') W('teal', T('w_arrest', 'Cardiac arrest'), T('w_arrest_t', '1 mg IV / IO every 3–5 minutes during CPR.'));
        else { W('amber', T('w_adr', 'Patient has a pulse'), T('w_adr_t', 'Outside CPR: 0.5 mg IM for anaphylaxis or a crashing pressure. It races the heart.')); if (v.hr && v.hr > 130) W('red', T('w_hr', 'Heart rate %s', v.hr), T('w_hr_t', 'Already very fast. Adrenaline speeds it up further.')); }
        if (info.lastAdrenaline !== undefined && info.lastAdrenaline !== null && info.lastAdrenaline < 180) W('amber', T('w_adr_recent', 'Given %s ago', ago(info.lastAdrenaline)), T('w_adr_recent_t', 'Wait 3–5 minutes between doses.'));
      } else if (dr.id === 'naloxone') {
        if (v.pupils === 'pinpoint' || (v.rr && v.rr < 10)) W('teal', T('w_opioid', 'Fits an opioid overdose'), T('w_opioid_t', 'Pinpoint pupils / slow breathing. Naloxone should bring them round.'));
        else W('amber', T('w_noopioid', 'No opioid signs'), T('w_noopioid_t', 'Pupils %s, breathing %s/min: naloxone may change nothing.', v.pupils || '--', v.rr || '--'));
        W('teal', T('w_agitated', 'Stand clear'), T('w_agitated_t', 'They can wake up suddenly, confused and agitated.'));
      } else if (dr.id === 'txa') {
        if ((info.bleeding || 0) < 1) W('amber', T('w_txa_none', 'Not bleeding much'), T('w_txa_none_t', 'TXA helps clots hold in major bleeding.'));
        if (act.txa) W('amber', T('w_txa_active', 'TXA on board'), T('w_txa_active_t', 'Still working for %s.', ago(act.txa)));
      } else if (dr.id === 'antibiotics') {
        if (act.antibiotics) W('amber', T('w_ab_active', 'Antibiotics on board'), T('w_ab_active_t', 'Still covered for %s.', ago(act.antibiotics)));
      } else if (dr.id === 'painkillers') {
        if (act.morphine) W('amber', T('w_pk_morph', 'Morphine is working'), T('w_pk_morph_t', 'Tablets add little on top.'));
        if (act.painkillers) W('amber', T('w_pk_active', 'Already taken'), T('w_pk_active_t', 'Still working for %s.', ago(act.painkillers)));
      }
      return { out, block };
    },

    renderMeds() {
      const d = this.d, info = d.info || {}, v = info.vitals || {}, drugs = d.drugs || [];
      const dr = this.curDrug();
      const { out, block } = this.medWarnings(dr);
      const danger = out.some(x => x.tone === 'red');
      const act = info.active || {};
      const tone = (val, warn, bad, inv) => { if (!val) return ''; if (inv) return val < bad ? 'bad' : val < warn ? 'warn' : ''; return val > bad ? 'bad' : val > warn ? 'warn' : ''; };
      const doseBtns = dr ? dr.doses.map((x, i) => `<button data-d="${i + 1}" class="${this.ms.dose === i + 1 ? 'on' : ''}">${esc(x.mg)}</button>`).join('') : '';
      const routes = dr ? dr.routes.map((r, i) => {
        const dis = (r === 'iv' || dr.access) && !info.access && !d.easy;
        return `<button data-r="${esc(r)}" class="${this.ms.route === r ? 'on' : ''}" ${dis ? 'disabled' : ''}>${esc(T('route_' + r, r.toUpperCase()))}</button>`;
      }).join('') : '';
      const doseLabel = dr && dr.doses[this.ms.dose - 1] ? dr.doses[this.ms.dose - 1].mg : '';
      this.medsEl.innerHTML = `
        <div class="mh"><span class="ic">${NZA.icon('syringe')}</span><div><h3>${esc(T('meds_title', 'Medication'))}</h3><p>${esc(info.name || (d.patient && d.patient.name) || '')} · ${esc(T('state_' + (info.state || 'alive'), info.state || ''))}</p></div><span class="sp"></span>
          ${info.access ? `<span class="chipx sm teal">${NZA.icon('iv')}${esc(T('access_' + info.access, String(info.access).toUpperCase()))}</span>` : `<span class="chipx sm amber">${NZA.icon('iv')}${esc(T('no_access', 'No IV access'))}</span>`}
          <button class="pill-close">${esc(T('close', 'Close'))}</button></div>
        <div class="mb2">
          <div class="mlist nza-scroll"><div class="ml-h">${esc(T('drugs', 'Drugs'))}</div>
            ${drugs.map((x, i) => `<button class="drug ${i === this.ms.sel ? 'on' : ''} ${x.have > 0 ? '' : 'off'}" data-i="${i}"><span class="di">${NZA.icon(x.icon || 'syringe')}</span><span class="dt"><b>${esc(x.label)}</b><span>${esc(x.short || '')}</span></span><span class="dc ${x.have > 0 ? '' : 'none'}">×${x.have || 0}${act[x.id] ? `<i>${esc(NZA.fmt.time(act[x.id]))}</i>` : ''}</span></button>`).join('')}
          </div>
          <div class="mdet">
            <div class="dh"><div><h2>${esc(dr ? dr.label : '')}</h2><p>${esc(dr ? dr.desc || '' : '')}</p></div>${dr && act[dr.id] ? `<span class="chipx sm teal">${NZA.icon('clock')}${esc(T('active_for', 'Active %s', NZA.fmt.time(act[dr.id])))}</span>` : ''}</div>
            <div class="mvit">
              ${vring({ value: v.hr || '--', frac: (v.hr || 0) / 180, tone: !v.hr ? '' : tone(v.hr, 120, 140) === 'bad' ? 'red' : tone(v.hr, 120, 140) ? 'amber' : 'green', label: 'HR', beat: v.hr ? 60 / clamp(v.hr, 30, 200) : 0 })}
              ${vring({ value: v.sys ? `${v.sys}` : '--', frac: (v.sys || 0) / 180, tone: !v.sys ? '' : tone(v.sys, 100, 90, true) === 'bad' ? 'red' : tone(v.sys, 100, 90, true) ? 'amber' : 'white', label: 'SYS', unit: v.dia ? `/${v.dia}` : '' })}
              ${vring({ value: v.rr || '--', frac: (v.rr || 0) / 40, tone: !v.rr ? '' : tone(v.rr, 12, 10, true) === 'bad' ? 'red' : tone(v.rr, 12, 10, true) ? 'amber' : 'yellow', label: 'RR' })}
              ${vring({ value: v.spo2 || '--', frac: ((v.spo2 || 70) - 70) / 30, tone: !v.spo2 ? '' : tone(v.spo2, 94, 90, true) === 'bad' ? 'red' : tone(v.spo2, 94, 90, true) ? 'amber' : 'cyan', label: 'SpO₂' })}
              ${vring({ value: info.pain !== undefined ? info.pain : '--', frac: (info.pain || 0) / 100, tone: info.pain > 60 ? 'red' : info.pain > 30 ? 'amber' : 'teal', label: T('pain_l', 'Pain') })}
              ${vring({ value: v.avpu || '--', frac: { A: 1, V: 0.66, P: 0.33, U: 0.08 }[v.avpu] || 0, tone: v.avpu && v.avpu !== 'A' ? (v.avpu === 'V' ? 'amber' : 'red') : 'teal', label: 'AVPU' })}
            </div>
            <div class="mrow"><span>${esc(T('dose', 'Dose'))}</span><div class="segc seg-dose">${doseBtns}</div></div>
            <div class="mrow"><span>${esc(T('route', 'Route'))}</span><div class="segc seg-route">${routes}</div></div>
            <div class="mwarn">${out.map(x => `<div class="mnote ${x.tone === 'teal' ? '' : x.tone}"><span class="ni">${NZA.icon(x.tone === 'red' ? 'alert' : x.tone === 'amber' ? 'alert' : 'info')}</span><div><b>${esc(x.title)}</b><p>${esc(x.text)}</p></div></div>`).join('') || `<div class="mnote"><span class="ni">${NZA.icon('check')}</span><div><b>${esc(T('w_clear', 'No warnings'))}</b><p>${esc(T('w_clear_t', 'Nothing in the vitals argues against this drug.'))}</p></div></div>`}</div>
            <div class="mact"><div class="sum">${dr ? `${esc(T('give_sum', 'Give'))} <b>${esc(dr.label)} ${esc(doseLabel)}</b> ${esc(T('route_' + this.ms.route, (this.ms.route || '').toUpperCase()))}` : ''}</div><span class="sp"></span>
              ${block ? `<button class="btn-line" disabled>${NZA.icon('x')}<span>${esc(T('cannot_give', 'Cannot give'))}</span></button>` : danger ? `<button class="btn-red give-hold"><span class="hf"></span>${NZA.icon('alert')}<span>${esc(T('hold_give', 'Hold to give anyway'))}</span></button>` : `<button class="btn-teal give">${NZA.icon('syringe')}<span>${esc(T('administer', 'Administer'))}</span></button>`}
            </div>
          </div>
        </div>
        <div class="mfoot"><span><kbd>↑</kbd><kbd>↓</kbd>${esc(T('f_drug', 'Drug'))}</span><span><kbd>1</kbd><kbd>3</kbd>${esc(T('f_dose', 'Dose'))}</span><span><kbd>Q</kbd><kbd>W</kbd><kbd>R</kbd>${esc(T('f_route', 'Route'))}</span><span><kbd>Enter</kbd>${esc(T('f_give', 'Give'))}</span><span><kbd>ESC</kbd>${esc(T('close', 'Close'))}</span>${NZA.cfg.signature !== false ? '<span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>' : ''}</div>`;
      const m = this.medsEl;
      m.querySelector('.pill-close').onclick = () => NZA.close('treat');
      m.querySelectorAll('.drug').forEach(b => { b.onclick = () => { this.selectDrug(Number(b.dataset.i)); this.renderMeds(); NZA.audio.click(); }; });
      m.querySelectorAll('.seg-dose button').forEach(b => { b.onclick = () => { this.ms.dose = Number(b.dataset.d); this.renderMeds(); }; });
      m.querySelectorAll('.seg-route button').forEach(b => { b.onclick = () => { if (b.disabled) return; this.ms.route = b.dataset.r; this.renderMeds(); }; });
      const give = m.querySelector('.give'); if (give) give.onclick = () => this.giveSelected();
      if (this.holdBtn) { this.holdBtn.destroy(); this.holdBtn = null; }
      const hb = m.querySelector('.give-hold');
      if (hb) this.holdBtn = NZA.ui.Hold({ key: '__none__', el: hb, seconds: 1.2, onProgress: p => hb.style.setProperty('--hold', p), onDone: () => this.giveSelected(true) });
    },

    giveSelected(forced) {
      if (this.mode !== 'meds' || this.medsEl.classList.contains('busy')) return;
      const dr = this.curDrug(); if (!dr) return;
      const { out, block } = this.medWarnings(dr);
      if (block) { NZA.audio.fail(); return; }
      if (out.some(x => x.tone === 'red') && !forced) { NZA.audio.fail(); return; }
      this.medsEl.classList.add('busy');
      NZA.post('treat:give', { drug: dr.id, dose: this.ms.dose, route: this.ms.route });
    },

    /* ═════════════════════════════ FIRST AID KIT ═════════════════════════════ */
    openKit(data) {
      this.ks = { sel: Math.max(0, (data.items || []).findIndex(x => x.usable && x.have > 0)) };
      this.kitEl.classList.add('on');
      this.renderKit();
    },
    renderKit() {
      const d = this.d, items = d.items || [];
      const icons = { bandage: 'bandage', medkit: 'medkit', ice_pack: 'snow', burn_dressing: 'flame', painkillers: 'pill', foil_blanket: 'blanket' };
      this.kitEl.innerHTML = `
        <div class="mh"><span class="ic">${NZA.icon('medkit')}</span><div><h3>${esc(T('kit_title', 'First aid'))}</h3><p>${esc(d.self ? T('kit_self', 'On yourself') : (d.name || ''))}</p></div><span class="sp"></span><button class="pill-close">${esc(T('close', 'Close'))}</button></div>
        <div class="kl">${items.length ? items.map((x, i) => {
          const ok = x.usable && x.have > 0;
          return `<button class="kit ${ok ? '' : 'off'} ${i === this.ks.sel ? 'on' : ''}" data-i="${i}"><kbd>${i + 1}</kbd><span class="ki">${x.img ? `<img src="${esc(x.img)}" alt="">` : NZA.icon(icons[x.key] || 'medkit')}</span><span class="kt"><b>${esc(x.label || x.key)}</b><span>${esc(x.have > 0 ? (x.text || '') : T('kit_none_have', 'You have none'))}</span></span><span class="kc ${x.have > 0 ? '' : 'none'}">×${x.have || 0}</span></button>`;
        }).join('') : `<div class="kempty">${esc(T('kit_empty', 'Nothing you carry can help here.'))}</div>`}</div>
        <div class="mfoot"><span><kbd>1</kbd><kbd>6</kbd>${esc(T('f_use', 'Use'))}</span><span><kbd>↑</kbd><kbd>↓</kbd>${esc(T('f_pick', 'Pick'))}</span><span><kbd>Enter</kbd>${esc(T('f_use', 'Use'))}</span><span><kbd>ESC</kbd>${esc(T('close', 'Close'))}</span></div>`;
      this.kitEl.querySelector('.pill-close').onclick = () => NZA.close('treat');
      this.kitEl.querySelectorAll('.kit').forEach(b => { b.onclick = () => this.useKit(Number(b.dataset.i)); });
    },
    moveKit(dir) { const n = (this.d.items || []).length; if (!n) return; this.ks.sel = (this.ks.sel + dir + n) % n; this.renderKit(); },
    useKit(i) {
      const x = (this.d.items || [])[i]; if (!x) return;
      if (!(x.usable && x.have > 0)) { NZA.audio.fail(); this.ks.sel = i; this.renderKit(); return; }
      NZA.post('treat:use', { key: x.key });
      NZA.closeLocal('treat');
    },

    /* ═════════════════════════════ PREVIEW ═════════════════════════════ */
    preview() {
      const q = new URLSearchParams(location.search);
      const demo = q.get('demo') || 'bleed';
      const vit = { hr: 128, sys: 94, dia: 58, spo2: 95, rr: 24 };
      const pt = { name: 'Lena Okafor', sex: 'f', kind: 'npc' };
      NZA.mock('treat:finish', res => {
        const r = res.result || {};
        setTimeout(() => app.msg.result({ score: r.score, grade: null, msg: demo === 'tq' ? 'Tourniquet on: Left thigh at 14:32. Bleeding stopped.' : demo === 'collar' ? 'Collar fitted (Regular). Spine stabilised.' : 'Packing + Wrap · Left thigh. Bleeding now 2.4 mL/min.', bleed: demo === 'bleed' || !demo ? 2.4 : undefined }), 500);
        return { ok: true };
      });
      NZA.mock('treat:give', () => { setTimeout(() => app.msg.given({ ok: true }), 600); return { ok: true }; });
      if (demo === 'meds') {
        this.preset = null;
        NZA.demo('treat', {
          mode: 'meds', patient: pt, preset: 'morphine', tune: { morphineRR: 10, morphineSys: 90 },
          info: { name: 'Lena Okafor', state: 'wounded', pain: 74, access: 'iv', active: { painkillers: 812 }, bleeding: 18.4, vitals: { hr: 118, sys: 88, dia: 54, rr: 9, spo2: 93, avpu: 'V', pupils: 'normal' } },
          drugs: [
            { id: 'morphine', label: 'Morphine', short: '10 mg/ml · opioid analgesic', desc: 'Strong pain relief. Slows breathing and drops the pressure: watch both.', icon: 'syringe', have: 3, routes: ['iv', 'im'], doses: [{ dose: 0.5, mg: '2.5 mg' }, { dose: 1, mg: '5 mg' }, { dose: 2, mg: '10 mg' }], default: 2 },
            { id: 'adrenaline', label: 'Adrenaline', short: '1 mg/ml · vasopressor', desc: 'Cardiac arrest, anaphylaxis, a crashing blood pressure.', icon: 'bolt', have: 2, routes: ['im', 'iv'], doses: [{ dose: 0.5, mg: '0.5 mg' }, { dose: 1, mg: '1 mg' }], default: 1 },
            { id: 'naloxone', label: 'Naloxone', short: '0.4 mg/ml · opioid antagonist', desc: 'Reverses an opioid overdose within minutes.', icon: 'syringe', have: 1, routes: ['in', 'im', 'iv'], doses: [{ dose: 0.5, mg: '0.4 mg' }, { dose: 1, mg: '0.8 mg' }, { dose: 2, mg: '2 mg' }], default: 2 },
            { id: 'txa', label: 'Tranexamic acid', short: '1 g · antifibrinolytic', desc: 'Helps clots hold in major bleeding. Within 3 hours of injury.', icon: 'drop', have: 2, routes: ['iv'], access: true, doses: [{ dose: 1, mg: '1 g' }], default: 1 },
            { id: 'antibiotics', label: 'Antibiotics', short: 'Cefazolin · broad cover', desc: 'Prevents and treats wound infection in dirty wounds.', icon: 'pill', have: 0, routes: ['iv', 'im'], doses: [{ dose: 1, mg: '1 g' }, { dose: 2, mg: '2 g' }], default: 1 },
            { id: 'painkillers', label: 'Painkillers', short: 'Paracetamol · oral', desc: 'Mild pain relief by mouth.', icon: 'pill', have: 4, routes: ['po'], doses: [{ dose: 1, mg: '1 g' }], default: 1 },
          ],
        });
        return;
      }
      if (demo === 'kit') {
        this.preset = null;
        NZA.demo('treat', {
          mode: 'kit', name: 'Lena Okafor', self: false,
          items: [
            { key: 'bandage', label: 'Bandage', have: 6, usable: true, text: 'Bandage: Deep laceration · Left forearm' },
            { key: 'medkit', label: 'Medkit', have: 1, usable: true, text: 'Patch up 2 minor injuries' },
            { key: 'ice_pack', label: 'Ice Pack', have: 2, usable: true, text: 'Cool: Contusion · Right thigh' },
            { key: 'burn_dressing', label: 'Burn Dressing', have: 1, usable: false, text: 'No burns to dress' },
            { key: 'painkillers', label: 'Painkillers', have: 0, usable: true, text: 'Pain 62/100' },
            { key: 'foil_blanket', label: 'Foil Blanket', have: 2, usable: true, text: 'Body temperature 34.6 °C: warm them up' },
          ],
        });
        return;
      }
      if (demo === 'tq') {
        this.preset = 'legfar';
        NZA.demo('treat', {
          mode: 'tq', patient: pt, vitals: vit, region: 'l_upper_leg', regionLabel: 'Left thigh', limb: 'leg', woundSeg: 'upper', woundFrac: 0.62,
          injury: { id: 'i7', region: 'l_upper_leg', regionLabel: 'Left thigh', type: 'gunshot', typeLabel: 'Gunshot wound', severity: 4, sevLabel: 'Critical', bleed: 186.4, limb: 'leg', frac: 0.62, arterial: true, spot: { x: 0.55, y: 0.72 } },
          tune: { occlusion: 194, turnGain: 68, overMargin: 110, unwind: 22, clipWindow: 14, jointZone: 0.1, idealAbove: [5, 8], length: 88 },
          time: '14:32',
        });
        const step = q.get('step');
        if (step === 'twist' || step === 'lock') {
          setTimeout(() => {
            this.tq.t = 0.2; this.ph.confirm(); this.tq.slack = 0.85; this.tq.slackScore = 100; this.ph.finished = true; this.nextTq();
            this.tq.P = step === 'lock' ? 236 : 128; this.tq.theta = step === 'lock' ? 4.6 : 2.2;
            if (step === 'lock') { this.ph.finished = true; this.nextTq(); }
          }, 150);
        }
        return;
      }
      if (demo === 'collar') {
        this.preset = 'neck';
        NZA.demo('treat', { mode: 'collar', patient: pt, vitals: vit, fingers: 4, size: 'regular', spinal: true, regionLabel: 'Neck', neck: [], tune: { fastenSeconds: 4, drift: 1 } });
        if (q.get('step') === 'fasten') {
          setTimeout(() => { this.col.measured = 4; this.col.fingers = 4; this.col.size = 'regular'; this.ph.done(); }, 150);
          setTimeout(() => { if (this.ph && this.ph.name === 'fasten') { this.ph.holding = true; this.col.fasten = 0.46; this.col.bubble = { x: 0.14, y: -0.1, vx: 0, vy: 0 }; } }, 1100);
        } else setTimeout(() => { const w = this.G && this.G.w; if (w) { this.ph.h = this.ph.geom(w).fpx * 3; this.col.fingers = 3; this.col.measured = 3; } }, 200);
        return;
      }
      if (demo === 'torso') {
        this.preset = 'torso';
        NZA.demo('treat', {
          mode: 'bleed', patient: pt, vitals: vit, steps: ['pressure', 'dressing'], method: 'dressing', deep: false,
          injury: { id: 'i3', region: 'chest', regionLabel: 'Chest', type: 'laceration', typeLabel: 'Deep laceration', severity: 2, sevLabel: 'Moderate', bleed: 14.2, limb: false, length: 64, spot: { x: 0.42, y: 0.5 } },
          tune: { pressureTarget: 0.3, pressureHold: 2.5, packStrips: 4, wrapTurns: 4, tensionBand: [0.38, 0.72] },
        });
        if (q.get('step') === 'dressing') { this.G.steps.pressure = 88; this.nextStep(); }
        return;
      }
      this.preset = 'leg';
      NZA.demo('treat', {
        mode: 'bleed', patient: pt, vitals: vit, steps: ['pressure', 'pack', 'wrap'], method: 'wrap', deep: true,
        injury: { id: 'i7', region: 'l_upper_leg', regionLabel: 'Left thigh', type: 'gunshot', typeLabel: 'Gunshot wound', severity: 3, sevLabel: 'Serious', bleed: 64.8, limb: 'leg', frac: 0.55, arterial: true, spot: { x: 0.55, y: 0.6 } },
        tune: { pressureTarget: 0.3, pressureHold: 2.5, packStrips: 4, wrapTurns: 4, tensionBand: [0.38, 0.72] },
      });
      const step = q.get('step');
      if (step === 'pack') { this.G.steps.pressure = 91; this.nextStep(); }
      if (step === 'wrap') { this.G.steps.pressure = 91; this.G.steps.pack = 84; this.stepIdx = 1; this.nextStep(); }
    },
  });
})();
