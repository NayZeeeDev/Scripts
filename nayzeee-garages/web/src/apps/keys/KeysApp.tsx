/**
 * Key ring app (docs/CARLOCK.md). Placeholder: implemented by the car lock UI task.
 */
import { useApp } from '../../lib/store';

export function KeysApp() {
  const app = useApp('keys');
  if (!app.open) return null;
  return null;
}
