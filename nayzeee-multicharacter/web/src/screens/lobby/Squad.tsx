import { useEffect, useRef, useState, type ReactNode } from 'react';
import { ArrowLeftRight, Check, Eye, EyeOff, Heart, Search, Trash2, UserPlus, Users, X, Inbox } from 'lucide-react';
import { useStore, useChar } from '../../lib/store';
import { post } from '../../lib/nui';
import { cue } from '../../lib/audio';
import { t } from '../../i18n';
import { relTime } from '../../lib/format';
import { Avatar, Btn, cx, Dot, Micro, Segmented, SectionHead } from '../../components/ui';
import type { LinkType, SquadLink } from '../../lib/types';

export type SquadTab = 'linked' | 'requests' | 'find';

type Reply = { ok?: boolean; msg?: string } | null;
function handle(r: Reply, okMsg?: string) {
  const st = useStore.getState();
  if (!r || r.ok === false) { cue('error'); if (r?.msg) st.toast('error', r.msg); return false; }
  if (r.msg || okMsg) st.toast('success', r.msg || okMsg!);
  return true;
}

function TypeBadge({ type }: { type: LinkType }) {
  return type === 'couple' ? (
    <span className="inline-flex items-center gap-1 micro text-[8px] px-[6px] py-[3px] bg-love/15 text-love border border-love/30"><Heart size={9} className="fill-love" />{t('type_couple')}</span>
  ) : (
    <span className="inline-flex items-center gap-1 micro text-[8px] px-[6px] py-[3px] bg-white/[.06] text-fg-2 border border-white/10"><Users size={9} />{t('type_squad')}</span>
  );
}

function LinkCard({ l }: { l: SquadLink }) {
  const cfg = useStore((s) => s.cfg)!;
  const setModal = useStore((s) => s.setModal);
  const squad = useStore((s) => s.squad);
  const set = (patch: Partial<SquadLink>) => useStore.setState({ squad: { ...squad, links: squad.links.map((x) => (x.id === l.id ? { ...x, ...patch } : x)) } });
  const other: LinkType = l.type === 'couple' ? 'squad' : 'couple';
  const hasCouple = squad.links.some((x) => x.type === 'couple' && x.id !== l.id);
  const canSwitch = cfg.squad?.couples !== false && !(other === 'couple' && hasCouple);
  const max = Math.min(4, 1 + (cfg.squad?.maxLinks ?? 3));
  const positions = Array.from({ length: max - 1 }, (_, i) => i + 2);

  return (
    <div className="glass-dark px-4 py-3">
      <div className="flex items-center gap-3">
        <div className="relative">
          <Avatar name={l.other.name} size={40} ring={l.type === 'couple' ? 'love' : null} />
          <span className="absolute -bottom-[1px] -right-[1px] p-[2px] rounded-full bg-ink"><Dot online={l.other.online} /></span>
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="display text-[20px] text-fg truncate">{l.other.name}</span>
            <TypeBadge type={l.type} />
          </div>
          <div className="micro text-[9px] text-fg-3 mt-[3px] truncate">
            {l.other.online ? <span className="text-ok">{t('online')}</span> : t('offline')}
            {l.other.job?.label && <><span className="mx-[6px] text-fg-4">·</span>{l.other.job.label}</>}
          </div>
        </div>
        <button title={l.visible ? t('visible') : t('hidden')}
          onMouseEnter={() => cue('hover')}
          onClick={async () => { cue('tick'); const v = !l.visible; set({ visible: v }); const r = await post<Reply>('squadVisible', { id: l.id, visible: v }); if (r && r.ok === false) set({ visible: !v }); }}
          className={cx('w-[32px] h-[32px] grid place-items-center rounded-[4px] transition-colors', l.visible ? 'text-fg-2 hover:bg-white/10' : 'text-fg-4 bg-white/[.04] hover:text-fg-2')}>
          {l.visible ? <Eye size={16} /> : <EyeOff size={16} />}
        </button>
        <button title={t('remove')} onMouseEnter={() => cue('hover')} onClick={() => { cue('click'); setModal({ kind: 'removeLink', id: l.id, name: l.other.name }); }}
          className="w-[32px] h-[32px] grid place-items-center rounded-[4px] text-fg-3 hover:text-bad hover:bg-bad/10 transition-colors">
          <Trash2 size={15} />
        </button>
      </div>
      <div className="flex items-center gap-3 mt-3">
        <Micro className="text-[8px] w-[56px]">{t('position')}</Micro>
        {l.type === 'couple' ? (
          <span className="micro text-[10px] text-fg-2 px-2 h-[26px] grid place-items-center border border-white/10">P2</span>
        ) : (
          <div className="flex gap-[3px]">
            {positions.map((p) => (
              <button key={p} onMouseEnter={() => cue('hover')}
                onClick={async () => { if (p === l.slot) return; cue('tick'); set({ slot: p }); const r = await post<Reply>('squadSlot', { id: l.id, slot: p }); if (r && r.ok === false) set({ slot: l.slot }); }}
                className={cx('w-[30px] h-[26px] micro text-[10px] border transition-colors',
                  p === l.slot ? 'border-accent/60 bg-accent/20 text-white' : 'border-white/10 text-fg-3 hover:text-fg hover:border-white/25')}>
                P{p}
              </button>
            ))}
          </div>
        )}
        <span className="flex-1" />
        {l.pendingType ? (
          <span className="micro text-[8px] px-2 h-[26px] inline-flex items-center gap-[6px] text-warn border border-warn/30 bg-warn/10">
            <ArrowLeftRight size={11} />{l.pendingByMe ? t('switch_waiting', l.other.name.split(' ')[0]) : t('switch_pending')}
          </span>
        ) : canSwitch ? (
          <Btn small variant="line" onClick={async () => handle(await post<Reply>('squadSwitch', { id: l.id, type: other }))}>
            <ArrowLeftRight size={12} />{t('switch_to', other === 'couple' ? t('type_couple') : t('type_squad'))}
          </Btn>
        ) : null}
      </div>
    </div>
  );
}

