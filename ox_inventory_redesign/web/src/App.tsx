import InventoryComponent from './components/inventory';
import useNuiEvent from './hooks/useNuiEvent';
import { Items } from './store/items';
import { Locale } from './store/locale';
import { setImagePath } from './store/imagepath';
import { setupInventory } from './store/inventory';
import { Inventory } from './typings';
import { useAppDispatch } from './store';
import { debugData } from './utils/debugData';
import DragPreview from './components/utils/DragPreview';
import { fetchNui } from './utils/fetchNui';
import { useDragDropManager } from 'react-dnd';
import KeyPress from './components/utils/KeyPress';
import Bridge from './components/nz/Bridge';

debugData([
  {
    action: 'setupInventory',
    data: {
      leftInventory: {
        id: 'test',
        type: 'player',
        slots: 50,
        label: 'Ivan Wayne',
        weight: 10000,
        maxWeight: 24000,
        items: [
          { slot: 1, name: 'money', weight: 0, count: 4000 },
          { slot: 2, name: 'sprunk', weight: 350, count: 1, metadata: { rarity: 'uncommon' } },
          {
            slot: 3,
            name: 'WEAPON_PISTOL',
            weight: 1130,
            count: 1,
            metadata: { durability: 85, ammo: 12, serial: 'NZ-48213', components: [] },
          },
          {
            slot: 4,
            name: 'burger',
            weight: 220,
            count: 1,
            metadata: { rarity: 'epic', description: 'A juicy **double** cheeseburger.' },
          },
          { slot: 5, name: 'parachute', weight: 8000, count: 1, metadata: { rarity: 'legendary' } },
          { slot: 6, name: 'phone', weight: 190, count: 1 },
          { slot: 7, name: 'scrapmetal', weight: 80, count: 1, metadata: { rarity: 'rare' } },
        ],
      },
      rightInventory: {
        id: 'newdrop',
        type: 'newdrop',
        slots: 50,
        weight: 0,
        maxWeight: 24000,
        items: [],
      },
    },
  },
  {
    action: 'nz:player',
    data: { name: 'Ivan Wayne', id: 2, wallet: 4000, bank: 140010186, job: 'Unemployed' },
  },
]);

const App: React.FC = () => {
  const dispatch = useAppDispatch();
  const manager = useDragDropManager();

  useNuiEvent<{
    locale: { [key: string]: string };
    items: typeof Items;
    leftInventory: Inventory;
    imagepath: string;
  }>('init', ({ locale, items, leftInventory, imagepath }) => {
    for (const name in locale) Locale[name] = locale[name];
    for (const name in items) Items[name] = items[name];

    setImagePath(imagepath);
    dispatch(setupInventory({ leftInventory }));
  });

  fetchNui('uiLoaded', {});

  useNuiEvent('closeInventory', () => {
    manager.dispatch({ type: 'dnd-core/END_DRAG' });
  });

  return (
    <div className="app-wrapper">
      <Bridge />
      <InventoryComponent />
      <DragPreview />
      <KeyPress />
    </div>
  );
};

addEventListener('dragstart', function (event) {
  event.preventDefault();
});

export default App;
