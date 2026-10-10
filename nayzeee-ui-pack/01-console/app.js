/* 01 · CONSOLE
   SendNUIMessage({ action = 'open', data = { title, subtitle, user = {name, role}, roster = {...}, incidents = {...} } })
   SendNUIMessage({ action = 'close' })
   Callbacks: close, navigate {page}, refresh, filter
*/
const app = NZ.$('#app');
const STATUS = { available: ['live', 'Available'], scene: ['hot', 'On scene'], standby: ['off', 'Standby'] };

function render(d) {
  if (d.title) NZ.$('#title').textContent = d.title;
  if (d.subtitle) NZ.$('#subtitle').textContent = d.subtitle;
  if (d.user) {
    NZ.$('#who-name').textContent = d.user.name;
    NZ.$('#who-role').textContent = d.user.role;
    NZ.$('#who-av').textContent = NZ.initials(d.user.name);
  }
  if (d.roster) {
    NZ.$('#onduty').textContent = d.roster.length;
    NZ.$('#roster').innerHTML = d.roster.map(r => {
      const [cls, label] = STATUS[r.status] || STATUS.standby;
      return `<div class="row"><div class="nz-av">${NZ.initials(r.name)}</div>
        <div class="row-txt"><b>${NZ.esc(r.name)}</b><span>${NZ.esc(r.role)}</span></div>
        <span class="nz-tag ${cls}">${label}</span></div>`;
    }).join('');
  }
  if (d.incidents) {
    NZ.$('#incidents').innerHTML = d.incidents.map(i => `
      <article class="inc ${i.urgent ? 'urgent' : ''}">
        <div class="inc-top"><span class="nz-chip ${i.urgent ? 'red' : ''}">${NZ.esc(i.type)}</span><span class="ref">${NZ.esc(i.ref)}</span></div>
        <h3>${NZ.esc(i.title)}</h3><p>${NZ.esc(i.text)}</p>
        <div class="meta"><span>Patient <b>${NZ.esc(i.patient)}</b></span><span>Filed by <b>${NZ.esc(i.by)}</b></span><span>${NZ.esc(i.time)}</span></div>
      </article>`).join('');
  }
}

function tick() {
  const now = new Date();
  NZ.$('#clock').textContent = now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  NZ.$('#date').textContent = now.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
}
tick(); setInterval(tick, 10000);

let shiftStart = Date.now() - 15158000;
setInterval(() => {
  const s = Math.floor((Date.now() - shiftStart) / 1000);
  NZ.$('#shift').textContent = [s / 3600, (s % 3600) / 60, s % 60].map(n => String(Math.floor(n)).padStart(2, '0')).join(':');
}, 1000);

NZ.$$('.nav').forEach(n => n.addEventListener('click', () => {
  NZ.$$('.nav').forEach(x => x.classList.remove('on'));
  n.classList.add('on');
  NZ.post('navigate', { page: n.dataset.page });
}));
NZ.$$('[data-post]').forEach(b => b.addEventListener('click', () => NZ.post(b.dataset.post)));
NZ.$$('[data-close]').forEach(b => b.addEventListener('click', () => NZ.close(app)));
NZ.escape(() => NZ.close(app));

NZ.on('open', d => { render(d || {}); if (d && d.shiftStart) shiftStart = d.shiftStart; NZ.open(app); });
NZ.on('close', () => NZ.close(app, { notify: false }));

NZ.preview(() => {
  render({
    roster: [
      { name: 'John Doe', role: 'Chief · Unit 01', status: 'available' },
      { name: 'Maya Reyes', role: 'Paramedic · Unit 04', status: 'scene' },
      { name: 'Theo Kane', role: 'EMT · Unit 09', status: 'available' },
      { name: 'Sam Brooks', role: 'Trainee · Unassigned', status: 'standby' },
    ],
    incidents: [
      { urgent: true, type: 'Trauma', ref: 'MED-215', title: 'Gunshot wound, Vespucci Beach', text: 'Single patient with a wound to the left shoulder. Bleeding controlled on scene and patient transported to Pillbox in critical but stable condition.', patient: 'R. Salas', by: 'Theo Kane', time: '02:41' },
      { type: 'Collision', ref: 'MED-214', title: 'Traffic collision on Route 68', text: 'Three vehicles involved near the eastbound off-ramp. Scene secured with PD support; two patients assessed on arrival, one transported with stable vitals.', patient: 'J. Pork', by: 'John Doe', time: '02:07' },
      { type: 'Assessment', ref: 'MED-213', title: 'On-scene medical evaluation', text: "Full evaluation completed at the caller's residence. No life-threatening conditions identified, patient cleared on scene.", patient: 'J. Pork', by: 'Maya Reyes', time: '02:05' },
    ],
  });
  NZ.open(app);
});
