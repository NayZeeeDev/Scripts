/* ═══════════════════════════════════════════════════════════
   NZ Trader — the brokerage app
   ═══════════════════════════════════════════════════════════ */
(() => {
  const S = NZ.state;
  const icon = NZ.icon;
  const C = () => NZ.colors;

  const TF = [[5, '5s'], [15, '15s'], [60, '1m'], [300, '5m'], [900, '15m']];
  const TYPE = { market: 'MKT', limit: 'LMT', stop: 'STP', trail: 'TRL' };
  const LEVELS = 7;
  const NAV = [
    [null, [['terminal', 'Terminal', 'candles']]],
    ['Account', [['portfolio', 'Portfolio', 'briefcase'], ['orders', 'Orders', 'list'], ['funding', 'Funding', 'wallet']]],
    ['Market', [['markets', 'Markets', 'pulse'], ['news', 'News', 'news'], ['leaders', 'Leaderboard', 'trophy']]],
    ['System', [['settings', 'Settings', 'gear']]],
  ];

  const refs = (root) => {
    const r = {};
    root.querySelectorAll('[data-r]').forEach((el) => { r[el.dataset.r] = el; });
    return r;
  };
  const num = (v) => { const n = parseFloat(String(v ?? '').replace(/[,$\s]/g, '')); return isFinite(n) ? n : null; };
  const decimals = () => S.cfg.cryptoDecimals || 4;
  const roundQty = (sym, q) => {
    if (!(q > 0)) return 0;
    const m = NZ.isCrypto(sym) ? Math.pow(10, decimals()) : 1;
    return Math.floor(q * m + 1e-9) / m;
  };
  const sideTag = (qty) => (qty > 0 ? '<span class="tag live">Long</span>' : '<span class="tag hot">Short</span>');
  const pctOf = (a, b) => (b ? (a / b) * 100 : 0);

  function newsCards(list, withTrade) {
    if (!list.length) return `<div class="empty">${icon('news')}<b>The wire is quiet</b><span>Headlines appear here the moment they cross.</span></div>`;
    return list.map((n) => {
      const kind = { company: n.impact >= 0 ? ['chip', 'Bullish'] : ['chip red', 'Bearish'], earnings: n.impact >= 0 ? ['chip', 'Earnings beat'] : ['chip red', 'Earnings miss'], macro: n.impact >= 0 ? ['chip mono', 'Macro'] : ['chip mono', 'Macro'], halt: ['chip amber', 'Halt'] }[n.kind] || ['chip mono', 'News'];
      const cls = n.kind === 'halt' ? 'halt' : n.impact < 0 ? 'bear' : '';
      const m = n.symbol && S.by[n.symbol];
      return `<article class="inc ${cls}"><div class="inc-top"><span class="${kind[0]}">${kind[1]}</span>${n.scope ? `<span class="chip mono">${n.scope === 'crypto' ? 'Crypto' : 'All stocks'}</span>` : ''}<span class="ref">${n.symbol || 'MARKET'}</span></div>
        <h3>${NZ.esc(n.text)}</h3>
        <div class="meta"><span>${NZ.ago(n.time)}</span>${m ? `<span>Now <b class="${NZ.dir(NZ.change(m))}">${NZ.px(m.q.last)} (${NZ.pct(NZ.change(m))})</b></span>` : ''}${withTrade && m && m.tradable ? `<button data-trade="${m.s}">Trade ${m.s} →</button>` : ''}</div></article>`;
    }).join('');
  }
  NZ.newsCards = newsCards;

  function create(ctx) {
    const T = {
      view: S.profile ? 'terminal' : 'onboard',
      focus: S.focus,
      tf: 60,
      wlTab: S.watch.length ? 'watch' : 'stock',
      wlQuery: '',
      blot: 'positions',
      history: null,
      v: null,
      offs: [],
      tk: { side: 'buy', type: 'market', qty: null, limit: null, stop: null, trail: null, tif: 'day', bracket: false, tp: null, sl: null },
    };

    // ── chrome: title bar slots, sidebar, status bar ─────────────
    ctx.mid.innerHTML = `
      <span class="dot" data-r="sdot"></span>
      <p><b data-r="ses"></b> · <span data-r="next"></span></p>
      <div class="acct-switch" data-r="acct">
        <button data-acct="practice">${icon('target')}Practice</button>
        <button data-acct="live" class="live">${icon('bolt')}Live</button>
      </div>
      <span class="ver amber" data-r="mode">PAPER</span>`;
    ctx.end.innerHTML = `
      <div class="bar-sum">
        <div><span>Equity</span><b data-r="eq">—</b></div>
        <div><span>Day P&L</span><b data-r="day">—</b></div>
        <div><span>Buying power</span><b data-r="bp">—</b></div>
      </div>`;
    const bar = { ...refs(ctx.mid), ...refs(ctx.end) };

    const root = NZ.h(`<div class="trader ${S.settings.compact || S.device === 'tablet' ? 'compact' : ''}"><nav class="side"></nav><section class="view"></section></div>`);
    const side = root.firstElementChild;
    const viewEl = root.lastElementChild;
    ctx.body.appendChild(root);

    const status = NZ.h(`
      <div class="statusbar">
        <span><i class="key">B</i>Buy</span><span><i class="key">S</i>Sell</span>
        <span><i class="key">F</i>Flatten</span><span><i class="key">C</i>Cancel orders</span>
        <span><i class="key">↑↓</i>Symbol</span><span><i class="key">1-5</i>Timeframe</span>
        <span><i class="key">ESC</i>Close</span>
        <span class="sp"><span class="dot" style="margin-right:8px"></span>Feed <b style="margin-left:4px">live</b></span>
        <span>Server <b data-r="time" style="margin-left:4px"></b></span>
      </div>`);
    ctx.body.appendChild(status);
    const sb = refs(status);

    let sideRefs = {};
    function renderSide() {
      const name = S.profile ? S.profile.name : S.player.name;
      side.innerHTML = `
        <div class="who"><div class="av">${NZ.esc(NZ.initials(name))}</div>
          <div class="who-txt"><b>${NZ.esc(name || 'Trader')}</b><span>${S.active === 'live' ? 'Live account' : 'Practice account'}</span></div></div>
        <div class="shift"><span data-r="clock"></span><b data-r="ses"><span class="dot"></span><em style="font-style:normal"></em></b></div>
        ${NAV.map(([grp, items]) => `
          ${grp ? `<div class="grp">${grp}</div>` : ''}
          ${items.map(([id, label, ic]) => `<button class="nav ${T.view === id ? 'on' : ''}" data-nav="${id}" title="${label}">${icon(ic)}<span class="nav-label">${label}</span><span class="tally" data-badge-for="${id}" style="display:none"></span></button>`).join('')}
        `).join('')}
        <button class="nav collapse" data-a="compact" title="Toggle sidebar">${icon('sidebar')}<span class="nav-label">Collapse</span></button>`;
      sideRefs = refs(side);
      root.classList.toggle('solo', !S.profile);
      status.style.display = S.profile ? '' : 'none';
      updateChrome();
    }

    side.addEventListener('click', (e) => {
      const n = e.target.closest('[data-nav]');
      if (n) return go(n.dataset.nav);
      if (e.target.closest('[data-a=compact]')) {
        root.classList.toggle('compact');
        if (S.device !== 'tablet') { S.settings.compact = root.classList.contains('compact'); NZ.saveSettings(); }
      }
    });

    ctx.mid.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-acct]');
      if (!b || !S.profile || b.dataset.acct === S.active) return;
      if (b.dataset.acct === 'live' && !S.accounts.live) return NZ.toast({ kind: 'err', title: 'Live trading unavailable', text: 'This server only offers practice trading.' });
      S.active = b.dataset.acct;
      NZ.sound.play('click');
      NZ.api('active', { account: S.active });
      T.history = null;
      NZ.emit('account');
      renderSide();
      go(T.view, true);
    });

    function badge(id, n) {
      const el = side.querySelector(`[data-badge-for="${id}"]`);
      const nav = side.querySelector(`[data-nav="${id}"]`);
      if (!el || !nav) return;
      el.style.display = n ? '' : 'none';
      el.textContent = n;
      if (n) nav.dataset.badge = n; else delete nav.dataset.badge;
    }

    function updateChrome() {
      const acc = NZ.account();
      const mt = NZ.metrics(acc);
      NZ.text(bar.ses, NZ.sessionLabel());
      NZ.text(bar.next, NZ.sessionNext());
      bar.sdot.className = 'dot ' + NZ.sessionDot();
      bar.acct.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.acct === S.active));
      bar.acct.style.display = S.profile ? '' : 'none';
      bar.mode.style.display = S.profile ? '' : 'none';
      NZ.text(bar.mode, S.active === 'live' ? 'LIVE' : 'PAPER');
      bar.mode.className = 'ver' + (S.active === 'live' ? '' : ' amber');
      ctx.end.firstElementChild.style.visibility = mt ? '' : 'hidden';
      if (mt) {
        NZ.text(bar.eq, NZ.money(mt.equity));
        NZ.text(bar.day, NZ.signed(mt.day));
        bar.day.className = NZ.dir(mt.day);
        NZ.text(bar.bp, NZ.money(mt.bp));
      }
      NZ.text(sb.time, NZ.clock(S.t, true));
      const sr = sideRefs;
      if (sr.clock) {
        NZ.text(sr.clock, NZ.clock(S.t, true));
        sr.ses.className = { open: '', pre: 'amber', post: 'amber', closed: 'red' }[S.session.code] || '';
        sr.ses.querySelector('.dot').className = 'dot ' + NZ.sessionDot();
        NZ.text(sr.ses.querySelector('em'), { open: 'Open', pre: 'Pre', post: 'After', closed: 'Closed' }[S.session.code] || '');
      }
      if (acc) {
        badge('portfolio', acc.positions.length);
        badge('orders', acc.orders.length);
      }
      badge('news', S.unreadNews);
    }

    // ── navigation ───────────────────────────────────────────────
    function go(view, force) {
      if (!S.profile) view = 'onboard';
      if (view === T.view && T.v && !force) return;
      if (T.v && T.v.destroy) T.v.destroy();
      T.view = view;
      if (view === 'news') S.unreadNews = 0;
      side.querySelectorAll('[data-nav]').forEach((n) => n.classList.toggle('on', n.dataset.nav === view));
      viewEl.innerHTML = '';
      viewEl.className = 'view';
      T.v = (VIEWS[view] || VIEWS.terminal)(viewEl) || {};
      updateChrome();
    }

    function focusSymbol(sym, toTerminal) {
      if (!S.by[sym]) return;
      T.focus = S.focus = sym;
      if (toTerminal && T.view !== 'terminal') return go('terminal');
      if (T.v && T.v.focus) T.v.focus();
    }

    // ═════════════════════════════════════════════════════════════
    // VIEWS
    // ═════════════════════════════════════════════════════════════
    const VIEWS = {};

    // ── onboarding ───────────────────────────────────────────────
    VIEWS.onboard = (el) => {
      const cfg = S.cfg;
      el.innerHTML = `
        <div class="onboard"><div class="card">
          <div class="top"><div class="mark lg"></div>
            <div><h1>Open your ${NZ.esc(cfg.ui.company)} account</h1>
            <p style="margin-top:8px">Trade ${S.syms.filter((m) => m.tradable).length} stocks and crypto pairs with real market tools. Start on a practice account, then fund a live account when you're ready.</p></div>
          </div>
          <div class="mid">
            <div class="perks">
              <div class="perk"><b>${NZ.money0(cfg.practice.startingCash)} practice</b><span>Paper money, resets any time</span></div>
              <div class="perk"><b>${cfg.live.enabled ? 'Live account' : 'Practice only'}</b><span>${cfg.live.enabled ? 'Deposit from your bank' : 'Live trading is disabled'}</span></div>
              <div class="perk"><b>${cfg.leverage}× buying power</b><span>Margin, shorting, brackets</span></div>
              <div class="perk"><b>Pro tools</b><span>Charts, Level 2, time & sales</span></div>
            </div>
            <div class="field"><label>Display name <b>shown on the leaderboard</b></label><input class="input" data-r="name" maxlength="24" value="${NZ.esc(S.player.name || '')}"></div>
            <div class="check" data-r="agree"><i>${icon('check')}</i><span>I understand that trading involves risk and live losses come out of my own money.</span></div>
          </div>
          <div class="foot"><span class="muted" style="font-size:11px" data-r="err"></span><button class="btn-teal" data-r="go" disabled>Open account ${icon('arrowRight')}</button></div>
        </div></div>`;
      const r = refs(el);
      r.agree.onclick = () => { r.agree.classList.toggle('on'); r.go.disabled = !r.agree.classList.contains('on'); NZ.sound.play('click'); };
      r.go.onclick = async () => {
        r.go.disabled = true;
        const res = await NZ.api('createProfile', { name: r.name.value });
        if (!res.ok) { r.go.disabled = false; NZ.text(r.err, res.err); NZ.sound.play('reject'); return; }
        NZ.loadProfile(res.data);
        T.focus = S.focus;
        T.wlTab = S.watch.length ? 'watch' : 'stock';
        NZ.sound.play('unlock');
        NZ.toast({ title: 'Account opened', text: `Welcome, ${S.profile.name}. Your practice account is funded.` });
        renderSide();
        go('terminal', true);
      };
    };

    // ── terminal ─────────────────────────────────────────────────
    VIEWS.terminal = (el) => {
      el.innerHTML = `
        <div class="term">
          <section class="panel wl">
            <div class="p-head">
              <div class="wl-search">${icon('search')}<input class="input" data-r="q" placeholder="Search symbol or company"></div>
              <div class="seg" data-r="wltabs"><button data-t="watch">Watch</button><button data-t="stock">Stocks</button><button data-t="crypto">Crypto</button><button data-t="index">Index</button></div>
            </div>
            <div class="wl-list" data-r="wl"></div>
          </section>
          <div class="center">
            <section class="panel symhead" data-r="head"></section>
            <section class="panel chart-panel">
              <div class="p-head">
                <div style="display:flex;gap:8px">
                  <div class="seg" data-r="tf">${TF.map(([s, l]) => `<button data-tf="${s}">${l}</button>`).join('')}</div>
                  <div class="seg" data-r="ctype"><button data-c="candle">Candles</button><button data-c="line">Line</button></div>
                </div>
                <div class="ind" data-r="ind">
                  <button data-i="ema9"><i style="background:rgba(255,255,255,.72)"></i>EMA 9</button>
                  <button data-i="ema21"><i style="background:#e5a50a"></i>EMA 21</button>
                  <button data-i="vwap"><i style="background:#0fd4c4"></i>VWAP</button>
                  <button data-i="vol"><i style="background:#63696d"></i>Volume</button>
                </div>
              </div>
              <div class="chart-wrap" data-r="chart">
                <div class="chart-legend" data-r="legend"></div>
                <div class="chart-halt hidden" data-r="halt"><div>${icon('pause')}<span></span></div></div>
                <div class="chart-loading" data-r="loading"><div class="sk" style="width:60%;height:60%;opacity:.4"></div></div>
              </div>
            </section>
            <section class="panel blotter">
              <div class="p-head"><div class="tabs" data-r="btabs"></div><div class="act" data-r="bact"></div></div>
              <div class="p-body" data-r="blot"></div>
            </section>
          </div>
          <div class="right">
            <section class="panel ticket" data-r="ticket"></section>
            <section class="panel l2t">
              <div><h3>Level 2 <span data-r="bookex"></span></h3><div class="colhead"><span>Price</span><span>Size</span></div><div class="book" data-r="book"></div></div>
              <div><h3>Time & Sales <span>${icon('clock', 'style="width:12px;height:12px"')}</span></h3><div class="colhead"><span>Time</span><span>Price</span><span>Size</span></div><div class="tape" data-r="tape"></div></div>
            </section>
          </div>
        </div>`;
      const r = refs(el);
      const tk = T.tk;
      let rows = {};
      let chart, reqId = 0, book = { a: [], b: [] }, bookRows = { a: [], b: [] }, spreadEl;

      // ── watchlist ──
      function wlList() {
        const q = T.wlQuery.trim().toLowerCase();
        if (q) return S.syms.filter((m) => m.s.toLowerCase().includes(q) || m.n.toLowerCase().includes(q));
        if (T.wlTab === 'watch') return S.watch.map((s) => S.by[s]).filter(Boolean);
        return S.syms.filter((m) => m.type === T.wlTab);
      }
      function renderWatch() {
        r.wltabs.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.t === T.wlTab && !T.wlQuery));
        const list = wlList();
        rows = {};
        if (!list.length) {
          r.wl.innerHTML = `<div class="empty">${icon('star')}<b>Your watchlist is empty</b><span>Hover a symbol in Stocks or Crypto and tap the star to pin it here.</span></div>`;
          return;
        }
        r.wl.innerHTML = list.map((m) => `
          <div class="wl-row ${m.s === T.focus ? 'on' : ''}" data-sym="${m.s}">
            <div class="sym">${m.s}${NZ.halted(m) ? '<i>HALT</i>' : ''}</div><div class="px"></div>
            <div class="nm">${NZ.esc(m.n)}</div><div class="ch"></div>
            <button class="icon-btn star ${S.watch.includes(m.s) ? 'on' : ''}" data-star="${m.s}">${icon('star')}</button>
          </div>`).join('');
        r.wl.querySelectorAll('.wl-row').forEach((row) => {
          rows[row.dataset.sym] = { row, px: row.querySelector('.px'), ch: row.querySelector('.ch') };
        });
        updateWatch(true);
      }
      function updateWatch(all) {
        for (const sym in rows) {
          const m = S.by[sym], x = rows[sym];
          NZ.text(x.px, NZ.px(m.q.last));
          const ch = NZ.change(m);
          NZ.text(x.ch, NZ.pct(ch));
          x.ch.className = 'ch ' + NZ.dir(ch);
          if (!all && m.q.dir) {
            const c = m.q.dir > 0 ? 'flash-up' : 'flash-dn';
            x.px.classList.add(c);
            setTimeout(() => x.px.classList.remove(c), 260);
          }
        }
      }
      r.q.addEventListener('input', () => { T.wlQuery = r.q.value; renderWatch(); });
      r.wltabs.addEventListener('click', (e) => {
        const b = e.target.closest('[data-t]');
        if (!b) return;
        T.wlTab = b.dataset.t; T.wlQuery = ''; r.q.value = '';
        renderWatch();
      });
      r.wl.addEventListener('click', (e) => {
        const star = e.target.closest('[data-star]');
        if (star) {
          e.stopPropagation();
          toggleWatch(star.dataset.star);
          return;
        }
        const row = e.target.closest('[data-sym]');
        if (row) { NZ.sound.play('click'); focusSymbol(row.dataset.sym); }
      });

      // ── symbol header ──
      let hd = {};
      function renderHead() {
        const m = S.by[T.focus];
        r.head.innerHTML = `
          <div class="av">${m.s.slice(0, 4)}</div>
          <div class="id"><b>${m.s} <span class="chip mono">${m.ex}</span><span data-r="st"></span></b><span>${NZ.esc(m.n)} · ${m.sector[0].toUpperCase() + m.sector.slice(1)}</span></div>
          <div class="last"><b data-r="last"></b><span data-r="chg"></span></div>
          <div class="cells">
            <div class="cell"><span>Bid</span><b data-r="bid" class="dn"></b></div>
            <div class="cell"><span>Ask</span><b data-r="ask" class="up"></b></div>
            <div class="cell"><span>Spread</span><b data-r="spr"></b></div>
            <div class="cell"><span>Day range</span><b data-r="rng"></b><div class="range-bar"><i data-r="rdot"></i></div></div>
            <div class="cell"><span>Volume</span><b data-r="vol"></b></div>
            <div class="cell"><span>Prev close</span><b data-r="prev"></b></div>
          </div>`;
        hd = refs(r.head);
        updateHead();
      }
      function updateHead() {
        const m = S.by[T.focus], q = m.q;
        NZ.text(hd.last, NZ.px(q.last));
        const chg = q.last - m.prev;
        NZ.text(hd.chg, `${chg >= 0 ? '+' : ''}${NZ.px(chg)} (${NZ.pct(NZ.change(m))})`);
        hd.chg.className = NZ.dir(chg);
        NZ.text(hd.bid, NZ.px(q.bid));
        NZ.text(hd.ask, NZ.px(q.ask));
        NZ.text(hd.spr, m.tradable ? NZ.px(q.ask - q.bid) : '—');
        NZ.text(hd.rng, `${NZ.px(q.lo)} – ${NZ.px(q.hi)}`);
        hd.rdot.style.left = (q.hi > q.lo ? ((q.last - q.lo) / (q.hi - q.lo)) * 100 : 50) + '%';
        NZ.text(hd.vol, m.type === 'index' ? '—' : NZ.compact(q.vol));
        NZ.text(hd.prev, NZ.px(m.prev));
        let st;
        if (NZ.halted(m)) st = ['chip amber', 'HALTED'];
        else if (m.type === 'crypto') st = ['chip', '24/7'];
        else st = { open: ['chip', 'OPEN'], pre: ['chip amber', 'PRE-MKT'], post: ['chip amber', 'AFTER-HRS'], closed: ['chip red', 'CLOSED'] }[S.session.code];
        hd.st.className = st[0];
        NZ.text(hd.st, st[1]);
      }

      // ── chart ──
      function legend(d, prev) {
        if (!d) return;
        const ch = prev ? ((d.c - prev.c) / prev.c) * 100 : 0;
        r.legend.innerHTML = `<b>${T.focus} · ${TF.find((x) => x[0] === T.tf)[1]}</b>
          <span class="o"><span><em>O</em> ${NZ.px(d.o)}</span><span><em>H</em> ${NZ.px(d.h)}</span><span><em>L</em> ${NZ.px(d.l)}</span><span><em>C</em> ${NZ.px(d.c)}</span></span>
          <span class="${NZ.dir(ch)}">${NZ.pct(ch)}</span><span><em style="font-style:normal">Vol</em> ${NZ.compact(d.v)}</span>`;
      }
      chart = new NZ.Chart(r.chart, {
        onLegend: legend,
        onContext: (price, e) => {
          const m = S.by[T.focus];
          if (!m.tradable) return;
          const p = NZ.px(price);
          const above = price > m.q.last;
          NZ.menu([
            { label: `Buy limit @ ${p}`, color: C().teal, run: () => preset('buy', 'limit', price) },
            { label: `Sell limit @ ${p}`, color: C().red, run: () => preset('sell', 'limit', price) },
            { label: `${above ? 'Buy' : 'Sell'} stop @ ${p}`, color: C().amber, run: () => preset(above ? 'buy' : 'sell', 'stop', price) },
            null,
            { label: `Alert when ${above ? 'above' : 'below'} ${p}`, color: '#fff', run: () => addAlert(T.focus, above ? 'above' : 'below', price) },
          ], e.clientX, e.clientY);
        },
      });
      Object.assign(chart.ind, S.settings.chartInd || {});
      function chartToolbar() {
        r.tf.querySelectorAll('button').forEach((b) => b.classList.toggle('on', +b.dataset.tf === T.tf));
        r.ctype.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.c === chart.type));
        r.ind.querySelectorAll('button').forEach((b) => b.classList.toggle('on', !!chart.ind[b.dataset.i]));
      }
      async function loadCandles() {
        const id = ++reqId;
        r.loading.classList.remove('hidden');
        const res = await NZ.api('candles', { symbol: T.focus, tf: T.tf });
        if (id !== reqId) return;
        r.loading.classList.add('hidden');
        if (res.ok) chart.setData(res.data, T.tf);
        chartLines();
      }
      r.tf.addEventListener('click', (e) => { const b = e.target.closest('[data-tf]'); if (b) setTf(+b.dataset.tf); });
      r.ctype.addEventListener('click', (e) => { const b = e.target.closest('[data-c]'); if (b) { chart.type = b.dataset.c; chartToolbar(); chart.invalidate(); } });
      r.ind.addEventListener('click', (e) => {
        const b = e.target.closest('[data-i]');
        if (!b) return;
        chart.ind[b.dataset.i] = !chart.ind[b.dataset.i];
        chartToolbar();
        chart.invalidate();
      });
      function setTf(tf) { if (tf === T.tf) return; T.tf = tf; chartToolbar(); loadCandles(); }

      function chartLines() {
        const L = [];
        const m = S.by[T.focus];
        const acc = NZ.account();
        const col = C();
        if (acc) {
          const pos = NZ.position(T.focus, acc);
          if (pos) {
            const pnl = pos.qty * (m.q.last - pos.avg);
            L.push({ price: pos.avg, color: pos.qty > 0 ? col.teal : col.red, dash: [], ink: pos.qty > 0 ? '#00201d' : '#fff',
              label: `${pos.qty > 0 ? 'LONG' : 'SHORT'} ${NZ.qty(Math.abs(pos.qty))} @ ${NZ.px(pos.avg)}   ${NZ.signed(pnl)}` });
          }
          for (const o of acc.orders) {
            if (o.sym !== T.focus) continue;
            const price = o.type === 'limit' ? o.limit : o.stop;
            const c = o.type === 'limit' ? col.amber : o.side === 'buy' ? col.teal : col.red;
            L.push({ price, color: c, label: `${o.side.toUpperCase()} ${TYPE[o.type]} ${NZ.qty(o.qty)}${o.reduce ? (o.type === 'limit' ? ' · TP' : ' · SL') : ''}` });
          }
        }
        for (const a of S.alerts) {
          if (a.sym === T.focus) L.push({ price: a.price, color: '#ffffff', ink: '#000', dash: [2, 3], label: `ALERT ${a.cond === 'above' ? '≥' : '≤'} ${NZ.px(a.price)}` });
        }
        if (tk.bracket && m.tradable) {
          if (tk.tp) L.push({ price: tk.tp, color: col.teal, dash: [2, 4], label: 'TP preview' });
          if (tk.sl) L.push({ price: tk.sl, color: col.red, dash: [2, 4], ink: '#fff', label: 'SL preview' });
        }
        if (tk.type === 'limit' && tk.limit) L.push({ price: tk.limit, color: '#9ea5aa', dash: [2, 4], label: `${tk.side.toUpperCase()} LMT preview` });
        chart.setLines(L);
      }

      function updateHalt() {
        const m = S.by[T.focus];
        const h = NZ.halted(m);
        r.halt.classList.toggle('hidden', !h);
        if (h) NZ.text(r.halt.querySelector('span'), `Trading halted · resumes in ${NZ.countdown(m.halt - S.t)}`);
      }

      // ── blotter ──
      function renderBlotTabs() {
        const acc = NZ.account();
        const np = acc ? acc.positions.length : 0, no = acc ? acc.orders.length : 0;
        r.btabs.innerHTML = [
          ['positions', 'Positions', np], ['orders', 'Working', no], ['fills', 'Fills'], ['alerts', 'Alerts', S.alerts.length],
        ].map(([id, l, n]) => `<button data-b="${id}" class="${T.blot === id ? 'on' : ''}">${l}${n !== undefined ? ` <span class="tally ${n ? 'teal' : ''}">${n}</span>` : ''}</button>`).join('');
        r.bact.innerHTML = T.blot === 'positions' ? `<button class="btn-ghost red" data-act="flattenAll" ${np ? '' : 'disabled'}>${icon('flatten')}Flatten all</button>`
          : T.blot === 'orders' ? `<button class="btn-ghost red" data-act="cancelAll" ${no ? '' : 'disabled'}>${icon('x')}Cancel all</button>`
          : T.blot === 'fills' ? `<button class="btn-ghost" data-act="refreshFills">${icon('refresh')}Refresh</button>` : '';
      }
      let posCells = {};
      function renderBlot() {
        renderBlotTabs();
        const acc = NZ.account();
        posCells = {};
        if (!acc) return;
        if (T.blot === 'positions') {
          if (!acc.positions.length) { r.blot.innerHTML = `<div class="empty">${icon('briefcase')}<b>No open positions</b><span>Use the ticket or press B / S to trade ${T.focus} at market.</span></div>`; return; }
          r.blot.innerHTML = `<table class="tbl"><thead><tr><th>Symbol</th><th>Side</th><th class="r">Qty</th><th class="r">Avg</th><th class="r">Last</th><th class="r">Market value</th><th class="r">Unrealized</th><th class="r">%</th><th></th></tr></thead><tbody>
            ${acc.positions.map((p) => `<tr class="click" data-sym="${p.sym}"><td><b>${p.sym}</b></td><td>${sideTag(p.qty)}</td><td class="r">${NZ.qty(Math.abs(p.qty))}</td><td class="r">${NZ.px(p.avg)}</td>
              <td class="r" data-c="last"></td><td class="r" data-c="mv"></td><td class="r" data-c="pnl"></td><td class="r" data-c="pct"></td>
              <td><div class="act"><button class="btn-ghost red" data-close="${p.sym}">Close</button></div></td></tr>`).join('')}
          </tbody></table>`;
          r.blot.querySelectorAll('tr[data-sym]').forEach((tr) => {
            const c = {};
            tr.querySelectorAll('[data-c]').forEach((td) => { c[td.dataset.c] = td; });
            posCells[tr.dataset.sym] = c;
          });
          updateBlot();
        } else if (T.blot === 'orders') {
          if (!acc.orders.length) { r.blot.innerHTML = `<div class="empty">${icon('list')}<b>No working orders</b><span>Limit, stop and trailing orders wait here until they trigger.</span></div>`; return; }
          r.blot.innerHTML = `<table class="tbl"><thead><tr><th>Time</th><th>Symbol</th><th>Side</th><th>Type</th><th class="r">Qty</th><th class="r">Price</th><th>TIF</th><th>Link</th><th></th></tr></thead><tbody>
            ${acc.orders.map((o) => `<tr><td>${NZ.clock(o.created, true)}</td><td><b>${o.sym}</b></td><td class="${o.side === 'buy' ? 'up' : 'dn'}">${o.side.toUpperCase()}</td><td>${TYPE[o.type]}</td>
              <td class="r">${NZ.qty(o.qty)}</td><td class="r"><b>${NZ.px(o.type === 'limit' ? o.limit : o.stop)}</b>${o.type === 'trail' ? ` <span class="muted">(${NZ.px(o.trail)})</span>` : ''}</td>
              <td>${o.tif.toUpperCase()}</td><td>${o.reduce ? `<span class="chip mono">${o.type === 'limit' ? 'TP' : 'SL'} · OCO</span>` : o.tp || o.sl ? '<span class="chip">BRACKET</span>' : '—'}</td>
              <td><div class="act"><button class="icon-btn red" data-cancel="${o.id}" title="Cancel">${icon('x')}</button></div></td></tr>`).join('')}
          </tbody></table>`;
        } else if (T.blot === 'fills') {
          const fills = T.history ? T.history.fills : null;
          if (!fills) { r.blot.innerHTML = `<div class="empty"><div class="sk" style="width:60%;height:10px"></div></div>`; loadHistory().then(() => T.blot === 'fills' && renderBlot()); return; }
          if (!fills.length) { r.blot.innerHTML = `<div class="empty">${icon('check')}<b>No fills yet</b><span>Executions show up here with price, fees and realized P&L.</span></div>`; return; }
          r.blot.innerHTML = fillsTable(fills.slice(0, 60));
        } else {
          r.blot.innerHTML = alertsForm() + (S.alerts.length ? `<table class="tbl"><thead><tr><th>Symbol</th><th>Condition</th><th class="r">Price</th><th class="r">Last</th><th></th></tr></thead><tbody>
            ${S.alerts.map((a) => `<tr><td><b>${a.sym}</b></td><td>${a.cond === 'above' ? 'Rises above' : 'Falls below'}</td><td class="r"><b>${NZ.px(a.price)}</b></td><td class="r">${NZ.px((S.by[a.sym] || {}).q?.last)}</td>
              <td><div class="act"><button class="icon-btn red" data-delalert="${a.id}">${icon('x')}</button></div></td></tr>`).join('')}</tbody></table>`
            : `<div class="empty">${icon('bell')}<b>No price alerts</b><span>Right-click the chart or use the form above. Alerts ping you even with the device closed.</span></div>`);
          const af = refs(r.blot);
          af.alertGo.onclick = () => addAlert(T.focus, af.alertCond.value, num(af.alertPrice.value));
        }
      }
      function alertsForm() {
        const m = S.by[T.focus];
        return `<div style="display:flex;gap:8px;align-items:flex-end;padding:10px;border-bottom:1px solid var(--line-hair)">
          <div class="field" style="width:110px"><label>Symbol</label><input class="input" value="${m.s}" disabled></div>
          <div class="field" style="width:150px"><label>Condition</label><select class="select" data-r="alertCond"><option value="above">Rises above</option><option value="below">Falls below</option></select></div>
          <div class="field" style="width:140px"><label>Price</label><input class="input" data-r="alertPrice" placeholder="${NZ.px(m.q.last)}"></div>
          <button class="btn-teal" data-r="alertGo">${icon('bell')}Add alert</button></div>`;
      }
      function updateBlot() {
        if (T.blot !== 'positions') return;
        const acc = NZ.account();
        if (!acc) return;
        for (const p of acc.positions) {
          const c = posCells[p.sym];
          const m = S.by[p.sym];
          if (!c || !m) continue;
          const pnl = p.qty * (m.q.last - p.avg);
          NZ.text(c.last, NZ.px(m.q.last));
          NZ.text(c.mv, NZ.money(Math.abs(p.qty) * m.q.last));
          NZ.text(c.pnl, NZ.signed(pnl));
          c.pnl.className = 'r ' + NZ.dir(pnl);
          const pc = pctOf(pnl, Math.abs(p.qty) * p.avg);
          NZ.text(c.pct, NZ.pct(pc));
          c.pct.className = 'r ' + NZ.dir(pc);
        }
      }
      r.btabs.addEventListener('click', (e) => { const b = e.target.closest('[data-b]'); if (b) { T.blot = b.dataset.b; renderBlot(); } });
      r.bact.addEventListener('click', (e) => {
        const b = e.target.closest('[data-act]');
        if (!b) return;
        if (b.dataset.act === 'flattenAll') flatten(null);
        if (b.dataset.act === 'cancelAll') cancelAll(null);
        if (b.dataset.act === 'refreshFills') { T.history = null; renderBlot(); }
      });
      r.blot.addEventListener('click', (e) => {
        const close = e.target.closest('[data-close]');
        if (close) { e.stopPropagation(); return flatten(close.dataset.close); }
        const cancel = e.target.closest('[data-cancel]');
        if (cancel) return cancelOrder(+cancel.dataset.cancel);
        const del = e.target.closest('[data-delalert]');
        if (del) return delAlert(+del.dataset.delalert);
        const row = e.target.closest('tr[data-sym]');
        if (row) focusSymbol(row.dataset.sym);
      });

      // ── order ticket ──
      function defaultQty(m) {
        return m.type === 'crypto' ? roundQty(m.s, Math.max(1000 / m.q.last, 1 / Math.pow(10, decimals()))) : 10;
      }
      function refPrice() {
        const m = S.by[T.focus], q = m.q;
        if (tk.type === 'limit') return tk.limit;
        if (tk.type === 'stop') return tk.stop;
        if (tk.type === 'trail') return tk.trail ? (tk.side === 'buy' ? q.ask + tk.trail : q.bid - tk.trail) : null;
        return tk.side === 'buy' ? q.ask : q.bid;
      }
      function stepFor(p) { return NZ.tick(p) * (p >= 100 ? 5 : 1); }
      let tr = {};
      function renderTicket() {
        const m = S.by[T.focus];
        if (!m.tradable) {
          r.ticket.innerHTML = `<div class="p-head"><div><h2>Order ticket</h2><p>${m.s} · index</p></div></div>
            <div class="p-body"><div class="empty">${icon('info')}<b>Indices aren't tradable</b><span>${NZ.esc(m.n)} tracks its constituents. Pick a stock or crypto pair to trade.</span></div></div>`;
          tr = {};
          return;
        }
        if (tk.qty == null || tk.sym !== m.s) {
          tk.sym = m.s; tk.qty = defaultQty(m);
          tk.limit = tk.stop = tk.tp = tk.sl = null;
          tk.trail = NZ.roundTick(m.q.last * 0.01);
          if (tk.type !== 'market') seedPrice();
        }
        const chips = m.type === 'crypto' ? [['$500', 500], ['$1K', 1000], ['$5K', 5000], ['$10K', 10000]] : [['10', 10], ['50', 50], ['100', 100], ['500', 500]];
        r.ticket.innerHTML = `
          <div class="p-head"><div><h2>Order ticket</h2><p>${m.s} · ${NZ.esc(m.n)}</p></div><span class="ver ${S.active === 'live' ? '' : 'amber'}">${S.active === 'live' ? 'LIVE' : 'PAPER'}</span></div>
          <div class="p-body">
            <div class="seg lg" data-r="side"><button data-s="buy" class="buy">Buy</button><button data-s="sell" class="sell">Sell</button></div>
            <div class="seg type" data-r="type"><button data-t="market">Market</button><button data-t="limit">Limit</button><button data-t="stop">Stop</button><button data-t="trail">Trail</button></div>
            <div class="field"><label>Quantity <b data-r="qnote"></b></label>
              <div class="stepper"><button data-qs="-1">${icon('minus')}</button><input data-r="qty" data-k="qty"><button data-qs="1">${icon('plus')}</button></div>
              <div class="qchips">${chips.map(([l, v]) => `<button data-chip="${v}">${l}</button>`).join('')}<button data-chip="max">Max</button></div>
            </div>
            <div class="row2" data-r="prices"></div>
            <div class="pos-line" data-r="pos"></div>
            <div class="bracket">
              <div class="sw-line"><span>Bracket · take profit & stop loss</span><span class="sw ${tk.bracket ? 'on' : ''}" data-r="bsw"><i></i></span></div>
              <div class="row2 ${tk.bracket ? '' : 'hidden'}" data-r="bf">
                <div class="field"><label>Take profit</label><div class="stepper"><button data-ps="tp:-1">${icon('minus')}</button><input data-k="tp"><button data-ps="tp:1">${icon('plus')}</button></div></div>
                <div class="field"><label>Stop loss</label><div class="stepper"><button data-ps="sl:-1">${icon('minus')}</button><input data-k="sl"><button data-ps="sl:1">${icon('plus')}</button></div></div>
              </div>
              <div class="rr ${tk.bracket ? '' : 'hidden'}" data-r="rr"></div>
            </div>
            <div class="summary" data-r="sum"></div>
            <div class="warnline" data-r="warn"></div>
            <button class="btn-teal submit" data-r="submit"></button>
          </div>`;
        tr = refs(r.ticket);
        renderPrices();
        syncTicket();
      }
      function seedPrice() {
        const m = S.by[T.focus], q = m.q;
        if (tk.type === 'limit') tk.limit = tk.side === 'buy' ? q.bid : q.ask;
        if (tk.type === 'stop') tk.stop = NZ.roundTick(tk.side === 'buy' ? q.ask * 1.005 : q.bid * 0.995);
      }
      function renderPrices() {
        const k = tk.type;
        const tif = `<div class="field"><label>Time in force</label><select class="select" data-k="tif"><option value="day">Day</option><option value="gtc">GTC</option></select></div>`;
        if (k === 'market') {
          tr.prices.innerHTML = `<div class="field"><label>Est. fill <b data-r="estlbl"></b></label><input class="input" data-r="est" disabled></div>
            <div class="field"><label>Time in force</label><input class="input" value="Immediate" disabled></div>`;
        } else {
          const key = k === 'limit' ? 'limit' : k === 'stop' ? 'stop' : 'trail';
          const label = k === 'limit' ? 'Limit price' : k === 'stop' ? 'Stop trigger' : 'Trail amount ($)';
          tr.prices.innerHTML = `<div class="field"><label>${label}</label><div class="stepper"><button data-ps="${key}:-1">${icon('minus')}</button><input data-k="${key}"><button data-ps="${key}:1">${icon('plus')}</button></div></div>${tif}`;
        }
        Object.assign(tr, refs(tr.prices));
        r.ticket.querySelectorAll('[data-k]').forEach((inp) => {
          const v = tk[inp.dataset.k];
          if (inp.tagName === 'SELECT') inp.value = v;
          else if (v != null) inp.value = inp.dataset.k === 'qty' ? v : NZ.px(v).replace(/,/g, '');
        });
      }
      function validate() {
        const m = S.by[T.focus];
        const acc = NZ.account();
        const mt = NZ.metrics(acc);
        const qty = roundQty(m.s, tk.qty || 0);
        const px = refPrice();
        const out = { qty, px, warn: null, fee: 0, grow: 0 };
        out.warn = NZ.tradableNow(m, tk.type);
        if (!acc) out.warn = 'No account';
        else if (qty <= 0) out.warn = 'Enter a quantity';
        else if (!px || px <= 0) out.warn = tk.type === 'trail' ? 'Enter a trail amount' : 'Enter a price';
        if (out.warn && !acc) return out;
        if (px > 0 && qty > 0 && acc) {
          const pos = NZ.position(m.s, acc);
          const cur = pos ? pos.qty : 0;
          const signed = tk.side === 'buy' ? qty : -qty;
          out.fee = NZ.fee(m.s, qty, px);
          out.grow = (Math.abs(cur + signed) - Math.abs(cur)) * px;
          out.short = cur + signed < 0 && cur >= 0;
          if (!out.warn && cur + signed < 0 && (!S.cfg.allowShort)) out.warn = 'Short selling is disabled';
          if (!out.warn && out.grow > 0 && out.grow > (mt.equity - out.fee) * (S.cfg.leverage || 1) - mt.exposure) out.warn = 'Insufficient buying power';
          if (!out.warn && tk.bracket) {
            const up = tk.side === 'buy';
            if (tk.tp && (up ? tk.tp <= px : tk.tp >= px)) out.warn = 'Take profit is on the wrong side';
            if (tk.sl && (up ? tk.sl >= px : tk.sl <= px)) out.warn = 'Stop loss is on the wrong side';
          }
          out.bpAfter = mt.bp - Math.max(0, out.grow) - out.fee;
        }
        return out;
      }
      function syncTicket() {
        if (!tr.submit) return;
        const m = S.by[T.focus], q = m.q;
        tr.side.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.s === tk.side));
        tr.type.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.t === tk.type));
        if (tr.est) {
          tr.est.value = NZ.px(tk.side === 'buy' ? q.ask : q.bid);
          NZ.text(tr.estlbl, tk.side === 'buy' ? 'at the ask' : 'at the bid');
        }
        const v = validate();
        const notional = v.qty * (v.px || 0);
        NZ.text(tr.qnote, notional ? '≈ ' + NZ.money(notional) : '');
        const acc = NZ.account();
        const pos = NZ.position(m.s, acc);
        if (pos) {
          const pnl = pos.qty * (q.last - pos.avg);
          tr.pos.innerHTML = `<span>Position <b>${pos.qty > 0 ? 'Long' : 'Short'} ${NZ.qty(Math.abs(pos.qty))}</b> @ ${NZ.px(pos.avg)}</span><b class="${NZ.dir(pnl)}">${NZ.signed(pnl)}</b><button class="btn-ghost" data-act="closeqty">Close qty</button>`;
        } else tr.pos.innerHTML = `<span>No position in ${m.s}</span><span>${NZ.money(NZ.metrics(acc)?.bp || 0)} BP</span>`;
        if (tk.bracket && v.px && tr.rr) {
          const risk = tk.sl ? Math.abs(v.px - tk.sl) * v.qty : null;
          const reward = tk.tp ? Math.abs(tk.tp - v.px) * v.qty : null;
          tr.rr.innerHTML = `<span>Risk <b class="dn">${risk != null ? NZ.money(risk) : '—'}</b></span><span>Reward <b class="up">${reward != null ? NZ.money(reward) : '—'}</b></span><span>R:R <b>${risk && reward ? '1 : ' + (reward / risk).toFixed(2) : '—'}</b></span>`;
        }
        tr.sum.innerHTML = `
          <div><span>Est. ${tk.type === 'market' ? 'fill' : 'trigger'} price</span><b>${v.px ? NZ.px(v.px) : '—'}</b></div>
          <div><span>Est. value</span><b>${NZ.money(notional)}</b></div>
          <div><span>Commission</span><b>${NZ.money(v.fee)}</b></div>
          <div><span>Buying power after</span><b>${v.bpAfter != null ? NZ.money(v.bpAfter) : '—'}</b></div>`;
        NZ.text(tr.warn, v.warn || '');
        const verb = tk.side === 'buy' ? (v.short === false && pos && pos.qty < 0 ? 'Buy to cover' : 'Buy') : (v.short ? 'Sell short' : 'Sell');
        tr.submit.innerHTML = `${verb} ${v.qty ? NZ.qty(v.qty) : ''} ${m.s} · ${TYPE[tk.type]}`;
        tr.submit.className = (tk.side === 'buy' ? 'btn-teal' : 'btn-sell') + ' submit';
        tr.submit.disabled = !!v.warn;
      }
      r.ticket.addEventListener('click', (e) => {
        const t = e.target;
        const sideB = t.closest('[data-s]');
        if (sideB) { tk.side = sideB.dataset.s; if (tk.type !== 'market') { seedPrice(); renderPrices(); } NZ.sound.play('click'); syncTicket(); chartLines(); return; }
        const typeB = t.closest('[data-t]');
        if (typeB) { tk.type = typeB.dataset.t; seedPrice(); renderPrices(); NZ.sound.play('click'); syncTicket(); chartLines(); return; }
        const qs = t.closest('[data-qs]');
        if (qs) {
          const m = S.by[T.focus];
          const step = m.type === 'crypto' ? defaultQty(m) / 10 || 0.0001 : 1;
          tk.qty = roundQty(m.s, Math.max(0, (tk.qty || 0) + step * +qs.dataset.qs));
          tr.qty.value = tk.qty;
          return syncTicket();
        }
        const chip = t.closest('[data-chip]');
        if (chip) {
          const m = S.by[T.focus];
          const px = refPrice() || m.q.last;
          if (chip.dataset.chip === 'max') {
            const mt = NZ.metrics();
            tk.qty = roundQty(m.s, ((mt ? mt.bp : 0) * 0.98) / px);
          } else tk.qty = m.type === 'crypto' ? roundQty(m.s, +chip.dataset.chip / px) : +chip.dataset.chip;
          tr.qty.value = tk.qty;
          NZ.sound.play('click');
          return syncTicket();
        }
        const ps = t.closest('[data-ps]');
        if (ps) {
          const [key, dir] = ps.dataset.ps.split(':');
          const base = tk[key] || refPrice() || S.by[T.focus].q.last;
          tk[key] = Math.max(NZ.tick(base), NZ.roundTick(base + stepFor(base) * +dir));
          const inp = r.ticket.querySelector(`[data-k="${key}"]`);
          if (inp) inp.value = NZ.px(tk[key]).replace(/,/g, '');
          syncTicket(); chartLines();
          return;
        }
        if (t.closest('[data-r=bsw]')) {
          tk.bracket = !tk.bracket;
          if (tk.bracket) {
            const px = refPrice() || S.by[T.focus].q.last;
            const up = tk.side === 'buy';
            tk.tp = NZ.roundTick(px * (up ? 1.02 : 0.98));
            tk.sl = NZ.roundTick(px * (up ? 0.99 : 1.01));
          }
          NZ.sound.play('click');
          return renderTicket(), chartLines();
        }
        if (t.closest('[data-act=closeqty]')) {
          const pos = NZ.position(T.focus);
          if (!pos) return;
          tk.side = pos.qty > 0 ? 'sell' : 'buy';
          tk.qty = Math.abs(pos.qty);
          tk.bracket = false;
          return renderTicket();
        }
        if (t.closest('[data-r=submit]')) submit();
      });
      r.ticket.addEventListener('input', (e) => {
        const k = e.target.dataset.k;
        if (!k) return;
        tk[k] = k === 'tif' ? e.target.value : num(e.target.value);
        syncTicket();
        if (k !== 'qty') chartLines();
      });
      r.ticket.addEventListener('change', (e) => { if (e.target.dataset.k === 'tif') tk.tif = e.target.value; });

      function preset(sideV, type, price) {
        tk.side = sideV; tk.type = type;
        if (type === 'limit') tk.limit = price; else tk.stop = price;
        renderTicket();
        chartLines();
        NZ.sound.play('click');
      }

      async function submit(quickSide) {
        const m = S.by[T.focus];
        const order = quickSide
          ? { side: quickSide, type: 'market', qty: roundQty(m.s, tk.qty || defaultQty(m)) }
          : { side: tk.side, type: tk.type, qty: roundQty(m.s, tk.qty || 0), limit: tk.type === 'limit' ? tk.limit : null,
              stop: tk.type === 'stop' ? tk.stop : null, trail: tk.type === 'trail' ? tk.trail : null, tif: tk.tif,
              tp: tk.bracket ? tk.tp : null, sl: tk.bracket ? tk.sl : null };
        if (!quickSide && validate().warn) return;
        if (S.settings.confirm) {
          const ok = await NZ.confirm({
            title: `${order.side === 'buy' ? 'Buy' : 'Sell'} ${NZ.qty(order.qty)} ${m.s}?`,
            text: `${TYPE[order.type]} order on your ${S.active} account${order.limit ? ' at ' + NZ.px(order.limit) : order.stop ? ' triggering at ' + NZ.px(order.stop) : ''}.`,
            ok: 'Send order', okClass: order.side === 'buy' ? 'btn-teal' : 'btn-sell', icon: 'info', teal: true,
          });
          if (!ok) return;
        }
        if (tr.submit) tr.submit.disabled = true;
        const res = await NZ.api('order', { account: S.active, symbol: m.s, ...order });
        if (tr.submit) syncTicket();
        if (!res.ok) {
          NZ.sound.play('reject');
          NZ.toast({ kind: 'err', title: 'Order rejected', text: res.err });
        }
      }

      // ── level 2 & tape ──
      function renderBook() {
        const m = S.by[T.focus];
        NZ.text(r.bookex, m.ex);
        if (!m.tradable) { r.book.innerHTML = `<div class="empty" style="margin:10px">${icon('layers')}<b>No order book</b></div>`; bookRows = { a: [], b: [] }; return; }
        const lvl = (s) => `<div class="lvl ${s}"><b></b><span></span></div>`;
        r.book.innerHTML = `<div class="side-a">${Array(LEVELS).fill(lvl('a')).join('')}</div><div class="spread"><span>Spread</span><b></b><span></span></div><div class="side-b">${Array(LEVELS).fill(lvl('b')).join('')}</div>`;
        bookRows = { a: [...r.book.querySelectorAll('.lvl.a')].reverse(), b: [...r.book.querySelectorAll('.lvl.b')] };
        spreadEl = r.book.querySelector('.spread');
        book = { a: [], b: [] };
        updateBook();
      }
      function updateBook() {
        const m = S.by[T.focus];
        if (!bookRows.a.length) return;
        const q = m.q;
        const tick = NZ.tick(q.last);
        const step = Math.max(tick, NZ.roundTick(q.last * 0.00025));
        const base = Math.max(m.vpt * 6, m.type === 'crypto' ? 0.5 : 100);
        let max = 0;
        for (const s of ['a', 'b']) {
          for (let i = 0; i < LEVELS; i++) {
            const target = base * (0.4 + Math.random() * 1.2) * (1 + i * 0.22);
            book[s][i] = book[s][i] ? book[s][i] * 0.6 + target * 0.4 : target;
            if (book[s][i] > max) max = book[s][i];
          }
        }
        for (const s of ['a', 'b']) {
          bookRows[s].forEach((row, i) => {
            const price = s === 'a' ? q.ask + step * i : q.bid - step * i;
            const size = book[s][i];
            row.dataset.price = price;
            NZ.text(row.firstChild, NZ.px(price));
            NZ.text(row.lastChild, m.type === 'crypto' ? size.toFixed(size < 10 ? 3 : 1) : NZ.compact(Math.round(size / 10) * 10));
            row.style.setProperty('--w', ((size / max) * 100).toFixed(1) + '%');
          });
        }
        NZ.text(spreadEl.children[1], NZ.px(q.ask - q.bid));
        NZ.text(spreadEl.children[2], ((q.ask - q.bid) / q.last * 10000).toFixed(1) + ' bps');
      }
      r.book.addEventListener('click', (e) => {
        const row = e.target.closest('.lvl');
        if (!row) return;
        preset(row.classList.contains('a') ? 'buy' : 'sell', 'limit', +row.dataset.price);
      });

      function tapePrint(price, size, side, you) {
        const m = S.by[T.focus];
        const base = Math.max(m.vpt, 1e-9);
        const el = NZ.h(`<div class="prt ${side} ${size > base * 1.6 ? 'big' : ''} ${you ? 'you' : ''}"><span>${you ? 'YOU' : NZ.clock(S.t, true)}</span><b>${NZ.px(price)}</b><em>${m.type === 'crypto' ? NZ.qty(Math.round(size * 1e4) / 1e4) : NZ.compact(size)}</em></div>`);
        r.tape.prepend(el);
        while (r.tape.childElementCount > 40) r.tape.lastElementChild.remove();
      }
      function updateTape() {
        const m = S.by[T.focus], q = m.q;
        if (!m.tradable || !q.dvol) return;
        let left = q.dvol;
        const n = left > m.vpt * 2 ? 3 : Math.random() < 0.55 ? 2 : 1;
        for (let i = 0; i < n && left > 0; i++) {
          let size = i === n - 1 ? left : left * (0.2 + Math.random() * 0.5);
          size = m.type === 'crypto' ? size : Math.max(1, Math.round(size));
          left -= size;
          const side = q.dir > 0 ? 'a' : q.dir < 0 ? 'b' : Math.random() < 0.5 ? 'a' : 'b';
          tapePrint(side === 'a' ? q.ask : q.bid, size, side);
        }
      }
      function seedTape() {
        r.tape.innerHTML = '';
        const m = S.by[T.focus];
        if (!m.tradable) { r.tape.innerHTML = `<div class="empty" style="margin:10px">${icon('clock')}<b>No prints</b></div>`; return; }
        for (let i = 0; i < 14; i++) {
          const side = Math.random() < 0.5 ? 'a' : 'b';
          tapePrint(side === 'a' ? m.q.ask : m.q.bid, m.type === 'crypto' ? m.vpt * Math.random() : Math.max(1, Math.round(m.vpt * Math.random() * 1.5)), side);
        }
      }

      // ── wiring ──
      function onFocus() {
        renderWatch();
        renderHead();
        renderTicket();
        renderBook();
        seedTape();
        renderBlot();
        updateHalt();
        loadCandles();
      }
      chartToolbar();
      onFocus();

      return {
        focus: onFocus,
        quotes() {
          const m = S.by[T.focus];
          updateWatch();
          updateHead();
          chart.update(S.t, m.q.last, m.q.dvol);
          chartLines();
          syncTicket();
          updateBook();
          updateTape();
          updateBlot();
          updateHalt();
        },
        account() { renderBlot(); syncTicket(); chartLines(); renderTicketHeader(); },
        alerts() { if (T.blot === 'alerts') renderBlot(); else renderBlotTabs(); chartLines(); },
        watch() { if (T.wlTab === 'watch') renderWatch(); else r.wl.querySelectorAll('[data-star]').forEach((b) => b.classList.toggle('on', S.watch.includes(b.dataset.star))); },
        halt() { renderWatch(); updateHead(); updateHalt(); },
        fill(f) {
          if (f.sym === T.focus) tapePrint(f.price, f.qty, f.side === 'buy' ? 'a' : 'b', true);
          if (T.blot === 'fills') renderBlot();
        },
        key(e) {
          const k = e.key.toLowerCase();
          if (k === 'b') submit('buy');
          else if (k === 's') submit('sell');
          else if (k === 'f') flatten(T.focus);
          else if (k === 'c') cancelAll(T.focus);
          else if (k === 'arrowup' || k === 'arrowdown') {
            const list = wlList();
            const i = list.findIndex((m) => m.s === T.focus);
            const next = list[(i + (k === 'arrowup' ? -1 : 1) + list.length) % list.length];
            if (next) { focusSymbol(next.s); e.preventDefault(); }
          } else if (k >= '1' && k <= '5') setTf(TF[+k - 1][0]);
          else return false;
          return true;
        },
        resize() { chart.resize(); },
        destroy() {
          S.settings.chartInd = { ...chart.ind };
          chart.destroy();
        },
      };
      function renderTicketHeader() {
        const v = r.ticket.querySelector('.p-head .ver');
        if (v) { v.className = 'ver ' + (S.active === 'live' ? '' : 'amber'); NZ.text(v, S.active === 'live' ? 'LIVE' : 'PAPER'); }
      }
    };

    // ── portfolio ────────────────────────────────────────────────
    VIEWS.portfolio = (el) => {
      el.classList.add('view-pad');
      el.innerHTML = `
        <div class="head"><div><h1>Portfolio</h1><p>Your ${S.active} account — positions, exposure and performance.</p></div>
          <div style="display:flex;gap:8px"><button class="btn-red" data-a="flat">${icon('flatten')}Flatten all</button></div></div>
        <div class="stats">
          ${stat('eq', 'Equity', 'wallet')}${stat('bp', 'Buying power', 'bolt')}${stat('cash', 'Cash', 'coin', 'mono')}${stat('upnl', 'Open P&L', 'pulse')}${stat('net', 'Realized (net)', 'trophy')}
        </div>
        <div class="cols" style="flex:1">
          <section class="panel"><div class="p-head"><div><h2>Open positions</h2><p data-r="psub"></p></div></div><div class="p-body" data-r="pos"></div></section>
          <div style="display:flex;flex-direction:column;gap:13px;min-height:0">
            <section class="panel"><div class="p-head"><div><h2>Allocation</h2><p>Share of gross exposure</p></div><span class="tag off" data-r="lev"></span></div><div class="alloc" data-r="alloc"></div></section>
            <section class="panel" style="flex:1"><div class="p-head"><div><h2>Performance</h2><p>Cumulative realized P&L after fees</p></div><span data-r="trades" class="tag off"></span></div><div class="p-body"><div class="curve" data-r="curve"></div></div></section>
          </div>
        </div>`;
      const r = refs(el);
      let cells = {};
      function render() {
        const acc = NZ.account();
        if (!acc) return;
        NZ.text(r.psub, `${acc.positions.length} open · ${acc.orders.length} working orders`);
        if (!acc.positions.length) {
          r.pos.innerHTML = `<div class="empty">${icon('briefcase')}<b>Nothing open right now</b><span>Positions you take in the terminal appear here with live P&L.</span></div>`;
        } else {
          r.pos.innerHTML = acc.positions.map((p) => `
            <div class="row" data-sym="${p.sym}" style="cursor:pointer"><div class="av">${p.sym.slice(0, 4)}</div>
              <div class="row-txt"><b>${p.sym} ${sideTag(p.qty)}</b><span>${NZ.qty(Math.abs(p.qty))} @ ${NZ.px(p.avg)} · <em data-c="last" style="font-style:normal"></em></span></div>
              <div style="text-align:right"><b data-c="pnl" style="display:block;font-size:13px;font-weight:600"></b><span data-c="mv" style="font-size:10.5px;color:var(--ink-3)"></span></div>
              <button class="btn-ghost red" data-close="${p.sym}">Close</button></div>`).join('');
        }
        cells = {};
        r.pos.querySelectorAll('[data-sym]').forEach((row) => {
          const c = {};
          row.querySelectorAll('[data-c]').forEach((x) => { c[x.dataset.c] = x; });
          cells[row.dataset.sym] = c;
        });
        NZ.text(r.trades, `${acc.trades} trades`);
        NZ.text(r.lev, `${S.cfg.leverage}× margin`);
        update();
        curve();
      }
      function update() {
        const acc = NZ.account();
        const mt = NZ.metrics(acc);
        if (!mt) return;
        setStat(el, 'eq', NZ.money(mt.equity), mt.dayPct);
        setStat(el, 'bp', NZ.money(mt.bp));
        setStat(el, 'cash', NZ.money(acc.cash));
        setStat(el, 'upnl', NZ.signed(mt.upnl), null, mt.upnl);
        setStat(el, 'net', NZ.signed(mt.net), null, mt.net);
        let gross = 0;
        for (const p of acc.positions) {
          const m = S.by[p.sym];
          const c = cells[p.sym];
          const v = Math.abs(p.qty) * m.q.last;
          gross += v;
          if (!c) continue;
          const pnl = p.qty * (m.q.last - p.avg);
          NZ.text(c.pnl, NZ.signed(pnl));
          c.pnl.className = NZ.dir(pnl);
          NZ.text(c.mv, NZ.money(v));
          NZ.text(c.last, 'last ' + NZ.px(m.q.last));
        }
        r.alloc.innerHTML = acc.positions.length ? acc.positions.map((p) => {
          const v = Math.abs(p.qty) * S.by[p.sym].q.last;
          const pc = gross ? (v / gross) * 100 : 0;
          return `<div class="alloc-row"><b>${p.sym}</b><div class="alloc-bar"><i class="${p.qty < 0 ? 'short' : ''}" style="width:${pc.toFixed(1)}%"></i></div><span>${pc.toFixed(1)}%</span></div>`;
        }).join('') : `<span class="muted" style="font-size:11.5px;font-weight:300">No exposure — ${NZ.money(mt.bp)} buying power available.</span>`;
      }
      async function curve() {
        if (!T.history) await loadHistory();
        if (!T.history) return;
        const fills = T.history.fills.slice().reverse();
        let sum = 0;
        const vals = [0, ...fills.map((f) => (sum += f.realized - f.fee))];
        r.curve.innerHTML = vals.length > 2 ? NZ.sparkline(vals, 600, 200).replace('class="spark"', 'style="width:100%;height:100%"')
          : `<div class="empty">${icon('pulse')}<b>No closed trades yet</b><span>Your realized P&L curve builds as you close positions.</span></div>`;
      }
      el.addEventListener('click', (e) => {
        const c = e.target.closest('[data-close]');
        if (c) { e.stopPropagation(); return flatten(c.dataset.close); }
        if (e.target.closest('[data-a=flat]')) return flatten(null);
        const row = e.target.closest('[data-sym]');
        if (row) focusSymbol(row.dataset.sym, true);
      });
      render();
      return { quotes: update, account: render };
    };

    // ── orders ───────────────────────────────────────────────────
    VIEWS.orders = (el) => {
      let filter = 'working';
      el.classList.add('view-pad');
      el.innerHTML = `
        <div class="head"><div><h1>Orders</h1><p>Working orders and your execution history on the ${S.active} account.</p></div>
          <div style="display:flex;gap:8px"><div class="seg" data-r="f"><button data-f="working">Working</button><button data-f="filled">Filled</button><button data-f="cancelled">Cancelled</button><button data-f="all">All</button></div>
          <button class="btn-ghost" data-a="refresh">${icon('refresh')}Refresh</button><button class="btn-ghost red" data-a="cancelAll">${icon('x')}Cancel all</button></div></div>
        <section class="panel" style="flex:1"><div class="p-body" style="padding:0" data-r="tbl"></div></section>`;
      const r = refs(el);
      function render() {
        r.f.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.f === filter));
        const acc = NZ.account();
        let list = [];
        if (filter === 'working' || filter === 'all') list = list.concat(acc.orders.map((o) => ({ ...o, status: 'working', time: o.created })));
        if (filter !== 'working') {
          if (!T.history) { r.tbl.innerHTML = `<div class="empty"><div class="sk" style="width:50%;height:10px"></div></div>`; loadHistory().then(render); return; }
          list = list.concat(T.history.orders.filter((o) => filter === 'all' || o.status === filter || (filter === 'cancelled' && o.status !== 'filled')));
        }
        if (!list.length) { r.tbl.innerHTML = `<div class="empty">${icon('list')}<b>Nothing here</b><span>No ${filter === 'all' ? '' : filter} orders on this account yet.</span></div>`; return; }
        const stTag = (s) => ({ working: 'tag warn', filled: 'tag live', cancelled: 'tag off', expired: 'tag off', rejected: 'tag hot' }[s] || 'tag off');
        r.tbl.innerHTML = `<table class="tbl"><thead><tr><th>#</th><th>Time</th><th>Symbol</th><th>Side</th><th>Type</th><th class="r">Qty</th><th class="r">Price</th><th class="r">Fill</th><th>Status</th><th>Note</th><th></th></tr></thead><tbody>
          ${list.map((o) => `<tr><td class="muted">${o.id}</td><td>${NZ.shortDate(o.time)} ${NZ.clock(o.time, true)}</td><td><b>${o.sym}</b></td>
            <td class="${o.side === 'buy' ? 'up' : 'dn'}">${o.side.toUpperCase()}</td><td>${TYPE[o.type] || o.type}</td><td class="r">${NZ.qty(o.qty)}</td>
            <td class="r">${o.type === 'market' ? 'MKT' : NZ.px(o.type === 'limit' ? o.limit : o.stop)}</td><td class="r"><b>${o.price ? NZ.px(o.price) : '—'}</b></td>
            <td><span class="${stTag(o.status)}">${o.status}</span></td><td class="muted">${NZ.esc(o.reason || (o.reduce ? 'Bracket exit' : ''))}</td>
            <td>${o.status === 'working' ? `<div class="act"><button class="icon-btn red" data-cancel="${o.id}">${icon('x')}</button></div>` : ''}</td></tr>`).join('')}
        </tbody></table>`;
      }
      el.addEventListener('click', (e) => {
        const f = e.target.closest('[data-f]');
        if (f) { filter = f.dataset.f; return render(); }
        if (e.target.closest('[data-a=refresh]')) { T.history = null; return render(); }
        if (e.target.closest('[data-a=cancelAll]')) return cancelAll(null);
        const c = e.target.closest('[data-cancel]');
        if (c) cancelOrder(+c.dataset.cancel);
      });
      render();
      return { account() { T.history = null; render(); } };
    };

    // ── markets ──────────────────────────────────────────────────
    VIEWS.markets = (el) => {
      let tab = 'all', sort = 'chg', dir = -1;
      el.classList.add('view-pad');
      el.innerHTML = `
        <div class="head"><div><h1>Markets</h1><p>Every listed symbol with live quotes. Click a row to open it in the terminal.</p></div>
          <div class="seg" data-r="tab"><button data-t="all">All</button><button data-t="stock">Stocks</button><button data-t="crypto">Crypto</button><button data-t="index">Indices</button></div></div>
        <div class="movers" data-r="movers"></div>
        <div class="cols" style="grid-template-columns:minmax(0,1fr) 300px;flex:1">
          <section class="panel"><div class="p-body" style="padding:0" data-r="tbl"></div></section>
          <section class="panel"><div class="p-head"><div><h2>Sectors</h2><p>Average move today</p></div></div><div class="heat" data-r="heat" style="grid-template-columns:1fr 1fr"></div></section>
        </div>`;
      const r = refs(el);
      let cells = {};
      const COLS = [['s', 'Symbol'], ['sector', 'Sector'], ['last', 'Last', 'r'], ['chg', 'Change', 'r'], ['hi', 'High', 'r'], ['lo', 'Low', 'r'], ['vol', 'Volume', 'r'], ['spark', '1h'], ['star', '']];
      const val = (m, k) => (k === 'chg' ? NZ.change(m) : k === 'last' ? m.q.last : k === 'vol' ? m.q.vol * m.q.last : k === 'hi' ? m.q.hi : k === 'lo' ? m.q.lo : m[k]);
      function render() {
        r.tab.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.t === tab));
        const list = S.syms.filter((m) => tab === 'all' || m.type === tab).sort((a, b) => {
          const x = val(a, sort), y = val(b, sort);
          return (typeof x === 'string' ? x.localeCompare(y) : x - y) * dir;
        });
        r.tbl.innerHTML = `<table class="tbl"><thead><tr>${COLS.map(([k, l, c]) => `<th class="${c || ''} ${k !== 'spark' && k !== 'star' ? 'sort' : ''} ${sort === k ? 'on' : ''}" data-sort="${k}">${l}${sort === k ? (dir > 0 ? ' ↑' : ' ↓') : ''}</th>`).join('')}</tr></thead><tbody>
          ${list.map((m) => `<tr class="click" data-sym="${m.s}"><td><b>${m.s}</b> <span class="muted">${NZ.esc(m.n)}</span></td><td style="text-transform:capitalize">${m.sector}</td>
            <td class="r" data-c="last"></td><td class="r" data-c="chg"></td><td class="r" data-c="hi"></td><td class="r" data-c="lo"></td><td class="r" data-c="vol"></td>
            <td data-c="spark"></td><td>${m.tradable ? `<button class="icon-btn ${S.watch.includes(m.s) ? 'up' : ''}" data-star="${m.s}">${icon('star')}</button>` : ''}</td></tr>`).join('')}
        </tbody></table>`;
        cells = {};
        r.tbl.querySelectorAll('tr[data-sym]').forEach((tr) => {
          const c = {};
          tr.querySelectorAll('[data-c]').forEach((td) => { c[td.dataset.c] = td; });
          cells[tr.dataset.sym] = c;
        });
        update(true);
      }
      let tick = 0;
      function update(full) {
        for (const sym in cells) {
          const m = S.by[sym], c = cells[sym];
          NZ.text(c.last, NZ.px(m.q.last));
          const ch = NZ.change(m);
          NZ.text(c.chg, NZ.pct(ch));
          c.chg.className = 'r ' + NZ.dir(ch);
          NZ.text(c.hi, NZ.px(m.q.hi));
          NZ.text(c.lo, NZ.px(m.q.lo));
          NZ.text(c.vol, m.type === 'index' ? '—' : NZ.compact(m.q.vol));
          if (full || tick % 10 === 0) c.spark.innerHTML = NZ.sparkline(m.spark.concat([m.q.last]));
        }
        tick++;
        const trad = S.syms.filter((m) => m.type !== 'index');
        const byChg = trad.slice().sort((a, b) => NZ.change(b) - NZ.change(a));
        const active = trad.slice().sort((a, b) => b.q.vol * b.q.last - a.q.vol * a.q.last)[0];
        const idx = S.syms.find((m) => m.type === 'index') || byChg[0];
        const card = (label, m, ic, cls, extra) => `<div class="stat" data-sym="${m.s}" style="cursor:pointer"><div class="tile ${cls}">${icon(ic)}</div><div class="stat-txt"><span>${label}</span><b>${m.s} <span style="font-size:13px" class="${NZ.dir(NZ.change(m))}">${NZ.pct(NZ.change(m))}</span></b></div><div class="delta muted" style="color:var(--ink-3)">${extra || NZ.px(m.q.last)}</div></div>`;
        r.movers.innerHTML = card(idx.n, idx, 'globe', 'mono') + card('Top gainer', byChg[0], 'arrowUp', '') + card('Top loser', byChg[byChg.length - 1], 'alert', 'red') + card('Most active', active, 'bolt', 'amber', '$' + NZ.compact(active.q.vol * active.q.last));
        const sectors = {};
        trad.forEach((m) => { (sectors[m.sector] = sectors[m.sector] || []).push(NZ.change(m)); });
        r.heat.innerHTML = Object.entries(sectors).map(([s, arr]) => {
          const avg = arr.reduce((a, b) => a + b, 0) / arr.length;
          const a = Math.min(0.32, Math.abs(avg) / 8 + 0.05);
          const bg = avg >= 0 ? `rgba(8,175,162,${a})` : `rgba(229,72,77,${a})`;
          return `<div style="background:${bg}"><b>${s}</b><span class="${NZ.dir(avg)}">${NZ.pct(avg)}</span></div>`;
        }).join('');
      }
      el.addEventListener('click', (e) => {
        const t = e.target.closest('[data-t]');
        if (t) { tab = t.dataset.t; return render(); }
        const s = e.target.closest('[data-sort]');
        if (s && s.dataset.sort !== 'spark' && s.dataset.sort !== 'star') {
          if (sort === s.dataset.sort) dir = -dir; else { sort = s.dataset.sort; dir = sort === 's' || sort === 'sector' ? 1 : -1; }
          return render();
        }
        const st = e.target.closest('[data-star]');
        if (st) { e.stopPropagation(); toggleWatch(st.dataset.star); st.classList.toggle('up', S.watch.includes(st.dataset.star)); return; }
        const row = e.target.closest('[data-sym]');
        if (row) focusSymbol(row.dataset.sym, true);
      });
      render();
      return { quotes: () => update(false), halt: render };
    };

    // ── news ─────────────────────────────────────────────────────
    VIEWS.news = (el) => {
      el.classList.add('view-pad');
      el.innerHTML = `
        <div class="head"><div><h1>News & calendar</h1><p>Headlines move prices. Earnings hit at the scheduled time — position before, or trade the reaction.</p></div>
          <div class="seg" data-r="f"><button data-f="all">All</button><button data-f="company">Company</button><button data-f="earnings">Earnings</button><button data-f="macro">Macro</button><button data-f="halt">Halts</button></div></div>
        <div class="cols" style="flex:1;grid-template-columns:minmax(0,1.5fr) minmax(0,1fr)">
          <section class="panel"><div class="p-head"><div><h2>Live wire</h2><p>Weazel Business · Bawsaq Newswire</p></div><span class="tag live">Live</span></div><div class="p-body" data-r="feed"></div></section>
          <div style="display:flex;flex-direction:column;gap:13px;min-height:0">
            <section class="panel"><div class="p-head"><div><h2>Earnings calendar</h2><p>Upcoming reports</p></div></div><div class="p-body" data-r="cal" style="flex:none;max-height:340px"></div></section>
            <section class="panel" style="flex:1"><div class="p-head"><div><h2>Session</h2><p>Trading hours</p></div></div><div class="p-body" data-r="ses"></div></section>
          </div>
        </div>`;
      const r = refs(el);
      let filter = 'all';
      function render() {
        r.f.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.f === filter));
        r.feed.innerHTML = newsCards(S.news.filter((n) => filter === 'all' || n.kind === filter), true);
        renderCal();
        const H = S.cfg.hours || {};
        const fmtH = (h) => `${Math.floor(h)}:${String(Math.round((h % 1) * 60)).padStart(2, '0')}`;
        r.ses.innerHTML = `
          <div class="row"><div class="tile ${NZ.sessionDot() || ''}">${icon('clock')}</div><div class="row-txt"><b>${NZ.sessionLabel()}</b><span>${NZ.sessionNext()}</span></div></div>
          ${H.enabled ? `<table class="tbl"><tbody>
            <tr><td>Pre-market</td><td class="r"><b>${fmtH(H.pre)} – ${fmtH(H.open)}</b></td></tr>
            <tr><td>Regular session</td><td class="r"><b>${fmtH(H.open)} – ${fmtH(H.close)}</b></td></tr>
            <tr><td>After hours</td><td class="r"><b>${fmtH(H.close)} – ${fmtH(H.post)}</b></td></tr>
            <tr><td>Crypto</td><td class="r"><b>24/7</b></td></tr></tbody></table>`
          : `<p class="muted" style="font-size:11.5px;font-weight:300;line-height:1.6;padding:4px">Stocks and crypto trade around the clock on this server. Volatility pauses still halt a stock for a minute after a sharp move.</p>`}`;
      }
      function renderCal() {
        r.cal.innerHTML = S.cal.length ? S.cal.map((c) => `
          <div class="cal"><div class="av">${c.symbol.slice(0, 4)}</div><div class="row-txt"><b>${NZ.esc(c.name)} Q${c.q}</b><span>Est. EPS $${c.est.toFixed(2)} · ${c.symbol}</span></div>
            <div class="cd"><b>${NZ.countdown(c.at - S.t)}</b><span>until report</span></div></div>`).join('')
          : `<div class="empty">${icon('clock')}<b>No reports scheduled</b><span>New earnings dates are announced throughout the day.</span></div>`;
      }
      el.addEventListener('click', (e) => {
        const f = e.target.closest('[data-f]');
        if (f) { filter = f.dataset.f; return render(); }
        const t = e.target.closest('[data-trade]');
        if (t) focusSymbol(t.dataset.trade, true);
      });
      render();
      return { news: render, calendar: renderCal, quotes: renderCal };
    };

    // ── funding ──────────────────────────────────────────────────
    VIEWS.funding = (el) => {
      el.classList.add('view-pad');
      const live = S.active === 'live';
      const cfg = S.cfg;
      if (!live) {
        el.innerHTML = `
          <div class="head"><div><h1>Practice account</h1><p>Paper money with real market rules. Nothing here touches your bank.</p></div></div>
          <div class="stats s4">${stat('eq', 'Equity', 'wallet')}${stat('start', 'Starting balance', 'coin', 'mono')}${stat('net', 'Realized (net)', 'trophy')}${stat('trades', 'Trades', 'list', 'mono')}</div>
          <div class="cols">
            <section class="panel"><div class="p-head"><div><h2>Reset practice account</h2><p>Back to ${NZ.money0(cfg.practice.startingCash)}, positions and orders cleared</p></div></div>
              <div class="form-card"><p class="muted" style="font-size:12px;font-weight:300;line-height:1.6">Blew up the account or want a clean slate before trying a new strategy? Resets are free, with a ${cfg.practice.resetCooldown}-minute cooldown.</p>
              <div><button class="btn-red" data-a="reset">${icon('refresh')}Reset account</button> <span class="muted" data-r="cool" style="font-size:11px;margin-left:8px"></span></div></div></section>
            <section class="panel"><div class="p-head"><div><h2>Go live</h2><p>Trade with your own money</p></div></div>
              <div class="form-card"><p class="muted" style="font-size:12px;font-weight:300;line-height:1.6">${cfg.live.enabled ? 'Switch to the Live account in the title bar, deposit from your bank and trade with real profits — and real losses.' : 'Live trading is turned off on this server.'}</p>
              ${cfg.live.enabled ? `<div><button class="btn-teal" data-a="golive">${icon('bolt')}Switch to Live</button></div>` : ''}</div></section>
          </div>`;
        const r = refs(el);
        const update = () => {
          const acc = NZ.account(), mt = NZ.metrics(acc);
          setStat(el, 'eq', NZ.money(mt.equity), pctOf(mt.equity - cfg.practice.startingCash, cfg.practice.startingCash));
          setStat(el, 'start', NZ.money0(cfg.practice.startingCash));
          setStat(el, 'net', NZ.signed(mt.net), null, mt.net);
          setStat(el, 'trades', String(acc.trades));
          const wait = acc.resetAt + cfg.practice.resetCooldown * 60 - S.t;
          NZ.text(r.cool, wait > 0 ? `Available in ${NZ.countdown(wait)}` : '');
        };
        el.addEventListener('click', async (e) => {
          if (e.target.closest('[data-a=golive]')) return ctx.mid.querySelector('[data-acct=live]').click();
          if (!e.target.closest('[data-a=reset]')) return;
          const ok = await NZ.confirm({ title: 'Reset practice account?', text: `All positions and orders are closed and your balance returns to ${NZ.money0(cfg.practice.startingCash)}. Your practice history is kept.`, ok: 'Reset account' });
          if (!ok) return;
          const res = await NZ.api('reset');
          if (!res.ok) { NZ.sound.play('reject'); return NZ.toast({ kind: 'err', title: 'Reset unavailable', text: res.err }); }
          T.history = null;
          NZ.sound.play('unlock');
          NZ.toast({ title: 'Practice account reset', text: `Balance restored to ${NZ.money0(cfg.practice.startingCash)}.` });
        });
        update();
        return { quotes: update, account: update };
      }

      el.innerHTML = `
        <div class="head"><div><h1>Funding</h1><p>Move money between your bank and your brokerage account.</p></div></div>
        <div class="stats s4">${stat('bank', 'Bank balance', 'bank', 'mono')}${stat('cash', 'Brokerage cash', 'wallet')}${stat('wd', 'Withdrawable', 'arrowUp')}${stat('eq', 'Account equity', 'pulse')}</div>
        <div class="cols">
          <section class="panel"><div class="p-head"><div><h2>Transfer</h2><p>Instant · no fees</p></div><div class="seg" data-r="dir"><button data-d="deposit" class="on">Deposit</button><button data-d="withdraw">Withdraw</button></div></div>
            <div class="form-card">
              <div class="field"><label>Amount <b data-r="lim"></b></label><input class="input" data-r="amt" placeholder="$0"></div>
              <div class="amt-chips"><button data-v="1000">$1K</button><button data-v="5000">$5K</button><button data-v="10000">$10K</button><button data-v="25000">$25K</button><button data-v="max">Max</button></div>
              <button class="btn-teal" data-r="go" style="height:38px">${icon('arrowRight')}<span>Deposit to brokerage</span></button>
              <p class="muted" style="font-size:11px;font-weight:300;line-height:1.6">Withdrawals are limited to settled cash not needed as margin for open positions.</p>
            </div></section>
          <section class="panel"><div class="p-head"><div><h2>Transfer history</h2><p>Deposits & withdrawals</p></div></div><div class="p-body" style="padding:0" data-r="ledger"></div></section>
        </div>`;
      const r = refs(el);
      let mode = 'deposit', bank = null;
      const loadBank = async () => { const res = await NZ.api('bank'); if (res.ok) { bank = res.data; update(); } };
      const update = () => {
        const acc = NZ.account(), mt = NZ.metrics(acc);
        setStat(el, 'bank', bank == null ? '…' : NZ.money(bank));
        setStat(el, 'cash', NZ.money(acc.cash));
        setStat(el, 'wd', NZ.money(mt.withdrawable));
        setStat(el, 'eq', NZ.money(mt.equity), mt.dayPct);
        NZ.text(r.lim, mode === 'deposit' ? `min ${NZ.money0(cfg.live.minDeposit)}` : `max ${NZ.money(mt.withdrawable)}`);
      };
      const renderLedger = async () => {
        if (!T.history) await loadHistory();
        const l = T.history ? T.history.ledger : [];
        r.ledger.innerHTML = l.length ? `<table class="tbl"><thead><tr><th>Date</th><th>Type</th><th class="r">Amount</th></tr></thead><tbody>
          ${l.map((x) => `<tr><td>${NZ.shortDate(x.time)} ${NZ.clock(x.time)}</td><td style="text-transform:capitalize">${x.type}</td><td class="r ${x.type === 'withdraw' ? 'dn' : 'up'}"><b>${x.type === 'withdraw' ? '-' : '+'}${NZ.money(x.amount)}</b></td></tr>`).join('')}</tbody></table>`
          : `<div class="empty">${icon('bank')}<b>No transfers yet</b><span>Deposit from your bank to start trading live.</span></div>`;
      };
      el.addEventListener('click', async (e) => {
        const d = e.target.closest('[data-d]');
        if (d) {
          mode = d.dataset.d;
          r.dir.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === d));
          r.go.lastElementChild.textContent = mode === 'deposit' ? 'Deposit to brokerage' : 'Withdraw to bank';
          r.go.className = mode === 'deposit' ? 'btn-teal' : 'btn-white';
          return update();
        }
        const v = e.target.closest('[data-v]');
        if (v) {
          const mt = NZ.metrics();
          r.amt.value = v.dataset.v === 'max' ? Math.floor(mode === 'deposit' ? Math.min(bank || 0, cfg.live.maxDeposit) : mt.withdrawable) : v.dataset.v;
          return NZ.sound.play('click');
        }
        if (e.target.closest('[data-r=go]')) {
          const amount = Math.floor(num(r.amt.value) || 0);
          if (!amount) return;
          r.go.disabled = true;
          const res = await NZ.api(mode, { amount });
          r.go.disabled = false;
          if (!res.ok) { NZ.sound.play('reject'); return NZ.toast({ kind: 'err', title: 'Transfer failed', text: res.err }); }
          bank = res.data;
          r.amt.value = '';
          T.history = null;
          NZ.sound.play('fill');
          NZ.toast({ title: mode === 'deposit' ? 'Deposit complete' : 'Withdrawal complete', text: `${NZ.money(amount)} ${mode === 'deposit' ? 'added to your brokerage account' : 'sent to your bank'}.` });
          update();
          renderLedger();
        }
      });
      loadBank();
      update();
      renderLedger();
      return { quotes: update, account: update };
    };

    // ── leaderboard ──────────────────────────────────────────────
    VIEWS.leaders = (el) => {
      let kind = S.active;
      el.classList.add('view-pad');
      el.innerHTML = `
        <div class="head"><div><h1>Leaderboard</h1><p>Top traders in the city by realized profit after fees.</p></div>
          <div class="seg" data-r="k"><button data-k="practice">Practice</button>${S.cfg.live.enabled ? '<button data-k="live">Live</button>' : ''}</div></div>
        <section class="panel" style="flex:1"><div class="p-body" style="padding:0" data-r="tbl"></div></section>`;
      const r = refs(el);
      async function render() {
        r.k.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.k === kind));
        r.tbl.innerHTML = `<div style="padding:14px;display:flex;flex-direction:column;gap:10px">${Array(6).fill('<div class="sk" style="height:28px"></div>').join('')}</div>`;
        const res = await NZ.api('leaderboard', { type: kind });
        const rows = res.ok ? res.data : [];
        r.tbl.innerHTML = rows.length ? `<table class="tbl"><thead><tr><th style="width:60px">Rank</th><th>Trader</th><th class="r">Trades</th><th class="r">Net realized</th></tr></thead><tbody>
          ${rows.map((x, i) => `<tr><td><span class="rank r${i + 1}">${i + 1}</span></td><td><b>${NZ.esc(x.name)}</b>${S.profile && x.name === S.profile.name ? ' <span class="chip">YOU</span>' : ''}</td><td class="r">${x.trades}</td><td class="r ${NZ.dir(x.net)}"><b class="${NZ.dir(x.net)}">${NZ.signed(x.net)}</b></td></tr>`).join('')}</tbody></table>`
          : `<div class="empty">${icon('trophy')}<b>No ranked traders yet</b><span>Close a trade to get on the board.</span></div>`;
      }
      el.addEventListener('click', (e) => { const k = e.target.closest('[data-k]'); if (k) { kind = k.dataset.k; render(); } });
      render();
      return {};
    };

    // ── settings ─────────────────────────────────────────────────
    VIEWS.settings = (el) => {
      el.classList.add('view-pad');
      el.innerHTML = `<div class="head"><div><h1>Settings</h1><p>Sounds, trading safety and display. Saved to your profile.</p></div></div><div data-r="s" style="flex:1;min-height:0"></div>`;
      NZ.renderSettings(el.querySelector('[data-r=s]'));
      return {};
    };

    // ── shared bits ──────────────────────────────────────────────
    function stat(id, label, ic, tone = '') {
      return `<div class="stat" data-stat="${id}"><div class="tile ${tone}">${icon(ic)}</div><div class="stat-txt"><span>${label}</span><b>—</b></div><div class="delta hidden">${icon('arrowUp')}<em style="font-style:normal"></em></div></div>`;
    }
    function setStat(root, id, value, deltaPct, tone) {
      const s = root.querySelector(`[data-stat="${id}"]`);
      if (!s) return;
      const b = s.querySelector('b');
      NZ.text(b, value);
      b.className = tone !== undefined && tone !== null ? NZ.dir(tone) : '';
      const d = s.querySelector('.delta');
      if (deltaPct == null || !isFinite(deltaPct)) return d.classList.add('hidden');
      d.classList.remove('hidden');
      d.classList.toggle('dn', deltaPct < 0);
      NZ.text(d.querySelector('em'), Math.abs(deltaPct).toFixed(2) + '%');
    }


    async function loadHistory() {
      const res = await NZ.api('history', { account: S.active });
      if (res.ok) T.history = res.data;
      return T.history;
    }

    function fillsTable(fills) {
      return `<table class="tbl"><thead><tr><th>Time</th><th>Symbol</th><th>Side</th><th class="r">Qty</th><th class="r">Price</th><th class="r">Fee</th><th class="r">Realized</th></tr></thead><tbody>
        ${fills.map((f) => `<tr><td>${NZ.clock(f.time, true)}</td><td><b>${f.sym}</b></td><td class="${f.side === 'buy' ? 'up' : 'dn'}">${f.side.toUpperCase()}</td><td class="r">${NZ.qty(f.qty)}</td>
          <td class="r"><b>${NZ.px(f.price)}</b></td><td class="r">${NZ.money(f.fee)}</td><td class="r ${NZ.dir(f.realized)}">${f.realized ? NZ.signed(f.realized) : '—'}</td></tr>`).join('')}</tbody></table>`;
    }

    async function toggleWatch(sym) {
      const list = S.watch.includes(sym) ? S.watch.filter((s) => s !== sym) : S.watch.concat(sym);
      S.watch = list;
      NZ.sound.play('click');
      if (T.v && T.v.watch) T.v.watch();
      const res = await NZ.api('watchlist', { list });
      if (res.ok) S.watch = res.data;
    }

    async function addAlert(sym, cond, price) {
      if (!price) return NZ.toast({ kind: 'err', title: 'Enter a price', text: 'Alerts need a trigger price.' });
      const res = await NZ.api('alertAdd', { symbol: sym, cond, price });
      if (!res.ok) { NZ.sound.play('reject'); return NZ.toast({ kind: 'err', title: 'Alert not saved', text: res.err }); }
      S.alerts = res.data;
      NZ.sound.play('place');
      NZ.toast({ title: 'Alert set', text: `${sym} ${cond === 'above' ? 'rises above' : 'falls below'} ${NZ.px(price)}` });
      NZ.emit('alerts');
    }
    async function delAlert(id) {
      const res = await NZ.api('alertDel', { id });
      if (res.ok) { S.alerts = res.data; NZ.sound.play('cancel'); NZ.emit('alerts'); }
    }
    async function cancelOrder(id) {
      const res = await NZ.api('cancel', { account: S.active, id });
      if (!res.ok) NZ.toast({ kind: 'err', title: 'Cancel failed', text: res.err });
    }
    async function cancelAll(sym) {
      const res = await NZ.api('cancelAll', { account: S.active, symbol: sym });
      if (res.ok && !res.data) NZ.toast({ title: 'No working orders', text: sym ? `Nothing working in ${sym}.` : 'Nothing to cancel.' });
    }
    async function flatten(sym) {
      const acc = NZ.account();
      if (!acc || !acc.positions.some((p) => !sym || p.sym === sym)) {
        if (!sym || !acc.orders.some((o) => o.sym === sym)) return NZ.toast({ title: 'Nothing to flatten', text: sym ? `No position in ${sym}.` : 'No open positions.' });
      }
      if (!sym && S.settings.confirm) {
        const ok = await NZ.confirm({ title: 'Flatten everything?', text: 'Every open position is closed at market and all working orders are cancelled.', ok: 'Flatten all' });
        if (!ok) return;
      }
      const res = await NZ.api('flatten', { account: S.active, symbol: sym });
      if (!res.ok) { NZ.sound.play('reject'); NZ.toast({ kind: 'err', title: 'Flatten failed', text: res.err }); }
    }

    // ── subscriptions ────────────────────────────────────────────
    const sub = (ev, fn) => T.offs.push(NZ.on(ev, fn));
    sub('quotes', () => { updateChrome(); if (T.v.quotes) T.v.quotes(); });
    sub('account', () => { updateChrome(); if (T.v.account) T.v.account(); });
    sub('fill', (f) => { T.history = null; if (T.v.fill) T.v.fill(f); });
    sub('alerts', () => { if (T.v.alerts) T.v.alerts(); });
    sub('news', () => { if (T.view === 'news') S.unreadNews = 0; updateChrome(); if (T.v.news) T.v.news(); });
    sub('calendar', () => { if (T.v.calendar) T.v.calendar(); });
    sub('halt', () => { if (T.v.halt) T.v.halt(); });
    sub('session', () => { updateChrome(); if (T.v.halt) T.v.halt(); });
    sub('scale', () => { if (T.v.resize) T.v.resize(); });
    sub('settings', () => { if (S.device !== 'tablet') root.classList.toggle('compact', !!S.settings.compact); });

    renderSide();
    go(T.view, true);

    return {
      key(e) {
        if (!S.settings.hotkeys || T.view !== 'terminal' || !T.v.key) return false;
        return T.v.key(e);
      },
      focusSymbol,
      ticket(preset) {
        if (preset.symbol && S.by[preset.symbol]) T.focus = S.focus = preset.symbol;
        if (preset.ticket) Object.assign(T.tk, preset.ticket, { sym: T.focus });
        if (T.view !== 'terminal') go('terminal');
        else if (T.v.focus) T.v.focus();
      },
      destroy() {
        T.offs.forEach((off) => off());
        if (T.v && T.v.destroy) T.v.destroy();
      },
    };
  }

  NZ.apps = NZ.apps || {};
  NZ.apps.trader = {
    id: 'trader', icon: 'teal', glyph: 'candles', size: 'max',
    title: () => S.cfg.ui.brand, sub: () => S.cfg.ui.sub,
    create,
  };
})();
