import en, { type I18nKey } from './en';

let dict: Record<string, string> = { ...en };

/** Merge locale overrides from UiConfig.locale (either the `ui` sub-table or flat keys). */
export function setLocale(locale?: Record<string, unknown>) {
  dict = { ...en };
  if (!locale) return;
  const src = (locale.ui && typeof locale.ui === 'object' ? locale.ui : locale) as Record<string, unknown>;
  for (const [k, v] of Object.entries(src)) if (typeof v === 'string' && k in en) dict[k] = v;
}

export function t(key: I18nKey | string, ...args: (string | number)[]): string {
  let s = dict[key] ?? key;
  for (const a of args) s = s.replace('%s', String(a));
  return s;
}

export type { I18nKey };
