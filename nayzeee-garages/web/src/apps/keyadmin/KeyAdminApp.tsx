/**
 * keyadmin app — admin key manager and admin key settings (docs/V2_CHANGES.md G.12 / G.13).
 * Opened by /vehiclekeysadmin (client/carlock/keyadmin.lua: CarLock.openKeyAdmin(opts)).
 *
 * Header pills switch between "Manage keys" (search a player → their keys, plate view, track,
 * give / delete) and "Settings" (the server's key settings schema, tabs, search, save). The
 * settings page stays mounted once visited, so its unsaved draft survives a switch to the
 * keys page. Escape and the Close pill ask first while settings are unsaved.
 * Every answer comes from the server (admin checked there); the page never decides anything.
 */
import { useCallback, useEffect, useState } from 'react';
import { Badge, ConfirmDialog, KeyHint, Segmented, Window } from '@/components/ui';
import { useEscape } from '@/lib/escape';
import { t } from '@/lib/i18n';
import { useApp } from '@/lib/store';
import type { KeyAdminOpenData, KeyMode } from '@/lib/types';
import { ManageKeys } from './ManageKeys';
import { SettingsView } from './SettingsView';
import { optionLabel } from './model';
import './keyadmin.css';

type Page = 'keys' | 'settings';

export function KeyAdminApp() {
  const app = useApp('keyadmin');
  if (!app.open || !app.data) return null;
  return <KeyAdminWindow data={app.data} close={app.close} />;
}

function KeyAdminWindow({ data, close }: { data: KeyAdminOpenData; close: () => void }) {
  const [page, setPage] = useState<Page>(data.page === 'settings' ? 'settings' : 'keys');
  const [settingsMounted, setSettingsMounted] = useState(page === 'settings');
  const [dirty, setDirty] = useState(false);
  const [askClose, setAskClose] = useState(false);
  const [keyMode, setKeyMode] = useState<KeyMode | null>(data.keyMode ?? null);

  useEffect(() => {
    if (page === 'settings') setSettingsMounted(true);
  }, [page]);
  useEffect(() => {
    if (data.keyMode) setKeyMode(data.keyMode);
  }, [data.keyMode]);

  const requestClose = useCallback(() => {
    if (dirty) setAskClose(true);
    else close();
  }, [dirty, close]);
  useEscape(requestClose, true);

  const modeLabel = keyMode ? optionLabel('keys.mode', keyMode).label : null;

  return (
    <Window
      className="nz-kadm"
      bodyClassName="nz-kadm__body"
      width="min(1320px, 95vw)"
      height="min(880px, 93vh)"
      title={t('Key manager')}
      icon="key"
      subtitle={page === 'keys' ? t('Find a player and see where every key is') : t('Server-wide key rules, stored in the database')}
      onClose={requestClose}
      headerExtra={
        <div className="nz-kadm__head">
          {modeLabel && (
            <Badge tone="neutral" icon="key" size="sm" className="nz-kadm__mode" title={t('Key mode')}>
              {modeLabel}
            </Badge>
          )}
          <Segmented<Page>
            value={page}
            onChange={setPage}
            className="nz-kadm__nav"
            options={[
              { value: 'keys', label: t('Manage keys'), icon: 'users' },
              { value: 'settings', label: dirty ? `${t('Settings')} •` : t('Settings'), icon: 'cog' },
            ]}
          />
        </div>
      }
      footer={
        <>
          <span className="nz-kadm__foot-note">
            {page === 'keys' ? t('Every change is checked and logged by the server') : t('Changes apply to every player right away')}
          </span>
          <span className="nz-kadm__foot-keys">
            {page === 'keys' ? <KeyHint keys={['Enter']} label={t('Search')} /> : <KeyHint keys={['Ctrl', 'S']} label={t('Save')} />}
            <KeyHint keys={['Esc']} label={t('Close')} />
          </span>
        </>
      }
    >
      <div className="nz-kadm__page" hidden={page !== 'keys'}>
        <ManageKeys data={data} active={page === 'keys'} />
      </div>
      {settingsMounted && (
        <div className="nz-kadm__page" hidden={page !== 'settings'}>
          <SettingsView
            active={page === 'settings'}
            initialTab={data.settingsTab ?? null}
            onDirtyChange={setDirty}
            onKeyMode={setKeyMode}
          />
        </div>
      )}
      <ConfirmDialog
        open={askClose}
        tone="red"
        icon="warning"
        title={t('Discard unsaved changes?')}
        message={t('Some key settings are not saved yet. Close the key manager without saving them?')}
        confirmLabel={t('Close without saving')}
        cancelLabel={t('Keep editing')}
        onConfirm={() => {
          setAskClose(false);
          close();
        }}
        onCancel={() => setAskClose(false)}
      />
    </Window>
  );
}
