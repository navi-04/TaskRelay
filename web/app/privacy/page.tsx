import Link from 'next/link';

export const metadata = { title: 'Privacy policy · TaskRelay' };

const ISSUES = 'https://github.com/navi-04/TaskRelay/issues';

export default function Privacy() {
  return (
    <main style={{ maxWidth: 720, paddingTop: 24 }}>
      <p><Link href="/">← TaskRelay</Link></p>
      <h1>Privacy policy</h1>
      <p className="muted">Last updated: November 2026</p>

      <p>
        TaskRelay is a personal task and habit tracker (Android app and website) made by an independent developer. This page explains, in plain
        language, what it stores, why, and how you can delete it.
      </p>

      <h2>What we store</h2>
      <ul>
        <li><strong>Account:</strong> your email address and your password. The password is never stored as text, only as a salted hash that cannot be turned back into the password.</li>
        <li><strong>Your content:</strong> the tasks, notes, repeat settings, reminder times, types, priorities and daily-limit settings you create, plus whether each task was done and when.</li>
        <li><strong>Technical data:</strong> your timezone (so “today” is right), sign-in sessions, and a private access ID if you use the Claude feature.</li>
        <li><strong>AI change log:</strong> if you let an AI assistant change your tasks, the last 200 of those changes (what changed and when), so you can see and undo them.</li>
      </ul>
      <p>
        We do <strong>not</strong> collect your location, contacts, photos or advertising identifiers, and the app has no ads and no analytics or
        tracking SDKs. The Android app asks for notification and alarm permissions only to ring your reminders.
      </p>

      <h2>Where it is stored</h2>
      <p>
        Your data is stored in a database run by <strong>Turso</strong> and served by <strong>Vercel</strong>. They act on our behalf to run the service. Like any web
        host, Vercel keeps standard request logs (such as IP address and time) under its own policy. Everything is sent over HTTPS, and each account can only
        read its own data.
      </p>

      <h2>AI assistants (optional)</h2>
      <p>
        TaskRelay does not send your data to any AI company. Only if <em>you</em> give your private AI access link to an assistant such as Claude can that assistant read and
        change your tasks, and then that assistant’s own privacy policy applies. Treat the link like a password: you can switch it off or replace it at any time in
        Profile, and the old link stops working immediately.
      </p>

      <h2>How long we keep it, and deleting it</h2>
      <ul>
        <li>Deleted tasks are kept for <strong>30 days</strong> so you can undo, then permanently removed.</li>
        <li>You can download all your data (Profile → Download my data).</li>
        <li>You can delete your account at any time (Profile → Delete my account). That removes your account and everything in it immediately. See <Link href="/account-deletion">how deletion works</Link>.</li>
      </ul>

      <h2>Children</h2>
      <p>TaskRelay is not directed at children under 13 and we do not knowingly collect their data.</p>

      <h2>Changes and contact</h2>
      <p>
        If this policy changes in a way that matters, we will update the date above. Questions or requests: please open an issue at{' '}
        <a href={ISSUES}>{ISSUES.replace('https://', '')}</a>.
      </p>
    </main>
  );
}
