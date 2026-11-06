import { getDb } from '@/lib/db';
import { clientIp, handle, isWebClient, json, readBody, sessionCookie } from '@/lib/http';
import { registerUser } from '@/lib/services/auth';
import { register } from '@/lib/validation';

export const POST = (req: Request) =>
  handle(async () => {
    const input = await readBody(req, register);
    const { token, user } = await registerUser(await getDb(), input, { ip: clientIp(req), now: new Date() });
    // Apps get the token in the body; the web UI gets an httpOnly cookie and never sees it.
    if (isWebClient(req)) return json({ user }, 201, { 'Set-Cookie': sessionCookie(req, token) });
    return json({ token, user }, 201);
  });
