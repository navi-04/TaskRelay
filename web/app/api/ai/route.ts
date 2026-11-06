import { buildManual, manualToText } from '@/lib/ai';
import { AI_HEADERS, aiJson, aiRoute } from '@/lib/http';

/** The manual. Paste this URL (with the id) to an AI assistant; it explains everything else. `?format=text` for markdown. */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx, url) => {
    const uid = url.searchParams.get('uid') ?? req.headers.get('x-ai-id') ?? req.headers.get('authorization')?.slice(7) ?? '';
    const manual = buildManual(ctx, url.origin, uid);
    if (url.searchParams.get('format') === 'text') {
      return new Response(manualToText(manual), { headers: { ...AI_HEADERS, 'Content-Type': 'text/plain; charset=utf-8' } });
    }
    return aiJson(manual);
  });
