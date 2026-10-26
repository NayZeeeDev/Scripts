/* ═══════════════════════════════════════════════════════════
   Audio engine

   A song arrives in one of two modes:
     file   → an <audio> element we own, routed through the full graph below.
     iframe → YouTube's embedded player. Its sound belongs to YouTube's frame and the browser
              will not let us process it, so only volume works (smoothed, never stepped).

   One "voice" per speaker, file mode:

     element → hp → low → mid → high      speaker voicing (every model sounds a little different)
             → bass → mids → treble       the player's own EQ
             → gate                       transport fades: play, pause, seek, cue, crossfade
             → air → muffle → thump       distance darkening, walls / cars, car bass that leaks out
             ├→ toPan (mono) → panner (HRTF) ─┐                a far speaker is one point in the world
             ├→ direct → align → balance ──────┴→ out → master  true stereo when you are at the source
             └→ room / hall / street sends → shared reverb buses → master

   master → glue compressor → limiter → soft clip → speakers

   Lua sends one spatial frame every Config.Audio.updateRate ms. Every AudioParam is ramped
   across that interval, so movement never zippers or steps.
   ═══════════════════════════════════════════════════════════ */
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-speaker';
function post(name, data) {
  return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
    .then(r => r.json()).catch(() => null);
}

const Engine = (() => {
  /* Built-in voicing per speaker. Config.Audio.voices (sent at init) overrides any of these.
     hp = low cut in Hz · low / mid / high = dB at lowHz (shelf) / midHz (peak, midQ) / highHz (shelf) */
  const FLAT = { hp: 20, low: 0, lowHz: 140, mid: 0, midHz: 1100, midQ: 0.7, high: 0, highHz: 6000 };
  const VOICES = {
    default: FLAT,
    nayzeee_audio_a: { hp: 35, low: 2.5, lowHz: 110, mid: -1.0, midHz: 650, midQ: 0.7, high: 1.5, highHz: 8000 },   // Pulse Tower: party bass, crisp top
    nayzeee_audio_b: { hp: 70, low: -1.0, lowHz: 150, mid: 1.0, midHz: 2200, midQ: 0.8, high: 0.5, highHz: 7000 },   // Echo Column: lean, clear vocals
    nayzeee_audio_c: { hp: 45, low: 2.0, lowHz: 130, mid: 1.5, midHz: 280, midQ: 1.1, high: -1.5, highHz: 6000 },   // Drum Hub: round barrel boom
    nayzeee_audio_d: { hp: 110, low: -4.5, lowHz: 180, mid: 1.0, midHz: 1800, midQ: 0.8, high: 1.0, highHz: 7500 },  // Orb: small, light low end
    nayzeee_audio_e: { hp: 75, low: -1.5, lowHz: 160, mid: 1.5, midHz: 1500, midQ: 0.8, high: -0.5, highHz: 6500 },  // Carry Cube: punchy mids
    nayzeee_audio_f: { hp: 95, low: -2.0, lowHz: 150, mid: 3.0, midHz: 1400, midQ: 0.7, high: -4.0, highHz: 6500 },  // Roll Bar: mid-forward 80s boombox
    nayzeee_audio_g: { hp: 40, low: 1.5, lowHz: 120, mid: 0.5, midHz: 900, midQ: 0.7, high: -2.5, highHz: 7000 },    // Record Console: warm vintage
    nayzeee_audio_h: { hp: 25, low: 0.5, lowHz: 100, mid: 0, midHz: 1100, midQ: 0.7, high: 0.5, highHz: 9000 },      // Studio Set: full range
    vehicle: { hp: 28, low: 2.0, lowHz: 90, mid: -0.5, midHz: 500, midQ: 0.7, high: 0.5, highHz: 8000 },              // car system
    jam: FLAT, preview: FLAT,
  };

  /* Shared reverb buses. Every speaker feeds all three through its own send gains, so moving
     between spaces is a crossfade of sends and the CPU cost stays flat with many speakers. */
  const BUSES = [
    { name: 'room', hp: 160, lp: 9000, ret: 0.9, len: 0.7, pre: 0.004, rt60: 0.45, build: 0.010, hfStart: 8500, hfEnd: 2000, hfTau: 0.08, diffuse: 1.0, burst: 0.0012,
      er: [[4.2, 0.55], [6.3, 0.42], [8.9, 0.36], [12.2, 0.28], [15.7, 0.22], [20.3, 0.16], [25.8, 0.11]] },
    { name: 'hall', hp: 120, lp: 7000, ret: 0.85, len: 2.6, pre: 0.018, rt60: 1.9, build: 0.060, hfStart: 6500, hfEnd: 900, hfTau: 0.30, diffuse: 1.0, burst: 0.0016,
      er: [[18, 0.5], [24, 0.42], [31, 0.36], [39, 0.3], [49, 0.25], [61, 0.2], [75, 0.15], [92, 0.1]] },
    // outdoor street: building facades throw back a few distinct slaps, then a short dark wash
    { name: 'street', hp: 180, lp: 6000, ret: 1.0, len: 1.4, pre: 0.07, rt60: 1.0, build: 0.08, hfStart: 4500, hfEnd: 800, hfTau: 0.20, diffuse: 0.35, burst: 0.003, slapLp: 3500,
      er: [[46, 0.6], [95, 0.38], [150, 0.24], [228, 0.14]], erR: [[59, 0.55], [116, 0.34], [181, 0.2], [262, 0.12]] },
  ];

  // AudioParam slots a voice remembers so unchanged values are not rescheduled every frame
  const OUT = 0, TOPAN = 1, DIRECT = 2, AIR = 3, MUF = 4, THUMP = 5, PX = 6, PY = 7, PZ = 8, BAL = 9, SEND = 10; // SEND..SEND+2
  const GATE = 13, SLOTS = 14;
  const HALF_PI = Math.PI / 2;
  const BUTTERWORTH = -3.01;     // lowpass / highpass Q is in dB in Web Audio: -3 dB = flat, no resonant bump
  const DOPPLER_DEAD = 1.0;      // m/s of closing speed ignored (walking about never wobbles the pitch)
  const DOPPLER_SLEW = 0.08;     // fastest playbackRate change per second
  const PATH_FADE = 0.3;         // s to swap between the close-up stereo path and the HRTF path
  const PAN_MAKEUP = 1.33;       // measured: the mono fold + HRTF sit ~2.5 dB under the stereo path on music
  const TICK = 30;               // ms between steps of things that are not AudioParams (playbackRate, embed volume)
  const SOFT_K = 1 - Math.exp(-TICK / 150);
  const SOFT_STEP = 0.03;        // the embed's volume never moves more than 3 % per step

  const S = {
    ctx: null, master: null, buses: [], clock: 0,
    emitters: new Map(), nodes: new Map(), fading: new Map(), dying: new Set(), failed: new Set(),
    settings: { master: 1, effects: true, streamer: false, bass: 0, mid: 0, treble: 0 },
    cfg: {
      panning: 'HRTF', syncCheck: true, drift: 1.5,
      doppler: true, dopplerAmount: 0.6, maxDoppler: 0.03,
      updateRate: 120, near: 1.5, rolloff: 3.0, closeStereo: 1.2,
      airAbsorption: true, reverbLevel: 1.0, voices: {},
    },
    dt: 0.12, lastFrame: 0, timer: 0,
    playLag: 0.03,   // s from play() to sound, measured; a cued start calls play() this much early
    ytReady: null, reported: new Set(),
  };

  const keyOf = t => t ? (t.id || t.url) : null;
  const now = () => performance.now() + S.clock;
  const isFile = t => t && t.mode === 'file' && !!t.url && !S.failed.has(t.url);
  const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
  const sstep = (a, b, v) => { const x = clamp((v - a) / (b - a), 0, 1); return x * x * (3 - 2 * x); };
  // the volume slider is perceptual: 50 % sounds like half, not like 80 %
  const volCurve = v => Math.pow(clamp(v === undefined || v === null ? 0.7 : v, 0, 1), 1.5);

  function expected(e) {
    if (!e || !e.track) return 0;
    if (!e.playing) return e.pos || 0;
    return Math.max(0, (now() - e.startedAt) / 1000);
  }

  /* ─────────── context, master bus, reverb ─────────── */
  function ctx() {
    if (!S.ctx) {
      const c = S.ctx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: 'playback' });
      // 6 dB of headroom for several speakers at once; the glue compressor's built-in makeup gain
      // brings a single speaker back to about unity (measured: -12 dBFS in, -13 dBFS out)
      S.master = c.createGain(); S.master.gain.value = 0.5;
      // glue: slow and gentle, so a loud street of speakers sits together without pumping
      // (measured: a steady tone under 2 Hz kicks moves 0.2 dB)
      const glue = c.createDynamicsCompressor();
      glue.threshold.value = -12; glue.knee.value = 10; glue.ratio.value = 2;
      glue.attack.value = 0.03; glue.release.value = 0.5;
      // safety limiter: fast, hard knee, catches what the glue lets through
      const lim = c.createDynamicsCompressor();
      lim.threshold.value = -2; lim.knee.value = 0; lim.ratio.value = 20;
      lim.attack.value = 0.002; lim.release.value = 0.25;
      // last line: soft clip above -1 dBFS, so an over can never become a hard digital click
      const clip = c.createWaveShaper();
      clip.curve = softClipCurve();
      S.master.connect(glue); glue.connect(lim); lim.connect(clip); clip.connect(c.destination);
      S.buses = BUSES.map(buildBus);
    }
    if (S.ctx.state === 'suspended') S.ctx.resume();
    return S.ctx;
  }

  function softClipCurve() {
    const N = 2048, curve = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const x = (i / (N - 1)) * 2 - 1, a = Math.abs(x);
      const y = a < 0.89 ? a : 0.89 + 0.11 * Math.tanh((a - 0.89) / 0.11);
      curve[i] = x < 0 ? -y : y;
    }
    return curve;
  }

  function buildBus(spec) {
    const c = S.ctx;
    const input = c.createGain();
    const hp = c.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = spec.hp; hp.Q.value = BUTTERWORTH;
    const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = spec.lp; lp.Q.value = BUTTERWORTH;
    const conv = c.createConvolver(); conv.normalize = true; conv.buffer = makeIR(spec);
    const ret = c.createGain(); ret.gain.value = spec.ret * S.cfg.reverbLevel;
    input.connect(hp); hp.connect(lp); lp.connect(conv); conv.connect(ret); ret.connect(S.master);
    return { input, ret, spec };
  }

  /* Impulse responses, generated once:
       - stereo decorrelated (own noise and own reflection timing per ear)
       - pre-delay, then early reflections as short soft bursts (never clicks)
       - a diffuse tail that builds up instead of starting at full level
       - frequency dependent decay: a lowpass that closes over time, so highs die first
         and there is no hissy white-noise tail */
  function makeIR(o) {
    const c = S.ctx, rate = c.sampleRate, len = Math.floor(o.len * rate);
    const buf = c.createBuffer(2, len, rate);
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch);
      let seed = ch ? 0x2545f491 : 0x9e3779b9;
      const rnd = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 2147483648 - 1; };
      const preN = Math.floor(o.pre * rate);
      let lp = 0;
      for (let i = preN; i < len; i++) {
        const tt = (i - preN) / rate;
        const env = Math.exp(-6.9078 * tt / o.rt60) * Math.min(1, tt / o.build);
        const fc = o.hfEnd + (o.hfStart - o.hfEnd) * Math.exp(-tt / o.hfTau);
        const a = Math.exp(-2 * Math.PI * fc / rate);
        lp = (1 - a) * rnd() + a * lp;
        d[i] = lp * env * o.diffuse;
      }
      // early reflections / slaps
      const list = ch && o.erR ? o.erR : o.er;
      const burstN = Math.max(8, Math.floor(o.burst * rate));
      const slapA = o.slapLp ? Math.exp(-2 * Math.PI * o.slapLp / rate) : 0;
      for (const [ms, g] of list) {
        const jitter = o.erR ? 1 : 1 + rnd() * 0.08;
        const at = Math.floor(ms / 1000 * jitter * rate);   // reflection times are absolute
        const sign = rnd() < 0 ? -1 : 1;
        let s = 0;
        for (let k = 0; k < burstN && at + k < len; k++) {
          const w = 0.5 - 0.5 * Math.cos(2 * Math.PI * k / burstN);   // Hann window
          const v = rnd() * 0.35 + (k === Math.floor(burstN / 2) ? sign : 0);
          s = slapA ? (1 - slapA) * v * 3 + slapA * s : v;
          d[at + k] += s * w * g * 2.2;
        }
      }
    }
    return buf;
  }

  /* ─────────── param helpers (no allocation) ─────────── */
  // Pin the param where it is right now, so the next ramp starts here and now. A ramp always starts
  // at the previous event: after a quiet spell that event is long past and the ramp would jump, so
  // once the last ramp has finished we pin its end value at `t` explicitly.
  function hold(n, slot, p, t) {
    if (t < n.ends[slot]) {
      if (p.cancelAndHoldAtTime) { p.cancelAndHoldAtTime(t); return; }
      const v = p.value; p.cancelScheduledValues(t); p.setValueAtTime(v, t); return;
    }
    const v = n.last[slot];
    p.cancelScheduledValues(t);
    p.setValueAtTime(v === v ? v : p.value, t);   // v !== v: never set yet (NaN)
  }
  function lin(n, slot, p, v, t, end) {
    if (Math.abs(n.last[slot] - v) < 1e-4) return;   // already there or already heading there
    hold(n, slot, p, t);
    n.last[slot] = v; n.ends[slot] = end;
    p.linearRampToValueAtTime(v, end);
  }
  // cutoffs move in log space, the way the ear hears them
  function expo(n, slot, p, v, t, end) {
    if (v < 20) v = 20;
    if (Math.abs(n.last[slot] - v) < v * 0.004) return;
    hold(n, slot, p, t);
    n.last[slot] = v; n.ends[slot] = end;
    p.exponentialRampToValueAtTime(v, end);
  }

  /* ─────────── distance ─────────── */
  // Full level within cfg.near, then an inverse-style falloff that reaches -12 dB near the edge
  // (rolloff 3), times a cosine tail over the last 40 % so it lands on silence exactly at range.
  let revReach = 0;
  function reachOf(d, r) {
    const near = S.cfg.near;
    if (d <= near) { revReach = 1; return 1; }
    const x = clamp((d - near) / Math.max(r - near, 0.5), 0, 1);
    const inv = 1 / (1 + S.cfg.rolloff * x);
    const tail = x <= 0.6 ? 1 : 0.5 + 0.5 * Math.cos(Math.PI * (x - 0.6) / 0.4);
    revReach = Math.sqrt(inv) * tail;   // the room's reverb dies slower than the direct sound
    return inv * tail;
  }
  // air absorption: a high shelf that keeps sinking and a lowpass that slowly closes with distance
  const airDb = d => -Math.min(10, d * 0.22);
  const airCut = d => 20000 / (1 + d / 22);

  /* ─────────── voices ─────────── */
  function voiceFor(e) {
    const v = S.cfg.voices || {};
    return v[e.item] || VOICES[e.item] || v[e.kind] || VOICES[e.kind] || v.default || VOICES.default;
  }

  function base(id, k, type) {
    return {
      id, key: k, type, fx: false, soft: false, ready: false, dead: false, leaving: false,
      seen: performance.now(), lastSync: 0, level: 0, dist: 0,
      open: false, fadeIn: 0.03, onStart: null, cueT: 0, dipT: 0, pauseT: 0,
      rate: 1, rateTo: 1, drift: 0, panOn: true, close: false, closeT: 0,
      last: new Float64Array(SLOTS).fill(NaN), ends: new Float64Array(SLOTS),
      vCur: 0, vTarget: 0, vSent: -1, fFrom: 0, fTo: 0, fT0: 0, fDur: 0,
    };
  }

  function mount(id) {
    const e = S.emitters.get(id);
    if (!e || !e.track) return null;
    const k = keyOf(e.track);
    const want = isFile(e.track) ? 'audio' : 'yt';
    let n = S.nodes.get(id);
    if (n && n.key === k && n.type === want) return n;
    if (n) retire(n, 0.05);
    n = want === 'audio' ? mountAudio(id, e, k) : mountYT(id, e, k);
    S.nodes.set(id, n);
    return n;
  }

  // measured: Chromium's HRTF panner delays by 300 samples at 44.1 kHz and 305 at 48 kHz
  function hrtfLatency() {
    if (S.cfg.panning === 'equalpower') return 0;
    return (S.ctx.sampleRate > 46000 ? 305 : 300) / S.ctx.sampleRate;
  }

  function biquad(type, f, q, g) {
    const b = S.ctx.createBiquadFilter();
    b.type = type; b.frequency.value = f;
    if (q !== undefined) b.Q.value = q;
    if (g !== undefined) b.gain.value = g;
    return b;
  }

  function mountAudio(id, e, k) {
    const c = ctx();
    const el = new Audio();
    el.crossOrigin = 'anonymous';
    el.preload = 'auto';
    el.preservesPitch = false;   // doppler bends the pitch like a real moving source
    el.mozPreservesPitch = false;
    el.webkitPreservesPitch = false;
    const n = base(id, k, 'audio');
    n.el = el;

    el.addEventListener('loadedmetadata', () => { n.ready = true; reportDuration(id, k, el.duration); sync(n, true); });
    el.addEventListener('playing', () => onPlaying(n));
    el.addEventListener('seeked', () => { if (n.open && !n.dead && !n.leaving) gateTo(n, 1, 0.08); });
    el.addEventListener('ended', () => { if (!n.leaving && !n.dead) post('ended', { id, key: k }); });
    el.addEventListener('error', () => {
      // the audio link died or the host sent no CORS header: fall back to the embed so music keeps playing
      if (n.dead || S.nodes.get(id) !== n) return;
      const em = S.emitters.get(id);
      S.failed.add(e.track.url);
      retire(n, 0);
      if (em && em.track && em.track.id && keyOf(em.track) === k) {
        S.nodes.set(id, mountYT(id, em, k));
        post('fellback', { id, key: k });
      }
    });

    try {
      n.src = c.createMediaElementSource(el);
    } catch (_) {
      // could not be routed through the graph: play it plain, volume only
      n.soft = true;
      el.volume = 0;
      el.src = e.track.url;
      ensureTick();
      return n;
    }
    n.fx = true;
    const v = voiceFor(e);
    n.vHp = biquad('highpass', v.hp || 20, BUTTERWORTH);
    n.vLow = biquad('lowshelf', v.lowHz || 140, undefined, v.low || 0);
    n.vMid = biquad('peaking', v.midHz || 1100, v.midQ || 0.7, v.mid || 0);
    n.vHigh = biquad('highshelf', v.highHz || 6000, undefined, v.high || 0);
    n.bass = biquad('lowshelf', 180, undefined, 0);
    n.mid = biquad('peaking', 1100, 0.8, 0);
    n.treble = biquad('highshelf', 4200, undefined, 0);
    n.gate = c.createGain(); n.gate.gain.value = 0; n.last[GATE] = 0;
    n.air = biquad('highshelf', 3000, undefined, 0);
    n.muf = biquad('lowpass', 20000, BUTTERWORTH);
    n.thump = biquad('lowshelf', 110, undefined, 0);
    // a speaker across the street is one point source, so the HRTF path gets L+R folded to mono
    // (Chromium's HRTF would otherwise send the left channel only to the left ear and so on)
    n.toPan = c.createGain();
    n.toPan.channelCount = 1; n.toPan.channelCountMode = 'explicit'; n.toPan.channelInterpretation = 'speakers';
    n.pan = c.createPanner();
    n.pan.panningModel = S.cfg.panning === 'equalpower' ? 'equalpower' : 'HRTF';
    n.pan.distanceModel = 'inverse'; n.pan.refDistance = 1; n.pan.rolloffFactor = 0;   // we do distance ourselves
    n.direct = c.createGain(); n.direct.gain.value = 0;
    // the HRTF path runs ~6.5 ms late; delaying the stereo path the same keeps swaps free of comb filtering
    n.align = c.createDelay(0.05); n.align.delayTime.value = hrtfLatency();
    n.bal = c.createStereoPanner();
    n.out = c.createGain(); n.out.gain.value = 0;
    n.sends = S.buses.map(b => { const g = c.createGain(); g.gain.value = 0; g.connect(b.input); return g; });
    n.an = c.createAnalyser(); n.an.fftSize = 256; n.an.smoothingTimeConstant = 0.78;

    n.src.connect(n.vHp); n.vHp.connect(n.vLow); n.vLow.connect(n.vMid); n.vMid.connect(n.vHigh);
    n.vHigh.connect(n.bass); n.bass.connect(n.mid); n.mid.connect(n.treble); n.treble.connect(n.gate);
    n.gate.connect(n.an);
    n.gate.connect(n.air); n.air.connect(n.muf); n.muf.connect(n.thump);
    n.thump.connect(n.toPan); n.toPan.connect(n.pan); n.pan.connect(n.out);
    n.thump.connect(n.direct); n.direct.connect(n.align); n.align.connect(n.bal); n.bal.connect(n.out);
    for (const s of n.sends) n.thump.connect(s);
    n.out.connect(S.master);

    applyEq(n);
    el.src = e.track.url;
    return n;
  }

  function applyEq(n) {
    if (!n.fx) return;
    const s = S.settings, t = S.ctx.currentTime;
    n.bass.gain.setTargetAtTime(s.bass || 0, t, 0.05);
    n.mid.gain.setTargetAtTime(s.mid || 0, t, 0.05);
    n.treble.gain.setTargetAtTime(s.treble || 0, t, 0.05);
  }

  /* YouTube embedded player: volume only */
  function loadYT() {
    if (S.ytReady) return S.ytReady;
    S.ytReady = new Promise(res => {
      window.onYouTubeIframeAPIReady = () => res();
      const s = document.createElement('script');
      s.src = 'https://www.youtube.com/iframe_api';
      document.head.appendChild(s);
    });
    return S.ytReady;
  }

  function mountYT(id, e, k) {
    const n = base(id, k, 'yt');
    n.soft = true;
    const host = document.createElement('div');
    host.style.cssText = 'position:absolute;width:1px;height:1px;left:-9999px;top:-9999px;opacity:0;pointer-events:none';
    const inner = document.createElement('div');
    host.appendChild(inner);
    document.body.appendChild(host);
    n.host = host;
    ensureTick();
    loadYT().then(() => {
      if (n.dead) return;
      n.player = new YT.Player(inner, {
        width: 1, height: 1, videoId: e.track.id,
        playerVars: { autoplay: 0, controls: 0, disablekb: 1, playsinline: 1, start: Math.floor(expected(e)) },
        events: {
          onReady: () => { n.ready = true; n.player.setVolume(0); n.vSent = 0; reportDuration(id, k, n.player.getDuration()); sync(n, true); },
          onStateChange: ev => {
            if (ev.data === 0 && !n.leaving && !n.dead) post('ended', { id, key: k });
            if (ev.data === 1) { reportDuration(id, k, n.player.getDuration()); onPlaying(n); }
          },
          onError: () => { if (!n.leaving && !n.dead) post('ended', { id, key: k }); },
        },
      });
    });
    return n;
  }

  // stop a voice, with a short fade so it never clicks
  function retire(n, sec) {
    if (n.dead) return;
    n.dead = true;
    if (S.nodes.get(n.id) === n) S.nodes.delete(n.id);
    if (S.fading.get(n.id) === n) S.fading.delete(n.id);
    clearTimeout(n.cueT); clearTimeout(n.dipT); clearTimeout(n.pauseT);
    if (n.fx && sec > 0 && n.ready) {
      gateTo(n, 0, sec);
      setTimeout(() => teardown(n), sec * 1000 + 40);
    } else if (n.soft && sec > 0 && n.ready) {
      // the embed fades on the ticker, so keep it ticking until it is silent
      gateTo(n, 0, sec);
      S.dying.add(n);
      ensureTick();
      setTimeout(() => { S.dying.delete(n); teardown(n); }, n.fDur + 40);
    } else teardown(n);
  }

  function teardown(n) {
    if (n.type === 'audio') {
      try { n.el.pause(); n.el.removeAttribute('src'); n.el.load(); } catch (_) {}
      if (n.fx) { try { n.src.disconnect(); n.out.disconnect(); for (const s of n.sends) s.disconnect(); } catch (_) {} }
    } else {
      try { n.player && n.player.destroy(); } catch (_) {}
      n.host && n.host.remove();
    }
  }

  function reportDuration(id, k, dur) {
    const e = S.emitters.get(id);
    if (!e || !e.track || e.track.duration > 0 || !isFinite(dur) || dur <= 0) return;
    const tag = id + '|' + k;
    if (S.reported.has(tag)) return;
    S.reported.add(tag);
    post('duration', { id, key: k, value: dur });
  }

  /* ─────────── transport gate ─────────── */
  // equal-power when `smooth` (crossfades between two songs), linear for quick declicks
  function gateTo(n, v, sec, smooth) {
    if (n.soft) {
      // the embed's volume can only be stepped every TICK, so its fades are never shorter than 0.6 s
      n.fFrom = softFade(n, performance.now()); n.fTo = v;
      n.fT0 = performance.now(); n.fDur = Math.max(sec, 0.6) * 1000;
      return;
    }
    if (!n.gate) return;
    const p = n.gate.gain, t = S.ctx.currentTime;
    hold(n, GATE, p, t);
    const end = t + Math.max(sec, 0.005);
    if (smooth && sec > 0.2) {
      const from = p.value, steps = 24;
      for (let i = 1; i <= steps; i++) {
        const x = (i / steps) * HALF_PI;
        p.linearRampToValueAtTime(from * Math.cos(x) + v * Math.sin(x), t + sec * i / steps);
      }
    } else {
      p.linearRampToValueAtTime(v, end);
    }
    n.last[GATE] = v; n.ends[GATE] = end;
  }

  function onPlaying(n) {
    if (n.dead) return;
    if (n.playAt) {
      S.playLag += (clamp((performance.now() - n.playAt) / 1000, 0, 0.3) - S.playLag) * 0.3;
      n.playAt = 0;
    }
    // a song on its way out (crossfade) never opens up again, even if it rebuffers
    if (n.open && !n.leaving) { gateTo(n, 1, n.fadeIn, n.fadeIn > 0.2); n.fadeIn = 0.03; }
    if (n.onStart) { const f = n.onStart; n.onStart = null; f(); }
  }

  function startPlay(n) {
    clearTimeout(n.pauseT);
    n.open = true;
    if (n.type === 'audio') {
      if (n.el.paused) { if (!n.soft) gateTo(n, 0, 0.005); n.playAt = n.el.readyState >= 3 ? performance.now() : 0; n.el.play().catch(() => {}); }
      else gateTo(n, 1, 0.05);
    } else if (n.player) {
      const st = n.player.getPlayerState();
      if (st !== 1 && st !== 3) n.player.playVideo(); else gateTo(n, 1, 0.1);
    }
  }

  // fade out, then pause; `to` (seconds) parks the song there once it is silent
  function pauseSoft(n, to) {
    if (!n.open && n.pauseT) { n.parkAt = to; return; }
    n.open = false;
    n.parkAt = to;
    gateTo(n, 0, n.soft ? 0.6 : 0.06);
    clearTimeout(n.pauseT);
    n.pauseT = setTimeout(() => {
      n.pauseT = 0;
      if (n.dead || n.open) return;
      if (n.type === 'audio') {
        if (!n.el.paused) n.el.pause();
        if (n.parkAt !== undefined && Math.abs(n.el.currentTime - n.parkAt) > 0.02) { n.drift = 0; n.el.currentTime = n.parkAt; }
      } else if (n.player && n.player.getPlayerState) {
        if (n.player.getPlayerState() === 1) n.player.pauseVideo();
        if (n.parkAt !== undefined) n.player.seekTo(n.parkAt, true);
      }
    }, n.soft ? 630 : 75);
  }

  // jump inside the song: dip the gate, move, open again on 'seeked'
  function seek(n, to) {
    n.drift = 0;
    if (n.type !== 'audio') { if (n.player && n.player.seekTo) n.player.seekTo(to, true); return; }
    const el = n.el;
    if (el.paused || !n.open || n.soft) { el.currentTime = to; return; }
    gateTo(n, 0, 0.03);
    clearTimeout(n.dipT);
    n.dipT = setTimeout(() => { n.dipT = 0; if (!n.dead) el.currentTime = to + 0.035; }, 35);
  }

  function armCue(n, ms) {
    clearTimeout(n.cueT);
    n.cueT = setTimeout(() => { n.cueT = 0; if (!n.dead) sync(n, true); }, Math.max(0, ms));
  }

  /* ─────────── sync ─────────── */
  function sync(n, force) {
    const e = S.emitters.get(n.id);
    if (!e || !e.track || !n.ready || n.leaving || n.dead) return;
    n.lastSync = performance.now();
    // a start in the future: wait silently at 0:00 and set off so the first note lands on startedAt
    const ahead = e.startedAt - now();
    const lead = n.type === 'audio' ? S.playLag * 1000 : 0;
    const cued = e.playing && ahead > lead + 10;
    const want = expected(e);
    const dur = e.track.duration || 0;
    const past = dur > 0 && want >= dur - 0.25;

    if (n.type === 'audio') {
      const el = n.el;
      if (cued) {
        if (!el.paused) pauseSoft(n, 0);
        else { n.open = false; if (el.currentTime > 0.02) el.currentTime = 0; n.drift = 0; }
        armCue(n, ahead - lead);
      } else if (e.playing && !past) {
        // doppler bends the rate on purpose; n.drift is how far that carried us, so it never counts as lag
        const err = el.currentTime - n.drift - want;
        const bending = Math.abs(n.rate - 1) > 0.002;
        const tol = S.cfg.drift;
        if (force ? Math.abs(err) > 0.12 : (S.cfg.syncCheck && Math.abs(err) > tol && (!bending || Math.abs(err) > tol + 3))) seek(n, want);
        if (el.paused || !n.open) startPlay(n);
      } else if (!el.paused) {
        pauseSoft(n, e.playing ? undefined : want);
      } else if (!e.playing && Math.abs(el.currentTime - want) > 0.4) {
        n.drift = 0; el.currentTime = want;
      }
    } else if (n.player && n.player.getPlayerState) {
      const cur = n.player.getCurrentTime() || 0;
      const st = n.player.getPlayerState();
      if (cued) {
        if (st === 1 || st === 3) pauseSoft(n, 0);
        else { n.open = false; if (cur > 0.3) n.player.seekTo(0, true); }
        armCue(n, ahead);
      } else if (e.playing && !past) {
        if (force || (S.cfg.syncCheck && Math.abs(cur - want) > S.cfg.drift + 0.5)) {
          if (Math.abs(cur - want) > 0.3) n.player.seekTo(want, true);
        }
        if (st !== 1 && st !== 3) { n.open = true; n.player.playVideo(); }
        else if (!n.open) startPlay(n);
      } else if (st === 1) {
        pauseSoft(n, e.playing ? undefined : want);
      }
    }
  }

  /* ─────────── crossfade (mixed playlists) ─────────── */
  // the old song keeps playing (and keeps its place in the world) while the new one comes in
  function crossfade(old, secs) {
    const prior = S.fading.get(old.id);
    if (prior) retire(prior, 0.05);
    S.nodes.delete(old.id);
    old.leaving = true;
    S.fading.set(old.id, old);
    const n = mount(old.id);
    if (!n) { retire(old, 0.1); return; }
    // carry the old voice's last spatial values over so the new one does not ramp in from nothing
    if (n.fx && old.fx) copySpatial(old, n);
    n.fadeIn = secs;
    let begun = false;
    const begin = () => {
      if (begun || old.dead) return;
      begun = true;
      let left = secs;
      if (old.type === 'audio' && isFinite(old.el.duration)) left = old.el.duration - old.el.currentTime;
      const dur = clamp(Math.min(secs, left), 0.4, Math.max(secs, 0.4));
      gateTo(old, 0, dur, true);
      setTimeout(() => retire(old, 0), dur * 1000 + 80);
    };
    n.onStart = begin;
    // if the new song is slow to load, start letting go of the old one anyway
    setTimeout(begin, Math.min(1500, secs * 400));
  }

  // params in slot order (OUT … SEND+2), so a crossfade can hand them over one to one
  function spatialParams(n) {
    const p = n.pan;
    return [n.out.gain, n.toPan.gain, n.direct.gain, n.air.gain, n.muf.frequency, n.thump.gain,
      p.positionX, p.positionY, p.positionZ, n.bal.pan, n.sends[0].gain, n.sends[1].gain, n.sends[2].gain];
  }
  function copySpatial(a, b) {
    const t = S.ctx.currentTime, pa = spatialParams(a), pb = spatialParams(b);
    for (let i = 0; i < pa.length; i++) {
      if (!pa[i] || !pb[i]) continue;
      const v = pa[i].value;
      pb[i].setValueAtTime(v, t);
      b.last[i] = v; b.ends[i] = t;
    }
  }

  /* ─────────── spatial frame from Lua ─────────── */
  /* Frame fields: id · x y z (camera space, metres; -z ahead) · d distance · r range · h 1 = head locked
     (in the car, carrying it, jam, preview) · lp muffle cutoff Hz · g muffle gain · b car bass shelf dB ·
     wr wh ws reverb sends (room, hall, street) · v closing speed m/s (doppler) */
  let pruneT = 0;
  function spatial(list) {
    const c = ctx();
    const tp = performance.now();
    if (S.lastFrame) S.dt += (clamp((tp - S.lastFrame) / 1000, 0.02, 1) - S.dt) * 0.25;
    S.lastFrame = tp;
    const t = c.currentTime;
    const end = t + clamp(S.dt * 1.15, 0.03, 0.6);
    for (let i = 0; i < list.length; i++) {
      const it = list[i];
      const e = S.emitters.get(it.id);
      if (!e || !e.track) continue;
      const n = mount(it.id);
      if (n) { n.seen = tp; apply(n, it, e, t, end); }
      const f = S.fading.get(it.id);
      if (f) { f.seen = tp; apply(f, it, e, t, end); }
      if (n && tp - n.lastSync > 2000) sync(n, false);
    }
    pruneT = tp;
    S.nodes.forEach(prune);
    S.fading.forEach(prune);
  }

  function prune(n) { if (n.seen < pruneT - 1500) retire(n, 0.1); }

  function apply(n, it, e, t, end) {
    const st = S.settings, cf = S.cfg;
    const fx = st.effects !== false;
    const head = it.h === 1 || e.kind === 'preview';
    const d = head ? 0 : (it.d || 0);
    const reach = head ? 1 : reachOf(d, it.r || 1);
    const rev = head ? 1 : revReach;
    const level = st.streamer ? 0 : volCurve(e.volume) * (st.master === undefined ? 1 : st.master);
    const g = fx && it.g !== undefined ? it.g : 1;
    n.level = reach * g;
    n.dist = d;
    const amp = level * reach * g;

    if (!n.fx) { n.vTarget = amp; ensureTick(); return; }

    // close up you hear the speaker's real stereo; further out it is one point in the world (HRTF).
    // The swap is a short crossfade with hysteresis, so you never stand in a half-and-half zone.
    const close = !fx || head || d < cf.closeStereo || (n.close && d < cf.closeStereo * 1.8);
    if (close !== n.close) { n.close = close; n.closeT = t; }
    lin(n, OUT, n.out.gain, amp, t, end);
    lin(n, TOPAN, n.toPan.gain, close ? 0 : PAN_MAKEUP, t, t + PATH_FADE);
    lin(n, DIRECT, n.direct.gain, close ? 1 : 0, t, t + PATH_FADE);
    routePanner(n, t);

    let x = 0, y = 0, z = -1;
    if (!head && fx) {
      x = it.x || 0; y = it.y || 0; z = it.z || 0;
      const len = Math.sqrt(x * x + y * y + z * z);
      if (len < 1e-3) { x = 0; y = 0; z = -1; }
      else if (len < 1) { x /= len; y /= len; z /= len; }   // never let the source sit inside the head
    }
    if (n.panOn) {
      const model = fx && cf.panning !== 'equalpower' ? 'HRTF' : 'equalpower';
      if (n.pan.panningModel !== model) { n.pan.panningModel = model; n.align.delayTime.value = model === 'HRTF' ? hrtfLatency() : 0; }
      const pp = n.pan;
      if (pp.positionX) { lin(n, PX, pp.positionX, x, t, end); lin(n, PY, pp.positionY, y, t, end); lin(n, PZ, pp.positionZ, z, t, end); }
      else pp.setPosition(x, y, z);
    }
    const reachLen = Math.max(Math.sqrt(x * x + y * y + z * z), 1e-3);
    lin(n, BAL, n.bal.pan, head || !fx ? 0 : clamp(x / reachLen * 0.35, -0.35, 0.35), t, end);

    const air = fx && !head && cf.airAbsorption !== false;
    lin(n, AIR, n.air.gain, air ? airDb(d) : 0, t, end);
    expo(n, MUF, n.muf.frequency, fx ? Math.min(it.lp || 20000, air ? airCut(d) : 20000) : 20000, t, end);
    lin(n, THUMP, n.thump.gain, fx ? (it.b || 0) : 0, t, end);

    const wet = fx ? level * rev : 0;
    lin(n, SEND, n.sends[0].gain, wet * (it.wr || 0), t, end);
    lin(n, SEND + 1, n.sends[1].gain, wet * (it.wh || 0), t, end);
    lin(n, SEND + 2, n.sends[2].gain, wet * (it.ws || 0), t, end);

    doppler(n, fx && !head && cf.doppler ? (it.v || 0) : 0);
  }

  // when the HRTF path has been silent for a moment, unhook it: an idle HRTF panner then costs nothing
  function routePanner(n, t) {
    if (n.close) {
      if (n.panOn && t - n.closeT > PATH_FADE + 0.6) { try { n.toPan.disconnect(n.pan); } catch (_) {} n.panOn = false; }
    } else if (!n.panOn) {
      n.toPan.connect(n.pan); n.panOn = true;
      n.last[PX] = n.last[PY] = n.last[PZ] = NaN; n.ends[PX] = n.ends[PY] = n.ends[PZ] = 0;
    }
  }

  // closing speed → target playbackRate with a dead zone and a hard cap; the ticker slews toward it
  function doppler(n, v) {
    const cf = S.cfg;
    let target = 1;
    if (v > DOPPLER_DEAD || v < -DOPPLER_DEAD) {
      const vv = v > 0 ? v - DOPPLER_DEAD : v + DOPPLER_DEAD;
      const max = cf.maxDoppler || 0.03;
      target = 1 + clamp(vv / 343 * (cf.dopplerAmount === undefined ? 0.6 : cf.dopplerAmount), -max, max);
    }
    n.rateTo = target;
    if (target !== 1 || n.rate !== 1) ensureTick();
  }

  /* ─────────── ticker: playbackRate glides, smoothed embed volume ─────────── */
  function softFade(n, tp) {
    if (n.fDur <= 0) return n.fTo;
    const x = clamp((tp - n.fT0) / n.fDur, 0, 1);
    if (x >= 1) { n.fDur = 0; return n.fTo; }
    return n.fFrom * Math.cos(x * HALF_PI) + n.fTo * Math.sin(x * HALF_PI);
  }

  let tickAny = false, tickNow = 0, tickLast = 0, tickDt = TICK / 1000;
  function tickVoice(n) {
    if (n.soft) {
      tickAny = true;
      n.vCur += clamp((n.vTarget - n.vCur) * SOFT_K, -SOFT_STEP, SOFT_STEP);
      const v = clamp(n.vCur * softFade(n, tickNow), 0, 1);
      if (n.type === 'yt') {
        const q = Math.round(v * 100);
        if (q !== n.vSent && n.player && n.player.setVolume) { n.player.setVolume(q); n.vSent = q; }
      } else if (Math.abs(v - n.vSent) > 0.002) { n.el.volume = v; n.vSent = v; }
      return;
    }
    if (!n.fx || (n.rate === 1 && n.rateTo === 1)) return;
    tickAny = true;
    const el = n.el;
    // how far the bent rate carried the song ahead of the clock (the sync check allows for it)
    if (!el.paused) n.drift += (n.rate - 1) * tickDt;
    const step = DOPPLER_SLEW * tickDt;
    let r = n.rate + clamp(n.rateTo - n.rate, -step, step);
    if (n.rateTo === 1 && Math.abs(r - 1) < 0.0004) r = 1;
    n.rate = r;
    if (Math.abs(el.playbackRate - r) > 0.0002 || r === 1) { if (el.playbackRate !== r) el.playbackRate = r; }
  }
  function tick() {
    tickAny = false; tickNow = performance.now();
    tickDt = clamp((tickNow - tickLast) / 1000, 0.001, 0.25); tickLast = tickNow;
    S.nodes.forEach(tickVoice);
    S.fading.forEach(tickVoice);
    S.dying.forEach(tickVoice);
    if (!tickAny) { clearInterval(S.timer); S.timer = 0; }
  }
  function ensureTick() {
    if (S.timer) return;
    tickLast = performance.now();
    S.timer = setInterval(tick, TICK);
  }

  /* ─────────── state ─────────── */
  function setEmitter(e) {
    const prev = S.emitters.get(e.id);
    S.emitters.set(e.id, e);
    const f = S.fading.get(e.id);
    if (f && (!e.track || !e.playing)) retire(f, 0.08);
    const n = S.nodes.get(e.id);
    if (!n) return;   // mounts on its next spatial frame
    if (!e.track) { retire(n, 0.06); return; }
    const k = keyOf(e.track);
    if (n.key !== k) {
      const xf = e.xfade;
      if (xf && xf.from === n.key && xf.secs > 0 && e.playing && n.ready && !n.dead) crossfade(n, xf.secs);
      else { retire(n, 0.05); mount(e.id); }
      return;
    }
    const changed = !prev || prev.playing !== e.playing || prev.startedAt !== e.startedAt || prev.pos !== e.pos;
    if (changed) sync(n, true);
  }

  function removeEmitter(id) {
    const n = S.nodes.get(id), f = S.fading.get(id);
    if (n) retire(n, 0.06);
    if (f) retire(f, 0.06);
    S.emitters.delete(id);
  }

  function reset(list) {
    for (const n of [...S.nodes.values(), ...S.fading.values()]) retire(n, 0.06);
    S.emitters.clear();
    list.forEach(e => S.emitters.set(e.id, e));
  }

  function setSettings(s) {
    Object.assign(S.settings, s || {});
    S.nodes.forEach(applyEq);
  }

  function setConfig(c) {
    Object.assign(S.cfg, c || {});
    if (c && c.updateRate) S.dt = clamp(c.updateRate / 1000, 0.02, 1);
    if (S.ctx) S.buses.forEach(b => b.ret.gain.setTargetAtTime(b.spec.ret * S.cfg.reverbLevel, S.ctx.currentTime, 0.1));
  }

  function levels(id, out) {
    const n = S.nodes.get(id);
    if (!n || !n.an || S.settings.streamer) return null;
    n.an.getByteFrequencyData(out);
    return out;
  }

  function audible() {
    const out = [];
    for (const [id, n] of S.nodes) {
      const e = S.emitters.get(id);
      if (e && e.track && n.level > 0) out.push({ id, level: n.level, dist: n.dist, kind: e.kind });
    }
    return out.sort((a, b) => b.level - a.level);
  }

  // what the Audio tab shows the player about the song they're hearing
  function status(id) {
    const n = S.nodes.get(id);
    const e = S.emitters.get(id);
    if (!e || !e.track) return null;
    return {
      mode: n ? n.type : (isFile(e.track) ? 'audio' : 'yt'),
      fx: !!(n && n.fx),
      ready: !!(n && n.ready),
    };
  }

  // a snapshot of one voice's live values (NUI devtools: Engine.inspect('b1'))
  function inspect(id, which) {
    const n = which === 'fading' ? S.fading.get(id) : S.nodes.get(id);
    if (!n) return null;
    const o = { type: n.type, fx: n.fx, ready: n.ready, open: n.open, level: n.level, dist: n.dist, rate: n.rate, drift: n.drift };
    if (n.type === 'audio') { o.time = n.el.currentTime; o.paused = n.el.paused; }
    if (n.fx) {
      o.gate = n.gate.gain.value; o.out = n.out.gain.value; o.toPan = n.toPan.gain.value; o.direct = n.direct.gain.value;
      o.air = n.air.gain.value; o.cutoff = n.muf.frequency.value; o.thump = n.thump.gain.value; o.balance = n.bal.pan.value;
      o.sends = n.sends.map(s => s.gain.value); o.panOn = n.panOn;
      if (n.pan.positionX) o.pos = [n.pan.positionX.value, n.pan.positionY.value, n.pan.positionZ.value];
    } else { o.volume = n.vCur; o.fade = softFade(n, performance.now()); }
    return o;
  }

  return {
    audible, status, inspect,
    setClock: server => { S.clock = server - performance.now(); },
    now,
    setConfig, setSettings,
    setEmitter, removeEmitter, reset, spatial, levels, expected,
    get: id => S.emitters.get(id),
    isLoaded: id => { const n = S.nodes.get(id); return !!(n && n.ready); },
    hasFx: id => { const n = S.nodes.get(id); return !!(n && n.fx); },
    unlock: () => ctx(),
    keyOf,
  };
})();
