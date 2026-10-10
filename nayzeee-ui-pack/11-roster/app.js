/* 11 · ROSTER
   SendNUIMessage({ action = 'open', data = {
     server = 'Los Santos Roleplay',
     slots = 5,              -- total slot cards shown
     allowed = 3,            -- slots this player may use; the rest show as locked ("Unlock with VIP")
     characters = {
       { cid = 'LS48213', slot = 1, first = 'Marcus', last = 'Delgado',
         job = 'Los Santos Police Department', grade = 'Sergeant',
         cash = 2450, bank = 84320, dob = '1991-03-14', nationality = 'American',
         phone = '(555) 214-8831', gender = 'male',       -- 'male' | 'female' (0 / 1 also accepted)
         lastPlayed = 1760090000 },                         -- unix seconds / ms, or a ready string like '2 days ago'
     } } })
   SendNUIMessage({ action = 'close' })

   Callbacks:
     preview {cid, slot}      selection changed. cid is nil on an empty or locked slot (hide the ped).
     play    {cid}            the UI closes itself afterwards (NZ.close → also posts 'close').
     delete  {cid}            sent after the player types the first name to confirm; removed from the list.
     create  {slot, first, last, dob = 'YYYY-MM-DD', gender = 'male'|'female', nationality, height = cm}
             return { ok = true, cid = 'NEW123', ... } to add it to the roster without reopening,
             or { ok = false, error = 'Name already taken' } to show an error in the form.
             (You may also simply send a fresh 'open'.) In the browser preview it is added locally.
     close                    posted whenever the UI closes itself.
   ESC only dismisses the create / delete dialogs, the roster itself stays until a character is played.
*/
NZ.addIcons({
  play: '<path d="M7 4.5v15l12-7.5-12-7.5z"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  flag: '<path d="M5 21V4M5 4.5h11l-2 4 2 4H5"/>',
  ruler: '<path d="m3.5 15.5 12-12 5 5-12 12-5-5z"/><path d="m7.5 11.5 2 2M10.5 8.5l2 2M13.5 5.5l2 2"/>',
  person: '<circle cx="12" cy="7.5" r="4"/><path d="M3.5 22c0-5 3.8-8.5 8.5-8.5s8.5 3.5 8.5 8.5"/>',
});

const app = NZ.$('#app');
let cfg = { server: '', slots: 5, allowed: 3 };
let chars = [];
let sel = 0;              // 0-based slot index
let lastPreview;          // avoid re-posting the same preview
let modal = null;         // 'create' | 'delete' | null

const pad = n => String(n).padStart(2, '0');
const charAt = i => chars.find(c => +c.slot === i + 1);
const slotKind = i => charAt(i) ? 'char' : i < cfg.allowed ? 'empty' : 'locked';
const genderOf = g => (g === 1 || g === '1' || /^f/i.test(String(g ?? ''))) ? 'female' : 'male';
const full = c => `${c.first || ''} ${c.last || ''}`.trim();

function when(v) {
  if (v == null || v === '') return 'Never played';
  if (typeof v === 'string' && isNaN(+v)) return v;
  let t = +v; if (t < 1e12) t *= 1000;
  const s = Math.max(0, (Date.now() - t) / 1000);
  if (s < 60) return 'Just now';
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) { const h = Math.floor(s / 3600); return `${h} hour${h > 1 ? 's' : ''} ago`; }
  const d = Math.floor(s / 86400);
  if (d < 30) return d === 1 ? 'Yesterday' : `${d} days ago`;
  return new Date(t).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}
const stamp = v => { if (v == null || (typeof v === 'string' && isNaN(+v))) return 0; const t = +v; return t < 1e12 ? t * 1000 : t; };

function parseDob(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ''));
  if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  return d.getMonth() === +m[2] - 1 ? d : null;
}
const ageOf = d => { const n = new Date(); let a = n.getFullYear() - d.getFullYear(); if (n < new Date(n.getFullYear(), d.getMonth(), d.getDate())) a--; return a; };
function dobText(s) {
  const d = parseDob(s);
  if (!d) return { v: NZ.esc(s || '—'), age: '' };
  return { v: d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }), age: `${ageOf(d)} y` };
}

/* ── render ── */
function renderTop() {
  NZ.$('#server').textContent = cfg.server || 'Character select';
  const used = chars.length;
  NZ.$('#used').textContent = used;
  NZ.$('#allowed').textContent = cfg.allowed;
  NZ.$('#segs').innerHTML = Array.from({ length: cfg.slots }, (_, i) =>
    `<i class="${charAt(i) ? 'used' : i >= cfg.allowed ? 'lock' : ''}"></i>`).join('');
}

