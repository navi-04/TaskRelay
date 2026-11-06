'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { api, ApiFail, errorMessage } from '@/lib/web/api';
import { useTheme } from '@/lib/web/theme';
import { FeedbackProvider } from './Feedback';

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

const TABS = [
  { href: '/today', label: 'Today', icon: '✓' },
  { href: '/calendar', label: 'Calendar', icon: '▦' },
  { href: '/sheet', label: 'Sheet', icon: '▤' },
  { href: '/review', label: 'Review', icon: '↺' },
  { href: '/search', label: 'Search', icon: '⌕' },
  { href: '/profile', label: 'Profile', icon: '◉' },
] as const;

/** Signed-in frame: checks the session (redirects to / when signed out), keeps the server's timezone in sync, shows the nav. */
export default function Shell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const path = usePathname();
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { toggle: toggleTheme } = useTheme();

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

  if (error)
    return (
      <main>
        <div className="banner" role="alert">{error}</div>
        <button onClick={() => location.reload()}>Retry</button>
      </main>
    );
  if (!me)
    return (
      <main aria-busy="true">
        <p className="muted">Loading…</p>
      </main>
    );

  return (
    <MeContext.Provider value={{ me, refresh }}>
      <FeedbackProvider>
        <header className="topbar">
          <span className="brand">
            <span className="brand-mark" aria-hidden="true">✓</span>TaskRelay
          </span>
          <div className="topbar-right">
            <nav className="tabs" aria-label="Main">
              {TABS.map((t) => (
                <Link key={t.href} href={t.href} aria-current={path === t.href ? 'page' : undefined}>
                  <span className="ico" aria-hidden="true">{t.icon}</span>
                  {t.label}
                </Link>
              ))}
            </nav>
            <button className="icon" aria-label="Switch between white and black theme" title="Switch theme" onClick={toggleTheme}>◐</button>
          </div>
        </header>
        <main>{children}</main>
      </FeedbackProvider>
    </MeContext.Provider>
  );
}
