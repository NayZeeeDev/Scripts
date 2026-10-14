/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Placement HUD (app 'builder')      module: hospital
   Bottom-centre HUD panel while placing a hospital position in the world:
   type icon, "Place <type>", department / kind tags, heading dial (+ snap),
   height, distance meter, a valid / invalid line and the key row.
   A crosshair marks the screen centre the placement ray uses.

   Lua → JS   open { type, label, icon, kind, dept, replace, locale, snapStep, max }
              state { heading, height, dist, max, valid, reason = nil|'far'|'nosurface', snap, snapStep }
              flash { reason }                    E pressed on an invalid spot
   JS → Lua   none (opened without focus; client/modules/hospital_builder.lua reads the keys)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  const APP = 'builder';
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  let root = null, cfg = {}, last = {};

  const kindLabel = k => ({ prop: T('k_prop', 'Prop'), marker: T('k_marker', 'Marker'), car: T('k_car', 'Vehicle'), heli: T('k_heli', 'Helicopter') }[k] || k);

  function render() {
    const title = cfg.replace ? T('bx_replace', 'Re-place %s', cfg.label) : T('bx_place', 'Place %s', cfg.label);
    root.innerHTML = `
      <div class="bx-cross"></div>
      <div class="bx nza-hud solid rail">
        <div class="bx-top">
          <div class="bx-ic">${icon(cfg.icon || 'pin')}</div>
          <div class="bx-t">
            <div class="bx-tag">${esc(T('bx_tag', 'Placement mode'))}${cfg.dept ? `<i></i><span>${esc(cfg.dept)}</span>` : ''}<i></i><span>${esc(kindLabel(cfg.kind))}</span></div>
            <div class="bx-title">${esc(title)}</div>
          </div>
          <div class="bx-stats">
            <div class="bx-dial" title="${esc(T('bx_heading', 'Heading'))}">
              <svg viewBox="0 0 44 44"><circle cx="22" cy="22" r="19" fill="rgba(255,255,255,.03)" stroke="rgba(255,255,255,.12)" stroke-width="1.5"/>
                <path d="M22 4v4M22 36v4M4 22h4M36 22h4" stroke="rgba(255,255,255,.25)" stroke-width="1.5" stroke-linecap="round"/>
                <text x="22" y="15" text-anchor="middle" font-size="6.5" font-weight="700" fill="rgba(255,255,255,.4)" font-family="Lexend,sans-serif">N</text>
                <g class="nd"><path d="M22 9l4.5 13h-9z" fill="#0fd4c4"/><path d="M22 35l-4.5-13h9z" fill="rgba(255,255,255,.18)"/></g>
                <circle cx="22" cy="22" r="2.2" fill="#fff"/></svg>
              <span class="snap"></span>
            </div>
            <div class="bx-stat"><div class="l">${esc(T('bx_heading', 'Heading'))}</div><div class="v" data-s="h">0.0<small>°</small></div></div>
            <div class="bx-stat"><div class="l">${esc(T('bx_height', 'Height'))}</div><div class="v" data-s="z">+0.00<small>m</small></div></div>
            <div class="bx-stat"><div class="l">${esc(T('bx_distance', 'Distance'))}</div><div class="v" data-s="d">--<small>m</small></div><div data-s="m"></div></div>
          </div>
        </div>
        <div class="bx-msg" data-s="msg">${icon('check')}<span></span><em></em></div>
        <div class="bx-keys">
          <span><kbd class="teal">E</kbd>${esc(T('bx_confirm', 'Confirm'))}</span>
          <span><kbd>Q</kbd>${esc(T('bx_cancel', 'Cancel'))}</span>
          <span><kbd>←</kbd><kbd>→</kbd>${esc(T('bx_rotate', 'Rotate'))}</span>
          <span><kbd>${esc(T('bx_wheel', 'Wheel'))}</kbd>${esc(T('bx_step', 'Step %s°', 7.5))}</span>
          <span><kbd>Shift</kbd>${esc(T('bx_faster', 'Hold for faster'))}</span>
          <span><kbd>Alt</kbd>${esc(T('bx_fine', 'Fine'))}</span>
          <span><kbd>PgUp</kbd><kbd>PgDn</kbd>${esc(T('bx_raise', 'Height'))}</span>
          <span data-s="snapkey"><kbd>G</kbd>${esc(T('bx_snap', 'Snap %s°', cfg.snapStep || 15))}</span>
        </div>
      </div>`;
    update(last, true);
  }

  function update(st, force) {
    if (!root || !root.firstElementChild) return;
    const q = s => root.querySelector(`[data-s=${s}]`);
    const h = Number(st.heading || 0);
    const bad = st.valid === false;
    root.querySelector('.bx').classList.toggle('bad', bad);
    root.querySelector('.bx-cross').classList.toggle('bad', bad);
    q('h').innerHTML = `${h.toFixed(1)}<small>°</small>`;
    const z = Number(st.height || 0);
    q('z').innerHTML = `${z >= 0 ? '+' : ''}${z.toFixed(2)}<small>m</small>`;
    const max = Number(st.max || cfg.max || 25);
    const d = st.dist === undefined || st.dist === null || st.dist < 0 ? null : Number(st.dist);
    q('d').innerHTML = `${d === null ? '--' : d.toFixed(1)}<small>m</small>`;
    q('d').classList.toggle('bad', st.reason === 'far');
    q('m').innerHTML = NZA.ui.meterHTML({ value: d === null ? 0 : Math.min(1, d / max), tone: st.reason === 'far' ? 'red' : '' });
    // the dial turns like a map arrow: GTA headings grow counter-clockwise
    root.querySelector('.bx-dial .nd').style.transform = `rotate(${-h}deg)`;
    const dial = root.querySelector('.bx-dial');
    dial.classList.toggle('snapping', !!st.snap);
    dial.querySelector('.snap').textContent = `${st.snapStep || cfg.snapStep || 15}°`;
    q('snapkey').classList.toggle('on', !!st.snap);
    const msg = q('msg');
    msg.classList.toggle('bad', bad);
    let text;
    if (st.reason === 'far') text = T('bx_far', 'Too far away. Walk closer (max %s m).', max.toFixed(0));
    else if (st.reason === 'nosurface') text = T('bx_nosurface', 'Aim the crosshair at the floor or a surface.');
    else text = T('bx_valid', 'Good spot. Press E to place it here.');
    msg.innerHTML = `${icon(bad ? 'alert' : 'check')}<span>${esc(text)}</span>${st.coords ? `<em>${Number(st.coords.x).toFixed(1)}, ${Number(st.coords.y).toFixed(1)}, ${Number(st.coords.z).toFixed(1)}</em>` : ''}`;
    if (force) msg.classList.remove('shake');
  }

  NZA.app(APP, {
    escClose: false,
    init(el) { root = el; },
    open(data) {
      if (data.locale) LOC = Object.assign({}, LOC, data.locale);
      cfg = data || {};
      last = { heading: 0, height: 0, dist: null, valid: true, max: data.max, snapStep: data.snapStep };
      render();
    },
    close() { if (root) root.innerHTML = ''; },
    msg: {
      state(d) { last = Object.assign({}, last, d || {}); update(last); },
      flash() {
        const m = root && root.querySelector('[data-s=msg]');
        if (!m) return;
        m.classList.remove('shake'); void m.offsetWidth; m.classList.add('shake');
        NZA.audio.fail();
      },
    },
    preview() {
      const kind = new URLSearchParams(location.search).get('kind') || 'marker';
      const demo = NZA.el('div', 'bx-demo', '<span class="beam"></span><span class="orb"></span><span class="ring"></span>');
      document.body.appendChild(demo);
      const types = {
        marker: { type: 'checkin', label: 'Check-in Desk', icon: 'ticket', kind: 'marker' },
        prop: { type: 'xray', label: 'X-ray Table', icon: 'xray', kind: 'prop' },
        heli: { type: 'heli', label: 'Helipad', icon: 'heli', kind: 'heli' },
      };
      NZA.open(APP, Object.assign({ dept: 'Los Santos Medical', snapStep: 15, max: 25, locale: {} }, types[kind] || types.marker));
      const bad = new URLSearchParams(location.search).get('bad');
      demo.classList.toggle('bad', !!bad);
      NZA.apps[APP].msg.state({ heading: 87.5, height: 0.1, dist: bad ? 31.4 : 4.2, max: 25, valid: !bad, reason: bad ? 'far' : null, snap: kind === 'prop', snapStep: 15, coords: { x: 307.4, y: -595.1, z: 43.28 } });
    },
  });
})();
