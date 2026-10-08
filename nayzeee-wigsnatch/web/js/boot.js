/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V3 · message router + boot
   ═══════════════════════════════════════════════════════════ */
'use strict';

const HANDLERS = {
  toast, banner, levelup, speech, progress, hint, struggle,
  sound: (d) => playSound(d.name, d.volume, d.duration),
  cash: () => SFX.cash(),
  prefs: applyPrefs,
  'clash:start': clashStart, 'clash:tick': clashTick, 'clash:seq': clashSeq, 'clash:end': clashEnd,
  'cut:start': cutStart, 'cut:update': cutUpdate, 'cut:tool': cutTool, 'cut:fx': cutFx, 'cut:end': cutEnd,
  'cut:sit': cutSit, 'cut:sitEnd': cutSitEnd,
  reveal,
  'app:open': (d) => openApp(d.view, d.data),
  'app:close': () => closeApp(true),
  'app:refresh': async () => {
    if (S.view === 'vault') loadVault();
    if (S.view === 'phone') phoneMsg({ type: 'refresh' });
  },
  'phone:msg': phoneMsg,
  'prompt:open': promptOpen,
  'prompt:close': promptClose,
  'studio:run': studioRun,
  'studio:saved': (d) => { if (S.studio && !d.err && !arr(S.studio.shots).includes(d.key)) S.studio.shots = arr(S.studio.shots).concat(d.key); },
  'studio:error': (d) => toast({ kind: 'error', message: d.msg }),
};

addEventListener('message', (e) => {
  const m = e.data || {};
  const h = HANDLERS[m.action];
  if (h) h(m.data || {});
});

// one keyboard router: settings key capture > minigame > cutting > close
function onKey(e) {
  if (settingsKey(e)) return;
  if (gameKey(e)) return;
  if (cutKey(e)) return;
  if (e.type !== 'keydown') return;
  if (e.key === 'Escape') {
    if (!$('#modal').hidden) return closeModal();
    if (S.view) return closeApp();
  }
}
addEventListener('keydown', onKey);
addEventListener('keyup', onKey);

(async function boot() {
  let cfg = null;
  for (let i = 0; i < 6 && !cfg; i++) {
    cfg = await post('ready');
    if (!cfg) await new Promise((r) => setTimeout(r, 1000));
  }
  if (!cfg) return;
  S.cfg = Object.assign(S.cfg, cfg);
  arr(cfg.tiers).forEach((t) => (S.tiers[t.id] = t));
  S.cfg.tiers = arr(cfg.tiers);
  S.cfg.grades = arr(cfg.grades);
  S.cfg.grades.forEach((g) => (S.grades[g.id] = g));
  applyPrefs(cfg.prefs);
})();

window.WS = { handle: (action, data) => HANDLERS[action] && HANDLERS[action](data || {}), S };
