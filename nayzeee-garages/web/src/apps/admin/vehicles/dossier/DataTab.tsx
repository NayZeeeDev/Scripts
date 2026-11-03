/**
 * Data tab: the saved vehicle properties as read-only, highlighted JSON with a key filter,
 * a copy button (clipboard API, execCommand fallback for CEF) and "Open editor".
 */
import { useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { Button, EmptyState, Icon, SearchInput, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { Props as VProps } from '../props/catalog';

interface Props {
  props: VProps;
  onEdit: () => void;
}

const TOKEN = /("(?:\\u[a-fA-F0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(?:true|false|null)\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g;

/** JSON text → spans (keys, strings, numbers, booleans, null). */
function highlight(json: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let k = 0;
  for (const m of json.matchAll(TOKEN)) {
    const at = m.index ?? 0;
    if (at > last) out.push(json.slice(last, at));
    const tok = m[0];
    let cls = 'num';
    if (tok.startsWith('"')) cls = m[2] ? 'key' : 'str';
    else if (tok === 'true' || tok === 'false') cls = 'bool';
    else if (tok === 'null') cls = 'null';
    out.push(
      <span key={k++} className={`nz-dos-json__${cls}`}>
        {tok}
      </span>,
    );
    last = at + tok.length;
  }
  if (last < json.length) out.push(json.slice(last));
  return out;
}

async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* CEF often blocks the clipboard API: fall back below */
  }
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}

export function DataTab({ props, onEdit }: Props) {
  const [query, setQuery] = useState('');
  const [copied, setCopied] = useState<'ok' | 'fail' | null>(null);
  const keys = Object.keys(props);
  const q = query.trim().toLowerCase();

  const filtered = useMemo(() => {
    if (!q) return props;
    const out: VProps = {};
    for (const [k, v] of Object.entries(props)) if (k.toLowerCase().includes(q)) out[k] = v;
    return out;
  }, [props, q]);

  const full = useMemo(() => JSON.stringify(props, null, 2), [props]);
  const text = useMemo(() => JSON.stringify(filtered, null, 2), [filtered]);
  const nodes = useMemo(() => highlight(text), [text]);
  const shownKeys = Object.keys(filtered).length;
  const size = new Blob([full]).size;
  const sizeText = size < 1024 ? t('{n} B', { n: size }) : t('{n} KB', { n: (size / 1024).toFixed(1) });

  const copy = async () => {
    const ok = await copyText(q ? text : full);
    setCopied(ok ? 'ok' : 'fail');
    window.setTimeout(() => setCopied(null), 1800);
  };

  if (keys.length === 0) {
    return (
      <div className="nz-dos-pane nz-dos-pane--center">
        <EmptyState
          icon="code"
          title={t('No saved properties')}
          description={t('The vehicle has no stored props yet. They are written the first time it is stored.')}
          action={
            <Button size="sm" variant="teal" icon="edit" onClick={onEdit}>
              {t('Open editor')}
            </Button>
          }
        />
      </div>
    );
  }

  return (
    <div className="nz-dos-pane nz-dos-data">
      <div className="nz-dos-data__bar">
        <SearchInput value={query} onChange={setQuery} placeholder={t('Filter keys, e.g. color or mod')} size="sm" className="nz-dos-data__search" />
        <span className="nz-dos-data__stats">
          {q ? t('{shown} of {n} keys', { shown: shownKeys, n: keys.length }) : t('{n} keys', { n: keys.length })} · {sizeText}
        </span>
        <span className={cx('nz-dos-data__copied', copied && 'is-on', copied === 'fail' && 'is-fail')} aria-live="polite">
          {copied === 'ok' && (
            <>
              <Icon name="check" size={13} strokeWidth={2} />
              {t('Copied')}
            </>
          )}
          {copied === 'fail' && t('Copy is blocked here: select the text instead')}
        </span>
        <Button size="sm" variant="line" icon="copy" onClick={copy}>
          {q ? t('Copy filtered') : t('Copy JSON')}
        </Button>
        <Button size="sm" variant="white" icon="edit" onClick={onEdit}>
          {t('Open editor')}
        </Button>
      </div>
      {shownKeys === 0 ? (
        <EmptyState compact icon="filter" title={t('No keys match “{query}”', { query })} />
      ) : (
        <pre className="nz-dos-json" tabIndex={0} aria-label={t('Vehicle properties JSON')}>
          {nodes}
        </pre>
      )}
    </div>
  );
}
