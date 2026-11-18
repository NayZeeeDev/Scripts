import { Lock, Plus, Star, Trash2, Play, Ban } from 'lucide-react';
import { useStore, useChar } from '../../lib/store';
import { post } from '../../lib/nui';
import { cue } from '../../lib/audio';
import { t } from '../../i18n';
import { cx, SectionHead } from '../../components/ui';
import { moneyCompact, relTime, two } from '../../lib/format';
import type { CharacterNui } from '../../lib/types';

type Row = { slot: number; kind: 'char'; c: CharacterNui } | { slot: number; kind: 'empty' } | { slot: number; kind: 'locked' };

export function useRows(): Row[] {
  const lobby = useStore((s) => s.lobby);
  if (!lobby) return [];
  const { total, shown, max } = lobby.slots;
  const bySlot = new Map(lobby.characters.map((c) => [c.slot, c]));
  const maxChar = lobby.characters.reduce((m, c) => Math.max(m, c.slot), 0);
  const n = Math.max(shown || Math.min(total + 1, max || total + 1), maxChar);
  const rows: Row[] = [];
  for (let i = 1; i <= n; i++) {
    const c = bySlot.get(i);
    if (c) rows.push({ slot: i, kind: 'char', c });
    else if (i <= total) rows.push({ slot: i, kind: 'empty' });
    else rows.push({ slot: i, kind: 'locked' });
  }
  return rows;
}

