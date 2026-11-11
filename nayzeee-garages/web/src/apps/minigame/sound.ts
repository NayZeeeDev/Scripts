/**
 * Minigame sounds, synthesised with WebAudio (no audio files): pin clicks, the set "thunk",
 * dropping pins, the snapping pick, wire sparks, splices and the reader's beeps. Quiet by
 * design (the game's own sound keeps playing). Every call is safe when audio is unavailable.
 */

type Ctx = AudioContext;
let ctx: Ctx | null = null;
let master: GainNode | null = null;
let noiseBuf: AudioBuffer | null = null;

function audio(): Ctx | null {
  if (ctx) {
    if (ctx.state === 'suspended') void ctx.resume().catch(() => undefined);
    return ctx;
  }
  try {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = 0.32;
    master.connect(ctx.destination);
    return ctx;
  } catch {
    return null;
  }
}

function noise(c: Ctx): AudioBuffer {
  if (noiseBuf) return noiseBuf;
  const len = Math.floor(c.sampleRate * 0.5);
  noiseBuf = c.createBuffer(1, len, c.sampleRate);
  const data = noiseBuf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  return noiseBuf;
}

/** Short filtered noise burst (metal ticks, sparks). */
function burst(freq: number, q: number, dur: number, gain: number, delay = 0, type: BiquadFilterType = 'bandpass') {
  const c = audio();
  if (!c || !master) return;
  const t = c.currentTime + delay;
  const src = c.createBufferSource();
  src.buffer = noise(c);
  const f = c.createBiquadFilter();
  f.type = type;
  f.frequency.value = freq;
  f.Q.value = q;
  const g = c.createGain();
  g.gain.setValueAtTime(gain, t);
  g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
  src.connect(f).connect(g).connect(master);
  src.start(t, Math.random() * 0.3, dur + 0.02);
}

/** Short tone with a pitch slide. */
function tone(from: number, to: number, dur: number, gain: number, delay = 0, type: OscillatorType = 'sine') {
  const c = audio();
  if (!c || !master) return;
  const t = c.currentTime + delay;
  const o = c.createOscillator();
  o.type = type;
  o.frequency.setValueAtTime(from, t);
  o.frequency.exponentialRampToValueAtTime(Math.max(20, to), t + dur);
  const g = c.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(gain, t + 0.006);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(master);
  o.start(t);
  o.stop(t + dur + 0.02);
}

export const sfx = {
  /** wake the audio context on the first key press (autoplay rules) */
  unlock() {
    audio();
  },
  /** the binding pin reached the shear line */
  click() {
    burst(4200, 9, 0.035, 0.9);
    tone(2600, 1900, 0.03, 0.08, 0, 'triangle');
  },
  /** a pin set: the plug gives a little */
  set() {
    burst(1500, 5, 0.07, 0.8);
    tone(420, 260, 0.09, 0.12, 0, 'triangle');
  },
  /** springy lift of a free pin */
  spring() {
    burst(6200, 14, 0.05, 0.22);
  },
  /** tension wrench applied */
  tension() {
    burst(900, 3, 0.06, 0.35);
  },
  /** tension released: the set pins rattle down */
  drop(count: number) {
    for (let i = 0; i < Math.max(1, count); i++) burst(3200 + Math.random() * 1600, 8, 0.04, 0.5, i * 0.045);
  },
  /** too much force: the pick snaps */
  snap() {
    burst(5200, 2.5, 0.12, 1.4, 0, 'highpass');
    tone(900, 120, 0.22, 0.2, 0.01, 'sawtooth');
    burst(2400, 6, 0.05, 0.6, 0.14);
  },
  /** the plug turns: unlocked */
  open() {
    burst(1100, 4, 0.12, 0.7);
    tone(330, 520, 0.16, 0.1, 0.05, 'triangle');
    tone(520, 780, 0.2, 0.08, 0.17, 'sine');
  },
  /** a wrong contact sparks */
  spark() {
    burst(5600, 1.4, 0.18, 1.2, 0, 'highpass');
    burst(2200, 3, 0.08, 0.6, 0.05);
    tone(120, 70, 0.16, 0.14, 0, 'square');
  },
  /** a matching pair spliced */
  splice() {
    burst(2600, 6, 0.05, 0.5);
    tone(660, 880, 0.08, 0.08, 0.03, 'sine');
  },
  /** the engine is live */
  ignition() {
    tone(180, 360, 0.25, 0.1, 0, 'sawtooth');
    tone(880, 1320, 0.12, 0.07, 0.18, 'sine');
  },
  /** reader: a tuning step */
  tick() {
    tone(1800, 1700, 0.018, 0.035, 0, 'square');
  },
  /** reader: row change */
  select() {
    tone(1200, 1400, 0.04, 0.05, 0, 'sine');
  },
  /** reader: verify started */
  verify() {
    tone(900, 900, 0.07, 0.06, 0, 'square');
    tone(1350, 1350, 0.07, 0.06, 0.1, 'square');
  },
  /** reader: signal locked */
  locked() {
    tone(988, 988, 0.09, 0.09, 0, 'sine');
    tone(1319, 1319, 0.16, 0.09, 0.1, 'sine');
  },
  /** reader: no lock */
  denied() {
    tone(330, 220, 0.24, 0.12, 0, 'square');
  },
};
