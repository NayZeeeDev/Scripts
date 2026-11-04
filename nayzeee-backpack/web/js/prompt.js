/* Key prompt: { action: 'prompt', data: { items: [{ k: 'E', label: 'Place' }, ...] } }, data null hides it */
(function () {
  const box = document.getElementById('keyPrompt');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  let hideTimer = null;
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (action !== 'prompt') return;
    clearTimeout(hideTimer);
    if (!data || !data.items || !data.items.length) {
      box.classList.remove('on');
      hideTimer = setTimeout(() => { if (!box.classList.contains('on')) box.innerHTML = ''; }, 200);
      return;
    }
    box.innerHTML = data.items.map((it) => it.k
      ? `<span class="kp-item"><kbd>${esc(it.k)}</kbd>${esc(it.label)}</span>`
      : `<span class="kp-item kp-note">${esc(it.label)}</span>`).join('');
    box.classList.add('on');
  });
})();
