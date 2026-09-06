import type { EmailChannel } from '../../config/env.js';

export type { EmailChannel };

export interface OutboundEmail {
  channel: EmailChannel;
  to: string;
  subject: string;
  text: string;
  html?: string;
  /** Phase 3 sets this so Phase 10b can answer "did this user get it?" by user id. */
  recipientUserId?: string;
}

export interface SendOutcome {
  /** The email_message row id — the handle for the delivery log. */
  messageId: string;
  status: 'sent' | 'suppressed' | 'failed';
}

/** What every domain module sends through. Nothing calls SES directly (CLAUDE.md invariant 10). */
export interface EmailSender {
  send(email: OutboundEmail): Promise<SendOutcome>;
}

/** The vendor boundary. SES in production; a file in development. */
export interface EmailTransport {
  deliver(
    email: OutboundEmail,
    from: string,
    configurationSet: string | null,
  ): Promise<{ providerMessageId: string }>;
}
