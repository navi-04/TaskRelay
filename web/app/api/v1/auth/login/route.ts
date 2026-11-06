import { getDb } from '@/lib/db';
import { clientIp, handle, isWebClient, json, readBody, sessionCookie } from '@/lib/http';
import { login } from '@/lib/services/auth';
import { login as loginSchema } from '@/lib/validation';

export const POST = (req: Request) =>
  handle(async () => {
    const input = await readBody(req, loginSchema);
    const { token, user } = await login(await getDb(), input, { ip: clientIp(req), now: new Date() });
    if (isWebClient(req)) return json({ user }, 200, { 'Set-Cookie': sessionCookie(req, token) });
    return json({ token, user });
  });
