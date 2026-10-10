/* 19 · TELLER
   SendNUIMessage({ action = 'open', data = {
     bank = 'Fleeca', location = 'Legion Square',
     cards = { { id = 'card_1', label = 'Fleeca debit', last4 = '4021', holder = 'Jamie Reyes' } },
     balance = 48250, cash = 1340 } })
   SendNUIMessage({ action = 'result', data = { ok = true, balance = 47750, cash = 1840 } })
       -- optional: reply to the request in flight (if your callback answers later),
       -- or push new balance / cash at any time while the machine is open
       -- ok = false, error = 'Daily limit reached' declines the request in flight
   SendNUIMessage({ action = 'close' })

   Callbacks (the machine waits for the callback's return value):
     pin      { card, pin }           → cb({ ok = true })  or  cb({ ok = false, attempts = 2 })
                                         attempts = tries left; 0 (or retained = true) keeps the card
     withdraw { card, amount }         → cb({ ok, error, balance, cash })
     deposit  { card, amount }         → cb({ ok, error, balance, cash })
     transfer { card, target, amount } → cb({ ok, error, balance, cash })   -- target = account / state id string
     close                             -- player walked away (ESC) or finished; release focus

   RegisterNUICallback('withdraw', function(d, cb)
     local res = lib.callback.await('bank:withdraw', false, d.card, d.amount) -- your server logic
     cb(res) -- { ok = true, balance = 47750, cash = 1840 } | { ok = false, error = 'Insufficient funds' }
   end)
   Preview PIN is 1234.
*/
const app = NZ.$('#app');
const MAX_PIN_TRIES = 3;
let cfg = null;          // open payload
let st = {};             // machine state
let busy = false;        // keypad locked while processing
let pending = null;      // resolver for the request in flight
let timers = [];

const later = (fn, ms) => { const t = setTimeout(fn, ms); timers.push(t); return t; };
const wait = ms => new Promise(r => later(r, ms));
const money = n => NZ.money(n || 0);
const card = () => cfg.cards.find(c => c.id === st.card);
const firstName = h => String(h || '').split(/\s+/)[0] || 'there';

/* ── fit the fixed-size machine into any resolution ── */
function fit() {
  const k = Math.min(1, (innerHeight - 28) / 930, (innerWidth - 28) / 780);
  app.style.setProperty('--k', k.toFixed(4));
}
addEventListener('resize', fit);

function tick() {
  const d = new Date();
  NZ.$('#clock').textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}
setInterval(tick, 10000);

/* ═════════ views ═════════
   each view returns { html, soft: { L1..R4: { label, sub, act, tone } }, digit, clear, enter, cancel } */
