/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · vhud — passenger mini HUD (never takes focus)          apps/vhud/app.js
   Shown to everyone in a radio vehicle while its MV-90 head unit is on
   (client/modules/vehicle.lua, Config.Vehicles.hud).

   Lua → NUI
     open   { same fields as data, optional }
     data   { freq '155.50' | nil, label, talker = { name, callsign, q } | 'name' | nil, on, mute, model? }
     close
   NUI → Lua   nothing

   A capsule at the top centre: head-unit glyph, model + state line over the rolling
   frequency, the channel label chip, the talker sliding in on the right. After a few quiet
   seconds the label folds away and the capsule steps back; any change brings it forward.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t } = NZR;
  const CALM_MS = 6500;
  const num = (v, d = NaN) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  // static words: re-read from the locale when Lua pushes the config (it arrives after init)
  const L = (k, f) => `<span data-t="${k}" data-f="${esc(f)}">${esc(t(k, f))}</span>`;
  const relabel = el => el.querySelectorAll('[data-t]').forEach(e => { e.textContent = t(e.dataset.t, e.dataset.f); });

  // a DIN head unit: faceplate, display, knob (our own glyph, NAYZEEE stroke style)
  const UNIT = '<svg viewBox="0 0 24 24"><path d="M2.5 7H21.5V16.2L19.2 18.5H2.5Z"/><path class="a" d="M5.2 10H13.8V14.2H5.2Z"/><circle cx="17.6" cy="12.1" r="2.1"/><path d="M6 18.5V20.5M18 18.5V20.5"/></svg>';
  const ARCS = [0, 1, 2, 3].map(i => {
    const a0 = (135 + i * 67.5 + 4.5) * Math.PI / 180, a1 = a0 + 58.5 * Math.PI / 180;
    const p = a => `${(8 + 6 * Math.cos(a)).toFixed(2)} ${(8 + 6 * Math.sin(a)).toFixed(2)}`;
    return `M${p(a0)}A6 6 0 0 1 ${p(a1)}`;
  });

  let app = null, box = null, odo = null, labEl = null, tkIn = null, sigEl = null, stEl = null;
  let last = '', calmTimer = 0, talkerKey = '';

  function roll(o, v) {
    const shape = v.replace(/\d/g, 'd');
    if (o.shape !== shape) { o.set(v.replace(/\d/g, '0')); void o.el.offsetWidth; o.shape = shape; }
    o.set(v);
  }
  function wake() {
    box.classList.remove('calm');
    clearTimeout(calmTimer);
    calmTimer = setTimeout(() => { if (!box.classList.contains('talk')) box.classList.add('calm'); }, CALM_MS);
  }
  function talkerOf(v) {
    if (!v) return null;
    if (typeof v === 'string') return { name: v, callsign: '', q: NaN };
    if (typeof v !== 'object') return null;
    const name = String(v.name ?? '').trim(), callsign = String(v.callsign ?? '').trim();
    if (!name && !callsign) return null;
    return { name, callsign, q: num(v.q) };
  }

  // every data message is the whole state (Lua drops nil fields, so nothing is merged)
  function data(d = {}) {
    d = d || {};
    const on = d.on !== false;
    const f = NZR.fmt.freq(d.freq ?? d.fkey);
    const mute = on && d.mute === true;
    const tk = on ? talkerOf(d.talker) : null;
    box.classList.toggle('off', !on);
    box.classList.toggle('mute', mute);
    box.classList.toggle('idle', on && !f);
    box.querySelector('.vh-mod span').textContent = String(d.model || 'MV-90');
    stEl.textContent = !on ? t('ui.vh_off', 'off') : mute ? t('ui.vh_muted', 'muted') : tk ? t('ui.vh_rx', 'receiving') : f ? t('ui.vh_ready', 'standby') : t('ui.vh_tune', 'no channel');
    roll(odo, f || '000.00');   // untuned: unlit zeros (.idle dims them)
    const label = on && d.label ? String(d.label) : '';
    labEl.innerHTML = label ? `<span class="nzr-chip">${esc(label)}</span>` : '';
    // talker
    const key = tk ? `${tk.callsign}|${tk.name}` : '';
    if (tk) {
      tkIn.querySelector('.vh-cs').textContent = tk.callsign;
      tkIn.querySelector('.vh-nm').textContent = tk.name || tk.callsign;
      if (Number.isFinite(tk.q)) {
        const bars = Math.max(0, Math.min(4, Math.round(tk.q * 4)));
        sigEl.className = `vh-sig t${bars <= 1 ? bars : bars === 2 ? 2 : 4}`;
        sigEl.innerHTML = `<svg viewBox="0 0 16 16">${ARCS.map((p, i) => `<path class="${i < bars ? 'on' : ''}" d="${p}"/>`).join('')}</svg>`;
      } else sigEl.innerHTML = '';
      if (talkerKey && key !== talkerKey) { tkIn.classList.remove('swap'); void tkIn.offsetWidth; tkIn.classList.add('swap'); }
    }
    box.classList.toggle('talk', !!tk);
    const sig = `${on}|${f}|${label}|${mute}|${key}`;
    talkerKey = key;
    if (sig !== last) wake();
    last = sig;
  }

  app = NZR.app('vhud', {
    escClose: false,
    init(el) {
      NZR.onCore('config', () => relabel(el));
      el.innerHTML = `<div class="vh"><div class="vh-cap">
          <span class="vh-ic">${UNIT}</span>
          <div class="vh-id"><span class="vh-mod"><span>MV-90</span><em></em></span>
            <div class="vh-f"><span class="vh-fo"></span><small>${L('ui.mhz', 'MHz')}</small></div><span class="vh-off">${L('ui.vh_offword', 'OFF')}</span></div>
          <span class="vh-lab"></span>
          <span class="vh-mu">${NZR.icon('mute')}${L('ui.vh_muted', 'muted')}</span>
          <div class="vh-tk"><div class="vh-tk-in"><span class="vh-rip"><i></i><i></i><b></b></span><span class="vh-cs"></span><b class="vh-nm"></b><span class="vh-sig"></span></div></div>
        </div></div>`;
      box = el.querySelector('.vh');
      odo = NZR.ui.Odometer(el.querySelector('.vh-fo'), { value: '000.00', blink: false });
      labEl = el.querySelector('.vh-lab');
      tkIn = el.querySelector('.vh-tk-in');
      sigEl = el.querySelector('.vh-sig');
      stEl = el.querySelector('.vh-mod em');
    },
    open(d) {
      last = '';
      talkerKey = '';
      box.style.animation = 'none'; void box.offsetWidth; box.style.animation = '';
      data(d || {});
    },
    close() { clearTimeout(calmTimer); },
    msg: { data },
    preview() {
      NZR.demo('vhud', { on: true, freq: '000.00', label: '' });
      const steps = [
        { freq: '155.50', label: 'Patrol North', talker: null, mute: false },
        { talker: { name: 'Maya Reyes', callsign: '2A14', q: 0.82 } },
        { talker: { name: 'Dario Kostas', callsign: '1L20', q: 0.41 } },
        { talker: null },
        { mute: true },
        { mute: false, freq: '462.725', label: 'Fire Ground 2' },
        { talker: { name: 'June Whitfield', callsign: 'K9', q: 1 } },
        { talker: null, on: false },
        { on: true, freq: '155.50', label: 'Patrol North' },
      ];
      let i = 0, state = { on: true, model: 'MV-90' };
      setTimeout(function step() { state = Object.assign(state, steps[i % steps.length]); app.msg.data(Object.assign({}, state)); i++; setTimeout(step, i === 2 ? 900 : 2600); }, 300);
    },
  });
})();
