/* NayZeee Sneaker Studio - talks only to the local studio process */
'use strict';

const $ = (id) => document.getElementById(id);
const ICONS = {
  book: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  shoe: '<path d="M3 16v-5l4-1 3 3h4l7 2v3H3z"/><path d="M3 19h18"/>',
  spark: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
  refresh: '<path d="M20 11a8 8 0 0 0-14.9-3M4 13a8 8 0 0 0 14.9 3"/><path d="M5 3v5h5M19 21v-5h-5"/>',
  check: '<path d="m5 12 5 5L20 7"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  wand: '<path d="m15 4 5 5L9 20l-5-5z"/><path d="M13 6l5 5"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  up: '<path d="m18 15-6-6-6 6"/>',
  drive: '<rect x="3" y="12" width="18" height="7" rx="2"/><path d="M7 16h.01M5 12l2-7h10l2 7"/>',
  server: '<rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><path d="M7 7.5h.01M7 16.5h.01"/>',
  warn: '<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
};
function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
}
function paintIcons(root = document) {
  root.querySelectorAll('[data-icon]').forEach((el) => {
    if (!el.dataset.painted) { el.insertAdjacentHTML('afterbegin', icon(el.dataset.icon)); el.dataset.painted = '1'; }
  });
}
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function api(path, body) {
  const res = await fetch(path, body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

function toast(msg, type = 'success', life = 3800) {
  const el = document.createElement('div');
  el.className = 'toast ' + type;
  el.style.setProperty('--life', life + 'ms');
  el.innerHTML = `<div class="ti">${icon(type === 'error' ? 'warn' : type === 'warning' ? 'warn' : 'check')}</div><div><b>${esc(msg)}</b></div>`;
  $('toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, life);
}

// ---------------------------------------------------------------- state

const S = {
  items: [], picked: new Set(), labels: {}, boxes: {}, filter: 'all', gender: 'all', query: '',
  texSize: 512, maxTris: 24000, running: false, lastClick: null, out: '',
};

function seg(id, onPick) {
  $(id).addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    $(id).querySelectorAll('button').forEach((x) => x.classList.toggle('on', x === b));
    onPick(b.dataset.v);
  });
}
function setSeg(id, v) { $(id).querySelectorAll('button').forEach((x) => x.classList.toggle('on', x.dataset.v === String(v))); }

seg('texSize', (v) => { S.texSize = +v; });
seg('maxTris', (v) => { S.maxTris = +v; });
seg('gender', (v) => { S.gender = v; render(); });
$('search').addEventListener('input', (e) => { S.query = e.target.value.trim().toLowerCase(); render(); });
$('stats').addEventListener('click', (e) => {
  const st = e.target.closest('.stat'); if (!st) return;
  S.filter = st.dataset.f;
  document.querySelectorAll('#stats .stat').forEach((x) => x.classList.toggle('on', x === st));
  render();
});

// ---------------------------------------------------------------- scan

const STATUS = {
  new: ['live', 'New'], changed: ['warn', 'Changed'], done: ['off', 'Up to date'], removed: ['hot', 'Removed'],
};

async function scan() {
  const root = $('root').value.trim();
  if (!root) { toast('Pick your server folder first', 'warning'); return; }
  $('scanBtn').disabled = true;
  $('scanBtn').lastChild.textContent = 'Scanning...';
  try {
    const r = await api('/api/scan', { root, out: $('out').value.trim(), textureSize: S.texSize, maxTriangles: S.maxTris });
    S.items = r.items; S.out = r.out;
    $('out').value = r.out;
    S.picked = new Set(r.items.filter((i) => i.status === 'new' || i.status === 'changed').map((i) => i.key));
    S.labels = {}; S.boxes = {};
    showInventory(r.inventory);
    const n = r.items.filter((i) => i.status !== 'removed').length;
    toast(n ? `Found ${n} shoe${n === 1 ? '' : 's'}` : 'No shoes found in that folder', n ? 'success' : 'warning');
    note(n ? '' : 'No <b>feet_XXX_u.ydd</b> files were found. Pick the folder your clothing packs are in (your resources folder works).', 'warn');
    render();
  } catch (err) {
    toast(err.message, 'error');
  } finally {
    $('scanBtn').disabled = false;
    $('scanBtn').lastChild.textContent = 'Scan for shoes';
  }
}
$('scanBtn').addEventListener('click', scan);
$('root').addEventListener('keydown', (e) => { if (e.key === 'Enter') scan(); });

function note(html, kind = '') {
  const n = $('sideNote');
  n.className = 'note' + (html ? ' show ' + kind : '');
  n.innerHTML = html;
}

function showInventory(path) {
  $('invPath').textContent = path ? 'Found: ' + path : 'No inventory found in the server folder. Icons stay in the props folder (icons/).';
}

// ---------------------------------------------------------------- cards

function visible() {
  return S.items.filter((i) => {
    if (S.filter !== 'all' && i.status !== S.filter) return false;
    if (S.gender !== 'all' && i.gender !== S.gender) return false;
    if (!S.query) return true;
    const label = (S.labels[i.key] ?? i.label).toLowerCase();
    return label.includes(S.query) || i.collection.toLowerCase().includes(S.query)
      || String(i.drawable).padStart(3, '0').includes(S.query) || i.folder.toLowerCase().includes(S.query);
  });
}

const observer = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    const img = e.target;
    observer.unobserve(img);
    img.src = img.dataset.src;
  }
}, { rootMargin: '300px' });