const VIEWS = {
  insert() {
    const list = cfg.cards.slice(st.page * 3, st.page * 3 + 3);
    const soft = { L4: { label: 'Exit', act: () => NZ.close(app), tone: 'danger' } };
    list.forEach((c, i) => {
      soft['R' + (i + 1)] = { label: c.label, sub: `•••• ${c.last4}  ·  ${c.holder}`, act: () => insertCard(c) };
    });
    if (cfg.cards.length > 3) soft.R4 = { label: 'More cards', sub: `Page ${st.page + 1} of ${Math.ceil(cfg.cards.length / 3)}`, act: () => { st.page = (st.page + 1) % Math.ceil(cfg.cards.length / 3); show('insert'); } };
    const html = `<div class="v-half">
      <div class="v-kicker">Welcome</div>
      <div class="v-title">Insert your card to begin</div>
      <div class="v-text">${cfg.cards.length ? `Choose a card with the side keys${list.length > 1 ? ` or press 1–${list.length}` : ''}.` : `No bank cards found. Visit a ${NZ.esc(cfg.bank)} branch to open an account.`}</div>
      <div class="insert-art"><i class="slotline"></i><i class="cardi"></i></div>
    </div>`;
    return {
      html, soft,
      digit: d => { const c = list[+d - 1]; if (c) insertCard(c); },
      cancel: () => NZ.close(app),
    };
  },

  pin() {
    const c = card();
    const left = st.tries[c.id] ?? MAX_PIN_TRIES;
    const dots = [0, 1, 2, 3].map(i => `<i class="${i < st.pin.length ? 'on' : ''}"></i>`).join('');
    const html = `<div class="v-center">
      <div class="v-kicker">Security check</div>
      <div class="v-title">Enter your PIN</div>
      <div class="pin-dots ${st.shake ? 'shake' : ''}">${dots}</div>
      <div class="v-msg ${st.err ? 'err' : left < MAX_PIN_TRIES ? 'warn' : ''}">${st.err ? NZ.esc(st.err) : left < MAX_PIN_TRIES ? `${left} attempt${left === 1 ? '' : 's'} left before the card is retained` : 'Four digits · shield the keypad'}</div>
      <div class="card-chip">${NZ.icon('card')}${NZ.esc(c.label)} · •••• ${NZ.esc(c.last4)}</div>
    </div>`;
    st.shake = false;
    return {
      html,
      soft: {
        L4: { label: 'Cancel', act: ejectToStart, tone: 'danger' },
        R4: { label: 'Confirm', act: submitPin, tone: st.pin.length === 4 ? 'prime' : 'off' },
      },
      digit: d => { if (st.pin.length < 4) { st.pin = (st.pin + d).slice(0, 4); st.err = ''; show('pin', true); } },
      clear: () => { st.pin = st.pin.slice(0, -1); show('pin', true); },
      enter: submitPin,
      cancel: ejectToStart,
    };
  },

  retained() {
    const c = card();
    return {
      html: `<div class="v-center">
        <div class="res-ic red">${NZ.icon('lock')}</div>
        <div class="v-title">Card retained</div>
        <div class="v-text">Too many incorrect PIN attempts. For your security the card ending ${NZ.esc(c ? c.last4 : '')} has been kept by this machine. Visit a ${NZ.esc(cfg.bank)} branch to collect it.</div>
      </div>`,
      soft: { R4: { label: 'Continue', act: retainDone } },
      enter: retainDone, cancel: retainDone,
    };
  },

  menu() {
    const c = card();
    const fast = n => () => request('withdraw', n);
    return {
      html: `<div class="menu-core"><div class="nz-mark"></div>
        <p>Hello, <b>${NZ.esc(firstName(c.holder))}</b><br>Choose a service</p></div>`,
      soft: {
        L1: { label: money(100), sub: 'Fast cash', act: fast(100) },
        L2: { label: money(500), sub: 'Fast cash', act: fast(500) },
        L3: { label: money(1000), sub: 'Fast cash', act: fast(1000) },
        L4: { label: 'Transfer', sub: 'To another account', act: () => { st.target = ''; st.err = ''; show('target'); } },
        R1: { label: 'Withdraw', sub: 'Choose an amount', act: () => amountFor('withdraw') },
        R2: { label: 'Deposit', sub: 'Cash into account', act: () => amountFor('deposit') },
        R3: { label: 'Balance', sub: 'View on screen', act: () => show('balance') },
        R4: { label: 'Finish', sub: 'Return my card', act: finish, tone: 'danger' },
      },
      cancel: finish,
    };
  },

  amount() {
    const m = st.mode;
    const titles = { withdraw: 'How much would you like to withdraw?', deposit: 'How much are you depositing?', transfer: 'How much would you like to send?' };
    const html = `<div class="v-center v-top">
      <div class="v-kicker">${m === 'withdraw' ? 'Withdraw' : m === 'deposit' ? 'Deposit' : `Transfer to ${NZ.esc(fmtAcct(st.target))}`}</div>
      <div class="v-title">${titles[m]}</div>
      <div class="amt"><small>$</small>${st.amount ? Number(st.amount).toLocaleString('en-US') : '<span class="ph">0</span>'}<i class="caret"></i></div>
      <div class="meta">
        <div>Available balance<b>${money(cfg.balance)}</b></div>
        <div>Cash on hand<b>${money(cfg.cash)}</b></div>
      </div>
      <div class="v-msg ${st.err ? 'err' : ''}">${st.err ? NZ.esc(st.err) : 'Type an amount on the keypad'}</div>
    </div>`;
    const back = () => (m === 'transfer' ? show('target') : show('menu'));
    return {
      html,
      soft: {
        L4: { label: 'Back', act: back },
        R4: { label: 'Confirm', act: confirmAmount, tone: st.amount ? 'prime' : 'off' },
      },
      digit: d => { if ((st.amount + d).replace(/^0+/, '').length <= 7) { st.amount = (st.amount + d).replace(/^0+/, ''); st.err = ''; show('amount', true); } },
      clear: () => { st.amount = st.amount.slice(0, -1); show('amount', true); },
      enter: confirmAmount,
      cancel: back,
    };
  },

  target() {
    const html = `<div class="v-center v-top">
      <div class="v-kicker">Transfer · step 1 of 2</div>
      <div class="v-title">Recipient account number</div>
      <div class="amt acct">${st.target ? NZ.esc(fmtAcct(st.target)) : '<span class="ph">0000 0000</span>'}<i class="caret"></i></div>
      <div class="v-msg ${st.err ? 'err' : ''}">${st.err ? NZ.esc(st.err) : 'Enter the account number or state ID of the recipient'}</div>
    </div>`;
    const next = () => {
      if (st.target.length < 3) { st.err = 'Account numbers have at least 3 digits'; return show('target', true); }
      st.mode = 'transfer'; st.amount = ''; st.err = ''; show('amount');
    };
    return {
      html,
      soft: {
        L4: { label: 'Back', act: () => show('menu') },
        R4: { label: 'Next', act: next, tone: st.target.length >= 3 ? 'prime' : 'off' },
      },
      digit: d => { if (st.target.length < 10) { st.target = (st.target + d).slice(0, 10); st.err = ''; show('target', true); } },
      clear: () => { st.target = st.target.slice(0, -1); show('target', true); },
      enter: next,
      cancel: () => show('menu'),
    };
  },

  processing() {
    return {
      html: `<div class="v-center">
        <div class="spin"><div class="nz-mark"></div></div>
        <div class="v-title">${NZ.esc(st.busyLabel || 'Processing your request')}</div>
        <div class="v-text">Please wait, do not remove your card.</div>
        <div class="bars"><i></i><i></i><i></i><i></i><i></i></div>
      </div>`,
      soft: {},
    };
  },

  done() {
    const t = st.txn;
    const heads = { withdraw: 'Please take your cash', deposit: 'Deposit accepted', transfer: 'Transfer sent' };
    const text = { withdraw: `${money(t.amount)} has been dispensed below the keypad.`, deposit: `${money(t.amount)} was added to your account.`, transfer: `${money(t.amount)} was sent to account ${NZ.esc(fmtAcct(t.target))}.` };
    return {
      html: `<div class="v-center v-top">
        <div class="res-ic">${NZ.icon('check')}</div>
        <div class="v-title">${heads[t.type]}</div>
        <div class="v-text">${text[t.type]}</div>
        <div class="res-row">
          <div>Amount<b class="t">${money(t.amount)}</b></div>
          <div>New balance<b>${money(cfg.balance)}</b></div>
        </div>
      </div>`,
      soft: {
        R3: { label: 'Print receipt', sub: 'Yes please', act: () => { printReceipt(t); show('after'); }, tone: 'prime' },
        R4: { label: 'No receipt', act: () => show('after') },
      },
      enter: () => { printReceipt(t); show('after'); },
      cancel: () => show('after'),
    };
  },

  after() {
    return {
      html: `<div class="v-center v-top">
        <div class="v-kicker">${st.printed ? 'Your receipt is printing' : 'Thank you'}</div>
        <div class="v-title">Anything else today?</div>
        <div class="v-text">Start another transaction without entering your PIN again.</div>
      </div>`,
      soft: {
        R3: { label: 'Another transaction', act: () => show('menu'), tone: 'prime' },
        R4: { label: 'Finish', sub: 'Return my card', act: finish, tone: 'danger' },
      },
      enter: () => show('menu'),
      cancel: finish,
    };
  },

  balance() {
    const c = card();
    const bal = { type: 'balance', amount: 0 };
    return {
      html: `<div class="v-center">
        <div class="v-kicker">${NZ.esc(c.label)} · •••• ${NZ.esc(c.last4)}</div>
        <div class="bal">${money(cfg.balance)}</div>
        <div class="v-text">Available balance</div>
        <div class="res-row"><div>Cash on hand<b>${money(cfg.cash)}</b></div><div>Account holder<b>${NZ.esc(c.holder)}</b></div></div>
      </div>`,
      soft: {
        L4: { label: 'Back', act: () => show('menu') },
        R3: { label: 'Print balance', act: () => printReceipt(bal) },
        R4: { label: 'Finish', sub: 'Return my card', act: finish, tone: 'danger' },
      },
      enter: () => show('menu'),
      cancel: () => show('menu'),
    };
  },

  declined() {
    return {
      html: `<div class="v-center">
        <div class="res-ic ${st.declineTone || 'red'}">${NZ.icon(st.declineTone === 'amber' ? 'alert' : 'x')}</div>
        <div class="v-title">Transaction declined</div>
        <div class="v-text">${NZ.esc(st.err || 'The bank could not complete this request.')}</div>
      </div>`,
      soft: {
        L4: { label: 'Back to menu', act: () => { st.err = ''; show('menu'); } },
        R4: { label: 'Finish', sub: 'Return my card', act: finish, tone: 'danger' },
      },
      enter: () => { st.err = ''; show('menu'); },
      cancel: finish,
    };
  },

  bye() {
    return {
      html: `<div class="v-center">
        <div class="res-ic">${NZ.icon('card')}</div>
        <div class="v-title">Please take your card</div>
        <div class="v-text">Thank you for banking with ${NZ.esc(cfg.bank)}.</div>
      </div>`,
      soft: {},
    };
  },
};

