/**
 * Error classes, one per category in plan §Phase 2. Each carries a fixed HTTP
 * status and a stable machine-readable `code` — the frontend routes on codes,
 * so renaming one is a breaking change (backend/CLAUDE.md, API contract).
 */
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ValidationError extends AppError {
  constructor(details: { path: string; message: string }[], message = 'Request failed validation') {
    super(400, 'VALIDATION_FAILED', message, details);
  }
}

export class AuthenticationError extends AppError {
  constructor(code = 'UNAUTHENTICATED', message = 'Authentication required') {
    super(401, code, message);
  }
}

export class AuthorizationError extends AppError {
  constructor(code = 'FORBIDDEN', message = 'Not allowed') {
    super(403, code, message);
  }
}

/** The code is the rule that was broken, e.g. EMAIL_NOT_VERIFIED. */
export class BusinessRuleError extends AppError {
  constructor(code: string, message: string, details?: unknown) {
    super(422, code, message, details);
  }
}

export class ConflictError extends AppError {
  constructor(code = 'CONFLICT', message = 'Conflict', details?: unknown) {
    super(409, code, message, details);
  }
}

/**
 * An optional code, because `NOT_FOUND` alone cannot say *what* was not found.
 *
 * The API contract has the client route on the code, and a fixed one makes
 * "this account has no provider profile yet" indistinguishable from a typo'd
 * URL — two cases a caller must handle differently. Callers that have no
 * client needing the distinction keep the default; adding a code is additive
 * and needs no change anywhere else.
 *
 * **Message first, code second — deliberately unlike `AuthorizationError` and
 * `ConflictError`, which take the code first.** Every existing caller passes a
 * message positionally, and both parameters are strings, so matching the
 * siblings' order would silently turn each of those messages into an error
 * code with no type error to catch it. The inconsistency is the safe choice;
 * do not "fix" it by reordering.
 */
export class NotFoundError extends AppError {
  constructor(message = 'Not found', code = 'NOT_FOUND') {
    super(404, code, message);
  }
}

export class InfrastructureError extends AppError {
  constructor(message = 'A dependency is unavailable') {
    super(503, 'INFRASTRUCTURE_UNAVAILABLE', message);
  }
}

export class RateLimitedError extends AppError {
  constructor(public readonly retryAfterSeconds: number) {
    super(429, 'RATE_LIMITED', 'Too many requests', { retryAfterSeconds });
  }
}

/** Any error that should carry a Retry-After header. RateLimitedError is one; the OTP send limit is another. */
export interface RetryAfterCarrier {
  retryAfterSeconds: number;
}

export function carriesRetryAfter(error: AppError): error is AppError & RetryAfterCarrier {
  return typeof (error as Partial<RetryAfterCarrier>).retryAfterSeconds === 'number';
}
