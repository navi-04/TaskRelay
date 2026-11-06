/** An error that maps to an HTTP response: `{ error: { code, message } }`. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export const badRequest = (message: string, code = 'bad_request') => new ApiError(400, code, message);
export const unauthorized = (message = 'Not signed in') => new ApiError(401, 'unauthorized', message);
export const forbidden = (message: string, code = 'forbidden') => new ApiError(403, code, message);
// Cross-user lookups are reported as 404, never 403, so ids can't be probed.
export const notFound = (what = 'Not found') => new ApiError(404, 'not_found', what);
export const conflict = (message: string, code = 'conflict') => new ApiError(409, code, message);
export const unprocessable = (message: string, code: string) => new ApiError(422, code, message);
export const tooMany = (retryAfterSec: number) =>
  new ApiError(429, 'rate_limited', `Too many attempts. Try again in ${Math.max(1, Math.ceil(retryAfterSec / 60))} min.`);
