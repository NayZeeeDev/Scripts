/**
 * Interaction prompt (no focus): a HUD pill at the left-middle of the screen —
 * accent keycap + label, e.g. [E] Open garage. Driven by the `prompt` NUI message.
 */
import { useEffect, useState } from 'react';
import { useUi } from '@/lib/store';
import type { PromptData } from '@/lib/types';
import { keyLabel, usePresence } from '@/components/ui/internal';
import './hud.css';

export function Prompt() {
  const prompt = useUi((s) => s.prompt);
  const [shown, setShown] = useState<PromptData | null>(prompt);
  const { mounted, closing } = usePresence(!!prompt, 180);

  useEffect(() => {
    if (prompt) setShown(prompt);
  }, [prompt]);

  if (!mounted || !shown) return null;
  const key = keyLabel(shown.key || 'E');
  return (
    <div className="nz-prompt" aria-live="polite">
      <div
        key={`${shown.key}|${shown.label}`}
        className={`nz-prompt__pill${closing ? ' is-leaving' : ''}${key.length > 1 ? ' nz-prompt__pill--wide' : ''}`}
      >
        <span className="nz-prompt__key">{key}</span>
        <span className="nz-prompt__label">{shown.label}</span>
      </div>
    </div>
  );
}
