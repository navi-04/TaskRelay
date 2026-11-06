'use client';

import { useCallback, useEffect, useState } from 'react';

export type ThemeChoice = 'system' | 'light' | 'dark';
export const THEME_KEY = 'tr-theme';

/** Runs in <head> before first paint (see layout) so the chosen theme never flashes the wrong colours. */
export const THEME_BOOT_SCRIPT = `try{var t=localStorage.getItem('${THEME_KEY}');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}`;

function read(): ThemeChoice {
  try {
    const t = localStorage.getItem(THEME_KEY);
    return t === 'light' || t === 'dark' ? t : 'system';
  } catch {
    return 'system';
  }
}

function apply(choice: ThemeChoice) {
  const root = document.documentElement;
  if (choice === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', choice);
  try {
    if (choice === 'system') localStorage.removeItem(THEME_KEY);
    else localStorage.setItem(THEME_KEY, choice);
  } catch {
    // storage blocked: the choice still applies for this visit
  }
}

/** The effective theme right now ('light' or 'dark'), resolving "system". */
export const effectiveTheme = (choice: ThemeChoice): 'light' | 'dark' =>
  choice === 'system' ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : choice;

/** The user's theme choice for this device (System, White or Black), kept in sync across tabs. */
export function useTheme() {
  const [choice, setChoice] = useState<ThemeChoice>('system');
  useEffect(() => {
    setChoice(read());
    const onStorage = (e: StorageEvent) => {
      if (e.key === THEME_KEY) {
        const next = read();
        setChoice(next);
        apply(next);
      }
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const set = useCallback((next: ThemeChoice) => {
    apply(next);
    setChoice(next);
  }, []);
  /** Flip between White and Black (from System, to whichever it is not right now). */
  const toggle = useCallback(() => set(effectiveTheme(read()) === 'dark' ? 'light' : 'dark'), [set]);
  return { choice, set, toggle };
}
