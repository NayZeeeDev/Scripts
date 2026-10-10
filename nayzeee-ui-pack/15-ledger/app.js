/* 15 · LEDGER — society / boss management
   SendNUIMessage({ action = 'open', data = {
     society   = { label = 'Hayes Autos', sub = 'Business · Little Bighorn Ave', balance = 1284560 },
     me        = 'Marcus Hale',                       -- optional, shown as "by" on local deposits / withdrawals
     employees = { { cid = 'HXL20481', name = 'Marcus Hale', grade = 4, onDuty = true, hired = 1741781000 } },
                 -- hired: unix seconds or a ready string; optional salary = 1200 overrides the grade salary
     grades    = { { grade = 0, label = 'Apprentice', salary = 650 } },   -- salary = weekly pay
     history   = { { amount = -2400, label = 'Parts order', by = 'Luis Ortega', time = 1760090000 } },
                 -- newest first; amount > 0 is income; time: unix seconds or a ready string
     chart     = { { day = '27 Sep', income = 18200, expense = 9400 } },  -- oldest → newest, 14 entries
   } })
   SendNUIMessage({ action = 'update', data = { society = { balance = 1290000 }, history = { ... } } })
                 -- any subset of the open keys; arrays replace, society merges
   SendNUIMessage({ action = 'close' })

   Callbacks — the UI applies each change straight away. Reply cb({ ok = false, error = '...' })
   to roll it back, or cb({ employees = ..., society = ... }) / send 'update' with the real data.
     hire       { id = 14, grade = 0 }            -- player server ID
     fire       { cid = 'HXL20481' }
     setGrade   { cid = 'HXL20481', grade = 2 }
     deposit    { amount = 5000 }
     withdraw   { amount = 5000 }
     saveGrades { grades = { { grade = 0, label = 'Apprentice', salary = 650 }, ... } }
     close
*/
NZ.addIcons({
  'user-plus': '<circle cx="10" cy="8" r="3.5"/><path d="M3.5 20a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6"/>',
  'user-x': '<circle cx="10" cy="8" r="3.5"/><path d="M3.5 20a6.5 6.5 0 0 1 13 0M16.5 8.5l5 5M21.5 8.5l-5 5"/>',
  dep: '<path d="M12 3v11M7.5 9.5 12 14l4.5-4.5"/><path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>',
  wd: '<path d="M12 14V3M7.5 7.5 12 3l4.5 4.5"/><path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>',
  'trend-up': '<path d="m3 17 6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
  'trend-down': '<path d="m3 7 6 6 4-4 8 8"/><path d="M15 17h6v-6"/>',
});

const app = NZ.$('#app');
const S = { society: { label: '', sub: '', balance: 0 }, me: '', employees: [], grades: [], history: [], chart: [] };
let tab = 'overview', empQ = '', empF = 'all', mode = 'deposit', txF = 'all', txQ = '';
let draft = [], dirty = false;

/* ── helpers ── */
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const pad = n => String(n).padStart(2, '0');
const toMs = t => (typeof t === 'number' && isFinite(t)) ? (t < 1e12 ? t * 1000 : t) : null;
function fmtTime(t) {
  const ms = toMs(t); if (ms == null) return String(t ?? '');
  const d = new Date(ms), now = new Date();
  const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const day0 = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  if (ms >= day0) return `Today ${hm}`;
  if (ms >= day0 - 864e5) return `Yesterday ${hm}`;
  return `${d.getDate()} ${MON[d.getMonth()]} ${hm}`;
}
function fmtDate(t) {
  const ms = toMs(t); if (ms == null) return String(t ?? '—');
  const d = new Date(ms); return `${d.getDate()} ${MON[d.getMonth()]} ${d.getFullYear()}`;
}
const shortMoney = n => {
  const a = Math.abs(n), s = n < 0 ? '-' : '';
  if (a >= 1e6) return `${s}$${+(a / 1e6).toFixed(1)}M`;
  if (a >= 1e3) return `${s}$${+(a / 1e3).toFixed(1)}k`;
  return `${s}$${a}`;
};
const signed = n => (n > 0 ? '+' : n < 0 ? '−' : '') + NZ.money(Math.abs(n));
const num = v => { const n = parseInt(String(v).replace(/[^\d]/g, ''), 10); return isNaN(n) ? 0 : n; };
const arr = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
const grades = () => [...S.grades].sort((a, b) => a.grade - b.grade);
const gradeOf = g => S.grades.find(x => +x.grade === +g);
const payOf = e => e.salary != null ? +e.salary : +(gradeOf(e.grade)?.salary || 0);
const topGrade = () => S.grades.reduce((m, g) => Math.max(m, +g.grade), -Infinity);
const payroll = () => S.employees.reduce((s, e) => s + payOf(e), 0);

