/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · tug of war
   The game reads the key and tells the server; this only draws it.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const TG = { d: null, timer: null, ends: 0 };
const tugEl = $('#tug');

function tugRope(rope) {
  const d = TG.d;
  if (!d) return;
  // rope > 0 = toward the snatcher. Draw it from MY side: my half grows when I'm winning.
  const mine = d.role === 'snatcher' ? rope : -rope;
  const pct = 50 + (mine / (d.winAt || 100)) * 50;
  $('.rope-half.mine', tugEl).style.width = `${Math.max(0, Math.min(100, pct))}%`;
  $('.rope-half.theirs', tugEl).style.width = `${Math.max(0, Math.min(100, 100 - pct))}%`;
  $('.rope-knot', tugEl).style.left = `${Math.max(0, Math.min(100, pct))}%`;
}

H['tug:start'] = (d) => {
  TG.d = d;
  $('.cl-side.me .cl-role', tugEl).textContent = d.role === 'snatcher' ? d.text.you : d.text.them;
  $('.cl-side.me .cl-name', tugEl).textContent = 'You';
  $('.cl-side.them .cl-role', tugEl).textContent = d.role === 'snatcher' ? d.text.them : d.text.you;
  $('.cl-side.them .cl-name', tugEl).textContent = d.opp || '';
  $('.tug-chain', tugEl).innerHTML = `<span class="th">${chainImg(d.image, 'gem')}</span><span class="tug-lbl">${esc(d.label)}</span>`;
  $('.tug-key', tugEl).textContent = d.key || 'SPACE';
  $('.cl-mods', tugEl).innerHTML = d.blind && d.role === 'snatcher' ? `<span class="chip t-success">${icon('bolt')}Blindside</span>`
    : d.blind ? `<span class="chip t-error">${icon('alert')}Grabbed from behind</span>` : '';
  $('.cl-result', tugEl).hidden = true;
  fillIcons(tugEl);
  tugRope(d.rope || 0);
  TG.ends = performance.now() + (d.duration || 5000);
  clearInterval(TG.timer);
  TG.timer = setInterval(() => {
    const left = Math.max(0, TG.ends - performance.now()) / 1000;
    $('.cl-time', tugEl).textContent = left.toFixed(1);
    $('.cl-clock', tugEl).classList.toggle('hot', left < 1.5);
  }, 50);
  tugEl.hidden = false;
};

H['tug:press'] = () => {
  const k = $('.mash-key', tugEl);
  k.classList.add('down');
  setTimeout(() => k.classList.remove('down'), 70);
};

H['tug:tick'] = (d) => {
  tugRope(d.rope || 0);
  tugEl.classList.remove('shake'); void tugEl.offsetWidth; tugEl.classList.add('shake');
};

H['tug:end'] = (r) => {
  clearInterval(TG.timer);
  if (!TG.d) return;
  const res = $('.cl-result', tugEl);
  if (r.cancelled) { tugEl.hidden = true; TG.d = null; return; }
  res.className = `cl-result ${r.win ? 'win' : 'lose'}`;
  $('b', res).textContent = r.win ? (r.role === 'snatcher' ? 'Snatched' : 'Held on') : (r.role === 'snatcher' ? 'Slipped' : 'Snatched');
  $('span', res).textContent = r.win ? (r.role === 'snatcher' ? 'It\'s yours now.' : 'They didn\'t get it.') : (r.role === 'snatcher' ? 'They held on.' : 'They took your chain.');
  res.hidden = false;
  setTimeout(() => { tugEl.hidden = true; TG.d = null; }, 1600);
};
