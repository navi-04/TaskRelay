'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useRef, useState, type FormEvent } from 'react';
import { useAsk, useToast } from '@/components/Feedback';
import { useMe } from '@/components/Shell';
import { ErrorBanner } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';

/** Password, data export, sign out, and the destructive actions. */
export default function AccountCard() {
  const router = useRouter();
  const { me } = useMe();
  const toast = useToast();
  const ask = useAsk();
  const [error, setError] = useState<string | null>(null);

  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [busy, setBusy] = useState(false);

  const deleteDialog = useRef<HTMLDialogElement>(null);
  const [deletePw, setDeletePw] = useState('');
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const signOut = () => api('/auth/logout', { method: 'POST' }).catch(() => undefined).then(() => router.replace('/'));

  async function changePassword(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (next !== again) return setError('The new passwords don’t match.');
    setBusy(true);
    try {
      await api('/me/password', { method: 'POST', body: { current_password: current, new_password: next } });
      setCurrent(''); setNext(''); setAgain('');
      toast('Password changed. Other devices were signed out.');
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function exportData() {
    try {
      const res = await fetch('/api/v1/me/export', { credentials: 'same-origin' });
      if (!res.ok) throw new Error((await res.json().catch(() => null))?.error?.message ?? 'Export failed');
      const url = URL.createObjectURL(await res.blob());
      const a = Object.assign(document.createElement('a'), { href: url, download: 'taskrelay-export.json' });
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function wipeTasks() {
    const choice = await ask({ title: 'Delete ALL your tasks?', message: 'Every task and its history is removed. Your account and settings stay. This cannot be undone.', choices: [{ id: 'yes', label: 'Delete all tasks', tone: 'danger' }] });
    if (!choice) return;
    try {
      await api('/me/data', { method: 'DELETE' });
      toast('All tasks deleted.');
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function deleteAccount(e: FormEvent) {
    e.preventDefault();
    setDeleteError(null);
    try {
      await api('/me', { method: 'DELETE', body: { password: deletePw } });
      router.replace('/');
    } catch (err) {
      setDeleteError(errorMessage(err));
    }
  }

  return (
    <>
      <section className="card" aria-labelledby="pw-h">
        <h2 id="pw-h">Password</h2>
        {error && <ErrorBanner message={error} />}
        <form onSubmit={changePassword}>
          <label htmlFor="pw-cur">Current password</label>
          <input id="pw-cur" type="password" autoComplete="current-password" required value={current} onChange={(e) => setCurrent(e.target.value)} />
          <label htmlFor="pw-new">New password (8+ characters)</label>
          <input id="pw-new" type="password" autoComplete="new-password" minLength={8} required value={next} onChange={(e) => setNext(e.target.value)} />
          <label htmlFor="pw-again">Repeat new password</label>
          <input id="pw-again" type="password" autoComplete="new-password" minLength={8} required value={again} onChange={(e) => setAgain(e.target.value)} />
          <div className="row" style={{ marginTop: 12 }}>
            <button className="primary" disabled={busy || !current || next.length < 8}>{busy ? 'Saving…' : 'Change password'}</button>
          </div>
        </form>
      </section>

      <section className="card" aria-labelledby="acc-h">
        <h2 id="acc-h">Account</h2>
        <p className="muted">{me.email} · {me.timezone}</p>
        <div className="row wrap">
          <button onClick={signOut}>Sign out</button>
          <button onClick={exportData}>Download my data</button>
        </div>
        <p className="muted small" style={{ marginBottom: 0 }}>
          <Link href="/privacy">Privacy policy</Link> · <Link href="/account-deletion">How deletion works</Link>
        </p>
      </section>

      <section className="card" aria-labelledby="danger-h">
        <h2 id="danger-h">Danger zone</h2>
        <div className="row wrap">
          <button className="danger" onClick={wipeTasks}>Delete all my tasks</button>
          <button className="danger" onClick={() => deleteDialog.current?.showModal()}>Delete my account</button>
        </div>
      </section>

      <dialog ref={deleteDialog} aria-labelledby="del-h">
        <form onSubmit={deleteAccount}>
          <h2 id="del-h">Delete your account?</h2>
          <p className="muted">This permanently deletes your account, tasks, history and settings. It cannot be undone. Enter your password to confirm.</p>
          {deleteError && <ErrorBanner message={deleteError} />}
          <label htmlFor="del-pw">Password</label>
          <input id="del-pw" type="password" autoComplete="current-password" required value={deletePw} onChange={(e) => setDeletePw(e.target.value)} />
          <div className="row" style={{ marginTop: 16, justifyContent: 'flex-end' }}>
            <button type="button" onClick={() => { setDeletePw(''); setDeleteError(null); deleteDialog.current?.close(); }}>Cancel</button>
            <button className="danger" disabled={!deletePw}>Delete everything</button>
          </div>
        </form>
      </dialog>
    </>
  );
}
