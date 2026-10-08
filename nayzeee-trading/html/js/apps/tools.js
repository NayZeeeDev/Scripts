/* ═══════════════════════════════════════════════════════════
   Utility apps: News, Position Size calculator, Settings
   ═══════════════════════════════════════════════════════════ */
(() => {
  const S = NZ.state;
  const icon = NZ.icon;
  const refs = (root) => {
    const r = {};
    root.querySelectorAll('[data-r]').forEach((el) => { r[el.dataset.r] = el; });
    return r;
  };
  const num = (v) => { const n = parseFloat(String(v ?? '').replace(/[,$\s]/g, '')); return isFinite(n) ? n : null; };
  NZ.apps = NZ.apps || {};

  // ── settings (shared with the trader's Settings view) ─────────
  const WALLS = [['teal', 'Teal'], ['graphite', 'Graphite'], ['grid', 'Grid'], ['aurora', 'Aurora']];
  let saveTimer;
  NZ.renderSettings = (host) => {
    const s = S.settings;
    const sw = (key, title, desc) => `<div class="sw-line"><span><b>${title}</b>${desc}</span><span class="sw ${s[key] ? 'on' : ''}" data-sw="${key}"><i></i></span></div>`;
    host.innerHTML = `
      <div class="cols" style="grid-template-columns:1fr 1fr;align-items:start">
        <section class="panel"><div class="p-head"><div><h2>Sound</h2><p>Trading floor audio, synthesised in-device</p></div><button class="btn-ghost" data-a="test">${icon('volume')}Test fill</button></div>
          <div class="set-group">
            ${sw('sounds', 'Sound effects', 'Order fills, alerts, news and system sounds')}
            ${sw('keySounds', 'Keyboard clicks', 'Mechanical key sounds while typing')}
            <div class="sw-line"><span><b>Volume</b><em data-r="vol" style="font-style:normal"></em></span><input type="range" class="range" min="0" max="1" step="0.05" value="${s.volume}" data-r="range" style="width:180px"></div>
          </div></section>
        <section class="panel"><div class="p-head"><div><h2>Trading</h2><p>Speed versus safety</p></div></div>
          <div class="set-group">
            ${sw('confirm', 'Confirm orders', 'Ask before sending orders and flattening everything')}
            ${sw('hotkeys', 'Hotkeys', 'B buy · S sell · F flatten · C cancel · arrows switch symbol')}
            ${sw('compact', 'Compact sidebar', 'Icon-only navigation for more chart room')}
          </div></section>
        <section class="panel" style="grid-column:1/-1"><div class="p-head"><div><h2>Wallpaper</h2><p>Desktop and lock screen background</p></div></div>
          <div class="wall-pick">${WALLS.map(([id, label]) => `<button data-wall="${id}" class="${s.wallpaper === id ? 'on' : ''}"><div class="wall"></div><span>${label}</span></button>`).join('')}</div></section>
      </div>`;
    const r = refs(host);
    const showVol = () => NZ.text(r.vol, Math.round(s.volume * 100) + '%');
    showVol();
    const save = () => { clearTimeout(saveTimer); saveTimer = setTimeout(() => NZ.saveSettings(), 400); };
    host.addEventListener('click', (e) => {
      const t = e.target.closest('[data-sw]');
      if (t) {
        s[t.dataset.sw] = !s[t.dataset.sw];
        t.classList.toggle('on', s[t.dataset.sw]);
        NZ.applySettings();
        NZ.sound.play('click');
        return save();
      }
      const w = e.target.closest('[data-wall]');
      if (w) {
        s.wallpaper = w.dataset.wall;
        host.querySelectorAll('[data-wall]').forEach((b) => b.classList.toggle('on', b === w));
        NZ.applySettings();
        return save();
      }
      if (e.target.closest('[data-a=test]')) NZ.sound.play('fill');
    });
    r.range.addEventListener('input', () => { s.volume = +r.range.value; NZ.applySettings(); showVol(); save(); });
    r.range.addEventListener('change', () => NZ.sound.play('fill'));
  };

  NZ.apps.settings = {
    id: 'settings', glyph: 'gear', title: 'Settings', sub: 'Device & trading preferences', w: 920, h: 640,
    create(ctx) {
      ctx.body.innerHTML = '<div class="view view-pad" style="flex:1"></div>';
      const host = ctx.body.firstElementChild;
      if (!S.profile) {
        host.innerHTML = `<div class="empty">${icon('user')}<b>No trading profile</b><span>Open the trader app first to create your account.</span></div>`;
        return {};
      }
      NZ.renderSettings(host);
      return {};
    },
  };

  // ── news reader ───────────────────────────────────────────────
  NZ.apps.news = {
    id: 'news', glyph: 'news', tone: 'tealink', title: 'Weazel Business', sub: 'Live market newswire', w: 980, h: 720,
    create(ctx) {
      ctx.mid.innerHTML = `<span class="dot"></span><p><b>Live</b> · <span data-r="n"></span></p>`;
      ctx.body.innerHTML = `<div class="view view-pad" style="flex:1">
        <div class="cols" style="flex:1;grid-template-columns:minmax(0,1.6fr) minmax(0,1fr)">
          <section class="panel"><div class="p-head"><div><h2>Headlines</h2><p>Market-moving news as it breaks</p></div></div><div class="p-body" data-r="feed"></div></section>
          <section class="panel"><div class="p-head"><div><h2>Earnings</h2><p>Scheduled reports</p></div></div><div class="p-body" data-r="cal"></div></section>
        </div></div>`;
      const r = { ...refs(ctx.body), ...refs(ctx.mid) };
      const render = () => {
        r.feed.innerHTML = NZ.newsCards(S.news, true);
        NZ.text(r.n, `${S.news.length} stories today`);
      };
      const renderCal = () => {
        r.cal.innerHTML = S.cal.length ? S.cal.map((c) => `
          <div class="cal"><div class="av">${c.symbol.slice(0, 4)}</div><div class="row-txt"><b>${NZ.esc(c.name)}</b><span>Q${c.q} · est. EPS $${c.est.toFixed(2)}</span></div>
          <div class="cd"><b>${NZ.countdown(c.at - S.t)}</b><span>${c.symbol}</span></div></div>`).join('')
          : `<div class="empty">${icon('clock')}<b>No reports scheduled</b></div>`;
      };
      ctx.body.addEventListener('click', (e) => {
        const t = e.target.closest('[data-trade]');
        if (t) ctx.open('trader', { symbol: t.dataset.trade });
      });
      render();
      renderCal();
      const offs = [NZ.on('news', render), NZ.on('calendar', renderCal), NZ.on('quotes', renderCal)];
      return { destroy: () => offs.forEach((o) => o()) };
    },
  };

  // ── position size calculator ──────────────────────────────────
  NZ.apps.calc = {
    id: 'calc', glyph: 'calc', tone: 'amber', title: 'Position Size', sub: 'Risk-based sizing tool', w: 780, h: 600,
    create(ctx) {
      const tradables = S.syms.filter((m) => m.tradable);
      const first = S.by[S.focus] && S.by[S.focus].tradable ? S.by[S.focus] : tradables[0];
      const mt = NZ.metrics();
      const st = { side: 'buy', sym: first.s, equity: mt ? Math.floor(mt.equity) : 10000, risk: 1, entry: first.q.last, stop: null, target: null };
      ctx.body.innerHTML = `<div class="view" style="flex:1;overflow-y:auto">
        <div class="calc">
          <div class="field"><label>Symbol</label><select class="select" data-k="sym">${tradables.map((m) => `<option value="${m.s}" ${m.s === st.sym ? 'selected' : ''}>${m.s} · ${NZ.esc(m.n)}</option>`).join('')}</select></div>
          <div class="field"><label>Direction</label><div class="seg lg" data-r="side"><button data-s="buy" class="buy on">Long</button><button data-s="sell" class="sell">Short</button></div></div>
          <div class="field"><label>Account size</label><input class="input" data-k="equity"></div>
          <div class="field"><label>Risk per trade <b>% of account</b></label><input class="input" data-k="risk"></div>
          <div class="field"><label>Entry price <b data-r="last"></b></label><input class="input" data-k="entry"></div>
          <div class="field"><label>Stop loss</label><input class="input" data-k="stop"></div>
          <div class="field" style="grid-column:1/-1"><label>Target <b>optional</b></label><input class="input" data-k="target"></div>
          <div class="out" data-r="out"></div>
          <div style="grid-column:1/-1;display:flex;justify-content:space-between;align-items:center;gap:12px">
            <span class="muted" style="font-size:11px;font-weight:300;line-height:1.5" data-r="note"></span>
            <button class="btn-teal" data-r="send">${icon('arrowRight')}Send to ticket</button></div>
        </div></div>`;
      const r = refs(ctx.body);
      const seed = () => {
        const m = S.by[st.sym];
        st.entry = m.q.last;
        const up = st.side === 'buy';
        st.stop = NZ.roundTick(m.q.last * (up ? 0.98 : 1.02));
        st.target = NZ.roundTick(m.q.last * (up ? 1.04 : 0.96));
        fill();
      };
      const fill = () => {
        ctx.body.querySelectorAll('input[data-k]').forEach((i) => {
          const v = st[i.dataset.k];
          i.value = v == null ? '' : i.dataset.k === 'risk' || i.dataset.k === 'equity' ? v : NZ.px(v).replace(/,/g, '');
        });
        calc();
      };
      const calc = () => {
        const m = S.by[st.sym];
        NZ.text(r.last, 'last ' + NZ.px(m.q.last));
        r.side.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.s === st.side));
        const perUnit = st.entry && st.stop ? Math.abs(st.entry - st.stop) : 0;
        const riskCash = (st.equity || 0) * ((st.risk || 0) / 100);
        let qty = perUnit ? riskCash / perUnit : 0;
        const dec = m.type === 'crypto' ? Math.pow(10, S.cfg.cryptoDecimals || 4) : 1;
        qty = Math.floor(qty * dec) / dec;
        const value = qty * (st.entry || 0);
        const reward = st.target && st.entry ? Math.abs(st.target - st.entry) * qty : null;
        const wrong = st.stop && st.entry && (st.side === 'buy' ? st.stop >= st.entry : st.stop <= st.entry);
        st.qty = wrong ? 0 : qty;
        const box = (l, v, cls = '') => `<div class="big"><span>${l}</span><b class="${cls}">${v}</b></div>`;
        r.out.innerHTML = box(m.type === 'crypto' ? 'Units' : 'Shares', wrong ? '—' : NZ.qty(qty))
          + box('Position value', NZ.money(wrong ? 0 : value))
          + box('Cash at risk', NZ.money(wrong ? 0 : qty * perUnit), 'dn')
          + box('Reward at target', reward != null && !wrong ? NZ.money(reward) : '—', 'up')
          + box('Reward : risk', reward && perUnit && !wrong ? (reward / (qty * perUnit)).toFixed(2) + 'R' : '—')
          + box('Leverage used', st.equity ? (value / st.equity).toFixed(2) + '×' : '—');
        NZ.text(r.note, wrong ? 'Your stop is on the wrong side of the entry.' : `Risking ${st.risk}% means a stop-out costs ${NZ.money(riskCash)}. Sizing keeps every loss the same size, whatever the stock.`);
        r.send.disabled = !st.qty;
      };
      ctx.body.addEventListener('input', (e) => {
        const k = e.target.dataset.k;
        if (!k) return;
        if (k === 'sym') { st.sym = e.target.value; return seed(); }
        st[k] = num(e.target.value);
        calc();
      });
      ctx.body.addEventListener('click', (e) => {
        const s = e.target.closest('[data-s]');
        if (s) { st.side = s.dataset.s; NZ.sound.play('click'); return seed(); }
        if (e.target.closest('[data-r=send]') && st.qty) {
          ctx.open('trader', {
            symbol: st.sym,
            ticket: { side: st.side, type: 'limit', limit: st.entry, qty: st.qty, bracket: !!(st.stop || st.target), tp: st.target, sl: st.stop },
          });
          NZ.sound.play('place');
        }
      });
      seed();
      return {};
    },
  };
})();
