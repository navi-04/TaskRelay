// Client-side helper for the web UI. Auth is the httpOnly session cookie, so no token is handled here.

export class ApiFail extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export async function api<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`/api/v1${path}`, {
      method: init.method ?? 'GET',
      headers: { 'content-type': 'application/json', 'x-tr-web': '1' },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      credentials: 'same-origin',
      cache: 'no-store',
    });
  } catch {
    throw new ApiFail(0, 'network', 'Could not reach the server. Check your connection and try again.');
  }
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    // An expired or revoked session anywhere sends the user back to sign in (login attempts themselves report 401 inline).
    if (res.status === 401 && !path.startsWith('/auth/') && typeof window !== 'undefined' && window.location.pathname !== '/') {
      window.location.assign('/');
    }
    throw new ApiFail(res.status, data?.error?.code ?? 'error', data?.error?.message ?? res.statusText);
  }
  return data as T;
}

export const errorMessage = (e: unknown): string => (e instanceof Error ? e.message : 'Something went wrong');
