/* 18 · TUMBLER
   Skill-check minigames. Give the player focus while it runs:
     circle   → SetNuiFocus(true, false)   (E / Space, no cursor needed)
     sequence → SetNuiFocus(true, true)    (click cells, or type the codes)

   SendNUIMessage({ action = 'start', data = {
     type = 'circle',            -- 'circle' | 'sequence'
     title = 'Lockpicking',      -- header text
     subtitle = 'Pillbox Hill',  -- optional, shown after the round info
     rounds = 3,                 -- rounds to clear (default 3)
     difficulty = 'medium',      -- 'easy' | 'medium' | 'hard'
     -- circle only
     misses = 0,                 -- slips allowed before failing (default 0)
     -- sequence only
     time = 10,                  -- seconds per round (default by difficulty: 14 / 11 / 9)
     length = 5,                 -- codes per sequence (default 4 / 5 / 6)
     grid = 5,                   -- grid size, 4 to 6 (default 5)
     charset = 'hex',            -- 'hex' (A9, 3F…) | 'digits' (07, 42…)
   } })
   SendNUIMessage({ action = 'close' })   -- abort silently (no result posted)

   Callbacks: result { success, type, rounds, hits, cancelled }
                -- posted ~1.2s after the end (immediately when ESC cancels), then close
              close
*/
NZ.addIcons({
  target: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>',
  chip: '<rect x="6" y="6" width="12" height="12" rx="1.5"/><rect x="9.5" y="9.5" width="5" height="5" rx=".5"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
});

const app = NZ.$('#app');
const card = NZ.$('#card');
const stage = NZ.$('#stage');

const CIRCLE = { easy: { zone: 58, speed: 150 }, medium: { zone: 42, speed: 205 }, hard: { zone: 30, speed: 265 } };
const SEQ = { easy: { len: 4, time: 14, pen: 1.5 }, medium: { len: 5, time: 11, pen: 2 }, hard: { len: 6, time: 9, pen: 3 } };
const DIFF_LABEL = { easy: 'Easy', medium: 'Medium', hard: 'Hard' };

let g = null;        // current game
let raf = 0, last = 0, endTimer = 0;

const rand = n => Math.floor(Math.random() * n);
const wait = (fn, ms) => setTimeout(() => { if (g && !g.over) fn(); }, ms);
function flashClass(el, cls, ms = 420) { el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); setTimeout(() => el.classList.remove(cls), ms); }

/* ── shared chrome ── */
function head() {
  NZ.$('#title').textContent = g.title;
  let sub = `Round <em>${Math.min(g.round + 1, g.rounds)}</em> of ${g.rounds}`;
  if (g.type === 'circle' && g.misses > 0) sub += ` · ${g.misses - g.slips} slip${g.misses - g.slips === 1 ? '' : 's'} left`;
  if (g.subtitle) sub += ` · ${NZ.esc(g.subtitle)}`;
  NZ.$('#sub').innerHTML = sub;
  const d = NZ.$('#diff');
  d.textContent = DIFF_LABEL[g.difficulty];
  d.className = 'tb-diff ' + g.difficulty;
  NZ.$('#pips').innerHTML = Array.from({ length: g.rounds }, (_, i) =>
    `<i class="${i < g.hits ? 'ok' : i === g.round && g.failed ? 'no' : i === g.round && !g.over ? 'cur' : ''}"></i>`).join('');
}

function hints() {
  const sig = '<span class="nz-sig"><span class="nz-mark xs"></span>NAYZEEE</span>';
  NZ.$('#hints').innerHTML = g.type === 'circle'
    ? `<span><span class="nz-key">E</span><span class="nz-key">Space</span>Lock in</span><span><span class="nz-key">ESC</span>Give up</span>${sig}`
    : `<span><span class="nz-key">${g.charset === 'hex' ? '0-F' : '0-9'}</span>Type <b id="typed">${NZ.esc(g.typed || '')}</b></span><span><span class="nz-key">Click</span>Pick</span><span><span class="nz-key">ESC</span>Give up</span>${sig}`;
}

/* ── circle ── */
const R = 118, C = 2 * Math.PI * R;

function circleBuild() {
  let ticks = '';
  for (let i = 0; i < 72; i++) {
    const a = i * 5 * Math.PI / 180, mj = i % 6 === 0;
    const r1 = 136, r2 = mj ? 146 : 141;
    ticks += `<line class="tick ${mj ? 'mj' : ''}" x1="${150 + r1 * Math.sin(a)}" y1="${150 - r1 * Math.cos(a)}" x2="${150 + r2 * Math.sin(a)}" y2="${150 - r2 * Math.cos(a)}"/>`;
  }
  stage.innerHTML = `<div class="dial" id="dial">
    <svg viewBox="0 0 300 300">
      ${ticks}
      <circle class="track" cx="150" cy="150" r="${R}"/>
      <circle class="zone" id="zone" cx="150" cy="150" r="${R}"/>
      <circle class="flash" cx="150" cy="150" r="${R}"/>
      <circle class="hubring" cx="150" cy="150" r="50"/>
      <g class="needle" id="needle"><line x1="150" y1="104" x2="150" y2="40"/><path d="M150 24 157 38H143z"/></g>
    </svg>
    <div class="hub"><span class="nz-key">E</span><small>Press</small></div>
  </div>`;
  NZ.$('#dial').onclick = circlePress;
}

