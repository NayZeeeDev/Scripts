/**
 * Mock scenarios for the in-world HUD widgets: in-interface notifications, interaction prompt
 * and key hints. (These widgets never call Lua, so there are no mockNui handlers here.)
 * The 'notify' messages are what Lua sends while one of our windows holds NUI focus; at any
 * other time notifications go through the configured notify integration instead.
 */
import type { NuiMessage, Toast } from '../../lib/types';
import { registerMock } from '../registry';
import { legionSquare } from './garage';

const notify = (data: Toast): NuiMessage => ({ action: 'notify', data });

registerMock({
  id: 'hud-toasts',
  group: 'HUD',
  label: 'Notifications in the interface (4 types)',
  messages: [
    notify({ type: 'success', title: 'Vehicle renamed', message: 'Your Elegy Retro Custom is now called "Track toy".', duration: 9000 }),
    notify({ type: 'info', title: 'Waypoint set', message: 'Follow the route to Pillbox Hill Parking (1.2 mi).', duration: 10000 }),
    notify({ type: 'warning', title: 'Payment due soon', message: 'Your next finance payment of $4,250 is due in 6 hours.', duration: 11000 }),
    notify({ type: 'error', message: 'You do not have enough money in your bank account.', duration: 12000 }),
  ],
});

registerMock({
  id: 'hud-toasts-stack',
  group: 'HUD',
  label: 'Notifications in the interface (overflow, sticky, long text)',
  messages: [
    notify({ type: 'info', message: 'Garage menu opened.', duration: 3000 }),
    notify({ type: 'success', title: 'Transfer complete', message: 'Sent to Mirror Park Garage.', duration: 9000 }),
    notify({
      type: 'warning',
      title: 'Garage almost full',
      message:
        'Only one space is left in this garage. Vehicles stored after that will be suggested to the nearest garage with free spaces instead.',
      duration: 15000,
    }),
    notify({ type: 'error', title: 'Cannot drive', message: 'This vehicle is impounded until 18:30.', duration: 0 }),
    notify({ type: 'success', message: 'Nickname saved.', duration: 9000 }),
    notify({ type: 'info', title: 'Sixth notification', message: 'The oldest one is dropped (max 5).', duration: 9000 }),
  ],
});

// The case the in-interface layer exists for: a focused garage window covers most of the
// screen, so these would be hidden behind it if the notify resource drew them.
registerMock({
  id: 'hud-toasts-window',
  group: 'HUD',
  label: 'Notifications over an open garage window',
  messages: [
    { action: 'open', data: { app: 'garage', data: legionSquare() } },
    notify({ type: 'error', message: 'You do not have enough money in your bank account.', duration: 20000 }),
    notify({ type: 'success', title: 'Vehicle renamed', message: 'Your Elegy Retro Custom is now called "Track toy".', duration: 20000 }),
  ],
});

registerMock({
  id: 'hud-prompt',
  group: 'HUD',
  label: 'Interaction prompt',
  messages: [{ action: 'prompt', data: { key: 'E', label: 'Open garage' } }],
});

registerMock({
  id: 'hud-prompt-store',
  group: 'HUD',
  label: 'Interaction prompt (store, long key)',
  messages: [{ action: 'prompt', data: { key: 'Enter', label: 'Store vehicle in Legion Square Parking' } }],
});

registerMock({
  id: 'hud-hint-placement',
  group: 'HUD',
  label: 'Key hint: vehicle fine-tune',
  messages: [
    {
      action: 'hint',
      data: {
        title: 'Fine-tune vehicle position',
        keys: [
          { keys: ['W', 'A', 'S', 'D'], label: 'Move' },
          { keys: ['Scroll'], label: 'Rotate' },
          { keys: ['R'], label: 'Up' },
          { keys: ['F'], label: 'Down' },
          { keys: ['Shift'], label: 'Precise' },
          { keys: ['Enter'], label: 'Confirm' },
          { keys: ['Esc'], label: 'Cancel' },
        ],
      },
    },
  ],
});

registerMock({
  id: 'hud-hint-walk',
  group: 'HUD',
  label: 'Key hint: walk mode',
  messages: [
    {
      action: 'hint',
      data: {
        title: 'Walk around the interior',
        keys: [
          { keys: ['W', 'A', 'S', 'D'], label: 'Walk' },
          { keys: ['Shift'], label: 'Run' },
          { keys: ['E'], label: 'Back to editor' },
        ],
      },
    },
  ],
});

registerMock({
  id: 'hud-overview',
  group: 'HUD',
  label: 'Everything at once',
  messages: [
    { action: 'prompt', data: { key: 'E', label: 'Open garage' } },
    {
      action: 'hint',
      data: {
        keys: [
          { keys: ['←', '→'], label: 'Previous / next page' },
          { keys: ['G'], label: 'Garage panel' },
          { keys: ['F'], label: 'Leave' },
        ],
      },
    },
  ],
});
