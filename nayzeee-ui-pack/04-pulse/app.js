/* 04 · PULSE — HUD (no close callback; show/hide from Lua)
   SendNUIMessage({ action = 'hud',      data = { show = true } })
   SendNUIMessage({ action = 'status',   data = { health, armor, hunger, thirst, stamina, stress } })   -- 0-100, nil hides a capsule
   SendNUIMessage({ action = 'voice',    data = { level = 1-3, talking = bool, radio = bool } })
   SendNUIMessage({ action = 'location', data = { street, zone, heading = 0-360, time, day } })
   SendNUIMessage({ action = 'player',   data = { id, cash, bank, job, grade, mapWidth = 300 } })
   SendNUIMessage({ action = 'vehicle',  data = { show = bool, speed, rpm = 0-1, gear, fuel = 0-100, belt, engine = 0-100, lights, unit = 'MPH' } })
*/
const app = NZ.$('#app');

/* ── dial geometry: 270° sweep, 40 ticks ── */
const CX = 125, CY = 112, R = 96, A0 = 135, SWEEP = 270, TICKS = 40;
const pt = (r, deg) => [CX + r * Math.cos(deg * Math.PI / 180), CY + r * Math.sin(deg * Math.PI / 180)];
(function buildDial() {
  let s = '';
  const [sx, sy] = pt(R + 8, A0), [ex, ey] = pt(R + 8, A0 + SWEEP);
  s += `<path class="track" d="M${sx} ${sy}A${R + 8} ${R + 8} 0 1 1 ${ex} ${ey}"/>`;
  for (let i = 0; i < TICKS; i++) {
    const a = A0 + (SWEEP / (TICKS - 1)) * i;
    const [x0, y0] = pt(R, a), [x1, y1] = pt(R + (i % 5 === 0 ? 16 : 11), a);
    s += `<line class="tick" data-i="${i}" x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}"/>`;
  }
  s += `<path class="needle-arc" id="sweep" d=""/>`;
  NZ.$('#dial').innerHTML = s;
  NZ.$('#fuel').innerHTML = '<i></i>'.repeat(10);
})();
const ticks = NZ.$$('.tick');

function setStatus(d) {
  NZ.$$('.cap').forEach(c => {
    const v = d[c.dataset.k];
    if (v === undefined) return;
    c.classList.toggle('hide', v === null);
    if (v === null) return;
    const n = Math.max(0, Math.min(100, Math.round(v)));
    c.style.setProperty('--v', n);
    c.querySelector('b').textContent = n;
    const lowBad = c.dataset.k === 'stress' ? n > 80 : n < 20;
    c.classList.toggle('low', lowBad);
  });
}

function setVoice(d) {
  const el = NZ.$('#voice');
  if (d.level) NZ.$$('#voice .lv i').forEach((i, k) => i.classList.toggle('on', k < d.level));
  if (d.talking !== undefined) el.classList.toggle('talk', !!d.talking);
  if (d.radio !== undefined) el.classList.toggle('radio', !!d.radio);
}

const DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
function setPlace(d) {
  if (d.heading !== undefined) {
    const h = ((Math.round(d.heading) % 360) + 360) % 360;
    NZ.$('#dir').textContent = DIRS[Math.round(h / 45) % 8];
    NZ.$('#deg').textContent = h + '°';
  }
  if (d.street) NZ.$('#street').textContent = d.street;
  if (d.zone) NZ.$('#zone').textContent = d.zone;
  if (d.time) NZ.$('#time').textContent = d.time;
  if (d.day) NZ.$('#day').textContent = d.day;
}

const last = {};
function flash(key, val) {
  const row = NZ.$(`#${key}-row`);
  if (last[key] !== undefined && last[key] !== val) {
    row.querySelector('.flash')?.remove();
    const diff = val - last[key];
    row.insertAdjacentHTML('afterbegin', `<span class="flash ${diff < 0 ? 'neg' : ''}">${diff < 0 ? '−' : '+'}${NZ.money(Math.abs(diff))}</span>`);
    setTimeout(() => row.querySelector('.flash')?.remove(), 2200);
  }
  last[key] = val;
  NZ.$(`#${key}`).textContent = NZ.money(val);
}
function setPlayer(d) {
  if (d.id !== undefined) NZ.$('#pid').textContent = 'ID ' + d.id;
  if (d.cash !== undefined) flash('cash', d.cash);
  if (d.bank !== undefined) flash('bank', d.bank);
  if (d.job) NZ.$('#job').innerHTML = `<b>${NZ.esc(d.job)}</b>${d.grade ? ' · ' + NZ.esc(d.grade) : ''}`;
  if (d.mapWidth) app.style.setProperty('--map-w', d.mapWidth + 'px');
}

