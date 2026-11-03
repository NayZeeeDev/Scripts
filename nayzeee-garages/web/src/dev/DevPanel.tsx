/**
 * Floating dev panel listing mock scenarios. Hidden with ?panel=0 (used for screenshots).
 */
import { useMemo, useState } from 'react';
import { openScenario, scenarios } from './registry';

export function DevPanel() {
  const [open, setOpen] = useState(true);
  const groups = useMemo(() => {
    const map = new Map<string, typeof scenarios>();
    scenarios.forEach((s) => map.set(s.group, [...(map.get(s.group) ?? []), s]));
    return [...map.entries()];
  }, []);

  const box: React.CSSProperties = {
    position: 'fixed', right: 12, bottom: 12, zIndex: 99999, width: 250, maxHeight: '70vh', overflow: 'auto',
    background: '#0e1011', border: '1px solid rgba(255,255,255,.1)', borderRadius: 10, padding: 10,
    font: '12px Lexend, system-ui, sans-serif', color: '#9ea5aa',
  };
  if (!open) {
    return <button style={{ ...box, width: 'auto', cursor: 'pointer' }} onClick={() => setOpen(true)}>Mocks</button>;
  }
  return (
    <div style={box}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, color: '#fff' }}>
        <b>Mock scenarios</b>
        <button style={{ color: '#9ea5aa', background: 'none', border: 0, cursor: 'pointer' }} onClick={() => setOpen(false)}>hide</button>
      </div>
      {groups.map(([group, list]) => (
        <div key={group} style={{ marginTop: 8 }}>
          <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '.12em', color: '#63696d' }}>{group}</div>
          {list.map((s) => (
            <button
              key={s.id}
              onClick={() => openScenario(s.id)}
              style={{ display: 'block', width: '100%', textAlign: 'left', padding: '4px 6px', marginTop: 2, borderRadius: 6, background: 'none', border: 0, color: '#f2f4f5', cursor: 'pointer' }}
            >
              {s.label} <span style={{ color: '#63696d' }}>· {s.id}</span>
            </button>
          ))}
        </div>
      ))}
    </div>
  );
}
