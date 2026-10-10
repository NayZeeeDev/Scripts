/* 09 · SLATE
   SendNUIMessage({ action = 'open', data = {
     owner, battery = 82,
     bank = { balance, account, transactions = {{label, sub, amount, icon}} },
     notes = {{id, title, body}},
     apps = {{id, label, icon, color = 'teal'|'red'|'white'|'amber'|'dark', badge, dock = true}} } })
   Built-in app ids: bank, notes. Any other id shows a placeholder and posts `app {id}` so Lua can react.
   Callbacks: app {id}, bank {action = 'transfer'|'deposit'|'withdraw'}, note {id, body}, close
*/
const app = NZ.$('#app');
let D = null, noteId = null;

const BG = {
  teal: 'linear-gradient(155deg,#0fd4c4,#067d74)', red: 'linear-gradient(155deg,#f06368,#a81f24)',
  white: 'linear-gradient(155deg,#ffffff,#b9c0c4)', amber: 'linear-gradient(155deg,#f2be3a,#a87500)',
  dark: 'linear-gradient(155deg,#2a2f33,#121516)', blue: 'linear-gradient(155deg,#4b8de0,#1f3a68)',
};
const appIcon = a => `<button class="app" data-app="${NZ.esc(a.id)}">
  <span class="ico" style="--bg:${BG[a.color] || BG.dark};${a.color === 'white' ? 'color:#000' : ''}">${NZ.icon(a.icon)}${a.badge ? `<span class="badge">${NZ.esc(a.badge)}</span>` : ''}</span>
  <span>${NZ.esc(a.label)}</span></button>`;

function clock() {
  const d = new Date();
  const t = d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  NZ.$('#sb-time').textContent = t; NZ.$('#h-time').textContent = t;
  NZ.$('#h-date').textContent = d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
}
setInterval(clock, 10000);

function home() {
  NZ.$('#appview').hidden = true;
  NZ.$('#home').hidden = false;
  const unread = D.apps.find(a => a.id === 'mail')?.badge || 0;
  NZ.$('#widgets').innerHTML = `
    <div class="widget"><span>${NZ.icon('bank')}Balance</span><b>${NZ.money(D.bank.balance)}</b><small>${NZ.esc(D.bank.account)}</small></div>
    <div class="widget"><span>${NZ.icon('mail')}Inbox</span><b>${unread} new</b><small>${NZ.esc(D.owner)}</small></div>`;
  NZ.$('#apps').innerHTML = D.apps.filter(a => !a.dock).map(appIcon).join('');
  NZ.$('#dock').innerHTML = D.apps.filter(a => a.dock).map(appIcon).join('');
  NZ.$$('[data-app]').forEach(b => b.onclick = () => openApp(b.dataset.app));
}

function chrome(a, extra = '') {
  return `<div class="a-head"><button class="back" data-home>${NZ.icon('chev-l')}</button>
    <span class="ico" style="--bg:${BG[a.color] || BG.dark}">${NZ.icon(a.icon)}</span><h1>${NZ.esc(a.label)}</h1>${extra}</div>`;
}

const VIEWS = {
  bank(a) {
    const b = D.bank;
    return chrome(a, `<button class="nz-btn ghost sm"><i data-ic="refresh"></i>Refresh</button>`) + `<div class="a-body"><div class="bank">
      <div>
        <div class="bcard"><div class="top"><span>NAYZEEE BANK</span><span class="nz-mark sm mono"></span></div>
          <small>Available balance</small><b>${NZ.money(b.balance)}</b><span class="num">${NZ.esc(b.account)}</span></div>
        <div class="qa">
          <button data-bank="transfer">${NZ.icon('swap')}Transfer</button>
          <button data-bank="deposit">${NZ.icon('arrow-up')}Deposit</button>
          <button data-bank="withdraw">${NZ.icon('cash')}Withdraw</button>
        </div>
      </div>
      <div class="tx"><h3>Recent activity</h3><div class="rows nz-scroll">${b.transactions.map(t => `
        <div class="trow"><div class="nz-tile ${t.amount > 0 ? '' : 'mute'}">${NZ.icon(t.icon || 'receipt')}</div>
          <div><b>${NZ.esc(t.label)}</b><span>${NZ.esc(t.sub)}</span></div>
          <em class="${t.amount > 0 ? 'in' : ''}">${t.amount > 0 ? '+' : ''}${NZ.money(t.amount)}</em></div>`).join('')}</div></div>
    </div></div>`;
  },
  notes(a) {
    if (!noteId && D.notes[0]) noteId = D.notes[0].id;
    const n = D.notes.find(x => x.id === noteId);
    return chrome(a, `<button class="nz-btn teal sm" data-newnote><i data-ic="plus"></i>New note</button>`) + `<div class="a-body"><div class="notes">
      <div class="nlist nz-scroll">${D.notes.map(x => `<button class="note ${x.id === noteId ? 'on' : ''}" data-note="${NZ.esc(x.id)}"><b>${NZ.esc(x.title)}</b><span>${NZ.esc(x.body.split('\n')[0])}</span></button>`).join('')}</div>
      <textarea class="nz-input nz-scroll" id="note-body" placeholder="Start typing…">${NZ.esc(n ? n.body : '')}</textarea>
    </div></div>`;
  },
};