function circleRound() {
  const base = CIRCLE[g.difficulty];
  g.zone = Math.max(14, base.zone * Math.pow(0.9, g.round));
  g.speed = base.speed * Math.pow(1.17, g.round);
  g.start = rand(360);
  g.dir = g.round % 2 ? -1 : 1;
  g.angle = (g.start + g.zone / 2 + 180) % 360;   // opposite side of the zone
  const z = NZ.$('#zone');
  z.setAttribute('stroke-dasharray', `${C * g.zone / 360} ${C}`);
  z.setAttribute('transform', `rotate(${g.start - 90} 150 150)`);
  g.lock = false;
  head();
}

function circleFrame(dt) {
  g.angle = (g.angle + g.dir * g.speed * dt + 360) % 360;
  NZ.$('#needle').setAttribute('transform', `rotate(${g.angle} 150 150)`);
}

function circlePress() {
  if (!g || g.over || g.lock || g.type !== 'circle') return;
  const d = ((g.angle - g.start) % 360 + 360) % 360;
  const tol = 3;
  const dial = NZ.$('#dial');
  g.lock = true;
  if (d <= g.zone + tol || d >= 360 - tol) {
    g.hits++; g.round++;
    flashClass(dial, 'hit', 450);
    head();
    if (g.round >= g.rounds) return wait(() => finish(true), 380);
    wait(circleRound, 420);
  } else {
    g.slips++;
    flashClass(dial, 'miss', 420);
    if (g.slips > g.misses) { g.failed = true; head(); return wait(() => finish(false), 420); }
    head();
    wait(circleRound, 460);
  }
}

/* ── sequence ── */
function codes(n, charset) {
  const pool = new Set();
  while (pool.size < n) {
    pool.add(charset === 'digits' ? String(rand(100)).padStart(2, '0') : rand(256).toString(16).toUpperCase().padStart(2, '0'));
  }
  return [...pool];
}

function seqRound() {
  const base = SEQ[g.difficulty];
  g.cells = codes(g.size * g.size, g.charset);
  const pick = [...g.cells].sort(() => Math.random() - 0.5);
  g.seq = pick.slice(0, Math.min(g.length, g.cells.length));
  g.pos = 0;
  g.left = g.total = +g.time || base.time;
  g.pen = base.pen;
  g.typed = '';
  g.lock = false;
  stage.innerHTML = `<div class="seqw" id="seqw">
    <div class="sq-target" id="target"></div>
    <div class="sq-time" style="position:relative"><div class="sq-bar" id="bar"><i></i></div><b id="secs"></b></div>
    <div class="sq-grid" style="--n:${g.size}">${g.cells.map(c => `<button class="sq-cell" data-c="${NZ.esc(c)}">${NZ.esc(c)}</button>`).join('')}</div>
  </div>`;
  NZ.$$('.sq-cell', stage).forEach(b => b.onclick = () => { b.blur(); seqPick(b.dataset.c); });
  seqTarget(); hints(); head(); seqTime();
}

function seqTarget() {
  NZ.$('#target').innerHTML = g.seq.map((c, i) =>
    `<span class="sq-slot ${i < g.pos ? 'done' : i === g.pos ? 'cur' : ''}">${NZ.esc(c)}</span>`).join('');
}

function seqTime() {
  const f = Math.max(0, g.left / g.total);
  const bar = NZ.$('#bar');
  if (!bar) return;
  bar.firstElementChild.style.transform = `scaleX(${f})`;
  bar.className = 'sq-bar' + (f < 0.2 ? ' crit' : f < 0.4 ? ' low' : '');
  NZ.$('#secs').textContent = Math.max(0, g.left).toFixed(1) + 's';
}

function seqFrame(dt) {
  if (g.lock) return;
  g.left -= dt;
  seqTime();
  if (g.left <= 0) { g.failed = true; g.lock = true; head(); flashClass(NZ.$('#seqw'), 'shake', 400); wait(() => finish(false), 420); }
}

function seqPick(c) {
  if (!g || g.over || g.lock || g.type !== 'sequence') return;
  const cell = NZ.$(`.sq-cell[data-c="${CSS.escape(c)}"]`, stage);
  g.typed = ''; setTyped();
  if (c === g.seq[g.pos]) {
    cell && cell.classList.add('got');
    g.pos++;
    seqTarget();
    if (g.pos >= g.seq.length) {
      g.lock = true; g.hits++; g.round++;
      NZ.$('#seqw').classList.add('clear');
      head();
      if (g.round >= g.rounds) return wait(() => finish(true), 420);
      wait(seqRound, 520);
    }
  } else {
    if (cell) flashClass(cell, 'bad', 450);
    flashClass(NZ.$('#seqw'), 'shake', 400);
    g.left -= g.pen;
    const t = NZ.$('.sq-time');
    t.insertAdjacentHTML('beforeend', `<span class="pen">-${g.pen.toFixed(1)}s</span>`);
    setTimeout(() => t.querySelector('.pen')?.remove(), 700);
    seqTime();
  }
}

