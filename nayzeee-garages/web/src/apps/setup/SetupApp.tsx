/**
 * Vehicle setup (app 'setup', takes focus): bottom-left HUD panel shown after a job /
 * spawner vehicle spawns. Liveries (radio list, live preview) and extras (toggles), then
 * Drive. Escape and Enter drive as well. Tabs without items are hidden.
 */
import { useEffect, useRef, useState } from 'react';
import { closeApp, useApp, useUi } from '@/lib/store';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import { Button, Icon, KeyHint, Segmented, Toggle, cx } from '@/components/ui';
import './setup.css';

type Tab = 'liveries' | 'extras';

const isTyping = (el: EventTarget | null) => {
  const node = el as HTMLElement | null;
  if (!node || !node.tagName) return false;
  return node.tagName === 'INPUT' || node.tagName === 'TEXTAREA';
};

export function SetupApp() {
  const { open, data, update } = useApp('setup');
  const [tab, setTab] = useState<Tab>('liveries');
  const [driving, setDriving] = useState(false);
  const liverySeq = useRef(0);
  const listRef = useRef<HTMLDivElement>(null);

  const liveries = data?.liveries ?? [];
  const extras = data?.extras ?? [];
  // A single livery cannot be changed: no point in showing the list.
  const hasLiveries = liveries.length > 1;
  const hasExtras = extras.length > 0;
  const activeTab: Tab = tab === 'liveries' && !hasLiveries ? 'extras' : tab === 'extras' && !hasExtras ? 'liveries' : tab;

  useEffect(() => {
    if (!open) return;
    setDriving(false);
    setTab(hasLiveries ? 'liveries' : 'extras');
    // Only on open: later data updates (extras sync) must not switch the tab.
  }, [open]);

  const drive = async () => {
    if (driving) return;
    setDriving(true);
    const res = await request('setup:drive', {});
    if (res.ok) useUi.getState().hideApp('setup');
    // Lua's close handler finishes the setup too: never leave the player stuck with focus.
    else closeApp('setup');
  };

  useEscape(() => void drive(), open);

  const pickLivery = async (index: number) => {
    const current = useUi.getState().apps.setup.data;
    if (!current || driving || index === current.livery) return;
    const prev = current.livery;
    update({ livery: index });
    const seq = ++liverySeq.current;
    const res = await request('setup:livery', { index });
    if (!res.ok && seq === liverySeq.current) update({ livery: prev });
  };

  const toggleExtra = async (id: number, enabled: boolean) => {
    const current = useUi.getState().apps.setup.data;
    if (!current || driving) return;
    const set = (on: boolean) => {
      const now = useUi.getState().apps.setup.data;
      if (now) update({ extras: now.extras.map((e) => (e.id === id ? { ...e, enabled: on } : e)) });
    };
    set(enabled);
    const res = await request('setup:extra', { id, enabled });
    if (!res.ok) set(!enabled);
  };

  // Keyboard: ↑/↓ browse liveries (live preview), Enter drives.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (isTyping(e.target)) return;
      const current = useUi.getState().apps.setup.data;
      if (!current) return;
      if (e.key === 'Enter') {
        const tag = (e.target as HTMLElement | null)?.tagName;
        if (tag === 'BUTTON') return; // a focused button handles Enter itself
        e.preventDefault();
        void drive();
        return;
      }
      if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && activeTab === 'liveries' && current.liveries.length > 1) {
        e.preventDefault();
        const list = current.liveries;
        const i = list.findIndex((l) => l.index === current.livery);
        const next = e.key === 'ArrowDown' ? (i + 1) % list.length : (i - 1 + list.length) % list.length;
        void pickLivery(list[Math.max(0, next)].index);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  // Keep the selected livery visible while browsing with the keyboard.
  useEffect(() => {
    const list = listRef.current;
    const item = list?.querySelector<HTMLElement>('[aria-checked="true"]');
    if (!list || !item) return;
    const top = item.offsetTop;
    const bottom = top + item.offsetHeight;
    if (top < list.scrollTop + 4) list.scrollTop = Math.max(0, top - 4);
    else if (bottom > list.scrollTop + list.clientHeight - 4) list.scrollTop = bottom - list.clientHeight + 4;
  }, [data?.livery, activeTab]);

  if (!open || !data) return null;

  const extrasOn = extras.filter((e) => e.enabled).length;
  const showTabs = hasLiveries && hasExtras;

  return (
    <section className="nz-setup" role="dialog" aria-label={t('Vehicle setup')}>
      <header className="nz-setup__head">
        <span className="nz-setup__icon">
          <Icon name="sliders" size={16} strokeWidth={1.8} />
        </span>
        <div className="nz-setup__titles">
          <h2>{t('Vehicle setup')}</h2>
          <p title={data.label}>{data.label || t('Vehicle')}</p>
        </div>
      </header>

      {showTabs && (
        <Segmented<Tab>
          full
          size="sm"
          value={activeTab}
          onChange={setTab}
          options={[
            { value: 'liveries', label: t('Liveries'), icon: 'palette' },
            { value: 'extras', label: t('Extras'), icon: 'sparkle' },
          ]}
          className="nz-setup__tabs"
        />
      )}

      {(hasLiveries || hasExtras) && (
        <div className="nz-setup__content">
          <div className="nz-setup__sub">
            <span>{activeTab === 'liveries' ? t('Liveries') : t('Extras')}</span>
            <small>
              {activeTab === 'liveries'
                ? t('{count} available', { count: liveries.length })
                : t('{on} of {count} on', { on: extrasOn, count: extras.length })}
            </small>
          </div>

          {activeTab === 'liveries' ? (
            <div ref={listRef} className="nz-setup__list" role="radiogroup" aria-label={t('Liveries')}>
              {liveries.map((l) => {
                const on = l.index === data.livery;
                return (
                  <button
                    key={l.index}
                    type="button"
                    role="radio"
                    aria-checked={on}
                    tabIndex={on ? 0 : -1}
                    disabled={driving}
                    className={cx('nz-setup__livery', on && 'is-on')}
                    onClick={() => void pickLivery(l.index)}
                  >
                    <span className="nz-setup__radio" aria-hidden="true">
                      <i />
                    </span>
                    <span className="nz-setup__livery-label">{l.label}</span>
                    {on && <Icon name="eye" size={13} strokeWidth={1.8} className="nz-setup__preview" />}
                  </button>
                );
              })}
            </div>
          ) : (
            <div className="nz-setup__list nz-setup__list--extras">
              {extras.map((x) => (
                <Toggle
                  key={x.id}
                  size="sm"
                  checked={x.enabled}
                  disabled={driving}
                  onChange={(v) => void toggleExtra(x.id, v)}
                  label={t('Extra {id}', { id: x.id })}
                  className="nz-setup__extra"
                />
              ))}
            </div>
          )}
        </div>
      )}

      {!hasLiveries && !hasExtras && <p className="nz-setup__none">{t('Nothing to set up on this vehicle.')}</p>}

      <div className="nz-setup__foot">
        <Button variant="teal" size="lg" icon="arrowRight" full loading={driving} onClick={() => void drive()}>
          {t('Drive')}
        </Button>
        <div className="nz-setup__keys">
          <KeyHint keys={['Esc']} label={t('Drive')} />
          {activeTab === 'liveries' && hasLiveries && <KeyHint keys={['ArrowUp', 'ArrowDown']} label={t('Browse liveries')} />}
        </div>
      </div>
    </section>
  );
}
