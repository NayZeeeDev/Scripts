import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Calendar, ChevronDown, Mars, Search, Venus, X } from 'lucide-react';
import { useStore } from '../lib/store';
import { post } from '../lib/nui';
import { cue } from '../lib/audio';
import { t } from '../i18n';
import { ageFrom, two } from '../lib/format';
import { cx, HoldButton, IconBtn, Kbd, Micro, Panel, Slider } from '../components/ui';
import type { UiConfig } from '../lib/types';

type Errors = Partial<Record<'firstname' | 'lastname' | 'dob' | 'nationality' | 'height' | 'backstory' | 'gender', string>>;

function regOpts(cfg: UiConfig) {
  const r = cfg.registration || ({} as UiConfig['registration']);
  const obj = <T extends object>(v: unknown, d: T): T & { enabled: boolean } =>
    v === false ? { ...d, enabled: false } : v && typeof v === 'object' ? { ...d, enabled: true, ...(v as object) } : { ...d, enabled: v !== undefined ? !!v : true };
  return {
    nameMin: r.nameMin ?? 2, nameMax: r.nameMax ?? 16, minAge: r.minAge ?? 18, maxAge: r.maxAge ?? 90,
    height: obj(r.height, { min: 150, max: 210, default: 175 }),
    nationality: obj(r.nationality, { required: true, default: '' }),
    backstory: { ...obj(r.backstory, { required: false, min: 20, max: 600 }), enabled: r.backstory ? (r.backstory as { enabled: boolean }).enabled !== false : false },
    genders: r.genders?.length ? r.genders : ['m', 'f'],
    blacklist: (r.blacklist || []).map((x) => x.toLowerCase()),
  };
}

