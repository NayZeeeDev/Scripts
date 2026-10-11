import React, { useState, useRef, useEffect } from 'react';
import { useDrop } from 'react-dnd';
import { useAppDispatch, useAppSelector } from '../../store';
import { selectItemAmount, setItemAmount } from '../../store/inventory';
import { DragSource } from '../../typings';
import { onUse } from '../../dnd/onUse';
import { onGive } from '../../dnd/onGive';
import { Locale } from '../../store/locale';
import UsefulControls from './UsefulControls';
import { openGive, selectConfig } from '../../store/ui';
import { IconHand, IconHandshake, IconInfo } from '../nz/Icons';

const formatAmount = (n: number) => (n > 0 ? n.toLocaleString('en-US') : '0');
const digitsOnly = (s: string) => s.replace(/\D/g, '');
const countDigitsBefore = (s: string, index: number) => digitsOnly(s.substring(0, index)).length;

const InventoryControl: React.FC<{ children?: React.ReactNode }> = ({ children }) => {
  const itemAmount = useAppSelector(selectItemAmount);
  const config = useAppSelector(selectConfig);
  const dispatch = useAppDispatch();

  const [infoVisible, setInfoVisible] = useState(false);
  const [value, setValue] = useState(formatAmount(itemAmount));
  const inputRef = useRef<HTMLInputElement>(null);
  const cursorRef = useRef<number | null>(null);
  const giveMenuRef = useRef(config.giveMenu);
  giveMenuRef.current = config.giveMenu;

  const [{ useOver }, use] = useDrop<DragSource, void, { useOver: boolean }>(() => ({
    accept: 'SLOT',
    collect: (monitor) => ({ useOver: monitor.isOver() && monitor.getItem()?.inventory === 'player' }),
    drop: (source) => {
      source.inventory === 'player' && onUse(source.item);
    },
  }));

  const [{ giveOver }, give] = useDrop<DragSource, void, { giveOver: boolean }>(() => ({
    accept: 'SLOT',
    collect: (monitor) => ({ giveOver: monitor.isOver() && monitor.getItem()?.inventory === 'player' }),
    drop: (source) => {
      if (source.inventory !== 'player') return;
      if (giveMenuRef.current) {
        dispatch(openGive({ slot: source.item.slot, count: 0 }));
      } else onGive(source.item);
    },
  }));

  const commitValue = (raw: string, cursorIndex: number) => {
    const digitsBefore = countDigitsBefore(raw, cursorIndex);
    const num = parseInt(digitsOnly(raw), 10) || 0;

    setValue(formatAmount(num));
    dispatch(setItemAmount(num));
    cursorRef.current = digitsBefore;
  };

  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) =>
    commitValue(event.target.value, event.target.selectionStart ?? 0);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    const el = event.currentTarget;
    const pos = el.selectionStart ?? 0;

    if (pos !== el.selectionEnd) return;

    if (event.key === 'Backspace' && el.value[pos - 1] === ',') {
      event.preventDefault();
      commitValue(el.value.slice(0, pos - 2) + el.value.slice(pos), pos - 2);
    } else if (event.key === 'Delete' && el.value[pos] === ',') {
      event.preventDefault();
      commitValue(el.value.slice(0, pos) + el.value.slice(pos + 2), pos);
    }
  };

  useEffect(() => {
    if (!inputRef.current || cursorRef.current === null) return;
    let newPos = 0;
    let count = 0;

    for (let i = 0; i < value.length && count < cursorRef.current; i++) {
      if (/\d/.test(value[i])) count++;
      newPos++;
    }

    inputRef.current.setSelectionRange(newPos, newPos);
    cursorRef.current = null;
  }, [value]);

  return (
    <>
      <UsefulControls infoVisible={infoVisible} setInfoVisible={setInfoVisible} />
      <div className="nz-controls">
        {children}
        <input
          className="nz-amount"
          type="text"
          ref={inputRef}
          value={value}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          onFocus={(e) => e.currentTarget.select()}
        />
        <div
          className={`nz-action${useOver ? ' is-over' : ''}`}
          ref={(el) => {
            use(el);
          }}
        >
          <IconHand className="nz-action-icon" />
          <span>{Locale.ui_use || 'Use'}</span>
        </div>
        <div
          className={`nz-action${giveOver ? ' is-over' : ''}`}
          ref={(el) => {
            give(el);
          }}
        >
          <IconHandshake className="nz-action-icon" />
          <span>{Locale.ui_give || 'Give'}</span>
        </div>
        <button className="nz-info-btn" onClick={() => setInfoVisible(true)} title={Locale.ui_usefulcontrols}>
          <IconInfo />
        </button>
      </div>
    </>
  );
};

export default InventoryControl;
