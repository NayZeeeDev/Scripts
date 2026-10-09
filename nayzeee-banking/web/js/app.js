/* ═══════════════════════════════════════════════════════════
   NAYZEEE BANKING — NUI
   ═══════════════════════════════════════════════════════════ */
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'nayzeee-banking';

const S = {
  data: null,
  page: 'dashboard',
  accountId: null,
  cardIndex: 0,
  tx: { page: 1, search: '', category: 'all' },
  billPage: 1,
  payPage: 1,
  cardPage: 1,
  societyId: null,
  payrollData: null,
  selectedCard: null,
  statement: null,
  txResult: null,
  sharedId: null,
  members: [],
  busy: false
};

/* ── theme ────────────────────────────────────────────────── */
function hexToRgb(hex) {
  const h = String(hex || '').replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
  const n = parseInt(full, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** Server owners set one accent; the washes and edges come off it. */
function applyTheme(ui) {
  if (!ui) return;
  const root = document.documentElement.style;
  const [r, g, b] = hexToRgb(ui.accent);

  root.setProperty('--teal', ui.accent);
  root.setProperty('--teal-hi', ui.accentLight || ui.accent);
  root.setProperty('--teal-lo', ui.accentDark || ui.accent);
  root.setProperty('--teal-wash', `rgba(${r},${g},${b},.11)`);
  root.setProperty('--teal-edge', `rgba(${r},${g},${b},.34)`);

  if (ui.danger) {
    const [dr, dg, db] = hexToRgb(ui.danger);
    root.setProperty('--red', ui.danger);
    root.setProperty('--red-wash', `rgba(${dr},${dg},${db},.11)`);
    root.setProperty('--red-edge', `rgba(${dr},${dg},${db},.34)`);
  }
  if (ui.background) root.setProperty('--base', ui.background);
  if (ui.panel) root.setProperty('--panel', ui.panel);

  applyLogo(ui.logo);
}

/** Swap the built-in mark for the server's own logo, in both places. */
function applyLogo(url) {
  const pairs = [
    ['brandLogo', 'brandMark'],
    ['introLogo', 'introMark'],
    ['pinLogo',   'pinMark']
  ];

  for (const [imgId, markId] of pairs) {
    const img = document.getElementById(imgId);
    const mark = document.getElementById(markId);
    if (!img || !mark) continue;

    if (url && String(url).trim() !== '') {
      img.src = url;
      img.onload = () => { img.classList.remove('hidden'); mark.classList.add('hidden'); };
      img.onerror = () => { img.classList.add('hidden'); mark.classList.remove('hidden'); };
    } else {
      img.classList.add('hidden');
      mark.classList.remove('hidden');
    }
  }
}

/* ── bridge ───────────────────────────────────────────────── */
const POST_TIMEOUT = 12000;

async function post(name, ...args) {
  const control = new AbortController();
  const timer = setTimeout(() => control.abort(), POST_TIMEOUT);

  try {
    const res = await fetch(`https://${RES}/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ name, args }),
      signal: control.signal
    });
    return await res.json();
  } catch (e) {
    // aborted, or the server callback errored and never answered
    return { ok: false, msg: 'The bank did not respond. Try again.' };
  } finally {
    clearTimeout(timer);
  }
}

function closeUI() {
  document.body.classList.remove('up');
  fetch(`https://${RES}/close`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: '{}'
  }).catch(() => {});
}

/* ═══════════════════════════════════════════════════════════
   SOUND

   Every sound in the resource plays from here. This page stays
   loaded even while it is hidden, so the ATM screen and the phone
   can both ask it to play something — a DUI cannot be relied on
   for audio, and this way there is one volume to set.

   Clips are cached after the first play so a keypress never waits
   on a file read.
   ═══════════════════════════════════════════════════════════ */
const SOUNDS = {};

function playSound(name, volume) {
  if (!name) return;
  try {
    let clip = SOUNDS[name];
    if (!clip) {
      clip = new Audio(`sounds/${name}.ogg`);
      clip.preload = 'auto';
      SOUNDS[name] = clip;
    }
    // a second press before the first finished restarts it rather
    // than being swallowed
    clip.currentTime = 0;
    clip.volume = Math.max(0, Math.min(1, volume == null ? 0.6 : volume));
    const p = clip.play();
    if (p && p.catch) p.catch(() => {});
  } catch (err) { /* audio is never worth breaking a screen over */ }
}

window.addEventListener('message', (e) => {
  const m = e.data;
  if (m.action === 'sound') return playSound(m.name, m.volume);
  if (m.action === 'open') {
    S.data = m.data;
    S.accountId = m.data.primary;
    S.page = 'dashboard';
    S.cardIndex = 0;
    S.txResult = null;
    S.statement = null;
    S.statementDoc = null;
    S.statementAccount = null;
    S.statementPeriod = 'week';
    const stale = document.getElementById('view');
    if (stale) stale.innerHTML = '';
    S.tx = { page: 1, search: '', category: 'all' };
    applyTheme(m.data.config.ui);
    document.body.classList.remove('locked');
    document.body.classList.add('up');
    boot();
  } else if (m.action === 'pinpad') {
    applyTheme(m.data && m.data.ui);
    openPinPad(m.data);
  } else if (m.action === 'lock') {
    document.body.classList.add('locked');
  } else if (m.action === 'update') {
    S.data = m.data;
    render();
    chrome();
  } else if (m.action === 'close') {
    document.body.classList.remove('up');
  }
});

document.addEventListener('keydown', (e) => {
  if (!document.body.classList.contains('up')) return;

  if (document.getElementById('pinpad').classList.contains('up')) {
    if (e.key === 'Escape') return cancelPin();
    if (e.key === 'Backspace') { PIN.value = PIN.value.slice(0, -1); return drawPinDots(); }
    if (/^[0-9]$/.test(e.key) && PIN.value.length < 4 && !PIN.busy) {
      PIN.value += e.key;
      drawPinDots();
      if (PIN.value.length === 4) submitPin();
    }
    return;
  }

  if (document.getElementById('veil').classList.contains('up')) {
    if (e.key === 'Escape') closeModal();
    return;
  }
  if (e.key === 'Escape') return closeUI();
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;

  const k = e.key.toLowerCase();
  if (k === 'd') amountModal('deposit');
  else if (k === 'w') amountModal('withdraw');
  else if (k === 't') transferModal();
});

/* ── intro ────────────────────────────────────────────────── */
/** The bar tracks real work, not a timer. */
function introStep(label, pct) {
  const bar = document.getElementById('introBar');
  const step = document.getElementById('introStep');
  if (bar) bar.style.width = pct + '%';
  if (step) step.textContent = label;
}

let introStart = 0;

function startIntro() {
  const cfg = S.data.config.intro || {};
  introStart = Date.now();
  const intro = document.getElementById('intro');
  const frame = document.querySelector('.frame');

  if (!cfg.enabled) return false;

  document.getElementById('introName').textContent =
    (S.data.config.serverName || 'Banking').toUpperCase();
  document.getElementById('introSub').textContent = isATM()
    ? 'Reading your card'
    : (cfg.tagline || 'Secure Banking');

  document.body.classList.add('booting');
  frame.classList.remove('entered');
  intro.classList.remove('out');
  void intro.offsetWidth;          // replay the animations on every open
  intro.classList.add('up');

  introStep('Connecting', 12);
  return true;
}

/** Called once the dashboard actually has its data. */
async function finishIntro() {
  const cfg = S.data.config.intro || {};
  const intro = document.getElementById('intro');
  const frame = document.querySelector('.frame');

  if (!cfg.enabled) {
    document.body.classList.remove('booting');
    frame.classList.add('entered');
    return;
  }

  // loading is usually faster than the intro reads, so hold it on screen
  // for at least the configured duration rather than flashing past
  const elapsed = Date.now() - introStart;
  const hold = Math.max(0, (cfg.duration || 2600) - elapsed);
  if (hold > 0) await sleep(hold);

  introStep('Ready', 100);
  await sleep(520);               // a beat on 100% before it moves

  intro.classList.add('out');
  document.body.classList.remove('booting');
  frame.classList.add('entered');
  setTimeout(() => intro.classList.remove('up', 'out'), 480);
}

/* ── ATM pin pad ──────────────────────────────────────────── */
const PIN = { value: '', card: null, busy: false };

function openPinPad(data) {
  PIN.value = '';
  PIN.card = data && data.card;
  PIN.busy = true;                 // locked until the card is read

  const last = PIN.card ? String(PIN.card.number).slice(-4) : '····';
  document.getElementById('pinCard').textContent = `Card ending ${last}`;

  const brand = document.getElementById('pinBrandName');
  if (brand) brand.textContent = (data && data.serverName ? data.serverName : 'Banking').toUpperCase();

  setPinMessage('4-digit card PIN', false);
  drawPinDots();

  // nothing of the account is visible until the PIN is accepted
  document.body.classList.add('up', 'locked');
  document.getElementById('pinpad').classList.add('up');

  // how the pad arrives, set by Config.ATM.cardAnimation
  const style = (data && data.animation) || 'vertical';
  const box = document.querySelector('.pin-box');
  box.className = 'pin-box' + (style === 'none' ? '' : ' ' + style);
  void box.offsetWidth;

  PIN.busy = false;
}

function closePinPad() {
  document.getElementById('pinpad').classList.remove('up');
  if (!S.data || !document.querySelector('.frame')) return;
}

function drawPinDots() {
  const dots = document.getElementById('pinDots').children;
  for (let i = 0; i < dots.length; i++) {
    dots[i].classList.toggle('on', i < PIN.value.length);
  }
}

function setPinMessage(text, bad) {
  const el = document.getElementById('pinMsg');
  el.textContent = text;
  el.classList.toggle('bad', !!bad);
}

async function submitPin() {
  if (PIN.busy || PIN.value.length !== 4) return;
  PIN.busy = true;
  setPinMessage('Checking…', false);

  const res = await post('nz_bank:verifyPin', PIN.card.id, PIN.value);

  if (res && res.ok) {
    // stay hidden. The open message below brings the UI back with its intro —
    // releasing the frame here flashes whatever was rendered last.
    document.getElementById('pinpad').classList.remove('up');
    document.body.classList.remove('up');
    document.body.classList.add('booting');
    fetch(`https://${RES}/pinResult`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ ok: true })
    }).catch(() => {});
    return;
  }

  PIN.value = '';
  PIN.busy = false;
  drawPinDots();
  setPinMessage((res && res.msg) || 'Wrong PIN', true);

  const box = document.getElementById('pinInner');
  box.classList.add('pin-shake');
  setTimeout(() => box.classList.remove('pin-shake'), 280);

  if (res && res.msg && res.msg.toLowerCase().includes('blocked')) {
    setTimeout(cancelPin, 900);
  }
}

function cancelPin() {
  document.getElementById('pinpad').classList.remove('up');
  document.body.classList.remove('up', 'locked');
  fetch(`https://${RES}/pinResult`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ ok: false })
  }).catch(() => {});
}

document.getElementById('pinpad').addEventListener('click', (e) => {
  const btn = e.target.closest('[data-key]');
  if (!btn) return;
  const key = btn.dataset.key;

  if (key === 'cancel') return cancelPin();
  if (key === 'clear') { PIN.value = ''; drawPinDots(); return setPinMessage('4-digit card PIN', false); }
  if (PIN.value.length >= 4 || PIN.busy) return;

  PIN.value += key;
  drawPinDots();
  if (PIN.value.length === 4) submitPin();
});

/* ── helpers ──────────────────────────────────────────────── */
const cur = () => (S.data && S.data.config.currency) || '$';
/* the minus goes in front of the symbol: −$1 234, not $-1 234 */
const money = (n) => {
  const r = Math.round(n || 0);
  const v = Math.abs(r).toLocaleString('en-US').replace(/,/g, ' ');
  const s = (S.data && S.data.config.currencyRight) ? `${v}${cur()}` : `${cur()}${v}`;
  return r < 0 ? `−${s}` : s;
};
const short = (n) => {
  n = Math.round(n || 0);
  const a = Math.abs(n);
  const right = S.data && S.data.config.currencyRight;
  const wrap = (v) => (n < 0 ? '−' : '') + (right ? v + cur() : cur() + v);
  // 999 600 would round to 1000k, so it reads as millions instead
  if (a >= 1e6 || Math.round(a / 1e3) >= 1000) return wrap((a / 1e6).toFixed(1) + 'm');
  if (a >= 1e4) return wrap(Math.round(a / 1e3) + 'k');
  return money(n);
};
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const initials = (name) => String(name || '').trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase();
const account = (id) => (S.data.accounts || []).find(a => a.id === id);
const accountsOfType = (t) => (S.data.accounts || []).filter(a => a.type === t);
const isATM = () => S.data && S.data.context === 'atm';

const ICON = {
  in:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v13M6.5 12.5 12 18l5.5-5.5"/></svg>',
  out:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V6M6.5 11.5 12 6l5.5 5.5"/></svg>',
  swap: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h14l-3.5-3.5M20 16H6l3.5 3.5"/></svg>',
  card: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19M6 15h3"/></svg>',
  bank: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10 12 4l9 6M5 10v9h14v-9M9 19v-5h6v5"/></svg>',
  coin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M14.5 9.2a3 3 0 0 0-5.2 2c0 2.4 5 2 5 4.2a3 3 0 0 1-5.2 1.5M12 6.5v11"/></svg>',
  chart:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M4 19V9M10 19V5M16 19v-6M22 19H2"/></svg>',
  bag:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 11a6 6 0 0 1 6-6h3a6 6 0 0 1 6 6v3a4 4 0 0 1-4 4h-1v2h-3v-2H9a5 5 0 0 1-5-5v-2z"/></svg>',
  bill: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3z"/><path d="M9.5 8h5M9.5 12h5"/></svg>',
  clock:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
  warn: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg>',
  check:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5 9 17.5 20 6.5"/></svg>',
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 6v12M6 12h12"/></svg>',
  x:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  pen:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17v3z"/></svg>',
  cog:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="3.2"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"/></svg>',
  up:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M6 14.5 12 8.5l6 6"/></svg>',
  down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M6 9.5 12 15.5l6-6"/></svg>',
  none: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>'
};

const CAT_ICON = { deposit: 'in', withdraw: 'out', transfer: 'swap', card: 'card', loan: 'coin',
  interest: 'bag', bill: 'bill', payroll: 'in', fee: 'out', admin: 'cog' };

