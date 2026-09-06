import { z } from 'zod';

import { MAX_PASSWORD_LENGTH } from './crypto.js';

export const loginBody = z.object({
  // Trim first, then validate as an email, then bound the length — chaining
  // .trim() after the top-level z.email() would run the format check before
  // the trim and reject a merely whitespace-padded address.
  email: z.string().trim().pipe(z.email()).pipe(z.string().max(320)),
  password: z.string().min(1).max(MAX_PASSWORD_LENGTH),
});

export const sessionIdParams = z.object({ id: z.uuid() });

export const revokeSessionBody = z.object({ reason: z.string().trim().min(1).max(500) });

export const mfaCodeBody = z.object({ code: z.string().trim().min(6).max(11) });

export const reauthBody = z.object({
  password: z.string().min(1).max(MAX_PASSWORD_LENGTH),
  code: z.string().trim().min(6).max(11),
});
