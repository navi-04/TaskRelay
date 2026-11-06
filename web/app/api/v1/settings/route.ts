import { authApp, handle, json, readBody } from '@/lib/http';
import { getSettings, patchSettings } from '@/lib/services/settings';
import { settingsPatch } from '@/lib/validation';

export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await getSettings(ctx));
  });

export const PATCH = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await patchSettings(ctx, await readBody(req, settingsPatch)));
  });
