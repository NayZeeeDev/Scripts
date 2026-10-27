/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · NZR.sfx — procedural radio audio                       core/sfx.js
   WebAudio only, no sound files. Loaded after core/nzr.js and replaces its NZR.sfx stub.
   One AudioContext for the whole page (NZR.audio.ctx() / out()); it is created on the first
   '_core' message and resumed on every one after. Nothing here ever throws: when the browser
   will not run audio yet, sounds are dropped quietly.

   NZR.sfx.play(name, opts) → bool   one-shot. opts.volume 0..1.5 (× master), opts.q 0..1
     key error toggle boot power_off · tx_start rx_start tx_end rx_end squelch {q} lost
     emergency · place hack_tick hack_ok hack_fail · gunshot {kind, d, q}
   NZR.sfx.rx({ active, worstQ, lost, gain })   hiss bed with slow flutter; lost adds stutter
                                               and broken bursts. gain defaults to (1-q)^1.6*.35
   NZR.sfx.noise(gain 0..1)                    jammer bed: noise + a 3-7 Hz swept warble
   NZR.sfx.ambient(on, volume 0..1)            cabin ambience: faint static + random squelch
                                               chirps every 6-20 s
   NZR.sfx.gunfire(shots, q, volume)           shots = [{ dt (ms after the first shot), kind, d (m) }]
                                               kind pistol|smg|rifle|shotgun|sniper|heavy|silenced,
                                               scheduled after a 180 ms jitter buffer, level by d, × q
   NZR.sfx.volume(v)  NZR.sfx.stop(name | 'all')  NZR.sfx.unlock()  NZR.sfx.names  NZR.sfx.state()

   '_core' actions handled (NZR.onCore):
     sfx { name, ...opts } · rx { active, worstQ, lost, gain } · noise { gain } ·
     ambient { on, volume } · gunfire { shots, q, volume } · config { sfx, clicks }
   Mic clicks are gated in Lua (a per-player setting): config.clicks is kept as NZR.sfx.clicks
   only, so a player who turned clicks on still hears them when the server default is off.

   Preview: index.html?app=sfx — a bench with a button for every sound and sliders for the beds.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  if (!NZR || !NZR.audio) return;
  const AU = NZR.audio;
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const rnd = (a, b) => a + Math.random() * (b - a);
  const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };

  const MAX_VOICES = 32;          // one-shots alive at once (a gunshot counts as one)
  const MAX_SHOTS = 30;           // per gunfire batch (SPEC §5.1)
  const JITTER = 0.18;            // s, gunfire jitter buffer
  const GUN_RADIUS = 60;          // m, Config.Gunfire.radius default: level falls to the floor here
  const BED_HISS = 0.5;           // bed scale: rx gain (0..~.35) → speaker level
  const BED_JAM = 0.24;
  const BED_AMB = 0.025;
  const BED_IDLE_MS = 4000;       // a silent bed is torn down after this long

  const st = { vol: 0.8, clicks: true };
  let ctx = null;                 // the context the graph was built for
  let G = null;                   // { bus, comp, spk, noise, soft, scope }
  let suspendedTake = 0;          // one-shots accepted while the context is still suspended
  let lastResume = -1e9;
  const voices = [];              // { end, nodes }
  const curves = {};

  /* ─────────────── graph ─────────────── */
  function curve(k) {
    const key = Math.round(k * 4) / 4;
    if (curves[key]) return curves[key];
    const n = 1024, c = new Float32Array(n), d = Math.tanh(key);
    for (let i = 0; i < n; i++) { const x = i * 2 / (n - 1) - 1; c[i] = Math.tanh(key * x) / d; }
    curves[key] = c;
    return c;
  }
  function biq(c, type, f, Q = 0.7, gain = 0) {
    const b = c.createBiquadFilter();
    b.type = type; b.frequency.value = f; b.Q.value = Q;
    if (gain) b.gain.value = gain;
    return b;
  }
  function amp(c, v = 1) { const g = c.createGain(); g.gain.value = v; return g; }
  function chain(...n) { for (let i = 0; i < n.length - 1; i++) n[i].connect(n[i + 1]); return n[n.length - 1]; }

  function build(c) {
    const out = AU.out();
    if (!out) throw new Error('no output');
    const bus = amp(c, st.vol);
    // a gentle limiter: a gunfight plus the beds never clips the page
    const comp = c.createDynamicsCompressor();
    comp.threshold.value = -12; comp.knee.value = 8; comp.ratio.value = 6;
    comp.attack.value = 0.002; comp.release.value = 0.16;
    bus.connect(comp); comp.connect(out);
    // the radio's own little speaker: band limited, a presence bump, a touch of grit
    const spk = amp(c, 1);
    const sh = c.createWaveShaper(); sh.curve = curve(1.6); sh.oversample = '2x';
    chain(spk, biq(c, 'highpass', 280, 0.7), biq(c, 'peaking', 1750, 0.9, 3.5), biq(c, 'lowpass', 3500, 0.7), sh, bus);
    // 2 s of white noise shared by every noisy sound (random start offsets)
    const len = c.sampleRate * 2, noise = c.createBuffer(1, len, c.sampleRate), d = noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    G = { bus, comp, spk, noise, scope: null };
  }

  function ensure() {
    let c = null;
    try { c = AU.ctx(); } catch (_) { c = null; }
    if (!c || c.state === 'closed') return null;
    if (c !== ctx) {
      ctx = c; G = null; beds.hiss = beds.jam = beds.amb = null;
      suspendedTake = 0; voices.length = 0; lastResume = -1e9;
      try { build(c); } catch (e) { console.warn('[nzr] sfx: no audio graph', e); G = null; }
    }
    // a blocked page would refuse (and log) every resume: ask at most every 2 s
    if (c.state === 'suspended' && performance.now() - lastResume > 2000) {
      lastResume = performance.now();
      try { c.resume().catch(() => {}); } catch (_) { /* not allowed yet */ }
    }
    return G ? c : null;
  }
  // a context that sounds now (or the moment it resumes: only a few one-shots wait for that,
  // so a page that was blocked for minutes does not fire a backlog at once)
  function live() {
    const c = ensure();
    if (!c) return null;
    if (c.state === 'running') { suspendedTake = 0; return c; }
    if (suspendedTake < 3) { suspendedTake++; return c; }
    return null;
  }
  function room(c) {
    const now = c.currentTime;
    for (let i = voices.length - 1; i >= 0; i--) if (voices[i].end < now) voices.splice(i, 1);
    return voices.length < MAX_VOICES;
  }

  /* ─────────────── building blocks ─────────────── */
  // percussive envelope: silence → peak in a, hold h, exponential release r
  function env(p, t, peak, a, h, r) {
    p.cancelScheduledValues(t);
    p.setValueAtTime(0.0001, t);
    p.linearRampToValueAtTime(Math.max(0.0002, peak), t + a);
    if (h > 0) p.setValueAtTime(Math.max(0.0002, peak), t + a + h);
    p.exponentialRampToValueAtTime(0.0001, t + a + h + r);
  }
  function tone(c, dest, t, nodes, { f, to = null, type = 'sine', dur, vol, a = 0.004, r = null }) {
    const o = c.createOscillator(), g = amp(c, 0);
    o.type = type; o.frequency.setValueAtTime(f, t);
    if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
    const rel = r !== null ? r : Math.min(0.04, dur * 0.5);
    env(g.gain, t, vol, a, Math.max(0, dur - a - rel), rel);
    o.connect(g); g.connect(dest);
    o.start(t); o.stop(t + dur + 0.05);
    nodes.push(o);
    return t + dur;
  }
  // noise burst through optional filters; returns the burst's output (caller connects it)
  function burst(c, t, nodes, { dur, vol, a = 0.002, r = null }, ...filters) {
    const s = c.createBufferSource();
    s.buffer = G.noise; s.loop = true;
    const g = amp(c, 0);
    const rel = r !== null ? r : dur * 0.6;
    env(g.gain, t, vol, a, Math.max(0, dur - a - rel), rel);
    chain(s, ...filters, g);
    s.start(t, rnd(0, 1.9)); s.stop(t + dur + 0.05);
    nodes.push(s);
    return g;
  }
  function click(c, t, nodes, vol) {
    burst(c, t, nodes, { dur: 0.006, vol, a: 0.0005, r: 0.005 }, biq(c, 'highpass', 1800, 0.7)).connect(G.bus);
  }
  // two-tone chirp through the speaker, a faint octave on top so it rings like a real set
  function chirp(c, t, nodes, seq, vol) {
    let at = t;
    seq.forEach(([f, d]) => {
      tone(c, G.spk, at, nodes, { f, dur: d, vol, a: 0.003, r: 0.012 });
      tone(c, G.spk, at, nodes, { f: f * 2, dur: d, vol: vol * 0.12, a: 0.003, r: 0.012 });
      at += d;
    });
    return at;
  }
  // squelch: band-passed noise with a crackle riding on it
  function squelchTail(c, t, nodes, dur, vol, rough) {
    const g = burst(c, t, nodes, { dur, vol, a: 0.003, r: dur * 0.72 }, biq(c, 'highpass', 420, 0.7), biq(c, 'bandpass', 1900, 0.55));
    const cr = amp(c, 1);
    for (let x = t; x < t + dur; x += rnd(0.008, 0.022)) cr.gain.setValueAtTime(1 - Math.random() * rough, x);
    g.connect(cr); cr.connect(G.spk);
    return t + dur;
  }
  // a shred of a broken transmission: a noise splinter or a buzzy piece of a voice
  function garble(c, t, nodes, dur, vol) {
    if (Math.random() < 0.55) {
      burst(c, t, nodes, { dur, vol, a: 0.003, r: dur * 0.4 }, biq(c, 'bandpass', rnd(500, 2600), rnd(1.5, 5))).connect(G.spk);
    } else {
      const o = c.createOscillator(), g = amp(c, 0);
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(rnd(95, 160), t);
      o.frequency.linearRampToValueAtTime(rnd(90, 170), t + dur);
      env(g.gain, t, vol * 1.4, 0.004, dur * 0.5, dur * 0.45);
      chain(o, biq(c, 'bandpass', rnd(600, 1150), 4), g, G.spk);
      o.start(t); o.stop(t + dur + 0.05);
      nodes.push(o);
    }
    return t + dur;
  }

  /* ─────────────── one-shots: (ctx, t, nodes, opts) → end time ─────────────── */
  const GUN = {
    //          crack  tail   thump  drive  bright  level
    pistol:   [0.090, 0.16, 86, 9, 2600, 0.90],
    smg:      [0.060, 0.10, 78, 8, 2800, 0.75],
    rifle:    [0.110, 0.26, 70, 12, 3000, 1.00],
    shotgun:  [0.160, 0.32, 60, 14, 1800, 1.05],
    sniper:   [0.120, 0.55, 66, 14, 3200, 1.10],
    heavy:    [0.220, 0.60, 60, 18, 1500, 1.15],
    silenced: [0.035, 0.05, 88, 2, 1100, 0.35],
  };

  const S = {
    key(c, t, n, o) {     // soft rubber tick + a faint keypad beep
      burst(c, t, n, { dur: 0.012, vol: 0.26 * o.volume, a: 0.0008, r: 0.01 }, biq(c, 'bandpass', 3400, 1.4)).connect(G.bus);
      tone(c, G.bus, t, n, { f: 210, to: 120, dur: 0.028, vol: 0.2 * o.volume, a: 0.001 });
      tone(c, G.spk, t + 0.006, n, { f: 2350, dur: 0.03, vol: 0.022 * o.volume, type: 'square', a: 0.001, r: 0.012 });
      return t + 0.06;
    },
    error(c, t, n, o) {   // low double blip
      tone(c, G.spk, t, n, { f: 277, dur: 0.085, vol: 0.11 * o.volume, type: 'square', a: 0.003, r: 0.03 });
      return tone(c, G.spk, t + 0.12, n, { f: 233, dur: 0.1, vol: 0.11 * o.volume, type: 'square', a: 0.003, r: 0.04 });
    },
    toggle(c, t, n, o) {
      click(c, t, n, 0.09 * o.volume);
      return tone(c, G.spk, t + 0.01, n, { f: 1450, dur: 0.045, vol: 0.09 * o.volume, a: 0.002, r: 0.02 });
    },
    boot(c, t, n, o) {    // two-note rise
      tone(c, G.spk, t, n, { f: 880, dur: 0.09, vol: 0.075 * o.volume, type: 'square', r: 0.02 });
      return tone(c, G.spk, t + 0.11, n, { f: 1320, dur: 0.15, vol: 0.075 * o.volume, type: 'square', r: 0.06 });
    },
    power_off(c, t, n, o) {   // falling blip
      click(c, t, n, 0.07 * o.volume);
      return tone(c, G.spk, t + 0.01, n, { f: 1150, to: 260, dur: 0.26, vol: 0.12 * o.volume, type: 'triangle', r: 0.09 });
    },
    tx_start(c, t, n, o) {    // PTT switch, then the two-tone talk permit
      click(c, t, n, 0.08 * o.volume);
      return chirp(c, t + 0.012, n, [[1200, 0.055], [1800, 0.075]], 0.15 * o.volume);
    },
    rx_start(c, t, n, o) {    // squelch opens, then the far end's key-up chirp
      burst(c, t, n, { dur: 0.028, vol: 0.09 * o.volume, a: 0.002, r: 0.02 }, biq(c, 'highpass', 500, 0.7), biq(c, 'bandpass', 2100, 0.6)).connect(G.spk);
      return chirp(c, t + 0.03, n, [[1250, 0.05], [1850, 0.07]], 0.12 * o.volume);
    },
    tx_end(c, t, n, o) {      // key-down chirp, the switch, a breath of squelch
      const e = chirp(c, t, n, [[1800, 0.045], [1200, 0.06]], 0.12 * o.volume);
      click(c, e + 0.02, n, 0.06 * o.volume);
      return squelchTail(c, e, n, 0.05, 0.045 * o.volume, 0.3);
    },
    rx_end(c, t, n, o) {      // roger beep + a short squelch (squelch {q} adds the sized tail)
      const e = chirp(c, t, n, [[1550, 0.07]], 0.12 * o.volume);
      return squelchTail(c, e, n, 0.04, 0.06 * o.volume, 0.3);
    },
    squelch(c, t, n, o) {     // 90-420 ms, a worse link is longer and louder; starts after a roger beep
      const w = 1 - clamp(num(o.q, 0.8), 0, 1);
      return squelchTail(c, t + 0.085, n, 0.09 + w * 0.33, (0.09 + w * 0.15) * o.volume, 0.25 + w * 0.6);
    },
    lost(c, t, n, o) {        // one broken burst (the bed makes these by itself while lost)
      let at = t;
      for (let i = 0; i < 4; i++) at = garble(c, at + rnd(0.02, 0.08), n, rnd(0.04, 0.13), 0.12 * o.volume);
      return at;
    },
    emergency(c, t, n, o) {   // alternating 960 / 1280 Hz, three cycles
      let at = t;
      for (let i = 0; i < 6; i++) {
        tone(c, G.spk, at, n, { f: i % 2 ? 1280 : 960, dur: 0.17, vol: 0.06 * o.volume, type: 'square', a: 0.004, r: 0.015 });
        tone(c, G.spk, at, n, { f: i % 2 ? 1280 : 960, dur: 0.17, vol: 0.05 * o.volume, type: 'triangle', a: 0.004, r: 0.015 });
        at += 0.18;
      }
      return at;
    },
    place(c, t, n, o) {       // set down: a thunk, then the unit arms with two beeps
      tone(c, G.bus, t, n, { f: 130, to: 52, dur: 0.15, vol: 0.32 * o.volume, a: 0.001, r: 0.1 });
      burst(c, t, n, { dur: 0.04, vol: 0.18 * o.volume, a: 0.001, r: 0.035 }, biq(c, 'lowpass', 900, 0.7)).connect(G.bus);
      tone(c, G.spk, t + 0.2, n, { f: 1650, dur: 0.06, vol: 0.07 * o.volume, type: 'square', r: 0.02 });
      return tone(c, G.spk, t + 0.29, n, { f: 2200, dur: 0.08, vol: 0.07 * o.volume, type: 'square', r: 0.03 });
    },
    hack_tick(c, t, n, o) {
      click(c, t, n, 0.12 * o.volume);
      return tone(c, G.bus, t, n, { f: 2600, dur: 0.018, vol: 0.11 * o.volume, a: 0.001, r: 0.01 });
    },
    hack_ok(c, t, n, o) {     // rising arpeggio, the last note held
      [880, 1175, 1568].forEach((f, i) => tone(c, G.spk, t + i * 0.075, n, { f, dur: i === 2 ? 0.2 : 0.07, vol: 0.08 * o.volume, type: 'square', r: i === 2 ? 0.1 : 0.02 }));
      return t + 0.4;
    },
    hack_fail(c, t, n, o) {   // descending buzz
      burst(c, t, n, { dur: 0.12, vol: 0.08 * o.volume, r: 0.09 }, biq(c, 'bandpass', 900, 1.2)).connect(G.spk);
      return tone(c, G.spk, t, n, { f: 230, to: 105, dur: 0.38, vol: 0.13 * o.volume, type: 'sawtooth', r: 0.12 });
    },
    gunshot(c, t, n, o) {
      const k = GUN[o.kind] || GUN.pistol;
      const [crack, tail, thump, drive, bright, level] = k;
      const d = Math.max(0, num(o.d, 10));
      const near = clamp(1 - d / GUN_RADIUS, 0, 1);
      const q = clamp(num(o.q, 1), 0, 1);
      const lvl = (0.14 + 0.86 * Math.pow(near, 1.3)) * level * o.volume * (0.3 + 0.7 * q);
      if (lvl < 0.004) return t;
      // the talker's mic clips on the transient, the radio band-limits what is left (300-3400 Hz);
      // far shots arrive darker
      const sh = c.createWaveShaper(); sh.curve = curve(drive * (0.5 + near)); sh.oversample = '2x';
      const out = amp(c, lvl);
      chain(sh, biq(c, 'highpass', 300, 0.7), biq(c, 'lowpass', 2300 + 1100 * near, 0.7), out, G.spk);
      burst(c, t, n, { dur: crack, vol: 0.9, a: 0.0006, r: crack * 0.9 }, biq(c, 'bandpass', bright, 0.6)).connect(sh);
      tone(c, sh, t, n, { f: thump * 1.6, to: thump, dur: 0.09 + crack * 0.5, vol: 0.85, a: 0.001, r: 0.06 });
      burst(c, t + 0.012, n, { dur: tail, vol: 0.22 + 0.1 * (1 - near), a: 0.004, r: tail * 0.95 }, biq(c, 'lowpass', 1400, 0.5)).connect(sh);
      // a weak link chops pieces out of the report
      if (q < 0.6) for (let x = t + rnd(0.01, 0.04); x < t + crack + tail; x += rnd(0.02, 0.06)) out.gain.setValueAtTime(Math.random() < (0.6 - q) ? 0 : lvl, x);
      return t + crack + tail + 0.06;
    },
  };
  const ALIAS = { click: 'key', tick: 'key', beep: 'toggle', deny: 'error', denied: 'error', alert: 'emergency', shot: 'gunshot' };

  function play(name, opts = {}) {
    try {
      const key = ALIAS[name] || name;
      const fn = S[key];
      if (!fn) return false;
      const c = live();
      if (!c || !room(c)) return false;
      const o = Object.assign({}, opts || {});
      o.volume = clamp(num(o.volume, 1), 0, 1.5);
      if (o.volume <= 0) return false;
      const nodes = [];
      const t = c.currentTime + 0.012 + Math.max(0, num(o.delay, 0));
      const end = fn(c, t, nodes, o);
      voices.push({ end: end + 0.1, nodes });
      return true;
    } catch (e) {
      console.warn('[nzr] sfx', name, e);
      return false;
    }
  }

  /* ─────────────── beds (looped) ─────────────── */
  const beds = { hiss: null, jam: null, amb: null };
  const want = { hiss: 0, jam: 0, amb: 0, ambVol: 0.6, lost: false };
  const idleTimers = {};
  let lostTimer = null, ambTimer = null;

  function loopNoise(c, list) {
    const s = c.createBufferSource();
    s.buffer = G.noise; s.loop = true;
    s.start(c.currentTime, rnd(0, 1.9));
    list.push(s);
    return s;
  }
  function lfo(c, list, f, depth, param, type = 'sine') {
    const o = c.createOscillator(), g = amp(c, depth);
    o.type = type; o.frequency.value = f;
    o.connect(g); g.connect(param); o.start();
    list.push(o);
    return o;
  }
  const BUILD = {
    // hiss: band-passed noise with two slow, detuned flutters on the level and one on the tone
    hiss(c) {
      const list = [];
      const bp = biq(c, 'bandpass', 2300, 0.45), flutter = amp(c, 1), stutter = amp(c, 1), level = amp(c, 0);
      chain(loopNoise(c, list), biq(c, 'highpass', 380, 0.7), bp, flutter, stutter, level, G.spk);
      lfo(c, list, 0.43, 0.16, flutter.gain);
      lfo(c, list, 0.11, 0.1, flutter.gain);
      lfo(c, list, 0.27, 450, bp.frequency);
      return { list, level, stutter };
    },
    // jammer: noise whose level warbles at 3-7 Hz (the rate itself sweeps), plus a buzzy carrier
    // swept by the same warble, all a little overdriven
    jam(c) {
      const list = [];
      const body = amp(c, 0.55), level = amp(c, 0);
      const warble = c.createOscillator();
      warble.frequency.value = 5; warble.start(); list.push(warble);
      const wd = amp(c, 0.45); warble.connect(wd); wd.connect(body.gain);
      lfo(c, list, 0.17, 2, warble.frequency);
      const car = c.createOscillator();
      car.type = 'sawtooth'; car.frequency.value = 640; car.start(); list.push(car);
      const cd = amp(c, 170); warble.connect(cd); cd.connect(car.frequency);
      chain(car, biq(c, 'lowpass', 2000, 0.7), amp(c, 0.22), body);
      chain(loopNoise(c, list), biq(c, 'bandpass', 1300, 0.7), body);
      const grit = c.createWaveShaper(); grit.curve = curve(2.5);
      chain(body, grit, level, G.spk);
      return { list, level };
    },
    // cabin: a faint dark static floor (the chirps are scheduled one-shots)
    amb(c) {
      const list = [];
      const breathe = amp(c, 1), level = amp(c, 0);
      chain(loopNoise(c, list), biq(c, 'lowpass', 1600, 0.6), biq(c, 'highpass', 180, 0.7), breathe, level, G.spk);
      lfo(c, list, 0.07, 0.25, breathe.gain);
      return { list, level };
    },
  };
  function setBed(name, gain) {
    const c = gain > 0 ? ensure() : ctx;
    if (!c || !G) return;
    try {
      let b = beds[name];
      if (!b && gain > 0) b = beds[name] = BUILD[name](c);
      if (!b) return;
      const now = c.currentTime;
      b.level.gain.cancelScheduledValues(now);
      b.level.gain.setTargetAtTime(Math.max(0, gain), now, gain > 0 ? 0.12 : 0.25);
      clearTimeout(idleTimers[name]);
      if (gain <= 0) {
        idleTimers[name] = setTimeout(() => {
          if (beds[name] !== b || (name === 'hiss' ? want.hiss : name === 'jam' ? want.jam : want.amb) > 0) return;
          b.list.forEach(s => { try { s.stop(); } catch (_) { /* already stopped */ } });
          try { b.level.disconnect(); } catch (_) { /* gone */ }
          beds[name] = null;
        }, BED_IDLE_MS);
      }
    } catch (e) { console.warn('[nzr] sfx bed', name, e); }
  }

  // while the link is lost: the hiss stutters and broken shreds come through
  function lostTick() {
    lostTimer = null;
    const c = ctx && ctx.state === 'running' ? ctx : null;
    if (!want.lost || want.hiss <= 0) {
      if (c && beds.hiss) beds.hiss.stutter.gain.setTargetAtTime(1, c.currentTime, 0.05);
      return;
    }
    if (c && G) {
      try {
        const t = c.currentTime + 0.01;
        if (beds.hiss) beds.hiss.stutter.gain.setValueAtTime(rnd(0.12, 1), t);
        if (Math.random() < 0.7 && room(c)) {
          const n = [];
          const end = garble(c, t, n, rnd(0.04, 0.16), clamp(want.hiss * 0.5, 0.05, 0.16));
          voices.push({ end, nodes: n });
        }
      } catch (_) { /* skip this tick */ }
    }
    lostTimer = setTimeout(lostTick, rnd(90, 260));
  }

  // cabin chirps: somebody keys up somewhere on the band every 6-20 s
  function ambTick() {
    ambTimer = null;
    if (!(want.amb > 0)) return;
    const c = ctx && ctx.state === 'running' ? ctx : null;
    if (c && G && room(c)) {
      try {
        const n = [], v = clamp(want.ambVol, 0, 1);
        let t = c.currentTime + 0.02;
        if (Math.random() < 0.4) t = chirp(c, t, n, [[1250, 0.045], [1850, 0.06]], 0.035 * v) + 0.02;
        if (Math.random() < 0.35) { const e = t + rnd(0.35, 1.1); while (t < e) t = garble(c, t + rnd(0.01, 0.05), n, rnd(0.05, 0.14), 0.03 * v); }
        const end = squelchTail(c, t, n, rnd(0.12, 0.34), 0.05 * v, rnd(0.3, 0.7));
        voices.push({ end, nodes: n });
      } catch (_) { /* skip this one */ }
    }
    ambTimer = setTimeout(ambTick, rnd(6000, 20000));
  }

  function rx(d = {}) {
    d = d || {};
    const active = d.active === true || num(d.active, 0) > 0;
    const q = clamp(num(d.worstQ, 1), 0, 1);
    const gain = active ? clamp(num(d.gain, Math.pow(1 - q, 1.6) * 0.35), 0, 1) : 0;
    want.hiss = gain;
    want.lost = active && d.lost === true;
    setBed('hiss', gain * BED_HISS + (want.lost ? 0.03 : 0));
    if (want.lost && !lostTimer) lostTick();
  }
  function noise(gain) {
    if (gain && typeof gain === 'object') gain = gain.gain;
    want.jam = clamp(num(gain, 0), 0, 1);
    setBed('jam', want.jam * BED_JAM);
  }
  function ambient(on, volume) {
    if (on && typeof on === 'object') { volume = on.volume; on = on.on; }
    want.amb = on ? 1 : 0;
    want.ambVol = clamp(num(volume, want.ambVol), 0, 1);
    setBed('amb', want.amb * want.ambVol * BED_AMB);
    clearTimeout(ambTimer); ambTimer = null;
    if (want.amb) ambTimer = setTimeout(ambTick, rnd(2500, 7000));
  }

  /* ─────────────── gunfire through an open mic ─────────────── */
  function gunfire(shots, q, volume) {
    if (shots && !Array.isArray(shots) && typeof shots === 'object') { q = shots.q; volume = shots.volume; shots = shots.shots; }
    if (!Array.isArray(shots) || !shots.length) return 0;
    const c = live();
    if (!c) return 0;
    const list = shots.slice(0, MAX_SHOTS).filter(s => s && typeof s === 'object');
    // dt is in ms (GetGameTimer deltas); a batch written in seconds is recognised by its size
    const maxDt = list.reduce((m, s) => Math.max(m, num(s.dt, 0)), 0);
    const unit = maxDt > 0 && maxDt <= 2 && list.some(s => num(s.dt, 0) % 1 !== 0) ? 1 : 0.001;
    const base = c.currentTime + JITTER;
    let n = 0;
    list.forEach(s => {
      if (!room(c)) return;
      const nodes = [];
      try {
        const t = base + clamp(num(s.dt, 0) * unit, 0, 3) + rnd(0, 0.006);
        const end = S.gunshot(c, t, nodes, { kind: String(s.kind || 'pistol'), d: s.d, q, volume: clamp(num(volume, 1), 0, 1.5) });
        voices.push({ end, nodes });
        n++;
      } catch (_) { /* one bad shot never stops the rest */ }
    });
    return n;
  }

  function volume(v) {
    st.vol = clamp(num(v, st.vol), 0, 1);
    if (G && ctx) G.bus.gain.setTargetAtTime(st.vol, ctx.currentTime, 0.05);
    return st.vol;
  }
  function stop(name = 'all') {
    if (name === 'hiss' || name === 'rx' || name === 'all') rx({ active: 0 });
    if (name === 'jam' || name === 'noise' || name === 'jammer' || name === 'all') noise(0);
    if (name === 'ambient' || name === 'all') ambient(false);
    if (name === 'all') {
      voices.splice(0).forEach(v => v.nodes.forEach(s => { try { s.stop(); } catch (_) { /* done */ } }));
    }
  }
  function unlock() { ensure(); }

  NZR.sfx = {
    stub: false, play, stop, volume, unlock, rx, noise, ambient, gunfire,
    names: [...Object.keys(S)],
    get clicks() { return st.clicks; },
    state() { return { ctx: ctx ? ctx.state : 'none', voices: voices.length, beds: Object.keys(beds).filter(k => beds[k]), vol: st.vol, want: Object.assign({}, want) }; },
    _graph() { ensure(); return G; },
  };

  /* ─────────────── '_core' messages from Lua ─────────────── */
  NZR.onCore('*', () => unlock());
  NZR.onCore('sfx', d => { if (d && d.name) play(String(d.name), d); });
  NZR.onCore('rx', d => rx(d));
  NZR.onCore('noise', d => noise(d && d.gain));
  NZR.onCore('ambient', d => ambient(!!(d && d.on), d && d.volume));
  NZR.onCore('gunfire', d => { if (d) gunfire(d.shots, num(d.q, 1), num(d.volume, 1)); });
  NZR.onCore('config', d => {
    if (!d) return;
    if (d.sfx !== undefined) volume(d.sfx);
    if (d.clicks !== undefined) st.clicks = d.clicks !== false;
  });

  /* ═══════════════ PREVIEW: index.html?app=sfx (browser only) ═══════════════ */
  if (NZR.inGame) return;

  const CSS = `
  .sfxw{position:absolute;inset:0;display:grid;place-items:center;padding:24px}
  .sfxb{position:relative;width:min(700px,100%);padding:18px 20px 14px;display:flex;flex-direction:column;gap:14px;animation:nzr-pop 220ms cubic-bezier(.2,.7,.2,1) both}
  .sfxb .hd{display:flex;align-items:center;gap:12px}
  .sfxb .hd b{display:block;font-size:14px;font-weight:600;color:var(--white);letter-spacing:.02em}
  .sfxb .hd span{display:block;font-size:11px;color:var(--ink-3);font-weight:300;margin-top:3px}
  .sfxb .hd .ctx{margin-left:auto}
  .sfxb .scope{position:relative;height:74px;border-radius:8px;background:var(--inset);border:1px solid var(--line-soft);overflow:hidden}
  .sfxb .scope canvas{position:absolute;inset:0;width:100%;height:100%}
  .sfxb .scope::after{content:'';position:absolute;inset:0;pointer-events:none;background:repeating-linear-gradient(90deg,rgba(255,255,255,.035) 0 1px,transparent 1px 56px),repeating-linear-gradient(0deg,rgba(255,255,255,.035) 0 1px,transparent 1px 18px)}
  .sfxb .grp{display:grid;grid-template-columns:118px 1fr;gap:10px;align-items:start}
  .sfxb .grp > .nzr-label{padding-top:8px}
  .sfxb .btns{display:flex;flex-wrap:wrap;gap:6px}
  .sfxb .btns button{height:27px;padding:0 10px;border-radius:4px;border:1px solid var(--line);color:var(--ink-2);font:500 11px var(--mono);transition:all var(--fast)}
  .sfxb .btns button:hover{border-color:var(--teal-edge);color:var(--teal-hi);background:var(--teal-wash)}
  .sfxb .btns button.hit{border-color:var(--teal);color:var(--on-teal);background:var(--teal)}
  .sfxb .beds{display:grid;grid-template-columns:1fr 1fr;gap:10px 22px;padding:12px 14px;border-radius:10px;background:var(--inset);border:1px solid var(--line-hair)}
  .sfxb .bed{display:flex;flex-direction:column;gap:7px}
  .sfxb .bed .t{display:flex;align-items:center;justify-content:space-between;gap:10px}
  .sfxb .bed .t b{font-size:12px;font-weight:600;color:var(--white)}
  .sfxb .bed .t small{font-size:10.5px;color:var(--ink-3);font-weight:300}
  .sfxb .ft{display:flex;align-items:center;gap:14px;padding-top:10px;border-top:1px solid var(--line-hair)}
  .sfxb .ft .nz-sig{margin-left:auto}`;

  let scopeRaf = 0;
  const benchLabel = n => {
    const [a, b] = n.split(':');
    if (a === 'gun') return b;
    if (a === 'burst') return `burst · ${b}`;
    if (a === 'squelch') return `squelch q ${b}`;
    return a;
  };
  function bench(el) {
    if (!document.getElementById('nzr-sfx-bench-css')) {
      const s = document.createElement('style'); s.id = 'nzr-sfx-bench-css'; s.textContent = CSS; document.head.appendChild(s);
    }
    el.innerHTML = '';
    const shell = NZR.el('div', 'sfxw');
    const card = NZR.el('div', 'sfxb nzr-hud solid nzr-brk nzr-int');
    const groups = [
      ['Device', ['key', 'error', 'toggle', 'boot', 'power_off']],
      ['Link', ['tx_start', 'tx_end', 'rx_start', 'rx_end', 'squelch:0.9', 'squelch:0.45', 'squelch:0.1', 'lost']],
      ['Alerts & tools', ['emergency', 'place', 'hack_tick', 'hack_ok', 'hack_fail']],
      ['Gunfire', ['gun:pistol', 'gun:smg', 'gun:rifle', 'gun:shotgun', 'gun:sniper', 'gun:heavy', 'gun:silenced', 'burst:near', 'burst:far']],
    ];
    card.innerHTML = `
      <div class="hd"><span class="nz-mark"></span><div><b>Sound bench</b><span>NZR.sfx · every radio sound is synthesised, no audio files</span></div><span class="ctx nzr-chip">audio idle</span></div>
      <div class="scope"><canvas></canvas></div>
      ${groups.map(([g, list]) => `<div class="grp"><span class="nzr-label">${NZR.esc(g)}</span><div class="btns">${list.map(n => `<button data-s="${n}">${NZR.esc(benchLabel(n))}</button>`).join('')}</div></div>`).join('')}
      <div class="beds">
        <div class="bed"><div class="t"><b>Receiving</b><small>hiss bed · flutter · lost stutter</small><span data-k="rxon"></span></div><span data-k="q"></span></div>
        <div class="bed"><div class="t"><b>Jammer nearby</b><small>noise + swept warble</small></div><span data-k="jam"></span></div>
        <div class="bed"><div class="t"><b>Cabin ambience</b><small>static + chirps every 6-20 s</small><span data-k="amb"></span></div><span data-k="ambv"></span></div>
        <div class="bed"><div class="t"><b>Master</b><small>Config.Audio.sfx</small></div><span data-k="vol"></span></div>
      </div>
      <div class="ft nz-hints"><span><kbd>LMB</kbd>Play</span><span><kbd>SPACE</kbd>Stop all</span><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span></div>`;
    shell.appendChild(card);
    el.appendChild(shell);
    const k = s => card.querySelector(`[data-k="${s}"]`);
    let rxOn = false, q = 0.7;
    const pushRx = () => rx({ active: rxOn ? 1 : 0, worstQ: q, lost: q < 0.15 });
    NZR.ui.Toggle(k('rxon'), { on: false, onChange: v => { rxOn = v; pushRx(); } });
    NZR.ui.Slider(k('q'), { min: 0, max: 100, value: 70, format: v => `q ${(v / 100).toFixed(2)}`, onChange: v => { q = v / 100; pushRx(); } });
    NZR.ui.Slider(k('jam'), { min: 0, max: 100, value: 0, format: v => `${v}%`, onChange: v => noise(v / 100) });
    let ambOn = false, ambV = 70;
    NZR.ui.Toggle(k('amb'), { on: false, onChange: v => { ambOn = v; ambient(ambOn, ambV / 100); if (v) play('rx_start', { volume: 0.4 }); } });
    NZR.ui.Slider(k('ambv'), { min: 0, max: 100, value: 70, format: v => `${v}%`, onChange: v => { ambV = v; if (ambOn) ambient(true, v / 100); } });
    NZR.ui.Slider(k('vol'), { min: 0, max: 100, value: Math.round(st.vol * 100), format: v => `${v}%`, onChange: v => volume(v / 100) });

    const burstDemo = far => {
      const kinds = ['rifle', 'rifle', 'pistol', 'smg', 'smg', 'smg', 'shotgun', 'pistol'];
      let dt = 0;
      return kinds.map((kind, i) => { dt += i ? (kind === 'smg' ? 85 : rnd(160, 420)) : 0; return { dt: Math.round(dt), kind, d: far ? rnd(35, 58) : rnd(2, 14) }; });
    };
    card.querySelector('.btns') && card.addEventListener('click', e => {
      const b = e.target.closest('button[data-s]');
      if (!b) return;
      unlock();
      const [n, arg] = b.dataset.s.split(':');
      if (n === 'squelch') play('squelch', { q: Number(arg) });
      else if (n === 'gun') gunfire([{ dt: 0, kind: arg, d: 6 }], 1, 1);
      else if (n === 'burst') gunfire(burstDemo(arg === 'far'), arg === 'far' ? 0.55 : 0.95, 1);
      else play(n);
      b.classList.add('hit'); setTimeout(() => b.classList.remove('hit'), 160);
    });
    const ctxChip = card.querySelector('.ctx');
    const cv = card.querySelector('.scope canvas');
    let an = null, buf = null;
    const draw = () => {
      scopeRaf = requestAnimationFrame(draw);
      const s = ctx ? ctx.state : 'none';
      const label = s === 'running' ? 'audio running' : s === 'suspended' ? 'click to start audio' : 'audio idle';
      if (ctxChip.textContent !== label) { ctxChip.textContent = label; ctxChip.className = `ctx nzr-chip ${s === 'running' ? 'teal' : ''}`; }
      if (!an && G && ctx) {
        try { an = ctx.createAnalyser(); an.fftSize = 2048; G.comp.connect(an); buf = new Float32Array(an.fftSize); } catch (_) { an = null; }
      }
      const { w, h } = NZR.fitCanvas(cv);
      const g = cv.getContext('2d');
      g.clearRect(0, 0, w, h);
      g.lineWidth = Math.max(1, h / 60);
      g.strokeStyle = '#0fd4c4';
      g.shadowColor = 'rgba(15,212,196,.6)'; g.shadowBlur = 6;
      g.beginPath();
      for (let i = 0; i < 256; i++) {
        const v = an && buf ? buf[i * 8] || 0 : 0;
        const x = (i / 255) * w, y = h / 2 - v * h * 0.9;
        if (i) g.lineTo(x, y); else g.moveTo(x, y);
      }
      g.stroke();
      if (an && buf) an.getFloatTimeDomainData(buf);
    };
    cancelAnimationFrame(scopeRaf);
    draw();
  }

  NZR.app('sfx', {
    escClose: false,
    keys: { ' ': () => stop('all') },
    open() { bench(this.el); },
    close() { cancelAnimationFrame(scopeRaf); stop('all'); },
    preview() { NZR.open('sfx', {}); },
  });
})();
