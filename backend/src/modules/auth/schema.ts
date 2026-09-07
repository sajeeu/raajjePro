import { z } from 'zod';

export const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
export const sessionIdParams = z.object({ id: z.uuid() });
export const deviceName = z.string().trim().max(80).optional();
export const otpCodeBody = z.object({
  code: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'Enter the 6-digit code'),
});
