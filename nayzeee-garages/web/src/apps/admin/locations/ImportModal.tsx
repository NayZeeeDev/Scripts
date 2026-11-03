/**
 * ImportModal — import locations from another garage script or from pasted JSON
 * (admin:location:import { source, json? } → { imported, skipped }).
 *
 * API
 *   <ImportModal open sources onClose onImported(result) />
 * Sources come from AdminOpenData.importSources; ones whose resource is not running are listed
 * but disabled. Locations that already exist (same name and kind) are skipped by the server.
 */
import { useEffect, useState } from 'react';
import { Button, Field, Icon, Modal, Select } from '@/components/ui';
import { request } from '@/lib/nui';
import { toast } from '@/lib/store';
import { t } from '@/lib/i18n';
import type { AdminOpenData } from '@/lib/types';

export interface ImportModalProps {
  open: boolean;
  sources: AdminOpenData['importSources'];
  onClose: () => void;
  onImported: (result: { imported: number; skipped: number }) => void;
}

const EXAMPLE = `[
  {
    "kind": "garage",
    "name": "Del Perro Pier",
    "vehicleType": "car",
    "openPoints": [{ "coords": { "x": -1600.4, "y": -1030.2, "z": 13.1 }, "radius": 2.0 }],
    "spawnPoints": [{ "x": -1606.1, "y": -1024.8, "z": 13.0, "w": 140.0 }]
  }
]`;

export function ImportModal({ open, sources, onClose, onImported }: ImportModalProps) {
  const firstAvailable = sources.find((s) => s.available)?.key ?? null;
  const [source, setSource] = useState<string | null>(firstAvailable);
  const [json, setJson] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setError(null);
      setSource((s) => (s && sources.some((x) => x.key === s && x.available) ? s : firstAvailable));
    }
  }, [open, sources, firstAvailable]);

  const isJson = source === 'json';
  const canSubmit = !!source && (!isJson || json.trim().length > 0);

  const submit = async () => {
    if (!source || busy) return;
    if (isJson) {
      try {
        JSON.parse(json);
      } catch {
        setError(t('This is not valid JSON. Check for missing commas or quotes.'));
        return;
      }
    }
    setError(null);
    setBusy(true);
    const res = await request('admin:location:import', isJson ? { source, json } : { source });
    setBusy(false);
    if (!res.ok) return;
    const { imported, skipped } = res.data;
    toast({
      type: imported > 0 ? 'success' : 'info',
      title: t('Import finished'),
      message:
        skipped > 0
          ? t('{imported} imported, {skipped} skipped (already exist or invalid).', { imported, skipped })
          : t('{imported} locations imported.', { imported }),
    });
    if (isJson) setJson('');
    onImported(res.data);
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      locked={busy}
      icon="import"
      title={t('Import locations')}
      subtitle={t('Bring garages over from the script you used before')}
      width={520}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="import" loading={busy} disabled={!canSubmit} onClick={() => void submit()}>
            {t('Import')}
          </Button>
        </>
      }
    >
      {sources.length === 0 ? (
        <div className="nz-admin-import__note">
          <Icon name="info" size={14} strokeWidth={1.7} />
          {t('No import sources are configured in config/server.lua (ServerConfig.ImportSources).')}
        </div>
      ) : (
        <>
          <Field label={t('Source')} hint={!firstAvailable ? t('None of the supported resources are running.') : undefined}>
            <Select<string>
              value={source}
              onChange={(v) => {
                setSource(v);
                setError(null);
              }}
              placeholder={t('Choose a source')}
              options={sources.map((s) => ({
                value: s.key,
                label: s.label,
                hint: s.available ? (s.key === 'json' ? t('Paste below') : t('Running')) : t('Not running'),
                icon: s.key === 'json' ? 'code' : 'import',
                disabled: !s.available,
              }))}
            />
          </Field>

          {isJson ? (
            <Field
              label={t('Locations JSON')}
              error={error ?? undefined}
              hint={t('An array of locations in the same shape the panel saves. Existing names are skipped.')}
              aside={
                <button type="button" className="nz-admin-import__example" onClick={() => setJson(EXAMPLE)}>
                  {t('Insert example')}
                </button>
              }
            >
              <textarea
                className="nz-admin-import__json"
                value={json}
                spellCheck={false}
                placeholder={EXAMPLE}
                onChange={(e) => {
                  setJson(e.target.value);
                  if (error) setError(null);
                }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
                    e.preventDefault();
                    void submit();
                  }
                }}
              />
            </Field>
          ) : (
            source && (
              <div className="nz-admin-import__note">
                <Icon name="info" size={14} strokeWidth={1.7} />
                {t('Garages, job garages and impounds are read from the config of {resource}. Garages that already exist here are skipped, nothing is overwritten.', {
                  resource: source,
                })}
              </div>
            )
          )}
        </>
      )}
    </Modal>
  );
}
