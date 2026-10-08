/* ═══════════════════════════════════════════════════════════
   Browser preview — only runs when opened outside FiveM.
   Simulates the server so the UI can be designed in a browser:
   open html/index.html (add ?device=tablet or ?onboard=1).
   ═══════════════════════════════════════════════════════════ */
(() => {
  if (NZ.resource) return;

  const params = new URLSearchParams(location.search);
  const now = () => Math.floor(Date.now() / 1000);
  const gauss = () => Math.sqrt(-2 * Math.log(Math.random() || 1e-9)) * Math.cos(2 * Math.PI * Math.random());
  const round = (p) => { const t = p >= 1 ? 0.01 : 0.0001; return Math.round(p / t) * t; };

  const DEF = [
    ['GLBL', 'Global 500', 'index', 'index', 6581], ['TECH', 'Tech Composite', 'index', 'index', 24015.36],
    ['FRUT', 'Fruit Computers', 'stock', 'tech', 251.49, 0.024], ['WHIZ', 'Whiz Wireless', 'stock', 'tech', 341.82, 0.035],
    ['FACI', 'Facade Social', 'stock', 'tech', 580.2, 0.032], ['MAZE', 'Maze Bank', 'stock', 'finance', 245, 0.02],
    ['FLEE', 'Fleeca', 'stock', 'finance', 112.5, 0.022], ['LIFE', 'LifeInvader', 'stock', 'media', 12.75, 0.07],
    ['WZL', 'Weazel Media', 'stock', 'media', 67.8, 0.034], ['VAPD', 'Vapid Motors', 'stock', 'transport', 89.3, 0.03],
    ['RON', 'RON Oil', 'stock', 'energy', 78.9, 0.03], ['AMMU', 'Ammu-Nation', 'stock', 'retail', 156, 0.03],
    ['BURG', 'Burger Shot', 'stock', 'consumer', 41.2, 0.024], ['SHRK', 'Shark Cards Ltd', 'stock', 'speculative', 42.69, 0.09],
    ['BKC', 'BlockCoin', 'crypto', 'crypto', 68421.5, 0.035], ['ETRM', 'Ethereum Max', 'crypto', 'crypto', 3845.2, 0.045],
    ['DGEN', 'DegenCoin', 'crypto', 'crypto', 0.42, 0.12],
  ];
  const H = 5400;
  const syms = DEF.map(([s, n, type, sector, price, vol]) => {
    const c5 = [];
    let p = price * (0.97 + Math.random() * 0.06);
    const t0 = now() - (now() % 5) - 720 * 5 * 12;
    for (let k = 0; k < 720 * 12; k++) {
      const o = p;
      p = round(p * Math.exp((vol || 0.012) * Math.sqrt(5 / H) * gauss()));
      c5.push([t0 + k * 5, o, Math.max(o, p) * 1.0004, Math.min(o, p) * 0.9996, p, type === 'index' ? 0 : Math.round(150e6 / price / H * 5 * (0.5 + Math.random()))]);
    }
    return { s, n, type, sector, price: p, prev: c5[0][1], vol: vol || 0.012, vpt: type === 'index' ? 0 : 150e6 / price / H, c5, volume: 2e6 / Math.sqrt(price), hi: p, lo: p, halt: 0 };
  });
  syms.forEach((m) => { m.c5.forEach((c) => { m.hi = Math.max(m.hi, c[2]); m.lo = Math.min(m.lo, c[3]); }); });
  const by = Object.fromEntries(syms.map((m) => [m.s, m]));
  const spread = (m) => (m.type === 'index' ? 0 : Math.max(m.price >= 1 ? 0.02 : 0.0002, m.price * 0.0004));
  const quotes = () => syms.map((m) => [m.price, round(m.price - spread(m) / 2), round(m.price + spread(m) / 2), m.volume, m.hi, m.lo]);

  let nextId = 100;
  const accounts = {
    practice: { id: 1, type: 'practice', cash: 100000, realized: 0, fees: 0, trades: 0, dayStart: 100000, resetAt: 0, positions: [], orders: [] },
    live: { id: 2, type: 'live', cash: 25000, realized: 0, fees: 0, trades: 0, dayStart: 25000, resetAt: 0, positions: [], orders: [] },
  };
  const history = { practice: { orders: [], fills: [], ledger: [] }, live: { orders: [], fills: [], ledger: [{ type: 'deposit', amount: 25000, time: now() - 3600 }] } };
  let profile = params.get('onboard') ? null : { name: 'Nay Zeee', settings: {}, watchlist: ['FRUT', 'MAZE', 'LIFE', 'SHRK', 'BKC', 'ETRM'], active: 'practice' };
  let alerts = [], bank = 184250;
  const news = [
    { id: 1, kind: 'earnings', symbol: 'FRUT', text: 'Fruit Computers Q4 earnings: EPS $2.41 vs $2.10 est. — beat', impact: 0.07, time: now() - 300 },
    { id: 2, kind: 'macro', scope: 'market', text: 'Fed signals rate cuts ahead; equities rally', impact: 0.012, time: now() - 900 },
    { id: 3, kind: 'company', symbol: 'LIFE', text: 'Data breach exposes millions of LifeInvader customers', impact: -0.06, time: now() - 1500 },
  ];
  const calendar = [{ id: 1, symbol: 'MAZE', name: 'Maze Bank', at: now() + 412, est: 1.42, q: 4 }, { id: 2, symbol: 'AMMU', name: 'Ammu-Nation', at: now() + 1310, est: 0.97, q: 4 }];

  const send = (action, data) => window.postMessage({ action, data }, '*');
  const pos = (acc, s) => acc.positions.find((p) => p.sym === s);
  const fee = (s, q, p) => (by[s].type === 'crypto' ? q * p * 0.0015 : Math.min(Math.max(1, q * 0.005), q * p * 0.005));

  function fill(acc, o, px) {
    const signed = o.side === 'buy' ? o.qty : -o.qty;
    const f = Math.round(fee(o.sym, o.qty, px) * 100) / 100;
    let p = pos(acc, o.sym), realized = 0;
    if (!p) { p = { sym: o.sym, qty: 0, avg: 0 }; acc.positions.push(p); }
    if (p.qty === 0 || (p.qty > 0) === (signed > 0)) {
      p.avg = (Math.abs(p.qty) * p.avg + o.qty * px) / Math.abs(p.qty + signed);
      p.qty += signed;
    } else {
      realized = Math.min(Math.abs(p.qty), o.qty) * (px - p.avg) * (p.qty > 0 ? 1 : -1);
      const nq = p.qty + signed;
      if (nq !== 0 && (nq > 0) !== (p.qty > 0)) p.avg = px;
      p.qty = nq;
    }
    acc.positions = acc.positions.filter((x) => Math.abs(x.qty) > 1e-9);
    acc.cash -= signed * px + f;
    acc.realized += realized; acc.fees += f; acc.trades++;
    acc.orders = acc.orders.filter((x) => x.id !== o.id);
    if (o.oco) acc.orders = acc.orders.filter((x) => x.oco !== o.oco);
    history[acc.type].fills.unshift({ id: nextId++, sym: o.sym, side: o.side, qty: o.qty, price: px, fee: f, realized, time: now() });
    history[acc.type].orders.unshift({ ...o, status: 'filled', price: px, time: now() });
    if (!o.reduce && (o.tp || o.sl)) {
      const side = o.side === 'buy' ? 'sell' : 'buy';
      if (o.tp) acc.orders.unshift({ id: nextId++, sym: o.sym, side, type: 'limit', qty: o.qty, limit: o.tp, tif: 'gtc', oco: o.id, reduce: true, created: now() });
      if (o.sl) acc.orders.unshift({ id: nextId++, sym: o.sym, side, type: 'stop', qty: o.qty, stop: o.sl, tif: 'gtc', oco: o.id, reduce: true, created: now() });
    }
    setTimeout(() => { send('fill', { acc: acc.type, sym: o.sym, side: o.side, qty: o.qty, price: px, fee: f, realized, type: o.type }); send('account', acc); }, 60);
  }

  const API = {
    boot: () => ({
      player: { name: 'Nay Zeee' },
      cfg: { ui: { brand: 'NZ Trader', company: 'Nayzeee Securities', sub: 'Brokerage · Los Santos', version: '4.0.0' }, leverage: 2, maintenance: 0.25, allowShort: true, cryptoDecimals: 4,
        fees: { stock: { perShare: 0.005, min: 1, maxPct: 0.005 }, crypto: { pct: 0.0015 } }, practice: { startingCash: 100000, resetCooldown: 30 },
        live: { enabled: true, minDeposit: 100, maxDeposit: 2500000 }, maxAlerts: 15, hours: { enabled: false } },
      market: syms.map((m) => ({ s: m.s, n: m.n, type: m.type, sector: m.sector, ex: m.type === 'crypto' ? 'CRYPTO' : m.type === 'index' ? 'INDEX' : 'BAWSAQ', prev: m.prev, open: m.prev, tradable: m.type !== 'index', vpt: m.vpt, halt: 0,
        spark: m.c5.filter((_, i) => i % 12 === 11).slice(-60).map((c) => c[4]) })),
      quotes: quotes(), session: { code: 'open', enabled: false }, news, calendar, t: now(),
      profile, accounts: profile ? accounts : null, alerts,
    }),
    createProfile: (d) => { profile = { name: d.name, settings: {}, watchlist: ['FRUT', 'MAZE', 'BKC'], active: 'practice' }; return API.boot(); },
    candles: ({ symbol, tf }) => {
      const out = [];
      for (const c of by[symbol].c5) {
        const b = c[0] - (c[0] % tf);
        const l = out[out.length - 1];
        if (!l || l[0] !== b) out.push([b, c[1], c[2], c[3], c[4], c[5]]);
        else { l[2] = Math.max(l[2], c[2]); l[3] = Math.min(l[3], c[3]); l[4] = c[4]; l[5] += c[5]; }
      }
      return out.slice(-400);
    },
    order: (d) => {
      const acc = accounts[d.account];
      const m = by[d.symbol];
      const o = { id: nextId++, sym: d.symbol, side: d.side, type: d.type, qty: d.qty, limit: d.limit, stop: d.stop, trail: d.trail, tif: d.tif || 'day', tp: d.tp, sl: d.sl, created: now() };
      if (d.type === 'trail') o.stop = round(d.side === 'sell' ? m.price - d.trail : m.price + d.trail);
      if (d.type === 'market') { fill(acc, o, round(m.price + (d.side === 'buy' ? 1 : -1) * spread(m) / 2)); return { id: o.id }; }
      acc.orders.unshift(o);
      setTimeout(() => { send('order', { acc: acc.type, kind: 'working', ...o }); send('account', acc); }, 40);
      return { id: o.id };
    },
    cancel: (d) => {
      const acc = accounts[d.account];
      const o = acc.orders.find((x) => x.id === d.id);
      acc.orders = acc.orders.filter((x) => x.id !== d.id);
      if (o) history[acc.type].orders.unshift({ ...o, status: 'cancelled', reason: 'Cancelled', time: now() });
      setTimeout(() => { send('order', { acc: acc.type, kind: 'cancelled', ...o }); send('account', acc); }, 40);
      return true;
    },
    cancelAll: (d) => {
      const acc = accounts[d.account];
      const list = acc.orders.filter((o) => !d.symbol || o.sym === d.symbol);
      list.forEach((o) => API.cancel({ account: d.account, id: o.id }));
      return list.length;
    },
    flatten: (d) => {
      const acc = accounts[d.account];
      API.cancelAll(d);
      acc.positions.filter((p) => !d.symbol || p.sym === d.symbol).forEach((p) => {
        const m = by[p.sym];
        fill(acc, { id: nextId++, sym: p.sym, side: p.qty > 0 ? 'sell' : 'buy', type: 'market', qty: Math.abs(p.qty), reduce: true }, m.price);
      });
      return 1;
    },
    history: (d) => history[d.account],
    bank: () => bank,
    deposit: (d) => { bank -= d.amount; accounts.live.cash += d.amount; accounts.live.dayStart += d.amount; history.live.ledger.unshift({ type: 'deposit', amount: d.amount, time: now() }); send('account', accounts.live); return bank; },
    withdraw: (d) => { bank += d.amount; accounts.live.cash -= d.amount; accounts.live.dayStart -= d.amount; history.live.ledger.unshift({ type: 'withdraw', amount: d.amount, time: now() }); send('account', accounts.live); return bank; },
    reset: () => { Object.assign(accounts.practice, { cash: 100000, realized: 0, fees: 0, trades: 0, dayStart: 100000, positions: [], orders: [], resetAt: now() }); send('account', accounts.practice); return true; },
    alertAdd: (d) => { alerts.push({ id: nextId++, sym: d.symbol, cond: d.cond, price: d.price }); return alerts; },
    alertDel: (d) => { alerts = alerts.filter((a) => a.id !== d.id); return alerts; },
    settings: (d) => d.settings,
    watchlist: (d) => d.list,
    active: (d) => d.account,
    leaderboard: () => [['Lester C.', 182340], ['Nay Zeee', 96412], ['Vinewood Capital', 64210], ['Dom B.', 22018], ['Trevor P.', -4210]].map(([name, net], i) => ({ name, net, trades: 240 - i * 37 })),
  };

  NZ.preview = {
    post(name, data) {
      if (name === 'close') { setTimeout(() => start(params.get('device') || 'laptop'), 1200); return Promise.resolve(true); }
      if (name !== 'api') return Promise.resolve(true);
      const fn = API[data.action];
      if (!fn) return Promise.resolve({ ok: false, err: 'Unknown action' });
      return new Promise((r) => setTimeout(() => r({ ok: true, data: fn(data.data || {}) }), 60));
    },
  };

  // market heartbeat
  setInterval(() => {
    const t = now();
    for (const m of syms) {
      if (m.type === 'index') continue;
      m.price = round(m.price * Math.exp(m.vol * Math.sqrt(1 / H) * 1.6 * gauss()));
      const v = Math.round(m.vpt * (0.4 + Math.random()));
      m.volume += v;
      m.hi = Math.max(m.hi, m.price); m.lo = Math.min(m.lo, m.price);
      const b = t - (t % 5), l = m.c5[m.c5.length - 1];
      if (l[0] !== b) m.c5.push([b, m.price, m.price, m.price, m.price, v]);
      else { l[2] = Math.max(l[2], m.price); l[3] = Math.min(l[3], m.price); l[4] = m.price; l[5] += v; }
    }
    const stocks = syms.filter((m) => m.type === 'stock');
    syms.filter((m) => m.type === 'index').forEach((m) => { m.price = round(DEF.find((d) => d[0] === m.s)[4] * stocks.reduce((a, s) => a + s.price / DEF.find((d) => d[0] === s.s)[4], 0) / stocks.length); });
    for (const type of ['practice', 'live']) {
      const acc = accounts[type];
      for (const o of acc.orders.slice()) {
        const m = by[o.sym];
        if ((o.type === 'limit' && ((o.side === 'buy' && m.price <= o.limit) || (o.side === 'sell' && m.price >= o.limit)))
          || (o.type !== 'limit' && ((o.side === 'buy' && m.price >= o.stop) || (o.side === 'sell' && m.price <= o.stop)))) fill(acc, o, m.price);
      }
    }
    send('quotes', { t, q: quotes() });
  }, 1000);

  function start(device) {
    send('open', { device, boot: API.boot() });
  }
  document.body.style.background = 'radial-gradient(1200px 700px at 50% 30%, #1a2a2a, #050606)';
  setTimeout(() => start(params.get('device') || 'laptop'), 300);
  if (params.get('hint')) send('hint', { title: 'Place laptop', keys: [['E', 'Place'], ['Scroll', 'Rotate'], ['Shift', 'Fine'], ['Backspace', 'Cancel']] });
})();
