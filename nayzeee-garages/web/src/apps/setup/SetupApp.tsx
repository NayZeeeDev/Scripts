/**
 * Vehicle setup (app 'setup', takes focus): wide panel at the bottom middle, shown after a
 * job / spawner vehicle spawns. Tile grid in the owner's "Vehicle Controls" manner: liveries
 * (numbered swatch, live preview), extras (on / off tiles) and camera presets, with the
 * vehicle's facts on the left (plate, plate template, performance mods). Then Drive.
 *
 * While it is open Lua orbits a scripted camera round the frozen vehicle: drag the empty
 * screen (or A / D, W / S), scroll (or Q / E) to zoom, R resets. Arrow keys only move the
 * focus over the tiles (so every section is reachable without changing the livery); Enter /
 * Space use the focused tile. Enter with no tile focused drives, Escape drives too.
 */
import { useEffect, useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent, ReactNode, WheelEvent as ReactWheelEvent } from 'react';
import { closeApp, useApp, useUi } from '@/lib/store';
import { request } from '@/lib/nui';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import type { SetupMod, SetupModId, SetupView } from '@/lib/types';
import { Badge, Bar, Button, Icon, KeyHint, PlateTag, Window, cx } from '@/components/ui';
import { HOLD_CODES, useOrbitInput } from './camera';
import { ARROWS, nextTile } from './nav';
import type { Dir } from './nav';
import { LiverySwatch, MiniSwitch, ViewGlyph } from './glyphs';
import './setup.css';

const isTyping = (el: EventTarget | null) => {
  const node = el as HTMLElement | null;
  if (!node || !node.tagName) return false;
  return node.tagName === 'INPUT' || node.tagName === 'TEXTAREA';
};

const VIEWS: SetupView[] = ['reset', 'front', 'side', 'rear', 'top'];
const viewLabel = (v: SetupView) =>
  v === 'reset' ? t('Reset') : v === 'front' ? t('Front') : v === 'side' ? t('Side') : v === 'rear' ? t('Rear') : t('Top');

const MOD_ORDER: SetupModId[] = ['engine', 'brakes', 'transmission', 'suspension', 'armour', 'turbo'];
const modLabel = (id: SetupModId) =>
  id === 'engine'
    ? t('Engine')
    : id === 'brakes'
      ? t('Brakes')
      : id === 'transmission'
        ? t('Gearbox')
        : id === 'suspension'
          ? t('Suspension')
          : id === 'armour'
            ? t('Armour')
            : t('Turbo');

/** Columns of a tile group: two rows when it fits, at most `max` columns (then it scrolls). */
const columns = (count: number, max: number) => Math.max(1, Math.min(max, Math.ceil(count / 2)));

const GRID_GAP = 8; // px, .nz-setup__grid gap
const GRID_PAD = 6; // px, .nz-setup__grid padding (both sides, room for the focus ring)
const GRID_BAR = 8; // px, the kit's scrollbar (base.css ::-webkit-scrollbar)

/**
 * Explicit grid size: the fixed tracks plus, when the group has more than two rows, room for
 * the scrollbar. A CEF draws real scrollbars that take their width from the box: without
 * the gutter the last column would be clipped and a horizontal bar would appear.
 */
function gridStyle(cols: number, count: number, track: string) {
  const scroll = count > cols * 2;
  const extra = (cols - 1) * GRID_GAP + GRID_PAD + (scroll ? GRID_BAR : 0);
  return {
    scroll,
    style: { gridTemplateColumns: `repeat(${cols}, ${track})`, width: `calc(${cols} * ${track} + ${extra}px)` },
  };
}

