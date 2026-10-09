/* ═══════════════════════════════════════════════════════════
   NAYZEEE BANKING — in-world ATM screen (DUI)

   This file is a pure renderer. It has no cursor, no click handler
   and no way to reach Lua — the client decides which of the
   machine's own buttons is being looked at and sends it here to
   light up. Every press, PIN digit and confirmation is handled in
   Lua, which also means none of it is reachable from the player's
   console, and the PIN itself never exists in the browser.
   ═══════════════════════════════════════════════════════════ */

const A = {
  view: 'boot',
  currency: '$',
  currencyRight: false,
  sides: {},
  hover: null
};

/* ═══════════════════════════════════════════════════════════
   WHERE THE PAGE LANDS ON THE TEXTURE

   These prop textures are atlases — the screen face is only a patch
   of the sheet. Drawing the page across the whole sheet is what makes
   it come out squashed and off to one side. Lua sends the patch and
   the page scales itself into it, so no layout has to know.
   ═══════════════════════════════════════════════════════════ */
function applyIsland(island, outside) {
  const box = el('island');
  if (!box) return;

  if (outside) document.body.style.background = outside;

  const i = island || { x: 0, y: 0, w: 1, h: 1 };
  const full = !i || (i.x === 0 && i.y === 0 && i.w === 1 && i.h === 1);

  if (full) {
    box.style.transform = '';
    box.style.width = '';
    box.style.height = '';
    return;
  }

  // The page keeps its own pixel size and is scaled down into the
  // patch, so type stays crisp rather than being laid out tiny.
  box.style.width = '100vw';
  box.style.height = '100vh';
  box.style.transformOrigin = 'top left';
  box.style.transform =
    `translate(${(i.x * 100).toFixed(3)}vw, ${(i.y * 100).toFixed(3)}vh) ` +
    `scale(${i.w.toFixed(4)}, ${i.h.toFixed(4)})`;
}

/* ── helpers ──────────────────────────────────────────────── */
const money = (n) => {
  const v = Math.round(n || 0).toLocaleString('en-US').replace(/,/g, ' ');
  return A.currencyRight ? `${v}${A.currency}` : `${A.currency}${v}`;
};

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const el = (id) => document.getElementById(id);

