/**
 * Change owner: a player (identifier search via admin:players:search), a job or a gang.
 */
import { useEffect, useMemo, useState } from 'react';
import { Avatar, Button, EmptyState, Field, Icon, Modal, SearchInput, Segmented, Select, SkeletonRows, cx } from '@/components/ui';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import type { AdminOpenData, AdminVehicleDetail, AdminVehiclePatch, PlayerSearchRow } from '@/lib/types';
import { Highlight, OnlineDot } from '../common';
import { ownerTypeLabel } from '../util';

type OwnerType = 'player' | 'job' | 'gang';

interface Props {
  open: boolean;
  data: AdminOpenData;
  detail: AdminVehicleDetail;
  onClose: () => void;
  onSave: (patch: AdminVehiclePatch, message: string) => Promise<boolean>;
}

export function OwnerModal({ open, data, detail, onClose, onSave }: Props) {
  const v = detail.vehicle;
  const [type, setType] = useState<OwnerType>(v.ownerType);
  const [query, setQuery] = useState('');
  const [searched, setSearched] = useState<string | null>(null);
  const [rows, setRows] = useState<PlayerSearchRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [picked, setPicked] = useState<PlayerSearchRow | null>(null);
  const [job, setJob] = useState<string | null>(v.job);
  const [gang, setGang] = useState<string | null>(v.gang);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) return;
    setType(v.ownerType);
    setQuery('');
    setSearched(null);
    setRows([]);
    setPicked(null);
    setJob(v.job ?? data.jobs[0]?.name ?? null);
    setGang(v.gang ?? data.gangs[0]?.name ?? null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, detail]);

  const search = async () => {
    const q = query.trim();
    setLoading(true);
    const res = await request('admin:players:search', { query: q, page: 1 });
    setLoading(false);
    setSearched(q);
    setRows(res.ok ? res.data.rows : []);
  };

  const typeOptions = useMemo(
    () =>
      [
        { value: 'player' as const, label: t('Player'), icon: 'user' as const },
        { value: 'job' as const, label: t('Job'), icon: 'briefcase' as const },
        ...(data.gangsSupported ? [{ value: 'gang' as const, label: t('Gang'), icon: 'users' as const }] : []),
      ],
    [data.gangsSupported],
  );

  let patch: AdminVehiclePatch | null = null;
  let label = '';
  if (type === 'player' && picked && !(picked.identifier === v.owner && v.ownerType === 'player')) {
    patch = { owner: { type: 'player', identifier: picked.identifier } };
    label = picked.name;
  } else if (type === 'job' && job && !(v.ownerType === 'job' && v.job === job)) {
    patch = { owner: { type: 'job', job } };
    label = data.jobs.find((j) => j.name === job)?.label ?? job;
  } else if (type === 'gang' && gang && !(v.ownerType === 'gang' && v.gang === gang)) {
    patch = { owner: { type: 'gang', gang } };
    label = data.gangs.find((g) => g.name === gang)?.label ?? gang;
  }

  const submit = async () => {
    if (!patch || busy) return;
    setBusy(true);
    const ok = await onSave(patch, t('{vehicle} now belongs to {owner}', { vehicle: v.label, owner: label }));
    setBusy(false);
    if (ok) onClose();
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      locked={busy}
      icon="key"
      title={t('Change owner')}
      subtitle={`${v.label} · ${v.plate}`}
      width={500}
      footer={
        <>
          <Button variant="line" onClick={onClose} disabled={busy}>
            {t('Cancel')}
          </Button>
          <Button variant="teal" icon="check" onClick={submit} loading={busy} disabled={!patch}>
            {t('Change owner')}
          </Button>
        </>
      }
    >
      <div className="nz-aveh-owner-now">
        <Avatar name={v.ownerName || '?'} size={30} />
        <div>
          <span>{t('Current owner')}</span>
          <b>
            {v.ownerName || t('Nobody')} <em>· {ownerTypeLabel(v.ownerType)}</em>
          </b>
        </div>
      </div>

      <Segmented value={type} onChange={setType} options={typeOptions} full />

      {type === 'player' && (
        <div className="nz-aveh-owner-pick">
          <SearchInput
            value={query}
            onChange={setQuery}
            onEnter={search}
            shortcut="Enter"
            loading={loading}
            placeholder={t('Search by player name, identifier, or plate')}
            autoFocus
          />
          <div className="nz-aveh-owner-list">
            {loading ? (
              <SkeletonRows count={3} />
            ) : searched === null ? (
              <EmptyState compact icon="search" title={t('Find the new owner')} description={t('Search for a character and pick them from the list.')} />
            ) : rows.length === 0 ? (
              <EmptyState compact icon="users" title={t('No players found')} description={t('Nothing matches “{query}”.', { query: searched })} />
            ) : (
              rows.map((r) => {
                const current = r.identifier === v.owner && v.ownerType === 'player';
                const on = picked?.identifier === r.identifier;
                return (
                  <button
                    key={r.identifier}
                    type="button"
                    className={cx('nz-aveh-owner-row', on && 'is-on')}
                    onClick={() => setPicked(r)}
                    disabled={current}
                  >
                    <span className="nz-aveh-player__av">
                      <Avatar name={r.name} size={28} />
                      <OnlineDot online={r.online} />
                    </span>
                    <span className="nz-aveh-owner-row__text">
                      <b>
                        <Highlight text={r.name} query={searched} />
                      </b>
                      <span className="nz-aveh-mono">{r.identifier}</span>
                    </span>
                    {current ? (
                      <em className="nz-aveh-owner-row__tag">{t('Current owner')}</em>
                    ) : (
                      <span className={cx('nz-aveh-radio', on && 'is-on')}>{on && <Icon name="check" size={11} strokeWidth={2.6} />}</span>
                    )}
                  </button>
                );
              })
            )}
          </div>
        </div>
      )}

      {type === 'job' && (
        <Field label={t('Job')} hint={t('Members of this job can use the vehicle in their job garages.')}>
          <Select
            value={job}
            onChange={setJob}
            options={data.jobs.map((j) => ({ value: j.name, label: j.label, hint: j.name }))}
            placeholder={t('Choose a job')}
            searchable
          />
        </Field>
      )}

      {type === 'gang' && (
        <Field label={t('Gang')} hint={t('Members of this gang can use the vehicle in their gang garages.')}>
          <Select
            value={gang}
            onChange={setGang}
            options={data.gangs.map((g) => ({ value: g.name, label: g.label, hint: g.name }))}
            placeholder={t('Choose a gang')}
            searchable
          />
        </Field>
      )}
    </Modal>
  );
}
