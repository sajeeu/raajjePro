import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { PushMessage, PushTarget, PushTransport } from '../types.js';

/**
 * Development/test transport: one JSON file per push in a gitignored
 * directory, exactly as `FileEmailTransport` does for mail. This is the whole
 * vendor layer for now — no Firebase project and no Apple developer account
 * exist, and neither is procured by this phase
 * (docs/decisions/15-phase-3c-push.md). Everything above this line is real.
 *
 * It records the token so a local run can tell multi-device fan-out apart,
 * and nothing else about the recipient.
 */
export class FilePushTransport implements PushTransport {
  constructor(private readonly directory: string) {}

  async deliver(message: PushMessage, target: PushTarget): Promise<{ providerMessageId: string }> {
    await mkdir(this.directory, { recursive: true });
    const providerMessageId = `file-${randomUUID()}`;
    const file = join(
      this.directory,
      `${new Date().toISOString().replaceAll(':', '-')}-${providerMessageId}.json`,
    );
    await writeFile(
      file,
      JSON.stringify(
        {
          providerMessageId,
          platform: target.platform,
          token: target.token,
          deviceTokenId: target.deviceTokenId,
          ...message,
        },
        null,
        2,
      ),
    );
    return { providerMessageId };
  }
}
