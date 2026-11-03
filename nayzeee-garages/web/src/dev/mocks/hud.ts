/**
 * Mock scenarios for the in-world HUD widgets: toasts, interaction prompt, key hints.
 * (These widgets never call Lua, so there are no mockNui handlers here.)
 */
import { registerMock } from '../registry';

registerMock({
  id: 'hud-toasts',
  group: 'HUD',
  label: 'Toasts (4 types)',
  messages: [
    {
      action: 'notify',
      data: { type: 'success', title: 'Vehicle stored', message: 'Your Elegy Retro Custom is parked at Legion Square.', duration: 9000 },
    },
    {
      action: 'notify',
      data: { type: 'info', title: 'Waypoint set', message: 'Follow the route to Pillbox Hill Parking (1.2 mi).', duration: 10000 },
    },
    {
      action: 'notify',
      data: { type: 'warning', title: 'Payment due soon', message: 'Your next finance payment of $4,250 is due in 6 hours.', duration: 11000 },
    },
    { action: 'notify', data: { type: 'error', message: 'You do not have enough money in your bank account.', duration: 12000 } },
  ],
});

registerMock({
  id: 'hud-toasts-stack',
  group: 'HUD',
  label: 'Toasts (overflow, sticky, long text)',
  messages: [
    { action: 'notify', data: { type: 'info', message: 'Garage menu opened.', duration: 3000 } },
    { action: 'notify', data: { type: 'success', title: 'Transfer complete', message: 'Sent to Mirror Park Garage.' } },
    {
      action: 'notify',
      data: {
        type: 'warning',
        title: 'Garage almost full',
        message:
          'Only one space is left in this garage. Vehicles stored after that will be suggested to the nearest garage with free spaces instead.',
        duration: 15000,
      },
    },
    { action: 'notify', data: { type: 'error', title: 'Cannot drive', message: 'This vehicle is impounded until 18:30.', duration: 0 } },
    { action: 'notify', data: { type: 'success', message: 'Nickname saved.' } },
    { action: 'notify', data: { type: 'info', title: 'Sixth toast', message: 'The oldest one is dropped (max 5).' } },
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
    { action: 'notify', data: { type: 'success', title: 'Welcome home', message: 'Mirror Park Garage · 6 of 12 spaces used.', duration: 20000 } },
  ],
});