/* ── notifications ────────────────────────────────────────────
   The UI never draws its own. Everything is handed to the client,
   which forwards it to ox_lib, ESX or your own notify resource
   depending on Config.Notify.                                    */
function notify(title, description, kind) {
  fetch(`https://${RES}/notify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ title, description, type: kind || 'inform' })
  }).catch(() => {});
}

function toast(title, body, bad) { notify(title, body, bad ? 'error' : 'success'); }

/* Config.Sounds.enabled, passed in by the client with every payload */
const soundsOn = () => !(S.data && S.data.config && S.data.config.sounds === false);

function reply(res, fallback) {
  if (res && soundsOn()) playSound(res.ok ? 'approved' : 'declined', 0.35);
  if (!res) { notify('Banking', fallback || 'That did not go through.', 'error'); return false; }
  notify(res.ok ? 'Banking' : 'Not completed', res.msg || fallback, res.ok ? 'success' : 'error');
  return res.ok;
}

/** NUI blocks the async clipboard API, so fall back to a hidden textarea. */
function copyText(value) {
  let ok = false;

  try {
    const ta = document.createElement('textarea');
    ta.value = value;
    ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;top:-100px;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, ta.value.length);
    ok = document.execCommand('copy');
    ta.remove();
  } catch (e) {
    ok = false;
  }

  notify(ok ? 'Copied' : 'Account number',
    ok ? 'Account number is on your clipboard.' : value,
    ok ? 'success' : 'inform');
}

/* ── modal ────────────────────────────────────────────────── */
let modalConfirm = null;

function openModal({ title, text, body, confirm, danger, onConfirm, cancel }) {
  const veil = document.getElementById('veil');
  veil.innerHTML = `
    <div class="modal">
      <div class="modal-b">
        <div class="warn ${danger ? 'red' : ''}">${danger ? ICON.warn : ICON.check}</div>
        <div class="body-col">
          <div><h4>${esc(title)}</h4>${text ? `<p>${esc(text)}</p>` : ''}</div>
          ${body || ''}
        </div>
      </div>
      <div class="modal-f">
        <button class="btn-line" data-modal="cancel">${esc(cancel || 'Cancel')}</button>
        <button class="${danger ? 'btn-red' : 'btn-teal'}" data-modal="confirm">${esc(confirm || 'Confirm')}</button>
      </div>
    </div>`;
  veil.classList.add('up');
  modalConfirm = onConfirm;
  const first = veil.querySelector('input, select');
  if (first) setTimeout(() => first.focus(), 30);
}

function closeModal() {
  document.getElementById('veil').classList.remove('up');
  document.getElementById('veil').innerHTML = '';
  modalConfirm = null;
}

document.getElementById('veil').addEventListener('click', async (e) => {
  if (e.target.id === 'veil') return closeModal();
  const act = e.target.closest('[data-modal]');
  if (!act) return;
  if (act.dataset.modal === 'cancel') return closeModal();
  if (modalConfirm) {
    const fn = modalConfirm;
    const veil = document.getElementById('veil');
    const values = {};
    veil.querySelectorAll('[data-name]').forEach(i => {
      values[i.dataset.name] = i.type === 'checkbox' ? i.checked : i.value;
    });
    act.disabled = true;
    try {
      await fn(values);
    } catch (err) {
      notify('Banking', 'That did not go through.', 'error');
    } finally {
      act.disabled = false;
    }
  }
});

document.getElementById('veil').addEventListener('change', (e) => {
  const act = e.target.dataset.act;
  if (act === 'payee-pick') {
    const to = document.querySelector('#veil [data-name="to"]');
    if (to && e.target.value) to.value = e.target.value;
    return;
  }
  if (act === 'payee-save') {
    const field = document.getElementById('payeeLabelField');
    if (field) field.style.display = e.target.checked ? 'flex' : 'none';
    return;
  }
  if (act !== 'card-type') return;
  pickerShow(e.target.value);
  const t = (S.data.config.cardTypes || []).find(x => x.id === e.target.value);
  const field = document.getElementById('depositField');
  if (!field || !t) return;
  field.style.display = t.kind === 'secured' ? 'flex' : 'none';
  const input = field.querySelector('input');
  if (input && t.deposit) { input.value = t.deposit.min; input.placeholder = t.deposit.min; }
});

document.getElementById('veil').addEventListener('keydown', (e) => {
  // Enter on a focused button or select does its own thing; never fire Confirm over "Keep it"
  if (e.key === 'Enter' && !['BUTTON', 'SELECT', 'TEXTAREA'].includes(e.target.tagName)) {
    const btn = document.querySelector('[data-modal="confirm"]');
    if (btn) btn.click();
  }
});

/* style picker inside modals */
document.getElementById('veil').addEventListener('click', (e) => {
  const opt = e.target.closest('.skin-opt');
  if (opt) pickerShow(null, opt.dataset.skin);
});

/* quick-amount buttons inside modals */
document.getElementById('veil').addEventListener('click', (e) => {
  const q = e.target.closest('[data-fill]');
  if (!q) return;
  const input = document.querySelector('[data-name="amount"]');
  if (input) input.value = q.dataset.fill;
});

/* ═══════════════ MODAL FLOWS ═══════════════ */
function accountOptions(selectedId, filter) {
  return (S.data.accounts || [])
    .filter(a => (filter ? filter(a) : true))
    .map(a => `<option value="${a.id}" ${a.id === selectedId ? 'selected' : ''}>${esc(a.label)} · ${money(a.balance)}</option>`)
    .join('');
}

function amountModal(kind) {
  const acc = account(S.accountId) || account(S.data.primary);
  if (!acc) return;

  const isDep = kind === 'deposit';
  const max = isDep ? S.data.player.cash : acc.balance;
  const steps = [500, 1000, 5000, 25000].filter(v => v <= max);

  openModal({
    title: isDep ? 'Deposit cash' : 'Withdraw cash',
    text: isDep
      ? `You are carrying ${money(S.data.player.cash)}.`
      : `${acc.label} holds ${money(acc.balance)}.`,
    confirm: isDep ? 'Deposit' : 'Withdraw',
    body: `
      <div class="field">
        <label>Account</label>
        <select data-name="account">${accountOptions(acc.id, a => isDep ? a.can.deposit : a.can.withdraw)}</select>
      </div>
      <div class="field">
        <label>Amount</label>
        <input data-name="amount" type="number" min="1" placeholder="0" autocomplete="off">
      </div>
      <div class="quick">
        ${steps.map(v => `<button data-fill="${v}">${money(v)}</button>`).join('')}
        ${max > 0 ? `<button data-fill="${Math.floor(max)}">All</button>` : ''}
      </div>`,
    onConfirm: async (v) => {
      const amount = parseInt(v.amount, 10);
      if (!amount || amount <= 0) return toast('Not completed', 'Enter an amount above zero.', true);
      const res = await post(isDep ? 'nz_bank:deposit' : 'nz_bank:withdraw',
        parseInt(v.account, 10), amount, isATM());
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

/** Saved payees, most recently used first. null on a server without them. */
function payeeList() {
  const list = S.data && S.data.payees;
  if (!Array.isArray(list)) return null;
  return list.slice().sort((a, b) =>
    String(b.last_used || '').localeCompare(String(a.last_used || ''), undefined, { numeric: true }));
}

function transferModal(prefillNumber) {
  const acc = account(S.accountId) || account(S.data.primary);
  const fee = S.data.config.transferFee;
  const payees = payeeList();

  // picking a payee fills the number in; the field stays editable
  const picker = payees && payees.length ? `
      <div class="field">
        <label>Saved payee</label>
        <select data-act="payee-pick">
          <option value="">Type a number instead</option>
          ${payees.map(p => `<option value="${esc(p.account_number)}" ${p.account_number === prefillNumber ? 'selected' : ''}>${esc(p.label)} · ${esc(p.account_number)}</option>`).join('')}
        </select>
      </div>` : '';

  const saver = payees ? `
      <div class="sw-line">
        <div><b>Save as payee</b><span>Keep this number for next time.</span></div>
        <input type="checkbox" data-name="savePayee" data-act="payee-save">
      </div>
      <div class="field" id="payeeLabelField" style="display:none">
        <label>Payee name</label>
        <input data-name="payeeLabel" maxlength="32" placeholder="Landlord, mechanic…" autocomplete="off">
      </div>` : '';

  openModal({
    title: 'Send money',
    text: fee > 0 ? `A ${(fee * 100).toFixed(1)}% fee applies to transfers.` : 'Money arrives instantly.',
    confirm: 'Send',
    body: `
      <div class="field">
        <label>From</label>
        <select data-name="account">${accountOptions(acc && acc.id, a => a.can.transfer)}</select>
      </div>
      ${picker}
      <div class="field">
        <label>Account number</label>
        <input data-name="to" placeholder="NZB-PSL-XXXXXXXX" value="${esc(prefillNumber || '')}" autocomplete="off">
      </div>
      <div class="field row2">
        <div class="field">
          <label>Amount</label>
          <input data-name="amount" type="number" min="1" placeholder="0" autocomplete="off">
        </div>
        <div class="field">
          <label>Reference</label>
          <input data-name="note" maxlength="40" placeholder="Rent, tools, split…" autocomplete="off">
        </div>
      </div>
      ${saver}`,
    onConfirm: async (v) => {
      const to = (v.to || '').trim();
      const amount = parseInt(v.amount, 10);
      if (!to) return toast('Not completed', 'Add an account number.', true);
      if (!amount || amount <= 0) return toast('Not completed', 'Enter an amount above zero.', true);
      const res = await post('nz_bank:transfer', parseInt(v.account, 10), to, amount, v.note);
      closeModal();
      if (!reply(res)) return;

      // only after the money went through, and never twice for one number
      if (v.savePayee && !(payees || []).some(p => p.account_number === to)) {
        const saved = await post('nz_bank:savePayee', (v.payeeLabel || '').trim() || to, to);
        if (!saved || !saved.ok) reply(saved, 'The payee was not saved.');
      }
      refresh();
    }
  });
}

function payeeDeleteModal(id) {
  const p = (payeeList() || []).find(x => String(x.id) === String(id));
  if (!p) return;
  openModal({
    title: `Delete ${p.label}?`,
    text: `${p.account_number} comes off your saved payees. Nothing already sent is affected.`,
    confirm: 'Delete payee',
    cancel: 'Keep it',
    danger: true,
    onConfirm: async () => {
      const res = await post('nz_bank:deletePayee', p.id);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

/* ═══════════════ CHROME (title bar, sidebar) ═══════════════ */
function chrome() {
  const d = S.data;
  document.getElementById('playerName').textContent = d.player.name;
  const extraJobs = (d.player.jobs || []).length - 1;
  document.getElementById('playerJob').textContent =
    `${d.player.job}${d.player.grade ? ' · ' + d.player.grade : ''}${extraJobs > 0 ? ` (+${extraJobs})` : ''}`;
  document.getElementById('avatar').textContent = initials(d.player.name);
  document.getElementById('walletCash').textContent = money(d.player.cash);
  document.getElementById('creditBand').textContent = d.credit.band;
  document.getElementById('version').textContent = 'v' + (d.config.version || '1.0.0');
  document.getElementById('branchName').textContent =
    isATM() ? 'ATM terminal' : (d.config.serverName || 'Los Santos');
  document.getElementById('statusLine').innerHTML = isATM()
    ? 'Card verified · <b>limited service</b>'
    : `Signed in as <b>${esc(d.player.name)}</b>`;

  document.getElementById('tallyShared').textContent = accountsOfType('shared').length;
  const tallyCards = document.getElementById('tallyCards');
  if (tallyCards) {
    const owing = (d.cards || []).filter(c => c.kind !== 'debit' && c.balance > 0).length;
    tallyCards.textContent = (d.cards || []).length;
    tallyCards.className = 'tally' + (owing > 0 ? ' hot' : '');
  }
  const bills = d.bills.count || 0;
  const billTally = document.getElementById('tallyBills');
  billTally.textContent = bills;
  billTally.className = 'tally' + (bills > 0 ? ' hot' : '');

  const now = new Date();
  document.getElementById('clock').textContent =
    `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;

  // ATM runs a reduced menu
  const atmPages = ['dashboard', 'transactions', 'savings', 'bills'];
  const off = {
    cards:   d.config.features && d.config.features.cards === false,
    savings: d.config.features && d.config.features.savings === false,
    loans:   d.config.features && d.config.features.loans === false,
    bills:   d.config.features && d.config.features.bills === false,
    invest:  d.config.features && d.config.features.market === false
  };

  document.querySelectorAll('.nav').forEach(n => {
    const allowed = (!isATM() || atmPages.includes(n.dataset.page)) && !off[n.dataset.page];
    n.classList.toggle('hidden', !allowed);
    n.classList.toggle('on', n.dataset.page === S.page);
  });
  document.querySelectorAll('.grp').forEach(g => g.classList.toggle('hidden', isATM()));

  const societyNav = document.querySelector('[data-page="society"]');
  if (societyNav) societyNav.classList.toggle('hidden', isATM() || accountsOfType('society').length === 0);
}

/* ═══════════════ PAGES ═══════════════ */
function pageDashboard() {
  const d = S.data;
  const acc = account(d.primary) || { label: '—', balance: 0, number: '' };
  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const first = (d.player.name || '').split(' ')[0];

  const peak = Math.max(...d.cashflow.map(m => m.income), 1);
  const bars = d.cashflow.map(m => {
    const h = Math.max(5, Math.round((m.income / peak) * 100));
    const isPeak = m.income === peak && peak > 0;
    return `<div class="cbar ${isPeak ? 'peak' : ''}">
      ${isPeak ? `<span class="flag">${short(m.income)}</span>` : ''}
      <div class="fill" style="height:${h}%"></div>
      <span>${esc(m.label)}</span>
    </div>`;
  }).join('');

  return `
    <div class="head">
      <div>
        <h1>${greet}, ${esc(first)}</h1>
        <p>Your wallet, cards, transfers and cashflow in one place.</p>
      </div>
      <div class="head-act">
        <button class="btn-line" data-act="transfer">Transfer</button>
        <button class="btn-line" data-act="withdraw">Withdraw</button>
        <button class="btn-teal" data-act="deposit">Deposit</button>
      </div>
    </div>

    <div class="stats">
      ${statTile('bank', 'Total balance', money(acc.balance), acc.label)}
      ${statTile('out', 'Spending', money(d.summary.spending), 'This month', true)}
      ${statTile('in', 'Income', money(d.summary.income), 'This month')}
      ${statTile('bag', 'Savings', money(d.summary.savings), d.savings.open ? `${(d.savings.rate * 100).toFixed(0)}% interest` : 'Not open')}
    </div>

    <div class="cols">
      <div class="stack">
        <section class="panel">
          <div class="p-head">
            <div><h2>Cashflow</h2><p>Money in over the last twelve months</p></div>
            <div class="legend"><span><i></i>Income</span><span><i class="grey"></i>Quiet months</span></div>
          </div>
          <div class="p-body tight">
            <div class="num" style="font-size:26px;font-weight:700;letter-spacing:-.04em;color:var(--white)">${money(acc.balance)}</div>
            <div class="chart">${bars}</div>
          </div>
        </section>

        <section class="panel">
          <div class="p-head">
            <div><h2>Latest transactions</h2><p>Across ${esc(acc.label)}</p></div>
            <button class="btn-ghost" data-act="goto" data-page="transactions">${ICON.chart} See all</button>
          </div>
          <div class="p-body" id="recent">${skeletonRows(3)}</div>
        </section>
      </div>

      <div class="stack">
        ${cardPanel()}
      </div>
    </div>`;
}

function statTile(icon, label, value, sub, red) {
  return `<div class="stat">
    <div class="tile ${red ? 'red' : ''}">${ICON[icon]}</div>
    <div class="stat-txt"><span>${esc(label)}</span><b>${value}</b><i>${esc(sub || '')}</i></div>
  </div>`;
}

function quickActions() {
  return `<section class="panel">
    <div class="p-head"><div><h2>Move money</h2><p>Cash in, cash out, or send it on</p></div></div>
    <div class="p-body tight">
      <div class="acts-grid">
        <button class="act" data-act="deposit">${ICON.in}Deposit</button>
        <button class="act" data-act="withdraw">${ICON.out}Withdraw</button>
        <button class="act" data-act="transfer">${ICON.swap}Transfer</button>
      </div>
    </div>
  </section>`;
}

function skeletonRows(n) {
  return Array.from({ length: n }).map(() => `
    <div class="skel"><div class="sk circ"></div>
      <div style="flex:1"><div class="sk" style="height:9px;width:52%"></div>
      <div class="sk" style="height:7px;width:32%;margin-top:7px"></div></div></div>`).join('');
}

function txRow(t) {
  const dir = t.direction === 'in';
  return `<div class="row">
    <div class="ic ${dir ? '' : 'out'}">${ICON[CAT_ICON[t.category] || (dir ? 'in' : 'out')]}</div>
    <div class="row-txt"><b>${esc(t.label)}</b><span>${esc(t.stamp)}${t.actor_name ? ' · ' + esc(t.actor_name) : ''}</span></div>
    <div class="amount ${dir ? 'in' : 'out'}">${dir ? '+' : '−'} ${money(t.amount)}</div>
  </div>`;
}

/* ── cards ── */
const cap = (s) => String(s || '').charAt(0).toUpperCase() + String(s || '').slice(1);

/* The rendered 3D card (web/images/cards, from tools/cardicons.py) for a card
   type and style. A type without an item of its own borrows its kind's art. */
const KIND_ART = { debit: 'card_debit', secured: 'card_secured', credit: 'card_credit' };
function cardArt(typeId, skin) {
  const t = (S.data.config.cardTypes || []).find(x => x.id === typeId) || {};
  const item = t.item || KIND_ART[t.kind] || 'card_debit';
  return `images/cards/${item}_${skin}.png`;
}
// a style added in config without rendered art falls back to the first style
const artFallback = `onerror="this.onerror=null;this.src='images/cards/card_debit_teal.png'"`;
const artImg = (typeId, skin) => `<img src="${cardArt(typeId, skin)}" alt="" ${artFallback}>`;

/* the same badge the renders carry */
function cardBadge(card) {
  if (card.joint) return 'MEMBER';
  if (card.type === 'platinum') return 'PLATINUM';
  return card.kind === 'secured' ? 'SECURED' : card.kind === 'credit' ? 'CREDIT' : 'DEBIT';
}

function cardFace(card) {
  const on = card.express ? ' on' : '';
  return `<div class="bcard-stage"><div class="bcard ${card.skin} ${card.status !== 'active' ? 'blocked' : ''}" data-tilt>
    <div class="glare"></div><div class="shine"></div>
    <div class="top"><div class="emv"></div>
      <svg class="nfc${on}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M8.5 8.5a5 5 0 0 1 0 7"/><path d="M12 6a8.5 8.5 0 0 1 0 12"/><path d="M15.5 3.5a12 12 0 0 1 0 17"/></svg>
      <span class="badge">${cardBadge(card)}</span>
    </div>
    <div class="num">${esc(card.number)}</div>
    <div class="foot">
      <div><span>ACCOUNT NAME</span><b>${esc(card.holder)}</b></div>
      <div style="text-align:right"><span>EXPIRES</span><b>${esc(card.expires)}</b></div>
    </div>
  </div></div>`;
}

/* The card leans toward the mouse and the light follows it. */
document.addEventListener('mousemove', (e) => {
  const c = e.target.closest && e.target.closest('[data-tilt]');
  document.querySelectorAll('[data-tilt].live').forEach(x => {
    if (x === c) return;
    x.classList.remove('live');
    ['--rx', '--ry', '--gx', '--gy'].forEach(v => x.style.removeProperty(v));
  });
  if (!c) return;
  const r = c.getBoundingClientRect();
  const px = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
  const py = Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
  c.classList.add('live');
  c.style.setProperty('--rx', `${((0.5 - py) * 16).toFixed(2)}deg`);
  c.style.setProperty('--ry', `${((px - 0.5) * 22).toFixed(2)}deg`);
  c.style.setProperty('--gx', `${(px * 100).toFixed(1)}%`);
  c.style.setProperty('--gy', `${(py * 100).toFixed(1)}%`);
});

/* Style picker: the four rendered cards to click, and a big preview above. */
function stylePicker(typeId, current) {
  const skins = S.data.config.cardSkins || [];
  const pick = skins.includes(current) ? current : skins[0];
  return `
    <div class="card-preview" id="cardPreview">${artImg(typeId, pick)}</div>
    <div class="field"><label>Style</label>
      <div class="skin-pick" data-type="${esc(typeId)}">${skins.map(s => `
        <button type="button" class="skin-opt ${s === pick ? 'on' : ''}" data-skin="${esc(s)}">
          ${artImg(typeId, s)}<span>${esc(cap(s))}</span></button>`).join('')}
      </div>
      <input type="hidden" data-name="skin" value="${esc(pick)}">
    </div>`;
}

function pickerShow(typeId, skin) {
  const box = document.querySelector('.skin-pick');
  if (!box) return;
  if (typeId) {
    box.dataset.type = typeId;
    box.querySelectorAll('.skin-opt').forEach(b => {
      b.querySelector('img').src = cardArt(typeId, b.dataset.skin);
    });
  }
  const input = document.querySelector('[data-name="skin"]');
  if (skin && input) input.value = skin;
  const now = input ? input.value : skin;
  box.querySelectorAll('.skin-opt').forEach(b => b.classList.toggle('on', b.dataset.skin === now));
  const prev = document.getElementById('cardPreview');
  if (prev) prev.innerHTML = artImg(box.dataset.type, now);
}

/* rows shown under a card, different for a credit line vs a debit card */
function cardDetails(card) {
  const acc = account(card.account) || { label: '' };
  const status = card.status === 'active' ? 'Active' : card.status === 'stolen' ? 'Reported' : 'Frozen';

  if (card.kind === 'debit') {
    const pct = card.limit > 0 ? Math.min(100, Math.round((card.spent / card.limit) * 100)) : 0;
    return `
      <div class="kv"><span>Type</span><b>${esc(card.typeLabel || 'Debit Card')}</b></div>
      <div class="kv"><span>Linked account</span><b>${esc(acc.label)}</b></div>
      <div class="kv"><span>Status</span><b class="${card.status === 'active' ? 'teal' : 'red'}">${status}</b></div>
      <div class="kv"><span>Spend limit</span>
        <span class="meter"><i style="width:${pct}%"></i></span>
        <b>${money(card.spent)} / ${money(card.limit)}</b></div>
      ${card.spent > 0 && card.spentIn > 0
        ? `<div class="kv"><span>Resets in</span><b>${Math.floor(card.spentIn / 60)}h ${card.spentIn % 60}m</b></div>` : ''}`;
  }

  const usePct = card.credit > 0 ? Math.min(100, Math.round((card.balance / card.credit) * 100)) : 0;
  return `
    <div class="kv"><span>Type</span><b>${esc(card.typeLabel)} · ${(card.apr * 100).toFixed(0)}% APR</b></div>
    <div class="kv"><span>Status</span><b class="${card.status === 'active' ? 'teal' : 'red'}">${status}</b></div>
    <div class="kv"><span>Balance owed</span><b class="${card.balance > 0 ? 'red' : 'teal'}">${money(card.balance)}</b></div>
    <div class="kv"><span>Credit used</span>
      <span class="meter"><i style="width:${usePct}%"></i></span>
      <b>${money(card.available)} left</b></div>
    ${card.minPay > 0
      ? `<div class="kv"><span>Minimum due</span><b class="red">${money(card.minPay)} · ${card.dueIn} min</b></div>`
      : `<div class="kv"><span>Minimum due</span><b>Nothing owed</b></div>`}
    ${card.deposit > 0 ? `<div class="kv"><span>Deposit held</span><b>${money(card.deposit)}</b></div>` : ''}`;
}

function cardActions(card) {
  const owing = card.kind !== 'debit' && card.balance > 0;
  return `<div class="pinned">
    ${owing ? `<button class="btn-teal" style="flex:1" data-act="card-pay" data-id="${card.id}">Pay card</button>` : ''}
    ${card.status === 'active'
      ? `<button class="btn-line" style="flex:1" data-act="card-block">Freeze</button>`
      : card.status === 'blocked'
        ? `<button class="btn-teal" style="flex:1" data-act="card-unblock">Unfreeze</button>`
        : `<button class="btn-line" style="flex:1" data-act="card-replace">Replacement</button>`}
    <button class="btn-red" data-act="card-report">Report</button>
  </div>`;
}

/* ── dedicated cards page ── */
function pageCards() {
  const cards = visibleCards();
  if (!S.selectedCard || !cards.find(c => c.id === S.selectedCard)) {
    S.selectedCard = cards[0] ? cards[0].id : null;
  }
  const card = cards.find(c => c.id === S.selectedCard);

  const per = 4;
  const pages = Math.max(1, Math.ceil(cards.length / per));
  if (S.cardPage > pages) S.cardPage = 1;
  const slice = cards.slice((S.cardPage - 1) * per, S.cardPage * per);

  const rows = slice.map(c => `
    <div class="row" data-act="card-select" data-id="${c.id}"
      style="cursor:pointer;${c.id === S.selectedCard ? 'border-color:var(--teal-edge);background:var(--teal-wash)' : ''}">
      <div class="card-thumb ${c.status === 'active' ? '' : 'off'}">${artImg(c.type, c.skin)}</div>
      <div class="row-txt"><b>${esc(c.typeLabel || 'Card')} · ${esc(c.number.slice(-4))}</b>
        <span>${esc((account(c.account) || {}).label || '')}${c.joint ? ' · member card' : ''}</span></div>
      ${c.kind === 'debit'
        ? '<span class="tag off">Debit</span>'
        : `<span class="tag ${c.balance > 0 ? 'hot' : 'live'}">${c.balance > 0 ? money(c.balance) : 'Clear'}</span>`}
    </div>`).join('') || `<div class="empty">${ICON.card}<b>No cards yet</b>
      <span>Order one and it shows up here with its limits and statement.</span></div>`;

  const statement = (S.statement || []).map(t => `
    <div class="kv"><span>${esc(t.label)} · ${esc(t.stamp)}</span>
      <b class="${t.direction === 'payment' ? 'teal' : 'red'}">${t.direction === 'payment' ? '−' : '+'} ${money(t.amount)}</b></div>`)
    .join('') || `<div class="empty">${ICON.none}<b>No activity</b><span>Charges and payments show here.</span></div>`;

  return `
    <div class="head">
      <div><h1>Cards</h1><p>Debit, secured and credit lines, all in one wallet.</p></div>
      <div class="head-act"><button class="btn-teal" data-act="card-order">Order a card</button></div>
    </div>

    <div class="cols">
      <div class="stack">
        <section class="panel" style="flex:none">
          <div class="p-head"><div><h2>Your wallet</h2><p>${cards.length} card${cards.length === 1 ? '' : 's'} issued</p></div></div>
          <div class="p-body">${rows}
            ${pages > 1 ? `<div class="pager">
              ${Array.from({ length: pages }).map((_, i) =>
                `<button class="${i + 1 === S.cardPage ? 'on' : ''}" data-act="card-page" data-page="${i + 1}">${i + 1}</button>`).join('')}
            </div>` : ''}
          </div>
        </section>

        <section class="panel" style="flex:1;min-height:0">
          <div class="p-head"><div><h2>Statement</h2>
            <p>${card && card.kind !== 'debit' ? 'Charges, interest and payments' : 'Debit cards settle straight from the account'}</p></div></div>
          <div class="p-body tight"><div class="fill-rest">${card && card.kind !== 'debit' ? statement
            : `<div class="empty">${ICON.card}<b>Nothing to bill</b><span>This card takes money from the account as it is spent.</span></div>`}</div></div>
        </section>
      </div>

      <section class="panel">
        <div class="p-head"><div><h2>${card ? esc(card.typeLabel || 'Card') : 'No card'}</h2>
          <p>${card ? esc((account(card.account) || {}).label || '') : 'Order one to get started'}</p></div></div>
        <div class="p-body tight">
          ${card ? `${cardFace(card)}
            <div class="card-nav">
              <button class="icobtn" data-act="card-settings" title="Card settings">${ICON.cog}</button>
              <button class="icobtn" data-act="card-pin" title="Change PIN">${ICON.pen}</button>
              <span class="count">${esc(card.number.slice(-4))}</span>
              <button class="icobtn danger" data-act="card-delete" title="Close card">${ICON.x}</button>
            </div>
            <div class="fill-rest" style="margin-top:10px">
              ${cardDetails(card)}
              ${cardActions(card)}
            </div>`
            : `<div class="empty">${ICON.card}<b>No card selected</b>
                <span>Order a debit card, a secured card or a credit line.</span></div>`}
        </div>
      </section>
    </div>`;
}

function cardPanel() {
  const d = S.data;
  const cards = visibleCards();

  if (S.cardIndex >= cards.length) S.cardIndex = 0;
  const card = cards[S.cardIndex];

  const head = `<div class="p-head">
      <div><h2>Your cards</h2><p>Create, style and lock your cards</p></div>
    </div>`;

  if (!card) {
    return `<section class="panel">${head}
      <div class="p-body tight">
        <div class="empty">${ICON.card}<b>No card on this account yet</b>
          <span>A card lets you use ATMs and pay by terminal around the city.</span></div>
        <button class="btn-teal wide" style="margin-top:12px" data-act="card-order">Order a card</button>
        <button class="acctnum" style="margin-top:10px" data-act="copy"
          data-value="${esc((account(S.data.primary) || {}).number)}">
          ${esc((account(S.data.primary) || {}).number)}
        </button>
      </div></section>`;
  }

  return `<section class="panel">${head}
    <div class="p-body tight">
      ${cardFace(card)}

      <div class="card-nav">
        <button class="icobtn" data-act="card-settings" title="Card settings">${ICON.cog}</button>
        <button class="icobtn" data-act="card-pin" title="Change PIN">${ICON.pen}</button>
        <button class="icobtn" data-act="card-prev" ${cards.length < 2 ? 'disabled' : ''}>${ICON.up}</button>
        <button class="icobtn" data-act="card-next" ${cards.length < 2 ? 'disabled' : ''}>${ICON.down}</button>
        <span class="count">${S.cardIndex + 1}/${cards.length}</span>
        <button class="icobtn" data-act="card-order" title="New card">${ICON.plus}</button>
      </div>

      <div style="margin-top:12px">${cardDetails(card)}</div>

      <div style="display:flex;gap:8px;margin-top:12px">
        <button class="btn-line" style="flex:1" data-act="goto" data-page="cards">Manage cards</button>
        ${card.kind !== 'debit' && card.balance > 0
          ? `<button class="btn-teal" data-act="card-pay" data-id="${card.id}">Pay card</button>`
          : `<button class="btn-red" data-act="card-report">Report lost</button>`}
      </div>

      <div style="display:flex;gap:6px;margin-top:10px">
        <button class="acctnum" style="flex:1" data-act="copy"
          data-value="${esc((account(S.data.primary) || {}).number)}">
          ${esc((account(S.data.primary) || {}).number)}
        </button>
        <button class="icobtn" data-act="number-change" title="Reissue this number">${ICON.swap}</button>
      </div>
    </div>
  </section>`;
}

/* ── transactions ── */
function pageTransactions() {
  const r = S.txResult;
  const acc = account(S.accountId) || account(S.data.primary);

  const rows = !r ? skeletonRows(6) : (r.rows.length === 0
    ? `<div class="empty">${ICON.none}<b>Nothing here yet</b><span>Transactions on this account will show up as they happen.</span></div>`
    : `<table>
        <thead><tr><th>Action</th><th>Date</th><th class="right">Amount</th></tr></thead>
        <tbody>${r.rows.map(t => `<tr>
          <td><b>${esc(t.label)}</b></td>
          <td>${esc(t.stamp)}</td>
          <td class="right"><span class="amount ${t.direction === 'in' ? 'in' : 'out'}">
            ${t.direction === 'in' ? '+' : '−'} ${money(t.amount)}</span></td>
        </tr>`).join('')}</tbody>
      </table>
      ${pager(r)}`);

  const net = r ? r.income - r.spending : 0;
  const total = r ? Math.max(1, r.income + r.spending) : 1;
  const inPct = r ? (r.income / total) * 100 : 0;

  return `
    <div class="head">
      <div><h1>Transactions</h1><p>Search and filter everything that has moved through this account.</p></div>
      <div class="head-act">
        <div class="field"><select data-act="tx-account">${accountOptions(acc && acc.id)}</select></div>
      </div>
    </div>

    <div class="cols">
      <section class="panel">
        <div class="p-head">
          <div class="field" style="flex:1;max-width:260px">
            <input data-act="tx-search" placeholder="Search transactions" value="${esc(S.tx.search)}">
          </div>
          <div class="field" style="width:150px">
            <select data-act="tx-category">
              <option value="all">All activity</option>
              ${['deposit', 'withdraw', 'transfer', 'card', 'loan', 'interest', 'bill', 'payroll', 'fee']
                .map(c => `<option value="${c}" ${S.tx.category === c ? 'selected' : ''}>${c[0].toUpperCase() + c.slice(1)}</option>`).join('')}
            </select>
          </div>
        </div>
        <div class="p-body tight">${rows}</div>
      </section>

      <div class="stack">
        <section class="panel">
          <div class="p-head"><div><h2>Balance of activity</h2><p>Money in against money out</p></div></div>
          <div class="p-body tight">
            ${donut(inPct, r ? r.total : 0, 'TRANSACTIONS')}
            <div class="kv"><span>Money received</span><b class="teal">+ ${money(r ? r.income : 0)}</b></div>
            <div class="kv"><span>Money sent</span><b class="red">− ${money(r ? r.spending : 0)}</b></div>
            <div class="kv"><span>Net</span><b class="${net >= 0 ? 'teal' : 'red'}">${net >= 0 ? '+' : '−'} ${money(Math.abs(net))}</b></div>
          </div>
        </section>
      </div>
    </div>`;
}

function donut(pct, centre, label, tone) {
  const R = 76, C = 2 * Math.PI * R;
  const on = Math.max(0, Math.min(100, pct));
  return `<div class="donut">
    <svg viewBox="0 0 190 190" preserveAspectRatio="xMidYMid meet">
      <circle cx="95" cy="95" r="${R}" fill="none" stroke="rgba(255,255,255,.06)" stroke-width="17"/>
      <circle cx="95" cy="95" r="${R}" fill="none" stroke="${tone === 'red' ? 'var(--red)' : 'var(--teal)'}"
        stroke-width="17" stroke-linecap="round"
        stroke-dasharray="${(C * on / 100).toFixed(1)} ${C.toFixed(1)}"/>
    </svg>
    <div class="mid"><b>${centre}</b><span>${esc(label)}</span></div>
  </div>`;
}

function pager(r) {
  if (r.pages < 2) return '';
  const buttons = [];
  for (let i = 1; i <= Math.min(r.pages, 6); i++) {
    buttons.push(`<button class="${i === r.page ? 'on' : ''}" data-act="tx-page" data-page="${i}">${i}</button>`);
  }
  return `<div class="pager">
    <button data-act="tx-page" data-page="${Math.max(1, r.page - 1)}">Previous</button>
    ${buttons.join('')}
    <button data-act="tx-page" data-page="${Math.min(r.pages, r.page + 1)}">Next</button>
  </div>`;
}

/* ── shared ── */
function pageShared() {
  const shared = accountsOfType('shared');
  if (!S.sharedId || !shared.find(a => a.id === S.sharedId)) S.sharedId = shared[0] && shared[0].id;
  const acc = shared.find(a => a.id === S.sharedId);

  const tabs = shared.map(a => `
    <button class="btn-ghost ${a.id === S.sharedId ? 'on' : ''}" data-act="shared-select" data-id="${a.id}">
      ${esc(a.label)} · ${money(a.balance)}</button>`).join('');

  if (!acc) {
    return `
      <div class="head">
        <div><h1>Shared accounts</h1><p>Pool money with a crew, a business or a household.</p></div>
        <div class="head-act"><button class="btn-teal" data-act="shared-create">Open an account</button></div>
      </div>
      <section class="panel"><div class="p-body tight">
        <div class="empty">${ICON.bank}<b>You are not on a shared account</b>
          <span>Opening one costs ${money(S.data.config.sharedCost)} and lets you add up to ${S.data.config.maxSharedMembers} people.</span></div>
      </div></section>`;
  }

  const members = S.members.map(m => `
    <div class="row">
      <div class="av">${esc(initials(m.name))}</div>
      <div class="row-txt"><b>${esc(m.name)}</b>
        <span>${m.can_deposit ? 'Deposit' : ''}${m.can_withdraw ? ' · Withdraw' : ''}${m.can_transfer ? ' · Transfer' : ''}</span></div>
      ${m.role === 'owner'
        ? '<span class="tag live">Owner</span>'
        : `<button class="icobtn" data-act="member-card" data-id="${esc(m.identifier)}" data-name="${esc(m.name)}"
             title="Issue a card">${ICON.card}</button>
           <button class="icobtn" data-act="member-perms" data-id="${esc(m.identifier)}">${ICON.cog}</button>
           <button class="icobtn danger" data-act="member-remove" data-id="${esc(m.identifier)}" data-name="${esc(m.name)}">${ICON.x}</button>`}
    </div>`).join('') || `<div class="empty">${ICON.none}<b>Just you so far</b><span>Add someone by their server ID while they are online.</span></div>`;

  const isOwner = acc.role === 'owner';

  return `
    <div class="head">
      <div><h1>${esc(acc.label)}</h1><p>${esc(acc.number)}</p></div>
      <div class="head-act">
        ${isOwner ? `<button class="btn-line" data-act="shared-rename">Rename</button>` : ''}
        <button class="btn-teal" data-act="shared-create">New account</button>
      </div>
    </div>

    <div style="display:flex;gap:8px;flex-wrap:wrap">${tabs}</div>

    <div class="hero">
      <div>
        <h2>${esc(acc.label)} <span class="tag live">${acc.role === 'owner' ? 'You own this' : 'Member'}</span></h2>
        <div class="num">${money(acc.balance)}</div>
        <div class="acct">${esc(acc.number)}</div>
      </div>
      <div class="acts-grid" style="width:330px">
        <button class="act" data-act="deposit" data-account="${acc.id}">${ICON.in}Deposit</button>
        <button class="act" data-act="withdraw" data-account="${acc.id}">${ICON.out}Withdraw</button>
        <button class="act" data-act="transfer" data-account="${acc.id}">${ICON.swap}Transfer</button>
      </div>
    </div>

    <div class="cols even">
      <section class="panel">
        <div class="p-head">
          <div><h2>Members</h2><p>Who can reach this money</p></div>
          <span class="tally">${S.members.length}/${S.data.config.maxSharedMembers}</span>
        </div>
        <div class="p-body tight">
          ${isOwner ? `<div class="inline" style="margin-bottom:12px">
            <div class="field"><label>Add by server ID</label>
              <input data-act="member-id" placeholder="e.g. 42" autocomplete="off"></div>
            <button class="btn-teal" data-act="member-add">Add</button>
          </div>` : ''}
          <div class="scroll">${members}</div>
        </div>
      </section>

      <section class="panel">
        <div class="p-head"><div><h2>Recent activity</h2><p>Latest movements on this account</p></div></div>
        <div class="p-body" id="sharedTx">${skeletonRows(4)}</div>
        ${isOwner ? `<div class="modal-f"><button class="btn-red" data-act="shared-close">Close account</button></div>` : ''}
      </section>
    </div>`;
}

/* ── society ── */
function pageSociety() {
  const all = accountsOfType('society');
  if (!S.societyId || !all.find(a => a.id === S.societyId)) S.societyId = all[0] && all[0].id;
  const acc = all.find(a => a.id === S.societyId);

  const tabs = all.length > 1 ? `<div style="display:flex;gap:8px;flex-wrap:wrap">${
    all.map(a => `<button class="btn-ghost ${a.id === S.societyId ? 'on' : ''}"
      data-act="society-select" data-id="${a.id}" data-job="${esc(a.owner)}">
      ${esc(a.label)} · ${money(a.balance)}</button>`).join('')}</div>` : '';

  if (!acc) {
    return `<div class="head"><div><h1>Society</h1><p>Business and department funds.</p></div></div>
      <section class="panel"><div class="p-body tight">
        <div class="empty">${ICON.bank}<b>No society account</b>
          <span>Your current job does not have an account you can reach.</span></div></div></section>`;
  }

  return `
    <div class="head">
      <div><h1>${esc(acc.label)}</h1><p>Department funds, payouts and invoices.</p></div>
      <div class="head-act"><button class="btn-teal" data-act="bill-issue">Issue a bill</button></div>
    </div>

    ${tabs}

    <div class="hero">
      <div>
        <h2>${esc(acc.label)} <span class="tag live">Society account</span></h2>
        <div class="num">${money(acc.balance)}</div>
        <div class="acct">${esc(acc.number)}</div>
      </div>
      <div class="acts-grid" style="width:330px">
        <button class="act" data-act="deposit" data-account="${acc.id}">${ICON.in}Deposit</button>
        <button class="act" data-act="withdraw" data-account="${acc.id}">${ICON.out}Withdraw</button>
        <button class="act" data-act="transfer" data-account="${acc.id}">${ICON.swap}Transfer</button>
      </div>
    </div>

    <div class="cols">
      <section class="panel">
        <div class="p-head"><div><h2>Society transactions</h2><p>Everything moving through the department</p></div></div>
        <div class="p-body" id="societyTx">${skeletonRows(4)}</div>
      </section>

      ${payrollPanel()}
    </div>`;
}

function payrollPanel() {
  const p = S.payrollData || S.data.payroll;

  if (p && p.mode === 'esx') {
    return `<section class="panel">
      <div class="p-head"><div><h2>Payroll</h2><p>Handled outside the bank</p></div></div>
      <div class="p-body tight"><div class="empty">${ICON.coin}<b>ESX is paying wages</b>
        <span>Wages come out of this account on the framework's own cycle and land in each employee's bank.</span></div></div>
    </section>`;
  }

  if (!p) {
    return `<section class="panel">
      <div class="p-head"><div><h2>Payroll</h2><p>Management only</p></div></div>
      <div class="p-body tight"><div class="empty">${ICON.coin}<b>No access</b>
        <span>Your grade cannot set wages for this department.</span></div></div>
    </section>`;
  }

  const per = 4;
  const pages = Math.max(1, Math.ceil(p.rows.length / per));
  if (S.payPage > pages) S.payPage = 1;
  const slice = p.rows.slice((S.payPage - 1) * per, S.payPage * per);

  const rows = slice.map(r => `
    <div class="row">
      <div class="ic ${r.amount > 0 && r.enabled ? '' : 'out'}">${ICON.coin}</div>
      <div class="row-txt"><b>${esc(r.label)}</b>
        <span>${r.amount > 0 ? money(r.amount) + ' · ' + esc(r.interval) : 'No wage set'}</span></div>
      <span class="tag ${r.amount > 0 && r.enabled ? 'live' : 'off'}">${r.amount > 0 && r.enabled ? 'Paying' : 'Off'}</span>
      <button class="icobtn" data-act="wage-edit" data-grade="${r.grade}">${ICON.pen}</button>
    </div>`).join('');

  return `<section class="panel">
    <div class="p-head">
      <div><h2>Payroll</h2><p>${p.onShift} on shift · next run in ${p.nextIn} min</p></div>
      <span class="tally">${money(p.balance)}</span>
    </div>
    <div class="p-body">${rows}
      ${pages > 1 ? `<div class="pager">
        ${Array.from({ length: pages }).map((_, i) =>
          `<button class="${i + 1 === S.payPage ? 'on' : ''}" data-act="pay-page" data-page="${i + 1}">${i + 1}</button>`).join('')}
      </div>` : ''}
    </div>
  </section>`;
}

/* ── savings ── */
function pageSavings() {
  const s = S.data.savings;

  if (!s.open) {
    return `
      <div class="head"><div><h1>Savings</h1>
        <p>Put money aside and earn ${(s.rate * 100).toFixed(0)}% interest on every payout.</p></div></div>
      <section class="panel"><div class="p-body tight">
        <div class="empty">${ICON.bag}<b>No savings account yet</b>
          <span>Interest lands automatically while the money sits untouched.</span></div>
        <button class="btn-teal wide" style="margin-top:12px" data-act="savings-open">Open a savings account</button>
      </div></section>`;
  }

  const goalPct = s.goal ? Math.min(100, Math.round((s.balance / s.goal) * 100)) : 0;

  return `
    <div class="head">
      <div><h1>Savings</h1><p>${esc(s.number)}</p></div>
      <div class="head-act">
        <button class="btn-line" data-act="savings-goal">${s.goal ? 'Change goal' : 'Set a goal'}</button>
        <button class="btn-teal" data-act="deposit" data-account="${s.id}">Deposit</button>
      </div>
    </div>

    <div class="stats" style="grid-template-columns:repeat(3,1fr)">
      ${statTile('bag', 'Savings balance', money(s.balance), 'Earning interest')}
      ${statTile('in', 'Interest earned', money(s.earned), 'Since opening')}
      ${statTile('clock', 'Next payout', s.nextIn > 0 ? `${s.nextIn} min` : 'Any moment', `${(s.rate * 100).toFixed(0)}% each time`)}
    </div>

    <div class="cols">
      <section class="panel">
        <div class="p-head"><div><h2>Move money</h2><p>Savings can be topped up or drawn down at any time</p></div></div>
        <div class="p-body tight">
          <div class="acts-grid">
            <button class="act" data-act="deposit" data-account="${s.id}">${ICON.in}Deposit</button>
            <button class="act" data-act="withdraw" data-account="${s.id}">${ICON.out}Withdraw</button>
            <button class="act" data-act="transfer" data-account="${s.id}">${ICON.swap}Transfer</button>
          </div>
          <div style="margin-top:16px">
            <div class="kv"><span>Total deposited</span><b>${money(s.deposited)}</b></div>
            <div class="kv"><span>Total earned</span><b class="teal">${money(s.earned)}</b></div>
            <div class="kv"><span>Interest rate</span><b>${(s.rate * 100).toFixed(0)}%</b></div>
          </div>
        </div>
      </section>

      <section class="panel">
        <div class="p-head"><div><h2>${s.goal ? 'Goal progress' : 'Growth'}</h2>
          <p>${s.goal ? `Target ${money(s.goal)}` : 'What interest has added so far'}</p></div></div>
        <div class="p-body tight">
          ${s.goal
            ? donut(goalPct, goalPct + '%', 'OF GOAL')
            : donut(Math.min(100, s.balance > 0 ? (s.earned / s.balance) * 100 : 0), (s.rate * 100).toFixed(0) + '%', 'EARNED')}
        </div>
      </section>
    </div>`;
}

/* ── loans ── */
function pageLoans() {
  const d = S.data;
  const loan = d.loans.active[0];
  const score = d.credit.score;
  const pct = Math.round((score / 850) * 100);

  const tiers = d.config.loanTiers.map(t => {
    const locked = score < t.minCredit || !!loan;
    return `<div class="tier ${locked ? 'locked' : ''}">
      <div class="name">${ICON.coin}${esc(t.label)} loan</div>
      <div class="kv"><span>Total amount</span><b>${money(t.amount)}</b></div>
      <div class="kv"><span>Each payment</span><b>${money(t.payment)}</b></div>
      <div class="kv"><span>Interest</span><b>${(t.interest * 100).toFixed(0)}%</b></div>
      <div class="kv"><span>Term</span><b>${t.termDays} days</b></div>
      <div class="kv"><span>Credit needed</span><b class="${score >= t.minCredit ? 'teal' : 'red'}">${t.minCredit}</b></div>
      <button class="btn-line wide" data-act="loan-request" data-tier="${esc(t.id)}" ${locked ? 'disabled' : ''}>
        ${loan ? 'One loan at a time' : score < t.minCredit ? 'Credit too low' : 'Request this loan'}</button>
    </div>`;
  }).join('');

  const warning = d.loans.defaulted > 0
    ? `<div class="banner">${ICON.warn}
        <div><b>You have a defaulted loan</b><p>${money(d.loans.defaultedOwed || 0)} is outstanding. Settle it before borrowing again.</p></div>
        <button class="btn-line" data-act="loan-settle">Settle now</button></div>`
    : `<div class="banner">${ICON.warn}
        <div><b>Borrow only what you can repay</b>
        <p>Missed payments cut your credit score, and three misses put the loan into default.</p></div></div>`;

  const active = loan ? `
    <div class="fill-rest">
      <div class="kv"><span>Next payment in</span><b>${loan.nextIn} min</b></div>
      <div class="kv"><span>Remaining</span><b class="red">${money(loan.remaining)}</b></div>
      <div class="kv"><span>Each payment</span><b>${money(loan.payment)} · ${loan.daysLeft} left</b></div>
      <div class="kv"><span>Missed</span><b class="${loan.missed > 0 ? 'red' : ''}">${loan.missed}</b></div>
      <div class="pinned">
        <button class="btn-line" style="flex:1" data-act="loan-pay" data-id="${loan.id}">Make a payment</button>
        <button class="btn-teal" style="flex:1" data-act="loan-payoff" data-id="${loan.id}">Pay off</button>
      </div>
    </div>`
    : `<div class="fill-rest"><div class="empty" style="margin-top:8px">${ICON.check}<b>No loan running</b>
        <span>Your credit score decides which offers you can take.</span></div></div>`;

  return `
    <div class="head"><div><h1>Loans</h1>
      <p>Borrow against your credit standing. Payments are pulled automatically unless you turn that off.</p></div></div>

    ${warning}

    <div class="cols">
      <div class="tiers">${tiers}</div>

      <div class="stack">
        <section class="panel" style="flex:none">
          <div class="p-head"><div><h2>Credit score</h2><p>Built from how you repay</p></div></div>
          <div class="p-body tight">
            ${donut(pct, score, String(d.credit.band).toUpperCase())}
            <div class="kv"><span>On-time</span><b class="teal">${d.credit.onTime}</b></div>
            <div class="kv"><span>Late</span><b class="${d.credit.late > 0 ? 'red' : ''}">${d.credit.late}</b></div>
          </div>
        </section>

        <section class="panel" style="flex:1;min-height:0">
          <div class="p-head"><div><h2>Current loan</h2><p>${loan ? esc(loan.tier) + ' loan' : 'Nothing outstanding'}</p></div></div>
          <div class="p-body tight">${active}</div>
        </section>
      </div>
    </div>`;
}

/* ── bills ── */
function pageBills() {
  const b = S.data.bills;
  const per = 4;
  const pages = Math.max(1, Math.ceil(b.rows.length / per));
  if (S.billPage > pages) S.billPage = 1;
  const slice = b.rows.slice((S.billPage - 1) * per, S.billPage * per);
  const rows = slice.map(x => `
    <div class="row">
      <div class="ic out">${ICON.bill}</div>
      <div class="row-txt"><b>${esc(x.reason)}</b>
        <span>${esc(x.issuer_label)}${x.sender_name ? ' · ' + esc(x.sender_name) : ''} · ${esc(x.stamp)}</span></div>
      ${x.status === 'overdue' ? '<span class="tag hot">Overdue</span>'
        : `<span class="tag ${x.dueIn < 60 ? 'warn' : 'off'}">${x.dueIn > 0 ? x.dueIn + ' min left' : 'Due'}</span>`}
      <div class="amount out">${money(x.amount)}</div>
      <button class="btn-teal" data-act="bill-pay" data-id="${x.id}">Pay</button>
    </div>`).join('') || `<div class="empty">${ICON.check}<b>Nothing owed</b>
      <span>Invoices from the city, businesses and departments land here.</span></div>`;

  return `
    <div class="head">
      <div><h1>Bills</h1><p>Everything the city and its businesses have charged you.</p></div>
      <div class="head-act"><button class="btn-line" data-act="goto" data-page="settings">Auto-pay settings</button></div>
    </div>

    <div class="stats" style="grid-template-columns:repeat(2,1fr)">
      ${statTile('bill', 'Outstanding', money(b.total), `${b.count} unpaid`, b.count > 0)}
      ${statTile('bank', 'Account balance', money((account(S.data.primary) || {}).balance || 0), 'Personal')}
    </div>

    <section class="panel">
      <div class="p-head"><div><h2>Unpaid bills</h2><p>Late fees are added once a bill goes overdue</p></div></div>
      <div class="p-body">${rows}
        ${pages > 1 ? `<div class="pager">
          ${Array.from({ length: pages }).map((_, i) =>
            `<button class="${i + 1 === S.billPage ? 'on' : ''}" data-act="bill-page" data-page="${i + 1}">${i + 1}</button>`).join('')}
        </div>` : ''}
      </div>
    </section>`;
}

/* ── scheduled ── */
function pageScheduled() {
  const rows = (S.data.scheduled || []).map(s => `
    <div class="row">
      <div class="ic">${ICON.clock}</div>
      <div class="row-txt"><b>${esc(s.label)}</b>
        <span>From ${esc(s.from_label)} → ${esc(s.to_number)} · next in ${s.nextIn} min</span></div>
      <span class="tag ${s.enabled ? 'live' : 'off'}">${s.enabled ? 'Running' : 'Paused'}</span>
      <div class="amount out">${money(s.amount)}</div>
      <button class="icobtn" data-act="sched-toggle" data-id="${s.id}">${s.enabled ? ICON.x : ICON.check}</button>
      <button class="icobtn danger" data-act="sched-delete" data-id="${s.id}">${ICON.x}</button>
    </div>`).join('') || `<div class="empty">${ICON.clock}<b>No standing transfers</b>
      <span>Set one up for rent, wages or a share of your takings.</span></div>`;

  return `
    <div class="head">
      <div><h1>Scheduled transfers</h1><p>Money that moves on its own, on a rhythm you set.</p></div>
      <div class="head-act"><button class="btn-teal" data-act="sched-create">New transfer</button></div>
    </div>

    <section class="panel">
      <div class="p-head"><div><h2>Standing orders</h2><p>Paused automatically after repeated failures</p></div></div>
      <div class="p-body">${rows}</div>
    </section>`;
}

/* ── investments ── */
function sparkline(points, up) {
  if (!points || points.length < 2) return '<svg viewBox="0 0 80 24"></svg>';
  const min = Math.min(...points), max = Math.max(...points);
  const span = (max - min) || 1;
  const step = 80 / (points.length - 1);
  const d = points.map((v, i) => `${(i * step).toFixed(1)},${(22 - ((v - min) / span) * 20).toFixed(1)}`).join(' ');
  return `<svg viewBox="0 0 80 24" style="width:80px;height:24px;flex:none">
    <polyline points="${d}" fill="none" stroke="${up ? 'var(--teal)' : 'var(--red)'}"
      stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

function pageInvest() {
  const m = S.data.market;

  // the market failed to load server-side; say so rather than crash the page
  if (!m || !Array.isArray(m.assets)) {
    return `
      <div class="head"><div><h1>Investments</h1><p>Buy into listed assets and track how they move.</p></div></div>
      <section class="panel"><div class="p-body tight">
        <div class="empty">${ICON.none}<b>The market is not available</b>
          <span>Prices could not be loaded right now. Close the bank and open it again in a moment.</span></div>
      </div></section>`;
  }
  m.holdings = m.holdings || [];

  const assets = m.assets.map(a => {
    const up = a.change >= 0;
    return `<div class="row">
      <div class="ic ${up ? '' : 'out'}" style="font-size:9.5px;font-weight:700">${esc(a.id)}</div>
      <div class="row-txt"><b>${esc(a.label)}</b><span>${money(a.price)}</span></div>
      ${sparkline(a.history, up)}
      <div class="amount ${up ? 'in' : 'out'}" style="width:64px;text-align:right">${up ? '+' : ''}${a.change.toFixed(2)}%</div>
      <button class="btn-ghost" data-act="trade-buy" data-asset="${esc(a.id)}">Buy</button>
      <button class="btn-ghost" data-act="trade-sell" data-asset="${esc(a.id)}">Sell</button>
    </div>`;
  }).join('');

  const holdings = m.holdings.map(h => `
    <div class="kv"><span>${esc(h.label)} · ${h.units.toFixed(4)}</span>
      <b class="${h.pl >= 0 ? 'teal' : 'red'}">${money(h.value)} (${h.pl >= 0 ? '+' : '−'}${money(Math.abs(h.pl))})</b></div>`)
    .join('') || `<div class="empty" style="margin-top:6px">${ICON.chart}<b>Nothing held</b>
      <span>Buy into an asset and your position shows up here.</span></div>`;

  const plPct = m.cost > 0 ? Math.min(100, Math.max(0, 50 + (m.pl / m.cost) * 200)) : 50;

  return `
    <div class="head">
      <div><h1>Investments</h1>
        <p>Prices move every ${m.tick} minutes. A ${(m.fee * 100).toFixed(0)}% fee applies to both sides of a trade.</p></div>
    </div>

    <div class="stats" style="grid-template-columns:repeat(3,1fr)">
      ${statTile('chart', 'Portfolio value', money(m.value), `${m.holdings.length} position${m.holdings.length === 1 ? '' : 's'}`)}
      ${statTile(m.pl >= 0 ? 'in' : 'out', 'Unrealised', `${m.pl >= 0 ? '+' : '−'}${money(Math.abs(m.pl))}`, 'On open positions', m.pl < 0)}
      ${statTile('coin', 'Realised', `${m.realised >= 0 ? '+' : '−'}${money(Math.abs(m.realised))}`, 'Banked profit', m.realised < 0)}
    </div>

    <div class="cols">
      <section class="panel">
        <div class="p-head"><div><h2>Market</h2><p>Live prices across every listed asset</p></div></div>
        <div class="p-body">${assets}</div>
      </section>

      <section class="panel">
        <div class="p-head"><div><h2>Your positions</h2><p>Value against what you paid</p></div></div>
        <div class="p-body tight">
          ${donut(plPct, `${m.pl >= 0 ? '+' : '−'}${short(Math.abs(m.pl))}`, 'PROFIT / LOSS', m.pl < 0 ? 'red' : null)}
          <div class="kv"><span>Invested</span><b>${money(m.cost)}</b></div>
          ${holdings}
        </div>
      </section>
    </div>`;
}

/* ── settings ── */
function pageSettings() {
  const s = S.data.settings;
  const extras = [overdraftPanel(), payeesPanel()].filter(Boolean);
  const line = (key, title, text) => `
    <div class="sw-line">
      <div><b>${esc(title)}</b><span>${esc(text)}</span></div>
      <span class="sw ${s[key] ? 'on' : ''}" data-act="toggle" data-key="${key}"><i></i></span>
    </div>`;

  return `
    <div class="head"><div><h1>Settings</h1><p>How your account behaves when you are not looking at it.</p></div></div>

    <div class="cols even">
      <section class="panel">
        <div class="p-head"><div><h2>Automation</h2><p>Let the bank handle the routine</p></div></div>
        <div class="p-body tight">
          ${line('directDeposit', 'Paycheck into the bank', 'Wages go straight to your account instead of your pocket.')}
          ${line('autoPayBills', 'Pay bills automatically', 'New bills are settled the moment they arrive, if you can cover them.')}
          ${line('autoPayLoans', 'Pay loan instalments automatically', 'Instalments come out of your account so you never miss one.')}
          ${line('notifications', 'Account notifications', 'Get told about transfers, interest and bills as they happen.')}
          <button class="btn-teal wide" style="margin-top:14px" data-act="settings-save">Save changes</button>
        </div>
      </section>

      <section class="panel">
        <div class="p-head"><div><h2>Your details</h2><p>Everything the bank holds on you</p></div></div>
        <div class="p-body tight">
          <div class="kv"><span>Name</span><b>${esc(S.data.player.name)}</b></div>
          <div class="kv"><span>Account number</span><b>${esc((account(S.data.primary) || {}).number)}</b></div>
          <div class="kv"><span>Credit score</span><b class="teal">${S.data.credit.score} · ${esc(S.data.credit.band)}</b></div>
          <div class="kv"><span>Cards issued</span><b>${(S.data.cards || []).length}</b></div>
          <div class="kv"><span>Shared accounts</span><b>${accountsOfType('shared').length}</b></div>
          <div class="kv"><span>Savings</span><b>${S.data.savings.open ? money(S.data.savings.balance) : 'Not open'}</b></div>
        </div>
      </section>
    </div>

    ${extras.length ? `<div class="cols even">${extras.join('')}</div>` : ''}`;
}

/** Saved payees. Not drawn at all on a server that does not send them. */
function payeesPanel() {
  const payees = payeeList();
  if (!payees) return '';

  const rows = payees.map(p => `
    <div class="row">
      <div class="av">${esc(initials(p.label))}</div>
      <div class="row-txt"><b>${esc(p.label)}</b><span>${esc(p.account_number)}</span></div>
      <button class="icobtn" data-act="payee-send" data-number="${esc(p.account_number)}" title="Send money">${ICON.swap}</button>
      <button class="icobtn danger" data-act="payee-delete" data-id="${esc(p.id)}" title="Delete payee">${ICON.x}</button>
    </div>`).join('') || `<div class="empty">${ICON.none}<b>No saved payees</b>
      <span>Tick Save as payee when you send money and they show up here.</span></div>`;

  return `
      <section class="panel">
        <div class="p-head">
          <div><h2>Saved payees</h2><p>Numbers you send to often</p></div>
          <span class="tally">${payees.length}</span>
        </div>
        <div class="p-body tight scrolls">${rows}</div>
      </section>`;
}

/** Only drawn when the server says overdrafts are on offer. */
function overdraftPanel() {
  const od = S.data.overdraft;
  if (!od || !od.enabled) return '';

  const overdrawn = od.used > 0;

  return `
      <section class="panel">
        <div class="p-head">
          <div><h2>Overdraft</h2>
            <p>${od.savings
              ? 'Savings cover a shortfall first, then the overdraft line'
              : 'How far your account may go below zero'}</p></div>
        </div>
        <div class="p-body tight">
          ${od.optIn ? `
            <div class="sw-line">
              <div><b>Overdraft protection</b>
                <span>${od.on
                  ? `A payment that would bounce goes through instead, up to ${money(od.limit)}.`
                  : `A ${money(od.fee)} fee applies the first time you use it, then ${(od.rate * 100).toFixed(1)}% interest every ${od.rateEvery} minutes.`}</span></div>
              <span class="sw ${od.on ? 'on' : ''}" data-act="overdraft" data-on="${!od.on}"><i></i></span>
            </div>` : ''}

          <div class="kv"><span>Your limit</span><b>${money(od.limit)}</b></div>
          <div class="kv"><span>Used</span><b class="${overdrawn ? 'red' : ''}">${money(od.used)}</b></div>
          <div class="kv"><span>Still available</span><b class="teal">${money(od.available)}</b></div>
          ${od.fees > 0 ? `<div class="kv"><span>Fees charged</span><b class="red">${money(od.fees)}</b></div>` : ''}
          ${overdrawn && od.graceLeft != null ? `<div class="kv"><span>Interest starts in</span>
            <b class="${od.graceLeft <= 10 ? 'red' : ''}">${od.graceLeft} min</b></div>` : ''}

          ${overdrawn ? `<p class="note">Pay money in and the overdraft closes itself.
            Until then interest is charged on what you owe.</p>` : ''}
        </div>
      </section>`;
}

/* ═══════════════ STATEMENTS ═══════════════ */
function pageStatements() {
  const periods = S.data.config.statementPeriods || [];
  const st = S.statementDoc;

  const picker = `
    <div class="seg-row">
      ${(S.data.accounts || []).map(a => `
        <button class="${a.id === (S.statementAccount || S.data.primary) ? 'on' : ''}"
          data-act="st-account" data-id="${a.id}">${esc(a.label)}</button>`).join('')}
    </div>
    <div class="seg-row tight">
      ${periods.map(p => `
        <button class="${p.id === (S.statementPeriod || 'week') ? 'on' : ''}"
          data-act="st-period" data-id="${p.id}">${esc(p.label)}</button>`).join('')}
    </div>`;

  if (!st) {
    return `
      <div class="head"><div><h1>Statements</h1>
        <p>What the account opened at, what moved, and every line behind it.</p></div></div>
      <section class="panel">
        <div class="p-head"><div><h2>Pick a period</h2><p>Then pull the statement</p></div></div>
        <div class="p-body">
          ${picker}
          <button class="btn-teal wide" style="margin-top:18px" data-act="st-pull">Pull statement</button>
          ${S.data.config.statementFee ? `<p class="note">A ${money(S.data.config.statementFee)} fee applies.</p>` : ''}
        </div>
      </section>`;
  }

  const net = st.net >= 0;

  return `
    <div class="head">
      <div><h1>Statements</h1><p>${esc(st.account.label)} · ${esc(st.account.number)} · issued ${esc(st.issued)}</p></div>
      <div class="head-act"><button class="btn-line" data-act="st-clear">New statement</button></div>
    </div>

    <section class="panel">
      <div class="p-head"><div><h2>${esc(st.period.label)}</h2><p>Summary</p></div></div>
      <div class="p-body">
        ${picker}
        <div class="st-grid">
          <div class="kv"><span>Opening balance</span><b>${money(st.opening)}</b></div>
          <div class="kv"><span>Closing balance</span><b class="${st.closing < 0 ? 'red' : ''}">${money(st.closing)}</b></div>
          <div class="kv"><span>Paid in</span><b class="teal">${money(st.income)}</b></div>
          <div class="kv"><span>Paid out</span><b class="red">${money(st.spending)}</b></div>
          <div class="kv"><span>Net</span><b class="${net ? 'teal' : 'red'}">
            ${net ? '+' : '−'}${money(Math.abs(st.net))}</b></div>
          <div class="kv"><span>Lines</span><b>${st.count}${st.truncated ? '+' : ''}</b></div>
        </div>
      </div>
    </section>

    <div class="cols even">
      <section class="panel">
        <div class="p-head"><div><h2>Where it went</h2><p>Totals by category</p></div></div>
        <div class="p-body tight">
          ${st.breakdown.length ? st.breakdown.map(b => `
            <div class="kv"><span>${esc(b.label)} · ${b.count}</span>
              <b class="${b.direction === 'in' ? 'teal' : 'red'}">
                ${b.direction === 'in' ? '+' : '−'}${money(b.amount)}</b></div>`).join('')
            : '<p class="note">Nothing moved in this period.</p>'}
        </div>
      </section>

      <section class="panel">
        <div class="p-head"><div><h2>Every line</h2><p>Oldest first, with the running balance</p></div></div>
        <div class="p-body tight scrolls">
          ${st.rows.length ? st.rows.map(r => `
            <div class="st-line">
              <div class="txt"><b>${esc(r.label)}</b><span>${esc(r.stamp)}</span></div>
              <div class="amt ${r.direction === 'in' ? 'teal' : 'red'}">
                ${r.direction === 'in' ? '+' : '−'}${money(r.amount)}</div>
              <div class="run">${money(r.balance_after)}</div>
            </div>`).join('')
            : '<p class="note">No transactions in this period.</p>'}
        </div>
      </section>
    </div>`;
}

/* ═══════════════ RENDER ═══════════════ */
const PAGES = {
  dashboard: pageDashboard, transactions: pageTransactions, shared: pageShared,
  society: pageSociety, savings: pageSavings, loans: pageLoans,
  bills: pageBills, scheduled: pageScheduled, invest: pageInvest,
  cards: pageCards, settings: pageSettings, statements: pageStatements
};

let introSettled = false;

function render() {
  if (!S.data) return;

  // the entrance stagger is a one-off; page switches should be instant
  if (introSettled) {
    const frame = document.querySelector('.frame');
    if (frame) frame.classList.remove('entered');
  }

  const view = document.getElementById('view');
  view.innerHTML = (PAGES[S.page] || pageDashboard)();
  view.classList.toggle('long', S.page === 'settings');
  view.scrollTop = 0;

  if (S.page === 'dashboard' && introSettled !== false) loadRecent();
  if (S.page === 'transactions') loadTransactions();
  if (S.page === 'shared') { loadMembers(); loadPanelTx('sharedTx', S.sharedId); }
  if (S.page === 'cards') loadStatement();
  if (S.page === 'society') {
    const soc = accountsOfType('society').find(a => a.id === S.societyId) || accountsOfType('society')[0];
    if (soc) { loadPanelTx('societyTx', soc.id); loadPayroll(soc.owner); }
  }
}

async function boot() {
  introSettled = false;
  const showing = startIntro();

  if (showing) { await sleep(420); introStep('Verifying identity', 34); }
  chrome();

  if (showing) { await sleep(480); introStep('Loading accounts', 62); }
  render();

  // the dashboard fetches its own rows; wait for them so the bar means something
  if (showing) { await sleep(440); introStep('Fetching transactions', 84); }
  if (S.page === 'dashboard') await loadRecent();

  await finishIntro();
  setTimeout(() => { introSettled = true; }, 1100);
}

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function refresh() {
  const data = await post('nz_bank:getData', S.data ? S.data.context : 'bank');
  if (data && data.player) {
    S.data = data;
    chrome();
    render();
  }
}

async function loadRecent() {
  const res = await post('nz_bank:getTransactions', S.data.primary, 1, '', 'all');
  const box = document.getElementById('recent');
  if (!box) return;
  const fit = Math.max(2, Math.floor((box.clientHeight - 8) / 56));
  box.innerHTML = (res.rows && res.rows.length)
    ? res.rows.slice(0, fit).map(txRow).join('')
    : `<div class="empty">${ICON.none}<b>Nothing here yet</b><span>Your account activity will appear here.</span></div>`;
}

async function loadPanelTx(id, accountId) {
  if (!accountId) return;
  const res = await post('nz_bank:getTransactions', accountId, 1, '', 'all');
  const box = document.getElementById(id);
  if (!box) return;
  const fit = Math.max(2, Math.floor((box.clientHeight - 8) / 56));
  box.innerHTML = (res.rows && res.rows.length)
    ? res.rows.slice(0, fit).map(txRow).join('')
    : `<div class="empty">${ICON.none}<b>No activity yet</b><span>Movements will show up here.</span></div>`;
}

async function loadTransactions() {
  const acc = S.accountId || S.data.primary;
  const res = await post('nz_bank:getTransactions', acc, S.tx.page, S.tx.search, S.tx.category);
  // a timeout or server error returns {ok:false}; keep the page drawable instead of throwing on every render
  S.txResult = (res && Array.isArray(res.rows)) ? res
    : { rows: [], page: 1, pages: 1, total: 0, income: 0, spending: 0 };
  if (S.page === 'transactions') render2();
}

/* re-render the transactions page without re-triggering the fetch */
function render2() {
  const view = document.getElementById('view');
  view.innerHTML = pageTransactions();
}

async function loadPayroll(job) {
  if (!job) return;
  S.payrollData = await post('nz_bank:getPayroll', job);
  if (S.page === 'society') {
    const view = document.getElementById('view');
    view.innerHTML = pageSociety();
    const soc = accountsOfType('society').find(a => a.id === S.societyId);
    if (soc) loadPanelTx('societyTx', soc.id);
  }
}

async function loadStatement() {
  const card = visibleCards().find(c => c.id === S.selectedCard);
  if (!card || card.kind === 'debit') { S.statement = []; return; }
  const rows = await post('nz_bank:getStatement', card.id);
  S.statement = Array.isArray(rows) ? rows : [];
  if (S.page === 'cards') document.getElementById('view').innerHTML = pageCards();
}

async function loadMembers() {
  if (!S.sharedId) return;
  const rows = await post('nz_bank:getMembers', S.sharedId);
  S.members = Array.isArray(rows) ? rows : [];
  const acc = accountsOfType('shared').find(a => a.id === S.sharedId);
  if (acc && S.page === 'shared') {
    const view = document.getElementById('view');
    view.innerHTML = pageShared();
    loadPanelTx('sharedTx', S.sharedId);
  }
}

/* ═══════════════ EVENTS ═══════════════ */
document.getElementById('btnClose').addEventListener('click', closeUI);

document.querySelector('.side').addEventListener('click', (e) => {
  const nav = e.target.closest('.nav');
  if (!nav) return;
  S.page = nav.dataset.page;
  chrome();
  render();
});

document.getElementById('view').addEventListener('input', (e) => {
  const el = e.target;
  if (el.dataset.act === 'tx-search') {
    S.tx.search = el.value;
    S.tx.page = 1;
    clearTimeout(window._txT);
    window._txT = setTimeout(async () => {
      await loadTransactions();
      const input = document.querySelector('[data-act="tx-search"]');
      if (input) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
    }, 300);
  }
});

document.getElementById('view').addEventListener('change', async (e) => {
  const el = e.target;
  if (el.dataset.act === 'tx-category') { S.tx.category = el.value; S.tx.page = 1; loadTransactions(); }
  if (el.dataset.act === 'tx-account') { S.accountId = parseInt(el.value, 10); S.tx.page = 1; loadTransactions(); }
});

document.getElementById('view').addEventListener('click', async (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || S.busy) return;

  // a second click while the first is still in flight does nothing
  if (el.dataset.inflight === '1') return;
  el.dataset.inflight = '1';
  setTimeout(() => { delete el.dataset.inflight; }, 700);
  const act = el.dataset.act;
  const id = parseInt(el.dataset.id, 10);

  switch (act) {
    case 'goto':
      S.page = el.dataset.page; chrome(); render(); break;

    case 'deposit':
    case 'withdraw':
      if (el.dataset.account) S.accountId = parseInt(el.dataset.account, 10);
      amountModal(act); break;

    case 'transfer':
      if (el.dataset.account) S.accountId = parseInt(el.dataset.account, 10);
      transferModal(); break;

    case 'copy':
      copyText(el.dataset.value); break;

    case 'tx-page':
      S.tx.page = parseInt(el.dataset.page, 10); loadTransactions(); break;

    case 'bill-page':
      S.billPage = parseInt(el.dataset.page, 10); render(); break;

    case 'pay-page':
      S.payPage = parseInt(el.dataset.page, 10); render(); break;

    case 'society-select':
      S.societyId = id; S.payrollData = null; S.payPage = 1; render(); break;

    case 'wage-edit': wageModal(parseInt(el.dataset.grade, 10)); break;
    case 'member-card': memberCardModal(el.dataset.id, el.dataset.name); break;
    case 'trade-buy': tradeModal('buy', el.dataset.asset); break;
    case 'trade-sell': tradeModal('sell', el.dataset.asset); break;

    /* cards */
    case 'card-prev': S.cardIndex = Math.max(0, S.cardIndex - 1); render(); break;
    case 'card-next': S.cardIndex = Math.min(visibleCards().length - 1, S.cardIndex + 1); render(); break;
    case 'card-create':
    case 'card-order': cardOrderModal(); break;
    case 'card-select': S.selectedCard = id; S.statement = null; render(); break;
    case 'card-page': S.cardPage = parseInt(el.dataset.page, 10); render(); break;
    case 'card-pay': payCardModal(id); break;
    case 'number-change': numberChangeModal(); break;
    case 'card-delete': closeCardModal(); break;
    case 'card-settings': cardSettingsModal(); break;
    case 'card-pin': cardPinModal(); break;
    case 'card-block': await cardAction('block'); break;
    case 'card-unblock': await cardAction('unblock'); break;
    case 'card-replace': await cardAction('replace'); break;
    case 'card-report': confirmReportCard(); break;

    /* shared */
    case 'shared-select': S.sharedId = id; loadMembers(); break;
    case 'shared-create': sharedCreateModal(); break;
    case 'shared-rename': sharedRenameModal(); break;
    case 'shared-close': sharedCloseModal(); break;
    case 'member-add': {
      const input = document.querySelector('[data-act="member-id"]');
      const sid = input && input.value.trim();
      if (!sid) return toast('Not completed', 'Enter the server ID of an online player.', true);
      const res = await post('nz_bank:addMember', S.sharedId, sid);
      if (reply(res)) { input.value = ''; loadMembers(); }
      break;
    }
    case 'member-remove': memberRemoveModal(el.dataset.id, el.dataset.name); break;
    case 'member-perms': memberPermsModal(el.dataset.id); break;

    /* savings */
    case 'savings-open': {
      const res = await post('nz_bank:openSavings');
      if (reply(res)) refresh();
      break;
    }
    case 'savings-goal': savingsGoalModal(); break;

    /* loans */
    case 'loan-request': loanConfirmModal(el.dataset.tier); break;
    case 'loan-pay': loanPayModal(id); break;
    case 'loan-payoff': loanPayoffModal(id); break;
    case 'loan-settle': {
      const res = await post('nz_bank:settleDefault', S.data.loans.defaultedId || 0);
      if (reply(res, 'There is nothing to settle.')) refresh();
      break;
    }

    /* bills */
    case 'bill-pay': billPayModal(id); break;
    case 'bill-issue': billIssueModal(); break;

    /* scheduled */
    case 'sched-create': schedCreateModal(); break;
    case 'sched-toggle': {
      const res = await post('nz_bank:updateScheduled', id, 'toggle');
      if (reply(res)) refresh();
      break;
    }
    case 'sched-delete': {
      const res = await post('nz_bank:updateScheduled', id, 'delete');
      if (reply(res)) refresh();
      break;
    }

    /* settings */
    case 'toggle':
      S.data.settings[el.dataset.key] = !S.data.settings[el.dataset.key];
      el.classList.toggle('on');
      break;
    case 'settings-save': {
      const res = await post('nz_bank:saveSettings', S.data.settings);
      reply(res);
      break;
    }
    case 'payee-send': transferModal(el.dataset.number); break;
    case 'payee-delete': payeeDeleteModal(el.dataset.id); break;

    /* ── statements ── */
    case 'st-account':
      S.statementAccount = parseInt(el.dataset.id, 10);
      S.statementDoc = null;
      render();
      break;

    case 'st-period':
      S.statementPeriod = el.dataset.id;
      S.statementDoc = null;
      render();
      break;

    case 'st-clear':
      S.statementDoc = null;
      render();
      break;

    case 'st-pull': {
      el.disabled = true;
      el.textContent = 'Pulling…';
      try {
        const res = await post('nz_bank:accountStatement',
          S.statementAccount || S.data.primary,
          S.statementPeriod || 'week');

        if (!res || !res.ok) { reply(res); break; }
        S.statementDoc = res.statement;
        await refresh();
        render();
      } finally {
        if (el.isConnected) { el.disabled = false; el.textContent = 'Pull statement'; }
      }
      break;
    }

    /* ── overdraft ── */
    case 'overdraft': {
      el.disabled = true;
      const res = await post('nz_bank:setOverdraft', el.dataset.on === 'true');
      if (reply(res)) { await refresh(); render(); } else { el.disabled = false; }
      break;
    }
  }
});

/* ═══════════════ CARD FLOWS ═══════════════ */
function visibleCards() {
  return (S.data.cards || []).filter(c => {
    const a = account(c.account);
    return a && (a.type === 'personal' || a.type === 'shared' || a.type === 'society');
  });
}

function currentCard() {
  const cards = visibleCards();
  if (S.page === 'cards') return cards.find(c => c.id === S.selectedCard) || cards[0];
  return cards[S.cardIndex];
}

async function cardAction(action, value) {
  const card = currentCard();
  if (!card) return;
  const res = await post('nz_bank:updateCard', card.id, action, value);
  if (reply(res)) refresh();
  return res;
}

function cardOrderModal() {
  const skins = S.data.config.cardSkins;
  const types = S.data.config.cardTypes || [];
  const score = S.data.credit.score;

  const options = types.map(t => {
    const locked = score < (t.minCredit || 0);
    const detail = t.kind === 'secured' ? 'deposit backed'
      : t.kind === 'credit' ? money(t.creditLimit) + ' line'
      : 'from your account';
    return `<option value="${t.id}" ${locked ? 'disabled' : ''}>${esc(t.label)} · ${money(t.price)} · ${detail}${locked ? ' (needs ' + t.minCredit + ')' : ''}</option>`;
  }).join('');

  const first = types.find(t => score >= (t.minCredit || 0)) || types[0];

  openModal({
    title: 'Order a card',
    text: (first && first.blurb) || 'Pick the card that suits how you spend.',
    confirm: 'Order card',
    body: `
      <div class="field">
        <label>Card type</label>
        <select data-name="type" data-act="card-type">${options}</select>
      </div>
      <div class="field">
        <label>Account</label>
        <select data-name="account">${accountOptions(S.data.primary, a => a.type !== 'savings')}</select>
      </div>
      <div class="field"><label>Choose a PIN</label>
        <input data-name="pin" type="password" inputmode="numeric" maxlength="4" placeholder="4 digits"></div>
      ${stylePicker(first ? first.id : 'debit', skins[0])}
      <div class="field" id="depositField" style="display:${first && first.kind === 'secured' ? 'flex' : 'none'}">
        <label>Security deposit — this becomes your credit limit</label>
        <input data-name="deposit" type="number" placeholder="${first && first.deposit ? first.deposit.min : 2500}"
          value="${first && first.deposit ? first.deposit.min : ''}">
      </div>`,
    onConfirm: async (v) => {
      if (!/^\d{4}$/.test(v.pin || '')) return notify('Not completed', 'The PIN must be 4 digits.', 'error');
      const res = await post('nz_bank:createCard', parseInt(v.account, 10), v.pin, v.skin, null,
        v.type, parseInt(v.deposit, 10) || 0);
      closeModal();
      if (reply(res)) { S.statement = null; refresh(); }
    }
  });
}

function payCardModal(cardId) {
  const card = visibleCards().find(c => c.id === cardId) || currentCard();
  if (!card || card.kind === 'debit') return;

  const steps = [card.minPay, Math.round(card.balance / 2), card.balance].filter(v => v > 0);

  openModal({
    title: `Pay your ${card.typeLabel}`,
    text: card.minPay > 0
      ? `${money(card.minPay)} is due in ${card.dueIn} minutes. ${money(card.balance)} is owed in total.`
      : `${money(card.balance)} is owed. Paying early keeps interest off it.`,
    confirm: 'Pay card',
    body: `
      <div class="field"><label>Pay from</label>
        <select data-name="account">${accountOptions(S.data.primary, a => a.can.withdraw)}</select></div>
      <div class="field"><label>Amount</label>
        <input data-name="amount" type="number" min="1" value="${card.minPay || card.balance}"></div>
      <div class="quick">
        ${card.minPay > 0 ? `<button data-fill="${card.minPay}">Minimum</button>` : ''}
        <button data-fill="${Math.round(card.balance / 2)}">Half</button>
        <button data-fill="${card.balance}">Everything</button>
      </div>`,
    onConfirm: async (v) => {
      const amount = parseInt(v.amount, 10);
      if (!amount || amount <= 0) return toast('Not completed', 'Enter an amount above zero.', true);
      const res = await post('nz_bank:payCard', card.id, amount, parseInt(v.account, 10));
      closeModal();
      if (reply(res)) { S.statement = null; refresh(); }
    }
  });
}

function numberChangeModal() {
  const acc = account(S.data.primary);
  const cost = S.data.config.numberChangeCost || 0;

  openModal({
    title: 'Reissue your account number',
    text: cost > 0
      ? `A new number costs ${money(cost)}. Anyone holding the old one can no longer send to it, and your own scheduled transfers are moved across.`
      : 'Anyone holding the old number can no longer send to it. Your own scheduled transfers are moved across.',
    confirm: 'Reissue it',
    danger: true,
    cancel: 'Keep it',
    onConfirm: async () => {
      const res = await post('nz_bank:changeNumber', acc.id);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function closeCardModal() {
  const card = currentCard();
  if (!card) return;
  openModal({
    title: `Close this ${card.typeLabel || 'card'}?`,
    text: card.deposit > 0
      ? `Your ${money(card.deposit)} deposit comes back once the balance is clear.`
      : 'The card stops working immediately and cannot be brought back.',
    confirm: 'Close card',
    cancel: 'Keep it',
    danger: true,
    onConfirm: async () => {
      const res = await post('nz_bank:updateCard', card.id, 'delete');
      closeModal();
      if (reply(res)) { S.selectedCard = null; S.statement = null; refresh(); }
    }
  });
}

function cardSettingsModal() {
  const card = currentCard();
  if (!card) return;
  const limits = S.data.config.cardLimits;
  const skins = S.data.config.cardSkins;

  openModal({
    title: 'Card settings',
    text: 'Limits apply per day and reset at midnight.',
    confirm: 'Save card',
    body: `
      <div class="field">
        <label>Daily spend limit</label>
        <select data-name="limit">${limits.map(l =>
          `<option value="${l}" ${l === card.limit ? 'selected' : ''}>${money(l)}</option>`).join('')}</select>
      </div>
      ${stylePicker(card.type, card.skin)}
      <div class="sw-line">
        <div><b>Express pay</b><span>Skip the PIN on payments under ${money(2500)}.</span></div>
        <input type="checkbox" data-name="express" ${card.express ? 'checked' : ''}>
      </div>`,
    onConfirm: async (v) => {
      // only what changed, so a feature switched off server-side
      // (express pay) does not fail a save that never touched it
      const steps = [
        ['limit', parseInt(v.limit, 10), card.limit],
        ['skin', v.skin, card.skin],
        ['express', !!v.express, !!card.express]
      ].filter(([, value, was]) => value !== was);
      // stop at the first one the bank turns down and say why
      for (const [action, value] of steps) {
        const res = await post('nz_bank:updateCard', card.id, action, value);
        if (!res || !res.ok) {
          closeModal();
          reply(res);
          return refresh();
        }
      }
      closeModal();
      toast('Saved', 'Card settings updated.');
      refresh();
    }
  });
}

function cardPinModal() {
  const card = currentCard();
  if (!card) return;
  openModal({
    title: 'Change your PIN',
    text: 'You will need the new PIN at every ATM and payment terminal.',
    confirm: 'Set PIN',
    body: `<div class="field"><label>New PIN</label>
      <input data-name="pin" type="password" inputmode="numeric" maxlength="4" placeholder="4 digits"></div>`,
    onConfirm: async (v) => {
      if (!/^\d{4}$/.test(v.pin || '')) return toast('Not completed', 'The PIN must be 4 digits.', true);
      const res = await post('nz_bank:updateCard', card.id, 'pin', v.pin);
      closeModal();
      reply(res);
    }
  });
}

function confirmReportCard() {
  const card = currentCard();
  if (!card) return;
  openModal({
    title: 'Report this card lost?',
    text: 'The card stops working straight away and cannot be unfrozen. You can order a replacement afterwards.',
    confirm: 'Report it',
    cancel: 'Keep card',
    danger: true,
    onConfirm: async () => {
      const res = await post('nz_bank:reportCard', card.id);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

/* ═══════════════ SHARED FLOWS ═══════════════ */
function sharedCreateModal() {
  openModal({
    title: 'Open a shared account',
    text: `Opening one costs ${money(S.data.config.sharedCost)} from your personal account.`,
    confirm: 'Open account',
    body: `<div class="field"><label>Account name</label>
      <input data-name="label" maxlength="32" placeholder="Diablo Biker Club"></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_bank:createShared', v.label);
      closeModal();
      if (reply(res)) { S.sharedId = res.id; refresh(); }
    }
  });
}

