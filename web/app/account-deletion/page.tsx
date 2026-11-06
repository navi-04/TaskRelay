import Link from 'next/link';

export const metadata = { title: 'Delete your account · TaskRelay' };

const ISSUES = 'https://github.com/navi-04/TaskRelay/issues';

export default function AccountDeletion() {
  return (
    <main style={{ maxWidth: 720, paddingTop: 24 }}>
      <p><Link href="/">← TaskRelay</Link></p>
      <h1>Delete your TaskRelay account</h1>

      <h2>How to delete it</h2>
      <ol>
        <li>Sign in on the website, or open the TaskRelay Android app.</li>
        <li>Go to <strong>Profile</strong>.</li>
        <li>Choose <strong>Delete my account</strong> and enter your password to confirm.</li>
      </ol>

      <h2>What happens</h2>
      <ul>
        <li>Your account, tasks, notes, history, settings, types, priorities and sign-in sessions are <strong>deleted immediately and permanently</strong>.</li>
        <li>Any AI access link you created stops working at once.</li>
        <li>It cannot be undone, so download your data first if you want a copy (Profile → <strong>Download my data</strong>).</li>
        <li>Routine server logs kept by our hosting provider expire under that provider’s own schedule.</li>
      </ul>

      <h2>Only want to remove tasks?</h2>
      <p>Profile → <strong>Delete all my tasks</strong> clears your tasks and history but keeps your account. Deleting a single task can be undone for 30 days.</p>

      <h2>Can’t sign in?</h2>
      <p>
        If you no longer have your password, open an issue at <a href={ISSUES}>{ISSUES.replace('https://', '')}</a> that mentions the email address of the account, and
        we will help you delete it. See also our <Link href="/privacy">privacy policy</Link>.
      </p>
    </main>
  );
}
