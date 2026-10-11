import { ItemData } from '../typings/item';

export const Items: {
  [key: string]: ItemData | undefined;
} = {};

// labels for the browser preview only (`npm start`)
if (import.meta.env.DEV) {
  const dev: [string, string, boolean][] = [
    ['money', 'Money', true],
    ['sprunk', 'Sprunk', true],
    ['WEAPON_PISTOL', 'Pistol', false],
    ['burger', 'Burger', true],
    ['parachute', 'Parachute', false],
    ['phone', 'Phone', false],
    ['scrapmetal', 'Scrap Metal', true],
    ['lockpick', 'Lockpick', true],
  ];
  for (const [name, label, stack] of dev)
    Items[name] = { name, label, stack, usable: true, close: false, count: 0 };
}
