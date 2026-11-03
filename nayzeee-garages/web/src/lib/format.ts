/**
 * Formatting helpers. All read interface settings from the store at call time.
 */
import { useUi } from './store';
import { t } from './i18n';

const settings = () => useUi.getState().settings;

/** $50,000 (currency symbol from settings). */
export function money(n: number | null | undefined): string {
  const v = Math.round(Number(n) || 0);
  const sign = v < 0 ? '-' : '';
  return `${sign}${settings().currency}${Math.abs(v).toLocaleString('en-US')}`;
}

/** Kilometres in, "17,622 mi" / "28,360 km" out (unit from settings). */
export function distance(km: number | null | undefined): string {
  const unit = settings().distanceUnit;
  const v = unit === 'mi' ? (Number(km) || 0) * 0.621371 : Number(km) || 0;
  return `${Math.round(v).toLocaleString('en-US')} ${unit}`;
}

/** Number value only, in the configured unit (for inputs). */
export function distanceValue(km: number): number {
  return settings().distanceUnit === 'mi' ? km * 0.621371 : km;
}

/** Convert a value typed in the configured unit back to km. */
export function toKm(value: number): number {
  return settings().distanceUnit === 'mi' ? value / 0.621371 : value;
}

export function percent(n: number | null | undefined): number {
  return Math.max(0, Math.min(100, Math.round(Number(n) || 0)));
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const MONTHS_SHORT = MONTHS.map((m) => m.slice(0, 3));

/** "Sep 23, 2026" */
export function date(unix: number | null | undefined): string {
  if (!unix) return '-';
  const d = new Date(unix * 1000);
  return `${MONTHS_SHORT[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

/** "September 25 at 12:30" */
export function dateTime(unix: number | null | undefined): string {
  if (!unix) return '-';
  const d = new Date(unix * 1000);
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return t('{month} {day} at {time}', { month: MONTHS[d.getMonth()], day: d.getDate(), time: `${hh}:${mm}` });
}

/** "in 118h 40m" style duration from hours. */
export function hoursLabel(hours: number | null | undefined): string {
  if (hours === null || hours === undefined) return '-';
  const total = Math.max(0, Math.round(hours * 60));
  const h = Math.floor(total / 60);
  const m = total % 60;
  if (h === 0) return `${m}m`;
  return m ? `${h}h ${m}m` : `${h}h`;
}

/** Seconds until a unix time (negative when in the past). */
export function secondsUntil(unix: number): number {
  return unix - Math.floor(Date.now() / 1000);
}

/** Build the image URL for a model using settings.interface.imageUrl. */
export function vehicleImageUrl(model: string | null | undefined): string | null {
  const s = settings();
  if (!s.showImages || !model) return null;
  // Config.VehicleOverrides can provide a full image URL instead of a model name.
  if (/^(https?|nui):\/\//i.test(model)) return model;
  return s.imageUrl.replace('{model}', encodeURIComponent(model.toLowerCase()));
}

/** Local fallback image bundled in web/public/vehicles/<model>.png */
export function localVehicleImage(model: string | null | undefined): string | null {
  if (!model || /^(https?|nui):\/\//i.test(model)) return null;
  return `./vehicles/${encodeURIComponent(model.toLowerCase())}.png`;
}
