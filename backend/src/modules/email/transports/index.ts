import { resolve } from 'node:path';

import type { Config } from '../../../config/env.js';
import type { EmailTransport } from '../types.js';
import { FileEmailTransport } from './file.js';
import { SesEmailTransport } from './ses.js';

/**
 * `config.email.directory` (`.mail`) is relative — resolve it against the
 * process's cwd, not against this module's location. `npm run dev` and
 * `npm start` both run with `backend/` as the cwd, so this lands `.mail/`
 * next to `package.json`, where `.gitignore` already covers it.
 */
export function createEmailTransport(config: Config['email']): EmailTransport {
  return config.transport === 'ses'
    ? new SesEmailTransport(config.region)
    : new FileEmailTransport(resolve(process.cwd(), config.directory));
}
