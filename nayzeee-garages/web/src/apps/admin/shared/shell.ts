/**
 * Admin shell context — lets pages and modals talk to the AdminApp window.
 *
 * API
 * - useAdminShell(): AdminShell
 *     hidden          true while an in-world tool runs (admin:points). The admin window and
 *                     every overlay (modals included) are hidden by CSS automatically and stay
 *                     mounted — nothing to do in a page. (Gating a modal with
 *                     `open={open && !hidden}` still works but is no longer needed.)
 *     runInWorld(fn)  = runAway (shared/away.ts): hide the admin UI, await fn(), show it again
 *                     and return fn's result. For admin:points use requestPoints() directly.
 *     page            the current admin page.
 *     go(page)        switch page (same as clicking the sidebar).
 * - AdminShellContext  provider used by AdminApp only.
 */
import { createContext, useContext } from 'react';
import type { AdminPage } from '@/lib/types';
import { runAway, useAdminHidden } from './away';

export interface AdminShell {
  hidden: boolean;
  runInWorld: <T>(fn: () => Promise<T>) => Promise<T>;
  page: AdminPage;
  go: (page: AdminPage) => void;
}

type ShellBase = Omit<AdminShell, 'hidden'>;

const fallback: ShellBase = {
  runInWorld: runAway,
  page: 'garages',
  go: () => undefined,
};

export const AdminShellContext = createContext<ShellBase>(fallback);

export function useAdminShell(): AdminShell {
  const base = useContext(AdminShellContext);
  const hidden = useAdminHidden();
  return { ...base, hidden };
}
