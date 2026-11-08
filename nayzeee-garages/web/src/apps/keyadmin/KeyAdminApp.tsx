/** keyadmin app (docs/V2_CHANGES.md G). Placeholder: built by the car lock UI wave. */
import { useApp } from '../../lib/store';

export function KeyAdminApp() {
  const app = useApp('keyadmin');
  if (!app.open) return null;
  return null;
}
