// Web Audio: synthesized UI cues + procedural ambience soundscapes. No files.

export type Cue = 'hover' | 'click' | 'whoosh' | 'confirm' | 'error' | 'deploy' | 'back' | 'tick';

const PRESETS = ['city', 'rooftop', 'club', 'street', 'ocean', 'airport', 'helipad', 'garage', 'skydive'] as const;
type Preset = (typeof PRESETS)[number];

const THEME_PRESET: Record<string, Preset> = {
  supercar: 'city', penthouse: 'rooftop', studio: 'club', boutique: 'street',
  beach: 'ocean', jet: 'airport', helipad: 'helipad', garage: 'garage', skydive: 'skydive',
};

let ctx: AudioContext | null = null;
let uiBus: GainNode | null = null;
let ambBus: GainNode | null = null;
const noiseCache: Record<string, AudioBuffer> = {};

const state = {
  muted: false,
  uiVolume: 0.6,
  ambVolume: 0.35,
  uiEnabled: true,
  ambEnabled: true,
};

function ac(): AudioContext | null {
  if (ctx) return ctx;
  try {
    const C = window.AudioContext || (window as any).webkitAudioContext;
    ctx = new C();
    uiBus = ctx.createGain();
    uiBus.gain.value = state.uiVolume;
    uiBus.connect(ctx.destination);
    ambBus = ctx.createGain();
    ambBus.gain.value = 0;
    ambBus.connect(ctx.destination);
  } catch { ctx = null; }
  return ctx;
}

function wake() {
  const c = ac();
  if (c && c.state === 'suspended') c.resume().catch(() => {});
  return c;
}

function noise(kind: 'white' | 'pink' | 'brown'): AudioBuffer | null {
  const c = ac();
  if (!c) return null;
  if (noiseCache[kind]) return noiseCache[kind];
  const len = c.sampleRate * 4;
  const buf = c.createBuffer(1, len, c.sampleRate);
  const d = buf.getChannelData(0);
  let b0 = 0, b1 = 0, b2 = 0, last = 0;
  for (let i = 0; i < len; i++) {
    const w = Math.random() * 2 - 1;
    if (kind === 'white') d[i] = w;
    else if (kind === 'pink') {
      b0 = 0.99765 * b0 + w * 0.099046; b1 = 0.963 * b1 + w * 0.2965164; b2 = 0.57 * b2 + w * 1.0526913;
      d[i] = (b0 + b1 + b2 + w * 0.1848) * 0.18;
    } else {
      last = (last + 0.02 * w) / 1.02;
      d[i] = last * 3.2;
    }
  }
  noiseCache[kind] = buf;
  return buf;
}

// ── UI cues ───────────────────────────────────────────────────────────────
function env(g: GainNode, t: number, peak: number, attack: number, dur: number) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
}

function tone(type: OscillatorType, f0: number, f1: number, dur: number, peak: number, delay = 0) {
  const c = ctx!;
  const t = c.currentTime + delay;
  const o = c.createOscillator();
  const g = c.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
  env(g, t, peak, 0.004, dur);
  o.connect(g).connect(uiBus!);
  o.start(t);
  o.stop(t + dur + 0.02);
}

function burst(f0: number, f1: number, dur: number, peak: number, q = 1.2) {
  const c = ctx!;
  const t = c.currentTime;
  const src = c.createBufferSource();
  src.buffer = noise('white');
  const bp = c.createBiquadFilter();
  bp.type = 'bandpass';
  bp.Q.value = q;
  bp.frequency.setValueAtTime(f0, t);
  bp.frequency.exponentialRampToValueAtTime(f1, t + dur);
  const g = c.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + dur * 0.35);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(bp).connect(g).connect(uiBus!);
  src.start(t, Math.random() * 2);
  src.stop(t + dur + 0.05);
}