function Empty({ icon, title, desc }: { icon: ReactNode; title: string; desc?: string }) {
  return (
    <div className="flex flex-col items-center text-center py-10 px-6">
      <div className="w-[56px] h-[56px] rounded-full grid place-items-center bg-white/[.04] border border-white/[.06] text-fg-3">{icon}</div>
      <div className="display text-[20px] text-fg-2 mt-4">{title}</div>
      {desc && <div className="text-[13px] text-fg-3 mt-2 leading-snug max-w-[300px]">{desc}</div>}
    </div>
  );
}

function Requests() {
  const squad = useStore((s) => s.squad);
  const switches = squad.links.filter((l) => l.pendingType && !l.pendingByMe);
  const none = !squad.incoming.length && !squad.outgoing.length && !switches.length;
  if (none) return <Empty icon={<Inbox size={22} />} title={t('no_requests')} />;
  const respond = async (id: number, accept: boolean) => { cue(accept ? 'confirm' : 'back'); handle(await post<Reply>('squadRespond', { id, accept })); };
  return (
    <div className="flex flex-col gap-5">
      {(squad.incoming.length > 0 || switches.length > 0) && (
        <div>
          <SectionHead title={t('incoming')} right={squad.incoming.length + switches.length} />
          <div className="flex flex-col gap-[5px] mt-3">
            {squad.incoming.map((r) => (
              <div key={r.id} className="glass-dark flex items-center gap-3 px-3 py-[10px]">
                <Avatar name={r.from?.name || '?'} size={34} ring={r.type === 'couple' ? 'love' : 'accent'} />
                <div className="flex-1 min-w-0">
                  <div className="display text-[18px] text-fg truncate">{r.from?.name}</div>
                  <div className="flex items-center gap-2 mt-[3px]"><TypeBadge type={r.type} /><span className="micro text-[8px] text-fg-4">{relTime(r.at)}</span></div>
                </div>
                <button title={t('decline')} onClick={() => respond(r.id, false)} className="w-[32px] h-[32px] grid place-items-center rounded-[4px] bg-white/[.05] text-fg-2 hover:text-bad hover:bg-bad/10"><X size={16} /></button>
                <button title={t('accept')} onClick={() => respond(r.id, true)} className="w-[32px] h-[32px] grid place-items-center rounded-[4px] bg-accent text-black hover:bg-accent-hi"><Check size={16} strokeWidth={3} /></button>
              </div>
            ))}
            {switches.map((l) => (
              <div key={`s${l.id}`} className="glass-dark flex items-center gap-3 px-3 py-[10px]">
                <Avatar name={l.other.name} size={34} ring={l.pendingType === 'couple' ? 'love' : 'accent'} />
                <div className="flex-1 min-w-0">
                  <div className="display text-[18px] text-fg truncate">{l.other.name}</div>
                  <div className="micro text-[8px] text-warn mt-[3px] flex items-center gap-1"><ArrowLeftRight size={10} />{t('wants_switch', l.pendingType === 'couple' ? t('type_couple') : t('type_squad'))}</div>
                </div>
                <button title={t('decline')} onClick={() => respond(l.id, false)} className="w-[32px] h-[32px] grid place-items-center rounded-[4px] bg-white/[.05] text-fg-2 hover:text-bad hover:bg-bad/10"><X size={16} /></button>
                <button title={t('accept')} onClick={() => respond(l.id, true)} className="w-[32px] h-[32px] grid place-items-center rounded-[4px] bg-accent text-black hover:bg-accent-hi"><Check size={16} strokeWidth={3} /></button>
              </div>
            ))}
          </div>
        </div>
      )}
      {squad.outgoing.length > 0 && (
        <div>
          <SectionHead title={t('outgoing')} right={squad.outgoing.length} />
          <div className="flex flex-col gap-[5px] mt-3">
            {squad.outgoing.map((r) => (
              <div key={r.id} className="glass-dark flex items-center gap-3 px-3 py-[10px]">
                <Avatar name={r.to?.name || '?'} size={34} />
                <div className="flex-1 min-w-0">
                  <div className="display text-[18px] text-fg-2 truncate">{r.to?.name}</div>
                  <div className="flex items-center gap-2 mt-[3px]"><TypeBadge type={r.type} /><span className="micro text-[8px] text-fg-4">{relTime(r.at)}</span></div>
                </div>
                <Btn small variant="ghost" onClick={async () => handle(await post<Reply>('squadRemove', { id: r.id }))}>{t('cancel')}</Btn>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function Find() {
  const cfg = useStore((s) => s.cfg)!;
  const squad = useStore((s) => s.squad);
  const [q, setQ] = useState('');
  const [res, setRes] = useState<{ id: string; name: string; online?: boolean }[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState<Record<string, boolean>>({});
  const min = cfg.squad?.searchMin ?? 3;
  const full = squad.links.length >= (cfg.squad?.maxLinks ?? 3);
  const hasCouple = squad.links.some((l) => l.type === 'couple');
  const inputRef = useRef<HTMLInputElement>(null);
  const seq = useRef(0);

  useEffect(() => { inputRef.current?.focus(); }, []);
  useEffect(() => {
    const query = q.trim();
    if (query.length < min) { setRes(null); setLoading(false); return; }
    setLoading(true);
    const id = ++seq.current;
    const h = window.setTimeout(async () => {
      const r = await post<{ results?: { id: string; name: string; online?: boolean }[] }>('squadSearch', { query });
      if (id !== seq.current) return;
      setRes(r?.results || []);
      setLoading(false);
    }, 380);
    return () => window.clearTimeout(h);
  }, [q, min]);

  const request = async (target: string, type: LinkType) => {
    cue('click');
    if (handle(await post<Reply>('squadRequest', { target, type }))) setSent((s) => ({ ...s, [target]: true }));
  };

  return (
    <div>
      <div className="relative">
        <Search size={16} className="absolute left-[14px] top-1/2 -translate-y-1/2 text-fg-3" />
        <input ref={inputRef} className="field !pl-[40px]" placeholder={t('search_ph')} value={q} onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Escape') (e.target as HTMLInputElement).blur(); }} />
        {loading && <span className="absolute right-[14px] top-1/2 -translate-y-1/2 w-[14px] h-[14px] rounded-full border-2 border-white/15 border-t-accent a-spin" />}
      </div>
      <div className="micro text-[8px] text-fg-4 mt-2">
        {q.trim().length < min ? t('search_min', min) : full ? t('squad_full') : t('links_count', squad.links.length, cfg.squad?.maxLinks ?? 3)}
      </div>
      <div className="flex flex-col gap-[5px] mt-4">
        {res && res.length === 0 && !loading && <Empty icon={<Search size={20} />} title={t('search_none')} />}
        {res?.map((r) => (
          <div key={r.id} className="glass-dark flex items-center gap-3 px-3 py-[10px] a-fade">
            <div className="relative">
              <Avatar name={r.name} size={34} />
              <span className="absolute -bottom-[1px] -right-[1px] p-[2px] rounded-full bg-ink"><Dot online={!!r.online} /></span>
            </div>
            <div className="flex-1 min-w-0">
              <div className="display text-[18px] text-fg truncate">{r.name}</div>
              <div className="micro text-[8px] text-fg-4 mt-[2px] truncate">#{r.id}</div>
            </div>
            {sent[r.id] ? (
              <span className="micro text-[9px] text-accent-hi flex items-center gap-1"><Check size={12} />{t('requested')}</span>
            ) : (
              <div className="flex gap-[5px]">
                <Btn small variant="ghost" disabled={full} onClick={() => request(r.id, 'squad')}><Users size={12} />{t('as_squad')}</Btn>
                {cfg.squad?.couples !== false && (
                  <Btn small variant="ghost" disabled={full || hasCouple} onClick={() => request(r.id, 'couple')} className="hover:!text-love">
                    <Heart size={12} />{t('as_partner')}
                  </Btn>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

export default function Squad({ tab, setTab }: { tab: SquadTab; setTab: (t: SquadTab) => void }) {
  const cfg = useStore((s) => s.cfg)!;
  const squad = useStore((s) => s.squad);
  const char = useChar();
  const reqs = squad.incoming.length + squad.links.filter((l) => l.pendingType && !l.pendingByMe).length;
  const links = [...squad.links].sort((a, b) => a.slot - b.slot);

  return (
    <div className="flex flex-col h-full min-h-0 a-left">
      <div>
        <Micro className="text-[9px] text-accent-hi/70">SQUAD_LINK_C04</Micro>
        <div className="display text-[44px] text-fg mt-1">{t('squad_title')}</div>
        <div className="micro text-[10px] text-fg-3 mt-1">{char?.name} · {t('links_count', squad.links.length, cfg.squad?.maxLinks ?? 3)}</div>
      </div>
      <Segmented className="mt-5" value={tab} onChange={(v) => { cue('tick'); setTab(v); }} items={[
        { id: 'linked', label: <span>{t('tab_linked')} <span className="text-fg-4 ml-1">{squad.links.length}</span></span> },
        { id: 'requests', label: <span className="inline-flex items-center gap-2">{t('tab_requests')}{reqs > 0 && <span className="min-w-[16px] h-[16px] px-1 rounded-full bg-accent text-black text-[9px] font-mono font-bold grid place-items-center">{reqs}</span>}</span> },
        { id: 'find', label: <span className="inline-flex items-center gap-2"><UserPlus size={13} />{t('tab_find')}</span> },
      ]} />
      <div className="flex-1 min-h-0 scrolly mt-4 pr-[2px] -mr-[6px]">
        {tab === 'linked' && (links.length === 0
          ? <Empty icon={<Users size={22} />} title={t('no_links')} desc={t('no_links_desc')} />
          : <div className="flex flex-col gap-[6px]">{links.map((l) => <LinkCard key={l.id} l={l} />)}</div>)}
        {tab === 'requests' && <Requests />}
        {tab === 'find' && <Find />}
      </div>
    </div>
  );
}
