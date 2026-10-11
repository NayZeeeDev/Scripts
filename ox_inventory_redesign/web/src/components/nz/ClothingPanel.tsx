import React, { useEffect, useState } from 'react';
import { T } from '../../store/strings';
import { fetchNui } from '../../utils/fetchNui';
import { isEnvBrowser } from '../../utils/misc';
import {
  IconBracelet,
  IconChain,
  IconEar,
  IconGlasses,
  IconHat,
  IconMask,
  IconPants,
  IconShirt,
  IconShoe,
  IconBackpack,
  IconVest,
  IconWatch,
} from './Icons';

type Piece = 'hat' | 'glasses' | 'ears' | 'mask' | 'neck' | 'top' | 'vest' | 'bag' | 'watch' | 'bracelet' | 'pants' | 'shoes';

const LEFT: [Piece, React.FC<any>][] = [
  ['hat', IconHat],
  ['glasses', IconGlasses],
  ['ears', IconEar],
  ['mask', IconMask],
  ['neck', IconChain],
  ['top', IconShirt],
];

const RIGHT: [Piece, React.FC<any>][] = [
  ['vest', IconVest],
  ['bag', IconBackpack],
  ['watch', IconWatch],
  ['bracelet', IconBracelet],
  ['pants', IconPants],
];

type State = Partial<Record<Piece, boolean>>;

const ClothingPanel: React.FC = () => {
  const [state, setState] = useState<State>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (isEnvBrowser()) {
      setState({ hat: false, top: true, pants: true, shoes: true, watch: true });
      return;
    }
    fetchNui<State>('nz:clothing', { action: 'state' })
      .then((s) => s && setState(s))
      .catch(() => {});
  }, []);

  const toggle = (piece: Piece) => {
    if (busy) return;
    if (isEnvBrowser()) return setState((s) => ({ ...s, [piece]: !s[piece] }));
    setBusy(true);
    fetchNui<State>('nz:clothing', { action: 'toggle', piece })
      .then((s) => s && setState(s))
      .catch(() => {})
      .finally(() => setBusy(false));
  };

  const button = ([piece, Icon]: [Piece, React.FC<any>]) => (
    <button
      key={piece}
      className="nz-cloth-btn"
      data-worn={state[piece] || undefined}
      onClick={() => toggle(piece)}
      title={T[piece]}
    >
      <Icon />
      <span className="nz-cloth-tip">{T[piece]}</span>
    </button>
  );

  return (
    <div className="nz-clothing">
      <div className="nz-cloth-col">{LEFT.map(button)}</div>
      <div className="nz-cloth-stage" />
      <div className="nz-cloth-col">{RIGHT.map(button)}</div>
      <div className="nz-cloth-bottom">{button(['shoes', IconShoe])}</div>
    </div>
  );
};

export default ClothingPanel;
