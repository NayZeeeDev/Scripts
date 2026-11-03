/**
 * Owned copies (GroupInfo[]) of private garage locations, for the Private page cards, KPIs and
 * inspector.
 *
 * admin:groups is rate limited per admin on the server (300 ms) and the location editor's
 * "Owners & copies" tab calls it as soon as it mounts. So this loader asks for one location at
 * a time, at least GAP ms apart, never while `paused` (pass true while the editor is open), the
 * selected location first. `groupsCooldown()` says how long to wait before another
 * admin:groups call is safe (LocationListPage delays opening the editor by that much).
 *
 * API
 * - usePrivateGroups(ids, { enabled, paused, priority }) → { get(id), reload(id), complete }
 *     get(id): GroupInfo[] when loaded, 'error' when the request failed, undefined while loading.
 *     reload(id): forget the cached list and load it again (after the editor closed).
 *     complete: false when there are too many locations to load them all (only the selected
 *     one is loaded); totals over every location are not available then.
 * - groupsCooldown(): ms until the next admin:groups request is safe (0 = now).
 * Lists of more than MAX_PREFETCH locations only load the priority (selected) location.
 * Loaded lists are kept for TTL ms across visits of the page (module cache), so going back to
 * the Private page does not ask the server for every location again; reload(id) drops one.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { request } from '@/lib/nui';
import type { GroupInfo } from '@/lib/types';

const GAP = 380;
const MAX_PREFETCH = 40;
const TTL = 90_000;
let lastCall = -Infinity;

export function groupsCooldown(): number {
  return Math.max(0, lastCall + GAP - performance.now());
}

type Entry = GroupInfo[] | 'error';

/** Lists loaded recently (errors are not kept): reused by the next visit of the page. */
const recent = new Map<number, { list: GroupInfo[]; at: number }>();

function recentLists(): Record<number, Entry> {
  const now = performance.now();
  const out: Record<number, Entry> = {};
  recent.forEach((v, id) => {
    if (now - v.at < TTL) out[id] = v.list;
    else recent.delete(id);
  });
  return out;
}

export function usePrivateGroups(
  ids: number[],
  { enabled, paused, priority }: { enabled: boolean; paused: boolean; priority: number | null },
) {
  const [cache, setCache] = useState<Record<number, Entry>>(recentLists);
  const [wake, setWake] = useState(0);
  const inflight = useRef<number | null>(null);
  const alive = useRef(true);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const key = ids.join(',');

  useEffect(() => {
    if (!enabled || paused || inflight.current !== null) return;
    const want = (id: number) => cache[id] === undefined;
    let next: number | undefined;
    if (priority !== null && ids.includes(priority) && want(priority)) next = priority;
    else if (ids.length <= MAX_PREFETCH) next = ids.find(want);
    if (next === undefined) return;
    const wait = groupsCooldown();
    if (wait > 0) {
      const timer = window.setTimeout(() => setWake((n) => n + 1), wait + 10);
      return () => window.clearTimeout(timer);
    }
    const id = next;
    inflight.current = id;
    lastCall = performance.now();
    void request('admin:groups', { locationId: id }, { toastError: false }).then((res) => {
      inflight.current = null;
      const entry: Entry = res.ok ? (Array.isArray(res.data) ? (res.data as GroupInfo[]) : []) : 'error';
      if (entry !== 'error') recent.set(id, { list: entry, at: performance.now() });
      if (!alive.current) return;
      setCache((c) => ({ ...c, [id]: entry }));
    });
  }, [enabled, paused, priority, key, cache, wake]);

  const get = useCallback((id: number | null): Entry | undefined => (id === null ? undefined : cache[id]), [cache]);

  const reload = useCallback((id: number) => {
    recent.delete(id);
    setCache((c) => {
      if (c[id] === undefined) return c;
      const n = { ...c };
      delete n[id];
      return n;
    });
  }, []);

  return { get, reload, complete: ids.length <= MAX_PREFETCH };
}