let view = null;
function show(name, quiet) {
  st.view = name;
  view = VIEWS[name]();
  const el = NZ.$('#view');
  el.innerHTML = view.html;
  if (!quiet) { el.style.animation = 'none'; void el.offsetWidth; el.style.animation = ''; }
  else el.style.animation = 'none';
  renderSoft(quiet);
  NZ.$('#card-slot').classList.toggle('wait', name === 'insert');
}

function renderSoft(quiet) {
  const soft = view.soft || {};
  NZ.$('#slots').innerHTML = ['L1', 'L2', 'L3', 'L4', 'R1', 'R2', 'R3', 'R4'].map(s => {
    const o = soft[s];
    if (!o) return `<div class="slot ${s[0]}" data-slot="${s}"></div>`;
    return `<div class="slot ${s[0]} on ${o.tone || ''}" data-slot="${s}"><div ${quiet ? 'style="animation:none"' : ''}><b>${NZ.esc(o.label)}</b>${o.sub ? `<small>${NZ.esc(o.sub)}</small>` : ''}</div></div>`;
  }).join('');
  NZ.$$('.sk').forEach(b => b.classList.toggle('live', !!soft[b.dataset.slot] && soft[b.dataset.slot].tone !== 'off'));
  NZ.$$('#slots .slot.on').forEach(el => el.onclick = () => pressSoft(el.dataset.slot));
}

