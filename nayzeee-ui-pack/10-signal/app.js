/* 10 · SIGNAL — always-on overlay layer (no close callback)
   SendNUIMessage({ action = 'notify',   data = { type = 'success'|'error'|'warn'|'info', title, text, duration = 5000 } })
   SendNUIMessage({ action = 'announce', data = { label = 'SERVER', title, text, duration = 8000, countdown = 600 } })
   SendNUIMessage({ action = 'textui',   data = { key = 'E', text = 'Open stash', sub } })   -- data = { hide = true } to remove
   SendNUIMessage({ action = 'progress', data = { label, duration = 5000, icon, canCancel = true } })
   SendNUIMessage({ action = 'progressCancel' })
   SendNUIMessage({ action = 'input',    data = { title, text, submit, fields = {
                    {id, label, type = 'text'|'number'|'select'|'textarea'|'checkbox', placeholder, options = {{value,label}}, required, default, min, max} } } })
   SendNUIMessage({ action = 'confirm',  data = { title, text, confirm = 'Confirm', cancel = 'Cancel', danger = true } })
   Callbacks: progress {done = true} | {cancelled = true}
              input {values = {...}} | {cancelled = true}
              confirm {ok = true|false}
   Remember SetNuiFocus(true, true) in Lua while an input or confirm dialog is up.
*/
const app = NZ.$('#app');
NZ.open(app);

/* ── notify ── */
const TONES = { success: ['', 'check'], error: ['err', 'error'], warn: ['warn', 'alert'], info: ['info', 'info'] };
const TILE = { success: '', error: 'red', warn: 'amber', info: 'mute' };
function notify(d) {
  const type = TONES[d.type] ? d.type : 'success';
  const [cls, ic] = TONES[type];
  const ms = d.duration || 5000;
  const el = document.createElement('div');
  el.className = `toast ${cls}`;
  el.innerHTML = `<div class="nz-tile ${TILE[type]}">${NZ.icon(ic)}</div>
    <div><b>${NZ.esc(d.title || '')}</b>${d.text ? `<p>${NZ.esc(d.text)}</p>` : ''}</div>
    <span class="t">now</span><i class="timer" style="animation-duration:${ms}ms"></i>`;
  const box = NZ.$('#toasts');
  box.prepend(el);
  while (box.children.length > 5) box.lastElementChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, ms);
}

/* ── announce ── */
let annT = null, annTick = null;
function announce(d) {
  clearTimeout(annT); clearInterval(annTick);
  const host = NZ.$('#announce');
  let left = d.countdown || 0;
  const mmss = s => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  host.innerHTML = `<div class="announce"><div class="nz-mark"></div><div class="tx"><small>${NZ.esc((d.label || 'Announcement').toUpperCase())}</small>
    <b>${NZ.esc(d.title || '')}</b>${d.text ? `<p>${NZ.esc(d.text)}</p>` : ''}</div>${left ? `<span class="count">${mmss(left)}</span>` : ''}</div>`;
  if (left) annTick = setInterval(() => { left = Math.max(0, left - 1); const c = host.querySelector('.count'); if (c) c.textContent = mmss(left); }, 1000);
  annT = setTimeout(() => {
    host.firstElementChild?.classList.add('out');
    setTimeout(() => { host.innerHTML = ''; clearInterval(annTick); }, 300);
  }, d.duration || 8000);
}

/* ── text ui ── */
function textui(d) {
  const host = NZ.$('#textui');
  if (d.hide || d.show === false) {
    host.firstElementChild?.classList.add('out');
    setTimeout(() => { if (host.firstElementChild?.classList.contains('out')) host.innerHTML = ''; }, 200);
    return;
  }
  host.innerHTML = `<div class="textui"><span class="k">${NZ.esc(d.key || 'E')}</span><div><b>${NZ.esc(d.text || '')}</b>${d.sub ? `<span>${NZ.esc(d.sub)}</span>` : ''}</div></div>`;
}

