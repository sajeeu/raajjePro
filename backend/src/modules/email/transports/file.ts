import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { EmailTransport, OutboundEmail } from '../types.js';

/**
 * Development/test transport: one JSON file per message in a gitignored
 * directory, so an OTP can be read locally without AWS.
 */
export class FileEmailTransport implements EmailTransport {
  constructor(private readonly directory: string) {}

  async deliver(
    email: OutboundEmail,
    from: string,
    configurationSet: string | null,
  ): Promise<{ providerMessageId: string }> {
    await mkdir(this.directory, { recursive: true });
    const providerMessageId = `file-${randomUUID()}`;
    const file = join(
      this.directory,
      `${new Date().toISOString().replaceAll(':', '-')}-${providerMessageId}.json`,
    );
    await writeFile(
      file,
      JSON.stringify({ providerMessageId, from, configurationSet, ...email }, null, 2),
    );
    return { providerMessageId };
  }
}
