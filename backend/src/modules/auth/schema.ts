import { z } from 'zod';

import { MAX_USER_PASSWORD_LENGTH, MIN_USER_PASSWORD_LENGTH } from './service.js';

export const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
export const sessionIdParams = z.object({ id: z.uuid() });
export const deviceName = z.string().trim().max(80).optional();
export const otpCodeBody = z.object({
  code: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'Enter the 6-digit code'),
});

export const emailField = z.string().trim().pipe(z.email()).pipe(z.string().max(320));
export const passwordField = z.string().min(MIN_USER_PASSWORD_LENGTH).max(MAX_USER_PASSWORD_LENGTH);
export const phoneField = z.object({
  dialCode: z.string().trim().min(2).max(5),
  number: z.string().trim().min(1).max(40),
});

export const registerBody = z
  .object({
    role: z.enum(['customer', 'provider']),
    fullName: z.string().trim().min(1).max(120),
    email: emailField,
    phone: phoneField,
    password: passwordField,
    businessName: z.string().trim().min(1).max(120).optional(),
    acceptTerms: z.literal(true, { error: 'You need to accept the terms to continue' }),
    deviceName,
  })
  .superRefine((body, ctx) => {
    if (body.role === 'provider' && body.businessName === undefined) {
      ctx.addIssue({
        code: 'custom',
        path: ['businessName'],
        message: 'Business or trade name is required',
      });
    }
    if (body.role === 'customer' && body.businessName !== undefined) {
      ctx.addIssue({
        code: 'custom',
        path: ['businessName'],
        message: 'Only a provider account has a business name',
      });
    }
  });

export const loginBody = z.object({
  email: emailField,
  password: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
  deviceName,
});
// Not a Zod enum: an unregistered name must reach the route as a lookup miss
// (404 NOT_FOUND — the client contract for a provider that does not exist),
// not fail Zod's own validation (400 VALIDATION_FAILED) — plan §4.
export const socialParams = z.object({ provider: z.string().trim().min(1).max(40) });
export const socialBody = z.object({ idToken: z.string().min(20).max(8192), deviceName });
