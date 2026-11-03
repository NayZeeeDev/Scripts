/**
 * Admin shell context — lets pages and modals talk to the AdminApp window.
 *
 * API
 * - useAdminShell(): AdminShell
 *     hidden          true while an in-world tool runs (admin:points): the admin window AND
 *                     every admin modal must be invisible. Modals: `open={open && !hidden}`
 *                     (keep your component mounted so its state survives).
 *     runInWorld(fn)  hide the admin UI, await fn() (e.g. request('admin:points', …)), show it
 *                     again and return fn's result. Nested calls are counted.
 *     page            the current admin page.
 *     go(page)        switch page (same as clicking the sidebar).
 * - AdminShellContext  provider used by AdminApp only.
 */
import { createContext, useContext } from 'react';
import type { AdminPage } from '@/lib/types';

export interface AdminShell {
  hidden: boolean;
  runInWorld: <T>(fn: () => Promise<T>) => Promise<T>;
  page: AdminPage;
  go: (page: AdminPage) => void;
}

const fallback: AdminShell = {
  hidden: false,
  runInWorld: (fn) => fn(),
  page: 'garages',
  go: () => undefined,
};

export const AdminShellContext = createContext<AdminShell>(fallback);

export function useAdminShell(): AdminShell {
  return useContext(AdminShellContext);
}
