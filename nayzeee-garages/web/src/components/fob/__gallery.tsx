import { createRoot } from 'react-dom/client';
import '@fontsource/lexend/400.css';
import '../../styles/tokens.css';
import '../../styles/base.css';
import { FobArt, FOB_DESIGNS } from './FobArt';
const makes = ['DINKA', 'Pegassi', 'Übermacht', 'Vom Feuer', 'BF', 'ZIRCONIU', 'Grotti', 'Obey', 'Unknownmake', 'Karin'];
const actives = [null, 'lock', 'unlock', 'trunk', 'panic'];
function G() {
  const big = new URLSearchParams(location.search).get('size');
  const size = big ? Number(big) : 200;
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 28, padding: 24, alignItems: 'flex-end' }}>
      {FOB_DESIGNS.map((d, i) => (
        <div key={d} style={{ textAlign: 'center', color: '#9ea5aa', font: '12px Lexend' }}>
          <FobArt design={d} kind={d === 'key' ? 'key' : 'fob'} brand={makes[i]} size={size} active={actives[i % 5]} />
          <div>{d} / {makes[i]} / {String(actives[i % 5])}</div>
        </div>
      ))}
    </div>
  );
}
createRoot(document.getElementById('g')!).render(<G />);