function openApp(id) {
  const a = D.apps.find(x => x.id === id);
  if (!a) return;
  NZ.post('app', { id });
  const v = NZ.$('#appview');
  v.innerHTML = VIEWS[id] ? VIEWS[id](a) : chrome(a) + `<div class="a-body soon"><div class="nz-empty">${NZ.icon(a.icon)}<b>${NZ.esc(a.label)}</b><span>Hook this app up in Lua — the tablet posts <b>app</b> with id “${NZ.esc(id)}”.</span></div></div>`;
  NZ.hydrate(v);
  NZ.$('#home').hidden = true;
  v.hidden = false;
  v.style.animation = 'none'; void v.offsetWidth; v.style.animation = '';
  v.querySelector('[data-home]').onclick = home;
  v.querySelectorAll('[data-bank]').forEach(b => b.onclick = () => NZ.post('bank', { action: b.dataset.bank }));
  v.querySelectorAll('[data-note]').forEach(b => b.onclick = () => { noteId = b.dataset.note; openApp('notes'); });
  v.querySelector('[data-newnote]')?.addEventListener('click', () => {
    const n = { id: 'n' + Date.now(), title: 'New note', body: '' };
    D.notes.unshift(n); noteId = n.id; openApp('notes'); NZ.$('#note-body').focus();
  });
  const ta = v.querySelector('#note-body');
  if (ta) ta.oninput = () => {
    const n = D.notes.find(x => x.id === noteId); if (!n) return;
    n.body = ta.value; n.title = ta.value.split('\n')[0].slice(0, 40) || 'Untitled';
    clearTimeout(ta._t); ta._t = setTimeout(() => NZ.post('note', { id: n.id, body: n.body }), 500);
  };
}

NZ.$('#homebar').onclick = () => D && home();
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  if (e.key === 'Escape') {
    if (!NZ.$('#appview').hidden) home(); else NZ.close(app);
  }
});

function open(d) {
  D = d;
  if (d.battery != null) NZ.$('#sb-bat').textContent = d.battery + '%';
  clock(); home();
  NZ.open(app);
}
NZ.on('open', open);
NZ.on('bank', b => { if (D) { Object.assign(D.bank, b); if (!NZ.$('#appview').hidden) openApp('bank'); else home(); } });
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => open({
  owner: 'John Doe', battery: 82,
  bank: { balance: 128450, account: '•••• 4021', transactions: [
    { label: 'Paycheck · EMS', sub: 'Today, 16:00', amount: 2250, icon: 'medkit' },
    { label: 'Premium Deluxe Motorsport', sub: 'Yesterday · Card', amount: -14500, icon: 'car' },
    { label: 'Transfer from Maya Reyes', sub: 'Yesterday', amount: 600, icon: 'swap' },
    { label: '24/7 Supermarket', sub: 'Fri · Card', amount: -402, icon: 'cart' },
    { label: 'Fuel · Ron Alternates', sub: 'Thu · Card', amount: -88, icon: 'fuel' },
    { label: 'Paycheck · EMS', sub: 'Thu, 16:00', amount: 2250, icon: 'medkit' },
  ]},
  notes: [
    { id: 'n1', title: 'Shift checklist', body: 'Shift checklist\n- Restock bandages\n- Check Ambulance 04 fuel\n- Sign off MED-215 report' },
    { id: 'n2', title: 'Pillbox door codes', body: 'Pillbox door codes\nNo, I am not writing them here.' },
  ],
  apps: [
    { id: 'bank', label: 'Bank', icon: 'bank', color: 'teal' },
    { id: 'garage', label: 'Garage', icon: 'car', color: 'dark' },
    { id: 'jobs', label: 'Jobs', icon: 'briefcase', color: 'amber' },
    { id: 'map', label: 'Map', icon: 'map', color: 'blue' },
    { id: 'notes', label: 'Notes', icon: 'note', color: 'white' },
    { id: 'camera', label: 'Camera', icon: 'camera', color: 'dark' },
    { id: 'market', label: 'Market', icon: 'bag', color: 'red' },
    { id: 'settings', label: 'Settings', icon: 'sliders', color: 'dark' },
    { id: 'phone', label: 'Phone', icon: 'phone', color: 'teal', dock: true },
    { id: 'mail', label: 'Mail', icon: 'mail', color: 'dark', badge: 3, dock: true },
    { id: 'messages', label: 'Messages', icon: 'message', color: 'white', dock: true },
    { id: 'mdt', label: 'MDT', icon: 'badge', color: 'red', dock: true },
  ],
}));
