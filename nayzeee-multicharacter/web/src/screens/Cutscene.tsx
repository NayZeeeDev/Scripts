import { useStore } from '../lib/store';

/** Cutscene: everything else is hidden; optional letterbox bars slide in. */
export default function Cutscene() {
  const on = useStore((s) => s.view === 'cutscene');
  const bars = useStore((s) => s.settings.bars);
  if (!on || !bars) return null;
  const bar = 'absolute left-0 right-0 bg-black h-[11%]';
  return (
    <div className="absolute inset-0 pointer-events-none z-[90]">
      <div className={`${bar} top-0 origin-top`} style={{ animation: 'bar-in .9s cubic-bezier(.22,.8,.26,1) both' }} />
      <div className={`${bar} bottom-0 origin-bottom`} style={{ animation: 'bar-in .9s cubic-bezier(.22,.8,.26,1) both' }} />
    </div>
  );
}
