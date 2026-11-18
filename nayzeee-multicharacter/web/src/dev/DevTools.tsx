// Dev-only view switcher (browser mock mode, `npm run dev` or ?dev=1). Never loaded in game.
import { useState } from 'react';
import { emit } from '../lib/nui';

const show = import.meta.env.DEV || new URLSearchParams(location.search).has('dev');

export default function DevTools() {
  const [open, setOpen] = useState(true);
  if (!show) return null;
  const go = (v: string) => import('./mock').then((m) => m.go(v));
  const btn = 'px-2 h-[24px] rounded bg-white/10 hover:bg-white/20 text-[11px] font-mono text-white';
  return (
    <div className="fixed right-2 bottom-2 z-[9999] flex items-center gap-1 p-1 rounded-md bg-black/80 border border-white/10">
      <button className={btn} onClick={() => setOpen(!open)}>{open ? '×' : 'dev'}</button>
      {open && ['start', 'lobby', 'create', 'spawn', 'cutscene'].map((v) => (
        <button key={v} className={btn} onClick={() => go(v)}>{v}</button>
      ))}
      {open && <button className={btn} onClick={() => emit('toast', { type: 'success', text: 'Request sent to Kai Moreno' })}>toast</button>}
      {open && <button className={btn} onClick={() => emit('busy', { on: true, text: 'Loading scene' })}>busy</button>}
      {open && <button className={btn} onClick={() => emit('busy', { on: false })}>idle</button>}
    </div>
  );
}