function hexToRgb(hex) {
  const h = String(hex || '').replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
  const n = parseInt(full, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** Same accent contract as the main UI, so one config repaints both. */
function applyTheme(ui) {
  if (!ui) return;
  const root = document.documentElement.style;
  const [r, g, b] = hexToRgb(ui.accent);

  root.setProperty('--teal', ui.accent);
  root.setProperty('--teal-hi', ui.accentLight || ui.accent);
  root.setProperty('--teal-lo', ui.accentDark || ui.accent);
  root.setProperty('--teal-wash', `rgba(${r},${g},${b},.14)`);
  root.setProperty('--teal-edge', `rgba(${r},${g},${b},.4)`);

  if (ui.danger) {
    const [dr, dg, db] = hexToRgb(ui.danger);
    root.setProperty('--red', ui.danger);
    root.setProperty('--red-wash', `rgba(${dr},${dg},${db},.14)`);
  }

  // Every place the logo can appear. A file that will not load takes
  // the wordmark back, so a missing or broken logo costs nothing.
  const swap = (imgId, markId) => {
    const img = el(imgId), mark = el(markId);
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

  swap('homeLogo', 'homeBrand');
  swap('stLogo', 'stBrand');

  const logo = el('bootLogo');
  const mark = el('bootMark');
  if (ui.logo && String(ui.logo).trim() !== '') {
    logo.src = ui.logo;
    logo.onload = () => { logo.classList.remove('hidden'); mark.classList.add('hidden'); };
    logo.onerror = () => { logo.classList.add('hidden'); mark.classList.remove('hidden'); };
  } else {
    logo.classList.add('hidden');
    mark.classList.remove('hidden');
  }
}

/* ── view switching ───────────────────────────────────────── */
/* Views cross-fade, which means each change leaves timers running. A
   second change arriving mid-fade used to leave the first one's timer
   to fire afterwards and re-show a view that had already been replaced
   — a "Processing" overlay stranded on top of the finished screen,
   with nothing left to clear it.

   Two rules keep that from happening: a new transition cancels any
   still pending, and the step that actually reveals a view takes every
   other one down first. Whatever the timing, exactly one view is up. */
let pending = [];

function show(name) {
  if (A.view === name) return;

  const next = document.querySelector(`.view[data-view="${name}"]`);
  if (!next) return;

  pending.forEach(clearTimeout);
  pending = [];

  const current = document.querySelector('.view.up');
  const changing = current && current !== next;

  if (changing) {
    current.classList.add('out');
    pending.push(setTimeout(() => current.classList.remove('up', 'out'), 180));
  }

  pending.push(setTimeout(() => {
    document.querySelectorAll('.view').forEach(v => {
      if (v !== next) v.classList.remove('up', 'out');
    });

    next.classList.remove('out');
    next.classList.add('up');

  }, changing ? 140 : 0));

  A.view = name;
}

/* ═══════════════════════════════════════════════════════════
   THE MACHINE'S SIDE BUTTONS

   Four down each edge of the glass, matching the four moulded into
   the prop. Lua says which of them mean something on this screen and
   what to call them; the page just prints the labels beside the real
   buttons and lights one up when Lua says it is being looked at.

   The page has no idea a camera or a crosshair exists.
   ═══════════════════════════════════════════════════════════ */
const SLOTS = ['1', '2', '3', '4'];

function renderSides(sides) {
  A.sides = sides || {};

  ['l', 'r'].forEach(side => {
    const rail = el(side === 'l' ? 'railL' : 'railR');
    if (!rail) return;

    rail.innerHTML = SLOTS.map(n => {
      const id = `side_${side}${n}`;
      const entry = A.sides[id];
      if (!entry) return `<i class="slot" data-id="${id}"></i>`;

      return `<i class="slot live ${A.hover === id ? 'hot' : ''}" data-id="${id}">
        <b>${esc(entry.label)}</b></i>`;
    }).join('');
  });
}

/** Lua tells us which physical button is under the crosshair. */
function highlight(id) {
  A.hover = id || null;
  document.querySelectorAll('.rail .slot').forEach(n =>
    n.classList.toggle('hot', n.dataset.id === A.hover));

  const pad = el('padHint');
  if (pad) pad.classList.toggle('hot', !!(A.hover && A.hover.startsWith('pin_')));
}

/* ── renderers ────────────────────────────────────────────── */
function renderPin(length, error) {
  const dots = el('pinDots');
  [...dots.children].forEach((d, i) => d.classList.toggle('on', i < (length || 0)));

  el('pinErr').textContent = error || '';
  if (error) {
    dots.classList.remove('shake');
    void dots.offsetWidth;
    dots.classList.add('shake');
  }
}

function renderHome(d) {
  el('homeBrand').textContent = (d.serverName || 'Banking').toUpperCase();
  el('homeBalance').textContent = money(d.balance);
  el('homeCardType').textContent = (d.cardType || 'Debit Card').toUpperCase();

  const last = String(d.cardNumber || '').slice(-4) || '••••';
  el('homeCardNo').textContent = `•••• •••• •••• ${last}`;

  // an overdrawn balance says so, rather than just showing a minus
  const bal = el('homeBalance');
  bal.classList.toggle('negative', (d.balance || 0) < 0);

  const od = el('homeOverdraft');
  if (d.overdraft && d.overdraft.on && (d.balance || 0) < 0) {
    od.textContent = `${money(d.overdraft.available)} of your overdraft left`;
    od.classList.remove('hidden');
  } else if (d.overdraft && d.overdraft.on) {
    od.textContent = `${money(d.overdraft.available)} overdraft available`;
    od.classList.remove('hidden');
  } else {
    od.classList.add('hidden');
  }
}

/* ── statement ──────────────────────────────────────────────
   The screen shows the summary and the most recent lines. The
   paper coming out of the slot is the full thing.
   ────────────────────────────────────────────────────────── */
function renderStatement(st) {
  if (!st) return;

  el('stPeriod').textContent = st.period ? st.period.label : '';
  el('stAccount').textContent = '•••• ' + String(st.account.number || '').slice(-4);
  el('stOpen').textContent = money(st.opening);
  el('stClose').textContent = money(st.closing);
  el('stIn').textContent = money(st.income);
  el('stOut').textContent = money(st.spending);

  const recent = (st.rows || []).slice(-6).reverse();
  el('stRows').innerHTML = recent.length
    ? recent.map(r => `
        <div class="st-row">
          <div class="txt"><b>${esc(r.label)}</b><span>${esc(r.stamp)}</span></div>
          <div class="amt ${r.direction === 'in' ? 'in' : ''}">
            ${r.direction === 'in' ? '+' : '−'}${money(r.amount)}</div>
        </div>`).join('')
    : '<div class="st-empty">No movement in this period</div>';
}

function renderAmount(d) {
  el('amountLabel').textContent = d.mode === 'deposit' ? 'Cash on hand' : 'Current Balance';
  el('amountBalance').textContent = money(d.mode === 'deposit' ? d.cash : d.balance);

  const input = el('amountInput');
  const raw = d.amount || '';
  input.textContent = raw === '' ? '0' : money(parseInt(raw, 10) || 0);
  input.classList.toggle('empty', raw === '');

  el('amountQuick').innerHTML = (d.quick || [])
    .map(v => `<b>${money(v)}</b>`).join('');
}

function renderTransfer(d) {
  const to = el('transferTo');
  to.textContent = d.to && d.to !== '' ? d.to : '—';
  to.classList.toggle('empty', !d.to || d.to === '');

  const amt = el('transferAmount');
  const raw = d.amount || '';
  amt.textContent = raw === '' ? '0' : money(parseInt(raw, 10) || 0);
  amt.classList.toggle('empty', raw === '');

  el('transferHint').textContent = d.stage === 'amount'
    ? 'Type the amount, then press ENTER'
    : 'Type the account number, then press ENTER';
}

function renderDone(d) {
  const badge = el('doneBadge');
  badge.classList.toggle('bad', !d.ok);
  badge.innerHTML = d.ok
    ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5 9 17.5 20 6.5"/></svg>'
    : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 8v6M12 17.4v.01"/><circle cx="12" cy="12" r="9"/></svg>';

  el('doneTitle').textContent = d.title || (d.ok ? 'Done' : 'Declined');
  el('doneText').textContent = d.text || '';
  el('doneBalance').textContent = money(d.balance);
}

/* There is no cursor on this screen and no way back to Lua from it.
   The machine's own buttons are the interface: Lua works out which
   one is under the crosshair and tells this page which to light. */

/* ── message bridge ───────────────────────────────────────── */
window.addEventListener('message', (e) => {
  const m = e.data || {};

  switch (m.action) {
    case 'init':
      A.currency = m.currency || '$';
      A.currencyRight = !!m.currencyRight;
      applyTheme(m.ui);
      el('bootName').textContent = (m.serverName || 'Banking').toUpperCase();
      applyIsland(m.island, m.outside);
      show('boot');
      break;

    case 'view':
      show(m.view);
      break;

    case 'pin':
      renderPin(m.length, m.error);
      break;

    case 'home':
      renderHome(m);
      show('home');
      break;

    case 'statement':
      renderStatement(m.statement);
      show('statement');
      break;

    case 'amount':
      renderAmount(m);
      show('amount');
      break;

    case 'transfer':
      renderTransfer(m);
      show('transfer');
      break;

    case 'busy':
      el('busyText').textContent = m.text || 'Processing';
      show('busy');
      break;

    case 'done':
      renderDone(m);
      show('done');
      break;

    case 'hover':
      highlight(m.button);
      break;

    case 'sides':
      renderSides(m.sides);
      break;

    case 'island':
      applyIsland(m.island);
      break;
  }
});