function renderSlots() {
  NZ.$('#slots').innerHTML = Array.from({ length: cfg.slots }, (_, i) => {
    const k = slotKind(i), c = charAt(i), on = i === sel ? 'on' : '';
    const delay = `style="animation-delay:${i * 45}ms"`;
    if (k === 'char') return `
      <button class="slot ${on}" data-i="${i}"><span class="slot-in" ${delay}>
        <span class="portrait">${NZ.icon('person', 'sil')}<span class="slot-no">${pad(i + 1)}</span>
          <span class="slot-gd">${genderOf(c.gender) === 'female' ? 'F' : 'M'}</span>
          <span class="mono">${NZ.esc(NZ.initials(full(c)))}</span></span>
        <span class="slot-txt"><b>${NZ.esc(full(c))}</b><span>${NZ.esc(c.job || 'Unemployed')}</span>
          <span class="slot-time">${NZ.icon('clock')}${NZ.esc(when(c.lastPlayed))}</span></span>
      </span></button>`;
    if (k === 'empty') return `
      <button class="slot empty ${on}" data-i="${i}"><span class="slot-in" ${delay}>
        <span class="portrait"><span class="slot-no">${pad(i + 1)}</span><span class="plus">${NZ.icon('plus')}</span></span>
        <span class="slot-txt"><b>Create character</b><span>Slot ${pad(i + 1)} · free</span>
          <span class="slot-time">${NZ.icon('user')}New citizen</span></span>
      </span></button>`;
    return `
      <button class="slot locked ${on}" data-i="${i}"><span class="slot-in" ${delay}>
        <span class="portrait"><span class="slot-no">${pad(i + 1)}</span>${NZ.icon('lock')}</span>
        <span class="slot-txt"><b>Locked slot</b><span class="vip">Unlock with VIP</span></span>
      </span></button>`;
  }).join('');
  NZ.$$('#slots .slot').forEach(b => {
    b.onclick = () => {
      const i = +b.dataset.i;
      if (i !== sel) select(i);
      else if (slotKind(i) === 'empty') openCreate();
    };
    b.ondblclick = () => activate();
  });
}

function renderHero() {
  const i = sel, k = slotKind(i), c = charAt(i);
  const ghost = `<div class="ro-ghost">${pad(i + 1)}</div>`;
  let h = '';
  if (k === 'char') {
    const longest = Math.max(String(c.first || '').length, String(c.last || '').length);
    const kScale = Math.min(1, 9 / Math.max(longest, 1)).toFixed(3);
    const dob = dobText(c.dob);
    h = `${ghost}
      <div class="ro-eyebrow in"><span class="nz-dot"></span><b>Slot ${pad(i + 1)}</b><i>·</i>CID ${NZ.esc(c.cid)}<i>·</i>${genderOf(c.gender) === 'female' ? 'Female' : 'Male'}</div>
      <h1 class="ro-name in" style="--k:${kScale}"><span>${NZ.esc(c.first)}</span><b>${NZ.esc(c.last)}</b></h1>
      <div class="ro-role in">${NZ.icon('briefcase')}<b>${NZ.esc(c.job || 'Unemployed')}</b>${c.grade ? `<span class="nz-chip">${NZ.esc(c.grade)}</span>` : ''}</div>
      <div class="ro-facts nz-frame in"><div class="nz-frame-in">
        <div class="fact money"><span>${NZ.icon('cash')}Cash</span><b>${NZ.money(+c.cash || 0)}</b></div>
        <div class="fact money"><span>${NZ.icon('bank')}Bank</span><b>${NZ.money(+c.bank || 0)}</b></div>
        <div class="fact"><span>${NZ.icon('calendar')}Date of birth</span><b>${dob.v}${dob.age ? `<small>${dob.age}</small>` : ''}</b></div>
        <div class="fact"><span>${NZ.icon('flag')}Nationality</span><b>${NZ.esc(c.nationality || '—')}</b></div>
        <div class="fact"><span>${NZ.icon('phone')}Phone</span><b>${NZ.esc(c.phone || '—')}</b></div>
        <div class="fact"><span>${NZ.icon('clock')}Last played</span><b>${NZ.esc(when(c.lastPlayed))}</b></div>
      </div></div>`;
  } else if (k === 'empty') {
    h = `${ghost}
      <div class="ro-eyebrow in"><span class="nz-dot off"></span><b>Slot ${pad(i + 1)}</b><i>·</i>Free</div>
      <h1 class="ro-name in"><span>New</span><b>character</b></h1>
      <p class="ro-note in">This slot is free. Create a new citizen with their own money, job, phone number and property, separate from your other characters.</p>`;
  } else {
    h = `${ghost}
      <div class="ro-eyebrow in"><span class="nz-dot off"></span><b>Slot ${pad(i + 1)}</b><i>·</i>Locked</div>
      <h1 class="ro-name in"><span>Locked</span><b>slot</b></h1>
      <p class="ro-note in">Your account can use <b>${cfg.allowed} of ${cfg.slots}</b> character slots. Unlock more slots with VIP on the server store.</p>`;
  }
  NZ.$('#hero').innerHTML = h;
}

