import { z } from 'zod';

import { MAX_PASSWORD_LENGTH } from './crypto.js';

export const loginBody = z.object({
  email: z.email().max(320),
  password: z.string().min(1).max(MAX_PASSWORD_LENGTH),
});

export const sessionIdParams = z.object({ id: z.uuid() });

export const revokeSessionBody = z.object({ reason: z.string().trim().min(1).max(500) });

export const mfaCodeBody = z.object({ code: z.string().trim().min(6).max(11) });

export const reauthBody = z.object({
  password: z.string().min(1).max(MAX_PASSWORD_LENGTH),
  code: z.string().trim().min(6).max(11),
});