function pressSoft(slot) {
  if (busy) return;
  const o = view.soft && view.soft[slot];
  const lbl = NZ.$(`#slots [data-slot="${slot}"]`);
  const key = NZ.$(`.sk[data-slot="${slot}"]`);
  if (key) { key.classList.add('down'); setTimeout(() => key.classList.remove('down'), 140); }
  if (!o || o.tone === 'off') return;
  if (lbl) lbl.classList.add('flash');
  setTimeout(() => o.act(), 110);
}

/* ── keypad ── */
function press(k) {
  const el = NZ.$(`.k[data-k="${k}"]`);
  if (el) { el.classList.add('down'); setTimeout(() => el.classList.remove('down'), 130); }
  if (busy || !view) return;
  if (/^\d+$/.test(k)) { if (view.digit) k.split('').forEach(d => view.digit(d)); }
  else if (k === 'clear' && view.clear) view.clear();
  else if (k === 'enter' && view.enter) view.enter();
  else if (k === 'cancel' && view.cancel) view.cancel();
}
NZ.$$('.k[data-k]').forEach(b => b.onclick = () => press(b.dataset.k));
NZ.$$('.sk').forEach(b => b.onclick = () => pressSoft(b.dataset.slot));

window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const k = e.key;
  if (/^[0-9]$/.test(k)) press(k);
  else if (k === 'Backspace') press('clear');
  else if (k === 'Enter') press('enter');
  else if (k === 'Delete') press('cancel');
  else if (k === 'Escape') NZ.close(app);
  else return;
  e.preventDefault();
});