function renderActs() {
  const k = slotKind(sel), c = charAt(sel);
  const el = NZ.$('#acts');
  if (k === 'char') {
    el.innerHTML = `
      <button class="nz-btn red" id="del">${NZ.icon('trash')}Delete</button>
      <button class="ro-play" id="play"><span class="pl">${NZ.icon('play')}</span>
        <span class="tx"><b>Play</b><small>as ${NZ.esc(full(c))}</small></span><span class="nz-key">↵</span></button>`;
    NZ.$('#del').onclick = openDelete;
    NZ.$('#play').onclick = play;
  } else if (k === 'empty') {
    el.innerHTML = `<button class="ro-play" id="new"><span class="pl">${NZ.icon('plus')}</span>
      <span class="tx"><b>Create character</b><small>Slot ${pad(sel + 1)}</small></span><span class="nz-key">↵</span></button>`;
    NZ.$('#new').onclick = openCreate;
  } else {
    el.innerHTML = `<div class="ro-locknote"><span class="nz-tile mute">${NZ.icon('lock')}</span>
      <p><b>Slot ${pad(sel + 1)} is locked.</b> Unlock with VIP to add another character.</p></div>`;
  }
}

function renderAll() { renderTop(); renderSlots(); renderHero(); renderActs(); }

function select(i) {
  sel = (i + cfg.slots) % cfg.slots;
  NZ.$$('#slots .slot').forEach(b => b.classList.toggle('on', +b.dataset.i === sel));
  renderHero(); renderActs();
  sendPreview();
}
function sendPreview() {
  const c = charAt(sel);
  const key = c ? `c:${c.cid}` : `s:${sel}`;
  if (key === lastPreview) return;
  lastPreview = key;
  NZ.post('preview', { cid: c ? c.cid : null, slot: sel + 1 });
}

function shake() {
  const b = NZ.$(`#slots .slot[data-i="${sel}"]`);
  if (!b) return;
  b.classList.remove('shake'); void b.offsetWidth; b.classList.add('shake');
}

function activate() {
  const k = slotKind(sel);
  if (k === 'char') play();
  else if (k === 'empty') openCreate();
  else shake();
}

function play() {
  const c = charAt(sel);
  if (!c) return;
  NZ.post('play', { cid: c.cid });
  NZ.close(app);
}

/* ── dialogs ── */
const mEl = NZ.$('#modal');
function showModal(kind, html) {
  modal = kind;
  mEl.innerHTML = html;
  mEl.hidden = false;
  mEl.onclick = e => { if (e.target === mEl) hideModal(); };
  NZ.$$('[data-cancel]', mEl).forEach(b => b.onclick = hideModal);
}
function hideModal() { modal = null; mEl.hidden = true; mEl.innerHTML = ''; }

function openDelete() {
  const c = charAt(sel);
  if (!c) return;
  showModal('delete', `
    <div class="dlg danger nz-frame"><div class="nz-frame-in nz-rail">
      <div class="dlg-head"><span class="nz-tile red">${NZ.icon('trash')}</span>
        <div><h2>Delete ${NZ.esc(full(c))}</h2><p>Slot ${pad(sel + 1)} · CID ${NZ.esc(c.cid)}</p></div></div>
      <div class="dlg-body">
        <p>This permanently removes the character with their money, vehicles, phone and property. It cannot be undone.
          Type <code>${NZ.esc(c.first)}</code> to confirm.</p>
        <div class="nz-field"><label for="confirm-name">First name</label>
          <input class="nz-input" id="confirm-name" autocomplete="off" spellcheck="false" placeholder="${NZ.esc(c.first)}"></div>
      </div>
      <div class="dlg-foot">
        <div class="nz-hints"><span><span class="nz-key">ESC</span>Cancel</span></div>
        <button class="nz-btn line" data-cancel>Cancel</button>
        <button class="nz-btn red solid" id="do-del" disabled>${NZ.icon('trash')}Delete forever</button>
      </div>
    </div></div>`);
  const inp = NZ.$('#confirm-name'), btn = NZ.$('#do-del');
  const ok = () => inp.value.trim().toLowerCase() === String(c.first).trim().toLowerCase();
  inp.oninput = () => { btn.disabled = !ok(); };
  inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); if (ok()) doDelete(c); } };
  btn.onclick = () => ok() && doDelete(c);
  inp.focus();
}
function doDelete(c) {
  NZ.post('delete', { cid: c.cid });
  chars = chars.filter(x => x !== c);
  hideModal();
  lastPreview = null;
  renderAll();
  sendPreview();
}

