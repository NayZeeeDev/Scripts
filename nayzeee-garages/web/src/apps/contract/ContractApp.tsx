/**
 * Contract app (docs/CARLOCK.md). Placeholder: implemented by the car lock UI task.
 */
import { useApp } from '../../lib/store';

export function ContractApp() {
  const app = useApp('contract');
  if (!app.open) return null;
  return null;
}
