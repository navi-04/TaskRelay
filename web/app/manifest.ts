import type { MetadataRoute } from 'next';

/** Makes the website installable ("Add to Home screen") and gives it the app's colours. No service worker: it needs the network anyway. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'TaskRelay',
    short_name: 'TaskRelay',
    description: 'Finish what you plan, one day at a time.',
    start_url: '/today',
    scope: '/',
    display: 'standalone',
    background_color: '#000000',
    theme_color: '#000000',
    icons: [
      { src: '/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' },
      { src: '/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'maskable' },
    ],
  };
}
