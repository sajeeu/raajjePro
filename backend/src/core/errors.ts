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
  constructor(code = 'CONFLICT', message = 'Conflict') {
    super(409, code, message);
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'Not found') {
    super(404, 'NOT_FOUND', message);
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
