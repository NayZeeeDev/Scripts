import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Ban, Check, Heart, PawPrint, Sparkles, X } from 'lucide-react';
import { useStore, useChar } from '../../lib/store';
import { post } from '../../lib/nui';
import { cue } from '../../lib/audio';
import { Icon } from '../../lib/icons';
import { t } from '../../i18n';
import { Btn, cx, IconBtn, Micro, Panel, Segmented } from '../../components/ui';
import { savePref } from './Themes';
import type { Prefs } from '../../lib/types';

type Key = 'pose' | 'couplePose' | 'weapon' | 'pet';
type Tab = 'pose' | 'couple' | 'weapon' | 'pet';

function PickCard({ icon, label, sub, tag, active, onHover, onClick }: {
  icon: ReactNode; label: string; sub?: string; tag?: string; active: boolean; onHover: () => void; onClick: () => void;
}) {
  return (
    <button
      onMouseEnter={() => { cue('hover'); onHover(); }}
      onFocus={onHover}
      onClick={onClick}
      className={cx(
        'group relative h-[100px] flex flex-col items-center justify-center gap-2 px-2 cut cut-sm lift text-center',
        active
          ? 'bg-gradient-to-b from-accent/25 to-accent/[.06] accent-glow'
          : 'bg-white/[.035] ring-1 ring-white/[.06] hover:bg-white/[.07] hover:ring-white/20',
      )}
    >
      <span className={cx('grid place-items-center w-[42px] h-[42px] rounded-full transition-colors',
        active ? 'text-white bg-accent/30' : 'text-fg-2 bg-white/[.05] group-hover:text-fg')}>
        {icon}
      </span>
      <span className={cx('label text-[12px] leading-tight tracking-[.08em]', active ? 'text-white' : 'text-fg-2 group-hover:text-fg')}>{label}</span>
      {sub && <span className="micro text-[8px] text-fg-3 -mt-1">{sub}</span>}
      {tag && <span className="absolute left-[6px] top-[6px] micro text-[7px] px-[4px] py-[1px] bg-white/10 text-fg-2">{tag}</span>}
      {active && <Check size={13} className="absolute right-[7px] top-[7px] text-accent-hi" strokeWidth={3} />}
    </button>
  );
}

function WeaponRow({ label, sub, tag, active, icon, onHover, onClick }: {
  label: string; sub?: string; tag?: string; active: boolean; icon: ReactNode; onHover: () => void; onClick: () => void;
}) {
  return (
    <button
      onMouseEnter={() => { cue('hover'); onHover(); }}
      onClick={onClick}
      className={cx('group relative h-[56px] w-full flex items-center gap-3 px-3 text-left lift border',
        active ? 'border-accent/50 bg-gradient-to-r from-accent/20 to-transparent' : 'border-white/[.05] bg-white/[.03] hover:bg-white/[.06]')}
    >
      {active && <span className="absolute left-0 top-0 bottom-0 w-[3px] bg-accent" />}
      <span className={cx('w-[36px] h-[36px] grid place-items-center shrink-0', active ? 'text-accent-hi' : 'text-fg-3')}>{icon}</span>
      <span className="flex-1 min-w-0">
        <span className={cx('display text-[19px] block truncate', active ? 'text-white' : 'text-fg')}>{label}</span>
        {sub && <span className="micro text-[8px] text-fg-3 block mt-[2px] truncate">{sub}</span>}
      </span>
      {tag && <span className="micro text-[8px] px-[6px] py-[3px] border border-white/15 text-fg-2">{tag}</span>}
      {active && <Check size={15} className="text-accent-hi" strokeWidth={3} />}
    </button>
  );
}

