/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Blood services (app 'donation')

   One app, four modes (Lua sends `mode` in the open data):
     donate  the donation minigame (bottom ProcPanel + collection monitor device):
               1 Inflate the cuff   hold Space, let go inside the band
               2 Pump with the pulse  Space as each pulse peak crosses the window, until the bag is full
               3 Seal the bag       C clamp the line, hold E to slide the needle out
             → donation:progress { ml } (throttled), donation:finish { score, ml }, donation:abort
             Lua then sends 'result' (server outcome: ml, usable, serial, bloodType, dest, label, grade)
     watch   the donor's view while a medic draws (no focus): collection monitor only
             Lua sends 'watch' { ml, active, done, bt }
     bank    blood bank window (UI v5): stock by group, units + expiry, fill an empty bag, your
             bags (deposit), log → donation:bank { action, serial?, type? } → { ok, msg, data }
     label   the printed label of a blood bag (using the item)
   Every mode: donation:close (router).

   Shared helpers for the IV stand app: window.NZABlood = { labelHTML, bagSVG, barcode, fmtType,
   dateText, relDays, expiryTone }.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'donation';
  const { esc, clamp } = NZA;
  const icon = (n) => NZA.icon(n);

  let Lc = {};
  const T = (k, fb) => (Lc[k] !== undefined ? Lc[k] : fb);
  const F = (s, ...a) => { let i = 0; return String(s).replace(/%[sd]/g, () => (a[i++] ?? '')); };
  const DAY = 86400;
  const TYPES = ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'];
  const keyCap = (code) => {
    const c = String(code || '');
    if (c === 'Space') return T('key_space', 'Space');
    if (/^Key[A-Z]$/.test(c)) return c.slice(3);
    if (/^Digit\d$/.test(c)) return c.slice(5);
    if (c === 'Enter') return 'Enter';
    return c;
  };

  /* ═══════════════════════════ SHARED: label, bag, barcode ═══════════════════════════ */

  const fmtType = (t) => String(t || '?').replace('-', '−');
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  function dateText(sec) {
    if (!sec) return '--';
    const d = new Date(sec * 1000);
    return `${String(d.getUTCDate()).padStart(2, '0')} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
  }
  function relDays(sec, now) {
    if (!sec || !now) return '';
    const d = (sec - now) / DAY;
    if (d < 0) { const a = Math.ceil(-d); return a <= 1 ? T('rel_expired_today', 'expired') : F(T('rel_expired_ago', 'expired %s d ago'), a); }
    if (d < 1) return F(T('rel_hours', 'in %s h'), Math.max(1, Math.round(d * 24)));
    return F(T('rel_days', 'in %s d'), Math.round(d));
  }
  function expiryTone(sec, now, warnDays = 3) {
    if (!sec || !now) return '';
    if (sec < now) return 'red';
    if (sec - now < warnDays * DAY) return 'amber';
    return '';
  }

  // Code-128-looking bars generated from the serial (decorative, stable per serial)
  function barcode(serial, w = 180, h = 34) {
    const s = String(serial || 'BB-000000');
    let x = 0; const bars = [];
    let seed = 7;
    for (let i = 0; i < s.length; i++) seed = (seed * 31 + s.charCodeAt(i)) >>> 0;
    const rnd = () => { seed = (seed * 1103515245 + 12345) >>> 0; return seed / 4294967296; };
    const quiet = 6;
    x = quiet;
    const pattern = [2, 1, 1, 2, 3, 2];
    pattern.forEach((pw, i) => { if (i % 2 === 0) bars.push([x, pw]); x += pw; });
    for (let i = 0; i < s.length * 2 + 6; i++) {
      for (let j = 0; j < 6; j++) {
        const pw = 1 + Math.floor(rnd() * 3.2);
        if (j % 2 === 0) bars.push([x, pw]);
        x += pw;
      }
    }
    [2, 3, 3, 1, 1, 1, 2].forEach((pw, i) => { if (i % 2 === 0) bars.push([x, pw]); x += pw; });
    const total = x + quiet;
    return `<svg class="bb-bars" viewBox="0 0 ${total} ${h}" preserveAspectRatio="none" width="${w}" height="${h}">${bars.map(([bx, bw]) => `<rect x="${bx}" y="0" width="${bw}" height="${h}"/>`).join('')}</svg>`;
  }

  let svgId = 0;
  // blood / saline bag drawing; fill 0..1
  function bagSVG({ fill = 1, kind = 'blood', type = '', w = 74, h = 104, label = true } = {}) {
    const id = `bb${++svgId}`;
    const f = clamp(fill, 0, 1);
    const top = 16, bottom = 92, inner = bottom - top;
    const level = bottom - inner * f;
    const blood = kind === 'blood';
    const liquid = blood ? `url(#${id}g)` : 'rgba(170,215,230,.30)';
    return `<svg class="bb-bag ${blood ? 'blood' : 'saline'}" viewBox="0 0 74 104" width="${w}" height="${h}">
      <defs>
        <linearGradient id="${id}g" x1="0" x2="1" y1="0" y2="0"><stop offset="0" stop-color="#5c0f14"/><stop offset=".45" stop-color="#9d1b22"/><stop offset="1" stop-color="#5a0c12"/></linearGradient>
        <clipPath id="${id}c"><path d="M12 14 Q12 8 18 8 H56 Q62 8 62 14 V86 Q62 94 54 94 H20 Q12 94 12 86 Z"/></clipPath>
      </defs>
      <path class="hang" d="M31 8 V3 H43 V8" />
      <circle class="hole" cx="37" cy="5.5" r="1.6"/>
      <g clip-path="url(#${id}c)">
        <rect x="10" y="${level.toFixed(2)}" width="56" height="${(100 - level).toFixed(2)}" fill="${liquid}"/>
        ${f > 0.02 && f < 0.995 ? `<path class="surf" d="M10 ${level.toFixed(2)} Q24 ${(level - 1.4).toFixed(2)} 37 ${level.toFixed(2)} T66 ${level.toFixed(2)}"/>` : ''}
        <rect x="14" y="10" width="7" height="80" class="shine"/>
      </g>
      <path class="shell" d="M12 14 Q12 8 18 8 H56 Q62 8 62 14 V86 Q62 94 54 94 H20 Q12 94 12 86 Z"/>
      ${[0.25, 0.5, 0.75].map(g => `<path class="grad" d="M54 ${(bottom - inner * g).toFixed(1)} H61"/>`).join('')}
      ${label ? `<rect class="lab" x="22" y="30" width="30" height="22" rx="2"/><text class="labt" x="37" y="46" text-anchor="middle">${esc(blood ? fmtType(type || '') : '0.9%')}</text>` : ''}
      <path class="port" d="M30 94 V100 M44 94 V100"/>
    </svg>`;
  }

  // the printed blood bag label (white paper, ISBT style; Rh negative printed inverted)
  function labelHTML(m = {}, o = {}) {
    const type = m.type || '?';
    const abo = String(type).replace(/[+-]/, '');
    const neg = /-/.test(type);
    const now = o.now || m.now;
    const tone = expiryTone(m.expires, now, o.warnDays || m.warnDays || 3);
    const cross = o.cross;   // { state: 'ok'|'bad'|'unknown', text }
    return `<div class="bb-label ${o.small ? 'sm' : ''} ${m.expired ? 'expired' : ''}">
      <div class="bb-head"><span class="bb-logo">${icon('drop')}</span><b>${esc(T('label_org', 'REGIONAL BLOOD SERVICE'))}</b><span class="bb-site">${esc(T('label_site', 'Los Santos'))}</span></div>
      <div class="bb-code">${barcode(m.serial, o.small ? 150 : 196, o.small ? 26 : 34)}<div class="bb-serial">${esc(m.serial || '--')}</div></div>
      <div class="bb-mid">
        <div class="bb-abo ${neg ? 'neg' : 'pos'}"><b>${esc(abo)}</b><span>${esc(neg ? T('rh_neg', 'Rh NEG') : T('rh_pos', 'Rh POS'))}</span></div>
        <div class="bb-prod">
          <div class="p">${esc(m.product || T('product', 'Red cells in SAG-M'))}</div>
          <div class="v"><b>${esc(Math.round(m.ml || 0))}</b> mL</div>
          <div class="d"><span>${esc(T('label_collected', 'Collected'))}</span><b>${esc(dateText(m.created))}</b></div>
          <div class="d ${tone}"><span>${esc(T('label_expires', 'Expires'))}</span><b>${esc(dateText(m.expires))}</b></div>
        </div>
      </div>
      <div class="bb-foot"><span>${esc(T('label_donor', 'Donor'))} <b>${esc(m.donor || '--')}</b></span><span>${esc(T('label_store', 'Store at 2-6 °C'))}</span></div>
      ${m.expired ? `<div class="bb-stamp">${esc(T('label_expired', 'EXPIRED'))}</div>` : ''}
      ${cross ? `<div class="bb-cross ${cross.state}">${icon(cross.state === 'ok' ? 'check' : 'alert')}<span>${esc(cross.text)}</span></div>` : ''}
    </div>`;
  }

  window.NZABlood = { labelHTML, bagSVG, barcode, fmtType, dateText, relDays, expiryTone };

  /* ═══════════════════════════ COLLECTION SCALE (device, top-left) ═══════════════════════════
     Generic industrial device (model code, no brand): bag gauge + instrument list + a scrolling
     pulse lane. The donor's pulse wave runs right → left; every systolic peak crosses the squeeze
     window; squeezes are stamped on the wave and scroll away with it. */

  // pleth shape over one beat, systolic peak at phase 0.5 (matches the game's beat timing)
  const g2 = (x, m, s) => Math.exp(-((x - m) * (x - m)) / (2 * s * s));
  const pleth = (p) => 0.08 + 0.92 * g2(p, 0.5, 0.05) + 0.3 * g2(p, 0.69, 0.055) + 0.12 * g2(p, 0.42, 0.06) - 0.05 * g2(p, 0.6, 0.02);

  function Lane(canvas) {
    const ctx = canvas.getContext('2d');
    let W = 0, H = 0, S = 1;
    const fit = () => {
      const f = NZA.fitCanvas(canvas);
      W = f.w; H = f.h; S = f.scale;
    };
    return {
      // st = { pos (beat position), bpm, window (good, in beats), marks [{ pos, g }], showWindow }
      draw(st) {
        fit();
        if (!W || !H) return;
        ctx.clearRect(0, 0, W, H);
        const pxPerBeat = 92 * S;
        const x0 = W * 0.26;
        const toX = (pos) => x0 + (pos - st.pos) * pxPerBeat;
        const base = H * 0.86, amp = H * 0.66;
        // grid
        ctx.strokeStyle = 'rgba(63,208,255,.07)'; ctx.lineWidth = 1;
        for (let gx = (x0 % (pxPerBeat / 4)); gx < W; gx += pxPerBeat / 4) { ctx.beginPath(); ctx.moveTo(gx, 0); ctx.lineTo(gx, H); ctx.stroke(); }
        // squeeze window
        if (st.showWindow) {
          const half = st.window * pxPerBeat;
          const gr = ctx.createLinearGradient(x0 - half, 0, x0 + half, 0);
          gr.addColorStop(0, 'rgba(15,212,196,0)'); gr.addColorStop(0.5, 'rgba(15,212,196,.22)'); gr.addColorStop(1, 'rgba(15,212,196,0)');
          ctx.fillStyle = gr; ctx.fillRect(x0 - half, 0, half * 2, H);
          ctx.strokeStyle = 'rgba(15,212,196,.85)'; ctx.lineWidth = 1.5 * S;
          ctx.setLineDash([4 * S, 4 * S]); ctx.beginPath(); ctx.moveTo(x0, 2 * S); ctx.lineTo(x0, H - 2 * S); ctx.stroke(); ctx.setLineDash([]);
        }
        // wave: the part that already passed is dim, the incoming part is bright
        const path = (from, to) => {
          ctx.beginPath();
          for (let x = from; x <= to; x += 2) {
            const pos = st.pos + (x - x0) / pxPerBeat;
            const y = base - pleth(((pos % 1) + 1) % 1) * amp;
            if (x === from) ctx.moveTo(x, y); else ctx.lineTo(x, y);
          }
          ctx.stroke();
        };
        ctx.lineWidth = 2 * S; ctx.lineJoin = 'round';
        ctx.strokeStyle = 'rgba(63,208,255,.3)'; path(0, Math.floor(x0));
        ctx.strokeStyle = '#3fd0ff'; ctx.shadowColor = '#3fd0ff'; ctx.shadowBlur = 6 * S; path(Math.floor(x0), W); ctx.shadowBlur = 0;
        // squeeze marks on the peaks
        (st.marks || []).forEach(m => {
          const x = toX(m.pos);
          if (x < -10 || x > W + 10) return;
          const y = base - pleth(((m.pos % 1) + 1) % 1) * amp - 9 * S;
          const col = { perfect: '#0fd4c4', good: '#f2f4f5', off: '#e5a50a', miss: '#e5484d' }[m.g] || '#fff';
          ctx.fillStyle = col; ctx.strokeStyle = col; ctx.lineWidth = 2 * S;
          if (m.g === 'miss') {
            const r = 4 * S; ctx.beginPath(); ctx.moveTo(x - r, y - r); ctx.lineTo(x + r, y + r); ctx.moveTo(x + r, y - r); ctx.lineTo(x - r, y + r); ctx.stroke();
          } else {
            const r = (m.g === 'perfect' ? 5 : 4) * S;
            ctx.beginPath(); ctx.moveTo(x, y - r); ctx.lineTo(x + r, y); ctx.lineTo(x, y + r); ctx.lineTo(x - r, y); ctx.closePath(); ctx.fill();
          }
        });
      },
    };
  }

  // host = parent element; mode 'run' (squeeze window) | 'watch'
  function Device(host, { watch = false } = {}) {
    const root = NZA.el('div', `dn-dev nza-int ${watch ? 'watch' : ''}`);
    root.innerHTML = `
      <div class="dn-bezel">
        <div class="dn-top"><span class="dn-model">${esc(T('dev_model', 'CM-450'))}</span><span class="dn-kind">${esc(T('dev_kind', 'Collection scale'))}</span><span class="dn-led"></span></div>
        <div class="dn-scr">
          <div class="dn-grid">
            <div class="dn-gauge"><div class="dn-bag"></div><div class="dn-ticks"></div></div>
            <div class="dn-list">
              <div class="dn-row vol"><span>${esc(T('dev_volume', 'Volume'))}</span><b><span class="dn-odo"></span><i class="dn-of"></i></b></div>
              <div class="dn-row flow"><span>${esc(T('dev_flow', 'Flow'))}</span><b><em class="fv">0.0</em><i>mL/s</i></b></div>
              <div class="dn-row hr"><span>${esc(T('dev_hr', 'Donor pulse'))}</span><b><em class="hi">${icon('heart')}</em><em class="hv">--</em><i>bpm</i></b></div>
              <div class="dn-row time"><span>${esc(T('dev_time', 'Elapsed'))}</span><b><em class="tv">00:00</em></b></div>
            </div>
          </div>
          <div class="dn-lane"><canvas></canvas><span class="dn-lane-l">${esc(T('dev_lane', 'Pleth'))}</span><span class="dn-lane-r">${esc(watch ? '' : T('dev_window', 'squeeze window'))}</span></div>
          <div class="dn-state"></div>
        </div>
        <div class="dn-btns"><span class="dn-btn"></span><span class="dn-btn"></span><span class="dn-knob"></span></div>
        <div class="dn-sticker">${esc(T('dev_sticker', 'Single use · sterile line'))}</div>
      </div>`;
    host.appendChild(root);
    const q = s => root.querySelector(s);
    const odo = NZA.ui.FlipClock(q('.dn-odo'), { value: '000' });
    const lane = Lane(q('.dn-lane canvas'));
    let lastMl = -1, lastBag = -1, size = 500;
    const api = {
      el: root,
      setup({ size: sz = 500 } = {}) {
        size = sz;
        q('.dn-of').textContent = `/ ${sz} mL`;
        q('.dn-ticks').innerHTML = [1, 0.8, 0.6, 0.4, 0.2, 0].map(f => `<span>${Math.round(sz * f)}</span>`).join('');
        lastMl = -1; lastBag = -1;
        api.set({ ml: 0, flow: 0 });
      },
      set({ ml = 0, flow = 0, elapsed = null } = {}) {
        const m = Math.floor(ml);
        if (m !== lastMl) { lastMl = m; odo.set(String(clamp(m, 0, 999)).padStart(3, '0')); }
        const pct = Math.round(clamp(ml / size, 0, 1) * 60) / 60;
        if (pct !== lastBag) { lastBag = pct; q('.dn-bag').innerHTML = bagSVG({ fill: pct, kind: 'blood', label: false, w: 62, h: 88 }) + '<span class="dn-tube"></span>'; }
        const tube = q('.dn-tube');
        if (tube) tube.classList.toggle('on', flow > 0.5);
        q('.fv').textContent = flow.toFixed(1);
        q('.flow').classList.toggle('low', flow > 0 && flow < 3.5);
        if (elapsed !== null) q('.tv').textContent = NZA.fmt.time(elapsed);
      },
      lane(st) { lane.draw(st); },
      bpm(n) { q('.hv').textContent = Math.round(n); },
      pulse() { const h = q('.hr'); h.classList.remove('beat'); void h.offsetWidth; h.classList.add('beat'); },
      state(text, tone = '') { const s = q('.dn-state'); s.className = `dn-state ${tone}`; s.textContent = text || ''; q('.dn-led').className = `dn-led ${tone}`; },
      destroy() { root.remove(); },
    };
    return api;
  }

  /* ═══════════════════════════ DONATION MINIGAME ═══════════════════════════ */

  const G = { on: false };

  function gameStart(el, d) {
    gameStop();
    const data = d.data || {};
    const flow = Object.assign({ perfect: 0.06, good: 0.15, maxFlow: 12, trickle: 1.6, ease: 0.35, cuffBand: [40, 60], cuffRate: 38, sealHold: 1.5 }, data.flow || {});
    const keys = Object.assign({ squeeze: 'Space', clamp: 'KeyC', needle: 'KeyE' }, d.keys || {});
    Object.assign(G, {
      on: true, el, data, flow, keys, self: !!d.self, step: 1, t: 0, last: performance.now(), raf: 0,
      cuff: { p: 0, pumping: false, tries: 0, acc: 0, done: false },
      beat: { base: data.bpm || 72, bpm: data.bpm || 72, pos: 0.12, hits: {}, missed: {}, lastBeat: -1 },
      q: 0.15, flowNow: 0, ml: 0, target: data.target || 450, size: data.bagSize || 500,
      grades: [], dots: [], marks: [], streak: 0, best: 0, weakT: 0, lastPost: 0, lastPostMl: 0,
      seal: { clamped: false, hold: 0, holding: false, restarts: 0, done: false },
      finished: false, result: null,
    });
    // configured key codes → handlers (the router looks keys up by e.key, then e.code)
    Object.values(keys).forEach(code => {
      if (!def.keys[code]) def.keys[code] = (e) => gameKey(e, true);
      if (!def.keysUp[code]) def.keysUp[code] = (e) => gameKey(e, false);
    });
    const wrap = NZA.el('div', 'dn-wrap');
    el.appendChild(wrap);
    G.wrap = wrap;
    G.pp = NZA.ui.ProcPanel(wrap, {
      step: 1, total: 3, tag: T('tag', 'Blood donation'),
      steps: [T('s1_title', 'Inflate the cuff'), T('s2_title', 'Pump with the pulse'), T('s3_title', 'Seal the bag')],
      hints: [{ keys: [keyCap(keys.squeeze)], label: T('hint_squeeze', 'squeeze') }],
      onAbort: () => { if (!G.finished) NZA.post(`${APP}:abort`, {}); },
      onTool: (k) => toolClick(k),
    });
    G.dev = Device(wrap);
    G.dev.setup({ size: G.size });
    G.dev.bpm(G.beat.bpm);
    G.dev.state(T('st_cuff', 'Cuff deflated'), 'dim');
    setStep(1);
    G.raf = requestAnimationFrame(loop);
  }

  function gameStop() {
    if (G.raf) cancelAnimationFrame(G.raf);
    if (G.pp) G.pp.destroy();
    if (G.dev) G.dev.destroy();
    if (G.wrap) G.wrap.remove();
    if (G.final) G.final.remove();
    Object.keys(G).forEach(k => delete G[k]);
    G.on = false;
  }

  function tools() {
    const k = G.keys;
    const s = G.step;
    return [
      { key: keyCap(k.squeeze), label: T('tool_cuff', 'Arm cuff'), icon: 'gauge', state: s === 1 ? 'active' : 'done' },
      { key: keyCap(k.squeeze), label: T('tool_squeeze', 'Squeeze ball'), icon: 'heart', state: s === 2 ? 'active' : s > 2 ? 'done' : 'locked' },
      { key: keyCap(k.clamp), label: T('tool_clamp', 'Line clamp'), icon: 'clamp', state: s < 3 ? 'locked' : G.seal.clamped ? 'done' : 'active' },
      { key: keyCap(k.needle), label: T('tool_needle', 'Needle out'), icon: 'needle', state: s < 3 || !G.seal.clamped ? 'locked' : G.seal.done ? 'done' : 'active' },
    ];
  }

  function setStep(n) {
    G.step = n;
    const k = G.keys;
    const self = G.self;
    if (n === 1) {
      G.pp.set({
        step: 1, title: T('s1_title', 'Inflate the cuff'),
        text: F(T(self ? 's1_text_self' : 's1_text', 'Hold {%s} to pump the arm cuff and let go inside the band. The veins fill, then the needle goes in.'), keyCap(k.squeeze)),
        stats: [
          { id: 'band', label: T('st_band', 'Band'), value: `${G.flow.cuffBand[0]}-${G.flow.cuffBand[1]}`, unit: 'mmHg' },
          { id: 'tries', label: T('st_tries', 'Tries'), value: `${G.cuff.tries}/3` },
        ],
        wide: { label: T('w_cuff', 'Cuff'), value: '0', unit: 'mmHg', meter: { value: 0, zone: [G.flow.cuffBand[0] / 100, G.flow.cuffBand[1] / 100] }, caption: F(T('w_cuff_cap', 'Let go between %s and %s mmHg'), G.flow.cuffBand[0], G.flow.cuffBand[1]) },
        tools: tools(),
        hints: [{ keys: [keyCap(k.squeeze)], label: T('hint_hold_pump', 'hold to pump') }],
      });
    } else if (n === 2) {
      G.pp.set({
        step: 2, title: T('s2_title', 'Pump with the pulse'),
        text: F(T(self ? 's2_text_self' : 's2_text', 'Press {%s} as each pulse peak crosses the window on the scale. A steady pump keeps the blood flowing.'), keyCap(k.squeeze)),
        stats: [
          { id: 'flow', label: T('st_flow', 'Flow'), value: '0.0', unit: 'mL/s' },
          { id: 'streak', label: T('st_streak', 'Streak'), value: '×0' },
          { id: 'missed', label: T('st_missed', 'Missed'), value: '0' },
        ],
        wide: { label: T('w_beat', 'Timing'), value: '--', unit: '', meter: { value: 0, zone: [0.7, 1] }, caption: T('w_beat_cap', 'Keep it above 70%') },
        tools: tools(),
        hints: [{ keys: [keyCap(k.squeeze)], label: T('hint_squeeze', 'squeeze') }],
      });
      G.dev.state(T('st_running', 'Collecting'), 'teal');
    } else if (n === 3) {
      G.pp.set({
        step: 3, title: T('s3_title', 'Seal the bag'),
        text: F(T('s3_text', 'Press {%s} to clamp the line, then hold {%s} to slide the needle out and press on the gauze.'), keyCap(k.clamp), keyCap(k.needle)),
        stats: [
          { id: 'ml', label: T('st_collected', 'Collected'), value: Math.round(G.ml), unit: 'mL' },
          { id: 'rhythm', label: T('st_rhythm', 'Rhythm'), value: rhythmPct(), unit: '%' },
        ],
        wide: { label: T('w_seal', 'Needle out'), value: '0', unit: '%', meter: { value: 0 }, caption: T('w_seal_cap', 'Clamp first, then hold') },
        tools: tools(),
        hints: [{ keys: [keyCap(k.clamp)], label: T('hint_clamp', 'clamp') }, { keys: [keyCap(k.needle)], label: T('hint_hold_needle', 'hold: needle out') }],
      });
      G.dev.state(T('st_full', 'Bag full · clamp the line'), 'teal');
      NZA.audio.success();
    }
  }

  function grade(g, pos) {
    const map = { perfect: 1, good: 0.65, off: 0.2, miss: 0 };
    G.marks.push({ pos: pos !== undefined ? pos : G.beat.pos, g });
    if (G.marks.length > 14) G.marks.shift();
    G.grades.push(map[g]);
    G.dots.push(g);
    if (G.dots.length > 24) G.dots.shift();
    G.q = G.q + (map[g] - G.q) * 0.38;
    if (g === 'perfect' || g === 'good') { G.streak++; G.best = Math.max(G.best, G.streak); } else G.streak = 0;
    const label = { perfect: T('g_perfect', 'Clean'), good: T('g_good', 'Close'), off: T('g_off', 'Off'), miss: T('g_miss', 'Missed') }[g];
    const tone = { perfect: 'teal', good: '', off: 'amber', miss: 'red' }[g];
    const q = Math.round(clamp(G.q, 0, 1) * 100);
    G.pp.wide({ value: `${q}`, unit: '%', tone: q >= 70 ? 'teal' : q < 35 ? 'red' : 'amber', meter: { value: q / 100, zone: [0.7, 1], tone: q < 35 ? 'red' : q < 70 ? 'amber' : '' }, caption: label, captionTone: tone });
    G.pp.stat('streak', { value: `×${G.streak}`, tone: G.streak >= 8 ? 'teal' : '' });
    G.missed = (G.missed || 0) + (g === 'miss' ? 1 : 0);
    if (G.step === 2) G.pp.stat('missed', { value: String(G.missed), tone: G.missed >= 5 ? 'red' : G.missed >= 2 ? 'amber' : '' });
  }

  function rhythmPct() {
    if (!G.grades || !G.grades.length) return '--';
    return String(Math.round(G.grades.reduce((a, b) => a + b, 0) / G.grades.length * 100));
  }

  // belt clicks (mouse) do what the keys do
  function toolClick(key) {
    if (!G.on || G.final) return;
    const k = G.keys;
    if (key === keyCap(k.squeeze) && G.step === 2) squeeze();
    else if (key === keyCap(k.clamp) && G.step === 3) gameKey({ code: k.clamp, repeat: false }, true);
  }

  function squeeze() {
    if (G.step !== 2) return;
    const b = G.beat;
    const idx = Math.floor(b.pos);
    const ph = b.pos - idx;
    const err = Math.abs(ph - 0.5);
    let g;
    if (b.hits[idx]) g = 'off';
    else if (err <= G.flow.perfect) g = 'perfect';
    else if (err <= G.flow.good) g = 'good';
    else g = 'off';
    if (!b.hits[idx]) b.hits[idx] = true;
    grade(g, b.pos);
    NZA.audio.click(g === 'perfect' ? 980 : g === 'good' ? 760 : 320);
    G.wrap.classList.remove('sq'); void G.wrap.offsetWidth; G.wrap.classList.add('sq');
  }

  function loop(now) {
    if (!G.on) return;
    const dt = Math.min(0.1, (now - G.last) / 1000);
    G.last = now;
    G.t += dt;
    const b = G.beat;
    b.bpm = b.base + Math.sin(G.t / 7) * 3 + (G.step === 2 ? clamp((G.t - 6) / 40, 0, 1) * 4 : 0);
    const prevPos = b.pos;
    b.pos += dt * b.bpm / 60;
    const idx = Math.floor(b.pos);
    const ph = b.pos - idx;
    // the heartbeat itself (phase 0.5)
    if (Math.floor(prevPos - 0.5) !== Math.floor(b.pos - 0.5)) {
      G.dev.pulse();
      NZA.audio.tone(64, 80, { vol: 0.12 }); NZA.audio.tone(56, 70, { vol: 0.08, at: 0.13 });
    }
    // browser preview: a demo hand squeezes (mostly) in time with the pulse
    if (G.auto && G.step === 2) {
      if (G.autoAt === undefined) G.autoAt = 0.5 + (Math.random() * 0.16 - 0.07);
      const pIdx = Math.floor(prevPos), pPh = prevPos - pIdx;
      if ((pIdx === idx && pPh < G.autoAt && ph >= G.autoAt) || (pIdx !== idx && ph >= G.autoAt)) {
        if (!b.hits[idx]) squeeze();
        G.autoAt = 0.5 + (Math.random() * 0.16 - 0.07);
      }
    }
    // a beat window passed without a squeeze → miss
    if (G.step === 2) {
      const prevIdx = Math.floor(prevPos);
      const prevPh = prevPos - prevIdx;
      const lim = 0.5 + G.flow.good;
      if ((prevIdx === idx && prevPh < lim && ph >= lim) || (prevIdx !== idx && prevPh < lim)) {
        const k = prevIdx === idx ? idx : prevIdx;
        if (!b.hits[k] && !b.missed[k] && G.t > 1.2) { b.missed[k] = true; grade('miss', k + 0.5); }
      }
    }

    const uiTick = now - (G.uiAt || 0) > 33;
    if (uiTick) G.uiAt = now;
    const slow = now - (G.slowAt || 0) > 220;
    if (slow) G.slowAt = now;
    if (G.step === 1) {
      const c = G.cuff;
      if (c.pumping) c.p = Math.min(110, c.p + G.flow.cuffRate * dt);
      else if (!c.done) c.p = Math.max(0, c.p - 2 * dt);
      const band = G.flow.cuffBand;
      if (uiTick) G.pp.wide({ value: String(Math.round(c.p)), tone: c.p > band[1] ? 'red' : c.p >= band[0] ? 'teal' : '', meter: { value: c.p / 100, zone: [band[0] / 100, band[1] / 100], tone: c.p > band[1] ? 'red' : '' } });
      if (c.p >= 100 && c.pumping) { c.pumping = false; cuffRelease(); }
    } else if (G.step === 2) {
      const f = G.flow;
      const target = f.trickle + clamp(G.q, 0, 1) * (f.maxFlow - f.trickle);
      const k = 1 - Math.pow(1 - f.ease, dt);
      G.flowNow += (target - G.flowNow) * k;
      G.ml = Math.min(G.target, G.ml + G.flowNow * dt);
      if (slow) G.pp.stat('flow', { value: G.flowNow.toFixed(1), tone: G.flowNow < f.maxFlow * 0.35 ? 'amber' : '' });
      if (G.flowNow < f.maxFlow * 0.3) {
        G.weakT += dt;
        if (G.weakT > 10 && G.t - (G.weakFlashAt || -99) > 20) { G.weakFlashAt = G.t; G.pp.flash('warn', T('flash_weak', 'The flow is weak: pump with every pulse or the line clots.'), 3500); }
      } else G.weakT = 0;
      if (G.ml >= G.target - 0.01) { G.ml = G.target; G.flowNow = 0; setStep(3); }
    } else if (G.step === 3) {
      const s = G.seal;
      if (s.clamped && !s.done) {
        if (s.holding) s.hold = Math.min(G.flow.sealHold, s.hold + dt);
        else if (s.hold > 0) s.hold = Math.max(0, s.hold - dt * 2);
        const p = s.hold / G.flow.sealHold;
        if (uiTick) G.pp.wide({ value: String(Math.round(p * 100)), meter: { value: p }, caption: T('w_seal_hold', 'Keep holding') });
        if (p >= 1) sealDone();
      }
    }
    G.dev.bpm(b.bpm);
    G.dev.set({ ml: G.ml, flow: G.step === 2 ? G.flowNow : 0, elapsed: G.t });
    G.dev.lane({ pos: b.pos, bpm: b.bpm, window: G.flow.good, marks: G.marks, showWindow: G.step === 2 });
    if (now - G.lastPost > 260 && Math.abs(G.ml - G.lastPostMl) >= 1) {
      G.lastPost = now; G.lastPostMl = G.ml;
      NZA.post(`${APP}:progress`, { ml: Math.round(G.ml) });
    }
    G.raf = requestAnimationFrame(loop);
  }

  function cuffRelease() {
    const c = G.cuff;
    if (c.done || G.step !== 1) return;
    const band = G.flow.cuffBand;
    if (c.p < 6) return;
    if (c.p >= band[0] && c.p <= band[1]) {
      const mid = (band[0] + band[1]) / 2;
      c.acc = clamp(1 - Math.abs(c.p - mid) / ((band[1] - band[0]) / 2) * 0.5, 0.5, 1);
      c.done = true;
      G.pp.flash('ok', T('flash_cuff_ok', 'Veins filling. Needle in, the line is running.'));
      G.dev.state(T('st_running', 'Collecting'), 'teal');
      NZA.audio.beep(1200, 70, 0.07);
      setTimeout(() => { if (G.on && G.step === 1) setStep(2); }, 900);
    } else {
      c.tries++;
      G.pp.stat('tries', { value: `${Math.min(c.tries, 3)}/3`, tone: c.tries >= 2 ? 'amber' : '' });
      const msg = c.p > band[1] ? T('flash_cuff_high', 'Too tight - the air is let out. Pump again.') : T('flash_cuff_low', 'Too loose. Pump a little more.');
      G.pp.flash('bad', msg);
      NZA.audio.fail();
      if (c.p > band[1]) c.p = 0;
      if (c.tries >= 3 && c.p <= band[1]) {
        c.acc = 0.35; c.done = true;
        G.pp.flash('warn', T('flash_cuff_auto', 'Good enough - the needle goes in.'));
        setTimeout(() => { if (G.on && G.step === 1) setStep(2); }, 900);
      }
    }
  }

  function sealDone() {
    const s = G.seal;
    if (s.done) return;
    s.done = true;
    G.pp.set({ tools: tools() });
    G.dev.state(T('st_sealed', 'Sealed · label printed'), 'teal');
    const beats = G.grades.length ? G.grades.reduce((a, b) => a + b, 0) / G.grades.length : 0.5;
    const score = Math.round(beats * 100 * 0.8 + G.cuff.acc * 100 * 0.12 + (s.restarts ? 60 : 100) * 0.08);
    G.result = { score: clamp(score, 0, 100), ml: Math.round(G.ml) };
    G.pp.set({ hints: [{ keys: ['Enter'], label: T('hint_finish', 'finish') }] });
    G.pp.complete({
      title: T('done_title', 'Unit collected'),
      text: F(T('done_text', '**%s mL** collected. Best streak ×%s. Press {Enter} to finish.'), Math.round(G.ml), G.best),
      label: T('done_btn', 'Finish'),
      onDone: () => {
        if (G.finished) return;
        G.finished = true;
        NZA.post(`${APP}:finish`, G.result);
        G.pp.set({ title: T('done_wait', 'Labelling the unit...'), titleTone: '' });
      },
    });
  }

  // the server outcome: the printed label + where it went
  function showResult(o = {}) {
    if (!G.on) return;
    if (G.final) G.final.remove();
    const card = NZA.el('div', 'dn-final nza-hud solid nza-pop');
    const usable = o.usable !== false && o.serial;
    const destText = o.dest === 'bank' ? T('res_bank', 'The unit went to the blood bank.') : o.dest === 'donor' ? T('res_donor', 'The unit is in the donor\'s bag.') : o.dest === 'collector' ? T('res_collector', 'The unit is in your bag.') : '';
    card.innerHTML = `
      <div class="dn-fh">${o.grade ? `<span class="grade g-${esc(o.grade)}">${esc(o.grade)}</span>` : ''}<div><div class="nza-label">${esc(T('res_tag', 'Donation complete'))}</div>
        <div class="nza-h">${esc(usable ? F(T('res_title', '%s mL of %s'), o.ml, fmtType(o.bloodType)) : F(T('res_short', 'Only %s mL'), o.ml || 0))}</div>
        <div class="nza-sub">${esc(usable ? destText : T('res_discard', 'Not enough for a unit - the bag was discarded.'))}</div></div></div>
      ${usable ? labelHTML(Object.assign({ now: o.label && o.label.created }, o.label || { serial: o.serial, type: o.bloodType, ml: o.ml })) : ''}
      <div class="dn-ff"><span class="t-dim">${esc(o.count ? F(T('res_count', 'Lifetime donations: %s'), o.count) : '')}</span><button class="btn-teal"><kbd>Enter</kbd>${esc(T('close', 'Close'))}</button></div>`;
    card.querySelector('button').onclick = () => NZA.close(APP);
    G.wrap.appendChild(card);
    G.final = card;
    if (G.pp) G.pp.el.style.display = 'none';
    NZA.audio.success();
  }

  /* ═══════════════════════════ WATCH (donor) ═══════════════════════════ */

  const W = { on: false };
  function watchStart(el, d) {
    watchStop();
    const data = d.data || {};
    W.on = true;
    W.wrap = NZA.el('div', 'dn-wrap watch');
    el.appendChild(W.wrap);
    const col = NZA.el('div', 'dn-col');
    W.wrap.appendChild(col);
    W.note = NZA.el('div', 'dn-note nza-hud');
    W.note.innerHTML = `<span class="ni">${icon('heart')}</span><div><b>${esc(T('watch_title', 'A medic is drawing your blood'))}</b><p>${esc(T('watch_text', 'Relax and keep your arm still. It takes about a minute.'))}</p></div>`;
    col.appendChild(W.note);
    W.dev = Device(col, { watch: true });
    W.dev.setup({ size: data.bagSize || 500 });
    W.dev.state(T('st_running', 'Collecting'), 'teal');
    W.ml = data.ml || 0; W.shown = W.ml; W.last = performance.now(); W.bpm = 74; W.pos = 0;
    W.raf = requestAnimationFrame(watchLoop);
  }
  function watchLoop(now) {
    if (!W.on) return;
    const dt = Math.min(0.1, (now - W.last) / 1000); W.last = now;
    const prev = W.pos; W.pos += dt * W.bpm / 60;
    if (Math.floor(prev) !== Math.floor(W.pos)) W.dev.pulse();
    const diff = W.ml - W.shown;
    const rate = W.done ? 0 : clamp(diff * 2.2, 0, 16);
    W.shown = Math.min(W.ml, W.shown + rate * dt);
    W.dev.bpm(W.bpm + Math.sin(now / 5000) * 2);
    W.dev.set({ ml: W.shown, flow: rate, elapsed: (W.t = (W.t || 0) + dt) });
    W.dev.lane({ pos: W.pos + 0.5, bpm: W.bpm, window: 0.15, marks: [], showWindow: false });
    W.raf = requestAnimationFrame(watchLoop);
  }
  function watchUpdate(u = {}) {
    if (!W.on) return;
    if (typeof u.ml === 'number') W.ml = Math.max(W.ml, u.ml);
    if (u.done && !W.done) {
      W.done = true; W.shown = W.ml;
      W.dev.state(u.bt ? F(T('st_done_type', 'Thank you · group %s'), fmtType(u.bt)) : T('st_done', 'Thank you'), 'teal');
      W.note.querySelector('b').textContent = T('watch_done', 'Donation complete');
      W.note.querySelector('p').textContent = T('watch_done_text', 'Stand up slowly. You may feel light-headed for a few minutes.');
    }
  }
  function watchStop() {
    if (W.raf) cancelAnimationFrame(W.raf);
    if (W.wrap) W.wrap.remove();
    Object.keys(W).forEach(k => delete W[k]);
    W.on = false;
  }

  /* ═══════════════════════════ BLOOD BANK (window) ═══════════════════════════ */

  const BK = { on: false };

  function bankStart(el, d) {
    bankStop();
    BK.on = true;
    BK.el = el;
    BK.data = d.data || {};
    BK.nav = 'stock';
    BK.pick = null;
    BK.busy = false;
    BK.dim = NZA.el('div', 'nza-dim');
    el.appendChild(BK.dim);
    BK.win = NZA.ui.Win(el, {
      title: T('bank_win', 'Blood bank'), sub: BK.data.title || '', width: '1140px', height: '700px',
      nav: navItems(), navValue: 'stock', onNav: (v) => { BK.nav = v; renderBank(); }, onClose: () => NZA.close(APP),
      status: [{ key: 'ESC', label: T('close', 'Close') }, { key: 'F5', label: T('bank_refresh', 'Refresh') }],
    });
    BK.win.el.classList.add('bk-win');
    renderBank();
  }
  function bankStop() {
    if (BK.win) BK.win.destroy();
    if (BK.dim) BK.dim.remove();
    Object.keys(BK).forEach(k => delete BK[k]);
    BK.on = false;
  }

  function stockUnits() { return (BK.data.units || []).filter(u => !u.expired); }
  function navItems() {
    const d = BK.data;
    return [
      { group: T('bank_grp_bank', 'Bank') },
      { id: 'stock', label: T('bank_nav_stock', 'Stock'), icon: 'database', tally: stockUnits().length },
      { id: 'fill', label: T('bank_nav_fill', 'Issue a unit'), icon: 'bloodbag', tally: d.needEmpty ? (d.empty || 0) : undefined },
      { group: T('bank_grp_you', 'You') },
      { id: 'mine', label: T('bank_nav_mine', 'Your bags'), icon: 'bag', tally: (d.mine || []).length },
      { id: 'log', label: T('bank_nav_log', 'Log'), icon: 'history' },
    ];
  }

  async function bankAction(action, extra = {}) {
    if (BK.busy) return;
    BK.busy = true;
    BK.win.el.classList.add('busy');
    const res = await NZA.post(`${APP}:bank`, Object.assign({ action }, extra));
    BK.busy = false;
    if (!BK.on) return;
    BK.win.el.classList.remove('busy');
    if (res && res.data) BK.data = res.data;
    if (res && res.ok === false && res.msg) NZA.toast({ title: T('bank_win', 'Blood bank'), message: res.msg, type: 'error' });
    if (res && res.ok && !NZA.inGame && res.msg) NZA.toast({ title: T('bank_win', 'Blood bank'), message: res.msg });
    BK.win.setNav(navItems());
    renderBank();
  }

  function typeTiles(sel) {
    const d = BK.data;
    const max = Math.max(4, ...((d.types || []).map(t => t.units)));
    return `<div class="bk-types">${(d.types || TYPES.map(t => ({ type: t, units: 0, ml: 0 }))).map(t => `
      <button class="bk-type ${sel === t.type ? 'on' : ''} ${t.units ? '' : 'none'} ${t.type === 'O-' ? 'uni' : ''}" data-type="${esc(t.type)}" ${t.type === 'O-' ? `title="${esc(T('universal', 'Universal donor'))}"` : ''}>
        <div class="ty">${esc(fmtType(t.type))}</div>
        <div class="un"><b>${esc(t.units)}</b> ${esc(t.units === 1 ? T('unit', 'unit') : T('units', 'units'))}</div>
        <div class="ml">${esc(t.ml)} mL</div>
        <div class="bar"><i style="width:${clamp(t.units / max, 0, 1) * 100}%"></i></div>
      </button>`).join('')}</div>`;
  }

  function unitRow(u, actions) {
    const d = BK.data;
    const tone = u.expired ? 'red' : u.soon ? 'amber' : '';
    return `<tr class="${u.expired ? 'exp' : ''}">
      <td><span class="bk-ser">${esc(u.serial || '--')}</span></td>
      <td><span class="bk-abo ${/-/.test(u.type) ? 'neg' : ''}">${esc(fmtType(u.type))}</span></td>
      <td><b>${esc(u.ml)}</b> mL</td>
      <td>${esc(u.donor || '--')}</td>
      <td>${esc(dateText(u.created))}</td>
      <td><span class="bk-exp ${tone}">${esc(dateText(u.expires))}<small>${esc(relDays(u.expires, d.now))}</small></span></td>
      <td class="act">${actions(u)}</td>
    </tr>`;
  }

  function renderBank() {
    if (!BK.on) return;
    const d = BK.data;
    const w = BK.win;
    const units = d.units || [];
    const ok = stockUnits();
    const oneg = ok.filter(u => u.type === 'O-').length;
    const totalMl = ok.reduce((a, u) => a + (u.ml || 0), 0);
    w.setMid(`<span class="nz-dot"></span><p>${esc(T('bank_mid', 'Stock'))} <b>${esc(ok.length)} ${esc(T('units', 'units'))}</b> · ${esc((totalMl / 1000).toFixed(1))} L · O− <b>${esc(oneg)}</b></p>`);
    w.act.innerHTML = `<button class="btn-line btn-sm bk-ref">${icon('refresh')}${esc(T('bank_refresh', 'Refresh'))}</button>`;
    w.act.querySelector('.bk-ref').onclick = () => bankAction('refresh');
    let html = '';
    if (BK.nav === 'stock') {
      html = `
        <div class="w-head"><div><h1>${esc(T('bank_stock_h', 'Blood stock'))}</h1><p>${esc(T('bank_stock_p', 'Units are issued first in, first out. Expired units are discarded automatically.'))}</p></div></div>
        <div class="w-stats">
          <div class="w-stat"><div class="nz-tile">${icon('bloodbag')}</div><div><span>${esc(T('bank_s_units', 'Units in stock'))}</span><b>${esc(ok.length)}</b></div></div>
          <div class="w-stat"><div class="nz-tile ${oneg ? '' : 'red'}">${icon('drop')}</div><div><span>${esc(T('bank_s_oneg', 'O− universal'))}</span><b>${esc(oneg)}</b></div></div>
          <div class="w-stat"><div class="nz-tile ${d.soon ? 'amber' : 'mute'}">${icon('clock')}</div><div><span>${esc(F(T('bank_s_soon', 'Expiring in %s days'), d.warnDays || 3))}</span><b>${esc(d.soon || 0)}</b></div></div>
          <div class="w-stat"><div class="nz-tile mute">${icon('bag')}</div><div><span>${esc(T('bank_s_empty', 'Empty bags (you)'))}</span><b>${esc(d.empty || 0)}</b></div></div>
        </div>
        ${typeTiles(null)}
        <div class="w-panel bk-tablep"><div class="w-phead"><div><h2>${esc(T('bank_units', 'Units'))}</h2><p>${esc(F(T('bank_units_p', '%s of %s slots used'), units.length, d.maxStock || 60))}</p></div></div>
          <div class="w-pbody nza-scroll">${units.length ? `<table class="w-table bk-table"><thead><tr><th>${esc(T('col_serial', 'Serial'))}</th><th>${esc(T('col_group', 'Group'))}</th><th>${esc(T('col_volume', 'Volume'))}</th><th>${esc(T('col_donor', 'Donor'))}</th><th>${esc(T('col_collected', 'Collected'))}</th><th>${esc(T('col_expires', 'Expires'))}</th><th></th></tr></thead><tbody>
            ${units.map(u => unitRow(u, x => x.expired
              ? `<button class="btn-red btn-sm" data-act="discard" data-serial="${esc(x.serial)}">${esc(T('bank_discard', 'Discard'))}</button>`
              : `<button class="btn-line btn-sm" data-act="${d.needEmpty ? 'pick' : 'withdraw'}" data-serial="${esc(x.serial)}" data-type="${esc(x.type)}">${esc(d.needEmpty ? T('bank_fill_this', 'Issue') : T('bank_withdraw', 'Withdraw'))}</button>`)).join('')}
          </tbody></table>` : `<div class="nz-empty bk-empty">${icon('bloodbag')}<b>${esc(T('bank_empty', 'The bank is empty'))}</b><span>${esc(T('bank_empty_p', 'Donations from the chairs and the city arrive here.'))}</span></div>`}</div></div>`;
    } else if (BK.nav === 'fill') {
      const sel = BK.pick || (ok[0] && ok[0].type) || 'O-';
      BK.pick = sel;
      const unit = (BK.pickSerial && ok.find(u => u.serial === BK.pickSerial && u.type === sel)) || ok.find(u => u.type === sel);
      const can = unit && (!d.needEmpty || (d.empty || 0) > 0);
      html = `
        <div class="w-head"><div><h1>${esc(T('bank_fill_h', 'Issue a unit'))}</h1><p>${esc(d.needEmpty ? T('bank_fill_p', 'Pick a group. The oldest unit is decanted into one of your empty collection bags and labelled for you.') : T('bank_fill_p2', 'Pick a group. The oldest unit is issued to you, labelled.'))}</p></div></div>
        ${typeTiles(sel)}
        <div class="bk-fill">
          <div class="w-panel bk-prev"><div class="w-phead"><div><h2>${esc(T('bank_issue', 'Unit to issue'))}</h2><p>${esc(unit ? relDays(unit.expires, d.now) : T('bank_none_type', 'No unit of this group in stock'))}</p></div></div>
            <div class="bk-prev-b">${unit ? labelHTML(Object.assign({ product: T('product', 'Red cells in SAG-M') }, unit), { now: d.now, warnDays: d.warnDays }) : `<div class="nz-empty bk-empty">${icon('alert')}<b>${esc(F(T('bank_out_of', 'Out of %s'), fmtType(sel)))}</b><span>${esc(T('bank_out_hint', 'O− can be given to every group.'))}</span></div>`}</div>
          </div>
          <div class="w-panel bk-side"><div class="w-phead"><div><h2>${esc(T('bank_you_carry', 'You carry'))}</h2><p>${esc(T('bank_you_carry_p', 'Collection bags and labelled units'))}</p></div></div>
            <div class="bk-side-b">
              <div class="bk-kv"><span>${icon('bag')}${esc(T('bank_empty_bags', 'Empty bags'))}</span><b class="${d.needEmpty && !(d.empty > 0) ? 't-red' : ''}">${esc(d.empty || 0)}</b></div>
              <div class="bk-kv"><span>${icon('bloodbag')}${esc(T('bank_units_carried', 'Blood units'))}</span><b>${esc((d.mine || []).length)}</b></div>
              ${d.needEmpty && !(d.empty > 0) ? `<div class="bk-note amber">${icon('alert')}<span>${esc(T('bank_need_empty', 'Issuing needs an empty collection bag. Get one from the pharmacy or storage.'))}</span></div>` : ''}
              <button class="btn-teal btn-lg btn-block bk-go" ${can ? '' : 'disabled'}>${icon('bloodbag')}${esc(unit ? F(T('bank_fill_btn', 'Issue %s unit'), fmtType(unit.type)) : T('bank_fill_btn0', 'Issue unit'))}</button>
            </div></div>
        </div>`;
    } else if (BK.nav === 'mine') {
      const mine = d.mine || [];
      html = `
        <div class="w-head"><div><h1>${esc(T('bank_mine_h', 'Your blood bags'))}</h1><p>${esc(T('bank_mine_p', 'Units you carry. Put unused ones back so they stay cold. Expired units are discarded.'))}</p></div></div>
        <div class="bk-mine nza-scroll">${mine.length ? mine.map(m => `
          <div class="bk-card ${m.expired ? 'exp' : ''}">
            ${labelHTML(Object.assign({ product: T('product', 'Red cells in SAG-M') }, m), { small: true, now: d.now, warnDays: d.warnDays })}
            <button class="${m.expired ? 'btn-red' : 'btn-teal'} btn-sm btn-block" data-act="deposit" data-serial="${esc(m.serial)}">${esc(m.expired ? T('bank_discard', 'Discard') : T('bank_deposit', 'Put back in the bank'))}</button>
          </div>`).join('') : `<div class="nz-empty bk-empty">${icon('bag')}<b>${esc(T('bank_mine_none', 'You carry no blood units'))}</b><span>${esc(T('bank_mine_none_p', 'Issue one from the stock, or collect one at a donation chair.'))}</span></div>`}</div>`;
    } else if (BK.nav === 'log') {
      const log = d.log || [];
      const ago = (t) => { const s = Math.max(0, (d.now || 0) - t); if (s < 60) return T('just_now', 'just now'); if (s < 3600) return F(T('min_ago', '%s min ago'), Math.floor(s / 60)); if (s < DAY) return F(T('h_ago', '%s h ago'), Math.floor(s / 3600)); return F(T('d_ago', '%s d ago'), Math.floor(s / DAY)); };
      const chip = { in: ['teal', T('log_in', 'Deposited')], out: ['white', T('log_out', 'Withdrawn')], fill: ['white', T('log_fill', 'Issued')], donated: ['teal', T('log_donated', 'Donated')], seed: ['white', T('log_seed', 'Opening stock')], discard: ['red', T('log_discard', 'Discarded')], expired: ['red', T('log_expired', 'Expired')] };
      html = `
        <div class="w-head"><div><h1>${esc(T('bank_log_h', 'Bank log'))}</h1><p>${esc(T('bank_log_p', 'Every unit in and out of this bank.'))}</p></div></div>
        <div class="w-panel bk-tablep"><div class="w-pbody nza-scroll">${log.length ? `<table class="w-table bk-table"><thead><tr><th>${esc(T('col_event', 'Event'))}</th><th>${esc(T('col_serial', 'Serial'))}</th><th>${esc(T('col_group', 'Group'))}</th><th>${esc(T('col_by', 'By'))}</th><th>${esc(T('col_when', 'When'))}</th></tr></thead><tbody>
          ${log.map(e => { const c = chip[e.action] || ['white', e.action]; return `<tr><td><span class="nz-chip ${c[0]}">${esc(c[1])}</span></td><td><span class="bk-ser">${esc(e.serial || '--')}</span></td><td>${e.type ? `<span class="bk-abo ${/-/.test(e.type) ? 'neg' : ''}">${esc(fmtType(e.type))}</span>` : '--'}</td><td>${esc(e.actor || T('log_system', 'System'))}</td><td>${esc(ago(e.at || 0))}</td></tr>`; }).join('')}
        </tbody></table>` : `<div class="nz-empty bk-empty">${icon('history')}<b>${esc(T('bank_log_none', 'Nothing yet'))}</b></div>`}</div></div>`;
    }
    w.main.innerHTML = html;
    w.main.querySelectorAll('.bk-type').forEach(b => b.onclick = () => {
      BK.pick = b.dataset.type; BK.pickSerial = null;
      if (BK.nav !== 'fill') { BK.nav = 'fill'; w.nav('fill'); }
      renderBank();
    });
    w.main.querySelectorAll('[data-act]').forEach(b => b.onclick = () => {
      const a = b.dataset.act;
      if (a === 'pick') { BK.pick = b.dataset.type; BK.pickSerial = b.dataset.serial; BK.nav = 'fill'; w.nav('fill'); renderBank(); return; }
      bankAction(a, { serial: b.dataset.serial });
    });
    const go = w.main.querySelector('.bk-go');
    if (go) go.onclick = () => {
      const unit = (BK.pickSerial && stockUnits().find(u => u.serial === BK.pickSerial && u.type === BK.pick)) || null;
      bankAction(d.needEmpty ? 'fill' : 'withdraw', { type: BK.pick, serial: unit ? unit.serial : (stockUnits().find(u => u.type === BK.pick) || {}).serial });
      BK.pickSerial = null;
    };
  }

  /* ═══════════════════════════ LABEL (item use) ═══════════════════════════ */

  const LB = { on: false };
  function labelStart(el, d) {
    labelStop();
    LB.on = true;
    const bag = d.bag || {};
    LB.wrap = NZA.el('div', 'lb-wrap');
    LB.wrap.innerHTML = `<div class="nza-dim"></div>
      <div class="lb-card nza-hud solid rail nza-pop">
        <div class="lb-h"><div><div class="nza-label">${esc(T('lb_tag', 'Blood unit'))}</div><div class="nza-h">${esc(F(T('lb_title', 'Group %s · %s mL'), fmtType(bag.type), Math.round(bag.ml || 0)))}</div>
          <div class="nza-sub">${esc(bag.expired ? T('lb_expired', 'This unit has expired. Return it to a blood bank to be discarded.') : F(T('lb_sub', 'Expires %s. Hang it from an IV stand.'), relDays(bag.expires, bag.now)))}</div></div>
          <button class="pill-close">${esc(T('close', 'Close'))}</button></div>
        <div class="lb-body">
          <div class="lb-bag">${bagSVG({ fill: 1, kind: 'blood', type: bag.type, w: 120, h: 168 })}</div>
          ${labelHTML(bag, { now: bag.now, warnDays: bag.warnDays })}
        </div>
        <div class="lb-f"><span><kbd>ESC</kbd> ${esc(T('close', 'Close'))}</span></div>
      </div>`;
    LB.wrap.querySelector('.pill-close').onclick = () => NZA.close(APP);
    el.appendChild(LB.wrap);
  }
  function labelStop() { if (LB.wrap) LB.wrap.remove(); Object.keys(LB).forEach(k => delete LB[k]); LB.on = false; }

  /* ═══════════════════════════ APP ═══════════════════════════ */

  let mode = null;
  const def = {
    escClose: true,
    open(d) {
      Lc = Object.assign({}, d.locale || {});
      this.close();
      mode = d.mode || 'donate';
      this.el.dataset.mode = mode;
      if (mode === 'donate') gameStart(this.el, d);
      else if (mode === 'watch') watchStart(this.el, d);
      else if (mode === 'bank') bankStart(this.el, d);
      else if (mode === 'label') labelStart(this.el, d);
    },
    close() {
      gameStop(); watchStop(); bankStop(); labelStop();
      this.el.innerHTML = '';
      mode = null;
    },
    msg: {
      result(o) { showResult(o || {}); },
      watch(u) { watchUpdate(u || {}); },
      bank(d) { if (BK.on && d) { BK.data = d; BK.win.setNav(navItems()); renderBank(); } },
    },
    keys: {
      Escape() { if (mode === 'donate') return !G.final; return mode === 'watch'; },
      Enter(e) {
        if (mode !== 'donate' || !G.on) return false;
        if (G.final) { NZA.close(APP); return true; }
        return G.pp ? G.pp.key(e) : false;
      },
      F5() { if (mode === 'bank') { bankAction('refresh'); return true; } return false; },
      ' '(e) { return gameKey(e, true); },
      Space(e) { return gameKey(e, true); },
      KeyC(e) { return gameKey(e, true); },
      KeyE(e) { return gameKey(e, true); },
    },
    keysUp: {
      ' '(e) { return gameKey(e, false); },
      Space(e) { return gameKey(e, false); },
      KeyE(e) { return gameKey(e, false); },
    },
    preview() { previewRun(new URLSearchParams(location.search).get('mode') || 'donate'); },
  };

  function gameKey(e, down) {
    if (mode !== 'donate' || !G.on || G.final) return false;
    const code = e.code || (e.key === ' ' ? 'Space' : e.key);
    const k = G.keys;
    if (code === k.squeeze) {
      if (G.step === 1) {
        if (down && !e.repeat) G.cuff.pumping = true;
        if (!down && G.cuff.pumping) { G.cuff.pumping = false; cuffRelease(); }
      } else if (G.step === 2 && down && !e.repeat) squeeze();
      return true;
    }
    if (code === k.clamp && down && G.step === 3 && !G.seal.clamped) {
      G.seal.clamped = true;
      NZA.audio.click(520);
      G.pp.set({ tools: tools() });
      G.pp.flash('ok', T('flash_clamped', 'Line clamped. Now slide the needle out.'));
      G.dev.state(T('st_clamped', 'Line clamped'), 'teal');
      return true;
    }
    if (code === k.needle && G.step === 3) {
      if (!G.seal.clamped) { if (down && !e.repeat) G.pp.flash('bad', T('flash_clamp_first', 'Clamp the line first, or the bag drains back.')); return true; }
      if (down && !e.repeat) { if (G.seal.hold > 0.05 && !G.seal.holding) G.seal.restarts++; G.seal.holding = true; }
      if (!down) G.seal.holding = false;
      return true;
    }
    return false;
  }

  NZA.app(APP, def);

  /* ═══════════════════════════ PREVIEW ═══════════════════════════ */

  const NOW = 1792000000;
  const demoUnits = () => [
    { serial: 'BB-482913', type: 'O-', ml: 450, donor: 'M. Garcia', created: NOW - 9 * DAY, expires: NOW + 26 * DAY },
    { serial: 'BB-118204', type: 'O-', ml: 450, donor: 'City donor', created: NOW - 33 * DAY, expires: NOW + 2 * DAY, soon: true },
    { serial: 'BB-730551', type: 'O+', ml: 450, donor: 'J. Chen', created: NOW - 4 * DAY, expires: NOW + 31 * DAY },
    { serial: 'BB-602117', type: 'O+', ml: 440, donor: 'City donor', created: NOW - 12 * DAY, expires: NOW + 23 * DAY },
    { serial: 'BB-990342', type: 'A+', ml: 450, donor: 'S. Ortiz', created: NOW - 2 * DAY, expires: NOW + 33 * DAY },
    { serial: 'BB-551876', type: 'A-', ml: 450, donor: 'City donor', created: NOW - 20 * DAY, expires: NOW + 15 * DAY },
    { serial: 'BB-204488', type: 'B+', ml: 450, donor: 'D. Wright', created: NOW - 7 * DAY, expires: NOW + 28 * DAY },
    { serial: 'BB-377012', type: 'AB+', ml: 430, donor: 'City donor', created: NOW - 37 * DAY, expires: NOW - 2 * DAY, expired: true },
  ];
  function demoBank() {
    const units = demoUnits();
    const types = TYPES.map(t => { const u = units.filter(x => x.type === t && !x.expired); return { type: t, units: u.length, ml: u.reduce((a, x) => a + x.ml, 0) }; });
    return {
      point: 12, bank: 'lsmd', title: 'Pillbox Medical · Blood bank', now: NOW, warnDays: 3,
      units, types, soon: 1, empty: 2, needEmpty: true, maxStock: 60,
      mine: [
        { slot: 4, serial: 'BB-300918', type: 'O-', ml: 450, donor: 'K. Lee', created: NOW - 3 * DAY, expires: NOW + 32 * DAY },
        { slot: 7, serial: 'BB-118870', type: 'B-', ml: 450, donor: 'City donor', created: NOW - 36 * DAY, expires: NOW - DAY, expired: true },
      ],
      log: [
        { action: 'donated', serial: 'BB-482913', type: 'O-', actor: 'Michael Garcia', at: NOW - 140 },
        { action: 'fill', serial: 'BB-300918', type: 'O-', actor: 'Dr. Ana Ruiz', at: NOW - 1200 },
        { action: 'in', serial: 'BB-602117', type: 'O+', actor: 'Paramedic Cole', at: NOW - 5400 },
        { action: 'expired', serial: 'BB-100223', type: 'A-', actor: null, at: NOW - 3 * 3600 },
        { action: 'donated', serial: 'BB-990342', type: 'A+', actor: 'City donor', at: NOW - 2 * DAY },
        { action: 'seed', serial: 'BB-551876', type: 'A-', actor: null, at: NOW - 20 * DAY },
      ],
    };
  }

  function previewRun(m) {
    if (m === 'bank') {
      let data = demoBank();
      NZA.mock(`${APP}:bank`, (q) => {
        if (q.action === 'fill' || q.action === 'withdraw') {
          const u = data.units.find(x => x.serial === q.serial) || data.units.find(x => x.type === q.type && !x.expired);
          if (!u) return { ok: false, msg: 'No unit of that group in stock.' };
          data.units = data.units.filter(x => x !== u);
          data.mine.unshift(Object.assign({}, u));
          data.empty = Math.max(0, data.empty - 1);
          data.log.unshift({ action: 'fill', serial: u.serial, type: u.type, actor: 'You', at: NOW });
        } else if (q.action === 'deposit' || q.action === 'discard') {
          const u = data.mine.find(x => x.serial === q.serial) || data.units.find(x => x.serial === q.serial);
          data.mine = data.mine.filter(x => x !== u);
          data.units = data.units.filter(x => x !== u);
          if (u && !u.expired && q.action === 'deposit') data.units.push(u);
          data.log.unshift({ action: q.action === 'deposit' && u && !u.expired ? 'in' : 'discard', serial: q.serial, type: u && u.type, actor: 'You', at: NOW });
        }
        data.types = TYPES.map(t => { const u = data.units.filter(x => x.type === t && !x.expired); return { type: t, units: u.length, ml: u.reduce((a, x) => a + x.ml, 0) }; });
        return { ok: true, msg: 'Done', data };
      });
      NZA.demo(APP, { mode: 'bank', data });
    } else if (m === 'label') {
      NZA.demo(APP, { mode: 'label', bag: { serial: 'BB-482913', type: 'O-', ml: 450, donor: 'M. Garcia', created: NOW - 9 * DAY, expires: NOW + 26 * DAY, now: NOW, product: 'Red cells in SAG-M', bagSize: 500 } });
    } else if (m === 'watch') {
      NZA.demo(APP, { mode: 'watch', data: { target: 450, bagSize: 500, ml: 0 } });
      let ml = 0;
      const tm = setInterval(() => { if (!W.on) return clearInterval(tm); ml = Math.min(450, ml + 4); watchUpdate({ ml, active: true }); }, 300);
    } else {
      NZA.mock(`${APP}:finish`, () => {
        setTimeout(() => def.msg.result({
          ml: 450, usable: true, serial: 'BB-730551', bloodType: 'O+', dest: 'bank', count: 4, score: 91, grade: 'A',
          label: { serial: 'BB-730551', type: 'O+', ml: 450, donor: 'Michael Garcia', created: NOW, expires: NOW + 35 * DAY, product: 'Red cells in SAG-M' },
        }), 600);
        return { ok: true };
      });
      setTimeout(() => { if (G.on) G.auto = true; }, 50);
      NZA.demo(APP, {
        mode: 'donate', self: true, keys: { squeeze: 'Space', clamp: 'KeyC', needle: 'KeyE' },
        data: { point: 3, self: true, name: 'Michael Garcia', count: 3, bpm: 72, target: 450, bagSize: 500, typed: true, bloodType: 'O+',
          flow: { perfect: 0.06, good: 0.15, maxFlow: 12, trickle: 1.6, ease: 0.35, cuffBand: [40, 60], cuffRate: 38, sealHold: 1.5 } },
      });
    }
  }

  // screenshot / QA helper: jump the minigame to a state
  def._demo = function (state) {
    if (!G.on) return;
    if (state === 'collect') {
      G.cuff.done = true; G.cuff.acc = 0.9; setStep(2);
      G.ml = 145; G.flowNow = 9.8; G.q = 0.82; G.t = 18; G.streak = 6; G.best = 9;
      ['perfect', 'good', 'perfect', 'off', 'perfect', 'perfect', 'good', 'perfect'].forEach(g => { G.dots.push(g); G.grades.push(1); });
      G.beat.pos = 40.44;
      ['perfect', 'good', 'perfect', 'perfect'].forEach((g, i) => G.marks.push({ pos: 36.5 + i, g }));
      G.pp.stat('streak', { value: '×6' }); grade('perfect', 40.5);
    } else if (state === 'seal') {
      G.cuff.done = true; setStep(2); G.ml = G.target; setStep(3); G.seal.clamped = true; G.seal.hold = 0.9; G.seal.holding = true; G.pp.set({ tools: tools() });
    } else if (state === 'done') {
      G.cuff.done = true; G.cuff.acc = 0.9; G.grades = [1, 1, 0.65, 1, 1]; G.best = 14; setStep(2); G.ml = G.target; setStep(3); G.seal.clamped = true; sealDone();
    }
  };
})();