/** Wide screens (1600 px and up) get more columns per group; 1280 still fits every group. */
function useWide() {
  const [wide, setWide] = useState(() => window.innerWidth >= 1600);
  useEffect(() => {
    const onResize = () => setWide(window.innerWidth >= 1600);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return wide;
}

export function SetupApp() {
  const { open, data, update } = useApp('setup');
  const [driving, setDriving] = useState(false);
  const [view, setView] = useState<SetupView | null>('reset');
  const [cameraUsed, setCameraUsed] = useState(false);
  const [missing, setMissing] = useState<number[]>([]);
  const [dragging, setDragging] = useState(false);
  const [tileFocus, setTileFocus] = useState(false);
  const liverySeq = useRef(0);
  const tilesRef = useRef<HTMLDivElement>(null);
  const drag = useRef<{ id: number; x: number; y: number } | null>(null);
  const wide = useWide();

  const liveries = data?.liveries ?? [];
  const extras = data?.extras ?? [];
  const mods = Array.isArray(data?.mods) ? data.mods : [];
  // A single livery cannot be changed: no point in showing the section.
  const hasLiveries = liveries.length > 1;
  const hasExtras = extras.length > 0;
  const camera = open && data?.camera === true;
  const cameraLive = camera && !driving;

  const orbit = useOrbitInput(cameraLive, () => {
    setView(null);
    setCameraUsed(true);
  });

  useEffect(() => {
    if (!open) return;
    setDriving(false);
    setView('reset');
    setCameraUsed(false);
    setMissing([]);
    setDragging(false);
    setTileFocus(false);
    drag.current = null;
    // Only on open: later data updates (extras sync) must not reset the menu.
  }, [open]);

  const drive = async () => {
    if (driving) return;
    orbit.releaseAll();
    setDriving(true);
    const res = await request('setup:drive', {});
    if (res.ok) useUi.getState().hideApp('setup');
    // Lua's close handler finishes the setup too: never leave the player stuck with focus.
    else closeApp('setup');
  };

  useEscape(() => void drive(), open);

  // Tell Lua where the menu's top edge is, so the camera frames the vehicle above it (the
  // panel covers far more of a 720p screen than of a 1080p one). After the open animation.
  useEffect(() => {
    if (!cameraLive) return;
    let timer = 0;
    const send = () => {
      const el = document.querySelector<HTMLElement>('.nz-window.nz-setup');
      if (!el || window.innerHeight <= 0) return;
      orbit.frame(el.getBoundingClientRect().top / window.innerHeight);
    };
    timer = window.setTimeout(send, 320);
    const onResize = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(send, 150);
    };
    window.addEventListener('resize', onResize);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener('resize', onResize);
    };
    // orbit is rebuilt each render; its `enabled` is cameraLive, the only dependency.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cameraLive]);

  // Keep the livery in use visible (on open and while browsing) without moving the focus.
  useEffect(() => {
    if (!open) return;
    const grid = tilesRef.current?.querySelector<HTMLElement>('.nz-setup__grid--fill');
    const item = grid?.querySelector<HTMLElement>('[aria-checked="true"]');
    if (!grid || !item) return;
    const top = item.offsetTop - grid.offsetTop;
    const bottom = top + item.offsetHeight;
    if (top < grid.scrollTop) grid.scrollTop = Math.max(0, top - 3);
    else if (bottom > grid.scrollTop + grid.clientHeight) grid.scrollTop = bottom - grid.clientHeight + 3;
  }, [open, data?.livery]);

  const pickLivery = async (index: number) => {
    const current = useUi.getState().apps.setup.data;
    if (!current || driving || index === current.livery) return;
    const prev = current.livery;
    update({ livery: index });
    const seq = ++liverySeq.current;
    const res = await request('setup:livery', { index });
    if (!res.ok) {
      setMissing((m) => (m.includes(index) ? m : [...m, index]));
      if (seq === liverySeq.current) update({ livery: prev });
    }
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

  const applyView = (v: SetupView) => {
    if (!cameraLive) return;
    setView(v);
    orbit.view(v);
  };

  /** Arrow keys: move the focus over the tiles. Nothing is applied: Enter / Space does that. */
  const moveFocus = (dir: Dir) => {
    const root = tilesRef.current;
    if (!root) return;
    const tiles = Array.from(root.querySelectorAll<HTMLElement>('[data-nav]:not(:disabled)'));
    if (tiles.length === 0) return;
    const focused = document.activeElement as HTMLElement | null;
    const checked = root.querySelector<HTMLElement>('[data-nav="livery"][aria-checked="true"]:not(:disabled)');
    if (!focused || !tiles.includes(focused)) {
      (checked ?? tiles[0]).focus();
      return;
    }
    let target = nextTile(tiles, focused, dir);
    if (!target) return;
    const from = focused.dataset.nav;
    // Entering the livery group lands on the livery in use (radio group convention).
    if (target.dataset.nav === 'livery' && from !== 'livery' && checked) target = checked;
    target.focus();
    target.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  };

  // Keyboard: camera keys (held), R reset view, arrows walk the tiles, Enter drives.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: KeyboardEvent) => {
      if (isTyping(e.target) || e.ctrlKey || e.altKey || e.metaKey) return;
      const current = useUi.getState().apps.setup.data;
      if (!current) return;
      const hold = HOLD_CODES[e.code];
      if (hold) {
        e.preventDefault();
        if (!e.repeat) orbit.press(hold, true);
        return;
      }
      if (e.code === 'KeyR') {
        e.preventDefault();
        if (!e.repeat) applyView('reset');
        return;
      }
      const dir = ARROWS[e.key];
      if (dir) {
        e.preventDefault();
        moveFocus(dir);
        return;
      }
      if (e.key === 'Enter') {
        const tag = (e.target as HTMLElement | null)?.tagName;
        if (tag === 'BUTTON') return; // a focused tile / button handles Enter itself
        e.preventDefault();
        void drive();
      }
    };
    const onUp = (e: KeyboardEvent) => {
      const hold = HOLD_CODES[e.code];
      if (hold) orbit.press(hold, false);
    };
    window.addEventListener('keydown', onDown);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onDown);
      window.removeEventListener('keyup', onUp);
    };
  });

  // Drag the empty screen to orbit, wheel to zoom.
  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!cameraLive || (e.button !== 0 && e.button !== 2)) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = { id: e.pointerId, x: e.clientX, y: e.clientY };
    setDragging(true);
  };
  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || d.id !== e.pointerId) return;
    const dx = e.clientX - d.x;
    const dy = e.clientY - d.y;
    d.x = e.clientX;
    d.y = e.clientY;
    orbit.drag(dx, dy);
  };
  const endDrag = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!drag.current || drag.current.id !== e.pointerId) return;
    drag.current = null;
    setDragging(false);
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
  };
  const onWheel = (e: ReactWheelEvent<HTMLDivElement>) => {
    if (!cameraLive || e.deltaY === 0) return;
    orbit.zoom(e.deltaY > 0 ? 1 : -1);
  };

  if (!open || !data) return null;

  const activePos = liveries.findIndex((l) => l.index === data.livery);
  const activeLivery = activePos >= 0 ? liveries[activePos] : null;
  const extrasOn = extras.filter((e) => e.enabled).length;
  const sortedMods = MOD_ORDER.map((id) => mods.find((m) => m.id === id)).filter((m): m is SetupMod => !!m);
  const template = typeof data.plateTemplate === 'string' ? data.plateTemplate : null;

  // Liveries: up to 4 columns (5 on wide screens) in two rows. Below 1600 px a scrolling
  // group keeps 3 columns, so the scrollbar gutter never pushes the row past the window.
  let liveryCols = Math.max(2, columns(liveries.length, wide ? 5 : 4));
  if (!wide && liveries.length > liveryCols * 2) liveryCols = 3;
  const liveryGrid = gridStyle(liveryCols, liveries.length, 'var(--nz-setup-livery)');
  const extraCols = Math.min(extras.length, Math.max(2, columns(extras.length, wide ? 4 : 3)));
  const extraGrid = gridStyle(Math.max(1, extraCols), extras.length, 'var(--nz-setup-tile)');
  const viewGrid = gridStyle(3, VIEWS.length, 'var(--nz-setup-tile)');

  return (
    <>
      {camera && (
        <div
          className={cx('nz-setup-stage', dragging && 'is-dragging', driving && 'is-idle')}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={endDrag}
          onPointerCancel={endDrag}
          onLostPointerCapture={endDrag}
          onWheel={onWheel}
          onContextMenu={(e) => e.preventDefault()}
          aria-hidden="true"
        >
          <div className={cx('nz-setup-hint', (cameraUsed || driving) && 'is-gone')}>
            <Icon name="camera" size={14} strokeWidth={1.8} />
            <span>{t('Drag to look around the vehicle')}</span>
            <i />
            <span>{t('Scroll to zoom')}</span>
          </div>
        </div>
      )}

      <Window
        className={cx('nz-setup', wide && 'nz-setup--wide')}
        bodyClassName="nz-setup__body"
        width="fit-content"
        title={t('Vehicle setup')}
        subtitle={data.garage || undefined}
        onClose={() => void drive()}
        headerExtra={
          <div className="nz-setup__head-extra">
            <Button variant="teal" size="sm" iconRight="arrowRight" loading={driving} onClick={() => void drive()}>
              {t('Drive')}
            </Button>
          </div>
        }
        footer={
          <div className="nz-setup__keys">
            <KeyHint keys={['ArrowLeft', 'ArrowUp', 'ArrowRight', 'ArrowDown']} label={t('Select')} />
            {tileFocus ? (
              <>
                <KeyHint keys={['Enter']} label={t('Apply')} />
                <KeyHint keys={['Esc']} label={t('Drive')} />
              </>
            ) : (
              <KeyHint keys={['Esc', 'Enter']} label={t('Drive')} />
            )}
            {camera && (
              <>
                <KeyHint keys={['A', 'D', 'W', 'S']} label={t('Orbit')} />
                <KeyHint keys={['Q', 'E']} label={t('Zoom')} />
                <KeyHint keys={['Scroll']} label={t('Zoom')} />
                <KeyHint keys={['R']} label={t('Reset view')} />
              </>
            )}
          </div>
        }
      >
        <aside className="nz-setup__info">
          <div className="nz-setup__veh">
            <span className="nz-setup__veh-icon">
              <Icon name="car" size={18} strokeWidth={1.7} />
            </span>
            <div className="nz-setup__veh-text">
              <b title={data.label}>{data.label || t('Vehicle')}</b>
              {data.model && <small>{data.model}</small>}
            </div>
          </div>

          <dl className="nz-setup__facts">
            {data.plate && (
              <div>
                <dt>{t('Plate')}</dt>
                <dd>
                  <PlateTag plate={data.plate} size="sm" />
                </dd>
              </div>
            )}
            {template !== null && (
              <div>
                <dt>{t('Template')}</dt>
                <dd>{template ? <code className="nz-setup__template">{template}</code> : <span className="nz-setup__muted">{t('Random')}</span>}</dd>
              </div>
            )}
          </dl>

          {sortedMods.length > 0 && (
            <div className="nz-setup__perf">
              <div className="nz-setup__perf-head">
                <span>{t('Performance')}</span>
                {data.maxMods ? (
                  <Badge tone="teal" size="sm" icon="gauge">
                    {t('Max mods')}
                  </Badge>
                ) : (
                  <Badge tone="neutral" size="sm">
                    {t('As spawned')}
                  </Badge>
                )}
              </div>
              <div className="nz-setup__mods">
                {sortedMods.map((m) => {
                  const full = m.max > 0 && m.level >= m.max;
                  return (
                    <div key={m.id} className={cx('nz-setup__mod', full && 'is-full', m.level <= 0 && 'is-stock')}>
                      <span>{modLabel(m.id)}</span>
                      <b>{m.id === 'turbo' ? (m.level > 0 ? t('On') : t('Off')) : m.level > 0 ? `${m.level}/${m.max}` : t('Stock')}</b>
                      <Bar value={m.level} max={Math.max(1, m.max)} height={2} />
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </aside>

        <div
          className="nz-setup__tiles"
          ref={tilesRef}
          onFocus={(e) => setTileFocus(e.target instanceof HTMLElement && !!e.target.dataset.nav)}
          onBlur={(e) => {
            const next = e.relatedTarget as HTMLElement | null;
            if (!next || !e.currentTarget.contains(next)) setTileFocus(false);
          }}
        >
          {hasLiveries && (
            <TileSection
              className="nz-setup__sec--liveries"
              title={t('Liveries')}
              icon="palette"
              meta={
                <>
                  {activeLivery && <em title={activeLivery.label}>{activeLivery.label}</em>}
                  <span className="nz-setup__count">
                    {activePos + 1 > 0 ? activePos + 1 : '–'}/{liveries.length}
                  </span>
                </>
              }
            >
              <div
                className={cx('nz-setup__grid nz-setup__grid--fill', liveryGrid.scroll && 'is-scroll')}
                style={liveryGrid.style}
                role="radiogroup"
                aria-label={t('Liveries')}
              >
                {liveries.map((l, i) => {
                  const on = l.index === data.livery;
                  const gone = missing.includes(l.index) && !on;
                  return (
                    <Tile
                      key={l.index}
                      nav="livery"
                      index={l.index}
                      role="radio"
                      checked={on}
                      tabIndex={on ? 0 : -1}
                      active={on}
                      disabled={driving || gone}
                      tag={gone ? t('Missing') : on ? t('On') : undefined}
                      tagTone={gone ? 'warn' : 'teal'}
                      label={l.label}
                      onClick={() => void pickLivery(l.index)}
                    >
                      <LiverySwatch index={l.index} position={i} />
                    </Tile>
                  );
                })}
              </div>
            </TileSection>
          )}

          {hasExtras && (
            <TileSection
              title={t('Extras')}
              icon="layers"
              meta={<span className="nz-setup__count">{t('{on} of {count} on', { on: extrasOn, count: extras.length })}</span>}
            >
              <div className={cx('nz-setup__grid', extraGrid.scroll && 'is-scroll')} style={extraGrid.style}>
                {extras.map((x) => (
                  <Tile
                    key={x.id}
                    nav="extra"
                    role="switch"
                    checked={x.enabled}
                    active={x.enabled}
                    disabled={driving}
                    tag={x.enabled ? t('On') : t('Off')}
                    tagTone={x.enabled ? 'teal' : 'muted'}
                    label={t('Extra {id}', { id: x.id })}
                    onClick={() => void toggleExtra(x.id, !x.enabled)}
                  >
                    <MiniSwitch on={x.enabled} />
                  </Tile>
                ))}
              </div>
            </TileSection>
          )}

          <TileSection
            title={t('Camera')}
            icon="camera"
            meta={<span className="nz-setup__count">{camera ? t('Orbit') : t('Unavailable')}</span>}
          >
            <div className="nz-setup__grid" style={viewGrid.style}>
              {VIEWS.map((v) => (
                <Tile
                  key={v}
                  nav="view"
                  pressed={cameraLive ? view === v : undefined}
                  active={cameraLive && view === v}
                  disabled={!cameraLive}
                  tag={v === 'side' ? t('Driver') : undefined}
                  label={viewLabel(v)}
                  onClick={() => applyView(v)}
                >
                  <ViewGlyph view={v} />
                </Tile>
              ))}
            </div>
          </TileSection>

          {!hasLiveries && !hasExtras && <p className="nz-setup__none">{t('Nothing to set up on this vehicle.')}</p>}
        </div>
      </Window>
    </>
  );
}

/* ── local pieces ─────────────────────────────────────────────────────── */

function TileSection({
  title,
  icon,
  meta,
  className,
  children,
}: {
  title: string;
  icon: 'palette' | 'layers' | 'camera';
  meta?: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <section className={cx('nz-setup__sec', className)}>
      <header className="nz-setup__sec-head">
        <h4>
          <Icon name={icon} size={12} strokeWidth={2} />
          {title}
        </h4>
        {meta && <div className="nz-setup__sec-meta">{meta}</div>}
      </header>
      {children}
    </section>
  );
}

interface TileProps {
  nav: 'livery' | 'extra' | 'view';
  label: string;
  active: boolean;
  disabled?: boolean;
  tag?: string;
  tagTone?: 'teal' | 'muted' | 'warn';
  role?: 'radio' | 'switch';
  checked?: boolean;
  pressed?: boolean;
  index?: number;
  tabIndex?: number;
  onClick: () => void;
  children: ReactNode;
}

function Tile({ nav, label, active, disabled, tag, tagTone = 'teal', role, checked, pressed, index, tabIndex, onClick, children }: TileProps) {
  return (
    <button
      type="button"
      className={cx('nz-setup__tile', active && 'is-on')}
      data-nav={nav}
      data-index={index}
      role={role}
      aria-checked={role ? checked === true : undefined}
      aria-pressed={pressed}
      aria-label={label}
      title={label}
      tabIndex={tabIndex}
      disabled={disabled}
      onClick={onClick}
    >
      {tag && <span className={cx('nz-setup__tag', `is-${tagTone}`)}>{tag}</span>}
      <span className="nz-setup__glyph">{children}</span>
      <span className="nz-setup__label">{label}</span>
    </button>
  );
}
