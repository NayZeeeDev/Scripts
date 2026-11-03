/**
 * Upgrades & paint tab: performance upgrades with level pips (+ model performance when the
 * client knows the model), real colour swatches from the GTA palette, lights, wheels, glass,
 * plate, livery, extras and the changed body parts. Editing happens in the PropsEditor.
 */
import { Bar, Button, EmptyState, Icon, Tooltip, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import { useSettings } from '@/lib/store';
import type { AdminVehicleDetail } from '@/lib/types';
import { CATEGORIES, describe, extrasMap, isRgb, isSet, neonList, rgbToHex } from '../props/catalog';
import type { FieldDef, Props as VProps } from '../props/catalog';
import { PERF_MODS, bool, installedModCount, num, perfModValue } from '../util';
import { XENON_HEX, speedLabel, swatchOf, tintLook } from './data';
import { ColourChip, Fact, Heading, LevelPips } from './parts';

interface Props {
  detail: AdminVehicleDetail;
  props: VProps;
  onEdit: (category?: string) => void;
  onViewAll: () => void;
}

const field = (cat: string, key: string): FieldDef | null => CATEGORIES.find((c) => c.id === cat)?.fields.find((f) => f.key === key) ?? null;
const text = (cat: string, key: string, props: VProps) => {
  const f = field(cat, key);
  return f ? describe(f, props) : '—';
};

/** Tiny top-down outline (nose right) with the neon sides lit. */
function NeonGlyph({ sides, hex }: { sides: [boolean, boolean, boolean, boolean]; hex: string }) {
  const lit = (on: boolean) => (on ? { stroke: hex, filter: `drop-shadow(0 0 3px ${hex})` } : undefined);
  return (
    <svg viewBox="0 0 64 34" className="nz-dos-neon" aria-hidden="true">
      <rect x={8} y={7} width={48} height={20} rx={7} className="nz-dos-neon__body" />
      <line x1={14} y1={3.5} x2={50} y2={3.5} className={cx('nz-dos-neon__side', sides[0] && 'is-on')} style={lit(sides[0])} />
      <line x1={14} y1={30.5} x2={50} y2={30.5} className={cx('nz-dos-neon__side', sides[1] && 'is-on')} style={lit(sides[1])} />
      <line x1={60.5} y1={11} x2={60.5} y2={23} className={cx('nz-dos-neon__side', sides[2] && 'is-on')} style={lit(sides[2])} />
      <line x1={3.5} y1={11} x2={3.5} y2={23} className={cx('nz-dos-neon__side', sides[3] && 'is-on')} style={lit(sides[3])} />
    </svg>
  );
}

export function UpgradesTab({ detail, props, onEdit, onViewAll }: Props) {
  const unit = useSettings().distanceUnit;
  const v = detail.vehicle;
  const empty = Object.keys(props).length === 0;
  const installed = installedModCount(props);

  if (empty) {
    return (
      <div className="nz-dos-pane nz-dos-pane--center">
        <EmptyState
          icon="sliders"
          title={t('No saved modifications')}
          description={t('This vehicle has no stored properties yet. They are saved the first time it is stored in a garage, or you can set them now.')}
          action={
            <Button size="sm" variant="teal" icon="edit" onClick={() => onEdit()}>
              {t('Edit modifications')}
            </Button>
          }
        />
      </div>
    );
  }

  const perf = PERF_MODS.map((m) => ({ m, val: perfModValue(m, props) }));
  const perfCount = perf.filter((p) => p.val.on).length;

  const paints: { key: string; label: string; fallback: number }[] = [
    { key: 'color1', label: t('Primary'), fallback: 0 },
    { key: 'color2', label: t('Secondary'), fallback: 0 },
    { key: 'pearlescentColor', label: t('Pearlescent'), fallback: 0 },
    { key: 'wheelColor', label: t('Wheels'), fallback: 156 },
    { key: 'interiorColor', label: t('Interior'), fallback: 0 },
    { key: 'dashboardColor', label: t('Dashboard'), fallback: 0 },
  ];

  const xenonOn = bool(props.modXenon);
  const xenonIdx = num(props.xenonColor, 255);
  const neon = neonList(props.neonEnabled);
  const neonHex = isRgb(props.neonColor) ? rgbToHex(props.neonColor) : '#ff00ff';
  const smokeOn = bool(props.modSmokeEnabled);
  const smokeHex = isRgb(props.tyreSmokeColor) ? rgbToHex(props.tyreSmokeColor) : '#ffffff';
  const tint = num(props.windowTint, -1);
  const tintGlass = tintLook(tint);

  const extras = Object.entries(extrasMap(props.extras));
  const cosmetics = CATEGORIES.find((c) => c.id === 'cosmetics')?.fields.filter((f) => isSet(f, props)) ?? [];
  const SHOWN = 8;

  return (
    <div className="nz-dos-pane">
      <div className="nz-dos-sheet nz-dos-up">
        <section className="nz-dos-col">
          <Heading count={`${perfCount}/${perf.length}`}>{t('Performance')}</Heading>
          <div className="nz-dos-perf">
            {perf.map(({ m, val }) => (
              <button type="button" key={m.key} className={cx('nz-dos-perf__row', val.on && 'is-on')} onClick={() => onEdit('performance')}>
                <span className="nz-dos-perf__label">{m.label()}</span>
                {m.max > 0 ? (
                  <LevelPips levels={m.max} level={val.level} />
                ) : (
                  <span className={cx('nz-dos-switch', val.on && 'is-on')} aria-hidden="true">
                    <i />
                  </span>
                )}
                <b>{val.text}</b>
              </button>
            ))}
          </div>

          {v.stats ? (
            <>
              <Heading className="nz-dos-h--gap">{t('Model performance')}</Heading>
              <div className="nz-dos-model">
                <div className="nz-dos-model__top">
                  <span>{t('Top speed')}</span>
                  <b>{speedLabel(v.stats.topSpeed, unit)}</b>
                  <em>{v.stats.seats === 1 ? t('1 seat') : t('{n} seats', { n: v.stats.seats })}</em>
                </div>
                {(
                  [
                    ['speed', t('Speed')],
                    ['acceleration', t('Acceleration')],
                    ['braking', t('Braking')],
                    ['traction', t('Traction')],
                  ] as const
                ).map(([k, label]) => {
                  const val = Math.max(0, Math.min(100, Math.round(v.stats?.[k] ?? 0)));
                  return (
                    <div key={k} className="nz-dos-model__bar">
                      <span>{label}</span>
                      <Bar value={val} height={4} tone="teal" />
                      <b>{val}</b>
                    </div>
                  );
                })}
              </div>
            </>
          ) : (
            <p className="nz-dos-note">
              <Icon name="info" size={13} strokeWidth={1.7} />
              {t('Model performance is unavailable for this model.')}
            </p>
          )}
        </section>

        <section className="nz-dos-col">
          <Heading>{t('Paint')}</Heading>
          <div className="nz-dos-paint">
            {paints.map((p) => {
              const sw = swatchOf(props[p.key], p.fallback);
              return (
                <button type="button" key={p.key} className="nz-dos-paint__item" onClick={() => onEdit('colours')}>
                  <ColourChip hex={sw.hex} size={30} />
                  <span className="nz-dos-paint__text">
                    <span>
                      {p.label}
                      <em>{sw.code}</em>
                    </span>
                    <b className="nz-aveh-ellipsis" title={sw.name}>
                      {sw.name}
                    </b>
                  </span>
                </button>
              );
            })}
          </div>

          <Heading className="nz-dos-h--gap">{t('Lights')}</Heading>
          <div className="nz-dos-lights">
            <div className={cx('nz-dos-light', !xenonOn && 'is-off')}>
              <ColourChip hex={xenonOn ? XENON_HEX[xenonIdx] ?? XENON_HEX[255] : null} size={22} glow={xenonOn} className={cx(!xenonOn && 'is-off')} />
              <span>
                <small>{t('Xenon headlights')}</small>
                <b>{xenonOn ? text('lights', 'xenonColor', props) : t('Off')}</b>
              </span>
            </div>
            <div className={cx('nz-dos-light', !neon.some(Boolean) && 'is-off')}>
              <NeonGlyph sides={neon} hex={neonHex} />
              <span>
                <small>{t('Neon')}</small>
                <b>{neon.some(Boolean) ? `${text('lights', 'neonEnabled', props)} · ${neonHex.toUpperCase()}` : t('Off')}</b>
              </span>
            </div>
            <div className={cx('nz-dos-light', !smokeOn && 'is-off')}>
              <ColourChip hex={smokeOn ? smokeHex : null} size={22} className={cx('is-smoke', !smokeOn && 'is-off')} />
              <span>
                <small>{t('Tyre smoke')}</small>
                <b>{smokeOn ? smokeHex.toUpperCase() : t('Off')}</b>
              </span>
            </div>
          </div>
        </section>

        <section className="nz-dos-col">
          <Heading
            count={installed}
            actions={
              <Button size="sm" variant="ghost" iconRight="arrowRight" onClick={onViewAll}>
                {t('All')}
              </Button>
            }
          >
            {t('Body and wheels')}
          </Heading>
          <div className="nz-dos-facts">
            <Fact label={t('Wheels')} icon="wheel">
              {text('wheels', 'wheels', props)}
              {num(props.modFrontWheels) >= 0 && <span className="nz-dos-fact__sub"> · {text('wheels', 'modFrontWheels', props)}</span>}
            </Fact>
            <Fact label={t('Custom tyres')} icon="wheel" tone={bool(props.modCustomTiresF) ? undefined : 'muted'}>
              {bool(props.modCustomTiresF) ? t('On') : t('Off')}
            </Fact>
            <Fact label={t('Window tint')} icon="eye" tone={tint < 0 || tint === 0 ? 'muted' : undefined}>
              <span className="nz-dos-glass" style={{ backgroundColor: `rgba(${tintGlass.rgb},${tintGlass.alpha})` }} aria-hidden="true" />
              {text('liveries', 'windowTint', props)}
            </Fact>
            <Fact label={t('Plate style')} icon="tag">
              {text('liveries', 'plateIndex', props)}
            </Fact>
            <Fact label={t('Livery')} icon="layers" tone={num(props.livery) < 0 && num(props.modLivery) < 0 ? 'muted' : undefined}>
              {num(props.modLivery) >= 0 ? text('liveries', 'modLivery', props) : text('liveries', 'livery', props)}
            </Fact>
          </div>

          <span className="nz-dos-sublabel">{t('Extras')}</span>
          <div className="nz-dos-tags">
            {extras.length === 0 ? (
              <span className="nz-dos-tags__none">{t('No extras saved')}</span>
            ) : (
              extras.map(([id, on]) => (
                <span key={id} className={cx('nz-dos-tag', on && 'is-on')}>
                  {t('Extra {n}', { n: id })}
                  <i>{on ? t('on') : t('off')}</i>
                </span>
              ))
            )}
          </div>

          <span className="nz-dos-sublabel">{t('Body kit')}</span>
          <div className="nz-dos-tags">
            {cosmetics.length === 0 ? (
              <span className="nz-dos-tags__none">{t('Stock body')}</span>
            ) : (
              <>
                {cosmetics.slice(0, SHOWN).map((f) => (
                  <Tooltip key={f.key} content={describe(f, props)}>
                    <span className="nz-dos-tag is-kit">{f.label()}</span>
                  </Tooltip>
                ))}
                {cosmetics.length > SHOWN && (
                  <button type="button" className="nz-dos-tag is-more" onClick={onViewAll}>
                    {t('+{n} more', { n: cosmetics.length - SHOWN })}
                  </button>
                )}
              </>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