/* ── progress ── */
let prog = null;
function progress(d) {
  if (prog) endProgress(false, true);
  const host = NZ.$('#progress');
  const ms = d.duration || 5000;
  host.innerHTML = `<div class="progress"><div class="top"><b>${NZ.icon(d.icon || 'timer')}${NZ.esc(d.label || 'Working…')}</b><span id="pct">0%</span></div>
    <div class="track"><div class="fill" id="fill"></div></div>
    <div class="foot nz-hints">${d.canCancel !== false ? '<span><span class="nz-key">X</span>Cancel</span>' : '<span></span>'}<span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span></div></div>`;
  const start = performance.now();
  prog = { canCancel: d.canCancel !== false, raf: 0 };
  const step = now => {
    const p = Math.min(1, (now - start) / ms);
    NZ.$('#fill').style.width = p * 100 + '%';
    NZ.$('#pct').textContent = Math.floor(p * 100) + '%';
    if (p < 1) prog.raf = requestAnimationFrame(step); else endProgress(true);
  };
  prog.raf = requestAnimationFrame(step);
}
function endProgress(done, silent) {
  if (!prog) return;
  cancelAnimationFrame(prog.raf);
  prog = null;
  if (!silent) NZ.post('progress', done ? { done: true } : { cancelled: true });
  const el = NZ.$('#progress .progress');
  if (!el) return;
  if (!done) { el.classList.add('cancelled'); NZ.$('#pct').textContent = 'Cancelled'; }
  setTimeout(() => { el.classList.add('out'); setTimeout(() => { if (!prog) NZ.$('#progress').innerHTML = ''; }, 200); }, done ? 150 : 700);
}
window.addEventListener('keydown', e => {
  if (prog && prog.canCancel && e.key.toLowerCase() === 'x' && !NZ.$('#dialog').firstElementChild) endProgress(false);
});

/* ── dialogs ── */
function field(f) {
  const id = `f-${NZ.esc(f.id)}`, req = f.required ? ' required' : '';
  const val = f.default != null ? ` value="${NZ.esc(f.default)}"` : '';
  if (f.type === 'checkbox') return `<div class="check"><span>${NZ.esc(f.label)}</span><span class="nz-sw ${f.default ? 'on' : ''}" data-id="${NZ.esc(f.id)}"><i></i></span></div>`;
  let ctl;
  if (f.type === 'select') ctl = `<select class="nz-input" id="${id}" name="${NZ.esc(f.id)}">${(f.options || []).map(o => `<option value="${NZ.esc(o.value)}" ${o.value == f.default ? 'selected' : ''}>${NZ.esc(o.label)}</option>`).join('')}</select>`;
  else if (f.type === 'textarea') ctl = `<textarea class="nz-input" id="${id}" name="${NZ.esc(f.id)}" placeholder="${NZ.esc(f.placeholder || '')}"${req}>${NZ.esc(f.default || '')}</textarea>`;
  else ctl = `<input class="nz-input" id="${id}" name="${NZ.esc(f.id)}" type="${f.type === 'number' ? 'number' : 'text'}" placeholder="${NZ.esc(f.placeholder || '')}"${val}${req}${f.min != null ? ` min="${f.min}"` : ''}${f.max != null ? ` max="${f.max}"` : ''}>`;
  return `<div class="nz-field"><label for="${id}">${NZ.esc(f.label)}</label>${ctl}</div>`;
}

let dlgDone = null;
function dialog(html, onEnter) {
  const host = NZ.$('#dialog');
  host.innerHTML = `<div class="scrim live">${html}</div>`;
  NZ.hydrate(host);
  host.querySelectorAll('.nz-sw').forEach(s => s.onclick = () => s.classList.toggle('on'));
  dlgDone = onEnter;
  setTimeout(() => host.querySelector('input,select,textarea,.nz-btn.teal,.nz-btn.red')?.focus(), 50);
}
const closeDialog = () => { NZ.$('#dialog').innerHTML = ''; dlgDone = null; };

function input(d) {
  dialog(`<div class="dlg"><div class="hd"><div class="nz-tile"><i data-ic="${NZ.esc(d.icon || 'clipboard')}"></i></div>
      <div><h3>${NZ.esc(d.title || 'Input')}</h3>${d.text ? `<p>${NZ.esc(d.text)}</p>` : ''}</div></div>
    <form id="dlg-form" novalidate>${(d.fields || []).map(field).join('')}<span class="err" id="dlg-err"></span></form>
    <div class="ft"><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>
      <button class="nz-btn line" data-x>${NZ.esc(d.cancel || 'Cancel')}</button><button class="nz-btn teal" data-ok>${NZ.esc(d.submit || 'Submit')}</button></div></div>`);
  const submit = () => {
    const values = {};
    let bad = false;
    (d.fields || []).forEach(f => {
      if (f.type === 'checkbox') { values[f.id] = NZ.$(`.nz-sw[data-id="${CSS.escape(f.id)}"]`).classList.contains('on'); return; }
      const el = NZ.$(`#f-${CSS.escape(f.id)}`);
      const v = el.value.trim();
      const miss = f.required && !v;
      el.classList.toggle('bad', miss);
      bad = bad || miss;
      values[f.id] = f.type === 'number' ? (v === '' ? null : +v) : v;
    });
    if (bad) { NZ.$('#dlg-err').textContent = 'Fill in the highlighted fields.'; return; }
    closeDialog();
    NZ.post('input', { values });
  };
  NZ.$('#dlg-form').onsubmit = e => { e.preventDefault(); submit(); };
  NZ.$('#dialog [data-ok]').onclick = submit;
  NZ.$('#dialog [data-x]').onclick = () => { closeDialog(); NZ.post('input', { cancelled: true }); };
  dlgDone = submit;
}

