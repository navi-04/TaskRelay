import type { NextConfig } from 'next';

const config: NextConfig = {
  // The Node libSQL client is only used for local `file:` databases (dev + tests);
  // keep it out of the bundle. Production talks to Turso through `@libsql/client/web`.
  serverExternalPackages: ['@libsql/client', 'libsql'],
};

export default config;