function setVehicle(d) {
  const sp = NZ.$('#speedo');
  if (d.show !== undefined) sp.classList.toggle('off', !d.show);
  if (d.speed !== undefined) {
    const s = String(Math.max(0, Math.round(d.speed))).padStart(3, '0');
    const lead = s.match(/^0*/)[0].slice(0, 2);
    NZ.$('#spd').innerHTML = `<i>${lead}</i>${s.slice(lead.length)}`;
  }
  if (d.rpm !== undefined) {
    const lit = Math.round(Math.max(0, Math.min(1, d.rpm)) * TICKS);
    ticks.forEach((t, i) => { t.classList.toggle('on', i < lit && i < TICKS * .82); t.classList.toggle('hot', i < lit && i >= TICKS * .82); });
    const end = A0 + SWEEP * Math.max(.002, Math.min(1, d.rpm));
    const [sx, sy] = pt(R - 7, A0), [ex, ey] = pt(R - 7, end);
    NZ.$('#sweep').setAttribute('d', `M${sx} ${sy}A${R - 7} ${R - 7} 0 ${end - A0 > 180 ? 1 : 0} 1 ${ex} ${ey}`);
  }
  if (d.gear !== undefined) NZ.$('#gear').textContent = d.gear === 0 ? 'R' : d.gear;
  if (d.unit) NZ.$('#unit').textContent = d.unit;
  if (d.fuel !== undefined) {
    const on = Math.ceil(d.fuel / 10);
    NZ.$$('#fuel i').forEach((i, k) => i.classList.toggle('on', k < on));
    NZ.$('#fuel').classList.toggle('low', d.fuel < 20);
  }
  if (d.belt !== undefined) { NZ.$('#belt').classList.toggle('on', !!d.belt); NZ.$('#belt').classList.toggle('warn', !d.belt); }
  if (d.engine !== undefined) { NZ.$('#engine').classList.toggle('warn', d.engine < 30); NZ.$('#engine').classList.toggle('on', d.engine >= 30); }
  if (d.lights !== undefined) NZ.$('#lights').classList.toggle('on', !!d.lights);
}

NZ.on('hud', d => d.show === false ? NZ.close(app, { notify: false }) : NZ.open(app));
NZ.on('status', setStatus);
NZ.on('voice', setVoice);
NZ.on('location', setPlace);
NZ.on('player', setPlayer);
NZ.on('vehicle', setVehicle);

NZ.preview(() => {
  NZ.open(app);
  setPlayer({ id: 12, cash: 4820, bank: 128450, job: 'EMS', grade: 'Paramedic' });
  setStatus({ health: 86, armor: 42, hunger: 64, thirst: 15, stamina: 92, stress: 28 });
  setVoice({ level: 2 });
  setPlace({ heading: 312, street: 'Vespucci Blvd', zone: 'Del Perro · Los Santos', time: '16:10', day: 'Sunday' });
  setVehicle({ show: true, speed: 0, rpm: .1, gear: 1, fuel: 62, belt: true, engine: 88, lights: true });

  let t = 0;
  setInterval(() => {
    t += 0.05;
    const speed = 52 + Math.sin(t * .7) * 38;
    const gear = Math.min(6, Math.max(1, Math.ceil(speed / 22)));
    setVehicle({ speed, rpm: .25 + ((speed % 22) / 22) * .7, gear });
    setVoice({ talking: Math.sin(t * 1.3) > .5 });
    setPlace({ heading: 312 + Math.sin(t * .2) * 20 });
  }, 60);
  setTimeout(() => setPlayer({ cash: 4320 }), 1500);
});
