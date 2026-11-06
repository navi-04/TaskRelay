'use client';

import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';

interface ToastOptions {
  actionLabel?: string;
  onAction?: () => void | Promise<void>;
  /** Milliseconds before it disappears (default 7000). */
  ms?: number;
}
interface ToastItem extends ToastOptions {
  id: number;
  message: string;
}

export interface Choice {
  id: string;
  label: string;
  tone?: 'danger' | 'primary';
}
export interface AskOptions {
  title: string;
  message?: string;
  choices: Choice[];
  cancelLabel?: string;
}

type Toast = (message: string, options?: ToastOptions) => void;
type Ask = (options: AskOptions) => Promise<string | null>;

const FeedbackContext = createContext<{ toast: Toast; ask: Ask } | null>(null);

const use = () => {
  const ctx = useContext(FeedbackContext);
  if (!ctx) throw new Error('Feedback hooks must be used inside <FeedbackProvider>');
  return ctx;
};
/** Show a message, optionally with an action such as Undo. */
export const useToast = (): Toast => use().toast;
/** Ask the user to pick one of several choices (resolves with the choice id, or null if cancelled). */
export const useAsk = (): Ask => use().ask;

/** Toasts (with Undo) and a promise-based choice dialog, used by every signed-in page. */
export function FeedbackProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const nextId = useRef(1);
  const [pending, setPending] = useState<{ options: AskOptions; resolve: (id: string | null) => void } | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);

  const dismiss = useCallback((id: number) => setToasts((t) => t.filter((x) => x.id !== id)), []);

  const toast = useCallback<Toast>(
    (message, options = {}) => {
      const id = nextId.current++;
      setToasts((t) => [...t.slice(-2), { id, message, ...options }]);
      setTimeout(() => dismiss(id), options.ms ?? 7000);
    },
    [dismiss],
  );

  const ask = useCallback<Ask>((options) => new Promise((resolve) => setPending({ options, resolve })), []);

  useEffect(() => {
    if (pending && dialog.current && !dialog.current.open) dialog.current.showModal();
  }, [pending]);

  const finish = (id: string | null) => {
    dialog.current?.close();
    pending?.resolve(id);
    setPending(null);
  };

  return (
    <FeedbackContext.Provider value={{ toast, ask }}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {toasts.map((t) => (
          <div className="toast" key={t.id}>
            <span>{t.message}</span>
            {t.actionLabel && (
              <button
                onClick={async () => {
                  dismiss(t.id);
                  await t.onAction?.();
                }}
              >
                {t.actionLabel}
              </button>
            )}
          </div>
        ))}
      </div>
      <dialog ref={dialog} aria-labelledby="ask-title" onCancel={(e) => { e.preventDefault(); finish(null); }}>
        {pending && (
          <div className="stack">
            <h2 id="ask-title">{pending.options.title}</h2>
            {pending.options.message && <p className="muted">{pending.options.message}</p>}
            <div className="stack">
              {pending.options.choices.map((c) => (
                <button key={c.id} className={c.tone ?? ''} style={{ width: '100%' }} onClick={() => finish(c.id)}>
                  {c.label}
                </button>
              ))}
              <button className="link" style={{ width: '100%' }} onClick={() => finish(null)}>
                {pending.options.cancelLabel ?? 'Cancel'}
              </button>
            </div>
          </div>
        )}
      </dialog>
    </FeedbackContext.Provider>
  );
}
