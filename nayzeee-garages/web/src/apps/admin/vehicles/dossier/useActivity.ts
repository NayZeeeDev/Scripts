/**
 * Paged activity log of one vehicle (admin:vehicle:activity). Keeps the newest page for the
 * Overview and the page the Activity tab shows; reload() after an edit refreshes both.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { request } from '@/lib/nui';
import type { Paged, VehicleActivity } from '@/lib/types';
import { asList } from './data';

export interface ActivityState {
  /** Page 1 (newest entries), null until loaded. */
  latest: Paged<VehicleActivity> | null;
  /** The page shown on the Activity tab. */
  current: Paged<VehicleActivity> | null;
  page: number;
  loading: boolean;
  error: string | null;
  setPage: (page: number) => void;
  reload: () => void;
}

/** Lua may send an empty rows table as {}. */
function normPaged(p: Paged<VehicleActivity>): Paged<VehicleActivity> {
  return {
    rows: asList<VehicleActivity>(p.rows),
    total: Number(p.total) || 0,
    page: Number(p.page) || 1,
    pageSize: Math.max(1, Number(p.pageSize) || 25),
  };
}

export function useActivity(plate: string | null): ActivityState {
  const [latest, setLatest] = useState<Paged<VehicleActivity> | null>(null);
  const [current, setCurrent] = useState<Paged<VehicleActivity> | null>(null);
  const [page, setPageState] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const seq = useRef(0);

  const load = useCallback(
    async (p: number) => {
      if (!plate) return;
      const id = ++seq.current;
      setLoading(true);
      setError(null);
      const res = await request('admin:vehicle:activity', { plate, page: p }, { toastError: false });
      if (id !== seq.current) return;
      setLoading(false);
      if (!res.ok) {
        setError(res.error);
        return;
      }
      const data = normPaged(res.data);
      setCurrent(data);
      if (p === 1) setLatest(data);
    },
    [plate],
  );

  // New plate (other vehicle or plate change): start again at page 1.
  useEffect(() => {
    setLatest(null);
    setCurrent(null);
    setPageState(1);
    void load(1);
  }, [load]);

  const setPage = useCallback(
    (p: number) => {
      setPageState(p);
      void load(p);
    },
    [load],
  );

  const reload = useCallback(() => {
    // Newest first: an edit adds an entry on page 1, so refresh it (and the shown page).
    if (page !== 1) {
      void (async () => {
        const res = await request('admin:vehicle:activity', { plate: plate ?? '', page: 1 }, { toastError: false });
        if (res.ok) setLatest(normPaged(res.data));
      })();
    }
    void load(page);
  }, [load, page, plate]);

  return { latest, current, page, loading, error, setPage, reload };
}