function counts() {
  const c = { all: 0, new: 0, changed: 0, done: 0, removed: 0 };
  for (const i of S.items) { c[i.status]++; if (i.status !== 'removed') c.all++; }
  $('nAll').textContent = c.all; $('nNew').textContent = c.new; $('nChanged').textContent = c.changed;
  $('nDone').textContent = c.done; $('nRemoved').textContent = c.removed;
}

function render() {
  counts();
  const list = visible();
  const grid = $('grid');
  $('empty').hidden = S.items.length > 0;
  grid.innerHTML = list.map((i) => {
    const [cls, txt] = STATUS[i.status];
    const picked = S.picked.has(i.key);
    const g = i.gender === 'male' ? 'Male' : i.gender === 'female' ? 'Female' : 'Gender?';
    const pack = i.loose ? 'Loose download' : i.collection ? i.collection : 'Base game slot';
    const box = S.boxes[i.key] ?? '';
    const notes = (i.notes || []).map((n) => `<div class="warn">${esc(n)}</div>`).join('');
    const src = i.status === 'removed' ? '' : `/api/preview?key=${encodeURIComponent(i.key)}&h=${i.hash}`;
    return `<div class="card${picked ? ' picked' : ''}${i.status === 'removed' ? ' removed' : ''}" data-key="${esc(i.key)}">
      <div class="pv" data-act="pick">
        ${src ? `<img data-src="${src}" alt="" onload="this.classList.add('ok')" onerror="this.nextElementSibling.classList.add('off')"><span class="spin"></span>` : ''}
        <span class="tag ${cls} st">${txt}</span>
        ${i.status === 'removed' ? '' : `<span class="pick">${icon('check')}</span>`}
      </div>
      <div class="body">
        <input class="name" value="${esc(S.labels[i.key] ?? i.label)}" data-act="label" spellcheck="false" ${i.status === 'removed' ? 'disabled' : ''}>
        <div class="meta">
          <span class="chip${i.gender === 'unknown' ? ' amber' : ''}">${g}</span>
          <span class="chip" style="color:var(--ink-2);background:var(--raise);border-color:var(--line)">${i.colours} colour${i.colours === 1 ? '' : 's'}</span>
          ${i.skin ? '<span class="chip amber">Skin tone</span>' : ''}
          <span class="ref" style="margin-left:auto">#${String(i.drawable).padStart(3, '0')}</span>
        </div>
        <div class="src" title="${esc(i.folder)}">${esc(pack)} · ${esc(i.folder)}</div>
        ${i.status === 'removed' ? '<div class="warn">Not on the server any more. Its props are removed when you convert.</div>' : `
        <div class="boxrow"><span>Box${i.box ? ` (now: ${esc(i.box)})` : ''}</span>
          <select data-act="box">
            <option value="" ${box === '' ? 'selected' : ''}>Auto</option>
            <option value="shoe" ${box === 'shoe' ? 'selected' : ''}>Shoe box</option>
            <option value="heel" ${box === 'heel' ? 'selected' : ''}>Heel box</option>
            <option value="boot" ${box === 'boot' ? 'selected' : ''}>Boot box</option>
          </select></div>`}
        ${notes}
      </div>
    </div>`;
  }).join('');
  grid.querySelectorAll('img[data-src]').forEach((img) => observer.observe(img));
  updatePick();
}