let lastHover = 0;
export function cue(name: Cue) {
  if (state.muted || !state.uiEnabled || state.uiVolume <= 0) return;
  const c = wake();
  if (!c || !uiBus) return;
  try {
    switch (name) {
      case 'hover': {
        const now = performance.now();
        if (now - lastHover < 45) return;
        lastHover = now;
        tone('sine', 2600, 2200, 0.035, 0.035);
        break;
      }
      case 'tick': tone('triangle', 1800, 1500, 0.03, 0.05); break;
      case 'click': tone('triangle', 1100, 620, 0.07, 0.12); tone('sine', 220, 180, 0.06, 0.05); break;
      case 'back': tone('triangle', 700, 420, 0.08, 0.1); break;
      case 'whoosh': burst(380, 2400, 0.32, 0.12, 0.8); break;
      case 'confirm': tone('sine', 660, 660, 0.12, 0.09); tone('sine', 990, 990, 0.2, 0.08, 0.07); break;
      case 'error': tone('square', 196, 150, 0.16, 0.05); tone('square', 185, 140, 0.2, 0.04, 0.09); break;
      case 'deploy':
        burst(200, 3800, 0.9, 0.16, 0.6);
        tone('sawtooth', 110, 440, 0.7, 0.04);
        tone('sine', 880, 1320, 0.5, 0.06, 0.25);
        break;
    }
  } catch { /* ignore */ }
}

// ── Ambience ─────────────────────────────────────────────────────────────
interface Running { stop: () => void }
let running: Running | null = null;
let runningKey = '';
let mediaEl: HTMLAudioElement | null = null;
let mediaFade: number | undefined;

function ambTarget() {
  return state.muted || !state.ambEnabled ? 0 : state.ambVolume;
}

function fadeBus(to: number, time = 1.4) {
  if (!ctx || !ambBus) return;
  const t = ctx.currentTime;
  ambBus.gain.cancelScheduledValues(t);
  ambBus.gain.setValueAtTime(ambBus.gain.value, t);
  ambBus.gain.linearRampToValueAtTime(to, t + time);
}

function fadeMedia(to: number, ms = 1400, then?: () => void) {
  if (!mediaEl) return then?.();
  window.clearInterval(mediaFade);
  const el = mediaEl;
  const from = el.volume;
  const start = performance.now();
  mediaFade = window.setInterval(() => {
    const k = Math.min(1, (performance.now() - start) / ms);
    el.volume = Math.max(0, Math.min(1, from + (to - from) * k));
    if (k >= 1) { window.clearInterval(mediaFade); then?.(); }
  }, 50);
}

function loopNoise(kind: 'white' | 'pink' | 'brown', out: AudioNode, nodes: AudioNode[]) {
  const c = ctx!;
  const s = c.createBufferSource();
  s.buffer = noise(kind);
  s.loop = true;
  s.connect(out);
  s.start(0, Math.random() * 3);
  nodes.push(s);
  return s;
}

function filt(type: BiquadFilterType, f: number, q = 0.7) {
  const b = ctx!.createBiquadFilter();
  b.type = type; b.frequency.value = f; b.Q.value = q;
  return b;
}

function gain(v: number) { const g = ctx!.createGain(); g.gain.value = v; return g; }

function lfo(freq: number, depth: number, target: AudioParam, nodes: AudioNode[], type: OscillatorType = 'sine') {
  const o = ctx!.createOscillator();
  o.type = type; o.frequency.value = freq;
  const g = gain(depth);
  o.connect(g).connect(target);
  o.start();
  nodes.push(o);
}

function osc(type: OscillatorType, f: number, out: AudioNode, nodes: AudioNode[], detune = 0) {
  const o = ctx!.createOscillator();
  o.type = type; o.frequency.value = f; o.detune.value = detune;
  o.connect(out); o.start(); nodes.push(o);
  return o;
}

