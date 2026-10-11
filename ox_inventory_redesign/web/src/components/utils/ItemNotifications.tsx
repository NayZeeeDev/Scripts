import React, { useContext, useRef } from 'react';
import { createPortal } from 'react-dom';
import { TransitionGroup } from 'react-transition-group';
import useNuiEvent from '../../hooks/useNuiEvent';
import useQueue from '../../hooks/useQueue';
import { Locale } from '../../store/locale';
import { getItemUrl } from '../../helpers';
import { SlotWithItem } from '../../typings';
import { Items } from '../../store/items';
import Fade from './transitions/Fade';
import { getRarity } from '../../store/rarity';
import { useAppSelector } from '../../store';

interface ItemNotificationProps {
  item: SlotWithItem;
  text: string;
  action: string;
  count?: number;
}

export const ItemNotificationsContext = React.createContext<{
  add: (item: ItemNotificationProps) => void;
} | null>(null);

export const useItemNotifications = () => {
  const itemNotificationsContext = useContext(ItemNotificationsContext);
  if (!itemNotificationsContext) throw new Error(`ItemNotificationsContext undefined`);
  return itemNotificationsContext;
};

const FALLBACK: Record<string, string> = {
  ui_added: 'Added',
  ui_removed: 'Removed',
  ui_equipped: 'Equipped',
  ui_holstered: 'Holstered',
};

const label = (key: string) => Locale[key] || FALLBACK[key] || key;

const tone = (action: string) =>
  action === 'ui_removed' ? 'is-removed' : action === 'ui_added' ? 'is-added' : 'is-neutral';

const ItemNotification: React.FC<{ item: ItemNotificationProps; modern: boolean }> = ({ item, modern }) => {
  const slotItem = item.item;
  const itemLabel = slotItem.metadata?.label || Items[slotItem.name]?.label || slotItem.name;
  const image = `url(${getItemUrl(slotItem) || 'none'})`;
  const rarity = getRarity(slotItem);

  if (modern) {
    return (
      <div className={`nz-notify-modern ${tone(item.action)}`} data-rarity={rarity}>
        <div className="nz-notify-text">
          <span>{item.text}</span>
          <p>{itemLabel}</p>
        </div>
        <div className="nz-notify-thumb" style={{ backgroundImage: image }} />
      </div>
    );
  }

  return (
    <div className={`nz-notify-card ${tone(item.action)}`}>
      <div className="nz-slot" data-rarity={rarity}>
        <div className="nz-slot-content">
          <div className="nz-slot-image" style={{ backgroundImage: image }} />
          <div className="nz-notify-action">{item.text}</div>
          <div className="nz-slot-footer">
            <span className="nz-slot-label">{itemLabel}</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export const ItemNotificationsProvider = ({ children }: { children: React.ReactNode }) => {
  const modern = useAppSelector((state) => state.ui.settings.notifyStyle === 'modern');
  const counter = useRef(0);
  const queue = useQueue<{
    id: number;
    item: ItemNotificationProps;
  }>();

  const add = (item: ItemNotificationProps) => {
    queue.add({ id: ++counter.current, item });
    setTimeout(() => queue.remove(), 2600);
  };

  useNuiEvent<[item: SlotWithItem, text: string, count?: number]>('itemNotify', ([item, text, count]) => {
    add({ item, action: text, count, text: count ? `${label(text)} ${count}x` : label(text) });
  });

  return (
    <ItemNotificationsContext.Provider value={{ add }}>
      {children}
      {createPortal(
        <TransitionGroup className={`nz-notify-container ${modern ? 'is-modern' : 'is-default'}`}>
          {queue.values.map((notification) => (
            <Fade key={`item-notification-${notification.id}`}>
              <ItemNotification item={notification.item} modern={modern} />
            </Fade>
          ))}
        </TransitionGroup>,
        document.body
      )}
    </ItemNotificationsContext.Provider>
  );
};