const capitalize = (s: string) => s.replace(/(^|[\s\-'])(\p{L})(\p{L}*)/gu, (_, a: string, b: string, c: string) => a + b.toUpperCase() + c.toLowerCase());

function parseDob(v: string): { y: number; m: number; d: number } | null {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(v);
  if (!m) return null;
  const d = +m[1], mo = +m[2], y = +m[3];
  const dt = new Date(y, mo - 1, d);
  if (dt.getFullYear() !== y || dt.getMonth() !== mo - 1 || dt.getDate() !== d) return null;
  return { y, m: mo, d };
}

function maskDob(raw: string): string {
  const d = raw.replace(/\D/g, '').slice(0, 8);
  if (d.length <= 2) return d;
  if (d.length <= 4) return `${d.slice(0, 2)}/${d.slice(2)}`;
  return `${d.slice(0, 2)}/${d.slice(2, 4)}/${d.slice(4)}`;
}

function Field({ label, hint, error, children, className }: { label: string; hint?: string; error?: string; children: ReactNode; className?: string }) {
  return (
    <div className={className}>
      <div className="flex items-baseline justify-between mb-[7px]">
        <span className="label text-[11px] text-fg-2 tracking-[.2em]">{label}</span>
        {hint && <span className="micro text-[8px] text-fg-4">{hint}</span>}
      </div>
      {children}
      <div className={cx('micro text-[9px] text-bad h-[14px] mt-[5px] normal-case tracking-[.04em] transition-opacity', error ? 'opacity-100' : 'opacity-0')}>{error || '·'}</div>
    </div>
  );
}

function NationalityPicker({ value, onChange, list, error }: { value: string; onChange: (v: string) => void; list: string[]; error?: string }) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [hi, setHi] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const inp = useRef<HTMLInputElement>(null);
  const filtered = useMemo(() => { const s = q.trim().toLowerCase(); return s ? list.filter((n) => n.toLowerCase().includes(s)) : list; }, [q, list]);

  useEffect(() => {
    if (!open) return;
    setHi(Math.max(0, filtered.indexOf(value)));
    const off = (e: PointerEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false); };
    window.addEventListener('pointerdown', off);
    return () => window.removeEventListener('pointerdown', off);
  }, [open]);
  useEffect(() => { document.getElementById(`nat-${hi}`)?.scrollIntoView({ block: 'nearest' }); }, [hi]);

  const choose = (n: string) => { cue('tick'); onChange(n); setOpen(false); setQ(''); inp.current?.blur(); };

  return (
    <div ref={ref} className="relative">
      <div className={cx('field flex items-center gap-2 !pr-3 cursor-text', error && 'err', open && '!border-accent/70')} onClick={() => { setOpen(true); inp.current?.focus(); }}>
        {open ? <Search size={15} className="text-fg-3 shrink-0" /> : null}
        <input ref={inp} className="flex-1 bg-transparent min-w-0 h-full" placeholder={open ? t('nationality_search') : value || t('nationality_ph')}
          value={open ? q : value} onFocus={() => setOpen(true)} onChange={(e) => { setQ(e.target.value); setHi(0); }}
          onKeyDown={(e) => {
            if (e.key === 'ArrowDown') { e.preventDefault(); setHi((h) => Math.min(filtered.length - 1, h + 1)); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); setHi((h) => Math.max(0, h - 1)); }
            else if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); if (filtered[hi]) choose(filtered[hi]); }
            else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); setOpen(false); inp.current?.blur(); }
          }} />
        <ChevronDown size={16} className={cx('text-fg-3 transition-transform', open && 'rotate-180')} />
      </div>
      {open && (
        <div className="absolute left-0 right-0 top-[50px] z-30 glass-dark !bg-[#0c0e0f] max-h-[230px] scrolly py-1 a-down shadow-[0_20px_40px_rgba(0,0,0,.6)]"
          style={{ background: 'linear-gradient(180deg,#121517,#0b0c0d)' }}>
          {filtered.length === 0 && <div className="px-4 py-3 text-[13px] text-fg-3">—</div>}
          {filtered.map((n, i) => (
            <div key={n} id={`nat-${i}`} onMouseEnter={() => setHi(i)} onPointerDown={(e) => { e.preventDefault(); choose(n); }}
              className={cx('px-4 h-[34px] flex items-center text-[14px] cursor-pointer', i === hi ? 'bg-accent/15 text-white' : 'text-fg-2', n === value && 'text-accent-hi')}>
              {n}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function GenderCard({ g, active, onClick }: { g: 'm' | 'f'; active: boolean; onClick: () => void }) {
  const IconC = g === 'm' ? Mars : Venus;
  return (
    <button onMouseEnter={() => cue('hover')} onClick={onClick}
      className={cx('group relative h-[150px] overflow-hidden cut text-left lift',
        active ? 'accent-glow' : 'ring-1 ring-white/[.08] hover:ring-white/25')}
      style={{
        ['--cut' as string]: '16px',
        background: active
          ? 'radial-gradient(90% 90% at 80% 70%, rgb(var(--accent) / .35), transparent 70%), linear-gradient(160deg, rgb(var(--accent-lo) / .55), rgba(10,11,12,.9))'
          : 'radial-gradient(90% 90% at 80% 70%, rgba(255,255,255,.08), transparent 70%), linear-gradient(160deg, rgba(30,33,36,.75), rgba(10,11,12,.85))',
      }}>
      <span className="absolute inset-0" style={{ background: 'repeating-linear-gradient(115deg, rgba(255,255,255,.035) 0 1px, transparent 1px 10px)' }} />
      <span className={cx('absolute right-[-14px] bottom-[-22px] transition-all duration-300', active ? 'text-white/80 scale-100' : 'text-white/15 group-hover:text-white/30 scale-95')}>
        <IconC size={150} strokeWidth={1} />
      </span>
      <span className={cx('absolute left-5 top-4 display text-[42px]', active ? 'text-white' : 'outline-text group-hover:text-white/60')}>
        {g === 'm' ? t('gender_m') : t('gender_f')}
      </span>
      <span className={cx('absolute left-5 bottom-4 micro text-[9px]', active ? 'text-white/80' : 'text-fg-4')}>{g === 'm' ? 'MP_M_FREEMODE' : 'MP_F_FREEMODE'}</span>
    </button>
  );
}

export function Steps({ active }: { active: number }) {
  const steps = [t('step_record'), t('step_appearance'), t('step_spawn')];
  return (
    <div className="grid grid-cols-3 glass-dark">
      {steps.map((s, i) => (
        <div key={s} className={cx('flex items-center gap-2 px-4 h-[40px]', i > 0 && 'border-l border-white/[.06]')}>
          <span className={cx('w-[6px] h-[6px] rounded-full', i < active ? 'bg-ok' : i === active ? 'bg-accent shadow-[0_0_8px_rgb(var(--accent))]' : 'bg-fg-4')} />
          <span className={cx('micro text-[9px] flex-1', i === active ? 'text-fg' : 'text-fg-3')}>{s}</span>
          <span className={cx('display text-[17px]', i === active ? 'text-accent-hi' : 'text-fg-4')}>{two(i + 1)}</span>
        </div>
      ))}
    </div>
  );
}

export default function Create() {
  const cfg = useStore((s) => s.cfg)!;
  const slot = useStore((s) => s.createSlot);
  const toast = useStore((s) => s.toast);
  const R = useMemo(() => regOpts(cfg), [cfg]);
  const [f, setF] = useState({
    firstname: '', lastname: '', dob: '', nationality: R.nationality.default || '', height: R.height.default || 175, backstory: '',
    gender: (R.genders[0] === 'f' ? 'f' : 'm') as 'm' | 'f',
  });
  const [errors, setErrors] = useState<Errors>({});
  const [touched, setTouched] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);

  const dob = parseDob(f.dob);
  const age = dob ? ageFrom(dob.y, dob.m, dob.d) : null;

  const validate = (): Errors => {
    const e: Errors = {};
    const nameRe = /^[\p{L}][\p{L}\s'-]*$/u;
    for (const k of ['firstname', 'lastname'] as const) {
      const v = f[k].trim();
      if (!v) e[k] = t('v_required');
      else if (v.length < R.nameMin) e[k] = t('v_min', R.nameMin);
      else if (v.length > R.nameMax) e[k] = t('v_max', R.nameMax);
      else if (!nameRe.test(v)) e[k] = t('v_letters');
      else if (R.blacklist.some((b) => v.toLowerCase().includes(b))) e[k] = t('v_blacklist');
    }
    if (!f.dob) e.dob = t('v_required');
    else if (!dob) e.dob = t('v_date');
    else if (age! < R.minAge) e.dob = t('v_age_min', R.minAge);
    else if (age! > R.maxAge) e.dob = t('v_age_max', R.maxAge);
    if (R.nationality.enabled && R.nationality.required && !cfg.nationalities.includes(f.nationality)) e.nationality = t('v_nationality');
    if (R.height.enabled && (f.height < R.height.min || f.height > R.height.max)) e.height = t('v_height', R.height.min, R.height.max);
    if (R.backstory.enabled) {
      const b = f.backstory.trim();
      if (R.backstory.required && !b) e.backstory = t('v_required');
      else if (b && b.length < (R.backstory.min ?? 0)) e.backstory = t('v_min', R.backstory.min!);
      else if (b.length > (R.backstory.max ?? 600)) e.backstory = t('v_max', R.backstory.max!);
    }
    if (!f.gender) e.gender = t('v_gender');
    return e;
  };
  const live = validate();
  const shown: Errors = {};
  for (const k of Object.keys(live) as (keyof Errors)[]) if (touched[k]) shown[k] = live[k];
  for (const k of Object.keys(errors) as (keyof Errors)[]) shown[k] = errors[k];

  const set = (k: keyof typeof f, v: string | number) => {
    setF((p) => ({ ...p, [k]: v }));
    if (errors[k as keyof Errors]) setErrors((p) => ({ ...p, [k]: undefined }));
  };
  const blur = (k: string) => setTouched((p) => ({ ...p, [k]: true }));

  const pickGender = (g: 'm' | 'f') => {
    if (g === f.gender) return;
    cue('click');
    set('gender', g);
    post('createGender', { gender: g });
  };

  const cancel = () => { cue('back'); post('sound', { name: 'back' }); post('createCancel'); };

  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || e.defaultPrevented) return;
      const el = document.activeElement as HTMLElement | null;
      if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) { el.blur(); return; }
      cancel();
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, []);

  const submit = async () => {
    const e = validate();
    setTouched({ firstname: true, lastname: true, dob: true, nationality: true, height: true, backstory: true, gender: true });
    if (Object.keys(e).length) { cue('error'); toast('error', t('v_fix')); return; }
    setBusy(true);
    const form = {
      firstname: capitalize(f.firstname.trim()),
      lastname: capitalize(f.lastname.trim()),
      dob: `${dob!.y}-${two(dob!.m)}-${two(dob!.d)}`,
      nationality: R.nationality.enabled ? f.nationality : undefined,
      height: R.height.enabled ? f.height : undefined,
      backstory: R.backstory.enabled ? f.backstory.trim() : undefined,
      gender: f.gender,
    };
    const r = await post<{ ok: boolean; errors?: Errors; msg?: string }>('createSubmit', { form });
    setBusy(false);
    if (!r || !r.ok) {
      cue('error');
      if (r?.errors) setErrors(r.errors);
      toast('error', r?.msg || t('v_fix'));
    }
  };

  const ui = cfg.ui;
  return (
    <div className="absolute inset-0">
      <div className="absolute inset-0 pointer-events-none" style={{ background: 'linear-gradient(270deg, rgba(4,5,6,.65) 0%, rgba(4,5,6,.25) 30%, rgba(4,5,6,0) 45%)' }} />
      {/* wordmark */}
      <div className="absolute left-12 top-[30px] a-down flex items-end gap-3">
        <span className="display text-[40px] italic text-white text-shadow leading-none">{ui.serverName || 'NAYZEEE'}</span>
        {ui.tagline && <span className="micro text-[9px] text-fg-3 mb-[5px] tracking-[.3em]">{ui.tagline}</span>}
      </div>
      <div className="absolute left-12 bottom-[34px] flex items-center gap-5 micro text-[9px] text-fg-3 a-fade">
        <span className="flex items-center gap-2"><Kbd className="!h-[18px] !text-[9px]">Enter</Kbd>{t('key_confirm')}</span>
        <span className="flex items-center gap-2"><Kbd className="!h-[18px] !text-[9px]">Esc</Kbd>{t('back')}</span>
      </div>

      <Panel className="absolute right-10 top-10 bottom-10 w-[600px] flex flex-col a-right" style={{ ['--cut' as string]: '24px' }}>
        <div className="px-8 pt-7 pb-5 flex items-start justify-between">
          <div>
            <Micro className="text-[9px] text-accent-hi/80">{t('create_record_slot', two(slot))}</Micro>
            <div className="display text-[64px] mt-2 leading-[.85]">
              <span className="text-white">{t('create_title')} </span><span className="outline-text">{t('create_title_2')}</span>
            </div>
          </div>
          <IconBtn title={t('cancel')} onClick={cancel}><X size={18} /></IconBtn>
        </div>
        <div className="h-px bg-white/[.06] mx-8" />

        <div className="flex-1 min-h-0 scrolly px-8 pt-5">
          <div className="grid grid-cols-2 gap-x-4">
            <Field label={t('firstname')} error={shown.firstname}>
              <input className={cx('field', shown.firstname && 'err')} maxLength={R.nameMax + 4} placeholder={t('firstname_ph')} value={f.firstname}
                onChange={(e) => set('firstname', e.target.value)} onBlur={() => { blur('firstname'); set('firstname', capitalize(f.firstname.trim())); }} />
            </Field>
            <Field label={t('lastname')} error={shown.lastname}>
              <input className={cx('field', shown.lastname && 'err')} maxLength={R.nameMax + 4} placeholder={t('lastname_ph')} value={f.lastname}
                onChange={(e) => set('lastname', e.target.value)} onBlur={() => { blur('lastname'); set('lastname', capitalize(f.lastname.trim())); }} />
            </Field>
            <Field label={t('dob')} hint="DD / MM / YYYY" error={shown.dob}>
              <div className="relative">
                <input className={cx('field font-mono !text-[14px] tracking-[.08em]', shown.dob && 'err')} inputMode="numeric" placeholder={t('dob_ph')} value={f.dob}
                  onChange={(e) => set('dob', maskDob(e.target.value))} onBlur={() => blur('dob')} />
                <Calendar size={16} className="absolute right-[14px] top-1/2 -translate-y-1/2 text-fg-3 pointer-events-none" />
              </div>
            </Field>
            <Field label={t('calc_age')}>
              <div className="field flex items-center justify-between !bg-black/15 text-fg-2">
                <span className={cx('display text-[22px]', age != null && dob ? 'text-fg' : 'text-fg-4')}>{age != null && dob ? age : '—'}</span>
                <span className="micro text-[8px] text-fg-4">{R.minAge}–{R.maxAge}</span>
              </div>
            </Field>
            {R.nationality.enabled && (
              <Field className="col-span-2" label={t('nationality')} error={shown.nationality}>
                <NationalityPicker value={f.nationality} list={cfg.nationalities || []} error={shown.nationality}
                  onChange={(v) => { set('nationality', v); blur('nationality'); }} />
              </Field>
            )}
            {R.height.enabled && (
              <Field className="col-span-2" label={t('height')} hint={`${R.height.min}–${R.height.max} CM`} error={shown.height}>
                <div className="field flex items-center !h-[46px] !bg-black/15">
                  <Slider value={f.height} min={R.height.min} max={R.height.max} step={1} format={(v) => `${v}cm`} onChange={(v) => set('height', v)} />
                </div>
              </Field>
            )}
            {R.backstory.enabled && (
              <Field className="col-span-2" label={t('backstory')} hint={`${f.backstory.trim().length}/${R.backstory.max}`} error={shown.backstory}>
                <textarea className={cx('field !h-[96px] py-3 resize-none leading-snug !text-[14px]', shown.backstory && 'err')} maxLength={R.backstory.max}
                  placeholder={t('backstory_ph')} value={f.backstory} onChange={(e) => set('backstory', e.target.value)} onBlur={() => blur('backstory')} />
              </Field>
            )}
            <Field className="col-span-2" label={t('gender')} error={shown.gender}>
              <div className={cx('grid gap-3', R.genders.length > 1 ? 'grid-cols-2' : 'grid-cols-1')}>
                {(R.genders.filter((g) => g === 'm' || g === 'f') as ('m' | 'f')[]).map((g) => (
                  <GenderCard key={g} g={g} active={f.gender === g} onClick={() => pickGender(g)} />
                ))}
              </div>
            </Field>
          </div>
        </div>

        <div className="px-8 pb-7 pt-3 flex flex-col gap-3">
          <Steps active={0} />
          <HoldButton label={t('create_submit')} sub={`${t('step_record')} 01 // ${t('step_appearance')} 02`} busy={busy} onComplete={submit} size="md" />
        </div>
      </Panel>
    </div>
  );
}
