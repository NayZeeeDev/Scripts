/**
 * Hotwire wires (G.7): behind the dash, three wire ends come from the battery loom (left) and
 * three from the ignition loom (right). Drag a left end onto the right end of the same colour
 * to splice it (or press its number 1-3, then the number of the right end). A wrong contact
 * sparks; three shorts and the attempt fails. Three splices start the car.
 * answer[i] = the right position (1-3) that left wire i was spliced to.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import { t } from '@/lib/i18n';
import { useEscape } from '@/lib/escape';
import type { MinigameOpenData } from '@/lib/types';
import { Window } from '@/components/ui';
import { HelpCard, PromptBar, TimeLeft, useFinish, useStarted } from '../shared';
import { sfx } from '../sound';

type WiresData = Extract<MinigameOpenData, { game: 'wires' }>;
type Status = 'play' | 'live' | 'fried';

const MAX_SHORTS = 3;
const RESULT_HOLD_MS = 950;
const SNAP_RADIUS = 34;

/** insulation colours of the server's wire names (content colours, not UI accents) */
const WIRE: Record<string, { base: string; dark: string; label: string }> = {
  red: { base: '#d84a45', dark: '#7e1f1c', label: 'Red' },
  blue: { base: '#3e7fd4', dark: '#1d3d6b', label: 'Blue' },
  yellow: { base: '#e2bf3a', dark: '#7d6614', label: 'Yellow' },
  green: { base: '#3daa58', dark: '#1a5a2a', label: 'Green' },
  white: { base: '#e6eaec', dark: '#7c8488', label: 'White' },
  orange: { base: '#e7843a', dark: '#7c3f12', label: 'Orange' },
};

const VB = { w: 640, h: 340 };
const ROWS = [86, 170, 254];
const LEFT_TIP = 226; // end of the bare copper, left side
const RIGHT_TIP = 414; // start of the bare copper, right side

function validPuzzle(p: WiresData['puzzle']): boolean {
  if (!p || !Array.isArray(p.left) || !Array.isArray(p.right) || p.left.length !== 3 || p.right.length !== 3) return false;
  if (![...p.left, ...p.right].every((c) => typeof c === 'string' && WIRE[c])) return false;
  return [...p.left].sort().join() === [...p.right].sort().join();
}

/** cubic bezier point + tangent angle at t */
function bezier(p0: number[], p1: number[], p2: number[], p3: number[], tt: number) {
  const u = 1 - tt;
  const x = u * u * u * p0[0] + 3 * u * u * tt * p1[0] + 3 * u * tt * tt * p2[0] + tt * tt * tt * p3[0];
  const y = u * u * u * p0[1] + 3 * u * u * tt * p1[1] + 3 * u * tt * tt * p2[1] + tt * tt * tt * p3[1];
  const dx = 3 * u * u * (p1[0] - p0[0]) + 6 * u * tt * (p2[0] - p1[0]) + 3 * tt * tt * (p3[0] - p2[0]);
  const dy = 3 * u * u * (p1[1] - p0[1]) + 6 * u * tt * (p2[1] - p1[1]) + 3 * tt * tt * (p3[1] - p2[1]);
  return { x, y, angle: (Math.atan2(dy, dx) * 180) / Math.PI };
}

function Cable({ d, colour, width = 9 }: { d: string; colour: string; width?: number }) {
  const c = WIRE[colour];
  return (
    <g className="nz-mg-wires__cable">
      <path d={d} stroke="rgba(0,0,0,.55)" strokeWidth={width + 3} fill="none" strokeLinecap="round" />
      <path d={d} stroke={c.dark} strokeWidth={width} fill="none" strokeLinecap="round" />
      <path d={d} stroke={c.base} strokeWidth={width - 3} fill="none" strokeLinecap="round" />
      <path d={d} stroke="rgba(255,255,255,.32)" strokeWidth={1.6} fill="none" strokeLinecap="round" transform="translate(0 -2)" />
    </g>
  );
}