function Header() {
  const c = useChar();
  const selected = useStore((s) => s.selected);
  return (
    <div className="flex gap-[6px] h-[112px]">
      <div className="relative flex-1 accent-block cut overflow-hidden" style={{ ['--cut' as string]: '18px' }}>
        {/* play mark (MW4 Quick Play) */}
        <div className="absolute left-0 top-0 bottom-0 w-[54px] grid place-items-center">
          <Play size={26} className="text-white/90 fill-white/85 drop-shadow" />
        </div>
        <div className="absolute left-[54px] top-[14px] bottom-[14px] w-px bg-white/25" />
        <div className="absolute left-[72px] right-4 top-[15px]">
          <div className="micro text-[9px] text-black/55 font-semibold">{t('slot_n', two(selected))} · {c ? (c.job?.label || t('unemployed')) : t('open_slot')}</div>
          <div key={c?.id || selected} className="display text-[44px] leading-[.95] mt-[6px] text-white truncate drop-shadow-[0_1px_1px_rgba(0,0,0,.25)] a-fade">
            {c ? c.name : t('create_character')}
          </div>
          <div className="micro text-[10px] text-white/75 mt-[5px] truncate">
            {c ? <>{c.job?.gradeLabel || '—'}<span className="text-black/40 mx-2">//</span>{t('last_played')} {relTime(c.lastPlayed)}</> : t('open_slot_desc')}
          </div>
        </div>
      </div>
      <div className="glass w-[74px] grid place-items-center text-center">
        <div>
          <div className="display text-[40px] text-fg leading-none">{two(selected)}</div>
          <div className="micro text-[8px] mt-1 text-fg-3">{t('slot')}</div>
        </div>
      </div>
    </div>
  );
}

function Stats() {
  const c = useChar();
  if (!c) return null;
  const cells: [string, string, string?][] = [
    [t('age'), c.age != null ? String(c.age) : '—'],
    [t('nationality'), c.nationality || '—'],
    [t('cash'), moneyCompact(c.cash), 'text-ok'],
    [t('bank'), moneyCompact(c.bank), 'text-accent-hi'],
  ];
  return (
    <div key={c.id} className="glass-dark grid grid-cols-[60px_1.4fr_1fr_1fr] mt-[6px] a-fade">
      {cells.map(([k, v, cls], i) => (
        <div key={k} className={cx('px-3 py-[9px] min-w-0', i > 0 && 'border-l border-white/[.06]')}>
          <div className="micro text-[8px] text-fg-3">{k}</div>
          <div className={cx('display text-[19px] mt-[3px] truncate', cls || 'text-fg')}>{v}</div>
        </div>
      ))}
    </div>
  );
}

function CharRow({ c, active }: { c: CharacterNui; active: boolean }) {
  const selectSlot = useStore((s) => s.selectSlot);
  const setModal = useStore((s) => s.setModal);
  const canDelete = useStore((s) => s.lobby?.canDelete);
  const patch = useStore((s) => s.patchCharacter);
  const toast = useStore((s) => s.toast);
  const dim = c.disabled || c.locked;

  const fav = async () => {
    cue('tick');
    patch(c.slot, { favorite: !c.favorite });
    const r = await post<{ ok: boolean; msg?: string }>('setPref', { slot: c.slot, key: 'favorite', value: !c.favorite });
    if (r && r.ok === false) { patch(c.slot, { favorite: c.favorite }); if (r.msg) toast('error', r.msg); }
  };

  return (
    <div
      onMouseEnter={() => cue('hover')}
      onClick={() => selectSlot(c.slot)}
      className={cx(
        'group relative h-[62px] flex items-center gap-3 pl-3 pr-3 cursor-pointer lift border overflow-hidden',
        active
          ? 'border-accent/50 bg-gradient-to-r from-accent/[.22] via-accent/[.08] to-transparent shadow-[inset_0_1px_0_rgba(255,255,255,.06)]'
          : 'border-white/[.05] bg-black/40 hover:bg-white/[.05] hover:border-white/10',
      )}
    >
      {active && <span className="absolute left-0 top-0 bottom-0 w-[3px] bg-accent shadow-[0_0_12px_rgb(var(--accent))]" />}
      <div className={cx('w-[40px] h-[40px] grid place-items-center shrink-0 cut cut-sm display text-[17px]',
        active ? 'bg-accent/25 text-white' : 'bg-white/[.06] text-fg-2')}>
        {dim ? (c.locked ? <Lock size={16} /> : <Ban size={16} />) : two(c.slot)}
      </div>
      <div className={cx('flex-1 min-w-0', dim && 'opacity-50')}>
        <div className="flex items-center gap-2">
          <span className={cx('display text-[21px] truncate', active ? 'text-white' : 'text-fg')}>{c.name}</span>
          {c.favorite && <Star size={12} className="text-warn fill-warn shrink-0" />}
          {c.disabled && <span className="micro text-[8px] px-[5px] py-[2px] bg-bad/20 text-bad">{t('disabled')}</span>}
        </div>
        <div className="micro text-[9px] text-fg-3 mt-[3px] truncate">
          {c.job?.label || t('unemployed')}<span className="mx-[6px] text-fg-4">·</span>{relTime(c.lastPlayed)}
        </div>
      </div>
      <div className="text-right group-hover:opacity-0 transition-opacity duration-150">
        <div className="micro text-[8px] text-fg-4">{t('bank')}</div>
        <div className="display text-[18px] text-fg-2">{moneyCompact(c.bank)}</div>
      </div>
      <div className="absolute right-2 top-1/2 -translate-y-1/2 flex gap-1 opacity-0 group-hover:opacity-100 translate-x-2 group-hover:translate-x-0 transition-all duration-200">
        <button title={c.favorite ? t('unfavorite') : t('favorite')} onClick={(e) => { e.stopPropagation(); fav(); }}
          className={cx('w-[30px] h-[30px] grid place-items-center rounded-[4px] bg-black/50 hover:bg-white/10', c.favorite ? 'text-warn' : 'text-fg-2')}>
          <Star size={14} className={c.favorite ? 'fill-warn' : ''} />
        </button>
        {canDelete && (
          <button title={t('delete_character')} onClick={(e) => { e.stopPropagation(); cue('click'); setModal({ kind: 'delete', slot: c.slot }); }}
            className="w-[30px] h-[30px] grid place-items-center rounded-[4px] bg-black/50 text-fg-2 hover:text-bad hover:bg-bad/15">
            <Trash2 size={14} />
          </button>
        )}
      </div>
    </div>
  );
}

function EmptyRow({ slot, active }: { slot: number; active: boolean }) {
  const create = () => { cue('confirm'); post('sound', { name: 'select' }); post('createStart', { slot }); };
  return (
    <div onMouseEnter={() => cue('hover')} onClick={create}
      className={cx('group relative h-[62px] flex items-center gap-3 pl-3 pr-4 cursor-pointer lift border border-dashed',
        active ? 'border-accent/60 bg-accent/10' : 'border-white/[.12] bg-black/25 hover:border-accent/50 hover:bg-accent/[.06]')}>
      <div className="w-[40px] h-[40px] grid place-items-center shrink-0 rounded-full border border-white/15 text-fg-2 group-hover:text-accent-hi group-hover:border-accent/60 transition-colors">
        <Plus size={18} />
      </div>
      <div className="flex-1 min-w-0">
        <div className="display text-[21px] text-fg group-hover:text-white">{t('create_character')}</div>
        <div className="micro text-[9px] text-fg-3 mt-[3px]"><span className="text-warn">●</span> {t('open_slot')} · {t('slot_n', two(slot))}</div>
      </div>
      <span className="kbd opacity-0 group-hover:opacity-100 transition-opacity">↵</span>
    </div>
  );
}

function LockedRow({ slot }: { slot: number }) {
  return (
    <div className="relative h-[54px] flex items-center gap-3 pl-3 pr-4 border border-white/[.04] bg-black/30 opacity-60">
      <div className="w-[40px] h-[40px] grid place-items-center shrink-0 text-fg-3"><Lock size={16} /></div>
      <div className="flex-1 min-w-0">
        <div className="display text-[19px] text-fg-3">{t('locked_slot')}</div>
        <div className="micro text-[9px] text-fg-4 mt-[2px]">{t('unlock_more')} · {t('slot_n', two(slot))}</div>
      </div>
    </div>
  );
}

export default function Characters() {
  const rows = useRows();
  const selected = useStore((s) => s.selected);
  const slots = useStore((s) => s.lobby?.slots);
  return (
    <div className="flex flex-col min-h-0 h-full a-left">
      <Header />
      <Stats />
      <SectionHead className="mt-6" code="CHAR_SELECT_C01" title={t('characters')} right={`${two(slots?.used ?? 0)}/${two(slots?.total ?? 0)}`} />
      <div className="mt-3 flex flex-col gap-[5px] scrolly min-h-0 pr-[2px] -mr-[6px]">
        {rows.map((r) =>
          r.kind === 'char' ? <CharRow key={r.slot} c={r.c} active={r.slot === selected} />
            : r.kind === 'empty' ? <EmptyRow key={r.slot} slot={r.slot} active={r.slot === selected} />
              : <LockedRow key={r.slot} slot={r.slot} />,
        )}
      </div>
    </div>
  );
}
