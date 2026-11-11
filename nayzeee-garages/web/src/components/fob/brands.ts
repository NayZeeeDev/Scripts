/**
 * Vehicle makes -> brand logo slugs (web/public/brands/<slug>.glb, badge png/<slug>.png).
 * The logos are the 402 Studio "GTA V 3D logos" pack; SOURCES.txt and USAGE.txt must stay
 * next to them (the pack's terms). Re-render the badges with `node tools/brand-badges.mjs`.
 *
 * brandSlug() accepts what the game and our data give: GetMakeNameFromVehicleModel label keys
 * ('DINKA', 'UBERMACH', 'ZIRCONIU' — often cut to 8 characters), their translated labels
 * ('Dinka', 'Übermacht', 'Vom Feuer', 'Bürgerfahrzeug'), slugs ('vom-feuer') and VehicleLabel.make.
 */

export const BRAND_SLUGS = [
  'albany', 'annis', 'benefactor', 'bf', 'bollokan', 'bravado', 'brute', 'buckingham', 'canis', 'chariot',
  'cheval', 'classique', 'coil', 'declasse', 'dewbauchee', 'dinka', 'dundreary', 'eberhard', 'emperor', 'enus',
  'fathom', 'gallivanter', 'grotti', 'hijak', 'hvy', 'imponte', 'invetero', 'jack-sheepe', 'jobuilt', 'karin',
  'kraken', 'lampadati', 'lcc', 'maibatsu', 'mammoth', 'maxwell', 'mtl', 'nagasaki', 'obey', 'ocelot',
  'overflod', 'pegassi', 'penaud', 'pfister', 'principe', 'progen', 'rune', 'schyster', 'shitzu', 'speedophile',
  'stanley', 'steel-horse', 'toundra', 'truffade', 'ubermacht', 'vapid', 'vom-feuer', 'vulcar', 'vysser', 'weeny',
  'western-motorcycle', 'western', 'willard', 'zirconium',
] as const;

export type BrandSlug = (typeof BRAND_SLUGS)[number];

/** Lower case, accents removed (Ü -> u, Ö -> o), only letters and digits. */
export function normalizeMake(make: string): string {
  return make
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/ß/g, 'ss')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

/** Spellings that are not a prefix of the slug (label keys, full names, common misspellings). */
const ALIASES: Record<string, BrandSlug> = {
  burgerfahrzeug: 'bf',
  buergerfahrzeug: 'bf',
  inverto: 'invetero',
  invertero: 'invetero',
  lampada: 'lampadati',
  joebuilt: 'jobuilt',
  libertycitycycles: 'lcc',
  libertycity: 'lcc',
  westernmotorcyclecompany: 'western-motorcycle',
  westernmc: 'western-motorcycle',
  wmc: 'western-motorcycle',
  jacksheep: 'jack-sheepe',
  jacksheepe: 'jack-sheepe',
  jsheepe: 'jack-sheepe',
  steelhorsemotorcycles: 'steel-horse',
  dewbauch: 'dewbauchee',
  dewbachee: 'dewbauchee',
  vomfeur: 'vom-feuer',
  ubermach: 'ubermacht',
  uebermacht: 'ubermacht',
  hvygroup: 'hvy',
  heavy: 'hvy',
  mtlindustries: 'mtl',
  zirconiu: 'zirconium',
  schyter: 'schyster',
  grotticars: 'grotti',
  pfisterautomobile: 'pfister',
};

const BY_KEY = new Map<string, BrandSlug>(BRAND_SLUGS.map((s) => [normalizeMake(s), s]));
/** longest normalised slug first, so 'westernmotorcycle…' wins over 'western' */
const BY_LENGTH = [...BY_KEY.entries()].sort((a, b) => b[0].length - a[0].length);
const cache = new Map<string, BrandSlug | null>();

/** The logo slug of a vehicle make, or null when the pack has no logo for it. */
export function brandSlug(make: string | null | undefined): BrandSlug | null {
  if (typeof make !== 'string') return null;
  const raw = make.trim();
  if (!raw || raw.toUpperCase() === 'NULL' || raw === 'CARNOTFOUND') return null;
  const hit = cache.get(raw);
  if (hit !== undefined) return hit;
  const key = normalizeMake(raw);
  let slug: BrandSlug | null = BY_KEY.get(key) ?? ALIASES[key] ?? null;
  if (!slug && key.length >= 4) {
    // GTA label keys are often cut to 8 characters ('ZIRCONIU', 'STEELHOR', 'BUCKINGH')
    for (const [k, s] of BY_LENGTH) {
      if (k.startsWith(key) || key.startsWith(k)) {
        slug = s;
        break;
      }
    }
  }
  cache.set(raw, slug);
  return slug;
}

/** Transparent 256 px chrome badge (relative: the NUI is served from web/dist). */
export function brandBadgeUrl(slug: BrandSlug): string {
  return `./brands/png/${slug}.png`;
}

/** The 3D logo (meshopt compressed GLB). */
export function brandModelUrl(slug: BrandSlug): string {
  return `./brands/${slug}.glb`;
}

/** Display name of a slug ('vom-feuer' -> 'Vom Feuer'), for alt texts. */
export function brandName(slug: BrandSlug): string {
  if (slug === 'bf') return 'BF';
  if (slug === 'ubermacht') return 'Übermacht';
  if (slug === 'overflod') return 'Överflöd';
  if (slug === 'jobuilt') return 'JoBuilt';
  if (slug === 'hvy' || slug === 'mtl' || slug === 'lcc') return slug.toUpperCase();
  return slug.split('-').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}
