/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · care — steps card (HUD, no focus)
   Right edge, middle. Shown while a medic stands near a patient they checked: what the
   patient still needs, in order, the next step marked; steps that just got done stay
   ticked for a moment. Lua: client/core/care.lua (server plan: server/core/care.lua).

   Lua → JS actions
     open   { name, state, tri, steps: [{ code, title, why, where, urgent, icon }], done: [...], locale }
     update (same shape)
   JS → Lua: none
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  let root = null;
  let L = {};
  const T = (k, fb) => (L[k] != null ? L[k] : fb);

  function row(s, i, kind) {
    const cls = ['cs-step', kind];
    if (s.urgent && kind !== 'done') cls.push('urgent');
    if (s.where === 'hospital') cls.push('hosp');
    const node = kind === 'done' ? icon('check') : (kind === 'next' ? icon(s.icon || 'medkit') : String(i + 1));
    const tag = kind === 'next' ? `<span class="tag nx">${esc(T('next', 'Next'))}</span>`
      : (s.where === 'hospital' ? `<span class="tag hp">${icon('hospital')}${esc(T('hospital', 'Hospital'))}</span>` : '');
    return `<li class="${cls.join(' ')}">
      <span class="nd">${node}</span>
      <span class="tx"><b>${esc(s.title || '')}</b>${kind === 'done' ? '' : `<small>${esc(s.why || '')}</small>`}</span>
      ${kind === 'done' ? `<span class="tag dn">${esc(T('done', 'Done'))}</span>` : tag}
    </li>`;
  }

  function render(d) {
    if (!root || !d) return;
    L = d.locale || L;
    const steps = Array.isArray(d.steps) ? d.steps : [];
    const done = Array.isArray(d.done) ? d.done : [];
    const tri = Math.min(3, Math.max(1, Number(d.tri) || 3));
    const firstField = steps.findIndex(s => s.where !== 'hospital');
    const nextIdx = firstField === -1 ? 0 : firstField;
    const list = [
      ...done.map(s => row(s, 0, 'done')),
      ...steps.map((s, i) => row(s, i, i === nextIdx ? 'next' : 'todo')),
    ].join('');
    root.innerHTML = `
      <div class="cs-head">
        <span class="cs-ic">${icon('clipboard')}</span>
        <span class="cs-t"><span class="lb">${esc(T('title', 'Care steps'))}</span><b>${esc(d.name || '')}</b></span>
        <span class="cs-tri p${tri}">P${tri}</span>
      </div>
      ${steps.length || done.length ? `<ol class="cs-list">${list}</ol>` : ''}
      ${steps.length ? '' : `<div class="cs-empty">${icon('check')}<span>${esc(T('all_done', 'Nothing left to do.'))}</span></div>`}
      <div class="cs-hint">${icon('eye')}<span>${esc(T('hint', 'Third eye on the patient → the next step'))}</span></div>`;
  }

  NZA.app('care', {
    noscale: false,
    hideUnderFull: true,   // out of sight the moment a full-screen procedure opens (Lua also closes it)
    init(el) {
      el.innerHTML = '<aside class="cs nza-hud solid rail"></aside>';
      root = el.querySelector('.cs');
    },
    open(d) { render(d); root.classList.remove('in'); void root.offsetWidth; root.classList.add('in'); },
    close() {},
    msg: { update(d) { render(d); } },
    preview() {
      NZA.open('care', {
        name: 'T. Reyna', state: 'wounded', tri: 1,
        locale: { title: 'Care steps', next: 'Next', hospital: 'Hospital', done: 'Done', hint: 'Third eye on the patient → the next step', all_done: 'Nothing left to do. Help them up or let them go.' },
        done: [{ code: 'bleed', title: 'Stop the bleeding', where: 'field' }],
        steps: [
          { code: 'fluids', title: 'Give fluids', why: 'Lost a lot of blood. IV or IO line, then fluids or blood.', where: 'field', urgent: true, icon: 'iv' },
          { code: 'splint', title: 'Splint the fracture', why: 'Right lower leg is broken.', where: 'field', icon: 'bone' },
          { code: 'pain', title: 'Give pain relief', why: 'A lot of pain.', where: 'field', icon: 'pill' },
          { code: 'hospital', title: 'Take them to hospital', why: 'Stretcher, ambulance, hospital. 2 step(s) there.', where: 'hospital', icon: 'ambulance' },
          { code: 'bullet', title: 'Remove the bullet', why: 'Something is still inside the chest. Operating table.', where: 'hospital', icon: 'scalpel' },
        ],
      });
    },
  });
})();
