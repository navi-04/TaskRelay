'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, errorMessage } from './api';

export interface ApiState<T> {
  /** The last successfully loaded value. Kept while a new request (e.g. another date) is loading. */
  data: T | undefined;
  error: string | null;
  loading: boolean;
  reload: () => Promise<void>;
}

/**
 * GET `path` and keep it in state; `null` disables the request. Reloads when `path` changes, ignores out-of-order
 * responses, and keeps showing the previous data (with `loading` true) instead of flashing empty.
 */
export function useApi<T>(path: string | null): ApiState<T> {
  const [data, setData] = useState<T>();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(path != null);
  const latest = useRef(0);

  const load = useCallback(async () => {
    if (path == null) return;
    const mine = ++latest.current;
    try {
      const d = await api<T>(path);
      if (mine !== latest.current) return;
      setData(d);
      setError(null);
    } catch (e) {
      if (mine === latest.current) setError(errorMessage(e));
    } finally {
      if (mine === latest.current) setLoading(false);
    }
  }, [path]);

  useEffect(() => {
    if (path == null) return;
    setLoading(true);
    void load();
  }, [path, load]);

  return { data, error, loading, reload: load };
}
