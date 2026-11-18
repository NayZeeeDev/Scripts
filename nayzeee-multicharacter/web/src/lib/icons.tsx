import type { LucideIcon, LucideProps } from 'lucide-react';
import {
  Anchor, Aperture, Armchair, Briefcase, Building, Building2, Camera, Car, Cat, CloudMoon, Coffee, Cross, Crosshair, Dog,
  Dumbbell, Flame, Globe, Hand, Heart, HeartHandshake, Helicopter, House, MapPin, Moon, PawPrint, Plane, Repeat, Shield,
  ShieldCheck, ShoppingBag, Smartphone, Smile, Sparkles, Star, Store, Sun, Sunset, TreePalm, TreePine, User, Users, Waves,
  Wrench, Swords, Target, Zap, Music, Mountain, Gem, Crown, Wind,
} from 'lucide-react';

const MAP: Record<string, LucideIcon> = {
  anchor: Anchor, aperture: Aperture, armchair: Armchair, briefcase: Briefcase, building: Building, 'building-2': Building2,
  camera: Camera, car: Car, cat: Cat, 'cloud-moon': CloudMoon, coffee: Coffee, crosshair: Crosshair, dog: Dog,
  dumbbell: Dumbbell, flame: Flame, globe: Globe, hand: Hand, heart: Heart, 'heart-handshake': HeartHandshake,
  helicopter: Helicopter, house: House, home: House, 'map-pin': MapPin, pin: MapPin, moon: Moon, paw: PawPrint,
  'paw-print': PawPrint, plane: Plane, repeat: Repeat, shield: Shield, 'shield-check': ShieldCheck,
  'shopping-bag': ShoppingBag, smartphone: Smartphone, smile: Smile, sparkles: Sparkles, star: Star, store: Store,
  sun: Sun, sunset: Sunset, user: User, users: Users, waves: Waves, wrench: Wrench, swords: Swords, target: Target,
  zap: Zap, wind: Wind, music: Music, mountain: Mountain, gem: Gem, crown: Crown,
  // spawn icon names (config/spawns.lua)
  city: Building2, beach: TreePalm, tree: TreePine, medical: Cross,
  // pet kinds
  smalldog: PawPrint,
};

export function iconFor(name?: string, fallback: LucideIcon = Sparkles): LucideIcon {
  if (!name) return fallback;
  return MAP[name] || MAP[name.toLowerCase()] || fallback;
}

export function Icon({ name, fallback, ...p }: { name?: string; fallback?: LucideIcon } & LucideProps) {
  const C = iconFor(name, fallback);
  return <C {...p} />;
}

// ── Brand marks (lucide ships no brand icons) ──────────────────────────────
const BRAND: Record<string, string> = {
  discord: 'M20.3 4.4A19.6 19.6 0 0 0 15.4 3l-.6 1.3a18 18 0 0 0-5.6 0L8.6 3a19.5 19.5 0 0 0-4.9 1.5C.6 9.2-.3 13.8.2 18.3a19.8 19.8 0 0 0 6 3l1.3-2a12.8 12.8 0 0 1-2-1l.5-.4a14.1 14.1 0 0 0 12 0l.5.4c-.6.4-1.3.7-2 1l1.3 2a19.7 19.7 0 0 0 6-3c.5-5.2-.9-9.8-3.6-13.9ZM8 15.6c-1.2 0-2.1-1.1-2.1-2.4S6.8 10.8 8 10.8s2.2 1.1 2.1 2.4c0 1.3-.9 2.4-2.1 2.4Zm8 0c-1.2 0-2.1-1.1-2.1-2.4s.9-2.4 2.1-2.4 2.2 1.1 2.1 2.4c0 1.3-.9 2.4-2.1 2.4Z',
  youtube: 'M23.5 6.2a3 3 0 0 0-2.1-2.1C19.5 3.6 12 3.6 12 3.6s-7.5 0-9.4.5A3 3 0 0 0 .5 6.2 31 31 0 0 0 0 12a31 31 0 0 0 .5 5.8 3 3 0 0 0 2.1 2.1c1.9.5 9.4.5 9.4.5s7.5 0 9.4-.5a3 3 0 0 0 2.1-2.1A31 31 0 0 0 24 12a31 31 0 0 0-.5-5.8ZM9.6 15.6V8.4l6.2 3.6-6.2 3.6Z',
  tiktok: 'M16.6 5.8A4.3 4.3 0 0 1 15.5 3h-3.3v12.4a2.6 2.6 0 0 1-2.6 2.5 2.6 2.6 0 0 1-2.6-2.6 2.6 2.6 0 0 1 3.4-2.5V9.5a6 6 0 0 0-6.8 5.9 6 6 0 0 0 6 6 6 6 0 0 0 6-6V9.1a7.6 7.6 0 0 0 4.4 1.4V7.2s-1.9.1-3.4-1.4Z',
  twitch: 'M4.3 2 3 5.4v13.5h4.6V22h2.6l3.1-3.1h3.7L22 13.9V2H4.3Zm15.6 10.9-2.9 2.9h-4.6l-2.6 2.6v-2.6H5.9V4.1h14v8.8ZM17 6.9h-2.1v5.6H17V6.9Zm-5.6 0H9.3v5.6h2.1V6.9Z',
  x: 'M18.2 2.3h3.4l-7.4 8.4 8.7 11.5h-6.8l-5.3-7-6.1 7H1.3l7.9-9L.9 2.3h7l4.8 6.4 5.5-6.4Zm-1.2 17.9h1.9L7 4.2H5l12 16Z',
  instagram: 'M12 2.2c3.2 0 3.6 0 4.8.1 3.3.1 4.8 1.7 4.9 4.9.1 1.3.1 1.6.1 4.8s0 3.6-.1 4.8c-.1 3.2-1.7 4.8-4.9 4.9-1.3.1-1.6.1-4.8.1s-3.6 0-4.8-.1c-3.3-.1-4.8-1.7-4.9-4.9C2.2 15.6 2.2 15.2 2.2 12s0-3.6.1-4.8C2.4 3.9 3.9 2.4 7.2 2.3c1.2-.1 1.6-.1 4.8-.1ZM12 0C8.7 0 8.3 0 7.1.1 2.7.3.3 2.7.1 7.1 0 8.3 0 8.7 0 12s0 3.7.1 4.9c.2 4.4 2.6 6.8 7 7 1.2.1 1.6.1 4.9.1s3.7 0 4.9-.1c4.4-.2 6.8-2.6 7-7 .1-1.2.1-1.6.1-4.9s0-3.7-.1-4.9c-.2-4.4-2.6-6.8-7-7C15.7 0 15.3 0 12 0Zm0 5.8a6.2 6.2 0 1 0 0 12.4 6.2 6.2 0 0 0 0-12.4ZM12 16a4 4 0 1 1 0-8 4 4 0 0 1 0 8Zm6.4-11.8a1.4 1.4 0 1 0 0 2.9 1.4 1.4 0 0 0 0-2.9Z',
};

export function SocialIcon({ name, size = 16, className }: { name: string; size?: number; className?: string }) {
  const d = BRAND[name];
  if (d) return <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" className={className}><path d={d} /></svg>;
  const C = name === 'store' ? Store : Globe;
  return <C size={size} className={className} strokeWidth={1.8} />;
}
