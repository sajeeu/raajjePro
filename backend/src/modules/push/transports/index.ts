import { resolve } from 'node:path';

import type { Config } from '../../../config/env.js';
import type { PushTransport } from '../types.js';
import { FilePushTransport } from './file.js';

/**
 * `config.push.directory` (`.push`) is relative — resolved against the
 * process cwd for the same reason the mail directory is, so it lands next to
 * `package.json` where `.gitignore` already covers it.
 *
 * There is one branch here today. When the FCM and APNs transports are built
 * this becomes a switch on `config.push.transport`, additively; `loadConfig`
 * refuses `PUSH_TRANSPORT=fcm_apns` until then, so this function can never be
 * reached with a transport it cannot construct.
 */
export function createPushTransport(config: Config['push']): PushTransport {
  return new FilePushTransport(resolve(process.cwd(), config.directory));
}
