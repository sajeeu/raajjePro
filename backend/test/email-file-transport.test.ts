import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import { FileEmailTransport } from '../src/modules/email/transports/file.js';

describe('FileEmailTransport', () => {
  it('writes one JSON file per message with the envelope, address and configuration set', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'raajjepro-file-transport-'));
    const transport = new FileEmailTransport(directory);
    const to = `user-${randomUUID()}@example.test`;

    const { providerMessageId } = await transport.deliver(
      { channel: 'otp', to, subject: 'Your code', text: '123456' },
      'no-reply@raajjepro.test',
      'cs-otp',
    );

    expect(providerMessageId).toMatch(/^file-/);
    const files = await readdir(directory);
    expect(files).toHaveLength(1);
    const contents = JSON.parse(await readFile(join(directory, files[0] ?? ''), 'utf8')) as {
      providerMessageId: string;
      from: string;
      configurationSet: string | null;
      to: string;
      subject: string;
      text: string;
    };
    expect(contents.providerMessageId).toBe(providerMessageId);
    expect(contents.from).toBe('no-reply@raajjepro.test');
    expect(contents.configurationSet).toBe('cs-otp');
    expect(contents.to).toBe(to);
    expect(contents.subject).toBe('Your code');
    expect(contents.text).toBe('123456');
  });

  it('creates the directory if it does not yet exist', async () => {
    const directory = join(
      await mkdtemp(join(tmpdir(), 'raajjepro-file-transport-')),
      'nested',
      'mail',
    );
    const transport = new FileEmailTransport(directory);

    await transport.deliver(
      { channel: 'notification', to: 'someone@example.test', subject: 's', text: 't' },
      'no-reply@raajjepro.test',
      null,
    );

    const files = await readdir(directory);
    expect(files).toHaveLength(1);
  });
});
