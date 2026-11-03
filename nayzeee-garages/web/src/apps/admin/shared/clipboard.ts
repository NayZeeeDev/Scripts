/**
 * copyText(text): copy to the clipboard from the FiveM NUI (CEF has no permission for the async
 * Clipboard API there, so a hidden textarea + execCommand('copy') is tried first).
 * Returns true when the copy most likely worked. Focus is restored afterwards.
 */
export function copyText(text: string): boolean {
  const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    ta.style.top = '0';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    active?.focus({ preventScroll: true });
    if (ok) return true;
  } catch {
    /* fall through */
  }
  try {
    if (navigator.clipboard) {
      void navigator.clipboard.writeText(text).catch(() => undefined);
      return true;
    }
  } catch {
    /* unavailable */
  }
  return false;
}
