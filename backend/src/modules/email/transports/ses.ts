import { SendEmailCommand, SESv2Client } from '@aws-sdk/client-sesv2';

import type { EmailTransport, OutboundEmail } from '../types.js';

/**
 * Amazon SES v2. Credentials come from the SDK default chain.
 * `ConfigurationSetName` is what routes events to the right SNS destination
 * and keeps channel reputations apart.
 *
 * Nothing else in this codebase imports `@aws-sdk/client-sesv2` (CLAUDE.md
 * invariant 10) — this file is the only vendor boundary.
 */
export class SesEmailTransport implements EmailTransport {
  private readonly client: SESv2Client;

  constructor(region: string) {
    this.client = new SESv2Client({ region });
  }

  async deliver(
    email: OutboundEmail,
    from: string,
    configurationSet: string | null,
  ): Promise<{ providerMessageId: string }> {
    const result = await this.client.send(
      new SendEmailCommand({
        FromEmailAddress: from,
        Destination: { ToAddresses: [email.to] },
        ...(configurationSet === null ? {} : { ConfigurationSetName: configurationSet }),
        Content: {
          Simple: {
            Subject: { Data: email.subject, Charset: 'UTF-8' },
            Body: {
              Text: { Data: email.text, Charset: 'UTF-8' },
              ...(email.html === undefined ? {} : { Html: { Data: email.html, Charset: 'UTF-8' } }),
            },
          },
        },
      }),
    );
    if (result.MessageId === undefined) throw new Error('SES returned no MessageId');
    return { providerMessageId: result.MessageId };
  }
}
