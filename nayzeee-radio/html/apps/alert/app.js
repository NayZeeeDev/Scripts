/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · alert — emergency on your channel (never takes focus)  apps/alert/app.js
   client/modules/alerts.lua forwards nzr:alerts:emergency here (the tone itself is the
   '_core sfx emergency' it sends next to it).

   Lua → NUI
     emergency { name, callsign, freq | fkey, label?, time?, street?, distance? (m) }
   NUI → Lua   nothing

   Each alert: a red-accented card slides in from the right edge (siren, EMERGENCY, name +
   callsign chip, then instrument rows: channel, label, time received, optional place), the
   screen edges pulse red three times, the card drains away after 8 s. Up to 3 stack, newest
   on top. The section shows itself while a card is up; no 'open' is needed.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t } = NZR;
  const MAX = 3;
  const LIFE_MS = 8000;
  const num = (v, d = NaN) => { const n = Number(v); return Number.isFinite(n) ? n : d; };

  let app = null, root = null, stack = null, edge = null, hideTimer = 0;

  const pad = n => String(n).padStart(2, '0');
  const clock = () => { const d = new Date(); return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; };

  function dismiss(card) {
    if (!card || card.classList.contains('out')) return;
    clearTimeout(card._t);
    card.classList.add('out');
    setTimeout(() => {
      card.remove();
      if (!stack.querySelector('.al')) {
        clearTimeout(hideTimer);
        hideTimer = setTimeout(() => { if (!stack.querySelector('.al') && !NZR.isOpen('alert')) root.classList.remove('nzr-on'); }, 400);
      }
    }, 330);
  }

  function emergency(d = {}) {
    d = d || {};
    clearTimeout(hideTimer);
    root.classList.add('nzr-on');
    const name = String(d.name || t('ui.al_unknown', 'Unknown caller'));
    const cs = d.callsign ? String(d.callsign) : '';
    const f = NZR.fmt.freq(d.freq ?? d.fkey);
    const rows = [
      [t('ui.al_channel', 'Channel'), f ? `${esc(f)}<small>${esc(t('ui.mhz', 'MHz'))}</small>` : '—'],
    ];
    if (d.label) rows.push([t('ui.al_label', 'Label'), esc(d.label), 'lab']);
    const dist = num(d.distance);
    if (d.street || Number.isFinite(dist)) {
      const where = [d.street ? esc(d.street) : '', Number.isFinite(dist) ? `${dist >= 1000 ? (dist / 1000).toFixed(1) : Math.round(dist)}<small>${dist >= 1000 ? 'km' : esc(t('ui.metres', 'm'))}</small>` : ''].filter(Boolean).join(' · ');
      rows.push([t('ui.al_where', 'Position'), where, d.street ? 'lab' : '']);
    }
    rows.push([t('ui.al_time', 'Received'), esc(d.time ? String(d.time) : clock())]);
    const card = NZR.el('div', 'al');
    card.style.setProperty('--d', `${LIFE_MS}ms`);
    card.innerHTML = `<div class="al-card">
        <div class="al-top"><span class="al-ic">${NZR.icon('siren')}</span>
          <div class="al-tt"><span class="al-k"><i></i>${esc(t('ui.al_title', 'EMERGENCY'))}</span><b>${esc(name)}</b></div>
          <span class="al-cs">${esc(cs)}</span></div>
        <div class="al-rows">${rows.map(([k, v, c]) => `<div class="al-row"><span>${esc(k)}</span><b class="${c || ''}">${v}</b></div>`).join('')}</div>
        <i class="al-bar"></i></div>`;
    stack.prepend(card);
    [...stack.querySelectorAll('.al:not(.out)')].slice(MAX).forEach(dismiss);
    card._t = setTimeout(() => dismiss(card), LIFE_MS);
    edge.classList.remove('go');
    void edge.offsetWidth;
    edge.classList.add('go');
  }

  app = NZR.app('alert', {
    escClose: false,
    init(el) {
      root = el;
      el.innerHTML = '<div class="al-edge"></div><div class="al-stack"></div>';
      stack = el.querySelector('.al-stack');
      edge = el.querySelector('.al-edge');
      edge.addEventListener('animationend', () => edge.classList.remove('go'));
    },
    open(d) { if (d && (d.name || d.callsign)) emergency(d); },
    close() { [...stack.querySelectorAll('.al')].forEach(c => { clearTimeout(c._t); c.remove(); }); edge.classList.remove('go'); },
    msg: { emergency },
    preview() {
      const calls = [
        { name: 'Maya Reyes', callsign: '2A14', freq: '155.50', label: 'Patrol North', street: 'Strawberry Ave', distance: 640 },
        { name: 'Dario Kostas', callsign: '1L20', freq: 155.5, label: 'Patrol North' },
        { name: 'June Whitfield', callsign: 'K9', fkey: '460.25', distance: 1850 },
      ];
      let i = 0;
      const next = () => { app.msg.emergency(calls[i % calls.length]); if (NZR.sfx.state().ctx === 'running') NZR.sfx.play('emergency'); i++; };
      setTimeout(next, 200);
      setTimeout(next, 1400);
      setInterval(next, 7000);
    },
  });
})();
