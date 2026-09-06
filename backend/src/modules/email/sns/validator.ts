import MessageValidator from 'sns-validator';

export interface SnsMessage {
  Type: 'Notification' | 'SubscriptionConfirmation' | 'UnsubscribeConfirmation';
  MessageId: string;
  TopicArn: string;
  Message: string;
  Timestamp: string;
  Subject?: string;
  SubscribeURL?: string;
  Token?: string;
}

/** Verifies an inbound SNS message. Rejects on malformed structure, a non-AWS certificate host, or a bad signature. */
export interface SnsMessageValidator {
  validate(rawBody: string): Promise<SnsMessage>;
}

export const SNS_HOST = /^sns\.[a-zA-Z0-9-]{3,}\.amazonaws\.com$/;

/**
 * `sns-validator` (decision 09): checks the SigningCertURL host against the
 * SNS pattern before fetching, rebuilds the string-to-sign in the documented
 * order, verifies SHA1/SHA256-withRSA per SignatureVersion, caches the cert.
 */
export class SnsValidatorAdapter implements SnsMessageValidator {
  private readonly validator = new MessageValidator(SNS_HOST);

  validate(rawBody: string): Promise<SnsMessage> {
    return new Promise((resolve, reject) => {
      this.validator.validate(rawBody, (error: Error | null, message?: Record<string, unknown>) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(message as unknown as SnsMessage);
      });
    });
  }
}

/** True only for an https URL on an SNS host — the rule for SubscribeURL before we GET it. */
export function isSnsUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && SNS_HOST.test(parsed.host);
  } catch {
    return false;
  }
}
