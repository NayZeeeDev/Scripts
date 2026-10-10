/* 08 · DIALOG
   SendNUIMessage({ action = 'open', data = { place, node } })
   SendNUIMessage({ action = 'node', data = node })        -- show the next line after a select
   node = { speaker, initials, role, rep = 0-100 (optional), text,     -- wrap words in *stars* to highlight
            options = { {id, label, hint, locked = 'Requires: ...', leave = true} } }
   Callbacks: select {id}, close
*/
const app = NZ.$('#app');
let node = null, typing = null, full = '', on = 0;

const fmt = s => NZ.esc(s).replace(/\*(.+?)\*/g, '<em>$1</em>');

function type(text) {
  clearInterval(typing);
  full = fmt(text);
  const plain = String(text).replace(/\*/g, '');
  const line = NZ.$('#line');
  let i = 0;
  NZ.$('#skip').classList.remove('gone');
  NZ.$('#opts').classList.add('wait');
  typing = setInterval(() => {
    i += 1;
    // type plain text, then swap in the highlighted version when done
    line.innerHTML = NZ.esc(plain.slice(0, i)) + '<span class="caret"></span>';
    if (i >= plain.length) finish();
  }, 22);
}
function finish() {
  clearInterval(typing); typing = null;
  NZ.$('#line').innerHTML = full + '<span class="caret"></span>';
  NZ.$('#skip').classList.add('gone');
  NZ.$('#opts').classList.remove('wait');
}

function show(n) {
  node = n; on = 0;
  NZ.$('#name').textContent = n.speaker;
  NZ.$('#role').textContent = n.role || '';
  NZ.$('#av').textContent = n.initials || NZ.initials(n.speaker);
  NZ.$('#rep').style.display = n.rep == null ? 'none' : '';
  if (n.rep != null) NZ.$('#rep-v').style.setProperty('--v', n.rep + '%');
  NZ.$('#opts').innerHTML = (n.options || []).map((o, i) => `
    <button class="opt ${o.leave ? 'leave' : ''} ${o.locked ? 'locked' : ''}" data-i="${i}" style="animation-delay:${i * 70}ms">
      <span class="nz-key">${i + 1}</span>
      <span class="tx">${NZ.esc(o.label)}${o.locked ? `<small>${NZ.esc(o.locked)}</small>` : o.hint ? `<small>${NZ.esc(o.hint)}</small>` : ''}</span>
      ${NZ.icon(o.locked ? 'lock' : o.leave ? 'logout' : 'chev-r')}
    </button>`).join('');
  NZ.$$('.opt').forEach(b => {
    b.onclick = () => choose(+b.dataset.i);
    b.onmouseenter = () => hover(+b.dataset.i);
  });
  hover(-1);
  type(n.text);
}

function hover(i) { on = i; NZ.$$('.opt').forEach(b => b.classList.toggle('on', +b.dataset.i === i)); }

function choose(i) {
  if (typing) return finish();
  const o = node.options?.[i];
  if (!o || o.locked) return;
  if (o.leave) { NZ.post('select', { id: o.id }); NZ.close(app); return; }
  NZ.post('select', { id: o.id });
  if (!NZ.inGame && PREVIEW[o.id]) show(PREVIEW[o.id]);
}

window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open')) return;
  const n = node?.options?.length || 0;
  if (e.key === ' ') { e.preventDefault(); if (typing) finish(); }
  else if (e.key === 'Escape') NZ.close(app);
  else if (/^[1-9]$/.test(e.key)) choose(+e.key - 1);
  else if (e.key === 'ArrowDown' && n) hover((on + 1) % n);
  else if (e.key === 'ArrowUp' && n) hover((on - 1 + n) % n);
  else if (e.key === 'Enter' && on >= 0) choose(on);
});
NZ.$('#line').onclick = () => typing && finish();

function open(d) {
  NZ.$('#place').textContent = (d.place || '').toUpperCase();
  app.classList.remove('in');
  NZ.open(app);
  requestAnimationFrame(() => requestAnimationFrame(() => app.classList.add('in')));
  setTimeout(() => show(d.node), 300); // let the letterbox slide in first
}
NZ.on('open', open);
NZ.on('node', show);
NZ.on('close', () => NZ.close(app, { notify: false }));

const VOSS = { speaker: 'Dr. Elena Voss', initials: 'EV', role: 'Pillbox Medical · Head of surgery', rep: 62 };
const PREVIEW = {
  start: { ...VOSS, text: "You're the new paramedic? Good. We had *three* gunshot victims before lunch and I'm running on cold coffee. Tell me you can hold pressure on a wound without fainting.",
    options: [
      { id: 'ready', label: "I'm ready. Put me on the next call.", hint: 'Start the EMS shift' },
      { id: 'pay', label: 'What does the job pay?' },
      { id: 'surgery', label: 'Can I assist in surgery?', locked: 'Requires: EMS grade 3' },
      { id: 'bye', label: 'Maybe another time.', leave: true },
    ] },
  pay: { ...VOSS, text: 'Base pay is *$450 a call*, plus a bonus for every patient who leaves this building breathing. Keep your response times under four minutes and the chief will notice.',
    options: [{ id: 'ready', label: "Sounds fair. Let's start." }, { id: 'bye', label: "I'll think about it.", leave: true }] },
  ready: { ...VOSS, rep: 70, text: "Then grab a kit from the locker and take *Ambulance 04*. Dispatch will ping your radio. And, rookie, don't drive like you stole it.",
    options: [{ id: 'bye', label: 'On my way.', leave: true }] },
};

NZ.preview(() => open({ place: 'Pillbox Medical', node: PREVIEW.start }));
