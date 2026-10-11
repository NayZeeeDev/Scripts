import React, { useState } from 'react';
import { useAppDispatch, useAppSelector } from '../../store';
import {
  closeSettings,
  commitDraft,
  restoreDraft,
  selectConfig,
  Settings,
  updateDraft,
} from '../../store/ui';
import { T } from '../../store/strings';
import { Locale } from '../../store/locale';
import { useEscapeClose } from '../../hooks/useEscapeClose';
import {
  BrandMark,
  IconBell,
  IconClose,
  IconContrast,
  IconExpand,
  IconGear,
  IconGrid,
  IconHexagon,
  IconInfo,
  IconPalette,
  IconRestore,
  IconSave,
  IconSliders,
  IconType,
} from './Icons';

type Tab = 'general' | 'theme' | 'info';

interface Option<V> {
  value: V;
  label: string;
}

const Row: React.FC<{ icon: React.ReactNode; title: string; desc: string; children: React.ReactNode }> = ({
  icon,
  title,
  desc,
  children,
}) => (
  <div className="nz-set-row">
    <div className="nz-set-icon">{icon}</div>
    <div className="nz-set-text">
      <p>{title}</p>
      <span>{desc}</span>
    </div>
    <div className="nz-set-control">{children}</div>
  </div>
);

