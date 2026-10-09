/* ═══════════════════════════════════════════════════════════
   NAYZEEE BANKING — phone app

   One page for every phone. client/cl_phone.lua loads it with
   ?phone=lb|qs|okok|ys so it knows which bridge it is sitting in.
   lb-phone injects fetchNui() into globalThis; every other phone
   is reached with a plain NUI fetch, which is what their own app
   templates do. Outside a phone the layout still renders.

   Cash never moves here. Depositing and withdrawing need a machine
   or a teller — the phone does everything else.
   ═══════════════════════════════════════════════════════════ */

const P = {
  tab: 'money',
  page: null,
  stack: [],
  data: null,
  currency: '$',
  currencyRight: false,
  hidden: false,
  amount: '',
  flow: 'send',
  who: 'nearby',
  targets: null,
  asset: null,
  period: 'week',
  busy: false
};

const RES = 'nayzeee-banking';

/* no ?phone= means an older registration, which was always lb-phone */
const PHONE = (new URLSearchParams(location.search).get('phone') || 'lb').toLowerCase();

/* ── bridge ───────────────────────────────────────────────── */
async function call(name, payload) {
  // only lb-phone's fetchNui is known to take (name, data); another
  // phone's global of the same name may not, so it is not trusted
  if (PHONE === 'lb' && typeof fetchNui === 'function') {
    try { return await fetchNui(name, payload || {}); }
    catch (e) { return { ok: false, msg: 'The bank did not respond.' }; }
  }

  try {
    const res = await fetch(`https://${RES}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {})
    });
    return await res.json();
  } catch (e) {
    return null;
  }
}

/* ── helpers ──────────────────────────────────────────────── */
const el = (id) => document.getElementById(id);

/* the minus goes in front of the symbol: −$1,234, not $-1,234 */
const money = (n) => {
  const r = Math.round(n || 0);
  const v = Math.abs(r).toLocaleString('en-US');
  const s = P.currencyRight ? `${v}${P.currency}` : `${P.currency}${v}`;
  return r < 0 ? `−${s}` : s;
};

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const initials = (name) => String(name || '').trim().split(/\s+/)
  .slice(0, 2).map(w => w[0] || '').join('').toUpperCase();

const account = (id) => (P.data.accounts || []).find(a => a.id === id);

/** Minutes into something a person reads without doing sums. */
const countdown = (mins) => {
  const m = Math.max(0, Math.round(mins || 0));
  if (m === 0) return 'due now';
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  if (h < 24) return r ? `${h}h ${r}m` : `${h}h`;
  const d = Math.floor(h / 24);
  return `${d}d ${h % 24}h`;
};

const units = (n) => {
  const v = Number(n || 0);
  return v >= 1 ? v.toFixed(4) : v.toPrecision(3);
};

const I = {
  in:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v13M6.5 12.5 12 18l5.5-5.5"/></svg>',
  out:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V6M6.5 11.5 12 6l5.5 5.5"/></svg>',
  swap:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h14l-3.5-3.5M20 16H6l3.5 3.5"/></svg>',
  card:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="2.5" y="5.5" width="19" height="13" rx="3"/><path d="M2.5 10h19"/></svg>',
  bank:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9.5 12 4l9 5.5M5 10v9M19 10v9M3 20h18"/></svg>',
  bag:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 11a6 6 0 0 1 6-6h3a6 6 0 0 1 6 6v3a4 4 0 0 1-4 4h-1v2h-3v-2H9a5 5 0 0 1-5-5v-2z"/></svg>',
  bill:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3z"/><path d="M9.5 8h5M9.5 12h5"/></svg>',
  coin:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M14.5 9.2a3 3 0 0 0-5.2 2c0 2.4 5 2 5 4.2a3 3 0 0 1-5.2 1.5M12 6.5v11"/></svg>',
  chart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17.5 9 11l4 4 8-8.5"/><path d="M15 6.5h6v6"/></svg>',
  repay: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9h12a4 4 0 0 1 0 8h-5"/><path d="M8 5 4 9l4 4"/></svg>',
  book:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3.5h11a1.5 1.5 0 0 1 1.5 1.5v14a1.5 1.5 0 0 1-1.5 1.5H6z"/><path d="M6 3.5v17M3.5 8h2.5M3.5 12h2.5M3.5 16h2.5"/></svg>',
  clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5.2l3.2 2"/></svg>',
  none:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
  chev:  '<svg class="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 6 15.5 12l-6 6"/></svg>'
};

const CAT = {
  deposit: 'in', withdraw: 'out', transfer: 'swap', card: 'card',
  loan: 'coin', interest: 'bag', bill: 'bill', payroll: 'in',
  fee: 'out', admin: 'bank'
};

function hexToRgb(hex) {
  const h = String(hex || '').replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
  const n = parseInt(full, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** One hex in config repaints the whole app. */
function applyTheme(ui) {
  if (!ui) return;
  const root = document.documentElement.style;

  root.setProperty('--accent', ui.accent);
  root.setProperty('--accent-hi', ui.accentLight || ui.accent);
  root.setProperty('--accent-lo', ui.accentDark || ui.accent);
  if (ui.danger) root.setProperty('--red', ui.danger);

  const [r, g, b] = hexToRgb(ui.accentDark || ui.accent);
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  root.setProperty('--accent-ink', lum > 0.45 ? '#001512' : '#00201d');

  // Splash and the Money header. A file that will not load leaves the
  // built-in mark showing, so a missing logo costs nothing.
  const swap = (imgId, markId) => {
    const img = el(imgId), mark = markId ? el(markId) : null;
    if (!img) return;

    if (!ui.logo || String(ui.logo).trim() === '') {
      img.classList.add('hidden');
      if (mark) mark.classList.remove('hidden');
      return;
    }

    img.onload = () => { img.classList.remove('hidden'); if (mark) mark.classList.add('hidden'); };
    img.onerror = () => { img.classList.add('hidden'); if (mark) mark.classList.remove('hidden'); };
    img.src = ui.logo;
  };

  swap('splashLogo', 'splashMark');
  swap('phoneLogo', null);
}

/* ── toasts ───────────────────────────────────────────────── */
function toast(title, body, bad) {
  const node = document.createElement('div');
  node.className = 'toast' + (bad ? ' err' : '');
  node.innerHTML = `<b>${esc(title)}</b>${body ? `<span>${esc(body)}</span>` : ''}`;
  el('toasts').appendChild(node);
  setTimeout(() => node.remove(), 3200);
}

function reply(res, fallback) {
  if (!res) { toast('Banking', fallback || 'That did not go through.', true); return false; }
  toast(res.ok ? 'Done' : 'Not completed', res.msg || fallback, !res.ok);
  return res.ok;
}

/* ── nothing renders without data ─────────────────────────────
   The bank not answering is a real state, not a crash. Every
   screen checks for it in one place and says so, rather than
   reading .cards off null.
   ───────────────────────────────────────────────────────────── */
function ready() { return !!(P.data && P.data.player); }

function offline(boxId, why) {
  const box = el(boxId);
  if (!box) return;
  box.innerHTML = `<div class="empty">${I.none}<b>Can't reach the bank</b>
    <span>${esc(why || 'The server did not answer. Close the app and open it again.')}</span>
    <button class="pill solid" style="margin-top:18px" id="retry">Try again</button></div>`;
}

document.addEventListener('click', (e) => {
  if (e.target.closest('#retry')) boot();
});

/* ── navigation ───────────────────────────────────────────── */
function goTab(tab) {
  P.tab = tab;
  document.querySelectorAll('.tab').forEach(t =>
    t.classList.toggle('up', t.dataset.tab === tab));
  document.querySelectorAll('.bar button').forEach(b =>
    b.classList.toggle('on', b.dataset.tabGo === tab));

  const view = document.querySelector(`.tab[data-tab="${tab}"] .scroll`);
  if (view) view.scrollTop = 0;

  if (tab === 'activity') loadActivity();
}

const RENDER = {
  cards: renderCards, accounts: renderAccounts, bills: renderBills,
  settings: renderSettings, invest: renderInvest, borrow: renderBorrow,
  asset: renderAsset, who: renderWho, statement: renderStatement
};

function openPage(page, keepStack) {
  if (!keepStack && P.page) P.stack.push(P.page);
  P.page = page;

  document.querySelectorAll('.sheet-page').forEach(p =>
    p.classList.toggle('up', p.dataset.page === page));
  el('bar').classList.toggle('hidden', !!page);

  const view = document.querySelector(`.sheet-page[data-page="${page}"] .scroll`);
  if (view) view.scrollTop = 0;

  if (RENDER[page]) RENDER[page]();
}

/** Back goes one step, not all the way out — asset returns to investing. */
function closePage() {
  const previous = P.stack.pop();
  if (previous) return openPage(previous, true);

  P.page = null;
  document.querySelectorAll('.sheet-page').forEach(p => p.classList.remove('up'));
  el('bar').classList.remove('hidden');
}

/* ── modal ────────────────────────────────────────────────── */
let modalConfirm = null;

function openModal({ title, text, fields, confirm, onConfirm }) {
  el('modalTitle').textContent = title;
  el('modalText').textContent = text || '';
  el('modalFields').innerHTML = fields || '';
  el('modalOk').textContent = confirm || 'Confirm';
  el('modal').classList.add('up');
  modalConfirm = onConfirm;

  const first = el('modalFields').querySelector('input, select');
  if (first) setTimeout(() => first.focus(), 60);
}

function closeModal() {
  el('modal').classList.remove('up');
  modalConfirm = null;
}

el('modal').addEventListener('click', async (e) => {
  if (e.target.id === 'modal') return closeModal();
  const act = e.target.closest('[data-modal]');
  if (!act) return;
  if (act.dataset.modal === 'cancel') return closeModal();
  if (!modalConfirm) return;

  const values = {};
  el('modalFields').querySelectorAll('[data-name]').forEach(i => {
    values[i.dataset.name] = i.value;
  });

  act.disabled = true;
  try { await modalConfirm(values); }
  finally { act.disabled = false; }
});

/* ═══════════════ MONEY TAB ═══════════════ */
function renderMoney() {
  if (!ready()) return offline('moneyStack');
  const d = P.data;
  const primary = account(d.primary) || { balance: 0, number: '', label: '' };

  el('avatar').textContent = initials(d.player.name);
  el('avatarPay').textContent = initials(d.player.name);
  el('avatarAct').textContent = initials(d.player.name);

  el('balanceAcct').textContent = '•••• ' + String(primary.number || '').slice(-4);
  el('balance').textContent = P.hidden ? '••••' : money(primary.balance);
  el('balance').classList.toggle('hidden-amount', P.hidden);

  // card chips
  const cards = (d.cards || []).filter(c => {
    const a = account(c.account);
    return a && a.type !== 'savings';
  }).slice(0, 4);

  el('chipStrip').innerHTML = cards.map(c => `
    <button class="chip ${c.status !== 'active' ? 'off' : ''}" data-go="cards">
      <i>${I.card}</i>•• ${esc(String(c.number).slice(-4))}
      <em>${esc((c.typeLabel || '').split(' ')[0])}</em>
    </button>`).join('') || `
    <button class="chip" data-go="cards"><i>${I.card}</i>Order a card</button>`;

  // Overdrawn is the first thing you should see, not something
  // buried a screen deep.
  const od = d.overdraft;
  const odLine = el('odLine');
  if (od && od.on && primary.balance < 0) {
    odLine.innerHTML = `${I.clock}<span>Overdrawn · ${money(od.available)} of your
      overdraft left${od.graceLeft ? ` · interest in ${countdown(od.graceLeft)}` : ''}</span>`;
    odLine.className = 'od-line bad';
  } else if (od && od.on) {
    odLine.innerHTML = `<span>${money(od.limit)} overdraft available</span>`;
    odLine.className = 'od-line';
  } else {
    odLine.className = 'od-line hidden';
  }

  // stacked blocks
  const blocks = [];
  const sv = d.savings;

  if (sv && sv.open) {
    const pct = sv.goal ? Math.min(100, Math.round((sv.balance / sv.goal) * 100)) : 0;
    blocks.push(`
      <div class="block" data-go="accounts">
        <div class="b-head">
          <div>
            <span class="b-title">Savings</span>
            <b class="b-amount">${money(sv.balance)}</b>
            <span class="b-sub">${sv.goal ? `${pct}% of ${money(sv.goal)} goal` : `Up to ${(sv.rate * 100).toFixed(0)}% interest`}</span>
          </div>
          <div class="b-icon">${I.bag}</div>
        </div>
        ${sv.goal ? `<div class="meter"><i style="width:${pct}%"></i></div>` : ''}
      </div>`);
  }

  // investing — what you hold, not what the market is doing
  const m = d.market;
  if (d.config.features.market && m && m.assets && m.assets.length) {
    const held = (m.holdings || []).length;
    const lead = m.assets[0];
    const up = held ? (m.pl || 0) >= 0 : (lead.change || 0) >= 0;

    blocks.push(`
      <div class="block" data-go="invest">
        <div class="b-head">
          <div>
            <span class="b-title">Investing</span>
            <b class="b-amount">${held ? money(m.value) : money(lead.price)}</b>
            <span class="b-sub ${up ? 'up' : 'down'}">
              ${held
                ? `${(m.pl || 0) >= 0 ? '+' : '−'}${money(Math.abs(m.pl || 0))} all time`
                : `${esc(lead.label)} ${up ? '↑' : '↓'} ${Math.abs(lead.change || 0).toFixed(2)}%`}
            </span>
          </div>
          ${sparkline(lead.history, up)}
        </div>
      </div>`);
  }

  // borrowing — available against your credit, and what is outstanding
  if (d.config.features.loans) {
    const loan = d.loans && d.loans.active && d.loans.active[0];
    const best = (d.config.loanTiers || []).filter(t => d.credit.score >= t.minCredit).pop();

    blocks.push(`
      <div class="block" data-go="borrow">
        <span class="b-title">Borrow</span>
        <div class="dots">
          <div class="dot-row">
            <span class="ring"></span>
            <b>${money(best && !loan ? best.amount : 0)}</b><span>available</span>
          </div>
          <div class="dot-row">
            <span class="ring ${loan ? 'on' : ''}"></span>
            <b>${money(loan ? loan.remaining : 0)}</b><span>owed</span>
          </div>
        </div>
        ${loan ? `<div class="due-line ${loan.nextIn <= 10 ? 'soon' : ''}">
          ${I.clock}<span>${money(loan.payment)} due in ${countdown(loan.nextIn)}</span></div>` : ''}
      </div>`);
  }

  if (d.config.features.bills && d.bills.count) {
    blocks.push(`
      <div class="block" data-go="bills">
        <div class="b-head">
          <div>
            <span class="b-title">Bills</span>
            <b class="b-amount">${money(d.bills.total)}</b>
            <span class="b-sub">${d.bills.count} waiting</span>
          </div>
          <div class="b-icon">${I.bill}</div>
        </div>
      </div>`);
  }

  el('moneyStack').innerHTML = blocks.join('');

  const loan = d.loans && d.loans.active && d.loans.active[0];
  const owing = (d.bills.count || 0) + (loan ? 1 : 0);
  const dot = el('actDot');
  dot.textContent = owing;
  dot.classList.toggle('hidden', owing === 0);
}

function sparkline(points, up) {
  if (!points || points.length < 2) return '<div class="b-icon">' + I.chart + '</div>';

  const min = Math.min(...points), max = Math.max(...points);
  const span = (max - min) || 1;
  const step = 108 / (points.length - 1);
  const d = points.map((v, i) =>
    `${(2 + i * step).toFixed(1)},${(40 - ((v - min) / span) * 34).toFixed(1)}`).join(' ');

  return `<svg class="spark" viewBox="0 0 112 44">
    <polyline points="${d}" stroke="${up ? 'var(--accent)' : 'var(--red)'}"/></svg>`;
}

/** The same shape, drawn big for an asset's own page. */
function bigChart(points, up) {
  if (!points || points.length < 2) return '';

  const min = Math.min(...points), max = Math.max(...points);
  const span = (max - min) || 1;
  const step = 316 / (points.length - 1);

  const pts = points.map((v, i) =>
    [2 + i * step, 118 - ((v - min) / span) * 104]);

  const line = pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
  const area = `${line} ${pts[pts.length - 1][0].toFixed(1)},124 2,124`;
  const col = up ? 'var(--accent)' : 'var(--red)';

  return `<svg class="big-chart" viewBox="0 0 320 128" preserveAspectRatio="none">
    <polygon points="${area}" fill="${col}" opacity=".12"/>
    <polyline points="${line}" fill="none" stroke="${col}" stroke-width="2.4"
      stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`;
}

/* ═══════════════ PAY TAB ═══════════════ */
function renderPay() {
  if (!ready()) return;
  const raw = P.amount;
  el('payAmount').textContent = raw === '' ? money(0) : money(parseInt(raw, 10) || 0);

  const primary = account(P.data.primary) || { balance: 0 };
  el('payNote').textContent = raw === ''
    ? 'Enter an amount'
    : `${money(primary.balance)} available`;

  const empty = raw === '' || parseInt(raw, 10) <= 0;
  el('payGo').disabled = empty;
  el('payRequest').disabled = empty || !P.data.config.features.bills;
}

el('keypad').addEventListener('click', (e) => {
  const k = e.target.closest('[data-key]');
  if (!k) return;
  const key = k.dataset.key;

  if (key === 'clear') P.amount = '';
  else if (key === 'del') P.amount = P.amount.slice(0, -1);
  else if (P.amount.length < 9) P.amount = (P.amount + key).replace(/^0+/, '');

  renderPay();
});

el('payGo').addEventListener('click', () => startFlow('send'));
el('payRequest').addEventListener('click', () => startFlow('request'));

function startFlow(flow) {
  const amount = parseInt(P.amount, 10);
  if (!amount || amount <= 0) return;

  P.flow = flow;
  P.stack = [];
  openPage('who', true);
}

/* ═══════════════ WHO — picking a person ═══════════════ */
async function renderWho() {
  if (!ready()) return offline('whoBody');
  const amount = parseInt(P.amount, 10) || 0;
  el('whoTitle').textContent = P.flow === 'send' ? 'Send to' : 'Request from';
  el('whoAmount').textContent = money(amount);
  el('whoNumber').value = '';

  // saved payees come with the account data, on servers that have them
  const hasPayees = Array.isArray(P.data.payees);
  el('whoPayees').classList.toggle('hidden', !hasPayees);
  if (!hasPayees && P.who === 'payees') P.who = 'nearby';

  document.querySelectorAll('#whoSeg button').forEach(b =>
    b.classList.toggle('on', b.dataset.who === P.who));

  const box = el('whoBody');
  box.innerHTML = '<div class="skel"></div><div class="skel"></div><div class="skel"></div>';

  P.targets = await call('phone:targets', {});
  paintWho();
}

function paintWho() {
  const box = el('whoBody');
  const t = P.targets || {};
  const list = P.who === 'payees'
    ? (P.data.payees || []).slice()
        .sort((a, b) => String(b.last_used || '').localeCompare(String(a.last_used || ''), undefined, { numeric: true }))
        .map(p => ({ name: p.label, account: p.account_number }))
    : t[P.who] || [];

  if (!list.length) {
    const blank = {
      nearby: ['No one close by', 'Walk up to someone and they will appear here.'],
      recent: ['No one yet', 'People you send money to show up here afterwards.'],
      contacts: ['No contacts found', 'Save them in your phone first, or type the account number above.'],
      payees: ['No saved payees', 'Save one when you send money from the bank and it shows up here.']
    }[P.who];

    box.innerHTML = `<div class="empty">${I.none}<b>${blank[0]}</b><span>${blank[1]}</span></div>`;
    return;
  }

  box.innerHTML = list.map(p => `
    <button class="person" data-pick="${esc(p.account)}" data-name="${esc(p.name)}">
      <div class="avatar">${esc(initials(p.name))}</div>
      <div class="txt"><b>${esc(p.name)}</b>
        <span>${P.who === 'nearby' ? `${p.dist} m away` : esc(p.account)}</span></div>
      ${I.chev}
    </button>`).join('');
}

el('whoSeg').addEventListener('click', (e) => {
  const b = e.target.closest('[data-who]');
  if (!b) return;
  P.who = b.dataset.who;
  document.querySelectorAll('#whoSeg button').forEach(x =>
    x.classList.toggle('on', x === b));
  paintWho();
});

el('whoManualGo').addEventListener('click', () => {
  const number = el('whoNumber').value.trim();
  if (!number) return toast('Not completed', 'Type an account number first.', true);
  confirmPerson(number, number);
});

function confirmPerson(accountNumber, name) {
  const amount = parseInt(P.amount, 10) || 0;
  const d = P.data;
  const sending = P.flow === 'send';
  // offer to save someone new as a payee (they show up at ATMs too)
  const canSave = sending && Array.isArray(d.payees)
    && !d.payees.some(p => String(p.account_number).toUpperCase() === String(accountNumber).toUpperCase());

  openModal({
    title: `${sending ? 'Send' : 'Request'} ${money(amount)}`,
    text: sending
      ? (d.config.transferFee > 0
          ? `To ${name}. A ${(d.config.transferFee * 100).toFixed(1)}% fee applies.`
          : `To ${name}. Arrives instantly.`)
      : `${name} gets a bill they can pay from their own phone.`,
    confirm: sending ? 'Send' : 'Request',
    fields: `
      ${sending ? `<select data-name="from">
        ${(d.accounts || []).filter(a => a.can.transfer)
          .map(a => `<option value="${a.id}">${esc(a.label)} · ${money(a.balance)}</option>`).join('')}
      </select>` : ''}
      <input data-name="note" maxlength="40" placeholder="What for? (optional)">
      ${canSave ? `<input data-name="saveAs" maxlength="32"
        placeholder="Save as payee — their name (optional)" value="${name !== accountNumber ? esc(name) : ''}">` : ''}`,
    onConfirm: async (v) => {
      const res = sending
        ? await call('phone:transfer', {
            from: parseInt(v.from, 10), to: accountNumber, amount, note: v.note })
        : await call('phone:request', {
            to: accountNumber, amount, note: v.note });

      closeModal();
      if (!reply(res)) return;

      const saveAs = (v.saveAs || '').trim();
      if (canSave && saveAs) await call('phone:savePayee', { label: saveAs, number: accountNumber });

      P.amount = '';
      renderPay();
      await refresh();
      closePage();
      goTab('activity');
    }
  });
}

/* ═══════════════ INVESTING ═══════════════ */
function renderInvest() {
  if (!ready()) return offline('investBody');
  const m = P.data.market;
  if (!m || !m.assets || !m.assets.length) {
    el('investBody').innerHTML = `<div class="empty">${I.chart}<b>Market closed</b>
      <span>There is nothing to trade right now.</span></div>`;
    return;
  }

  const held = m.holdings || [];
  const up = (m.pl || 0) >= 0;

  const mine = held.length ? `
    <div class="port">
      <span>Portfolio</span>
      <b>${money(m.value)}</b>
      <em class="${up ? 'up' : 'down'}">
        ${up ? '+' : '−'}${money(Math.abs(m.pl || 0))}
        (${m.cost ? ((m.pl / m.cost) * 100).toFixed(2) : '0.00'}%)</em>
    </div>

    <h3 class="sec">Your investments</h3>
    ${held.map(h => {
      const a = m.assets.find(x => x.id === h.asset) || {};
      const good = (h.pl || 0) >= 0;
      return `<button class="asset-row" data-asset="${esc(h.asset)}">
        <div class="coin">${esc(String(h.label).slice(0, 1))}</div>
        <div class="txt"><b>${esc(h.label)}</b><span>${units(h.units)} units</span></div>
        <div class="right">
          <b>${money(h.value)}</b>
          <span class="${good ? 'up' : 'down'}">
            ${good ? '+' : '−'}${money(Math.abs(h.pl || 0))}</span>
        </div>
        ${I.chev}
      </button>`;
    }).join('')}` : `
    <div class="port">
      <span>Portfolio</span>
      <b>${money(0)}</b>
      <em>Nothing invested yet</em>
    </div>`;

  el('investBody').innerHTML = `
    ${mine}
    <h3 class="sec">Market</h3>
    ${m.assets.map(a => {
      const good = (a.change || 0) >= 0;
      const h = held.find(x => x.asset === a.id);
      return `<button class="asset-row" data-asset="${esc(a.id)}">
        <div class="coin">${esc(String(a.label).slice(0, 1))}</div>
        <div class="txt"><b>${esc(a.label)}</b>
          <span>${h ? `You hold ${money(h.value)}` : money(a.price)}</span></div>
        <div class="right">
          <b>${money(a.price)}</b>
          <span class="${good ? 'up' : 'down'}">
            ${good ? '↑' : '↓'} ${Math.abs(a.change || 0).toFixed(2)}%</span>
        </div>
        ${I.chev}
      </button>`;
    }).join('')}

    <p class="fine">Prices move every ${m.tick} minutes. A ${(m.fee * 100).toFixed(1)}%
      fee applies to each order, and the smallest one is ${money(m.minTrade)}.</p>`;
}

/* ═══════════════ ONE ASSET ═══════════════ */
function renderAsset() {
  if (!ready()) return offline('assetBody');
  const m = P.data.market;
  const a = (m.assets || []).find(x => x.id === P.asset);
  if (!a) return closePage();

  const h = (m.holdings || []).find(x => x.asset === P.asset);
  const up = (a.change || 0) >= 0;

  el('assetName').textContent = a.label;
  el('assetSell').disabled = !h;

  const position = h ? `
    <h3 class="sec">Your position</h3>
    <div class="grid2">
      <div><span>Value</span><b>${money(h.value)}</b></div>
      <div><span>Units held</span><b>${units(h.units)}</b></div>
      <div><span>Average price</span><b>${money(h.avgPrice)}</b></div>
      <div><span>Profit / loss</span>
        <b class="${(h.pl || 0) >= 0 ? 'up' : 'down'}">
          ${(h.pl || 0) >= 0 ? '+' : '−'}${money(Math.abs(h.pl || 0))}</b></div>
    </div>
    <p class="fine">You bought in at an average of ${money(h.avgPrice)} per unit.
      At ${money(a.price)} that position is ${(h.pl || 0) >= 0 ? 'up' : 'down'}
      ${money(Math.abs(h.pl || 0))}.</p>` : `
    <div class="empty small">${I.coin}<b>You hold none of this</b>
      <span>Buy in and your position shows up right here.</span></div>`;

  el('assetBody').innerHTML = `
    <div class="asset-head">
      <b class="price">${money(a.price)}</b>
      <span class="${up ? 'up' : 'down'}">
        ${up ? '↑' : '↓'} ${Math.abs(a.change || 0).toFixed(2)}% today</span>
    </div>
    ${bigChart(a.history, up)}
    <div class="pad">${position}</div>`;
}

function tradeModal(side) {
  const m = P.data.market;
  const a = (m.assets || []).find(x => x.id === P.asset);
  const h = (m.holdings || []).find(x => x.asset === P.asset);
  if (!a) return;

  const buying = side === 'buy';
  const spendable = (P.data.accounts || []).filter(a2 => a2.can.withdraw && a2.type !== 'society');

  openModal({
    title: `${buying ? 'Buy' : 'Sell'} ${a.label}`,
    text: buying
      ? `At ${money(a.price)} a unit. Smallest order is ${money(m.minTrade)}.`
      : `You hold ${money(h ? h.value : 0)}. Leave it empty to sell the lot.`,
    confirm: buying ? 'Buy' : 'Sell',
    fields: `
      <input data-name="amount" type="number" inputmode="numeric" min="0"
        placeholder="${buying ? money(m.minTrade).replace(/[^\d]/g, '') : 'All of it'}">
      <select data-name="account">
        ${spendable.map(x => `<option value="${x.id}">${esc(x.label)} · ${money(x.balance)}</option>`).join('')}
      </select>`,
    onConfirm: async (v) => {
      // an empty sell field means the whole position; anything typed has to be above zero
      const typed = String(v.amount || '').trim() !== '';
      const amount = parseInt(v.amount, 10) || 0;
      if (buying && amount < m.minTrade) {
        return toast('Not completed', `The smallest order is ${money(m.minTrade)}.`, true);
      }
      if (!buying && typed && !(amount > 0)) {
        return toast('Not completed', 'Enter an amount above zero, or leave it empty to sell it all.', true);
      }
      if (!buying && typed && amount > Math.ceil(h ? h.value : 0)) {
        return toast('Not completed', `You only hold ${money(h ? h.value : 0)}. Leave it empty to sell it all.`, true);
      }

      const res = await call('phone:trade', {
        side, asset: P.asset, amount, account: parseInt(v.account, 10)
      });

      closeModal();
      if (reply(res)) { await refresh(); renderAsset(); }
    }
  });
}

el('assetBuy').addEventListener('click', () => tradeModal('buy'));
el('assetSell').addEventListener('click', () => tradeModal('sell'));

/* ═══════════════ BORROW ═══════════════ */
function renderBorrow() {
  if (!ready()) return offline('borrowBody');
  const d = P.data;
  const loan = d.loans && d.loans.active && d.loans.active[0];
  const box = el('borrowBody');

  if (d.loans && d.loans.defaulted) {
    box.innerHTML = `<div class="empty">${I.coin}<b>You are in default</b>
      <span>${money(d.loans.defaultedOwed)} outstanding. Settle it at a branch
      before you can borrow again.</span></div>`;
    return;
  }

  if (loan) {
    const paid = loan.totalOwed - loan.remaining;
    const pct = Math.min(100, Math.round((paid / Math.max(1, loan.totalOwed)) * 100));
    const soon = loan.nextIn <= 10;

    box.innerHTML = `
      <div class="port">
        <span>Still owed</span>
        <b>${money(loan.remaining)}</b>
        <em>of ${money(loan.totalOwed)} borrowed at ${(loan.interest * 100).toFixed(0)}%</em>
      </div>
      <div class="meter big"><i style="width:${pct}%"></i></div>

      <div class="due-card ${soon ? 'soon' : ''}">
        ${I.clock}
        <div><b>${money(loan.payment)} due in ${countdown(loan.nextIn)}</b>
          <span>${loan.missed > 0
            ? `${loan.missed} payment${loan.missed > 1 ? 's' : ''} missed already`
            : 'Paying on time builds your credit'}</span></div>
      </div>

      <div class="grid2">
        <div><span>Instalment</span><b>${money(loan.payment)}</b></div>
        <div><span>Payments left</span><b>${loan.daysLeft}</b></div>
        <div><span>Term</span><b>${loan.termDays} days</b></div>
        <div><span>Credit score</span><b>${d.credit.score}</b></div>
      </div>

      <div class="pair">
        <button class="pill" data-borrow="off" data-id="${loan.id}">Pay it off</button>
        <button class="pill solid" data-borrow="pay" data-id="${loan.id}">Pay ${money(loan.payment)}</button>
      </div>

      <p class="fine">Miss too many instalments and the loan defaults, which costs you
        credit and locks borrowing until it is settled.</p>`;
    return;
  }

  const tiers = d.config.loanTiers || [];
  box.innerHTML = `
    <div class="port">
      <span>Credit score</span>
      <b>${d.credit.score}</b>
      <em>${esc(d.credit.band)} · ${d.credit.onTime} on time, ${d.credit.late} late</em>
    </div>

    <h3 class="sec">What you can borrow</h3>
    ${tiers.map(t => {
      const can = d.credit.score >= t.minCredit;
      return `<button class="tier ${can ? '' : 'locked'}" ${can ? `data-tier="${esc(t.id)}"` : ''}>
        <div class="txt">
          <b>${esc(t.label)}</b>
          <span>${can
            ? `${money(t.payment)} every instalment · ${t.termDays} days`
            : `Needs a credit score of ${t.minCredit}`}</span>
        </div>
        <div class="right">
          <b>${money(t.amount)}</b>
          <span>${(t.interest * 100).toFixed(0)}% interest</span>
        </div>
      </button>`;
    }).join('')}

    <p class="fine">One loan at a time. The money lands in your account straight away,
      and instalments come out on a clock — pay them on time and your credit climbs.</p>`;
}

/* ═══════════════ ACTIVITY ═══════════════ */
function entry(t) {
  const isIn = t.direction === 'in';
  return `<div class="entry">
    <div class="ava ${isIn ? '' : 'neutral'}">${I[CAT[t.category] || (isIn ? 'in' : 'out')]}</div>
    <div class="txt"><b>${esc(t.label)}</b><span>${esc(t.stamp)}</span></div>
    <div class="amt ${isIn ? 'in' : ''}">${isIn ? '+' : '−'}${money(t.amount)}</div>
  </div>`;
}

async function loadActivity() {
  if (!ready()) return offline('activityBody');
  const box = el('activityBody');
  box.innerHTML = '<div class="group"><div class="skel"></div><div class="skel"></div><div class="skel"></div></div>';

  const res = await call('phone:transactions', { account: P.data.primary, page: 1 });
  const d = P.data;
  const out = [];
  const upcoming = [];

  (d.bills.rows || []).forEach(b => {
    upcoming.push(`<div class="entry">
      <div class="ava ${b.status === 'overdue' ? 'bad' : ''}">${I.bill}</div>
      <div class="txt"><b>${esc(b.issuer_label)}</b>
        <span>${esc(b.reason)} · ${b.status === 'overdue' ? 'Overdue' : countdown(b.dueIn) + ' left'}</span></div>
      <button class="go" data-bill="${b.id}">Pay</button>
    </div>`);
  });

  const loan = d.loans && d.loans.active && d.loans.active[0];
  if (loan) {
    upcoming.push(`<div class="entry">
      <div class="ava ${loan.nextIn <= 10 ? 'bad' : ''}">${I.repay}</div>
      <div class="txt"><b>Repayment</b>
        <span>${money(loan.payment)} · due in ${countdown(loan.nextIn)}</span></div>
      <button class="go" data-loan="${loan.id}">Pay</button>
    </div>`);
  }

  if (upcoming.length) {
    out.push(`<div class="group"><h3>Upcoming</h3>${upcoming.join('')}</div>`);
  }

  const rows = (res && res.rows) || [];
  if (rows.length) {
    out.push(`<div class="group"><h3>Recent</h3>${rows.map(entry).join('')}</div>`);
  } else if (!upcoming.length) {
    out.push(`<div class="empty">${I.none}<b>Nothing yet</b>
      <span>Money moving through your account shows up here.</span></div>`);
  }

  box.innerHTML = out.join('');
}

/* ═══════════════ SUB PAGES ═══════════════ */
function renderAccounts() {
  if (!ready()) return offline('accountsBody');
  el('accountsBody').innerHTML = (P.data.accounts || []).map(a => `
    <div class="list-row">
      ${a.type === 'savings' ? I.bag : I.bank}
      <div class="txt"><b>${esc(a.label)}</b><span>${esc(a.number)}</span></div>
      <div class="val">${money(a.balance)}</div>
    </div>`).join('') + `
    <p class="fine">Cash in and out happens at an ATM or a branch. Moving money
      between accounts and people works from here.</p>`;
}

function renderCards() {
  if (!ready()) return offline('cardsBody');
  const cards = (P.data.cards || []).filter(c => {
    const a = account(c.account);
    return a && a.type !== 'savings';
  });

  if (!cards.length) {
    el('cardsBody').innerHTML = `<div class="empty">${I.card}<b>No cards yet</b>
      <span>Order one at any branch to use ATMs and pay by terminal.</span></div>`;
    return;
  }

  el('cardsBody').innerHTML = cards.map(c => {
    const acc = account(c.account) || { label: '' };
    const flag = c.joint ? 'MEMBER' : c.kind === 'secured' ? 'SECURED'
      : c.kind === 'credit' ? 'CREDIT' : c.express ? 'EXPRESS' : '';

    const detail = c.kind === 'debit'
      ? `<div class="list-row"><div class="txt"><b>Spend limit</b></div>
           <div class="val">${money(c.spent)} / ${money(c.limit)}</div></div>`
      : `<div class="list-row"><div class="txt"><b>Balance owed</b></div>
           <div class="val">${money(c.balance)}</div></div>
         <div class="list-row"><div class="txt"><b>Credit left</b></div>
           <div class="val">${money(c.available)}</div></div>
         ${c.minPay > 0 ? `<div class="list-row"><div class="txt"><b>Minimum due</b>
           <span>in ${countdown(c.dueIn)}</span></div>
           <div class="val">${money(c.minPay)}</div></div>` : ''}`;

    return `
      <div class="bcard ${c.skin} ${c.status !== 'active' ? 'frozen' : ''}">
        <div class="glare"></div>
        <div class="row"><div class="emv"></div>
          ${flag ? `<span class="flag">${flag}</span>` : ''}</div>
        <div class="num">${esc(c.number)}</div>
        <div class="row foot">
          <div><span>ACCOUNT NAME</span><b>${esc(c.holder)}</b></div>
          <div style="text-align:right"><span>EXPIRES</span><b>${esc(c.expires)}</b></div>
        </div>
      </div>

      <div class="list-row"><div class="txt"><b>Linked account</b></div>
        <div class="val">${esc(acc.label)}</div></div>
      <div class="list-row"><div class="txt"><b>Status</b></div>
        <div class="val">${c.status === 'active' ? 'Active' : c.status === 'stolen' ? 'Reported' : 'Frozen'}</div></div>
      ${detail}

      <div class="pair">
        ${c.status === 'active'
          ? `<button class="pill" data-card="block" data-id="${c.id}">Freeze</button>`
          : c.status === 'blocked'
            ? `<button class="pill solid" data-card="unblock" data-id="${c.id}">Unfreeze</button>`
            : `<button class="pill" data-card="replace" data-id="${c.id}">Replacement</button>`}
        <button class="pill" data-card="report" data-id="${c.id}">Report lost</button>
      </div>`;
  }).join('');
}

function renderBills() {
  if (!ready()) return offline('billsBody');
  const b = P.data.bills;

  if (!b.rows.length) {
    el('billsBody').innerHTML = `<div class="empty">${I.bill}<b>Nothing owed</b>
      <span>Invoices, and money other people ask you for, land here.</span></div>`;
    return;
  }

  el('billsBody').innerHTML = b.rows.map(x => `
    <div class="entry">
      <div class="ava ${x.status === 'overdue' ? 'bad' : ''}">${I.bill}</div>
      <div class="txt"><b>${esc(x.reason)}</b>
        <span>${esc(x.issuer_label)} · ${x.status === 'overdue'
          ? 'Overdue' : countdown(x.dueIn) + ' left'}</span></div>
      <button class="go" data-bill="${x.id}">${money(x.amount)}</button>
    </div>`).join('');
}

function renderSettings() {
  if (!ready()) return offline('settingsBody');
  const d = P.data;
  const primary = account(d.primary) || { number: '' };

  el('settingsBody').innerHTML = `
    <div style="display:flex;flex-direction:column;align-items:flex-start;gap:12px;padding:8px 0 26px">
      <div class="avatar" style="width:68px;height:68px;font-size:24px">${esc(initials(d.player.name))}</div>
      <b style="font-size:30px;font-weight:700;letter-spacing:-.03em">${esc(d.player.name)}</b>
      <span style="font-size:14px;color:var(--ink-3)">${esc(primary.number)}</span>
    </div>

    <div class="list-row">${I.bank}<div class="txt"><b>Credit score</b>
      <span>${esc(d.credit.band)}</span></div><div class="val">${d.credit.score}</div></div>
    <div class="list-row">${I.card}<div class="txt"><b>Cards</b></div>
      <div class="val">${(d.cards || []).length}</div></div>
    <div class="list-row">${I.bag}<div class="txt"><b>Savings</b></div>
      <div class="val">${d.savings.open ? money(d.savings.balance) : 'Not open'}</div></div>
    <div class="list-row">${I.chart}<div class="txt"><b>Invested</b></div>
      <div class="val">${money((d.market && d.market.value) || 0)}</div></div>
    <div class="list-row">${I.bill}<div class="txt"><b>Unpaid bills</b></div>
      <div class="val">${d.bills.count || 0}</div></div>
    ${d.config.features.statements ? `<button class="list-row wide" data-go="statement">
      ${I.book}<div class="txt"><b>Statements</b>
        <span>What came in and went out</span></div>${I.chev}</button>` : ''}

    ${d.overdraft && d.overdraft.optIn ? `
      <h3 style="font-size:22px;font-weight:700;margin:30px 0 4px">Overdraft</h3>
      <div class="list-row">
        <div class="txt"><b>Overdraft protection</b>
          <span>${d.overdraft.on
            ? `Up to ${money(d.overdraft.limit)}${d.overdraft.savings ? ', savings used first' : ''}`
            : `A ${money(d.overdraft.fee)} fee applies when you use it`}</span></div>
        <button class="pill ${d.overdraft.on ? 'solid' : ''}"
          style="flex:none;height:38px;padding:0 20px;font-size:13.5px"
          data-overdraft="${d.overdraft.on ? 'off' : 'on'}">${d.overdraft.on ? 'On' : 'Off'}</button>
      </div>
      ${d.overdraft.used > 0 ? `<p class="fine">You are ${money(d.overdraft.used)} overdrawn.
        Interest of ${(d.overdraft.rate * 100).toFixed(1)}% is charged on what you owe
        every ${d.overdraft.rateEvery} minutes once the grace period ends.</p>` : ''}` : ''}

    <h3 style="font-size:22px;font-weight:700;margin:30px 0 4px">Automation</h3>
    ${toggleRow('directDeposit', 'Paycheck into the bank', d.settings.directDeposit)}
    ${toggleRow('autoPayBills', 'Pay bills automatically', d.settings.autoPayBills)}
    ${toggleRow('autoPayLoans', 'Pay loan instalments automatically', d.settings.autoPayLoans)}
    <button class="pill solid" style="width:100%;margin-top:20px" id="saveSettings">Save</button>`;
}

function toggleRow(key, label, on) {
  return `<div class="list-row">
    <div class="txt"><b>${esc(label)}</b></div>
    <button class="pill ${on ? 'solid' : ''}" style="flex:none;height:38px;padding:0 20px;font-size:13.5px"
      data-toggle="${key}">${on ? 'On' : 'Off'}</button>
  </div>`;
}

/* ═══════════════ STATEMENT ═══════════════ */
async function renderStatement() {
  if (!ready()) return offline('statementBody');
  const box = el('statementBody');
  box.innerHTML = '<div class="skel"></div><div class="skel"></div><div class="skel"></div>';

  document.querySelectorAll('#stSeg button').forEach(b =>
    b.classList.toggle('on', b.dataset.period === P.period));

  const res = await call('phone:statement', {
    account: P.data.primary, period: P.period
  });

  if (!res || !res.ok) {
    box.innerHTML = `<div class="empty">${I.book}<b>No statement</b>
      <span>${esc((res && res.msg) || 'Nothing to show for this period.')}</span></div>`;
    return;
  }

  const st = res.statement;
  const net = st.net >= 0;

  box.innerHTML = `
    <div class="port">
      <span>${esc(st.account.label)} · ${esc(st.account.number)}</span>
      <b>${money(st.closing)}</b>
      <em>opened the period at ${money(st.opening)}</em>
    </div>

    <div class="grid2">
      <div><span>Paid in</span><b class="up">${money(st.income)}</b></div>
      <div><span>Paid out</span><b class="down">${money(st.spending)}</b></div>
      <div><span>Net</span><b class="${net ? 'up' : 'down'}">
        ${net ? '+' : '−'}${money(Math.abs(st.net))}</b></div>
      <div><span>Lines</span><b>${st.count}</b></div>
    </div>

    ${st.breakdown.length ? `<h3 class="sec">Where it went</h3>
      ${st.breakdown.map(b => `
        <div class="list-row">
          <div class="txt"><b>${esc(b.label)}</b><span>${b.count} ${b.count === 1 ? 'entry' : 'entries'}</span></div>
          <div class="val ${b.direction === 'in' ? 'up' : 'down'}">
            ${b.direction === 'in' ? '+' : '−'}${money(b.amount)}</div>
        </div>`).join('')}` : ''}

    <h3 class="sec">Every line</h3>
    ${st.rows.slice().reverse().map(r => `
      <div class="entry">
        <div class="ava ${r.direction === 'in' ? '' : 'neutral'}">
          ${I[CAT[r.category] || (r.direction === 'in' ? 'in' : 'out')]}</div>
        <div class="txt"><b>${esc(r.label)}</b><span>${esc(r.stamp)}</span></div>
        <div class="amt ${r.direction === 'in' ? 'in' : ''}">
          ${r.direction === 'in' ? '+' : '−'}${money(r.amount)}</div>
      </div>`).join('')}

    <p class="fine">Issued ${esc(st.issued)}.${st.truncated
      ? ' Only the most recent lines are shown.' : ''}${st.fee
      ? ` A ${money(st.fee)} fee was charged for this statement.` : ''}</p>`;
}

/* ═══════════════ EVENTS ═══════════════ */
document.addEventListener('click', async (e) => {
  const tabBtn = e.target.closest('[data-tab-go]');
  if (tabBtn) return goTab(tabBtn.dataset.tabGo);

  if (e.target.closest('[data-back]')) return closePage();

  const nav = e.target.closest('[data-go]');
  if (nav) {
    const where = nav.dataset.go;
    if (where === 'send' || where === 'request') {
      P.flow = where;
      return goTab('pay');
    }
    return openPage(where);
  }

  // an asset's own page
  const assetBtn = e.target.closest('[data-asset]');
  if (assetBtn) {
    P.asset = assetBtn.dataset.asset;
    return openPage('asset');
  }

  // picking somebody to pay
  const pick = e.target.closest('[data-pick]');
  if (pick) return confirmPerson(pick.dataset.pick, pick.dataset.name);

  // taking a loan
  const tier = e.target.closest('[data-tier]');
  if (tier && !P.busy) {
    const t = (P.data.config.loanTiers || []).find(x => x.id === tier.dataset.tier);
    if (!t) return;

    return openModal({
      title: `Borrow ${money(t.amount)}`,
      text: `${money(t.payment)} comes out every instalment over ${t.termDays} days, ` +
            `at ${(t.interest * 100).toFixed(0)}% interest. Miss too many and it defaults.`,
      confirm: 'Take it',
      onConfirm: async () => {
        P.busy = true;
        const res = await call('phone:requestLoan', { tier: t.id });
        P.busy = false;
        closeModal();
        if (reply(res)) { await refresh(); renderBorrow(); }
      }
    });
  }

  // repaying
  const borrowBtn = e.target.closest('[data-borrow]');
  if (borrowBtn && !P.busy) {
    const id = parseInt(borrowBtn.dataset.id, 10);
    const off = borrowBtn.dataset.borrow === 'off';

    P.busy = true;
    borrowBtn.disabled = true;
    const res = off
      ? await call('phone:payOffLoan', { loan: id })
      : await call('phone:payLoan', { loan: id });
    P.busy = false;

    if (reply(res)) { await refresh(); renderBorrow(); }
    else borrowBtn.disabled = false;
    return;
  }

  // card actions
  const cardBtn = e.target.closest('[data-card]');
  if (cardBtn && !P.busy) {
    P.busy = true;
    const action = cardBtn.dataset.card;
    const id = parseInt(cardBtn.dataset.id, 10);

    const res = action === 'report'
      ? await call('phone:reportCard', { card: id })
      : await call('phone:updateCard', { card: id, action });

    P.busy = false;
    if (reply(res)) { await refresh(); renderCards(); }
    return;
  }

  // bills
  const billBtn = e.target.closest('[data-bill]');
  if (billBtn && !P.busy) {
    P.busy = true;
    const res = await call('phone:payBill', {
      bill: parseInt(billBtn.dataset.bill, 10),
      account: P.data.primary
    });
    P.busy = false;
    if (reply(res)) { await refresh(); renderBills(); loadActivity(); }
    return;
  }

  // loan instalment from the activity list
  const loanBtn = e.target.closest('[data-loan]');
  if (loanBtn && !P.busy) {
    P.busy = true;
    loanBtn.disabled = true;
    const res = await call('phone:payLoan', { loan: parseInt(loanBtn.dataset.loan, 10) });
    P.busy = false;
    if (reply(res)) { await refresh(); loadActivity(); }
    else loanBtn.disabled = false;
    return;
  }

  // overdraft opt-in — a server call, not a local toggle
  const odBtn = e.target.closest('[data-overdraft]');
  if (odBtn && !P.busy) {
    P.busy = true;
    odBtn.disabled = true;
    const res = await call('phone:setOverdraft', { on: odBtn.dataset.overdraft === 'on' });
    P.busy = false;
    if (reply(res)) { await refresh(); renderSettings(); }
    else odBtn.disabled = false;
    return;
  }

  // settings toggles
  const tog = e.target.closest('[data-toggle]');
  if (tog) {
    const key = tog.dataset.toggle;
    P.data.settings[key] = !P.data.settings[key];
    tog.textContent = P.data.settings[key] ? 'On' : 'Off';
    tog.classList.toggle('solid', P.data.settings[key]);
    return;
  }

  if (e.target.closest('#saveSettings')) {
    const res = await call('phone:saveSettings', P.data.settings);
    reply(res);
  }
});

el('stSeg').addEventListener('click', (e) => {
  const b = e.target.closest('[data-period]');
  if (!b) return;
  P.period = b.dataset.period;
  renderStatement();
});

el('whoNumber').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') el('whoManualGo').click();
});

el('hideBalance').addEventListener('click', () => {
  P.hidden = !P.hidden;
  renderMoney();
});

/* ═══════════════ BOOT ═══════════════ */
async function refresh() {
  const data = await call('phone:getData', {});

  // A payload without a player means the server could not build one.
  // Keep whatever we already had rather than blanking the screen, and
  // let the caller decide what to tell them.
  if (!data || !data.player) return false;

  P.data = data;
  P.currency = data.config.currency || '$';
  P.currencyRight = !!data.config.currencyRight;

  applyTheme(data.config.ui);
  renderMoney();
  renderPay();
  return true;
}

async function boot() {
  const ok = await refresh();

  setTimeout(() => {
    const s = el('splash');
    s.classList.add('out');
    setTimeout(() => s.classList.remove('up', 'out'), 320);
  }, 620);

  goTab('money');

  if (!ok) {
    offline('moneyStack', 'The bank could not load your account. ' +
      'If this keeps happening, the server console will say why.');
    toast('Banking', 'Could not reach your account.', true);
  }
}

/** Fetch again and redraw whatever is on screen. */
function pull() {
  refresh().then(() => {
    if (P.page && RENDER[P.page] && P.page !== 'who') RENDER[P.page]();
    if (P.tab === 'activity') loadActivity();
  });
}

window.addEventListener('message', (e) => {
  const m = e.data || {};
  // lb-phone forwards our refresh push; qs-smartphone-pro posts
  // 'app-opened' each time the app is brought to the front
  if (m.action === 'refresh' || m.type === 'refresh') return pull();
  if (PHONE === 'qs' && m === 'app-opened') return pull();
});

// phones with no documented push: catch up whenever the app is shown again
document.addEventListener('visibilitychange', () => {
  if (PHONE !== 'lb' && document.visibilityState === 'visible') pull();
});

boot();