$('grid').addEventListener('click', (e) => {
  const card = e.target.closest('.card'); if (!card) return;
  if (e.target.closest('[data-act="pick"]')) togglePick(card.dataset.key, e.shiftKey);
});
$('grid').addEventListener('input', (e) => {
  const card = e.target.closest('.card'); if (!card) return;
  if (e.target.dataset.act === 'label') {
    S.labels[card.dataset.key] = e.target.value;
    // a renamed shoe that's already converted just needs its name saved
    if (!S.picked.has(card.dataset.key)) { S.picked.add(card.dataset.key); card.classList.add('picked'); updatePick(); }
  }
});
$('grid').addEventListener('change', (e) => {
  const card = e.target.closest('.card'); if (!card) return;
  if (e.target.dataset.act === 'box') {
    S.boxes[card.dataset.key] = e.target.value;
    if (!S.picked.has(card.dataset.key)) { S.picked.add(card.dataset.key); card.classList.add('picked'); updatePick(); }
  }
});

function togglePick(key, range) {
  const item = S.items.find((i) => i.key === key);
  if (!item || item.status === 'removed') return;
  const list = visible().filter((i) => i.status !== 'removed').map((i) => i.key);
  if (range && S.lastClick && list.includes(S.lastClick)) {
    const [a, b] = [list.indexOf(S.lastClick), list.indexOf(key)].sort((x, y) => x - y);
    const on = !S.picked.has(key);
    for (const k of list.slice(a, b + 1)) on ? S.picked.add(k) : S.picked.delete(k);
  } else {
    S.picked.has(key) ? S.picked.delete(key) : S.picked.add(key);
  }
  S.lastClick = key;
  document.querySelectorAll('.card').forEach((c) => c.classList.toggle('picked', S.picked.has(c.dataset.key)));
  updatePick();
}

$('pickAll').addEventListener('click', () => {
  for (const i of visible()) if (i.status !== 'removed') S.picked.add(i.key);
  render();
});
$('pickNone').addEventListener('click', () => { S.picked.clear(); render(); });

function updatePick() {
  const n = S.picked.size;
  const removed = S.items.filter((i) => i.status === 'removed').length;
  const rm = $('removeMissing').checked && removed > 0;
  $('convertBtn').disabled = S.running || (n === 0 && !rm);
  $('convertTxt').textContent = n ? `Convert ${n} shoe${n === 1 ? '' : 's'}` : rm ? `Remove ${removed} old shoe${removed === 1 ? '' : 's'}` : 'Convert';
  if (!S.running) {
    const colours = S.items.filter((i) => S.picked.has(i.key)).reduce((a, i) => a + i.colours, 0);
    $('pickInfo').innerHTML = n ? `<b>${n}</b> selected · <b>${colours}</b> props and <b>${colours * 2}</b> icons will be made` : 'Nothing selected';
  }
}
$('removeMissing').addEventListener('change', updatePick);

// ---------------------------------------------------------------- convert

async function convert() {
  const keys = [...S.picked];
  try {
    await api('/api/convert', {
      keys, labels: S.labels, boxes: Object.fromEntries(Object.entries(S.boxes).filter(([, v]) => v)),
      removeMissing: $('removeMissing').checked, copyIcons: $('copyIcons').checked,
    });
  } catch (err) { toast(err.message, 'error'); return; }
  S.running = true;
  $('convertBtn').disabled = true; $('scanBtn').disabled = true;
  $('progress').hidden = false; $('pickInfo').hidden = true; $('logBtn').hidden = false; $('openBtn').hidden = true;
  poll();
}
$('convertBtn').addEventListener('click', convert);

async function poll() {
  let j;
  try { j = await api('/api/job'); } catch { setTimeout(poll, 1000); return; }
  $('pBar').style.width = (j.total ? (j.done / j.total) * 100 : 100) + '%';
  $('pNum').textContent = `${j.done} / ${j.total}`;
  $('pCur').textContent = j.running ? (j.current ? 'Converting ' + j.current : 'Finishing up...') : 'Done';
  $('log').innerHTML = j.log.map((l) => `<div${/FAILED|couldn't/.test(l) ? ' class="bad"' : ''}>${esc(l)}</div>`).join('');
  $('log').scrollTop = 1e9;
  if (j.running) { setTimeout(poll, 600); return; }
  S.running = false;
  $('scanBtn').disabled = false; $('openBtn').hidden = false;
  if (j.error) { toast(j.error, 'error', 6000); }
  else if (j.result) {
    const r = j.result;
    const parts = [`${r.converted} converted`];
    if (r.removed) parts.push(`${r.removed} removed`);
    if (r.failed) parts.push(`${r.failed} failed`);
    toast(parts.join(' · '), r.failed ? 'warning' : 'success', 6000);
    if (r.failed) note('Some shoes couldn\'t be converted:<br>' + r.errors.map(esc).join('<br>'), 'err');
    else note(`Done. Put <b>${esc(S.out)}</b> in your resources and <b>ensure nayzeee-sneakers-props</b> before nayzeee-sneakers, then use <b>/sneakerstudio</b> in game.`);
  }
  setTimeout(() => { $('progress').hidden = true; $('pickInfo').hidden = false; scan(); }, 1200);
}