function confirmBox(d) {
  dialog(`<div class="dlg"><div class="hd"><div class="nz-tile ${d.danger ? 'red' : ''}"><i data-ic="${d.danger ? 'alert' : 'info'}"></i></div>
      <div><h3>${NZ.esc(d.title || 'Are you sure?')}</h3>${d.text ? `<p>${NZ.esc(d.text)}</p>` : ''}</div></div>
    <div style="height:18px"></div>
    <div class="ft"><span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>
      <button class="nz-btn line" data-x>${NZ.esc(d.cancel || 'Cancel')}</button><button class="nz-btn ${d.danger ? 'red' : 'teal'}" data-ok>${NZ.esc(d.confirm || 'Confirm')}</button></div></div>`);
  const answer = ok => { closeDialog(); NZ.post('confirm', { ok }); };
  NZ.$('#dialog [data-ok]').onclick = () => answer(true);
  NZ.$('#dialog [data-x]').onclick = () => answer(false);
  dlgDone = () => answer(true);
}

window.addEventListener('keydown', e => {
  if (!NZ.$('#dialog').firstElementChild) return;
  if (e.key === 'Escape') NZ.$('#dialog [data-x]')?.click();
  else if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA' && dlgDone) { e.preventDefault(); dlgDone(); }
});

NZ.on('notify', notify);
NZ.on('announce', announce);
NZ.on('textui', textui);
NZ.on('progress', progress);
NZ.on('progressCancel', () => endProgress(false));
NZ.on('input', input);
NZ.on('confirm', confirmBox);

/* ── browser preview: a control panel to fire each overlay ── */
NZ.preview(() => {
  const demo = document.createElement('div');
  demo.className = 'demo';
  demo.innerHTML = `<b>Preview controls · not shown in game</b><div>
    <button class="nz-btn ghost sm" data-d="ok">Notify</button><button class="nz-btn ghost sm" data-d="err">Error</button>
    <button class="nz-btn ghost sm" data-d="warn">Warning</button><button class="nz-btn ghost sm" data-d="ann">Announce</button>
    <button class="nz-btn ghost sm" data-d="ui">Text UI</button><button class="nz-btn ghost sm" data-d="prog">Progress</button>
    <button class="nz-btn ghost sm" data-d="in">Input</button><button class="nz-btn ghost sm" data-d="cf">Confirm</button></div>`;
  document.body.appendChild(demo);
  let ui = false;
  const A = {
    ok: () => notify({ type: 'success', title: 'Report filed', text: 'MED-215 was saved to the patient record.' }),
    err: () => notify({ type: 'error', title: "You're not on duty", text: 'Sign in at the station terminal to file reports.' }),
    warn: () => notify({ type: 'warn', title: 'Low fuel', text: 'Ambulance 04 is under 15%. Refuel soon.' }),
    ann: () => announce({ label: 'Server', title: 'Scheduled restart', text: 'Park your vehicles and log off safely.', countdown: 600, duration: 9000 }),
    ui: () => { ui = !ui; textui(ui ? { key: 'E', text: 'Open stash', sub: 'Pillbox locker · 12 / 40 slots' } : { hide: true }); },
    prog: () => progress({ label: 'Applying bandage', icon: 'bandage', duration: 4000 }),
    in: () => input({ title: 'Send invoice', text: 'The player gets a bill they can pay from their phone.', icon: 'receipt', submit: 'Send invoice', fields: [
      { id: 'target', label: 'Player ID', type: 'number', placeholder: 'e.g. 14', required: true },
      { id: 'amount', label: 'Amount', type: 'number', placeholder: '$0', required: true, min: 1 },
      { id: 'reason', label: 'Reason', type: 'select', options: [{ value: 'treat', label: 'Medical treatment' }, { value: 'tow', label: 'Towing' }, { value: 'other', label: 'Other' }] },
      { id: 'notify', label: 'Text them a receipt', type: 'checkbox', default: true },
    ] }),
    cf: () => confirmBox({ title: 'Delete this report?', text: 'MED-214 and its attached patient notes will be removed. This cannot be undone.', confirm: 'Delete report', cancel: 'Keep report', danger: true }),
  };
  demo.querySelectorAll('[data-d]').forEach(b => b.onclick = () => A[b.dataset.d]());

  A.ok(); setTimeout(A.err, 250); setTimeout(A.warn, 500);
  A.ann(); A.ui();
  progress({ label: 'Applying bandage', icon: 'bandage', duration: 14000, canCancel: true });
});
