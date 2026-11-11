/**
 * Minigame mocks (browser dev only). Scenarios (?mock=<id>):
 *   minigame-pins         the five-pin lock, centred (no door anchor)
 *   minigame-pins-door    the lock over a door handle on the left of the screen
 *   minigame-pins-seven   a seven-pin lock (lockpicking.pins = 7), low time left
 *   minigame-wires        hotwire: three pairs of wires behind the dash
 *   minigame-reader       the signal reader (reference 433.9 MHz / 212 deg)
 * minigame:finish answers like Lua: it logs the result, checks the answer like the server and
 * closes the app.
 */
import { registerMock } from '../registry';
import { emitNuiMessage, mockNui } from '../../lib/nui';
import { toast } from '../../lib/store';
import type { MinigameOpenData, NuiMessage } from '../../lib/types';

type Distribute<T> = T extends unknown ? Omit<T, 'token'> : never;
type MockData = Distribute<MinigameOpenData>;

let token = 100;
let current: MinigameOpenData | null = null;

const open = (data: MockData): NuiMessage => ({
  action: 'open',
  data: { app: 'minigame', data: { ...data, token: ++token } as MinigameOpenData },
});

function solved(d: MinigameOpenData, answer: unknown): boolean {
  if (d.game === 'pins') return Array.isArray(answer) && answer.join() === d.puzzle.order.join();
  if (d.game === 'wires') {
    if (!Array.isArray(answer) || answer.length !== 3) return false;
    return answer.every((j, i) => d.puzzle.right[Number(j) - 1] === d.puzzle.left[i]) && new Set(answer).size === 3;
  }
  const a = answer as { frequency?: number; phase?: number } | null;
  if (!a || typeof a.frequency !== 'number' || typeof a.phase !== 'number') return false;
  const dp = Math.abs((((a.phase - d.puzzle.phase + 180) % 360) + 360) % 360 - 180);
  return Math.abs(a.frequency - d.puzzle.frequency) <= d.puzzle.tolerance.frequency && dp <= d.puzzle.tolerance.phase;
}

mockNui('minigame:ready', () => null);
mockNui('minigame:started', (req) => {
  console.info(`[minigame] started token=${req.token} ok=${req.ok}`);
  return null;
});
mockNui('minigame:finish', (req) => {
  console.info('[minigame] finish', JSON.stringify(req));
  const d = current;
  if (d && req.success) {
    const ok = solved(d, req.answer);
    toast({ type: ok ? 'success' : 'error', message: ok ? 'Server: answer accepted' : 'Server: wrong answer' });
  } else if (req.snapped) {
    toast({ type: 'error', message: 'Your lockpick snapped' });
  } else {
    toast({ type: 'info', message: req.cancelled ? 'You stopped' : 'Failed' });
  }
  setTimeout(() => emitNuiMessage({ action: 'close', data: { app: 'minigame' } }), 50);
  return null;
});

function scenario(id: string, label: string, data: MockData) {
  registerMock({
    id,
    group: 'Minigames',
    label,
    get messages() {
      const msg = open(data);
      current = (msg.data as { data: MinigameOpenData }).data;
      return [msg];
    },
  });
}

const vehicle = { label: 'Karin Sultan RS', plate: '46EEK572' };

scenario('minigame-pins', 'Lock pick (centred)', {
  game: 'pins',
  puzzle: { pins: 5, order: [3, 1, 5, 2, 4], heights: [0.62, 0.35, 0.84, 0.48, 0.71] },
  snapChance: 35,
  anchor: null,
  timeLimit: 85,
  vehicle,
});

scenario('minigame-pins-door', 'Lock pick (over the door)', {
  game: 'pins',
  puzzle: { pins: 5, order: [2, 4, 1, 5, 3], heights: [0.4, 0.8, 0.55, 0.3, 0.9] },
  snapChance: 35,
  anchor: { x: 0.31, y: 0.44 },
  timeLimit: 85,
  vehicle: { label: 'Pegassi Zentorno', plate: 'NZ 4419' },
});

scenario('minigame-pins-seven', 'Lock pick (seven pins)', {
  game: 'pins',
  puzzle: { pins: 7, order: [7, 2, 5, 1, 6, 3, 4], heights: [0.5, 0.75, 0.3, 0.88, 0.42, 0.66, 0.25] },
  snapChance: 60,
  anchor: { x: 0.7, y: 0.5 },
  timeLimit: 14,
  vehicle,
});

scenario('minigame-wires', 'Hotwire (wires)', {
  game: 'wires',
  puzzle: { left: ['red', 'yellow', 'blue'], right: ['blue', 'red', 'yellow'] },
  timeLimit: 85,
  vehicle,
});

scenario('minigame-reader', 'Hotwire (signal reader)', {
  game: 'reader',
  puzzle: { frequency: 433.9, phase: 212, tolerance: { frequency: 1.5, phase: 8 } },
  timeLimit: 85,
  vehicle: { label: 'Obey 10F Widebody', plate: 'LUX 001' },
});
