import React, { useEffect, useRef } from 'react';
import { useAppDispatch, useAppSelector } from '../../store';
import { openSettings, selectConfig, setClothingOpen, setSearch, setSearchOpen, toggleView } from '../../store/ui';
import { T } from '../../store/strings';
import { fetchNui } from '../../utils/fetchNui';
import { IconCompact, IconExpand, IconGear, IconSearch, IconShirt } from './Icons';

const Toolbar: React.FC<{ compact?: boolean }> = ({ compact }) => {
  const dispatch = useAppDispatch();
  const { search, searchOpen, clothingOpen, settings } = useAppSelector((state) => state.ui);
  const config = useAppSelector(selectConfig);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (searchOpen) inputRef.current?.focus();
  }, [searchOpen]);

  const toggleClothing = () => {
    const next = !clothingOpen;
    dispatch(setClothingOpen(next));
    fetchNui('nz:clothing', { action: next ? 'open' : 'close', reblur: true }).catch(() => {});
  };

  return (
    <div className={`nz-toolbar${compact ? ' is-compact' : ''}`}>
      <div className={`nz-search${searchOpen ? ' is-open' : ''}`}>
        <button
          className="nz-tool"
          onClick={() => dispatch(setSearchOpen(!searchOpen))}
          title={T.search}
          data-active={searchOpen || undefined}
        >
          <IconSearch />
        </button>
        {searchOpen && (
          <input
            ref={inputRef}
            value={search}
            placeholder={T.search}
            onChange={(e) => dispatch(setSearch(e.target.value))}
            onKeyUp={(e) => {
              if (e.key !== 'Escape') return;
              e.stopPropagation();
              dispatch(setSearchOpen(false));
            }}
          />
        )}
      </div>
      <button
        className="nz-tool"
        data-active={settings.view === 'fullscreen' || undefined}
        onClick={() => dispatch(toggleView())}
        title={settings.view === 'fullscreen' ? T.compact : T.fullscreen}
      >
        {settings.view === 'fullscreen' ? <IconExpand /> : <IconCompact />}
      </button>
      <button className="nz-tool" onClick={() => dispatch(openSettings())} title={T.settings}>
        <IconGear />
      </button>
      {config.clothing && (
        <button className="nz-tool" data-active={clothingOpen || undefined} onClick={toggleClothing} title={T.clothing}>
          <IconShirt />
        </button>
      )}
    </div>
  );
};

export default Toolbar;
