/**
 * Key hint bar (no focus): bottom-center HUD panel with an optional title and groups of
 * keycaps + labels. W/A/S/D is drawn as a small key cross. Driven by the `hint` NUI message.
 */
import { useEffect, useState } from 'react';
import { useUi } from '@/lib/store';
import type { HintData } from '@/lib/types';
import { Icon } from '@/components/icons';
import { keyLabel, usePresence } from '@/components/ui/internal';
import './hud.css';

const isWasd = (keys: string[]) =>
  keys.length === 4 && keys.map((k) => k.trim().toUpperCase()).join('') === 'WASD';

function Cap({ k }: { k: string }) {
  const label = keyLabel(k);
  return <kbd className={`nz-hint__cap${label.length > 2 ? ' nz-hint__cap--word' : ''}`}>{label}</kbd>;
}

export function Hint() {
  const hint = useUi((s) => s.hint);
  const [shown, setShown] = useState<HintData | null>(hint);
  const { mounted, closing } = usePresence(!!hint, 180);

  useEffect(() => {
    if (hint) setShown(hint);
  }, [hint]);

  if (!mounted || !shown || !shown.keys?.length) return null;
  return (
    <div className="nz-hint">
      <div className={`nz-hint__panel${closing ? ' is-leaving' : ''}`}>
        {shown.title && (
          <div className="nz-hint__title">
            <Icon name="info" size={13} strokeWidth={1.8} />
            <span>{shown.title}</span>
          </div>
        )}
        <div className="nz-hint__groups">
          {shown.keys.map((g, i) => (
            <div key={`${g.label}-${i}`} className={`nz-hint__group${isWasd(g.keys) ? ' nz-hint__group--cross' : ''}`}>
              {isWasd(g.keys) ? (
                <span className="nz-hint__cross" aria-label="W A S D">
                  <span className="nz-hint__cross-w">
                    <Cap k="W" />
                  </span>
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
              <span className="nz-hint__label">{g.label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
