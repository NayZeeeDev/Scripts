/**
 * Interior creator — Cutscene tab: enable the entry cutscene, timings, the camera path
 * (record the current gameplay camera, reorder, delete) and an in-game preview.
 */
import { t } from '@/lib/i18n';
import type { CameraPoint } from '@/lib/types';
import { Button, EmptyState, Field, IconButton, InfoDot, NumberInput, Toggle, cx } from '@/components/ui';
import { PointRow, SectionHead, coordSummary, fixed, headingLabel } from './parts';
import type { TabProps } from './parts';

export function CutsceneTab({ draft, patchCutscene, run, pending }: TabProps) {
  const cut = draft.cutscene;
  const points = cut.points;
  const busy = pending !== null;

  const setPoints = (next: CameraPoint[]) => patchCutscene({ points: next });

  const addPoint = async () => {
    const res = await run('addCameraPoint', 'creator:addCameraPoint', {});
    if (res?.ok && res.data) setPoints([...draft.cutscene.points, res.data]);
  };

  const move = (i: number, dir: -1 | 1) => {
    const j = i + dir;
    if (j < 0 || j >= points.length) return;
    const next = [...points];
    [next[i], next[j]] = [next[j], next[i]];
    setPoints(next);
  };

  const remove = (i: number) => setPoints(points.filter((_, k) => k !== i));

  const preview = () => {
    if (points.length) void run('preview', 'creator:previewCutscene', { cutscene: draft.cutscene });
  };

  const seconds = points.length ? (cut.transition * Math.max(1, points.length - 1) + cut.returnTime) / 1000 : 0;

  return (
    <div className="nz-creator__stack">
      <div className="nz-creator__card">
        <Toggle
          checked={cut.enabled}
          onChange={(v) => patchCutscene({ enabled: v })}
          label={
            <span className="nz-creator__label-row">
              {t('Cinematic entry cutscene')}
              <InfoDot text={t('Plays the camera path below every time a player goes inside this interior.')} />
            </span>
          }
          description={cut.enabled ? t('Players see the camera path when they enter.') : t('Players appear inside right away.')}
        />
      </div>

      <div className={cx('nz-creator__grid2', !cut.enabled && 'is-muted')}>
        <Field label={t('Transition')} aside={<InfoDot text={t('Time the camera takes to fly from one point to the next.')} />}>
          <NumberInput
            value={cut.transition}
            onChange={(n) => patchCutscene({ transition: n })}
            min={0}
            max={60000}
            step={100}
            suffix={t('ms')}
          />
        </Field>
        <Field label={t('Return')} aside={<InfoDot text={t('Time to blend back to the player camera at the end.')} side="left" />}>
          <NumberInput
            value={cut.returnTime}
            onChange={(n) => patchCutscene({ returnTime: n })}
            min={0}
            max={30000}
            step={100}
            suffix={t('ms')}
          />
        </Field>
      </div>

      <div className={cx('nz-creator__block', !cut.enabled && 'is-muted')}>
        <SectionHead
          title={t('Camera path')}
          count={points.length}
          actions={points.length > 0 && <span className="nz-creator__meta">{t('about {s}s', { s: seconds.toFixed(1) })}</span>}
        />

        {points.length === 0 ? (
          <EmptyState
            compact
            icon="camera"
            title={t('No camera points')}
            description={t('Walk to a spot, aim the camera at the garage, come back and add the point. Add several to make the camera fly between them.')}
          />
        ) : (
          <ol className="nz-creator__list">
            {points.map((p, i) => (
              <PointRow
                key={`${i}-${p.coords.x}-${p.coords.y}`}
                index={i + 1}
                main={coordSummary(p.coords)}
                sub={t('FOV {fov} · pitch {pitch}° · heading {heading}', {
                  fov: Math.round(p.fov),
                  pitch: fixed(p.rot.x, 0),
                  heading: headingLabel(p.rot.z),
                })}
                actions={
                  <>
                    <IconButton icon="chevronUp" size="sm" label={t('Move up')} disabled={busy || i === 0} onClick={() => move(i, -1)} />
                    <IconButton
                      icon="chevronDown"
                      size="sm"
                      label={t('Move down')}
                      disabled={busy || i === points.length - 1}
                      onClick={() => move(i, 1)}
                    />
                    <IconButton
                      icon="trash"
                      size="sm"
                      label={t('Delete point')}
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

        <div className="nz-creator__grid2 nz-creator__grid2--tight">
          <Button icon="camera" full loading={pending === 'addCameraPoint'} disabled={busy} onClick={() => void addPoint()}>
            {t('Add camera point')}
          </Button>
          <Button
            icon="eye"
            variant="white"
            full
            loading={pending === 'preview'}
            disabled={busy || points.length === 0}
            onClick={preview}
            title={points.length === 0 ? t('Add at least one camera point first') : undefined}
          >
            {t('Preview')}
          </Button>
        </div>
        <p className="nz-creator__help">{t('Walk to the spot and aim the camera first (Esc to walk around), then add the point. The current camera position, angle and zoom are saved.')}</p>
      </div>
    </div>
  );
}