function sharedRenameModal() {
  const acc = accountsOfType('shared').find(a => a.id === S.sharedId);
  if (!acc) return;
  openModal({
    title: 'Rename this account',
    confirm: 'Save name',
    body: `<div class="field"><label>Account name</label>
      <input data-name="label" maxlength="32" value="${esc(acc.label)}"></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_bank:renameAccount', S.sharedId, v.label);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function sharedCloseModal() {
  const acc = accountsOfType('shared').find(a => a.id === S.sharedId);
  if (!acc) return;
  openModal({
    title: `Close ${acc.label}?`,
    text: 'Everyone loses access and the remaining balance moves to your personal account.',
    confirm: 'Close account',
    cancel: 'Keep it open',
    danger: true,
    onConfirm: async () => {
      const res = await post('nz_bank:closeShared', S.sharedId);
      closeModal();
      if (reply(res)) { S.sharedId = null; refresh(); }
    }
  });
}

function memberRemoveModal(identifier, name) {
  openModal({
    title: `Remove ${name}?`,
    text: 'They lose access to this account immediately.',
    confirm: 'Remove',
    cancel: 'Keep them',
    danger: true,
    onConfirm: async () => {
      const res = await post('nz_bank:removeMember', S.sharedId, identifier);
      closeModal();
      if (reply(res)) loadMembers();
    }
  });
}

function memberPermsModal(identifier) {
  const m = S.members.find(x => x.identifier === identifier);
  if (!m) return;
  openModal({
    title: `What ${m.name} can do`,
    text: 'Deposits are usually safe to allow. Withdrawals and transfers move money out.',
    confirm: 'Save permissions',
    body: `
      <div class="sw-line"><div><b>Deposit</b><span>Put money into the account.</span></div>
        <input type="checkbox" data-name="deposit" ${m.can_deposit ? 'checked' : ''}></div>
      <div class="sw-line"><div><b>Withdraw</b><span>Take cash out of the account.</span></div>
        <input type="checkbox" data-name="withdraw" ${m.can_withdraw ? 'checked' : ''}></div>
      <div class="sw-line"><div><b>Transfer</b><span>Send money to other accounts.</span></div>
        <input type="checkbox" data-name="transfer" ${m.can_transfer ? 'checked' : ''}></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_bank:setMemberPerms', S.sharedId, identifier, {
        deposit: !!v.deposit, withdraw: !!v.withdraw, transfer: !!v.transfer
      });
      closeModal();
      if (reply(res)) loadMembers();
    }
  });
}