/* ── tabs ── */
function moveInk() {
  const b = NZ.$(`#tabs [data-tab="${tab}"]`), ink = NZ.$('#ink');
  if (!b) return;
  ink.style.left = b.offsetLeft + 'px';
  ink.style.width = b.offsetWidth + 'px';
}
function setTab(t) {
  tab = t;
  NZ.$$('#tabs [data-tab]').forEach(b => b.classList.toggle('on', b.dataset.tab === t));
  NZ.$$('.pane').forEach(p => p.classList.toggle('on', p.dataset.pane === t));
  moveInk();
  if (t === 'overview') drawChart();
}
NZ.$$('#tabs [data-tab]').forEach(b => b.onclick = () => setTab(b.dataset.tab));
NZ.$$('[data-goto]').forEach(b => b.onclick = () => setTab(b.dataset.goto));

/* ── header + overview ── */
function renderHead() {
  NZ.$('#soc-label').textContent = S.society.label || 'Society';
  NZ.$('#soc-sub').textContent = S.society.sub || '';
  NZ.$('#mini-bal').textContent = NZ.money(S.society.balance || 0);
  NZ.$('#t-emp').textContent = S.employees.length;
}

function renderOverview() {
  const bal = +S.society.balance || 0;
  const big = NZ.$('#ov-bal');
  big.classList.toggle('neg', bal < 0);
  big.innerHTML = `<span class="cur">${bal < 0 ? '−$' : '$'}</span>${Math.abs(Math.round(bal)).toLocaleString('en-US')}`;

  const net = S.chart.reduce((s, d) => s + (+d.income || 0) - (+d.expense || 0), 0);
  NZ.$('#ov-delta').innerHTML = S.chart.length
    ? `<b class="${net < 0 ? 'neg' : ''}">${NZ.icon(net < 0 ? 'trend-down' : 'trend-up')}${signed(net)}</b>net over the last ${S.chart.length} days`
    : '';
  NZ.$('#cc-range').textContent = `Last ${S.chart.length || 14} days`;

  const n = S.employees.length, on = S.employees.filter(e => e.onDuty).length, pr = payroll();
  const weeks = pr > 0 ? Math.floor(Math.max(0, bal) / pr) : null;
  NZ.$('#kpis').innerHTML = `
    <div class="kpi"><span>${NZ.icon('users')}Employees</span><b>${n}</b><small>${S.grades.length} grades</small></div>
    <div class="kpi"><span>${NZ.icon('pulse')}On duty</span><b>${on}</b><div class="nz-meter"><i style="--v:${n ? Math.round(on / n * 100) : 0}%"></i></div></div>
    <div class="kpi"><span>${NZ.icon('cash')}Payroll per week</span><b>${NZ.money(pr)}</b><small>${weeks == null ? 'No salaries set' : `Balance covers ${weeks} week${weeks === 1 ? '' : 's'}`}</small></div>`;

  const tx = S.history.slice(0, 12);
  NZ.$('#ov-tx').innerHTML = tx.length ? tx.map(h => {
    const inc = +h.amount > 0;
    return `<div class="tx"><span class="tx-ic ${inc ? 'in' : ''}">${NZ.icon(inc ? 'dep' : 'wd')}</span>
      <span class="tx-t"><b>${NZ.esc(h.label)}</b><span>${NZ.esc(h.by || '—')} · ${NZ.esc(fmtTime(h.time))}</span></span>
      <b class="amt ${inc ? 'in' : ''}">${signed(+h.amount)}</b></div>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('receipt')}<b>No transactions yet</b><span>Deposits, payroll and sales show up here.</span></div>`;
  drawChart();
}

/* ── chart: drawn by hand, sized to its box in real pixels so text stays crisp ── */
function niceStep(raw) {
  const p = Math.pow(10, Math.floor(Math.log10(raw))), n = raw / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
}
function barPath(x, y, w, h) {
  if (h < .5) return '';
  const r = Math.min(2.5, w / 2, h);
  return `M${x} ${y + h}V${y + r}Q${x} ${y} ${x + r} ${y}H${x + w - r}Q${x + w} ${y} ${x + w} ${y + r}V${y + h}Z`;
}
function drawChart() {
  const box = NZ.$('#chart');
  const W = box.clientWidth, H = box.clientHeight;
  if (!W || !H) return;
  const data = S.chart;
  if (!data.length) { box.innerHTML = `<div class="nz-empty">${NZ.icon('chart')}<b>No activity yet</b><span>Income and expenses appear once money moves.</span></div>`; return; }
  const L = 50, R = 4, T = 10, B = 24, pw = W - L - R, ph = H - T - B;
  const peak = Math.max(1, ...data.map(d => Math.max(+d.income || 0, +d.expense || 0)));
  const step = niceStep(peak / 4), top = Math.ceil(peak / step) * step;
  const y = v => T + ph - (v / top) * ph;
  const cw = pw / data.length, bw = Math.max(4, Math.min(12, cw * .24)), gap = Math.max(2, Math.min(4, cw * .07));
  const every = cw < 36 ? 2 : 1;

  let s = `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs>
    <linearGradient id="gIn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0fd4c4"/><stop offset="1" stop-color="#067d74"/></linearGradient></defs>`;
  for (let v = 0; v <= top + 1e-6; v += step) {
    const yy = Math.round(y(v)) + .5;
    s += `<line class="grid${v === 0 ? ' base' : ''}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/>`;
    s += `<text class="ax" x="${L - 10}" y="${yy + 3.5}" text-anchor="end">${shortMoney(v)}</text>`;
  }
  data.forEach((d, i) => {
    const x0 = L + cw * i, cx = x0 + cw / 2, inc = +d.income || 0, exp = +d.expense || 0, neg = exp > inc;
    const last = i === data.length - 1;
    s += `<g class="col" data-i="${i}"><rect class="hl" x="${x0 + 1}" y="${T}" width="${Math.max(0, cw - 2)}" height="${ph}" rx="3"/>`;
    s += `<path class="b in" d="${barPath(cx - gap / 2 - bw, y(inc), bw, y(0) - y(inc))}"/>`;
    s += `<path class="b ${neg ? 'neg' : 'out'}" d="${barPath(cx + gap / 2, y(exp), bw, y(0) - y(exp))}"/>`;
    if ((data.length - 1 - i) % every === 0) s += `<text class="ax${last ? ' now' : ''}" x="${cx}" y="${H - 6}" text-anchor="middle">${NZ.esc(d.day)}</text>`;
    s += `<rect class="hit" x="${x0}" y="0" width="${cw}" height="${H}"/></g>`;
  });
  box.innerHTML = s + '</svg><div class="tip" id="tip"></div>';

  const tip = NZ.$('#tip', box);
  NZ.$$('.col', box).forEach(g => {
    g.onmouseenter = () => {
      const i = +g.dataset.i, d = data[i], inc = +d.income || 0, exp = +d.expense || 0, net = inc - exp;
      NZ.$$('.col.on', box).forEach(c => c.classList.remove('on'));
      g.classList.add('on'); box.classList.add('hov');
      tip.innerHTML = `<b>${NZ.esc(d.day)}</b>
        <div><i class="sw in"></i>Income<span>${NZ.money(inc)}</span></div>
        <div><i class="sw ${net < 0 ? 'neg' : 'out'}"></i>Expenses<span>${NZ.money(exp)}</span></div>
        <div class="net ${net < 0 ? 'neg' : ''}">Net<span>${signed(net)}</span></div>`;
      const cx = L + cw * i + cw / 2, tw = tip.offsetWidth;
      tip.style.left = Math.max(tw / 2 + 2, Math.min(W - tw / 2 - 2, cx)) + 'px';
      tip.style.top = Math.max(tip.offsetHeight + 4, Math.min(y(inc), y(exp)) - 10) + 'px';
      tip.classList.add('on');
    };
  });
  NZ.$('svg', box).onmouseleave = () => {
    tip.classList.remove('on'); box.classList.remove('hov');
    NZ.$$('.col.on', box).forEach(c => c.classList.remove('on'));
  };
}

/* ── employees ── */
function renderEmployees() {
  const q = empQ.toLowerCase(), gs = grades(), hi = topGrade();
  const list = S.employees
    .filter(e => (empF === 'all' || e.onDuty) && (!q || [e.name, e.cid, gradeOf(e.grade)?.label].some(v => String(v || '').toLowerCase().includes(q))))
    .sort((a, b) => b.grade - a.grade || String(a.name).localeCompare(String(b.name)));
  NZ.$('#emp-count').innerHTML = `<b>${list.length}</b> of ${S.employees.length} employees`;
  NZ.$('#emp-rows').innerHTML = list.length ? list.map((e, k) => {
    const idx = gs.findIndex(g => +g.grade === +e.grade);
    const cid = NZ.esc(e.cid);
    return `<div class="er ${+e.grade === hi ? 'boss' : ''}" style="animation-delay:${Math.min(k, 12) * 18}ms">
      <div class="who"><span class="nz-av">${NZ.esc(NZ.initials(e.name))}</span><span><b>${NZ.esc(e.name)}</b><small>${cid}</small></span></div>
      <div><select class="nz-input g-sel" data-cid="${cid}">${gs.map(g => `<option value="${NZ.esc(g.grade)}" ${+g.grade === +e.grade ? 'selected' : ''}>${NZ.esc(g.grade)} · ${NZ.esc(g.label)}</option>`).join('')}</select></div>
      <div class="duty ${e.onDuty ? 'on' : ''}"><i class="nz-dot ${e.onDuty ? '' : 'off'}"></i>${e.onDuty ? 'On duty' : 'Off duty'}</div>
      <div class="hired">${NZ.esc(fmtDate(e.hired))}</div>
      <div class="pay">${NZ.money(payOf(e))}<small>/wk</small></div>
      <div class="acts">
        <button class="ab" data-act="up" data-cid="${cid}" title="Promote" ${idx < 0 || idx >= gs.length - 1 ? 'disabled' : ''}>${NZ.icon('chev-u')}</button>
        <button class="ab" data-act="down" data-cid="${cid}" title="Demote" ${idx <= 0 ? 'disabled' : ''}>${NZ.icon('chev-d')}</button>
        <button class="ab red" data-act="fire" data-cid="${cid}" title="Fire">${NZ.icon('user-x')}</button>
      </div></div>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('users')}<b>${S.employees.length ? 'No one matches' : 'No employees yet'}</b><span>${S.employees.length ? 'Try another name or clear the filter.' : 'Hire a nearby player to get started.'}</span></div>`;
}

const empBy = cid => S.employees.find(e => String(e.cid) === String(cid));
function setGrade(cid, grade) {
  const e = empBy(cid), g = gradeOf(grade);
  if (!e || !g || +e.grade === +grade) return;
  const up = +grade > +e.grade;
  act('setGrade', { cid: e.cid, grade: +grade }, () => { e.grade = +grade; },
    `${e.name} ${up ? 'promoted' : 'demoted'} to ${g.label}`);
}
NZ.$('#emp-rows').addEventListener('change', ev => {
  const s = ev.target.closest('.g-sel'); if (s) setGrade(s.dataset.cid, +s.value);
});
NZ.$('#emp-rows').addEventListener('click', ev => {
  const b = ev.target.closest('[data-act]'); if (!b) return;
  const e = empBy(b.dataset.cid); if (!e) return;
  const gs = grades(), idx = gs.findIndex(g => +g.grade === +e.grade);
  if (b.dataset.act === 'up' && gs[idx + 1]) setGrade(e.cid, gs[idx + 1].grade);
  else if (b.dataset.act === 'down' && gs[idx - 1]) setGrade(e.cid, gs[idx - 1].grade);
  else if (b.dataset.act === 'fire') fireModal(e);
});
NZ.$('#emp-q').oninput = ev => { empQ = ev.target.value.trim(); renderEmployees(); };
NZ.$$('#emp-f button').forEach(b => b.onclick = () => {
  empF = b.dataset.f; NZ.$$('#emp-f button').forEach(x => x.classList.toggle('on', x === b)); renderEmployees();
});
NZ.$('#hire').onclick = () => hireModal();

/* ── modal ── */
const M = NZ.$('#modal');
function modal(html, focusSel) {
  M.innerHTML = `<div class="dlg"><div class="nz-frame"><div class="nz-frame-in">${html}</div></div></div>`;
  M.classList.add('on');
  NZ.$$('[data-x]', M).forEach(b => b.onclick = closeModal);
  setTimeout(() => NZ.$(focusSel, M)?.focus(), 30);
}
function closeModal() { M.classList.remove('on'); M.innerHTML = ''; }
M.addEventListener('mousedown', ev => { if (ev.target === M) closeModal(); });

function fireModal(e) {
  modal(`<div class="dlg-h"><span class="nz-tile red">${NZ.icon('user-x')}</span><div>
      <b>Fire ${NZ.esc(e.name)}?</b>
      <span>They lose access to ${NZ.esc(S.society.label || 'the society')} and stop receiving their ${NZ.money(payOf(e))} weekly pay. This cannot be undone.</span></div></div>
    <div class="dlg-f"><button class="nz-btn line" data-x>Keep employee</button><button class="nz-btn red" id="m-ok">${NZ.icon('user-x')}Fire</button></div>`, '#m-ok');
  NZ.$('#m-ok', M).onclick = () => {
    closeModal();
    act('fire', { cid: e.cid }, () => { S.employees = S.employees.filter(x => x !== e); }, `${e.name} was let go`);
  };
}

const DEMO_NAMES = ['Jordan Pike', 'Mila Novak', 'Andre Wallace', 'Hana Kim', 'Victor Cruz', 'Leah Grant', 'Omar Haddad'];
function hireModal() {
  const gs = grades();
  modal(`<div class="dlg-h"><span class="nz-tile">${NZ.icon('user-plus')}</span><div>
      <b>Hire nearby player</b><span>They get a job offer and join at the grade you choose.</span></div></div>
    <div class="nz-field"><label for="h-id">Player ID</label><input class="nz-input" id="h-id" type="number" min="1" placeholder="Server ID, e.g. 14"></div>
    <div class="nz-field"><label for="h-g">Starting grade</label><select class="nz-input" id="h-g">${gs.map(g => `<option value="${NZ.esc(g.grade)}">${NZ.esc(g.grade)} · ${NZ.esc(g.label)} — ${NZ.money(g.salary)}/wk</option>`).join('')}</select></div>
    <div class="dlg-err" id="h-err"></div>
    <div class="dlg-f"><button class="nz-btn line" data-x>Cancel</button><button class="nz-btn teal" id="h-ok">${NZ.icon('user-plus')}Send offer</button></div>`, '#h-id');
  const go = () => {
    const inp = NZ.$('#h-id', M), id = parseInt(inp.value, 10), grade = +NZ.$('#h-g', M).value;
    if (!(id > 0)) { inp.classList.add('bad'); NZ.$('#h-err', M).textContent = 'Enter the player’s server ID'; inp.focus(); return; }
    closeModal();
    const local = NZ.inGame ? null : () => {
      const nm = DEMO_NAMES[Math.floor(Math.random() * DEMO_NAMES.length)];
      S.employees.push({ cid: 'HXL' + (20000 + Math.floor(Math.random() * 79999)), name: nm, grade, onDuty: true, hired: Math.floor(Date.now() / 1000) });
    };
    act('hire', { id, grade }, local, `Job offer sent to player ${id}`);
  };
  NZ.$('#h-ok', M).onclick = go;
  NZ.$('#h-id', M).onkeydown = ev => { if (ev.key === 'Enter') go(); };
  NZ.$('#h-id', M).oninput = ev => { ev.target.classList.remove('bad'); NZ.$('#h-err', M).textContent = ''; };
}

/* ── finances ── */
const CHIPS = [1000, 5000, 10000, 25000, 50000];
function renderFinances() {
  const bal = +S.society.balance || 0, a = num(NZ.$('#amt').value);
  NZ.$$('#fin-mode button').forEach(b => b.classList.toggle('on', b.dataset.m === mode));
  NZ.$('#chips').innerHTML = CHIPS.map(c => `<button data-c="${c}">+${shortMoney(c)}</button>`).join('') +
    (mode === 'withdraw' ? `<button class="mx" data-c="max">All</button>` : `<button data-c="clear">Clear</button>`);
  const after = mode === 'deposit' ? bal + a : bal - a;
  NZ.$('#f-now').textContent = NZ.money(bal);
  const fa = NZ.$('#f-after'); fa.textContent = NZ.money(after); fa.classList.toggle('neg', after < 0);
  const over = mode === 'withdraw' && a > bal;
  NZ.$('#f-err').textContent = over ? `The society only holds ${NZ.money(bal)}` : '';
  const go = NZ.$('#f-go');
  go.disabled = !a || over;
  go.innerHTML = `${NZ.icon(mode === 'deposit' ? 'dep' : 'wd')}${mode === 'deposit' ? 'Deposit' : 'Withdraw'}${a ? ' ' + NZ.money(a) : ''}`;

  const inSum = S.chart.reduce((s, d) => s + (+d.income || 0), 0), outSum = S.chart.reduce((s, d) => s + (+d.expense || 0), 0);
  NZ.$('#f-sum').innerHTML = `<div><span>In · ${S.chart.length || 14} days</span><b class="in">${NZ.money(inSum)}</b></div><div><span>Out · ${S.chart.length || 14} days</span><b>${NZ.money(outSum)}</b></div>`;
  renderBook();
}
function renderBook() {
  let run = +S.society.balance || 0;
  const rows = S.history.map(h => { const r = { h, bal: run }; run -= +h.amount || 0; return r; });
  const q = txQ.toLowerCase();
  const list = rows.filter(({ h }) => (txF === 'all' || (txF === 'in' ? +h.amount > 0 : +h.amount < 0)) &&
    (!q || [h.label, h.by].some(v => String(v || '').toLowerCase().includes(q))));
  NZ.$('#tx-rows').innerHTML = list.length ? list.map(({ h, bal }) => {
    const inc = +h.amount > 0;
    return `<div class="hr"><span class="t">${NZ.esc(fmtTime(h.time))}</span>
      <span class="d"><span class="tx-ic ${inc ? 'in' : ''}">${NZ.icon(inc ? 'dep' : 'wd')}</span><span><b>${NZ.esc(h.label)}</b><small>${NZ.esc(h.by || '—')}</small></span></span>
      <b class="amt ${inc ? 'in' : ''}">${signed(+h.amount)}</b><span class="rb">${NZ.money(bal)}</span></div>`;
  }).join('') : `<div class="nz-empty">${NZ.icon('receipt')}<b>No transactions match</b><span>Change the filter or clear the search.</span></div>`;
}
NZ.$$('#fin-mode button').forEach(b => b.onclick = () => { mode = b.dataset.m; renderFinances(); NZ.$('#amt').focus(); });
NZ.$('#chips').onclick = ev => {
  const b = ev.target.closest('[data-c]'); if (!b) return;
  const inp = NZ.$('#amt'), c = b.dataset.c;
  const v = c === 'max' ? Math.max(0, +S.society.balance || 0) : c === 'clear' ? 0 : num(inp.value) + +c;
  inp.value = v ? v.toLocaleString('en-US') : '';
  renderFinances();
};
NZ.$('#amt').oninput = ev => {
  const v = num(ev.target.value);
  ev.target.value = v ? v.toLocaleString('en-US') : '';
  renderFinances();
};
NZ.$('#amt').onkeydown = ev => { if (ev.key === 'Enter') moveMoney(); };
NZ.$('#f-go').onclick = () => moveMoney();
function moveMoney() {
  const a = num(NZ.$('#amt').value), bal = +S.society.balance || 0;
  if (!a || (mode === 'withdraw' && a > bal)) return;
  const dep = mode === 'deposit';
  NZ.$('#amt').value = '';
  act(dep ? 'deposit' : 'withdraw', { amount: a }, () => {
    S.society.balance = bal + (dep ? a : -a);
    S.history.unshift({ amount: dep ? a : -a, label: dep ? 'Deposit' : 'Withdrawal', by: S.me || 'You', time: Math.floor(Date.now() / 1000) });
    const today = S.chart[S.chart.length - 1];
    if (today) dep ? (today.income = (+today.income || 0) + a) : (today.expense = (+today.expense || 0) + a);
  }, `${dep ? 'Deposited' : 'Withdrew'} ${NZ.money(a)}`);
}
NZ.$$('#tx-f button').forEach(b => b.onclick = () => {
  txF = b.dataset.f; NZ.$$('#tx-f button').forEach(x => x.classList.toggle('on', x === b)); renderBook();
});
NZ.$('#tx-q').oninput = ev => { txQ = ev.target.value.trim(); renderBook(); };

/* ── grades ── */
function resetDraft() { draft = grades().map(g => ({ grade: +g.grade, label: g.label, salary: +g.salary || 0 })); dirty = false; }
function staffIn(g) { return S.employees.filter(e => +e.grade === +g).length; }
function renderGrades() {
  const hi = draft.length ? draft[draft.length - 1].grade : null;
  NZ.$('#g-rows').innerHTML = draft.map((g, i) => {
    const n = staffIn(g.grade), canDel = i === draft.length - 1 && draft.length > 1 && n === 0;
    return `<div class="gr ${g.grade === hi ? 'boss' : ''}">
      <span class="gn">${NZ.esc(g.grade)}</span>
      <input class="nz-input" data-i="${i}" data-k="label" value="${NZ.esc(g.label)}" maxlength="32" placeholder="Grade name">
      <div class="sal"><span>$</span><input class="nz-input" data-i="${i}" data-k="salary" inputmode="numeric" value="${NZ.esc(g.salary)}"></div>
      <span class="staff">${n}</span>
      <button class="ab red" data-del="${i}" title="${canDel ? 'Remove grade' : 'Only an empty top grade can be removed'}" ${canDel ? '' : 'disabled'}>${NZ.icon('trash')}</button>
    </div>`;
  }).join('');
  gradeSide();
}
function gradeSide() {
  NZ.$('#g-dirty').hidden = !dirty;
  NZ.$('#g-save').disabled = !dirty;
  NZ.$('#g-reset').disabled = !dirty;
  const rows = draft.map(g => {
    const staff = S.employees.filter(e => +e.grade === +g.grade);
    const cost = staff.reduce((s, e) => s + (e.salary != null ? +e.salary : g.salary), 0);
    return { g, n: staff.length, cost };
  });
  const total = rows.reduce((s, r) => s + r.cost, 0), max = Math.max(1, ...rows.map(r => r.cost));
  NZ.$('#g-cost').innerHTML = [...rows].reverse().map(r => `<div class="gc">
      <div><span>${NZ.esc(r.g.label || 'Unnamed')} <small>· ${r.n} × ${NZ.money(r.g.salary)}</small></span><span>${NZ.money(r.cost)}</span></div>
      <div class="nz-meter ${r.g.grade === draft[draft.length - 1].grade ? 'white' : ''}"><i style="--v:${Math.round(r.cost / max * 100)}%"></i></div></div>`).join('');
  NZ.$('#g-total').textContent = NZ.money(total);
  const diff = total - payroll();
  NZ.$('#g-delta').innerHTML = diff ? `<b class="${diff > 0 ? 'up' : 'down'}">${signed(diff)}</b> per week vs now` : 'Same as current payroll';
}
NZ.$('#g-rows').addEventListener('input', ev => {
  const inp = ev.target.closest('[data-k]'); if (!inp) return;
  const g = draft[+inp.dataset.i];
  if (inp.dataset.k === 'salary') { const v = num(inp.value); inp.value = inp.value === '' ? '' : v; g.salary = v; }
  else { g.label = inp.value; inp.classList.toggle('bad', !inp.value.trim()); }
  dirty = true; gradeSide();
});
NZ.$('#g-rows').addEventListener('click', ev => {
  const b = ev.target.closest('[data-del]'); if (!b) return;
  draft.splice(+b.dataset.del, 1); dirty = true; renderGrades();
});
NZ.$('#g-add').onclick = () => {
  const last = draft[draft.length - 1];
  draft.push({ grade: last ? last.grade + 1 : 0, label: '', salary: last ? last.salary : 0 });
  dirty = true; renderGrades();
  const ins = NZ.$$('#g-rows [data-k="label"]'); ins[ins.length - 1]?.focus();
};
NZ.$('#g-reset').onclick = () => { resetDraft(); renderGrades(); };
NZ.$('#g-save').onclick = () => {
  const bad = draft.findIndex(g => !String(g.label).trim());
  if (bad >= 0) { const inp = NZ.$$('#g-rows [data-k="label"]')[bad]; inp.classList.add('bad'); inp.focus(); toast('Every grade needs a name', 'err'); return; }
  const out = draft.map(g => ({ grade: g.grade, label: String(g.label).trim(), salary: +g.salary || 0 }));
  act('saveGrades', { grades: out }, () => { S.grades = out.map(g => ({ ...g })); dirty = false; }, 'Grades saved');
};

/* ── actions: apply locally, let Lua confirm or roll back ── */
async function act(name, payload, local, okMsg) {
  const snap = JSON.stringify(S);
  if (local) local();
  renderAll();
  if (!NZ.inGame) { if (okMsg) toast(okMsg); return; }
  const res = await NZ.post(name, payload);
  if (res && res.ok === false) {
    Object.assign(S, JSON.parse(snap));
    if (name === 'saveGrades') dirty = true;
    renderAll(true);
    toast(res.error || 'That did not go through', 'err');
    return;
  }
  if (res && typeof res === 'object') apply(res);
  if (okMsg) toast(okMsg);
}

function toast(text, type = 'ok') {
  const host = NZ.$('#toasts'), el = document.createElement('div');
  el.className = `nz-toast ${type === 'err' ? 'err' : ''}`;
  el.innerHTML = `<div class="nz-tile ${type === 'err' ? 'red' : ''}">${NZ.icon(type === 'err' ? 'error' : 'check')}</div><div><b>${type === 'err' ? 'Not saved' : 'Done'}</b><p>${NZ.esc(text)}</p></div>`;
  host.appendChild(el);
  while (host.children.length > 3) host.firstChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 320); }, 2600);
}

/* ── data in ── */
function apply(d, keepDraft) {
  if (!d || typeof d !== 'object') return;
  if (d.society && typeof d.society === 'object') Object.assign(S.society, d.society);
  if (d.me != null) S.me = d.me;
  ['employees', 'grades', 'history', 'chart'].forEach(k => { if (d[k] != null) S[k] = arr(d[k]); });
  if (d.grades != null && !dirty && !keepDraft) resetDraft();
  renderAll(true);
}
function renderAll(withGrades) {
  renderHead(); renderOverview(); renderEmployees(); renderFinances();
  if (withGrades || !dirty) { if (!dirty) resetDraft(); renderGrades(); } else gradeSide();
}

function openUI(d) {
  Object.assign(S, { society: { label: '', sub: '', balance: 0 }, me: '', employees: [], grades: [], history: [], chart: [] });
  empQ = ''; txQ = ''; empF = 'all'; txF = 'all'; mode = 'deposit';
  NZ.$('#emp-q').value = ''; NZ.$('#tx-q').value = ''; NZ.$('#amt').value = '';
  NZ.$$('#emp-f button, #tx-f button').forEach(b => b.classList.toggle('on', b.dataset.f === 'all'));
  closeModal();
  dirty = false;
  NZ.open(app);
  apply(d || {});
  setTab('overview');
  requestAnimationFrame(() => { moveInk(); drawChart(); });
}
NZ.on('open', openUI);
NZ.on('update', d => apply(d));
NZ.on('close', () => { closeModal(); NZ.close(app, { notify: false }); });

window.addEventListener('resize', () => { moveInk(); if (tab === 'overview') drawChart(); });
if (document.fonts) document.fonts.ready.then(() => moveInk());
NZ.$$('[data-close]').forEach(b => b.onclick = () => NZ.close(app));

window.addEventListener('keydown', ev => {
  if (!app.classList.contains('nz-open')) return;
  if (ev.key === 'Escape') { ev.preventDefault(); if (M.classList.contains('on')) closeModal(); else NZ.close(app); return; }
  if (M.classList.contains('on')) return;
  const typing = /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName || '');
  if (typing) return;
  const t = ['overview', 'employees', 'finances', 'grades'][+ev.key - 1];
  if (t) { setTab(t); ev.preventDefault(); }
  else if (ev.key === '/') { ev.preventDefault(); setTab('employees'); NZ.$('#emp-q').focus(); }
});

