import { z } from 'zod';

import { emailField, otpCodeBody, passwordField, phoneField } from '../auth/schema.js';
import { MAX_USER_PASSWORD_LENGTH } from '../auth/service.js';

export const changePasswordBody = z.object({
  currentPassword: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
  newPassword: passwordField,
});
export const changeEmailRequestBody = z.object({
  newEmail: emailField,
  currentPassword: z.string().min(1).max(MAX_USER_PASSWORD_LENGTH),
});
export const changeEmailConfirmBody = otpCodeBody;
export const changePhoneBody = phoneField;
