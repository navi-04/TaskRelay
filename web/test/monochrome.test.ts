import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

// The product is strictly black and white, in a White theme and a Black theme the user can choose.
// This makes it a property of the build: no source file can introduce a hue, and no emoji
// (browsers draw those in colour whatever the CSS says).

const root = join(__dirname, '..');
const dirs = ['app', 'components', 'lib/web', 'public'];
const exts = ['.css', '.ts', '.tsx', '.svg'];

function sources(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...sources(p));
    else if (exts.some((e) => p.endsWith(e))) out.push(p);
  }
  return out;
}

const files = dirs.flatMap((d) => sources(join(root, d)));

function lines(): { where: string; text: string }[] {
  return files.flatMap((f) =>
    readFileSync(f, 'utf8')
      .split(/\r?\n/)
      .map((text, i) => ({ where: `${relative(root, f).replace(/\\/g, '/')}:${i + 1}`, text })),
  );
}

const grey = (r: number, g: number, b: number) => r === g && g === b;

function hexIsGrey(hex: string): boolean {
  let h = hex;
  if (h.length === 3 || h.length === 4) h = [...h].map((c) => c + c).join('');
  if (h.length === 8) h = h.slice(0, 6); // drop alpha
  if (h.length !== 6) return true; // not a colour (e.g. an anchor like #main)
  return grey(parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16));
}

describe('the web UI is strictly black and white', () => {
  it('scans a meaningful set of files', () => {
    expect(files.length).toBeGreaterThan(30);
    expect(files.some((f) => f.endsWith('globals.css'))).toBe(true);
    expect(files.some((f) => f.endsWith('icon.svg'))).toBe(true);
  });

  it('has no emoji (they render in colour); text symbols and words only', () => {
    const bad = lines().filter((l) => /[\p{Emoji_Presentation}️]/u.test(l.text));
    expect(bad.map((l) => `${l.where}: ${l.text.trim()}`)).toEqual([]);
  });

  it('every hex colour is a pure grey', () => {
    const bad: string[] = [];
    for (const l of lines()) {
      // "#" followed by 3, 4, 6 or 8 hex digits and nothing word-like after it
      for (const m of l.text.matchAll(/#([0-9a-fA-F]{3,8})\b/g)) {
        if (![3, 4, 6, 8].includes(m[1].length)) continue;
        if (!hexIsGrey(m[1])) bad.push(`${l.where}: #${m[1]}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it('rgb()/hsl() colours are grey; no other colour spaces', () => {
    const bad: string[] = [];
    for (const l of lines()) {
      for (const m of l.text.matchAll(/\brgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/g)) {
        if (!grey(+m[1], +m[2], +m[3])) bad.push(`${l.where}: ${m[0]}`);
      }
      for (const m of l.text.matchAll(/\bhsla?\(\s*[\d.]+(?:deg)?[\s,]+([\d.]+)%/g)) {
        if (+m[1] !== 0) bad.push(`${l.where}: ${m[0]}`);
      }
      for (const m of l.text.matchAll(/\b(hwb|lab|lch|oklab|oklch|color-mix)\(/g)) bad.push(`${l.where}: ${m[0]}`);
    }
    expect(bad).toEqual([]);
  });

  it('uses no named hue in CSS', () => {
    const css = lines().filter((l) => l.where.includes('.css:'));
    const named = /:\s*[^;]*\b(red|green|blue|yellow|orange|purple|pink|teal|cyan|magenta|brown|gold|navy|lime|indigo|violet|crimson|tomato|salmon|aqua|olive|maroon|coral|khaki)\b/i;
    expect(css.filter((l) => named.test(l.text)).map((l) => `${l.where}: ${l.text.trim()}`)).toEqual([]);
  });

  it('defines a White theme, a Black theme, and follows the device when nothing is chosen', () => {
    const css = readFileSync(join(root, 'app/globals.css'), 'utf8');
    expect(css).toMatch(/:root\s*{[^}]*--bg:\s*#ffffff/);
    expect(css).toMatch(/:root\[data-theme='dark'\]\s*{[^}]*--bg:\s*#000000/);
    expect(css).toMatch(/@media \(prefers-color-scheme: dark\)\s*{\s*:root:not\(\[data-theme='light'\]\):not\(\[data-theme='dark'\]\)\s*{[^}]*--bg:\s*#000000/);
  });
});
