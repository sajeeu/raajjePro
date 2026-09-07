import { z } from 'zod';

export const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });
export const sessionIdParams = z.object({ id: z.uuid() });
export const deviceName = z.string().trim().max(80).optional();
