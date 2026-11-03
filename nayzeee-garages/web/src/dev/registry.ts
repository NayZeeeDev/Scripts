/**
 * Browser-only mock registry. Each src/dev/mocks/<area>.ts file registers named scenarios
 * (registerMock) and mock NUI callback answers (mockNui from lib/nui).
 * Open a scenario with ?mock=<id> or from the dev panel.
 */
import type { NuiMessage } from '../lib/types';
import { emitNuiMessage } from '../lib/nui';

export interface MockScenario {
  /** Unique id, used in the URL: ?mock=garage-grid */
  id: string;
  /** Group shown in the dev panel, e.g. 'Garage' */
  group: string;
  label: string;
  /** Messages dispatched (in order) when the scenario is opened. */
  messages: NuiMessage[];
}

export const scenarios: MockScenario[] = [];

export function registerMock(s: MockScenario) {
  const i = scenarios.findIndex((x) => x.id === s.id);
  if (i >= 0) scenarios[i] = s;
  else scenarios.push(s);
}

export function openScenario(id: string) {
  const s = scenarios.find((x) => x.id === id);
  if (!s) return;
  emitNuiMessage({ action: 'close', data: {} });
  emitNuiMessage({ action: 'hud', data: null });
  emitNuiMessage({ action: 'prompt', data: null });
  emitNuiMessage({ action: 'hint', data: null });
  setTimeout(() => s.messages.forEach((m) => emitNuiMessage(m)), 30);
}