$('openBtn').addEventListener('click', () => api('/api/open', { path: S.out }));
$('logBtn').addEventListener('click', () => { $('logModal').hidden = false; });
$('logClose').addEventListener('click', () => { $('logModal').hidden = true; });

// ---------------------------------------------------------------- folder picker

let pickTarget = null, pickPath = '';
document.querySelectorAll('[data-pick]').forEach((b) => b.addEventListener('click', () => openPicker(b.dataset.pick)));
async function openPicker(target) {
  pickTarget = target;
  $('pickerTitle').textContent = target === 'root' ? 'SERVER FOLDER' : 'SAVE PROPS TO';
  $('picker').hidden = false;
  await browse($(target).value.trim());
}
async function browse(path) {
  const r = await api('/api/dirs?path=' + encodeURIComponent(path || ''));
  pickPath = r.path;
  $('pickerPath').textContent = r.path || 'This PC';
  const rows = [];
  if (r.parent !== null && r.parent !== undefined) rows.push(`<div class="row" data-p="${esc(r.parent)}"><div class="av">${icon('up')}</div><div class="row-txt"><b>..</b><span>Up a folder</span></div></div>`);
  else if (r.path) rows.push(`<div class="row" data-p=""><div class="av">${icon('up')}</div><div class="row-txt"><b>..</b><span>Drives</span></div></div>`);
  for (const d of r.dirs) {
    const name = d.replace(/[\\/]+$/, '').split(/[\\/]/).pop() || d;
    rows.push(`<div class="row" data-p="${esc(d)}"><div class="av">${icon(r.path ? 'folder' : 'drive')}</div><div class="row-txt"><b>${esc(name)}</b><span>${esc(d)}</span></div></div>`);
  }
  $('pickerList').innerHTML = rows.join('') || '<div class="hint">No folders in here.</div>';
  $('pickerHint').innerHTML = r.server ? '<span class="hint ok">This looks like a server folder.</span>' : '';
  $('pickerUse').disabled = !r.path;
}
$('pickerList').addEventListener('click', (e) => { const row = e.target.closest('.row'); if (row) browse(row.dataset.p); });
$('pickerClose').addEventListener('click', () => { $('picker').hidden = true; });
$('pickerUse').addEventListener('click', () => {
  if (!pickPath) return;
  let p = pickPath;
  // a server folder with a resources folder inside: scanning resources is quicker
  $(pickTarget).value = p;
  if (pickTarget === 'root' && !$('out').value.trim()) $('out').value = p.replace(/[\\/]+$/, '') + (p.includes('\\') ? '\\' : '/') + 'nayzeee-sneakers-props';
  $('picker').hidden = true;
});

// ---------------------------------------------------------------- guide

function guide(on) { $('guide').classList.toggle('on', on); $('scrim').classList.toggle('on', on); }
$('guideBtn').addEventListener('click', () => guide(true));
$('guideClose').addEventListener('click', () => guide(false));
$('scrim').addEventListener('click', () => guide(false));
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { guide(false); $('picker').hidden = true; $('logModal').hidden = true; }
});

// ---------------------------------------------------------------- start

(async () => {
  paintIcons();
  try {
    const st = await api('/api/state');
    const s = st.settings;
    $('ver').textContent = 'v' + (st.version || '1.0.0');
    $('root').value = s.root || ''; $('out').value = s.out || '';
    S.texSize = s.textureSize || 512; S.maxTris = s.maxTriangles || 24000;
    setSeg('texSize', S.texSize); setSeg('maxTris', S.maxTris);
    $('copyIcons').checked = s.copyIcons !== false; $('removeMissing').checked = s.removeMissing !== false;
    showInventory(st.inventory);
    if (s.root) scan();
  } catch { /* first run */ }
  render();
})();
