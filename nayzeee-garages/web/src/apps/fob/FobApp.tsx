/** fob app (docs/V2_CHANGES.md G). Placeholder: built by the car lock UI wave. */
import { useApp } from '../../lib/store';

export function FobApp() {
  const app = useApp('fob');
  if (!app.open) return null;
  return null;
}
