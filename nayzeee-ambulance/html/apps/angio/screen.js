/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · angio — DUI screen runtime
   The in-world fluoroscopy monitor. Renders with window.NZAAngio.FluoroView (app.js).

   Messages (SendDuiMessage, JSON):
     { type: 'state', state }    full screen state from the procedure overlay (~20 Hz)
     { type: 'standby' }         standby screen (model code + radiation sign, no brand)
     { type: 'locale', locale }  'screen.*' strings (prefix kept)
   Between two states the running contrast run keeps animating on the page's own clock.
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const cv = document.getElementById('screen');
  const view = new window.NZAAngio.FluoroView(cv, {});
  let st = null, recvAt = 0, demoT0 = 0, demo = false;

  function size() {
    const w = Math.max(320, Math.round(window.innerWidth)), h = Math.max(180, Math.round(window.innerHeight));
    if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
  }
  size();
  window.addEventListener('resize', size);

  window.addEventListener('message', e => {
    let d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
    if (!d || typeof d !== 'object') return;
    if (d.type === 'state' && d.state && typeof d.state === 'object') { st = d.state; recvAt = performance.now(); demo = false; }
    else if (d.type === 'standby') st = null;
    else if (d.type === 'locale' && d.locale && typeof d.locale === 'object') view.o.locale = d.locale;
  });

  function frame(now) {
    size();
    let s = st;
    if (demo) {
      const t = ((now - demoT0) / 1000) % 8;
      s = window.NZAAngio.demoState({ seed: 4127, key: 'ileal', sev: 3 }, t > 1 ? t - 1 : 0);
      s.run && (s.hud.label = 'Selective run · Superior mesenteric');
    } else if (s && s.run) {
      // keep the run moving between updates (capped so a stalled sender freezes it)
      const extra = Math.min(0.3, (now - recvAt) / 1000);
      s = Object.assign({}, s, { run: Object.assign({}, s.run, { t: s.run.t + extra }) });
    }
    try { view.render(s, now); } catch (err) { console.error('[angio screen]', err); }
    requestAnimationFrame(frame);
  }

  if (/[?&]demo=1/.test(location.search)) { demo = true; demoT0 = performance.now(); }
  requestAnimationFrame(frame);
})();