/* ── card slot ── */
function cardAnim(cls) {
  const mc = NZ.$('#mini-card');
  mc.className = 'mini-card ' + cls;
}
function insertCard(c) {
  st.card = c.id; st.pin = ''; st.err = '';
  NZ.$('#mini-last4').textContent = c.last4;
  cardAnim('insert');
  busy = true;
  NZ.$('#view').innerHTML = `<div class="v-center"><div class="spin"><div class="nz-mark"></div></div><div class="v-title">Reading card</div></div>`;
  NZ.$('#slots').innerHTML = '';
  NZ.$$('.sk').forEach(b => b.classList.remove('live'));
  NZ.$('#card-slot').classList.remove('wait');
  later(() => { busy = false; show('pin'); }, 900);
}
function ejectCard(then) {
  cardAnim('eject');
  later(() => cardAnim('out'), 700);
  later(() => { cardAnim('take'); if (then) then(); }, 2200);
}
function ejectToStart() {
  st.card = null; st.pin = '';
  ejectCard();
  st.page = 0; show('insert');
}
function retainDone() {
  cfg.cards = cfg.cards.filter(c => c.id !== st.card);
  st.card = null; st.page = 0;
  show('insert');
}
function finish() {
  busy = true;
  show('bye');
  ejectCard(() => later(() => { busy = false; NZ.close(app); }, 600));
}

/* ── requests: callback return value, or a later 'result' message ── */
function settle(r) { if (pending) { const p = pending; pending = null; p(r); } }
NZ.on('result', d => {
  d = d || {};
  if (typeof d.balance === 'number') cfg.balance = d.balance;
  if (typeof d.cash === 'number') cfg.cash = d.cash;
  if (pending) settle(d);
  else if (cfg && ['balance', 'amount', 'menu'].includes(st.view)) show(st.view, true);
});

async function call(name, payload) {
  const resp = new Promise(res => { pending = res; });
  const t = setTimeout(() => settle({ ok: false, error: 'The machine timed out. Please try again.' }), 15000);
  if (NZ.inGame) NZ.post(name, payload).then(v => { if (v && typeof v === 'object') settle(v); });
  else later(() => settle(simulate(name, payload)), 900 + Math.random() * 700);
  const [r] = await Promise.all([resp, wait(1100)]);
  clearTimeout(t);
  return r || { ok: false, error: 'No response from the bank.' };
}

async function submitPin() {
  if (busy || st.pin.length !== 4) return;
  const c = card();
  busy = true; st.busyLabel = 'Verifying PIN'; show('processing');
  const r = await call('pin', { card: c.id, pin: st.pin });
  busy = false;
  if (r.ok) { st.tries[c.id] = MAX_PIN_TRIES; show('menu'); return; }
  const left = typeof r.attempts === 'number' ? r.attempts : (st.tries[c.id] ?? MAX_PIN_TRIES) - 1;
  st.tries[c.id] = Math.max(0, left);
  st.pin = '';
  if (r.retained || left <= 0) { cardAnim(''); show('retained'); return; }
  st.err = r.error || `Incorrect PIN · ${left} attempt${left === 1 ? '' : 's'} left`;
  st.shake = true;
  show('pin');
}