function Segmented<K extends keyof Settings>({
  field,
  options,
  value,
  onChange,
}: {
  field: K;
  options: Option<Settings[K]>[];
  value: Settings[K];
  onChange: (patch: Partial<Settings>) => void;
}) {
  return (
    <div className="nz-segmented">
      {options.map((o) => (
        <button
          key={String(o.value)}
          data-active={o.value === value || undefined}
          onClick={() => onChange({ [field]: o.value } as Partial<Settings>)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

const SettingsModal: React.FC = () => {
  const dispatch = useAppDispatch();
  const open = useAppSelector((state) => state.ui.settingsOpen);
  const draft = useAppSelector((state) => state.ui.draft);
  const saved = useAppSelector((state) => state.ui.settings);
  const config = useAppSelector(selectConfig);
  const [tab, setTab] = useState<Tab>('general');

  useEscapeClose(open, () => dispatch(closeSettings()));

  if (!open || !draft) return null;

  const set = (patch: Partial<Settings>) => dispatch(updateDraft(patch));
  const dirty = JSON.stringify(draft) !== JSON.stringify(saved);
  const customActive = !config.colors.some((c) => c.toLowerCase() === draft.accent.toLowerCase());

  return (
    <div className="nz-modal-backdrop" onMouseDown={() => dispatch(closeSettings())}>
      <div className="nz-settings" onMouseDown={(e) => e.stopPropagation()}>
        <div className="nz-banner">
          <div className="nz-banner-bg">{draft.brand ? config.brandName : 'SETTINGS'}</div>
          <div className="nz-banner-plus">+</div>
          <div className="nz-banner-logo">
            {draft.brand && config.brandLogo ? <img src={config.brandLogo} alt="" /> : <BrandMark size="9vh" />}
            <div>
              <h1>
                {draft.brand ? config.brandName : T.settings}
                {draft.brand && <sup>®</sup>}
              </h1>
              {draft.brand && config.brandTagline && <span>{config.brandTagline}</span>}
            </div>
          </div>
          <button className="nz-icon-btn nz-banner-close" onClick={() => dispatch(closeSettings())}>
            <IconClose />
          </button>
        </div>

        <div className="nz-tabs">
          <button data-active={tab === 'general' || undefined} onClick={() => setTab('general')}>
            <IconGear /> {T.general}
          </button>
          <button data-active={tab === 'theme' || undefined} onClick={() => setTab('theme')}>
            <IconPalette /> {T.theme}
          </button>
          <button data-active={tab === 'info' || undefined} onClick={() => setTab('info')}>
            <IconInfo /> {T.info}
          </button>
        </div>

        <div className="nz-section-title">
          <div className="nz-square-icon">{tab === 'general' ? <IconGear /> : tab === 'theme' ? <IconPalette /> : <IconInfo />}</div>
          <p>{tab === 'general' ? T.general : tab === 'theme' ? T.theme : T.info}</p>
        </div>

        <div className="nz-settings-body">
          {tab === 'general' && (
            <>
              <Row icon={<IconSliders />} title={T.inventory_type} desc={T.inventory_type_desc}>
                <Segmented
                  field="layout"
                  value={draft.layout}
                  onChange={set}
                  options={[
                    { value: 'default', label: T.default },
                    { value: 'perspective', label: T.perspective },
                  ]}
                />
              </Row>
              <Row icon={<IconExpand />} title={T.view_mode} desc={T.view_mode_desc}>
                <Segmented
                  field="view"
                  value={draft.view}
                  onChange={set}
                  options={[
                    { value: 'fullscreen', label: T.fullscreen },
                    { value: 'compact', label: T.compact },
                  ]}
                />
              </Row>
              <Row icon={<IconType />} title={T.style_source} desc={T.style_source_desc}>
                <Segmented
                  field="font"
                  value={draft.font}
                  onChange={set}
                  options={[
                    { value: 'default', label: T.default },
                    { value: 'roboto', label: 'Roboto' },
                    { value: 'manrope', label: 'Manrope' },
                    { value: 'montserrat', label: 'Montserrat' },
                    { value: 'inter', label: 'Inter' },
                  ]}
                />
              </Row>
              <Row icon={<IconInfo />} title={T.server_brand} desc={T.server_brand_desc}>
                <Segmented
                  field="brand"
                  value={draft.brand}
                  onChange={set}
                  options={[
                    { value: true, label: T.active },
                    { value: false, label: T.disable },
                  ]}
                />
              </Row>
            </>
          )}

          {tab === 'theme' && (
            <>
              <Row icon={<IconPalette />} title={T.theme_color} desc={T.theme_color_desc}>
                <div className="nz-swatches">
                  <label className="nz-swatch nz-swatch-custom" data-active={customActive || undefined}>
                    <IconContrast />
                    <input type="color" value={draft.accent} onChange={(e) => set({ accent: e.target.value })} />
                  </label>
                  {config.colors.map((color) => (
                    <button
                      key={color}
                      className="nz-swatch"
                      style={{ background: color }}
                      data-active={color.toLowerCase() === draft.accent.toLowerCase() || undefined}
                      onClick={() => set({ accent: color })}
                    />
                  ))}
                </div>
              </Row>
              <Row icon={<IconContrast />} title={T.bg_opacity} desc={T.bg_opacity_desc}>
                <div className="nz-range">
                  <input
                    type="range"
                    min={0}
                    max={100}
                    value={draft.opacity}
                    style={{ '--fill': `${draft.opacity}%` } as React.CSSProperties}
                    onChange={(e) => set({ opacity: Number(e.target.value) })}
                  />
                  <b>{draft.opacity}%</b>
                </div>
              </Row>
              <Row icon={<IconGrid />} title={T.fast_slot} desc={T.fast_slot_desc}>
                <Segmented
                  field="hotbarStyle"
                  value={draft.hotbarStyle}
                  onChange={set}
                  options={[
                    { value: 'normal', label: T.normal },
                    { value: 'hexagon', label: T.hexagons },
                  ]}
                />
              </Row>
              <Row icon={<IconBell />} title={T.notify_style} desc={T.notify_style_desc}>
                <Segmented
                  field="notifyStyle"
                  value={draft.notifyStyle}
                  onChange={set}
                  options={[
                    { value: 'default', label: T.default },
                    { value: 'modern', label: T.modern },
                  ]}
                />
              </Row>
              <Row icon={<IconHexagon />} title={T.slot_shape} desc={T.slot_shape_desc}>
                <Segmented
                  field="slotShape"
                  value={draft.slotShape}
                  onChange={set}
                  options={[
                    { value: 'square', label: T.square },
                    { value: 'hexagon', label: T.hexagon },
                  ]}
                />
              </Row>
            </>
          )}

          {tab === 'info' && (
            <div className="nz-info">
              <div className="nz-info-card">
                <p>{T.info_title}</p>
                <span>{T.info_text}</span>
              </div>
              <div className="nz-info-card">
                <p>{T.controls}</p>
                <div className="nz-keys">
                  <kbd>RMB</kbd>
                  <span>{Locale.ui_rmb || 'Open item context menu'}</span>
                  <kbd>ALT + LMB</kbd>
                  <span>{Locale.ui_alt_lmb || 'Fast use an item'}</span>
                  <kbd>CTRL + LMB</kbd>
                  <span>{Locale.ui_ctrl_lmb || 'Fast move a stack'}</span>
                  <kbd>SHIFT + Drag</kbd>
                  <span>{Locale.ui_shift_drag || 'Split item quantity into half'}</span>
                  <kbd>CTRL + SHIFT + LMB</kbd>
                  <span>{Locale.ui_ctrl_shift_lmb || 'Fast move half a stack'}</span>
                </div>
              </div>
            </div>
          )}
        </div>

        <div className="nz-settings-footer">
          <button className="nz-btn" onClick={() => dispatch(restoreDraft())}>
            <IconRestore /> {T.restore}
          </button>
          <button
            className="nz-btn is-primary"
            disabled={!dirty}
            onClick={() => {
              dispatch(commitDraft());
              dispatch(closeSettings());
            }}
          >
            <IconSave /> {T.save}
          </button>
        </div>
      </div>
    </div>
  );
};

export default SettingsModal;
