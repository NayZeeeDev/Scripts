/**
 * Key hint bar (no focus): the owner's prompt bar at the bottom centre — solid dark rounded
 * bar, an optional title first, then key chip(s) + white label per control. W/A/S/D is drawn as
 * a small key cross. Driven by the `hint` NUI message. Its height is published as
 * --nz-hint-h so the interaction prompt can stack above it.
 */
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useUi } from '@/lib/store';
import type { HintData } from '@/lib/types';
import { Icon } from '@/components/icons';
import { keyLabel, usePresence } from '@/components/ui/internal';
import './hud.css';

const isWasd = (keys: string[]) =>
  keys.length === 4 && keys.map((k) => k.trim().toUpperCase()).join('') === 'WASD';

function Cap({ k }: { k: string }) {
  const label = keyLabel(k);
  return <kbd className={`nz-hud-key${label.length > 2 ? ' nz-hud-key--word' : ''}`}>{label}</kbd>;
}

export function Hint() {
  const hint = useUi((s) => s.hint);
  const [shown, setShown] = useState<HintData | null>(hint);
  const { mounted, closing } = usePresence(!!hint, 180);
  const barRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (hint) setShown(hint);
  }, [hint]);

  const visible = mounted && !!shown && !!shown.keys?.length;
  useLayoutEffect(() => {
    const root = document.documentElement;
    const el = barRef.current;
    if (!visible || !el) {
      root.style.removeProperty('--nz-hint-h');
      return;
    }
    const publish = () => root.style.setProperty('--nz-hint-h', `${Math.ceil(el.getBoundingClientRect().height)}px`);
    publish();
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(publish) : null;
    ro?.observe(el);
    return () => {
      ro?.disconnect();
      root.style.removeProperty('--nz-hint-h');
    };
  }, [visible, shown]);

  if (!visible || !shown) return null;
  return (
    <div className="nz-hint">
      <div ref={barRef} className={`nz-hint__bar${closing ? ' is-leaving' : ''}`}>
        {shown.title && (
          <span className="nz-hint__title">
            <Icon name="info" size={13} strokeWidth={1.9} />
            <span>{shown.title}</span>
          </span>
        )}
        {shown.keys.map((g, i) => (
          <span key={`${g.label}-${i}`} className="nz-hint__group">
            {isWasd(g.keys) ? (
              <span className="nz-hint__cross" aria-label="W A S D">
                <Cap k="W" />
                <span className="nz-hint__cross-row">
                  <Cap k="A" />
                  <Cap k="S" />
                  <Cap k="D" />
                </span>
              </span>
            ) : (
              <span className="nz-hint__caps">
                {g.keys.map((k, j) => (
                  <Cap key={`${k}-${j}`} k={k} />
                ))}
              </span>
            )}
            <span className="nz-hud-label">{g.label}</span>
          </span>
        ))}
      </div>
    </div>
  );
}
