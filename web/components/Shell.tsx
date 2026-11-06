'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { api, ApiFail, errorMessage } from '@/lib/web/api';

export interface Me {
  id: string;
  email: string;
  timezone: string;
  ai_access_id: string;
  ai_access_enabled: boolean;
  ai_last_used_at: string | null;
}

const MeContext = createContext<{ me: Me; refresh: () => Promise<void> } | null>(null);
export const useMe = () => {
  const ctx = useContext(MeContext);
  if (!ctx) throw new Error('useMe must be used inside <Shell>');
  return ctx;
};

/** Signed-in frame: checks the session (redirects to / when signed out), keeps the server's timezone in sync, shows the nav. */
export default function Shell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const path = usePathname();
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = async () => setMe(await api<Me>('/me'));

  useEffect(() => {
    api<Me>('/me')
      .then(async (m) => {
        // The server derives "today" from the user's timezone, so keep it equal to this device's.
        const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
        if (tz && tz !== m.timezone) return api<Me>('/me', { method: 'PATCH', body: { timezone: tz } }).catch(() => m);
        return m;
      })
      .then((m) => m && setMe(m))
      .catch((e) => {
        if (e instanceof ApiFail && e.status === 401) router.replace('/');
        else setError(errorMessage(e));
      });
  }, [router]);

  if (error) return <main><div className="banner">{error}</div><button onClick={() => location.reload()}>Retry</button></main>;
  if (!me) return <main><p className="muted">Loading…</p></main>;

  const link = (href: string, label: string) => (
    <Link href={href} aria-current={path === href ? 'page' : undefined}>{label}</Link>
  );

  return (
    <MeContext.Provider value={{ me, refresh }}>
      <header className="bar">
        <span className="brand">TaskRelay</span>
        <nav>{link('/today', 'Today')}{link('/profile', 'Profile')}</nav>
      </header>
      <main>{children}</main>
    </MeContext.Provider>
  );
}