function amountFor(mode) { st.mode = mode; st.amount = ''; st.err = ''; show('amount'); }

function confirmAmount() {
  const n = parseInt(st.amount || '0', 10);
  if (!n) { st.err = 'Enter an amount first'; return show('amount', true); }
  if (st.mode !== 'deposit' && n > cfg.balance) { st.err = `Insufficient funds · available ${money(cfg.balance)}`; return show('amount', true); }
  if (st.mode === 'deposit' && n > cfg.cash) { st.err = `You only have ${money(cfg.cash)} in cash`; return show('amount', true); }
  if (st.mode === 'withdraw' && n % 10) { st.err = 'This machine dispenses multiples of $10'; return show('amount', true); }
  request(st.mode, n);
}

async function request(type, amount) {
  if (busy) return;
  const c = card();
  busy = true;
  st.busyLabel = { withdraw: 'Counting your notes', deposit: 'Counting your deposit', transfer: 'Sending your transfer' }[type];
  show('processing');
  if (type === 'deposit') notes('in');
  const payload = { card: c.id, amount };
  if (type === 'transfer') payload.target = st.target;
  const r = await call(type, payload);
  busy = false;
  if (typeof r.balance === 'number') cfg.balance = r.balance;
  if (typeof r.cash === 'number') cfg.cash = r.cash;
  if (!r.ok) {
    st.err = r.error || 'The bank could not complete this request.';
    st.declineTone = /limit|funds|cash/i.test(st.err) ? 'amber' : 'red';
    show('declined');
    return;
  }
  st.txn = { type, amount, target: st.target, ref: Math.random().toString(36).slice(2, 8).toUpperCase() };
  st.printed = false;
  if (type === 'withdraw') notes('out');
  show('done');
}

function notes(dir) {
  const n = NZ.$('#notes');
  n.className = 'notes';
  void n.offsetWidth;
  n.className = 'notes ' + dir;
  const disp = NZ.$('#dispenser');
  disp.classList.add('live');
  later(() => disp.classList.remove('live'), dir === 'out' ? 3600 : 1200);
}

/* ── receipt ── */
const fmtAcct = s => String(s || '').replace(/(\d{4})(?=\d)/g, '$1 ');

function printReceipt(t) {
  const c = card();
  const d = new Date();
  const when = d.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
  const label = { withdraw: 'Cash withdrawal', deposit: 'Cash deposit', transfer: 'Transfer out', balance: 'Balance enquiry' }[t.type];
  const lines = [
    ['Card', `•••• ${c.last4}`],
    ['Type', label],
  ];
  if (t.type === 'transfer') lines.push(['To account', fmtAcct(t.target)]);
  if (t.amount) lines.push(['Amount', money(t.amount)]);
  st.printed = true;
  const hang = NZ.$('#rcpt-hang');
  NZ.$('#paper').innerHTML = `
    <div class="p-head"><span class="nz-mark sm"></span><div><b>${NZ.esc(cfg.bank)}</b><span>${NZ.esc(cfg.location ? cfg.location + ' · ' : '')}ATM ${NZ.esc(termId())}</span></div></div>
    <div class="p-sec">
      <div class="p-ln"><span>Date</span>${NZ.esc(when)}</div>
      <div class="p-ln"><span>Ref</span>${NZ.esc(t.ref || Math.random().toString(36).slice(2, 8).toUpperCase())}</div>
    </div>
    <div class="p-sec">${lines.map(([a, b]) => `<div class="p-ln"><span>${NZ.esc(a)}</span>${NZ.esc(b)}</div>`).join('')}</div>
    <div class="p-tot"><span>Balance</span>${money(cfg.balance)}</div>
    <div class="p-thanks">Thank you for banking with ${NZ.esc(cfg.bank)}</div>
    <div class="p-sig"><span class="nz-mark"></span>NAYZEEE</div>`;
  const slot = NZ.$('#rcpt-slot');
  const side = NZ.$('#side');
  hang.style.top = (slot.getBoundingClientRect().bottom - side.getBoundingClientRect().top) / parseFloat(app.style.getPropertyValue('--k') || 1) - 4 + 'px';
  hang.className = 'rcpt-hang';
  hang.style.height = NZ.$('#paper').offsetHeight + 'px';
  void hang.offsetWidth;
  hang.className = 'rcpt-hang show';
  hang.onclick = takeReceipt;
}
function takeReceipt() {
  const hang = NZ.$('#rcpt-hang');
  if (!hang.classList.contains('show')) return;
  hang.className = 'rcpt-hang show taken';
  setTimeout(() => { hang.className = 'rcpt-hang'; hang.style.height = '0'; }, 460);
}
const termId = () => String((cfg.location || 'LS').split('').reduce((a, ch) => (a * 31 + ch.charCodeAt(0)) % 9000, 7) + 1000);