/* ═══════════════ SAVINGS / LOAN / BILL / SCHEDULE FLOWS ═══════════════ */
function savingsGoalModal() {
  openModal({
    title: 'Set a savings goal',
    text: 'The goal is a marker for you — money is never locked away.',
    confirm: 'Save goal',
    body: `<div class="field"><label>Target amount</label>
      <input data-name="amount" type="number" min="0" placeholder="0"
        value="${S.data.savings.goal || ''}"></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_bank:setSavingsGoal', parseInt(v.amount, 10) || 0);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function loanConfirmModal(tierId) {
  const t = S.data.config.loanTiers.find(x => x.id === tierId);
  if (!t) return;
  const owed = Math.round(t.amount * (1 + t.interest));
  openModal({
    title: `Take the ${t.label} loan?`,
    text: `${money(t.amount)} lands in your account now. You repay ${money(owed)} in instalments of ${money(t.payment)}.`,
    confirm: 'Take the loan',
    onConfirm: async () => {
      const res = await post('nz_bank:requestLoan', tierId);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function loanPayModal(loanId) {
  const loan = S.data.loans.active.find(l => l.id === loanId);
  if (!loan) return;
  openModal({
    title: 'Make a payment',
    text: `${money(loan.remaining)} left on this loan.`,
    confirm: 'Pay',
    body: `<div class="field"><label>Amount</label>
        <input data-name="amount" type="number" min="1" value="${loan.payment}"></div>
      <div class="quick">
        <button data-fill="${loan.payment}">Instalment</button>
        <button data-fill="${Math.round(loan.remaining / 2)}">Half</button>
        <button data-fill="${loan.remaining}">Everything</button>
      </div>`,
    onConfirm: async (v) => {
      const amount = parseInt(v.amount, 10);
      if (!(amount > 0)) return toast('Not completed', 'Enter an amount above zero.', true);
      const res = await post('nz_bank:payLoan', loanId, amount);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function loanPayoffModal(loanId) {
  const loan = S.data.loans.active.find(l => l.id === loanId);
  if (!loan) return;
  openModal({
    title: 'Pay this loan off?',
    text: `Clearing it early trims part of the remaining interest. ${money(loan.remaining)} is outstanding.`,
    confirm: 'Pay it off',
    onConfirm: async () => {
      const res = await post('nz_bank:payOffLoan', loanId);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function billPayModal(billId) {
  const bill = S.data.bills.rows.find(b => b.id === billId);
  if (!bill) return;
  openModal({
    title: `Pay ${bill.issuer_label}?`,
    text: `${bill.reason} — ${money(bill.amount)}`,
    confirm: 'Pay bill',
    body: `<div class="field"><label>Pay from</label>
      <select data-name="account">${accountOptions(S.data.primary, a => a.can.withdraw)}</select></div>`,
    onConfirm: async (v) => {
      const res = await post('nz_bank:payBill', billId, parseInt(v.account, 10));
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function billIssueModal() {
  openModal({
    title: 'Issue a bill',
    text: 'The money lands in your society account once the bill is paid.',
    confirm: 'Send bill',
    body: `
      <div class="field row2">
        <div class="field"><label>Server ID</label><input data-name="target" placeholder="e.g. 42"></div>
        <div class="field"><label>Amount</label><input data-name="amount" type="number" min="1" placeholder="0"></div>
      </div>
      <div class="field"><label>What is it for</label>
        <input data-name="reason" maxlength="60" placeholder="Repairs on a Sultan"></div>`,
    onConfirm: async (v) => {
      const amount = parseInt(v.amount, 10);
      if (!amount || amount <= 0) return toast('Not completed', 'Enter an amount above zero.', true);
      const res = await post('nz_bank:issueBill', v.target, amount, v.reason);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function schedCreateModal() {
  const intervals = S.data.config.intervals;
  openModal({
    title: 'New scheduled transfer',
    text: 'It pauses itself if the money is not there three times in a row.',
    confirm: 'Schedule it',
    body: `
      <div class="field"><label>From</label>
        <select data-name="account">${accountOptions(S.data.primary, a => a.can.transfer)}</select></div>
      <div class="field"><label>To account number</label>
        <input data-name="to" placeholder="NZB-PSL-XXXXXXXX"></div>
      <div class="field row2">
        <div class="field"><label>Amount</label><input data-name="amount" type="number" min="1" placeholder="0"></div>
        <div class="field"><label>How often</label>
          <select data-name="interval">${intervals.map(i => `<option value="${i.id}">${esc(i.label)}</option>`).join('')}</select></div>
      </div>
      <div class="field"><label>Name it</label><input data-name="label" maxlength="32" placeholder="Garage rent"></div>`,
    onConfirm: async (v) => {
      const amount = parseInt(v.amount, 10);
      if (!amount || amount <= 0) return toast('Not completed', 'Enter an amount above zero.', true);
      const res = await post('nz_bank:createScheduled', parseInt(v.account, 10), (v.to || '').trim(),
        amount, v.label, v.interval);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function wageModal(grade) {
  const p = S.payrollData || S.data.payroll;
  const soc = accountsOfType('society').find(a => a.id === S.societyId);
  const row = p && p.rows.find(r => r.grade === grade);
  if (!row) return;

  openModal({
    title: `Wage for ${row.label}`,
    text: `Paid out of the society account to everyone on this grade. Cap is ${money(p.maxWage)}.`,
    confirm: 'Save wage',
    body: `
      <div class="field row2">
        <div class="field"><label>Amount per payment</label>
          <input data-name="amount" type="number" min="0" max="${p.maxWage}" value="${row.amount}"></div>
        <div class="field"><label>How often</label>
          <select data-name="interval">
            ${(p.intervals || []).map(i =>
              `<option value="${i.id}" ${i.id === row.interval ? 'selected' : ''}>${esc(i.label)}</option>`).join('')}
          </select></div>
      </div>
      <div class="sw-line"><div><b>Paying</b><span>Turn off to pause this grade without losing the amount.</span></div>
        <input type="checkbox" data-name="enabled" ${row.enabled ? 'checked' : ''}></div>`,
    onConfirm: async (v) => {
      // 0 is a real wage (the server allows it); an emptied field is not
      const amount = parseInt(v.amount, 10);
      if (String(v.amount || '').trim() === '' || !(amount >= 0)) {
        return toast('Not completed', 'Enter a wage, or 0 to pay nothing.', true);
      }
      if (amount > p.maxWage) return toast('Not completed', `The most a wage can be is ${money(p.maxWage)}.`, true);
      const res = await post('nz_bank:setPayroll', grade, amount, v.interval,
        !!v.enabled, soc && soc.owner);
      closeModal();
      if (reply(res)) { S.payrollData = null; refresh(); }
    }
  });
}

function memberCardModal(identifier, name) {
  const skins = S.data.config.cardSkins;
  openModal({
    title: `Issue a card to ${name}`,
    text: `They get their own card on this account with a ${money(S.data.config.jointCardLimit)} daily limit. It costs ${money(S.data.config.cardPrice)} from the account.`,
    confirm: 'Issue card',
    body: `
      <div class="field"><label>Starting PIN</label>
        <input data-name="pin" type="password" inputmode="numeric" maxlength="4" placeholder="4 digits"></div>
      ${stylePicker('debit', skins[0])}`,
    onConfirm: async (v) => {
      if (!/^\d{4}$/.test(v.pin || '')) return notify('Not completed', 'The PIN must be 4 digits.', 'error');
      const res = await post('nz_bank:createCard', S.sharedId, v.pin, v.skin, identifier, 'debit', 0);
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

function tradeModal(side, assetId) {
  const m = S.data.market;
  const a = m && (m.assets || []).find(x => x.id === assetId);
  if (!a) return notify('Not completed', 'The market is not available right now.', 'error');
  const held = (m.holdings || []).find(h => h.asset === assetId);
  const buying = side === 'buy';

  if (!buying && !held) return notify('Not completed', `You hold no ${a.label}.`, 'error');

  const steps = buying ? [1000, 5000, 25000] : [Math.round(held.value / 2), held.value];

  openModal({
    title: `${buying ? 'Buy' : 'Sell'} ${a.label}`,
    text: buying
      ? `${money(a.price)} per unit. A ${(m.fee * 100).toFixed(0)}% fee is added on top.`
      : `You hold ${held.units.toFixed(4)} worth ${money(held.value)}. A ${(m.fee * 100).toFixed(0)}% fee comes off the sale.`,
    confirm: buying ? 'Place buy order' : 'Place sell order',
    body: `
      <div class="field"><label>${buying ? 'Spend from' : 'Pay into'}</label>
        <select data-name="account">${accountOptions(S.data.primary, x => x.type !== 'society')}</select></div>
      <div class="field"><label>Amount in ${cur()}</label>
        <input data-name="amount" type="number" min="${m.minTrade}" placeholder="0"></div>
      <div class="quick">${steps.map(v => `<button data-fill="${v}">${money(v)}</button>`).join('')}</div>`,
    onConfirm: async (v) => {
      const amount = parseInt(v.amount, 10);
      if (!amount || amount <= 0) return notify('Not completed', 'Enter an amount above zero.', 'error');
      // the server quietly sells everything for an amount over the position
      if (!buying && amount > Math.ceil(held.value)) {
        return notify('Not completed', `You only hold ${money(held.value)}.`, 'error');
      }
      const res = await post('nz_bank:trade', side, assetId, amount, parseInt(v.account, 10));
      closeModal();
      if (reply(res)) refresh();
    }
  });
}

/* keep the clock ticking */
setInterval(() => {
  if (!document.body.classList.contains('up') || !S.data) return;
  const now = new Date();
  const el = document.getElementById('clock');
  if (el) el.textContent = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}, 15000);
