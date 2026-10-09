/* ═══════════════════════════════════════════════════════════
   Audio engine

   A song arrives in one of two modes:
     file   → <audio> we own, routed through the full graph below. Everything works.
     iframe → YouTube's embedded player. Its sound belongs to YouTube's frame and the
              browser will not let us process it, so only volume works.

   file graph:
     element → bass → mid → treble → lowpass → ┬ dry ─────────────┐
                                               └ convolver → wet ─┴→ panner → gain → master
   ═══════════════════════════════════════════════════════════ */
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-speaker';
function post(name, data) {
  return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
    .then(r => r.json()).catch(() => null);
}

const Engine = (() => {
  const S = {
    ctx: null, master: null, comp: null, irs: [], clock: 0,
    emitters: new Map(), nodes: new Map(), seen: new Map(),
    settings: { master: 1, effects: true, streamer: false, bass: 0, mid: 0, treble: 0 },
    cfg: { panning: 'HRTF', syncCheck: true, drift: 1.5, doppler: true, dopplerAmount: 0.6 },
    ytReady: null, reported: new Set(),
  };

  const keyOf = t => t ? (t.id || t.url) : null;
  const now = () => performance.now() + S.clock;
  const isFile = t => t && t.mode === 'file' && !!t.url;

  function expected(e) {
    if (!e || !e.track) return 0;
    if (!e.playing) return e.pos || 0;
    return Math.max(0, (now() - e.startedAt) / 1000);
  }

  function ctx() {
    if (!S.ctx) {
      S.ctx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: 'playback' });
      S.master = S.ctx.createGain();
      // keeps several speakers at once from clipping
      S.comp = S.ctx.createDynamicsCompressor();
      S.comp.threshold.value = -8; S.comp.knee.value = 12; S.comp.ratio.value = 4;
      S.comp.attack.value = 0.004; S.comp.release.value = 0.2;
      S.master.connect(S.comp);
      S.comp.connect(S.ctx.destination);
      buildIRs();
    }
    if (S.ctx.state === 'suspended') S.ctx.resume();
    return S.ctx;
  }

  // small / medium / large room impulse responses, generated once
  function buildIRs() {
    const c = S.ctx;
    [[0.45, 3.2, 0.004], [1.2, 2.6, 0.012], [2.8, 2.1, 0.028]].forEach(([sec, curve, pre]) => {
      const rate = c.sampleRate, len = Math.floor(rate * sec), preN = Math.floor(rate * pre);
      const buf = c.createBuffer(2, len, rate);
      for (let ch = 0; ch < 2; ch++) {
        const d = buf.getChannelData(ch);
        for (let i = preN; i < len; i++) {
          const t = (i - preN) / (len - preN);
          d[i] = (Math.random() * 2 - 1) * Math.pow(1 - t, curve);
        }
      }
      S.irs.push(buf);
    });
  }

  /* ─────────── mounting ─────────── */
  function mount(id) {
    const e = S.emitters.get(id);
    if (!e || !e.track) return null;
    const k = keyOf(e.track);
    const want = isFile(e.track) ? 'audio' : 'yt';
    let n = S.nodes.get(id);
    if (n && n.key === k && n.type === want) return n;
    if (n) unmount(id);
    n = want === 'audio' ? mountAudio(id, e, k) : mountYT(id, e, k);
    S.nodes.set(id, n);
    return n;
  }

  function mountAudio(id, e, k) {
    const c = ctx();
    const el = new Audio();
    el.crossOrigin = 'anonymous';
    el.preload = 'auto';
    const n = { id, key: k, type: 'audio', el, fx: true, ready: false, room: -1, lastSync: 0, level: 0, dist: 0, lastX: null };

    el.addEventListener('loadedmetadata', () => { n.ready = true; reportDuration(id, k, el.duration); sync(n, true); });
    el.addEventListener('ended', () => post('ended', { id, key: k }));
    el.addEventListener('error', () => {
      // the audio link died or the host sent no CORS header: fall back to the embed so music keeps playing
      if (n.dead || S.nodes.get(id) !== n) return;
      const em = S.emitters.get(id);
      if (em && em.track && em.track.id) {
        unmount(id);
        S.nodes.set(id, mountYT(id, em, k));
        post('fellback', { id, key: k });
      }
    });

    try {
      n.src = c.createMediaElementSource(el);
    } catch (_) {
      n.fx = false;
      el.volume = 0;
      el.src = e.track.url;
      return n;
    }
    n.bass = c.createBiquadFilter(); n.bass.type = 'lowshelf'; n.bass.frequency.value = 180;
    n.mid = c.createBiquadFilter(); n.mid.type = 'peaking'; n.mid.frequency.value = 1100; n.mid.Q.value = 0.8;
    n.treble = c.createBiquadFilter(); n.treble.type = 'highshelf'; n.treble.frequency.value = 4200;
    n.lp = c.createBiquadFilter(); n.lp.type = 'lowpass'; n.lp.frequency.value = 20000; n.lp.Q.value = 0.7;
    n.dry = c.createGain();
    n.wet = c.createGain(); n.wet.gain.value = 0;
    n.pan = c.createPanner();
    n.pan.panningModel = S.cfg.panning === 'equalpower' ? 'equalpower' : 'HRTF';
    n.pan.distanceModel = 'linear'; n.pan.refDistance = 1; n.pan.maxDistance = 10000; n.pan.rolloffFactor = 0;
    n.out = c.createGain(); n.out.gain.value = 0;
    n.an = c.createAnalyser(); n.an.fftSize = 256; n.an.smoothingTimeConstant = 0.78;

    n.src.connect(n.bass); n.bass.connect(n.mid); n.mid.connect(n.treble); n.treble.connect(n.lp);
    n.lp.connect(n.dry); n.dry.connect(n.pan);
    n.wet.connect(n.pan);
    n.pan.connect(n.out); n.out.connect(S.master);
    n.treble.connect(n.an);

    applyEq(n);
    el.src = e.track.url;
    return n;
  }

  function applyEq(n) {
    if (!n.fx || !n.bass) return;
    const s = S.settings;
    const t = S.ctx.currentTime;
    n.bass.gain.setTargetAtTime(s.bass || 0, t, 0.05);
    n.mid.gain.setTargetAtTime(s.mid || 0, t, 0.05);
    n.treble.gain.setTargetAtTime(s.treble || 0, t, 0.05);
  }

  function setRoom(n, size) {
    if (!n.fx || n.room === size) return;
    const c = S.ctx;
    if (n.conv) { try { n.lp.disconnect(n.conv); n.conv.disconnect(); } catch (_) {} }
    n.conv = c.createConvolver();
    n.conv.buffer = S.irs[size] || S.irs[0];
    n.lp.connect(n.conv); n.conv.connect(n.wet);
    n.room = size;
  }

  /* YouTube embedded player — volume only */
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
    const n = { id, key: k, type: 'yt', fx: false, ready: false, lastSync: 0, level: 0, dist: 0 };
    const host = document.createElement('div');
    host.style.cssText = 'position:absolute;width:1px;height:1px;left:-9999px;top:-9999px;opacity:0;pointer-events:none';
    const inner = document.createElement('div');
    host.appendChild(inner);
    document.body.appendChild(host);
    n.host = host;
    loadYT().then(() => {
      if (n.dead) return;
      n.player = new YT.Player(inner, {
        width: 1, height: 1, videoId: e.track.id,
        playerVars: { autoplay: 1, controls: 0, disablekb: 1, playsinline: 1, start: Math.floor(expected(e)) },
        events: {
          onReady: () => { n.ready = true; n.player.setVolume(0); reportDuration(id, k, n.player.getDuration()); sync(n, true); },
          onStateChange: ev => { if (ev.data === 0) post('ended', { id, key: k }); if (ev.data === 1) reportDuration(id, k, n.player.getDuration()); },
          onError: () => post('ended', { id, key: k }),
        },
      });
    });
    return n;
  }

  function unmount(id) {
    const n = S.nodes.get(id);
    if (!n) return;
    n.dead = true;
    S.nodes.delete(id);
    if (n.type === 'audio') {
      try { n.el.pause(); n.el.removeAttribute('src'); n.el.load(); } catch (_) {}
      if (n.fx) { try { n.src.disconnect(); n.out.disconnect(); n.pan.disconnect(); n.lp.disconnect(); if (n.conv) n.conv.disconnect(); } catch (_) {} }
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

  /* ─────────── sync ─────────── */
  function sync(n, force) {
    const e = S.emitters.get(n.id);
    if (!e || !e.track || !n.ready) return;
    const want = expected(e);
    const dur = e.track.duration || 0;
    const past = dur > 0 && want >= dur - 0.25;

    if (n.type === 'audio') {
      const el = n.el;
      if (e.playing && !past) {
        // while doppler bends the playback rate the element drifts on purpose; give it more rope
        const tol = S.cfg.drift + (el.playbackRate !== 1 ? 2.5 : 0);
        if (force || (S.cfg.syncCheck && Math.abs(el.currentTime - want) > tol)) el.currentTime = want;
        if (el.paused) el.play().catch(() => {});
      } else {
        if (!el.paused) el.pause();
        if (!e.playing && Math.abs(el.currentTime - want) > 0.4) el.currentTime = want;
      }
    } else if (n.player && n.player.getPlayerState) {
      const cur = n.player.getCurrentTime() || 0;
      const st = n.player.getPlayerState();
      if (e.playing && !past) {
        if (force || (S.cfg.syncCheck && Math.abs(cur - want) > S.cfg.drift + 0.5)) n.player.seekTo(want, true);
        if (st !== 1 && st !== 3) n.player.playVideo();
      } else if (st === 1) {
        n.player.pauseVideo();
        if (!e.playing) n.player.seekTo(want, true);
      }
    }
    n.lastSync = performance.now();
  }

  /* ─────────── spatial frame from Lua ─────────── */
  const smooth = (param, v, tc) => param.setTargetAtTime(v, S.ctx.currentTime, tc === undefined ? 0.12 : tc);

  function falloff(d, r) {
    if (d <= 1) return 1;
    let g = Math.max(0, 1 - (d - 1) / Math.max(r - 1, 0.5));
    return g * g * (3 - 2 * g);
  }

  function spatial(list) {
    const t = performance.now();
    for (const it of list) {
      const e = S.emitters.get(it.id);
      if (!e || !e.track) continue;
      S.seen.set(it.id, t);
      const n = mount(it.id);
      if (!n) continue;

      const reach = falloff(it.d, it.r) * it.g;
      let g = reach * (e.volume ?? 0.7) * S.settings.master;
      n.level = reach;
      n.dist = it.d;
      if (S.settings.streamer) g = 0;
      const fx = S.settings.effects;

      if (n.type === 'audio' && n.fx) {
        const model = fx ? (S.cfg.panning === 'equalpower' ? 'equalpower' : 'HRTF') : 'equalpower';
        if (n.pan.panningModel !== model) n.pan.panningModel = model;
        smooth(n.out.gain, g);
        smooth(n.lp.frequency, fx ? it.lp : 20000);
        setRoom(n, it.s || 0);
        smooth(n.wet.gain, fx ? it.w : 0);
        smooth(n.dry.gain, fx ? 1 - it.w * 0.35 : 1);
        const [x, y, z] = fx ? [it.x, it.y, it.z] : [0, 0, -1];
        if (n.pan.positionX) { smooth(n.pan.positionX, x); smooth(n.pan.positionY, y); smooth(n.pan.positionZ, z); }
        else n.pan.setPosition(x, y, z);

        // doppler: closing fast pitches up, pulling away pitches down
        if (fx && S.cfg.doppler && it.v !== undefined) {
          let rate = 1 + (it.v / 343) * (S.cfg.dopplerAmount ?? 0.6);
          rate = Math.max(0.96, Math.min(1.04, rate));
          if (Math.abs(rate - 1) < 0.003) rate = 1;
          if (Math.abs(n.el.playbackRate - rate) > 0.0015) {
            n.el.preservesPitch = false;
            n.el.mozPreservesPitch = false;
            n.el.playbackRate = rate;
          }
        } else if (n.el.playbackRate !== 1) {
          n.el.playbackRate = 1;
        }
      } else if (n.type === 'audio') {
        n.el.volume = Math.min(1, Math.max(0, g));
      } else if (n.player && n.player.setVolume) {
        n.player.setVolume(Math.round(g * 100));
      }

      if (t - n.lastSync > 2000) sync(n, false);
    }
    for (const [id] of S.nodes) {
      if ((S.seen.get(id) || 0) < t - 1500) unmount(id);
    }
  }

  /* ─────────── state ─────────── */
  function setEmitter(e) {
    const prev = S.emitters.get(e.id);
    S.emitters.set(e.id, e);
    if (!e.track) return unmount(e.id);
    const n = S.nodes.get(e.id);
    if (n && n.key === keyOf(e.track)) {
      const changed = !prev || prev.playing !== e.playing || prev.startedAt !== e.startedAt || prev.pos !== e.pos;
      if (changed) sync(n, true);
    }
  }

  function removeEmitter(id) { unmount(id); S.emitters.delete(id); S.seen.delete(id); }

  function reset(list) {
    for (const id of [...S.nodes.keys()]) unmount(id);
    S.emitters.clear();
    list.forEach(e => S.emitters.set(e.id, e));
  }

  function setSettings(s) {
    Object.assign(S.settings, s || {});
    for (const [, n] of S.nodes) applyEq(n);
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

  return {
    audible, status,
    setClock: server => { S.clock = server - performance.now(); },
    setConfig: c => Object.assign(S.cfg, c || {}),
    setSettings,
    setEmitter, removeEmitter, reset, spatial, levels, expected,
    get: id => S.emitters.get(id),
    isLoaded: id => { const n = S.nodes.get(id); return !!(n && n.ready); },
    hasFx: id => { const n = S.nodes.get(id); return !!(n && n.fx); },
    unlock: () => ctx(),
    keyOf,
  };
})();
