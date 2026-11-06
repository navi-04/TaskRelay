'use client';

import { useTheme, type ThemeChoice } from '@/lib/web/theme';

const OPTIONS: Array<{ id: ThemeChoice; label: string; hint: string }> = [
  { id: 'light', label: 'White', hint: 'Black text on white' },
  { id: 'dark', label: 'Black', hint: 'White text on black' },
  { id: 'system', label: 'Match device', hint: 'Follow the system setting' },
];

/** Pick White, Black, or follow the device. Saved on this device only. */
export default function Appearance() {
  const { choice, set } = useTheme();
  return (
    <section className="card" aria-labelledby="theme-h">
      <h2 id="theme-h">Appearance</h2>
      <div className="theme-choice" role="radiogroup" aria-labelledby="theme-h">
        {OPTIONS.map((o) => (
          <label key={o.id} title={o.hint}>
            <input type="radio" name="theme" checked={choice === o.id} onChange={() => set(o.id)} />
            {o.label}
          </label>
        ))}
      </div>
      <p className="muted small" style={{ marginBottom: 0, marginTop: 8 }}>Saved on this device. The Android app has its own setting.</p>
    </section>
  );
}
