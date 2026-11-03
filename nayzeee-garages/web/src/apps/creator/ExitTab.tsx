/**
 * Interior creator — Exit tab: optional walk-out point (falls back to the entry point).
 */
import { t } from '@/lib/i18n';
import { Button, Icon, IconButton, InfoDot } from '@/components/ui';
import { CoordCard, SectionHead, isSet } from './parts';
import type { TabProps } from './parts';

export function ExitTab({ draft, patch, run, pending }: TabProps) {
  const busy = pending !== null;
  const exit = isSet(draft.exit) ? draft.exit : null;

  const pickExit = async () => {
    const res = await run('pickExit', 'creator:pickExit', {});
    if (res?.ok && res.data) patch({ exit: res.data });
  };

  return (
    <div className="nz-creator__stack">
      <div className="nz-creator__block">
        <SectionHead
          title={t('Exit point')}
          info={<InfoDot text={t('Players walk to this marker to leave the garage on foot.')} />}
        />
        <p className="nz-creator__help nz-creator__help--top">
          {t('Where players walk out of the garage. Without an exit point, the entry point is used.')}
        </p>

        <CoordCard value={exit} placeholder={t('Using the entry point')} />

        <div className="nz-creator__point-actions">
          <Button
            size="sm"
            icon="pin"
            loading={pending === 'pickExit'}
            disabled={busy}
            onClick={() => void pickExit()}
            className="nz-creator__grow"
          >
            {t('Use current position')}
          </Button>
          <IconButton
            icon="route"
            size="sm"
            variant="line"
            label={t('Teleport to the exit point')}
            disabled={busy || !exit}
            onClick={() => exit && void run('teleport', 'creator:teleport', { coords: exit })}
          />
          <IconButton
            icon="trash"
            size="sm"
            variant="line"
            label={t('Clear (use the entry point)')}
            disabled={busy || !exit}
            onClick={() => patch({ exit: null })}
            className="nz-creator__danger"
          />
        </div>

        <div className={`nz-creator__detect${exit ? ' is-found' : ''}`}>
          <Icon name={exit ? 'door' : 'info'} size={13} strokeWidth={1.8} />
          <span>{exit ? t('Players leave from this point.') : t('Players leave from the entry point.')}</span>
        </div>
      </div>
    </div>
  );
}