function build(preset: Preset): Running {
  const c = ctx!;
  const out = ambBus!;
  const nodes: AudioNode[] = [];
  const timers: number[] = [];
  let alive = true;
  const every = (minMs: number, maxMs: number, fn: () => void) => {
    const loop = () => {
      if (!alive) return;
      timers.push(window.setTimeout(() => { if (!alive) return; fn(); loop(); }, minMs + Math.random() * (maxMs - minMs)));
    };
    loop();
  };
  const carPass = (peak = 0.35, f = 650) => {
    const t = c.currentTime;
    const s = c.createBufferSource(); s.buffer = noise('pink');
    const bp = filt('bandpass', f, 1.4);
    bp.frequency.setValueAtTime(f * 1.25, t);
    bp.frequency.exponentialRampToValueAtTime(f * 0.6, t + 3.2);
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(peak, t + 1.5);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 3.4);
    s.connect(bp).connect(g).connect(out);
    s.start(t, Math.random() * 2); s.stop(t + 3.5);
  };
  const wind = (level: number, f = 520) => {
    const g = gain(level);
    const bp = filt('bandpass', f, 0.6);
    loopNoise('pink', bp, nodes);
    bp.connect(g).connect(out);
    lfo(0.09, level * 0.55, g.gain, nodes);
    lfo(0.05, f * 0.4, bp.frequency, nodes);
    nodes.push(g, bp);
  };

  switch (preset) {
    case 'city': {
      const lp = filt('lowpass', 320); const g = gain(0.55);
      loopNoise('brown', lp, nodes); lp.connect(g).connect(out);
      const r = gain(0.05); osc('sine', 46, r, nodes); r.connect(out);
      wind(0.05, 900);
      every(3500, 9000, () => carPass(0.28 + Math.random() * 0.15, 500 + Math.random() * 300));
      nodes.push(lp, g, r);
      break;
    }
    case 'rooftop': {
      wind(0.32, 460);
      wind(0.12, 1400);
      const lp = filt('lowpass', 180); const g = gain(0.25);
      loopNoise('brown', lp, nodes); lp.connect(g).connect(out);
      every(7000, 14000, () => carPass(0.08, 400));
      nodes.push(lp, g);
      break;
    }
    case 'club': {
      const muffle = filt('lowpass', 260, 0.9); const mg = gain(0.9);
      muffle.connect(mg).connect(out);
      const pad = filt('lowpass', 420, 1); const pg = gain(0.035);
      osc('sawtooth', 55, pad, nodes, -7); osc('sawtooth', 82.4, pad, nodes, 6); osc('sawtooth', 110, pad, nodes, 3);
      pad.connect(pg).connect(out);
      lfo(0.07, 160, pad.frequency, nodes);
      const room = filt('lowpass', 500); const rg = gain(0.12);
      loopNoise('brown', room, nodes); room.connect(rg).connect(out);
      const beat = 60 / 110;
      let next = c.currentTime + 0.1;
      const kick = (t: number) => {
        const o = c.createOscillator(); const g = c.createGain();
        o.frequency.setValueAtTime(130, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.18);
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.7, t + 0.006);
        g.gain.exponentialRampToValueAtTime(0.0001, t + 0.32);
        o.connect(g).connect(muffle); o.start(t); o.stop(t + 0.35);
      };
      const sched = window.setInterval(() => {
        if (!alive) return;
        while (next < c.currentTime + 0.25) { kick(next); next += beat; }
      }, 90);
      timers.push(sched);
      nodes.push(muffle, mg, pad, pg, room, rg);
      break;
    }
    case 'street': {
      const lp = filt('lowpass', 520); const g = gain(0.38);
      loopNoise('brown', lp, nodes); lp.connect(g).connect(out);
      const bp = filt('bandpass', 1100, 2.2); const cg = gain(0.0);
      loopNoise('pink', bp, nodes); bp.connect(cg).connect(out);
      every(140, 320, () => {
        const t = c.currentTime;
        cg.gain.setTargetAtTime(0.02 + Math.random() * 0.07, t, 0.06);
        bp.frequency.setTargetAtTime(800 + Math.random() * 900, t, 0.1);
      });
      every(4000, 10000, () => carPass(0.22, 600));
      nodes.push(lp, g, bp, cg);
      break;
    }
    case 'ocean': {
      const lp = filt('lowpass', 850); const g = gain(0.05);
      loopNoise('white', lp, nodes); lp.connect(g).connect(out);
      const base = filt('lowpass', 260); const bg = gain(0.25);
      loopNoise('brown', base, nodes); base.connect(bg).connect(out);
      const swell = () => {
        const t = c.currentTime; const len = 5 + Math.random() * 3;
        g.gain.cancelScheduledValues(t);
        g.gain.setValueAtTime(g.gain.value, t);
        g.gain.linearRampToValueAtTime(0.32 + Math.random() * 0.12, t + len * 0.42);
        g.gain.linearRampToValueAtTime(0.05, t + len);
        lp.frequency.setTargetAtTime(1300, t, len * 0.2);
        lp.frequency.setTargetAtTime(700, t + len * 0.45, len * 0.25);
      };
      swell();
      every(5500, 8500, swell);
      wind(0.05, 700);
      nodes.push(lp, g, base, bg);
      break;
    }
    case 'airport': {
      const hum = filt('lowpass', 560, 1.2); const hg = gain(0.045);
      osc('sawtooth', 98, hum, nodes); osc('sawtooth', 147, hum, nodes, 8); osc('triangle', 196, hum, nodes);
      hum.connect(hg).connect(out);
      lfo(0.2, 0.012, hg.gain, nodes);
      const wg = gain(0.0035); osc('sine', 3150, wg, nodes); wg.connect(out);
      lfo(0.13, 0.002, wg.gain, nodes);
      wind(0.18, 600);
      const lp = filt('lowpass', 220); const g = gain(0.3);
      loopNoise('brown', lp, nodes); lp.connect(g).connect(out);
      nodes.push(hum, hg, wg, lp, g);
      break;
    }
    case 'helipad': {
      const lp = filt('lowpass', 240, 1); const rg = gain(0.28);
      loopNoise('brown', lp, nodes); lp.connect(rg).connect(out);
      lfo(6.1, 0.24, rg.gain, nodes);
      const thump = filt('lowpass', 90); const tg = gain(0.0);
      osc('sine', 52, thump, nodes); thump.connect(tg).connect(out);
      lfo(6.1, 0.05, tg.gain, nodes);
      const whine = gain(0.006); osc('triangle', 860, whine, nodes); whine.connect(out);
      wind(0.16, 650);
      nodes.push(lp, rg, thump, tg, whine);
      break;
    }
    case 'skydive': {
      // helicopter in flight, door open: roaring air rush + gusts + heavy rotor thump (~5.6 Hz)
      const rush = filt('bandpass', 900, 0.45); const rg = gain(0.34);
      loopNoise('white', rush, nodes); rush.connect(rg).connect(out);
      lfo(0.11, 0.08, rg.gain, nodes);
      lfo(0.07, 380, rush.frequency, nodes);
      const hiss = filt('highpass', 2600, 0.5); const hs = gain(0.05);
      loopNoise('pink', hiss, nodes); hiss.connect(hs).connect(out);
      wind(0.22, 420);
      every(2500, 6500, () => {               // gusts
        const t = c.currentTime; const len = 1.2 + Math.random() * 1.8;
        rg.gain.cancelScheduledValues(t);
        rg.gain.setValueAtTime(rg.gain.value, t);
        rg.gain.linearRampToValueAtTime(0.5 + Math.random() * 0.15, t + len * 0.4);
        rg.gain.linearRampToValueAtTime(0.32, t + len);
      });
      const rotor = filt('lowpass', 180, 1.1); const rot = gain(0.36);
      loopNoise('brown', rotor, nodes); rotor.connect(rot).connect(out);
      lfo(5.6, 0.34, rot.gain, nodes);
      const thump = filt('lowpass', 85); const tg = gain(0.0);
      osc('sine', 48, thump, nodes); thump.connect(tg).connect(out);
      lfo(5.6, 0.09, tg.gain, nodes);
      const turbine = gain(0.004); osc('triangle', 1240, turbine, nodes); turbine.connect(out);
      nodes.push(rush, rg, hiss, hs, rotor, rot, thump, tg, turbine);
      break;
    }
    case 'garage': {
      const lp = filt('lowpass', 200); const g = gain(0.22);
      loopNoise('brown', lp, nodes); lp.connect(g).connect(out);
      const hg = gain(0.012); osc('sine', 60, hg, nodes); osc('sine', 120, hg, nodes); hg.connect(out);
      const buzz = filt('bandpass', 120 * 8, 8); const bg = gain(0.006);
      osc('sawtooth', 120, buzz, nodes); buzz.connect(bg).connect(out);
      every(1800, 6000, () => {
        const t = c.currentTime; const o = c.createOscillator(); const dg = c.createGain();
        const f = 1100 + Math.random() * 700;
        o.frequency.setValueAtTime(f, t); o.frequency.exponentialRampToValueAtTime(f * 0.55, t + 0.07);
        dg.gain.setValueAtTime(0.0001, t); dg.gain.exponentialRampToValueAtTime(0.05, t + 0.004);
        dg.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
        o.connect(dg).connect(out); o.start(t); o.stop(t + 0.15);
      });
      every(9000, 18000, () => carPass(0.06, 300));
      nodes.push(lp, g, hg, buzz, bg);
      break;
    }
  }

  return {
    stop: () => {
      alive = false;
      timers.forEach((id) => { window.clearTimeout(id); window.clearInterval(id); });
      for (const n of nodes) {
        try { (n as AudioScheduledSourceNode).stop?.(); } catch { /* not a source */ }
        try { n.disconnect(); } catch { /* ignore */ }
      }
    },
  };
}

