/**
 * Mock scenarios for the in-world HUD widgets: interaction prompt and key hints.
 * (These widgets never call Lua, so there are no mockNui handlers here. Notifications are
 * not part of the interface: they go through the configured notify integration in Lua.)
 */
import { registerMock } from '../registry';

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
