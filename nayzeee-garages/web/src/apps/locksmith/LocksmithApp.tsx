/**
 * Locksmith app (docs/CARLOCK.md). Placeholder: implemented by the car lock UI task.
 */
import { useApp } from '../../lib/store';

export function LocksmithApp() {
  const app = useApp('locksmith');
  if (!app.open) return null;
  return null;
}
