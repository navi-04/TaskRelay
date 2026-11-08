/** App blocking lives in the Android app and its settings stay on the phone, so this card only says where to find it (nothing to set here). */
export default function AppBlocking() {
  return (
    <section className="card" aria-labelledby="block-h">
      <h2 id="block-h">Block distracting apps</h2>
      <p className="muted">
        Choose apps to block until your tasks are done, or only allow them at set times. Tasks with a start and end time keep those apps blocked while they run.
      </p>
      <p className="muted small" style={{ marginBottom: 0 }}>
        App blocking runs in the TaskRelay Android app (Profile → Block distracting apps). The apps you choose stay on your phone, so there is nothing to set here.
      </p>
    </section>
  );
}
