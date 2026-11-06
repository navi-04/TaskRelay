import type { ReactNode } from 'react';
import './globals.css';

export const metadata = { title: 'TaskRelay', description: 'Finish what you plan, one day at a time.' };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
