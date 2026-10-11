// Notifications, progress bar and text prompts. Lives in #ui, outside the HUD widgets,
// so it keeps working while the HUD is toggled off.
(() => {
  const NH = window.NH;
  const ic = NH.ic;
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const KIND = {
    success: { icon: 'check', c: '#08afa2', r: '8,175,162' },
    error: { icon: 'x', c: '#e5484d', r: '229,72,77' },
    warning: { icon: 'warn', c: '#e5a50a', r: '229,165,10' },
    info: { icon: 'info', c: '#58a6ff', r: '88,166,255' },
  };
  NH.NOTIFY_STYLES = [['card', 'Card'], ['glass', 'Glass'], ['pill', 'Pill'], ['stripe', 'Stripe'], ['minimal', 'Minimal']];
  NH.PROGRESS_STYLES = [['bar', 'Bar'], ['ring', 'Ring'], ['line', 'Line'], ['pill', 'Pill']];
  NH.TEXT_STYLES = [['key', 'Key'], ['card', 'Card'], ['minimal', 'Minimal']];

  let root, stack, prog, text;
  const ui = () => NH.cur.ui || NH.DEFAULTS.ui;

  NH.buildUI = () => {
    root = document.getElementById('ui');
    root.innerHTML = '<div class="nt-stack"></div><div class="pg"></div><div class="tx"></div>';
    stack = root.querySelector('.nt-stack');
    prog = root.querySelector('.pg');
    text = root.querySelector('.tx');
    NH.applyUI();
  };

  NH.applyUI = () => {
    if (!root) return;
    const c = ui();
    stack.className = `nt-stack at-${c.notifyPos} ns-${c.notify}`;
    // swap only the style / position classes so a running progress bar or open prompt keeps its state
    const swap = (el, prefix, cls) => {
      [...el.classList].filter((k) => k.startsWith(prefix)).forEach((k) => el.classList.remove(k));
      el.classList.add(cls);
    };
    swap(prog, 'ps-', `ps-${c.progress}`);
    swap(text, 'ts-', `ts-${c.text}`);
    swap(text, 'at-', `at-${text.dataset.pos || c.textPos}`);
  };

  // ─── notifications ───────────────────────────────────────
  const noteHtml = (d, style) => {
    const k = KIND[d.kind] || KIND.info;
    const icon = d.icon && NH.ICONS[d.icon] ? d.icon : k.icon;
    return `<div class="nt nt-${d.kind}" style="--nc:${k.c};--nr:${k.r};--nd:${d.duration}ms">
      <span class="nt-i">${ic(icon)}</span>
      <div class="nt-t">${d.title ? `<b>${esc(d.title)}</b>` : ''}${d.message ? `<p>${esc(d.message)}</p>` : ''}</div>
      <i class="nt-bar"></i></div>`;
  };

  NH.notify = (d) => {
    if (!stack) return;
    d = Object.assign({ kind: 'info', duration: 5000 }, d);
    // same message twice in a row: bump the counter instead of stacking
    const key = `${d.kind}|${d.title || ''}|${d.message || ''}`;
    const dup = [...stack.children].find((n) => n.dataset.key === key && !n.classList.contains('out'));
    if (dup) {
      const n = (Number(dup.dataset.n) || 1) + 1;
      dup.dataset.n = n;
      let b = dup.querySelector('.nt-n');
      if (!b) { b = document.createElement('em'); b.className = 'nt-n'; dup.appendChild(b); }
      b.textContent = `×${n}`;
      clearTimeout(dup._t);
      dup._t = setTimeout(() => out(dup), d.duration);
      const bar = dup.querySelector('.nt-bar');
      bar.style.animation = 'none'; void bar.offsetWidth; bar.style.animation = '';
      return;
    }
    const wrap = document.createElement('div');
    wrap.innerHTML = noteHtml(d, ui().notify);
    const el = wrap.firstElementChild;
    el.dataset.key = key;
    const bottom = ui().notifyPos.startsWith('bottom');
    if (bottom) stack.appendChild(el); else stack.prepend(el);
    while (stack.children.length > 5) (bottom ? stack.firstElementChild : stack.lastElementChild).remove();
    void el.offsetWidth; // start from the off-screen style so it slides in
    el.classList.add('in');
    el._t = setTimeout(() => out(el), d.duration);
    if (ui().notifySound) NH.sfx(d.kind === 'error' ? 'nerr' : 'note');
  };
  const out = (el) => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 260);
  };

  // ─── progress ─────────────────────────────────────────────
  let progT = 0;
  NH.progress = (d) => {
    if (!prog) return;
    clearTimeout(progT);
    if (d.done) {
      prog.classList.toggle('cancelled', !!d.cancelled);
      prog.classList.add('fin');
      progT = setTimeout(() => prog.classList.remove('on', 'fin', 'cancelled'), d.cancelled ? 700 : 350);
      return;
    }
    const icon = d.icon && NH.ICONS[d.icon] ? ic(d.icon) : '';
    prog.innerHTML = `<div class="pg-box">
      <svg class="pg-ring" viewBox="0 0 48 48"><circle class="t" cx="24" cy="24" r="21" pathLength="100"/><circle class="f" cx="24" cy="24" r="21" pathLength="100"/></svg>
      <div class="pg-top">${icon}<b>${esc(d.label)}</b><em class="pg-pct">0%</em></div>
      <div class="pg-bar"><i></i></div>
      ${d.cancel ? `<small class="pg-cancel"><kbd>${esc(d.cancel)}</kbd> Cancel</small>` : ''}</div>`;
    prog.classList.remove('fin', 'cancelled');
    prog.classList.add('on');
    prog.style.setProperty('--pd', `${d.duration}ms`);
    // one CSS transition drives the bar; the % label ticks a few times a second
    const start = performance.now(), pct = prog.querySelector('.pg-pct');
    prog.classList.remove('run');
    requestAnimationFrame(() => requestAnimationFrame(() => prog.classList.add('run')));
    const tick = () => {
      if (!prog.classList.contains('on') || prog.classList.contains('fin')) return;
      const p = Math.min(100, Math.floor((performance.now() - start) / d.duration * 100));
      pct.textContent = `${p}%`;
      if (p < 100) progT = setTimeout(tick, 100);
    };
    tick();
  };

  // ─── text prompt ──────────────────────────────────────────
  const POS = { left: 'left', right: 'right', top: 'top', bottom: 'bottom', 'left-center': 'left', 'right-center': 'right', 'top-center': 'top', 'bottom-center': 'bottom' };
  NH.textUI = (d) => {
    if (!text) return;
    if (d.hide) { text.classList.remove('on'); return; }
    const key = d.key ? `<kbd>${esc(String(d.key).slice(0, 6))}</kbd>` : '';
    const icon = d.icon && NH.ICONS[d.icon] ? ic(d.icon) : '';
    // allow [E] at the start of the text as the key, like a lot of scripts send
    let msg = String(d.text || ''), k = key;
    const m = !k && msg.match(/^\s*\[([^\]]{1,6})\]\s*-?\s*/);
    if (m) { k = `<kbd>${esc(m[1])}</kbd>`; msg = msg.slice(m[0].length); }
    text.dataset.pos = POS[d.position] || '';
    text.innerHTML = `<div class="tx-box${k ? '' : ' nokey'}">${k}${icon}<span>${esc(msg)}</span></div>`;
    NH.applyUI();
    text.classList.add('on');
  };

  // previews for the settings tab
  NH.uiPreview = {
    notify: (style) => `<div class="nt-stack pv-ui ns-${style}">${noteHtml({ kind: 'success', title: 'Garage', message: 'Your vehicle is ready.', duration: 5000 }).replace('class="nt ', 'class="nt in ')}${noteHtml({ kind: 'error', message: 'Not enough cash.', duration: 5000 }).replace('class="nt ', 'class="nt in ')}</div>`,
    progress: (style) => `<div class="pg ps-${style} on pv-ui" style="--pv:62"><div class="pg-box"><svg class="pg-ring" viewBox="0 0 48 48"><circle class="t" cx="24" cy="24" r="21" pathLength="100"/><circle class="f" cx="24" cy="24" r="21" pathLength="100"/></svg><div class="pg-top"><b>Picking the lock</b><em class="pg-pct">62%</em></div><div class="pg-bar"><i></i></div><small class="pg-cancel"><kbd>X</kbd> Cancel</small></div></div>`,
    text: (style) => `<div class="tx ts-${style} on pv-ui"><div class="tx-box"><kbd>E</kbd><span>Open the stash</span></div></div>`,
  };
})();