/* ── open / close ── */
function openUI(d) {
  timers.forEach(clearTimeout); timers = [];
  cfg = Object.assign({ bank: 'Fleeca', location: '', cards: [], balance: 0, cash: 0 }, d || {});
  cfg.cards = (cfg.cards || []).map((c, i) => ({ id: c.id ?? String(i + 1), label: c.label || 'Bank card', last4: String(c.last4 || '0000').slice(-4), holder: c.holder || '' }));
  st = { view: 'insert', card: null, pin: '', amount: '', target: '', page: 0, tries: {}, err: '' };
  busy = false; pending = null;
  NZ.$('#bank').textContent = cfg.bank;
  NZ.$('#scr-bank').textContent = cfg.bank;
  NZ.$('#where').textContent = cfg.location ? `24h banking · ${cfg.location}` : '24h banking';
  NZ.$('#scr-loc').textContent = `${cfg.bank}${cfg.location ? ' · ' + cfg.location : ''} · ATM ${termId()}`;
  cardAnim('');
  NZ.$('#notes').className = 'notes';
  const hang = NZ.$('#rcpt-hang'); hang.className = 'rcpt-hang'; hang.style.height = '0';
  tick(); fit();
  show('insert');
  NZ.open(app);
}
function closeUI() {
  timers.forEach(clearTimeout); timers = [];
  settle({ ok: false, error: 'Session ended' });
  NZ.close(app, { notify: false });
}
NZ.on('open', openUI);
NZ.on('close', closeUI);

/* ── preview: simulated bank ── */
const sim = { pinTries: {} };
function simulate(name, p) {
  if (name === 'pin') {
    if (p.pin === '1234') { sim.pinTries[p.card] = MAX_PIN_TRIES; return { ok: true }; }
    sim.pinTries[p.card] = (sim.pinTries[p.card] ?? MAX_PIN_TRIES) - 1;
    return { ok: false, attempts: sim.pinTries[p.card] };
  }
  if (name === 'withdraw') {
    if (p.amount > 5000) return { ok: false, error: 'This machine dispenses up to $5,000 per transaction.' };
    if (p.amount > cfg.balance) return { ok: false, error: 'Insufficient funds in this account.' };
    return { ok: true, balance: cfg.balance - p.amount, cash: cfg.cash + p.amount };
  }
  if (name === 'deposit') return { ok: true, balance: cfg.balance + p.amount, cash: cfg.cash - p.amount };
  if (name === 'transfer') {
    if (p.target === '000' || p.target.startsWith('0000')) return { ok: false, error: 'Recipient account not found. Check the number and try again.' };
    if (p.amount > cfg.balance) return { ok: false, error: 'Insufficient funds in this account.' };
    return { ok: true, balance: cfg.balance - p.amount };
  }
  return { ok: false };
}

NZ.preview(() => openUI({
  bank: 'Fleeca',
  location: 'Legion Square',
  balance: 48250,
  cash: 1340,
  cards: [
    { id: 'fl_4021', label: 'Fleeca debit', last4: '4021', holder: 'Jamie Reyes' },
    { id: 'mz_7730', label: 'Maze Bank credit', last4: '7730', holder: 'Jamie Reyes' },
    { id: 'biz_1188', label: 'Business account', last4: '1188', holder: 'Reyes Towing LLC' },
  ],
}));
