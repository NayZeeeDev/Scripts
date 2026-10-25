/* Bag sounds
 *
 * Every sound is synthesised with WebAudio: zipper teeth, buckle clicks,
 * fabric, thuds, lock mechanisms. Nothing to license, nothing to download.
 * Drop your own file in web/sounds/ and name it in Config.Sounds.files to
 * use a recording instead.
 */
(function () {
  let ctx = null, master = null, noiseBuf = null;
  let files = {};

  function boot() {
    if (ctx) return true;
    try {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
    } catch (e) { return false; }
    master = ctx.createDynamicsCompressor(); // keeps stacked sounds from clipping
    master.connect(ctx.destination);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    return true;
  }

  const rnd = (a, b) => a + Math.random() * (b - a);

  function out(vol, pan) {
    const g = ctx.createGain();
    g.gain.value = vol;
    const p = ctx.createStereoPanner();
    p.pan.value = Math.max(-1, Math.min(1, pan || 0));
    g.connect(p).connect(master);
    return g;
  }

  function env(g, t, peak, attack, decay) {
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  }

  function noise(dest, t, len, type, freq, q, peak, attack, decay) {
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf;
    const f = ctx.createBiquadFilter();
    f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = ctx.createGain();
    env(g, t, peak, attack, decay);
    src.connect(f).connect(g).connect(dest);
    src.start(t, Math.random() * 0.8, len);
  }

  function tone(dest, t, type, f0, f1, peak, decay) {
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(f0, t);
    if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(f1, t + decay);
    const g = ctx.createGain();
    env(g, t, peak, 0.002, decay);
    o.connect(g).connect(dest);
    o.start(t);
    o.stop(t + decay + 0.05);
  }

  /* ---------- building blocks ---------- */

  // fabric moving: filtered noise with an uneven envelope
  function fabric(dest, t, dur, amp) {
    // overlapping scuffs at random moments, louder in the middle
    const parts = Math.max(6, Math.round(dur / 0.03));
    for (let i = 0; i < parts; i++) {
      const u = Math.random();
      const shape = Math.sin(Math.PI * u);
      noise(dest, t + dur * u, 0.2, 'bandpass', rnd(900, 3600), rnd(0.5, 1.2),
        amp * (0.25 + 0.75 * shape) * rnd(0.3, 1), rnd(0.008, 0.03), rnd(0.04, 0.14));
    }
  }

  function click(dest, t, f, amp) {
    tone(dest, t, 'triangle', f, f * 0.92, amp * 0.55, 0.035);
    noise(dest, t, 0.02, 'highpass', 3500, 0.7, amp * 0.6, 0.0008, 0.012);
  }

  // a zipper is a run of tiny tooth clicks, fast in the middle
  function zipper(dest, t, open) {
    const dur = rnd(0.42, 0.58);
    const teeth = Math.round(rnd(34, 44));
    for (let i = 0; i < teeth; i++) {
      const u = i / (teeth - 1);
      const tt = t + dur * (0.5 - 0.5 * Math.cos(Math.PI * u)) + rnd(-0.002, 0.002);
      const f = (open ? 2300 + 2100 * u : 4400 - 2100 * u) * rnd(0.9, 1.1);
      const amp = (0.35 + 0.65 * Math.sin(Math.PI * Math.min(1, u * 1.15))) * rnd(0.75, 1);
      noise(dest, tt, 0.02, 'bandpass', f, 5, amp, 0.0006, 0.011);
    }
    fabric(dest, t, dur * 0.9, 0.12);
    // the pull tab knocking the end stop
    click(dest, t + dur + 0.012, open ? 1900 : 2500, 0.45);
  }

  /* ---------- sounds ---------- */

  const SOUNDS = {
    zip_open: (o, t) => zipper(o, t, true),
    zip_close: (o, t) => zipper(o, t, false),

    rustle: (o, t) => fabric(o, t, 0.38, 0.35),

    strap: (o, t) => {
      fabric(o, t, 0.25, 0.22);
      click(o, t + 0.18, 1500, 0.55);
      click(o, t + 0.24, 2300, 0.45);
    },

    drop: (o, t) => {
      tone(o, t, 'sine', 120, 42, 0.95, 0.24);
      noise(o, t, 0.12, 'lowpass', 420, 0.8, 0.55, 0.002, 0.09);
      fabric(o, t + 0.03, 0.2, 0.16);
    },

    lock: (o, t) => {
      click(o, t, 1800, 0.8);
      click(o, t + 0.075, 2700, 0.7);
      tone(o, t + 0.075, 'sine', 3200, 3150, 0.08, 0.18); // shackle ring
    },

    unlock: (o, t) => {
      click(o, t, 2700, 0.7);
      click(o, t + 0.09, 1700, 0.8);
    },

    pick: (o, t) => {
      const n = Math.round(rnd(6, 9));
      for (let i = 0; i < n; i++) click(o, t + rnd(0, 0.85), rnd(3000, 4600), rnd(0.25, 0.55));
      noise(o, t, 0.9, 'bandpass', 5200, 3, 0.05, 0.05, 0.8); // scrape
    },

    cut: (o, t) => {
      noise(o, t, 0.06, 'highpass', 2200, 0.7, 1.0, 0.0008, 0.035);
      tone(o, t, 'sine', 1850, 1830, 0.35, 0.4);
      tone(o, t, 'sine', 2790, 2770, 0.22, 0.32);
      tone(o, t, 'sine', 160, 70, 0.5, 0.12);
    },

    coins: (o, t) => {
      for (let i = 0; i < 5; i++) tone(o, t + rnd(0, 0.25), 'sine', rnd(3800, 5200), rnd(3700, 5000), rnd(0.08, 0.16), rnd(0.12, 0.25));
      fabric(o, t, 0.3, 0.18);
    },
  };

  function playFile(src, vol, pan) {
    const a = new Audio(src);
    a.volume = Math.max(0, Math.min(1, vol));
    try {
      const node = ctx.createMediaElementSource(a);
      const p = ctx.createStereoPanner();
      p.pan.value = pan || 0;
      node.connect(p).connect(master);
    } catch (e) { /* plain playback is fine */ }
    a.play().catch(() => {});
  }

  const last = {};
  function play(name, vol, pan) {
    if (!boot()) return;
    if (ctx.state === 'suspended') { try { ctx.resume().catch(() => {}); } catch (e) { /* offline */ } }
    // the same sound twice within 60ms is one event heard twice
    const now = performance.now();
    if (last[name] && now - last[name] < 60) return;
    last[name] = now;

    if (files[name]) return playFile(files[name], vol, pan);
    const fn = SOUNDS[name];
    if (fn) fn(out(vol, pan), ctx.currentTime + 0.01);
  }

  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (action === 'sfx' && data) play(data.name, data.vol == null ? 1 : data.vol, data.pan);
    else if (action === 'sfxFiles' && data) files = data;
  });

  window.NBSfx = { play };
})();