function setTyped() {
  const el = NZ.$('#typed'); if (el) el.textContent = g.typed;
  NZ.$$('.sq-cell', stage).forEach(b => b.classList.toggle('typed', !!g.typed && b.dataset.c.startsWith(g.typed) && !b.classList.contains('got')));
}

function seqKey(k) {
  const ok = g.charset === 'digits' ? /^[0-9]$/ : /^[0-9a-f]$/i;
  if (k === 'Backspace') { g.typed = g.typed.slice(0, -1); setTyped(); return true; }
  if (!ok.test(k)) return false;
  g.typed += k.toUpperCase();
  if (g.typed.length >= 2) seqPick(g.typed); else setTyped();
  return true;
}

/* ── loop + lifecycle ── */
function loop(t) {
  const dt = Math.min(0.05, (t - last) / 1000); last = t;
  if (g && !g.over) {
    if (g.type === 'circle' && !g.lock) circleFrame(dt);
    if (g.type === 'sequence') seqFrame(dt);
  }
  raf = requestAnimationFrame(loop);
}

function finish(success, cancelled) {
  if (!g || g.over) return;
  g.over = true;
  const res = { success: !!success, type: g.type, rounds: g.rounds, hits: g.hits };
  if (cancelled) res.cancelled = true;
  head();
  cancelAnimationFrame(raf);
  if (cancelled) { NZ.post('result', res); NZ.close(app); return; }
  const r = NZ.$('#result');
  r.className = 'tb-result on' + (success ? '' : ' fail');
  r.innerHTML = `<div class="ic">${NZ.icon(success ? 'check' : 'x')}</div>
    <h2>${success ? 'Success' : 'Failed'}</h2>
    <p>${g.hits} of ${g.rounds} round${g.rounds === 1 ? '' : 's'} cleared</p><i class="run"></i>`;
  endTimer = setTimeout(() => { NZ.post('result', res); NZ.close(app); }, 1200);
}

function startGame(d) {
  d = d || {};
  clearTimeout(endTimer); cancelAnimationFrame(raf);
  const type = d.type === 'sequence' ? 'sequence' : 'circle';
  const difficulty = SEQ[d.difficulty] ? d.difficulty : 'medium';
  g = {
    type, difficulty,
    title: d.title || (type === 'circle' ? 'Lockpicking' : 'Bypass security'),
    subtitle: d.subtitle || '',
    rounds: Math.max(1, +d.rounds || 3),
    misses: Math.max(0, +d.misses || 0),
    time: d.time, length: Math.max(2, +d.length || SEQ[difficulty].len),
    size: Math.min(6, Math.max(4, +d.grid || 5)),
    charset: d.charset === 'digits' ? 'digits' : 'hex',
    round: 0, hits: 0, slips: 0, failed: false, over: false, lock: false, typed: '',
  };
  NZ.$('#result').className = 'tb-result';
  card.classList.toggle('seq', type === 'sequence');
  hints();
  if (type === 'circle') { circleBuild(); circleRound(); } else seqRound();
  NZ.open(app);
  last = performance.now();
  raf = requestAnimationFrame(loop);
}

function stopGame() {
  clearTimeout(endTimer); cancelAnimationFrame(raf);
  if (g) g.over = true;
  NZ.close(app, { notify: false });
}

window.addEventListener('keydown', e => {
  if (!app.classList.contains('nz-open') || !g || g.over) return;
  if (e.key === 'Escape') { e.preventDefault(); finish(false, true); return; }
  if (e.repeat) return;
  if (g.type === 'circle' && (e.key === 'e' || e.key === 'E' || e.key === ' ')) { e.preventDefault(); circlePress(); }
  else if (g.type === 'sequence' && !g.lock && seqKey(e.key)) e.preventDefault();
});

NZ.on('start', startGame);
NZ.on('close', stopGame);

/* ── browser preview ── */
let demoDiff = 'medium';
NZ.$$('#demo-diff button').forEach(b => b.onclick = () => {
  demoDiff = b.dataset.d;
  NZ.$$('#demo-diff button').forEach(x => x.classList.toggle('on', x === b));
});
const demo = {
  circle: () => startGame({ type: 'circle', title: 'Lockpicking', subtitle: 'Vinewood Hills', rounds: 3, difficulty: demoDiff, misses: 1 }),
  sequence: () => startGame({ type: 'sequence', title: 'Bypass security', subtitle: 'Fleeca · Great Ocean Hwy', rounds: 2, difficulty: demoDiff, charset: 'hex' }),
};
NZ.$$('#demo [data-type]').forEach(b => b.onclick = () => { b.blur(); demo[b.dataset.type](); });
NZ.preview(() => demo.circle());
