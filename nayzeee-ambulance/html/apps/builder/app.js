/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Site survey HUD (app 'builder')     module: hospital
   Shown while an admin sets a hospital site in the world. Never takes focus:
   client/modules/hospital_builder.lua reads the keys and feeds this HUD.

   Layout (NAYZEEE HUD language — nothing bottom-centre, nothing on the right edge):
     · left column, vertically centred: survey card (corner bracket, type status ring,
       bearing compass with a rolling read-out, instrument list, state note) and a
       control pad (key tiles that light up while held)
     · screen centre: bracket reticle (the placement ray starts there) + range chip

   Lua → JS   open  { type, label, icon, kind, dept, replace, locale, snapStep, max }
              state { heading, height, dist, max, valid, reason = nil|'far'|'nosurface',
                      snap, snapStep, coords, keys = { fast, fine, turn, wheel, lift } }
              flash { reason }                      E pressed on an invalid spot
   JS → Lua   none
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  const APP = 'builder';
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  let root = null, cfg = {}, last = {}, odo = null;

  const KIND = {
    prop: ['box', 'k_prop', 'Prop'], marker: ['pin', 'k_marker', 'Marker'],
    car: ['car', 'k_car', 'Vehicle bay'], heli: ['heli', 'k_heli', 'Helipad'],
  };
  const R = 15.5, CIRC = 2 * Math.PI * R;

  // compass rose: 72 ticks, cardinal letters; rotated as a whole so the fixed pointer reads the bearing
  function roseSVG(step) {
    let ticks = '';
    for (let i = 0; i < 72; i++) {
      const a = i * 5, major = a % 30 === 0, snapT = step > 0 && Math.abs((a / step) - Math.round(a / step)) < 1e-6;
      const r1 = major ? 50 : 53, r2 = 57;
      const rad = (a - 90) * Math.PI / 180;
      ticks += `<line class="${major ? 'mj' : ''} ${snapT ? 'sn' : ''}" x1="${(64 + r1 * Math.cos(rad)).toFixed(2)}" y1="${(64 + r1 * Math.sin(rad)).toFixed(2)}" x2="${(64 + r2 * Math.cos(rad)).toFixed(2)}" y2="${(64 + r2 * Math.sin(rad)).toFixed(2)}"/>`;
    }
    return `<g class="rose">${ticks}</g><g class="lt">${LETTERS.map(([l]) => `<text class="${l === 'N' ? 'n' : ''}" data-l="${l}">${l}</text>`).join('')}</g>`;
  }
  // GTA headings grow counter-clockwise (west = 90°). Letters stay upright and ride on the turning rose.
  const LETTERS = [['N', 0], ['W', 90], ['S', 180], ['E', 270]];
  function placeLetters(h) {
    LETTERS.forEach(([l, hd]) => {
      const t = root.querySelector(`.bx-compass text[data-l=${l}]`);
      if (!t) return;
      const a = ((360 - hd + h) % 360) * Math.PI / 180;
      t.setAttribute('x', (64 + 41 * Math.sin(a)).toFixed(2));
      t.setAttribute('y', (64 - 41 * Math.cos(a) + 3.4).toFixed(2));
    });
  }

  function render() {
    const k = KIND[cfg.kind] || KIND.marker;
    const step = Number(cfg.snapStep || 15);
    const sub = cfg.replace ? T('bx_replace', 'Moving an existing site') : T('bx_place', 'Setting a new site');
    root.innerHTML = `
      <div class="bx-ret">
        <div class="bx-sq"><i class="c1"></i><i class="c2"></i><i class="c3"></i><i class="c4"></i><b></b></div>
        <div class="bx-rchip"><i></i><span data-s="rchip">--</span></div>
      </div>
      <aside class="bx-col">
        <section class="bx-card nza-hud solid">
          <header class="bx-head">
            <span class="bx-kick">${esc(T('bx_tag', 'Site survey'))}</span>
            <span class="bx-kind">${icon(k[0])}${esc(T(k[1], k[2]))}</span>
          </header>
          <div class="bx-id">
            <div class="bx-ring"><svg viewBox="0 0 38 38"><circle class="tr" cx="19" cy="19" r="${R}"/><circle class="fl" cx="19" cy="19" r="${R}" stroke-dasharray="0 ${CIRC.toFixed(2)}"/></svg>${icon(cfg.icon || 'pin')}</div>
            <div class="bx-nm">
              <div class="bx-title">${esc(cfg.label || '')}</div>
              <div class="bx-sub">${cfg.dept ? `<b>${esc(cfg.dept)}</b><i></i>` : ''}${esc(sub)}</div>
            </div>
          </div>
          <div class="bx-read">
            <div class="bx-compass">
              <svg viewBox="0 0 128 128">
                <circle class="face" cx="64" cy="64" r="59"/>
                <circle class="inner" cx="64" cy="64" r="33"/>
                ${roseSVG(step)}
                <path class="ptr" d="M64 1.5l5.5 9h-11z"/>
              </svg>
              <div class="bx-cv"><div data-s="odo"></div><span>${esc(T('bx_heading', 'Bearing'))}</span></div>
              <span class="bx-lock">${icon('lock')}${step}°</span>
            </div>
            <div class="bx-il">
              <div class="bx-row"><span>${esc(T('bx_height', 'Lift'))}</span><b data-s="z">+0.00<small>m</small></b></div>
              <div class="bx-row" data-s="rrow"><span>${esc(T('bx_distance', 'Range'))}</span><b data-s="d">--<small>m</small></b><em class="bar"><i data-s="dbar"></i></em></div>
              <div class="bx-row" data-s="lrow"><span>${esc(T('bx_lock', 'Lock'))}</span><b data-s="lock">--</b></div>
              <div class="bx-row grid"><span>${esc(T('bx_grid', 'Grid'))}</span><b data-s="xyz">--</b></div>
            </div>
          </div>
          <div class="bx-state" data-s="msg"><span class="ic"></span><p></p></div>
        </section>
        <section class="bx-pad">
          ${tile('set', ['E'], T('bx_confirm', 'Set here'), '', 'go')}
          ${tile('back', ['Q'], T('bx_cancel', 'Back out'), '')}
          ${tile('turn', ['←', '→'], T('bx_rotate', 'Turn'), '')}
          ${tile('wheel', [T('bx_wheel', 'Wheel')], T('bx_nudge', 'Nudge'), T('bx_step', '±%s°', 7.5))}
          ${tile('lift', ['PgUp', 'PgDn'], T('bx_raise', 'Lift'), '')}
          ${tile('fast', ['Shift'], T('bx_faster', 'Coarse'), '×3')}
          ${tile('fine', ['Alt'], T('bx_fine', 'Fine'), '×0.2')}
          ${tile('snap', ['G'], T('bx_snap', 'Lock %s°', step), '')}
        </section>
      </aside>`;
    odo = NZA.ui.FlipClock(root.querySelector('[data-s=odo]'), { value: '000.0', small: true });
    update(last);
  }

  function tile(id, keys, label, note, extra = '') {
    return `<div class="bx-t ${extra}" data-k="${id}">${keys.map(k => `<kbd>${esc(k)}</kbd>`).join('')}<span>${esc(label)}</span>${note ? `<em>${esc(note)}</em>` : ''}</div>`;
  }

  function update(st) {
    if (!root || !root.querySelector('.bx-card')) return;
    const q = s => root.querySelector(`[data-s=${s}]`);
    const h = ((Number(st.heading || 0) % 360) + 360) % 360;
    const tone = st.valid === false ? (st.reason === 'nosurface' ? 'amber' : 'red') : 'teal';
    root.classList.remove('t-teal', 't-red', 't-amber');
    root.classList.add(`t-${tone}`);

    // bearing: the rose turns, the pointer stays at the top
    root.querySelector('.bx-compass .rose').style.transform = `rotate(${h}deg)`;
    placeLetters(h);
    if (odo) odo.set(h.toFixed(1).padStart(5, '0'));
    root.querySelector('.bx-compass').classList.toggle('snapping', !!st.snap);

    const z = Number(st.height || 0);
    q('z').innerHTML = `${z >= 0 ? '+' : '−'}${Math.abs(z).toFixed(2)}<small>m</small>`;
    const max = Number(st.max || cfg.max || 25);
    const d = st.dist === undefined || st.dist === null || st.dist < 0 ? null : Number(st.dist);
    const frac = d === null ? 0 : Math.min(1, d / max);
    q('d').innerHTML = `${d === null ? '--' : d.toFixed(1)}<small>/ ${max.toFixed(0)} m</small>`;
    q('dbar').style.width = `${(frac * 100).toFixed(1)}%`;
    q('rrow').classList.toggle('bad', st.reason === 'far');
    q('lock').textContent = st.snap ? `${Number(st.snapStep || cfg.snapStep || 15)}°` : T('bx_free', 'Free');
    q('lrow').classList.toggle('on', !!st.snap);
    q('xyz').textContent = st.coords ? `${Number(st.coords.x).toFixed(1)} · ${Number(st.coords.y).toFixed(1)} · ${Number(st.coords.z).toFixed(1)}` : '--';

    // status ring around the type icon = how much of the reach is used
    const fl = root.querySelector('.bx-ring .fl');
    fl.setAttribute('stroke-dasharray', `${(Math.max(0.02, frac) * CIRC).toFixed(2)} ${CIRC.toFixed(2)}`);

    // reticle chip
    let chip;
    if (st.reason === 'far') chip = T('bx_chip_far', 'Out of reach');
    else if (st.reason === 'nosurface') chip = T('bx_chip_none', 'No surface');
    else chip = d === null ? '--' : `${d.toFixed(1)} m`;
    q('rchip').textContent = chip;

    // state note
    let text, ic;
    if (st.reason === 'far') { text = T('bx_far', 'Out of reach. Walk within %s m of the spot.', max.toFixed(0)); ic = 'alert'; }
    else if (st.reason === 'nosurface') { text = T('bx_nosurface', 'Nothing under the reticle. Aim at the floor or a counter.'); ic = 'crosshair'; }
    else { text = T('bx_valid', 'Spot is clear. E sets it here.'); ic = 'check'; }
    const msg = q('msg');
    msg.querySelector('.ic').innerHTML = icon(ic);
    msg.querySelector('p').textContent = text;

    // key tiles light up while held
    const keys = st.keys || {};
    const lit = (k, on) => { const el = root.querySelector(`.bx-t[data-k=${k}]`); if (el) el.classList.toggle('on', !!on); };
    lit('fast', keys.fast); lit('fine', keys.fine); lit('turn', keys.turn); lit('wheel', keys.wheel); lit('lift', keys.lift); lit('snap', st.snap);
    const go = root.querySelector('.bx-t[data-k=set]');
    go.classList.toggle('off', st.valid === false);
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
    close() { if (root) { root.innerHTML = ''; root.classList.remove('t-teal', 't-red', 't-amber'); } odo = null; },
    msg: {
      state(d) { last = Object.assign({}, last, d || {}); update(last); },
      flash() {
        const m = root && root.querySelector('[data-s=msg]');
        if (!m) return;
        [m, root.querySelector('.bx-ret')].forEach(x => { x.classList.remove('shake'); void x.offsetWidth; x.classList.add('shake'); });
        NZA.audio.fail();
      },
    },
    preview() {
      const params = new URLSearchParams(location.search);
      const kind = params.get('kind') || 'marker';
      const bad = params.get('bad');
      const demo = NZA.el('div', `bx-demo k-${kind}${bad ? ` bad-${bad}` : ''}`, `
        <span class="glow"></span><span class="pool"></span>
        <span class="foot"><i class="c1"></i><i class="c2"></i><i class="c3"></i><i class="c4"></i><b class="arrow"></b></span>
        ${kind === 'marker' ? '<span class="plumb"></span><span class="pin"></span>' : '<span class="ghost"></span>'}`);
      document.body.appendChild(demo);
      const types = {
        marker: { type: 'checkin', label: 'Check-in Desk', icon: 'ticket', kind: 'marker' },
        prop: { type: 'xray', label: 'X-ray Table', icon: 'xray', kind: 'prop', replace: true },
        heli: { type: 'heli', label: 'Helipad', icon: 'heli', kind: 'heli' },
      };
      NZA.open(APP, Object.assign({ dept: 'Los Santos Medical', snapStep: 15, max: 25, locale: {} }, types[kind] || types.marker));
      const far = bad === 'far' || bad === '1';
      NZA.apps[APP].msg.state({
        heading: kind === 'prop' ? 165 : 87.5, height: kind === 'prop' ? 0 : 0.1, dist: far ? 31.4 : 4.2, max: 25,
        valid: !bad, reason: far ? 'far' : (bad ? 'nosurface' : null), snap: kind === 'prop', snapStep: 15,
        coords: { x: 307.4, y: -595.1, z: 43.28 }, keys: { fast: kind === 'heli', turn: kind === 'marker', fine: false, lift: false },
      });
    },
  });
})();