export default function Customize({ onClose }: { onClose: () => void }) {
  const cfg = useStore((s) => s.cfg)!;
  const char = useChar();
  const slot = useStore((s) => s.selected);
  const squad = useStore((s) => s.squad);
  const patch = useStore((s) => s.patchCharacter);
  const partner = squad.links.find((l) => l.type === 'couple' && l.visible);
  const prefs: Prefs = char?.prefs || {};

  const tabs = useMemo(() => {
    const tb: { id: Tab; label: string }[] = [{ id: 'pose', label: t('tab_pose') }];
    if (cfg.squad?.couples !== false && partner && cfg.couplePoses?.length) tb.push({ id: 'couple', label: t('tab_couple') });
    if (cfg.weapon?.enabled !== false) tb.push({ id: 'weapon', label: t('tab_weapon') });
    if (cfg.pets?.length) tb.push({ id: 'pet', label: t('tab_pet') });
    return tb;
  }, [cfg, partner]);
  const [tab, setTab] = useState<Tab>('pose');
  const [cat, setCat] = useState('all');
  const [petName, setPetName] = useState(prefs.petName || '');
  useEffect(() => setPetName(char?.prefs?.petName || ''), [char?.id]);
  useEffect(() => { if (!tabs.find((x) => x.id === tab)) setTab('pose'); }, [tabs, tab]);

  const saved = (k: Key): string => {
    const v = prefs[k];
    if (k === 'weapon') return v || (cfg.weapon?.allowAuto !== false ? 'auto' : 'none');
    if (k === 'couplePose' || k === 'pet') return v || 'none';
    return v || '';
  };

  // ── live preview (debounced) + revert ─────────────────────────────────
  const previewed = useRef(new Map<Key, string>());
  const timer = useRef<number>();
  const savedRef = useRef(saved);
  savedRef.current = saved;

  const preview = (k: Key, value: string) => {
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      if (previewed.current.get(k) === value) return;
      if (!previewed.current.has(k) && value === savedRef.current(k)) return;
      previewed.current.set(k, value);
      post('previewPref', { slot, key: k, value });
    }, 180);
  };
  const revert = (k?: Key) => {
    window.clearTimeout(timer.current);
    for (const key of [...previewed.current.keys()]) {
      if (k && key !== k) continue;
      const back = savedRef.current(key);
      if (previewed.current.get(key) !== back) post('previewPref', { slot, key, value: back });
      previewed.current.delete(key);
    }
  };
  useEffect(() => () => revert(), [slot]);

  const apply = async (k: Key, value: string) => {
    window.clearTimeout(timer.current);
    if (value === saved(k)) return;
    cue('confirm');
    post('sound', { name: 'select' });
    previewed.current.delete(k);
    const before = char?.prefs;
    patch(slot, { prefs: { ...prefs, [k]: value } });
    const ok = await savePref(slot, k, value);
    if (!ok) patch(slot, { prefs: before });
  };

  if (!char) return null;

  const cats = ['all', ...Array.from(new Set(cfg.poses.map((p) => p.category).filter(Boolean) as string[]))];
  const poses = cfg.poses.filter((p) => cat === 'all' || p.category === cat);
  const ownedPets = cfg.pets.filter((p) => !char.pets || char.pets.includes(p.id));
  const weapons = char.weapons || [];

  return (
    <Panel className="h-full flex flex-col a-right" style={{ ['--cut' as string]: '22px' }}>
      <div className="px-6 pt-5 pb-4">
        <div className="flex items-start justify-between">
          <div>
            <Micro className="text-[9px] text-accent-hi/70">LOADOUT_CFG_C03</Micro>
            <div className="display text-[38px] text-fg mt-1">{t('customize')}</div>
            <div className="micro text-[10px] text-fg-3 mt-[2px] truncate">{char.name}</div>
          </div>
          <IconBtn title={t('close')} onClick={onClose}><X size={18} /></IconBtn>
        </div>
        <Segmented className="mt-4" items={tabs} value={tab} onChange={(v) => { revert(); setTab(v); cue('tick'); }} />
      </div>
      <div className="h-px bg-white/[.06]" />

      <div className="flex-1 min-h-0 scrolly px-6 py-4" onMouseLeave={() => revert()}>
        {tab === 'pose' && (
          <>
            <div className="flex gap-[6px] flex-wrap mb-4">
              {cats.map((c) => (
                <button key={c} onMouseEnter={() => cue('hover')} onClick={() => { cue('tick'); setCat(c); }}
                  className={cx('h-[26px] px-3 label text-[11px] rounded-full border transition-colors',
                    c === cat ? 'border-accent/60 bg-accent/15 text-accent-hi' : 'border-white/10 text-fg-3 hover:text-fg hover:border-white/25')}>
                  {t(`cat_${c}`)}
                </button>
              ))}
            </div>
            <div className="grid grid-cols-3 gap-[7px]">
              {poses.map((p) => (
                <PickCard key={p.id} icon={<Icon name={p.icon} size={20} />} label={p.label} tag={p.prop ? t('prop') : undefined}
                  active={saved('pose') === p.id} onHover={() => preview('pose', p.id)} onClick={() => apply('pose', p.id)} />
              ))}
            </div>
          </>
        )}

        {tab === 'couple' && (
          <>
            <div className="flex items-center gap-2 mb-4 text-[13px] text-fg-2">
              <Heart size={14} className="text-love fill-love" />
              <span className="truncate">{partner?.other.name}</span>
            </div>
            <div className="grid grid-cols-3 gap-[7px]">
              <PickCard icon={<Ban size={20} />} label={t('none')} sub={t('couple_none_desc')} active={saved('couplePose') === 'none'}
                onHover={() => preview('couplePose', 'none')} onClick={() => apply('couplePose', 'none')} />
              {cfg.couplePoses.map((p) => (
                <PickCard key={p.id} icon={<Icon name={p.icon} size={20} fallback={Heart} />} label={p.label}
                  active={saved('couplePose') === p.id} onHover={() => preview('couplePose', p.id)} onClick={() => apply('couplePose', p.id)} />
              ))}
            </div>
          </>
        )}

        {tab === 'weapon' && (
          <div className="flex flex-col gap-[5px]">
            {cfg.weapon?.allowAuto !== false && (
              <WeaponRow icon={<Sparkles size={18} />} label={t('auto')} sub={t('auto_desc')} active={saved('weapon') === 'auto'}
                onHover={() => preview('weapon', 'auto')} onClick={() => apply('weapon', 'auto')} />
            )}
            {cfg.weapon?.allowNone !== false && (
              <WeaponRow icon={<Ban size={18} />} label={t('none')} sub={t('none_weapon_desc')} active={saved('weapon') === 'none'}
                onHover={() => preview('weapon', 'none')} onClick={() => apply('weapon', 'none')} />
            )}
            <div className="divider my-2" />
            {weapons.length === 0 && <div className="text-[13px] text-fg-3 py-4 text-center">{t('no_weapons')}</div>}
            {weapons.map((w) => (
              <WeaponRow key={w.name} icon={<span className="micro text-[9px]">{(w.class || 'wpn').slice(0, 3)}</span>}
                label={w.label} sub={w.name} tag={w.class} active={saved('weapon') === w.name}
                onHover={() => preview('weapon', w.name)} onClick={() => apply('weapon', w.name)} />
            ))}
          </div>
        )}

        {tab === 'pet' && (
          <>
            <div className="grid grid-cols-3 gap-[7px]">
              <PickCard icon={<Ban size={20} />} label={t('none')} active={saved('pet') === 'none'}
                onHover={() => preview('pet', 'none')} onClick={() => apply('pet', 'none')} />
              {ownedPets.map((p) => (
                <PickCard key={p.id} icon={<Icon name={p.icon || p.kind} size={20} fallback={PawPrint} />} label={p.label}
                  sub={p.kind === 'smalldog' ? 'dog' : p.kind} active={saved('pet') === p.id}
                  onHover={() => preview('pet', p.id)} onClick={() => apply('pet', p.id)} />
              ))}
            </div>
            {ownedPets.length === 0 && <div className="text-[13px] text-fg-3 py-4 text-center">{t('no_pets')}</div>}
            {cfg.petNames !== false && saved('pet') !== 'none' && (
              <div className="mt-5">
                <Micro className="text-[9px] mb-2">{t('pet_name')}</Micro>
                <div className="flex gap-2">
                  <input className="field !h-[40px]" maxLength={24} value={petName} placeholder={t('pet_name_ph')}
                    onChange={(e) => setPetName(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }} />
                  <Btn variant="accent" disabled={petName.trim() === (prefs.petName || '')}
                    onClick={async () => { const v = petName.trim(); patch(slot, { prefs: { ...prefs, petName: v } }); await savePref(slot, 'petName', v); }}>
                    {t('save')}
                  </Btn>
                </div>
              </div>
            )}
          </>
        )}
      </div>
      <div className="px-6 py-3 border-t border-white/[.06] micro text-[9px] text-fg-4">{t('preview_hint')}</div>
    </Panel>
  );
}
