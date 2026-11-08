/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · someone offers you a chain
   ═══════════════════════════════════════════════════════════ */
'use strict';

const ofEl = $('#offer');

H['offer:show'] = (o) => {
  const title = o.kind === 'swap' ? 'Swap chains' : o.kind === 'puton' ? 'Put it on you' : 'A gift';
  ofEl.innerHTML = `<div class="ch-frame"><div class="ch-in">
    <div class="of-b"><span class="th">${chainImg(o.image, 'gem')}</span>
      <div class="of-tx"><small>${esc(title)}</small><p>${esc(o.text)}${o.theirs ? `<br><span style="color:var(--ink-3)">for your ${esc(o.theirs)}</span>` : ''}</p></div></div>
    <div class="of-f"><i class="prog"></i><span class="hint-tx">${keyText(o.hint || '<kc>Y</kc> Accept  <kc>X</kc> Decline')}</span></div>
  </div></div>`;
  ofEl.hidden = false;
  $('.prog', ofEl).animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration: (o.timeout || 15) * 1000, easing: 'linear', fill: 'forwards' });
};
H['offer:hide'] = () => { ofEl.hidden = true; ofEl.innerHTML = ''; };
