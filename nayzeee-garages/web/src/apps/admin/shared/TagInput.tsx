/**
 * TagInput — a list of strings edited as removable chips (player identifiers…).
 *
 * API
 *   <TagInput value onChange placeholder? max? uppercase? mono? invalid? />
 * Type and press Enter, comma or space to add; pasting "A, B C" adds several; Backspace on an
 * empty field removes the last chip. Duplicates are ignored. Values are trimmed.
 */
import { useRef, useState } from 'react';
import type { ClipboardEvent, KeyboardEvent } from 'react';
import { Icon, cx } from '@/components/ui';
import { t } from '@/lib/i18n';

export interface TagInputProps {
  value: string[];
  onChange: (value: string[]) => void;
  placeholder?: string;
  max?: number;
  uppercase?: boolean;
  mono?: boolean;
  invalid?: boolean;
  className?: string;
}

export function TagInput({ value, onChange, placeholder, max = 200, uppercase = false, mono = true, invalid = false, className }: TagInputProps) {
  const [text, setText] = useState('');
  const ref = useRef<HTMLInputElement>(null);

  const add = (raw: string) => {
    const parts = raw
      .split(/[\s,;]+/)
      .map((s) => (uppercase ? s.trim().toUpperCase() : s.trim()))
      .filter(Boolean);
    if (!parts.length) return;
    const next = [...value];
    for (const p of parts) if (!next.includes(p) && next.length < max) next.push(p);
    if (next.length !== value.length) onChange(next);
    setText('');
  };

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' || e.key === ',' || e.key === ' ' || e.key === 'Tab') {
      if (!text.trim()) return;
      e.preventDefault();
      add(text);
    } else if (e.key === 'Backspace' && !text && value.length) {
      onChange(value.slice(0, -1));
    }
  };

  const onPaste = (e: ClipboardEvent<HTMLInputElement>) => {
    const s = e.clipboardData.getData('text');
    if (/[\s,;]/.test(s.trim())) {
      e.preventDefault();
      add(s);
    }
  };

  return (
    <div
      className={cx('nz-admin-tags', invalid && 'is-invalid', className)}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) {
          e.preventDefault();
          ref.current?.focus();
        }
      }}
    >
      {value.map((v) => (
        <span key={v} className={cx('nz-admin-tags__tag', mono && 'is-mono')}>
          {v}
          <button type="button" aria-label={t('Remove {value}', { value: v })} onClick={() => onChange(value.filter((x) => x !== v))}>
            <Icon name="close" size={11} strokeWidth={2.2} />
          </button>
        </span>
      ))}
      <input
        ref={ref}
        className={cx('nz-admin-tags__input', mono && 'is-mono')}
        value={text}
        placeholder={value.length ? '' : placeholder}
        spellCheck={false}
        autoComplete="off"
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        onPaste={onPaste}
        onBlur={() => text.trim() && add(text)}
      />
    </div>
  );
}
