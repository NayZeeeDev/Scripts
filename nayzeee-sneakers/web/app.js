const $ = id => document.getElementById(id);
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-sneakers';
const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
    .catch(() => {});

const img = name => name ? `images/${name}.png` : '';
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/* ---------------- menu ---------------- */
let options = [], sel = 0, open = false;

function renderSel() {
  [...$('menuList').children].forEach((el, i) => el.classList.toggle('sel', i === sel));
  $('menuList').children[sel]?.scrollIntoView({ block: 'nearest' });
}

function showMenu(menu) {
  options = menu.options || [];
  sel = Math.max(0, options.findIndex(o => !o.disabled));
  $('menuTitle').textContent = menu.title || '';
  $('menuSub').textContent = menu.subtitle || '';
  $('menuSub').hidden = !menu.subtitle;
  const mi = $('menuImg');
  mi.hidden = !menu.image;
  if (menu.image) mi.querySelector('img').src = img(menu.image);

  $('menuList').innerHTML = '';
  options.forEach((o, i) => {
    const b = document.createElement('button');
    b.className = 'opt';
    b.disabled = !!o.disabled;
    const icon = o.image ? `<img src="${img(o.image)}" alt="">` : `<i class="${esc(o.icon || 'fa-solid fa-chevron-right')}"></i>`;
    b.innerHTML = `<span class="ic">${icon}</span><span class="tx"><span class="lb">${esc(o.label)}</span>` +
      (o.description ? `<span class="ds">${esc(o.description)}</span>` : '') + `</span>`;
    b.addEventListener('mouseenter', () => { sel = i; renderSel(); });
    b.addEventListener('click', () => choose(i));
    $('menuList').appendChild(b);
  });
  $('menu').hidden = false;
  open = true;
  renderSel();
}

function hideMenu() { $('menu').hidden = true; open = false; }
function choose(i) {
  const o = options[i];
  if (!o || o.disabled) return;
  hideMenu();
  post('menuSelect', { id: o.id });
}
function closeMenu() { if (!open) return; hideMenu(); post('menuClose'); }

$('menuClose').addEventListener('click', closeMenu);
addEventListener('keydown', e => {
  if (!open) return;
  if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); closeMenu(); }
  else if (e.key === 'ArrowDown') { e.preventDefault(); step(1); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); step(-1); }
  else if (e.key === 'Enter') { e.preventDefault(); choose(sel); }
});
function step(d) {
  if (!options.length) return;
  for (let k = 0; k < options.length; k++) {
    sel = (sel + d + options.length) % options.length;
    if (!options[sel].disabled) break;
  }
  renderSel();
}

/* ---------------- inspect ---------------- */
function showInspect(show, d, hint) {
  $('inspect').hidden = !show;
  $('inspectHint').hidden = !show;
  if (!show || !d) return;
  $('insImg').src = img(d.image);
  $('insName').textContent = d.name;
  $('insColour').textContent = d.colourway;
  $('insSize').textContent = 'US ' + d.size;
  $('insCond').textContent = d.condition;
  $('insSerial').textContent = d.serial || '—';
  const dirt = Math.max(0, Math.min(100, d.dirt || 0));
  $('insDirtTxt').textContent = dirt < 5 ? 'Clean' : dirt + '%';
  const bar = $('insDirt');
  bar.style.width = dirt + '%';
  bar.className = dirt >= 60 ? 'high' : dirt >= 25 ? 'mid' : '';
  $('inspectHint').textContent = hint || '';
}

/* ---------------- toasts ---------------- */
const ICONS = { success: 'fa-solid fa-check', error: 'fa-solid fa-xmark', warning: 'fa-solid fa-triangle-exclamation', inform: 'fa-solid fa-circle-info' };
function toast(text, kind = 'inform') {
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.innerHTML = `<i class="${ICONS[kind] || ICONS.inform}"></i><span>${esc(text)}</span>`;
  $('toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 3800);
}

/* ---------------- messages ---------------- */
addEventListener('message', ({ data }) => {
  if (!data || !data.action) return;
  if (data.action === 'menu') showMenu(data.menu || {});
  else if (data.action === 'inspect') showInspect(data.show, data.data, data.hint);
  else if (data.action === 'toast') toast(data.text, data.kind);
});
