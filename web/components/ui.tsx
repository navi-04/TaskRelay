import type { ReactNode } from 'react';

export function ErrorBanner({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="banner" role="alert">
      <div className="spread">
        <span>{message}</span>
        {onRetry && <button onClick={onRetry}>Retry</button>}
      </div>
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="empty">
      <strong style={{ display: 'block', color: 'var(--text)' }}>{title}</strong>
      {children && <span>{children}</span>}
    </div>
  );
}

/** Placeholder rows while a list loads. */
export function Skeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="stack" aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="skeleton" style={{ height: 44 }} />
      ))}
    </div>
  );
}

/** A circular progress ring with a centre label. */
export function ProgressRing({ percent, label }: { percent: number; label: string }) {
  const p = Math.max(0, Math.min(100, Math.round(percent)));
  return (
    <div className="ring" style={{ ['--p' as string]: p }} role="img" aria-label={`${p}% complete`}>
      <span>{label}</span>
    </div>
  );
}