let xfade: number | undefined;
let xfadeOld: Running | null = null;

function stopProcedural(fade = true) {
  // a pending crossfade must not start its preset after a stop (or keep the old one alive)
  if (xfade !== undefined) { window.clearTimeout(xfade); xfade = undefined; }
  if (xfadeOld) { xfadeOld.stop(); xfadeOld = null; }
  const r = running;
  running = null;
  runningKey = '';
  if (!r) return;
  if (fade && ctx) {
    fadeBus(0, 1.0);
    window.setTimeout(() => r.stop(), 1100);
  } else r.stop();
}

function stopMedia(fade = true) {
  const el = mediaEl;
  if (!el) return;
  mediaEl = null;
  const end = () => { el.pause(); el.src = ''; };
  if (fade) {
    const from = el.volume; const start = performance.now();
    const id = window.setInterval(() => {
      const k = Math.min(1, (performance.now() - start) / 1000);
      el.volume = Math.max(0, from * (1 - k));
      if (k >= 1) { window.clearInterval(id); end(); }
    }, 50);
  } else end();
}

export interface AmbienceReq { ambience?: string | null; preset?: string; theme?: string; url?: string; muted?: boolean }

export function resolvePreset(req: AmbienceReq, themes?: { id: string; ambience?: { preset?: string; url?: string } }[]): { preset: Preset | null; url?: string } {
  const id = req.ambience || '';
  const theme = themes?.find((x) => x.id === (req.theme || id));
  const url = req.url || theme?.ambience?.url || undefined;
  const valid = (s?: string): s is Preset => !!s && (PRESETS as readonly string[]).includes(s);
  let p: string | undefined = req.preset || theme?.ambience?.preset;
  if (!p) p = valid(id) ? id : THEME_PRESET[id];
  return { preset: valid(p) ? p : id ? 'city' : null, url };
}