/* ── browser preview ── */
NZ.preview(() => {
  const now = Math.floor(Date.now() / 1000), H = 3600, D = 86400;
  const days = [];
  const inc = [14200, 18600, 12400, 21900, 16800, 9800, 23400, 19100, 15600, 11200, 22800, 17900, 20500, 13600];
  const exp = [8400, 9900, 16100, 10200, 8800, 24600, 11800, 9300, 10700, 9700, 9600, 26200, 10400, 7200];
  for (let i = 13; i >= 0; i--) {
    const d = new Date((now - i * D) * 1000);
    days.push({ day: `${d.getDate()} ${MON[d.getMonth()]}`, income: inc[13 - i], expense: exp[13 - i] });
  }
  openUI({
    society: { label: 'Hayes Autos', sub: 'Business · Little Bighorn Ave', balance: 1284560 },
    me: 'Marcus Hale',
    grades: [
      { grade: 0, label: 'Apprentice', salary: 650 },
      { grade: 1, label: 'Mechanic', salary: 950 },
      { grade: 2, label: 'Senior mechanic', salary: 1300 },
      { grade: 3, label: 'Shop foreman', salary: 1750 },
      { grade: 4, label: 'Owner', salary: 2400 },
    ],
    employees: [
      { cid: 'HXL20481', name: 'Marcus Hale', grade: 4, onDuty: true, hired: now - 412 * D },
      { cid: 'HXL31907', name: 'Tasha Reyes', grade: 3, onDuty: true, hired: now - 301 * D },
      { cid: 'HXL44120', name: 'Luis Ortega', grade: 2, onDuty: true, hired: now - 244 * D },
      { cid: 'HXL51388', name: 'Dmitri Volkov', grade: 2, onDuty: false, hired: now - 198 * D },
      { cid: 'HXL60215', name: 'Jada Brooks', grade: 2, onDuty: true, hired: now - 176 * D },
      { cid: 'HXL62904', name: 'Kenji Sato', grade: 1, onDuty: false, hired: now - 131 * D },
      { cid: 'HXL70033', name: 'Ava Mercer', grade: 1, onDuty: true, hired: now - 97 * D },
      { cid: 'HXL71456', name: 'Tyrell Banks', grade: 1, onDuty: false, hired: now - 88 * D },
      { cid: 'HXL77810', name: 'Nina Petrova', grade: 1, onDuty: true, hired: now - 61 * D },
      { cid: 'HXL80127', name: 'Cole Whitaker', grade: 0, onDuty: false, hired: now - 34 * D },
      { cid: 'HXL81544', name: 'Rosa Delgado', grade: 0, onDuty: true, hired: now - 19 * D },
      { cid: 'HXL83290', name: 'Eli Navarro', grade: 0, onDuty: false, hired: now - 12 * D },
      { cid: 'HXL85002', name: 'Sam Okafor', grade: 0, onDuty: false, hired: now - 5 * D },
      { cid: 'HXL85977', name: 'Priya Shah', grade: 0, onDuty: true, hired: now - 2 * D },
    ],
    history: [
      { amount: 1850, label: 'Repair invoice · Karin Sultan RS', by: 'Luis Ortega', time: now - 0.4 * H },
      { amount: 6400, label: 'Custom wrap · Pegassi Zentorno', by: 'Jada Brooks', time: now - 1.6 * H },
      { amount: -4200, label: 'Parts order · Benny’s supply', by: 'Tasha Reyes', time: now - 2.9 * H },
      { amount: 600, label: 'Tow job · Del Perro Pier', by: 'Ava Mercer', time: now - 4.1 * H },
      { amount: 20000, label: 'Deposit', by: 'Marcus Hale', time: now - 6.3 * H },
      { amount: -15350, label: 'Weekly payroll', by: 'System', time: now - 22 * H },
      { amount: 3150, label: 'Engine rebuild · Bravado Gauntlet', by: 'Dmitri Volkov', time: now - 25 * H },
      { amount: -3200, label: 'Property tax', by: 'City of Los Santos', time: now - 30 * H },
      { amount: 980, label: 'Repair invoice · Vapid Stanier', by: 'Nina Petrova', time: now - 33 * H },
      { amount: -5000, label: 'Withdrawal', by: 'Marcus Hale', time: now - 2.2 * D },
      { amount: 2700, label: 'Tuning package · Obey Tailgater', by: 'Luis Ortega', time: now - 2.5 * D },
      { amount: -1180, label: 'Electricity · LS Water & Power', by: 'System', time: now - 3.1 * D },
      { amount: 4300, label: 'Fleet service · Downtown Cab Co.', by: 'Tasha Reyes', time: now - 3.8 * D },
      { amount: -2650, label: 'Tool restock', by: 'Kenji Sato', time: now - 4.4 * D },
      { amount: 1420, label: 'Repair invoice · Declasse Vigero', by: 'Ava Mercer', time: now - 5.2 * D },
    ],
    chart: days,
  });
});
