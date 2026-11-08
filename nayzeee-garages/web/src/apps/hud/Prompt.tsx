/**
 * Interaction prompt (no focus): the owner's prompt bar at the bottom centre of the screen —
 * solid dark rounded bar, bordered key chip + white label, e.g. [E] Open garage. Driven by the
 * `prompt` NUI message. When the key hint bar is up as well, the prompt sits just above it.
 */
import { useEffect, useState } from 'react';
import { useUi } from '@/lib/store';
import type { PromptData } from '@/lib/types';
import { keyLabel, usePresence } from '@/components/ui/internal';
import './hud.css';

export function Prompt() {
  const prompt = useUi((s) => s.prompt);
  const hint = useUi((s) => s.hint);
  const [shown, setShown] = useState<PromptData | null>(prompt);
  const { mounted, closing } = usePresence(!!prompt, 180);

  useEffect(() => {
    if (prompt) setShown(prompt);
  }, [prompt]);

  if (!mounted || !shown) return null;
  const key = keyLabel(shown.key || 'E');
  const stacked = !!hint && hint.keys?.length > 0;
  return (
    <div className={`nz-prompt${stacked ? ' is-stacked' : ''}`} aria-live="polite">
      <div key={`${shown.key}|${shown.label}`} className={`nz-prompt__bar${closing ? ' is-leaving' : ''}`}>
        <kbd className={`nz-hud-key${key.length > 2 ? ' nz-hud-key--word' : ''}`}>{key}</kbd>
        <span className="nz-hud-label">{shown.label}</span>
      </div>
    </div>
  );
}