export function setAmbience(req: AmbienceReq, themes?: ThemeLike[]) {
  if (typeof req.muted === 'boolean') state.muted = req.muted;
  const { preset, url } = resolvePreset(req, themes);
  const key = url ? `url:${url}` : preset ? `p:${preset}` : '';
  if (!key || !state.ambEnabled) { stopAmbience(); return; }

  if (key === runningKey || (mediaEl && key === `url:${url}`)) { applyVolumes(); return; }

  if (url) {
    stopProcedural();
    stopMedia();
    const el = new Audio(url);
    el.loop = true; el.volume = 0;
    mediaEl = el;
    runningKey = key;
    el.play().catch(() => {});
    fadeMedia(ambTarget(), 1600);
    return;
  }
  const c = wake();
  if (!c || !ambBus) return;
  stopMedia();
  // a newer change supersedes a crossfade that's still pending
  if (xfade !== undefined) { window.clearTimeout(xfade); xfade = undefined; }
  const old = running || xfadeOld;
  running = null;
  if (old) {
    // crossfade: fade out the shared bus, rebuild, fade back in
    xfadeOld = old;
    fadeBus(0, 0.8);
    xfade = window.setTimeout(() => { xfade = undefined; old.stop(); xfadeOld = null; start(preset!); }, 850);
  } else start(preset!);
  runningKey = key;
}

type ThemeLike = { id: string; ambience?: { preset?: string; url?: string } };

function start(preset: Preset) {
  if (!ctx || !ambBus) return;
  running = build(preset);
  runningKey = `p:${preset}`;
  ambBus.gain.setValueAtTime(0, ctx.currentTime);
  fadeBus(ambTarget(), 1.8);
}

export function stopAmbience(fade = true) {
  stopProcedural(fade);
  stopMedia(fade);
}

function applyVolumes() {
  if (uiBus && ctx) uiBus.gain.setTargetAtTime(state.uiVolume, ctx.currentTime, 0.05);
  if (running) fadeBus(ambTarget(), 0.6);
  if (mediaEl) fadeMedia(ambTarget(), 600);
}

export function configureAudio(o: Partial<typeof state>) {
  Object.assign(state, o);
  if (!state.ambEnabled) stopAmbience();
  applyVolumes();
}

/** Lobby closed: stop everything and suspend the context so nothing runs. */
export function shutdownAudio() {
  stopAmbience(false);
  if (ctx && ctx.state === 'running') ctx.suspend().catch(() => {});
}