const NAME_RE = /^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ' -]{1,15}$/;
function openCreate() {
  if (slotKind(sel) !== 'empty') return;
  const max = new Date(); max.setFullYear(max.getFullYear() - 18);
  const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  showModal('create', `
    <div class="dlg wide nz-frame"><div class="nz-frame-in nz-rail">
      <div class="dlg-head"><div class="nz-mark"></div>
        <div><h2>New character</h2><p>Slot ${pad(sel + 1)} · ${NZ.esc(cfg.server || 'Los Santos')}</p></div></div>
      <form class="form" id="cform" novalidate>
        <div class="nz-field"><label>First name</label><input class="nz-input" name="first" maxlength="16" autocomplete="off" spellcheck="false" placeholder="Marcus"><div class="err"></div></div>
        <div class="nz-field"><label>Last name</label><input class="nz-input" name="last" maxlength="16" autocomplete="off" spellcheck="false" placeholder="Delgado"><div class="err"></div></div>
        <div class="nz-field"><label>Date of birth <em>18+</em></label><input class="nz-input" type="date" name="dob" min="1930-01-01" max="${iso(max)}" value="1995-06-15"><div class="err"></div></div>
        <div class="nz-field"><label>Gender</label>
          <div class="seg" id="gender"><button type="button" data-g="male" class="on">Male</button><button type="button" data-g="female">Female</button></div><div class="err"></div></div>
        <div class="nz-field"><label>Nationality</label><input class="nz-input" name="nationality" maxlength="24" autocomplete="off" spellcheck="false" placeholder="American"><div class="err"></div></div>
        <div class="nz-field"><label>Height <em>140 to 220</em></label><div class="unit"><input class="nz-input" type="number" name="height" min="140" max="220" value="178"><i>cm</i></div><div class="err"></div></div>
        <div class="form-msg" id="cmsg"></div>
      </form>
      <div class="dlg-foot">
        <div class="nz-hints"><span><span class="nz-key">↵</span>Create</span><span><span class="nz-key">ESC</span>Cancel</span></div>
        <button class="nz-btn line" data-cancel>Cancel</button>
        <button class="nz-btn teal" id="do-create">${NZ.icon('check')}Create</button>
      </div>
    </div></div>`);
  let gender = 'male';
  NZ.$$('#gender button').forEach(b => b.onclick = () => {
    gender = b.dataset.g;
    NZ.$$('#gender button').forEach(x => x.classList.toggle('on', x === b));
  });
  const form = NZ.$('#cform');
  form.onsubmit = e => { e.preventDefault(); submitCreate(form, () => gender); };
  form.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); submitCreate(form, () => gender); } };
  NZ.$$('input', form).forEach(inp => inp.addEventListener('input', () => setErr(inp, '')));
  NZ.$('#do-create').onclick = () => submitCreate(form, () => gender);
  form.first.focus();
}
function setErr(inp, msg) {
  inp.classList.toggle('bad', !!msg);
  const err = inp.closest('.nz-field').querySelector('.err');
  if (err) err.textContent = msg;
}
const cap = s => s.replace(/(^|[\s'-])(\p{L})/gu, (m, a, b) => a + b.toUpperCase());

let creating = false;
async function submitCreate(form, getGender) {
  if (creating) return;
  const f = {
    first: cap(form.first.value.trim().replace(/\s+/g, ' ')),
    last: cap(form.last.value.trim().replace(/\s+/g, ' ')),
    dob: form.dob.value,
    nationality: cap(form.nationality.value.trim().replace(/\s+/g, ' ')),
    height: Math.round(+form.height.value),
  };
  let bad = false;
  const check = (inp, msg) => { setErr(inp, msg || ''); if (msg) bad = true; };
  check(form.first, !f.first ? 'Enter a first name' : !NAME_RE.test(f.first) ? 'Letters only, 2 to 16' : '');
  check(form.last, !f.last ? 'Enter a last name' : !NAME_RE.test(f.last) ? 'Letters only, 2 to 16' : '');
  const d = parseDob(f.dob);
  check(form.dob, !d ? 'Pick a valid date' : ageOf(d) < 18 ? 'Must be 18 or older' : ageOf(d) > 95 ? 'Pick a later year' : '');
  check(form.nationality, !f.nationality ? 'Enter a nationality' : !/^[\p{L}][\p{L} '-]{1,23}$/u.test(f.nationality) ? 'Letters only' : '');
  check(form.height, !(f.height >= 140 && f.height <= 220) ? 'Between 140 and 220 cm' : '');
  if (bad) { form.querySelector('.bad')?.focus(); return; }

  const payload = { slot: sel + 1, ...f, gender: getGender() };
  const msg = NZ.$('#cmsg');
  msg.textContent = '';
  creating = true;
  NZ.$('#do-create').disabled = true;
  const res = await NZ.post('create', payload);
  creating = false;
  if (!NZ.$('#do-create')) return;
  NZ.$('#do-create').disabled = false;

  if (res && res.ok === false) { msg.textContent = res.error || 'Could not create this character'; return; }
  let made = null;
  if (!NZ.inGame) {
    made = { cid: 'LS' + Math.floor(10000 + Math.random() * 89999), job: 'Unemployed', grade: 'Freelancer',
      cash: 500, bank: 5000, phone: `(555) ${100 + Math.floor(Math.random() * 899)}-${1000 + Math.floor(Math.random() * 8999)}`,
      lastPlayed: null, ...payload };
  } else if (res && res.cid) {
    made = { job: 'Unemployed', cash: 0, bank: 0, lastPlayed: null, ...payload, ...res };
  }
  hideModal();
  if (made) {
    chars = chars.filter(c => +c.slot !== +made.slot).concat(made);
    lastPreview = null;
    renderAll();
    sendPreview();
  }
}

/* ── keys ── */
window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  if (modal) {
    if (e.key === 'Escape') { e.preventDefault(); hideModal(); }
    return;
  }
  const k = e.key;
  if (k === 'ArrowRight') select(sel + 1);
  else if (k === 'ArrowLeft') select(sel - 1);
  else if (k === 'Enter') activate();
  else if (k === 'Delete') openDelete();
  else return;
  e.preventDefault();
});

/* ── open / close ── */
function openUI(d) {
  d = d || {};
  cfg = { server: d.server || '', slots: Math.max(1, +d.slots || 5), allowed: Math.max(0, d.allowed != null ? +d.allowed : 3) };
  chars = Array.isArray(d.characters) ? d.characters.slice() : [];
  // characters without a slot fill the first free ones
  chars.forEach(c => {
    if (!c.slot) for (let i = 1; i <= cfg.slots; i++) if (!chars.some(x => +x.slot === i)) { c.slot = i; break; }
  });
  cfg.slots = Math.max(cfg.slots, ...chars.map(c => +c.slot || 0));
  // start on the most recently played character, else the first one, else slot 1
  const recent = chars.slice().sort((a, b) => stamp(b.lastPlayed) - stamp(a.lastPlayed))[0];
  sel = recent ? +recent.slot - 1 : 0;
  hideModal();
  lastPreview = null;
  renderAll();
  NZ.open(app);
  sendPreview();
}
NZ.on('open', openUI);
NZ.on('close', () => { hideModal(); NZ.close(app, { notify: false }); });

NZ.preview(() => {
  const now = Date.now() / 1000;
  openUI({
    server: 'Los Santos Roleplay · EU 1',
    slots: 5, allowed: 3,
    characters: [
      { cid: 'LS48213', slot: 1, first: 'Marcus', last: 'Delgado', job: 'Los Santos Police Department', grade: 'Sergeant',
        cash: 2450, bank: 84320, dob: '1991-03-14', nationality: 'American', phone: '(555) 214-8831', gender: 'male',
        lastPlayed: now - 7200 },
      { cid: 'LS77102', slot: 2, first: 'Ava', last: 'Kowalski', job: 'Pillbox Medical Center', grade: 'Paramedic',
        cash: 610, bank: 23975, dob: '1996-11-02', nationality: 'Polish', phone: '(555) 908-4417', gender: 'female',
        lastPlayed: now - 86400 * 4 },
    ],
  });
});
