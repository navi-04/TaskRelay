'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';
import { api, errorMessage } from '@/lib/web/api';

export default function SignIn() {
  const router = useRouter();
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Already signed in? Skip the form.
  useEffect(() => {
    api('/me').then(() => router.replace('/today')).catch(() => undefined);
  }, [router]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const body = mode === 'register' ? { email, password, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone } : { email, password };
      await api(`/auth/${mode}`, { method: 'POST', body });
      router.replace('/today');
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <main style={{ maxWidth: 420, paddingTop: 64 }}>
      <h1 className="brand" style={{ fontSize: '1.8rem' }}>TaskRelay</h1>
      <p className="muted">Finish what you plan, one day at a time.</p>
      <form className="card" onSubmit={submit}>
        <h2>{mode === 'login' ? 'Sign in' : 'Create your account'}</h2>
        {error && <div className="banner" role="alert">{error}</div>}
        <label htmlFor="email">Email</label>
        <input id="email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <label htmlFor="password">Password {mode === 'register' && <span className="muted">(8+ characters)</span>}</label>
        <input
          id="password"
          type="password"
          autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
          required
          minLength={mode === 'register' ? 8 : 1}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        <div className="row" style={{ marginTop: 16 }}>
          <button className="primary grow" disabled={busy}>{busy ? 'Please wait…' : mode === 'login' ? 'Sign in' : 'Create account'}</button>
        </div>
        <p className="muted" style={{ marginBottom: 0 }}>
          {mode === 'login' ? 'New here? ' : 'Have an account? '}
          <button type="button" className="link" onClick={() => { setMode(mode === 'login' ? 'register' : 'login'); setError(null); }}>
            {mode === 'login' ? 'Create an account' : 'Sign in'}
          </button>
        </p>
      </form>
    </main>
  );
}
