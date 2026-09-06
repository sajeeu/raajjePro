/** The standard response envelope (plan §Phase 2). Every response, success or failure, is one of these two shapes. */
export interface SuccessEnvelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

export interface ErrorEnvelope {
  error: { code: string; message: string; details?: unknown };
  requestId: string;
}

export function ok<T>(data: T, meta?: { nextCursor: string | null }): SuccessEnvelope<T> {
  return meta === undefined ? { data } : { data, meta };
}

export function fail(
  code: string,
  message: string,
  requestId: string,
  details?: unknown,
): ErrorEnvelope {
  return details === undefined
    ? { error: { code, message }, requestId }
    : { error: { code, message, details }, requestId };
}
