/**
 * Translation helper. English text is the key (same tables as the Lua `L()` helper):
 *   t('Search by name or plate')
 *   t('{count} vehicle(s)', { count: 4 })
 */
import { useUi } from './store';

export function t(text: string, vars?: Record<string, string | number>): string {
  const dict = useUi.getState().locale;
  let out = dict[text] ?? text;
  if (vars) {
    out = out.replace(/\{(\w+)\}/g, (m, k: string) => (vars[k] === undefined ? m : String(vars[k])));
  }
  return out;
}

/** Re-render when the locale changes (rarely needed — locale is set before UI opens). */
export function useT() {
  useUi((s) => s.locale);
  return t;
}
