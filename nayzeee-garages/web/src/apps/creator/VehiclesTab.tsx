/**
 * Interior creator — Vehicles tab: display vehicle positions placed with the in-game
 * ghost tool (add / move / go to / delete). Every change is mirrored to the in-game
 * ghosts with creator:showSlots (done by setSlots in CreatorApp).
 */
import { useState } from 'react';
import { t } from '@/lib/i18n';
import { Button, EmptyState, Icon, IconButton, InfoDot } from '@/components/ui';
import { PointRow, SectionHead, coordSummary, headingLabel } from './parts';
import type { TabProps } from './parts';

export function VehiclesTab({ draft, setSlots, run, pending, errors, profiles }: TabProps) {
  const slots = draft.slots;
  const busy = pending !== null;
  const profile = profiles.find((p) => p.key === draft.profile) ?? null;
  const [placing, setPlacing] = useState<number | 'new' | null>(null);

  const add = async () => {
    setPlacing('new');
    const res = await run('placeSlot', 'creator:placeSlot', { index: null, slot: null });
    setPlacing(null);
    if (res?.ok && res.data) setSlots([...draft.slots, res.data]);
  };

  const edit = async (i: number) => {
    setPlacing(i);
    const res = await run('placeSlot', 'creator:placeSlot', { index: i, slot: slots[i] });
    setPlacing(null);
    if (res?.ok && res.data) {
      const placed = res.data;
      setSlots(draft.slots.map((s, k) => (k === i ? placed : s)));
    }
  };

  const remove = (i: number) => setSlots(slots.filter((_, k) => k !== i));

  return (
    <div className="nz-creator__stack">
      <div className="nz-creator__block">
        <SectionHead
          title={t('Vehicle positions')}
          count={slots.length}
          info={
            <InfoDot
              text={t('Spots where the owner’s vehicles are displayed inside. Each floor shows this many vehicles; more vehicles go to the next floor.')}
            />
          }
          actions={
            <Button size="sm" variant="teal" icon="plus" loading={placing === 'new'} disabled={busy} onClick={() => void add()}>
              {t('Add')}
            </Button>
          }
        />

        {profile && profile.slots > 0 && (
          <p className="nz-creator__help nz-creator__help--top">
            <Icon name="info" size={12} strokeWidth={1.8} />
            {slots.length < profile.slots
              ? t('{name} has room for about {count} vehicles.', { name: profile.label, count: profile.slots })
              : t('All {count} suggested spots of {name} are placed.', { name: profile.label, count: profile.slots })}
          </p>
        )}

        {slots.length === 0 ? (
          <EmptyState
            compact
            icon="car"
            title={t('No vehicle positions')}
            description={t('Add at least one spot. A ghost vehicle appears in front of you: move it into place and confirm with Enter.')}
            action={
              <Button size="sm" icon="plus" disabled={busy} onClick={() => void add()}>
                {t('Add position')}
              </Button>
            }
            className={errors.slots ? 'nz-creator__empty-error' : undefined}
          />
        ) : (
          <ol className="nz-creator__list">
            {slots.map((s, i) => (
              <PointRow
                key={`${i}-${s.x}-${s.y}-${s.z}`}
                index={i + 1}
                className={placing === i ? 'is-editing' : undefined}
                main={coordSummary(s)}
                sub={t('Heading {heading}', { heading: headingLabel(s.w) })}
                actions={
                  <>
                    <IconButton
                      icon="route"
                      size="sm"
                      label={t('Teleport here')}
                      disabled={busy}
                      onClick={() => void run('teleport', 'creator:teleport', { coords: s })}
                    />
                    <IconButton icon="edit" size="sm" label={t('Move this position')} disabled={busy} onClick={() => void edit(i)} />
                    <IconButton
                      icon="trash"
                      size="sm"
                      label={t('Delete position')}
                      disabled={busy}
                      onClick={() => remove(i)}
                      className="nz-creator__danger"
                    />
                  </>
                }
              />
            ))}
          </ol>
        )}

        {errors.slots && (
          <p className="nz-creator__error" role="alert">
            <Icon name="warning" size={12} strokeWidth={1.8} />
            {errors.slots}
          </p>
        )}
      </div>
    </div>
  );
}
