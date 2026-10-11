import type { Rarity } from './ui';
import type { Slot } from '../typings';

export const RARITIES: Rarity[] = ['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic'];

export const RarityMap: Record<string, Rarity> = {};

export const setRarityMap = (map?: Record<string, string>) => {
  if (!map) return;
  for (const name in map) {
    const value = map[name]?.toLowerCase() as Rarity;
    if (RARITIES.includes(value)) RarityMap[name] = value;
  }
};

export const getRarity = (item: Pick<Slot, 'name' | 'metadata'>): Rarity => {
  const fromMeta = item.metadata?.rarity?.toString().toLowerCase();
  if (fromMeta && RARITIES.includes(fromMeta)) return fromMeta as Rarity;
  return (item.name && RarityMap[item.name]) || 'common';
};
