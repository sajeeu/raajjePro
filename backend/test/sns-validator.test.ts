import { describe, expect, it } from 'vitest';

import { SnsValidatorAdapter } from '../src/modules/email/sns/validator.js';

describe('SnsValidatorAdapter', () => {
  const adapter = new SnsValidatorAdapter();

  it('rejects a body that is not JSON', async () => {
    await expect(adapter.validate('nope')).rejects.toThrow();
  });

  it('rejects a message missing required fields', async () => {
    await expect(adapter.validate(JSON.stringify({ Type: 'Notification' }))).rejects.toThrow();
  });

  it('rejects a signing certificate not hosted by AWS SNS before fetching anything', async () => {
    await expect(
      adapter.validate(
        JSON.stringify({
          Type: 'Notification',
          MessageId: 'm',
          TopicArn: 'arn:aws:sns:ap-south-1:1:t',
          Message: '{}',
          Timestamp: '2026-09-06T00:00:00.000Z',
          SignatureVersion: '1',
          Signature: 'AAAA',
          SigningCertURL: 'https://attacker.example/cert.pem',
        }),
      ),
    ).rejects.toThrow();
  });
});