/** stripped copper end, pointing right (side 'left') or left (side 'right') */
function Copper({ x, y, side, hot }: { x: number; y: number; side: 'left' | 'right'; hot?: boolean }) {
  const dir = side === 'left' ? 1 : -1;
  const x0 = side === 'left' ? x - 30 : x;
  return (
    <g className={`nz-mg-wires__copper${hot ? ' is-hot' : ''}`}>
      <rect x={x0} y={y - 3.5} width={30} height={7} rx={2} fill="#c88645" />
      {[-2, 0, 2].map((o) => (
        <line key={o} x1={x0 + 2} y1={y + o} x2={x0 + 28} y2={y + o * 0.6} stroke="#f1c27d" strokeWidth={0.8} opacity={0.8} />
      ))}
      <circle cx={side === 'left' ? x : x} cy={y} r={2.2} fill="#f6d39a" transform={`translate(${dir * 0.5} 0)`} />
    </g>
  );
}

export function WiresGame({ data }: { data: WiresData }) {
  const puzzle = data.puzzle;
  const valid = useMemo(() => validPuzzle(puzzle), [puzzle]);
  useStarted(data.token, valid);
  const finish = useFinish(data.token);

  const [spliced, setSpliced] = useState<(number | null)[]>([null, null, null]); // left i -> right j (0-based)
  const [shorts, setShorts] = useState(0);
  const [status, setStatus] = useState<Status>('play');
  const [drag, setDrag] = useState<{ from: number; x: number; y: number } | null>(null);
  const [picked, setPicked] = useState<number | null>(null); // keyboard: left wire chosen
  const [sparks, setSparks] = useState<{ id: number; x: number; y: number }[]>([]);
  const [shake, setShake] = useState(0);
  const [help, setHelp] = useState(false);
  const svgRef = useRef<SVGSVGElement>(null);
  const done = useRef(false);
  const timers = useRef<number[]>([]);
  const later = (fn: () => void, ms: number) => timers.current.push(window.setTimeout(fn, ms));
  useEffect(() => () => timers.current.forEach((id) => window.clearTimeout(id)), []);

  const usedRight = spliced.filter((j): j is number => j !== null);
  const count = usedRight.length;

  const connect = useCallback(
    (i: number, j: number) => {
      if (status !== 'play' || done.current) return;
      if (spliced[i] !== null || spliced.includes(j)) return;
      if (puzzle.left[i] === puzzle.right[j]) {
        const next = [...spliced];
        next[i] = j;
        setSpliced(next);
        sfx.splice();
        if (next.every((v) => v !== null)) {
          setStatus('live');
          done.current = true;
          later(() => sfx.ignition(), 200);
          const answer = next.map((v) => (v as number) + 1);
          later(() => finish({ success: true, answer }), RESULT_HOLD_MS);
        }
        return;
      }
      // wrong contact: sparks at the right end
      sfx.spark();
      const id = performance.now();
      setSparks((s) => [...s.slice(-3), { id, x: RIGHT_TIP, y: ROWS[j] }]);
      later(() => setSparks((s) => s.filter((p) => p.id !== id)), 650);
      setShake((n) => n + 1);
      const total = shorts + 1;
      setShorts(total);
      if (total >= MAX_SHORTS) {
        setStatus('fried');
        done.current = true;
        later(() => finish({ success: false }), RESULT_HOLD_MS + 250);
      }
    },
    [status, spliced, puzzle, shorts, finish],
  );

  /* ── pointer ── */
  const toSvg = (e: { clientX: number; clientY: number }) => {
    const svg = svgRef.current;
    const m = svg?.getScreenCTM();
    if (!svg || !m) return { x: 0, y: 0 };
    const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(m.inverse());
    return { x: p.x, y: p.y };
  };
  const nearestRight = (x: number, y: number) => {
    let best = -1;
    let dist = SNAP_RADIUS;
    ROWS.forEach((ry, j) => {
      const d = Math.hypot(x - (RIGHT_TIP - 4), y - ry);
      if (d < dist && !usedRight.includes(j)) {
        best = j;
        dist = d;
      }
    });
    return best;
  };
  const onLeftDown = (i: number) => (e: ReactPointerEvent) => {
    if (status !== 'play' || spliced[i] !== null) return;
    e.preventDefault();
    sfx.unlock();
    svgRef.current?.setPointerCapture(e.pointerId);
    const p = toSvg(e);
    setPicked(null);
    setDrag({ from: i, x: p.x, y: p.y });
  };
  const onMove = (e: ReactPointerEvent) => {
    if (!drag) return;
    const p = toSvg(e);
    setDrag({ ...drag, x: p.x, y: p.y });
  };
  const onUp = (e: ReactPointerEvent) => {
    if (!drag) return;
    const p = toSvg(e);
    const j = nearestRight(p.x, p.y);
    setDrag(null);
    if (j >= 0) connect(drag.from, j);
  };

  /* ── keyboard: H help, 1-3 pick a left end then a right end ── */
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === 'Escape' || e.repeat) return;
      if (e.code === 'KeyH') {
        setHelp((v) => !v);
        return;
      }
      const n = ['Digit1', 'Digit2', 'Digit3', 'Numpad1', 'Numpad2', 'Numpad3'].indexOf(e.code);
      if (n < 0 || status !== 'play') return;
      const k = n % 3;
      sfx.unlock();
      if (picked === null) {
        if (spliced[k] === null) setPicked(k);
      } else {
        const from = picked;
        setPicked(null);
        connect(from, k);
      }
    };
    window.addEventListener('keydown', down);
    return () => window.removeEventListener('keydown', down);
  }, [picked, spliced, status, connect]);

  const cancel = () => {
    if (done.current) return;
    done.current = true;
    finish({ success: false, cancelled: true });
  };
  useEscape(cancel, valid);

  if (!valid) return null;

  const vehicle = [data.vehicle?.label, data.vehicle?.plate].filter(Boolean).join(' · ');
  const looseLeft = (i: number) => `M 70 ${128 + i * 42} C 128 ${128 + i * 42}, 140 ${ROWS[i]}, ${LEFT_TIP - 30} ${ROWS[i]}`;
  const looseRight = (j: number) => `M 570 ${128 + j * 42} C 512 ${128 + j * 42}, 500 ${ROWS[j]}, ${RIGHT_TIP + 30} ${ROWS[j]}`;
  const joint = (i: number, j: number) => {
    const p0 = [LEFT_TIP - 4, ROWS[i]];
    const p1 = [LEFT_TIP + 70, ROWS[i]];
    const p2 = [RIGHT_TIP - 70, ROWS[j]];
    const p3 = [RIGHT_TIP + 4, ROWS[j]];
    return { d: `M ${p0} C ${p1}, ${p2}, ${p3}`, mid: bezier(p0, p1, p2, p3, 0.5) };
  };

  const statusText =
    status === 'live'
      ? t('Ignition live: the engine turns over')
      : status === 'fried'
        ? t('Shorted out: the ignition is dead')
        : drag || picked !== null
          ? t('Touch it to the {colour} end on the right', { colour: t(WIRE[puzzle.left[drag ? drag.from : (picked as number)]].label).toLowerCase() })
          : t('Splice each battery wire to the ignition wire of the same colour');

  return (
    <>
      <Window
        title={t('Hotwire')}
        icon="engine"
        subtitle={vehicle || t('Behind the dashboard')}
        headerExtra={<TimeLeft limit={data.timeLimit} paused={status !== 'play'} />}
        onClose={cancel}
        width={700}
        className={`nz-mg-wires is-${status}`}
        bodyClassName="nz-mg-wires__body"
      >
        <div className="nz-mg-wires__meters">
          <div className="nz-mg-wires__meter">
            <span className="nz-mg-wires__heading">{t('Spliced')}</span>
            <span className="nz-mg-wires__pips">
              {[0, 1, 2].map((i) => (
                <span key={i} className={i < count ? 'is-on' : undefined} />
              ))}
            </span>
            <span className="nz-mg-wires__count">{count}/3</span>
          </div>
          <div className="nz-mg-wires__meter is-shorts">
            <span className="nz-mg-wires__heading">{t('Shorts')}</span>
            <span className="nz-mg-wires__pips">
              {Array.from({ length: MAX_SHORTS }, (_, i) => (
                <span key={i} className={i < shorts ? 'is-on' : undefined} />
              ))}
            </span>
            <span className="nz-mg-wires__count">
              {shorts}/{MAX_SHORTS}
            </span>
          </div>
          <span className={`nz-mg-wires__lamp is-${status}`}>
            <span />
            {status === 'live' ? t('Ignition on') : t('Ignition off')}
          </span>
        </div>

        <div className="nz-mg-wires__bay" key={shake} data-shake={shake > 0 ? 'y' : undefined}>
          <svg
            ref={svgRef}
            className={`nz-mg-wires__svg${drag ? ' is-dragging' : ''}`}
            viewBox={`0 0 ${VB.w} ${VB.h}`}
            onPointerMove={onMove}
            onPointerUp={onUp}
            onPointerCancel={() => setDrag(null)}
          >
            <defs>
              <pattern id="nz-mg-mesh" width="14" height="14" patternUnits="userSpaceOnUse">
                <circle cx="7" cy="7" r="1.1" fill="rgba(255,255,255,.05)" />
              </pattern>
              <linearGradient id="nz-mg-loom" x1="0" x2="1">
                <stop offset="0" stopColor="#1b1f22" />
                <stop offset=".5" stopColor="#2a3034" />
                <stop offset="1" stopColor="#15181a" />
              </linearGradient>
            </defs>
            <rect x="0" y="0" width={VB.w} height={VB.h} fill="url(#nz-mg-mesh)" />
            {/* looms */}
            <text x="44" y="38" className="nz-mg-wires__svgLabel" textAnchor="middle">{t('Battery')}</text>
            <text x="596" y="38" className="nz-mg-wires__svgLabel" textAnchor="middle">{t('Ignition')}</text>
            <rect x="26" y="56" width="44" height="228" rx="12" fill="url(#nz-mg-loom)" stroke="rgba(255,255,255,.08)" />
            <rect x="570" y="56" width="44" height="228" rx="12" fill="url(#nz-mg-loom)" stroke="rgba(255,255,255,.08)" />
            {[0, 1, 2, 3, 4, 5, 6, 7].map((k) => (
              <g key={k} opacity=".5">
                <line x1="28" x2="68" y1={70 + k * 28} y2={78 + k * 28} stroke="rgba(0,0,0,.5)" strokeWidth="2" />
                <line x1="572" x2="612" y1={78 + k * 28} y2={70 + k * 28} stroke="rgba(0,0,0,.5)" strokeWidth="2" />
              </g>
            ))}

            {/* right ends (ignition) */}
            {puzzle.right.map((c, j) => {
              const used = usedRight.includes(j);
              const hover = drag ? nearestRight(drag.x, drag.y) === j : false;
              return (
                <g key={`r${j}`} className={`nz-mg-wires__end${used ? ' is-used' : ''}${hover ? ' is-target' : ''}`}>
                  <Cable d={looseRight(j)} colour={c} />
                  {!used && <Copper x={RIGHT_TIP} y={ROWS[j]} side="right" hot={hover} />}
                  {!used && (picked !== null || drag) && (
                    <circle className="nz-mg-wires__ring" cx={RIGHT_TIP + 6} cy={ROWS[j]} r={16} />
                  )}
                  <text x={RIGHT_TIP + 46} y={ROWS[j] - 14} className="nz-mg-wires__num">{j + 1}</text>
                </g>
              );
            })}

            {/* spliced pairs: the joint and its teal heat-shrink sleeve */}
            {spliced.map((j, i) => {
              if (j === null) return null;
              const { d, mid } = joint(i, j);
              return (
                <g key={`s${i}`} className="nz-mg-wires__joint">
                  <Cable d={d} colour={puzzle.left[i]} width={8} />
                  <g transform={`translate(${mid.x} ${mid.y}) rotate(${mid.angle})`}>
                    <rect x="-22" y="-8" width="44" height="16" rx="5" className="nz-mg-wires__sleeve" />
                    <rect x="-22" y="-8" width="44" height="5" rx="3" fill="rgba(255,255,255,.18)" />
                  </g>
                </g>
              );
            })}

            {/* left ends (battery) */}
            {puzzle.left.map((c, i) => {
              const isSpliced = spliced[i] !== null;
              const active = drag?.from === i || picked === i;
              return (
                <g
                  key={`l${i}`}
                  className={`nz-mg-wires__end is-left${isSpliced ? ' is-used' : ''}${active ? ' is-active' : ''}`}
                  onPointerDown={onLeftDown(i)}
                >
                  <Cable d={looseLeft(i)} colour={c} />
                  {!isSpliced && !active && <Copper x={LEFT_TIP} y={ROWS[i]} side="left" />}
                  {!isSpliced && <rect x={LEFT_TIP - 60} y={ROWS[i] - 18} width={74} height={36} fill="transparent" />}
                  <text x={LEFT_TIP - 72} y={ROWS[i] - 14} className="nz-mg-wires__num">{i + 1}</text>
                </g>
              );
            })}

            {/* the end being dragged */}
            {drag && (
              <g className="nz-mg-wires__drag">
                <Cable
                  d={`M ${LEFT_TIP - 30} ${ROWS[drag.from]} C ${LEFT_TIP + 40} ${ROWS[drag.from]}, ${drag.x - 60} ${drag.y}, ${drag.x - 28} ${drag.y}`}
                  colour={puzzle.left[drag.from]}
                />
                <Copper x={drag.x + 2} y={drag.y} side="left" hot />
              </g>
            )}

            {sparks.map((s) => (
              <g key={s.id} className="nz-mg-wires__spark" transform={`translate(${s.x} ${s.y})`}>
                <circle r="14" className="nz-mg-wires__flash" />
                {Array.from({ length: 12 }, (_, k) => {
                  const a = (k / 12) * Math.PI * 2 + (k % 2) * 0.2;
                  const r1 = 6;
                  const r2 = 16 + (k % 3) * 8;
                  return (
                    <line
                      key={k}
                      x1={Math.cos(a) * r1}
                      y1={Math.sin(a) * r1}
                      x2={Math.cos(a) * r2}
                      y2={Math.sin(a) * r2}
                      className={k % 2 ? 'is-hot' : undefined}
                    />
                  );
                })}
              </g>
            ))}
          </svg>
          {help && (
            <HelpCard
              className="nz-mg-wires__help"
              title={t('Hotwiring')}
              steps={[
                t('Drag a battery wire (left) onto the ignition wire (right) of the same colour.'),
                t('Or press its number 1-3, then the number of the right end.'),
                t('A wrong contact sparks. {count} shorts and the ignition is dead.', { count: MAX_SHORTS }),
                t('Splice all three pairs and the engine starts.'),
              ]}
            />
          )}
        </div>
        <div className={`nz-mg-wires__status is-${status}`} role="status">
          {statusText}
        </div>
      </Window>
      <PromptBar
        items={[
          { keys: ['Mouse'], label: t('Drag'), active: !!drag },
          { keys: ['1', '2', '3'], label: t('Pick a wire'), active: picked !== null },
          { keys: ['H'], label: help ? t('Hide help') : t('Help'), active: help },
          { keys: ['Escape'], label: t('Close') },
        ]}
      />
    </>
  );
}
