/**
 * §Phase 3c's fallback-email content rule, which is a security rule wearing a
 * copywriting hat: "No links — do not train providers to tap links in messages
 * that claim a job is waiting. No amounts, no phone numbers."
 */
import { describe, expect, it } from 'vitest';

import {
  assertContentRules,
  fallbackEmail,
  NotificationContentError,
  pushMessage,
} from '../src/modules/push/content.js';
import type { NotificationContext } from '../src/modules/push/types.js';

const accept: NotificationContext = {
  kind: 'booking_accept_prompt',
  bookingType: 'Cleaning',
  customerFirstName: 'Aishath',
  islandName: 'Dh. Meedhoo',
};
const emergency: NotificationContext = {
  kind: 'emergency_dispatch',
  bookingType: 'Electrical',
  customerFirstName: 'Ibrahim',
  islandName: 'Kulhudhuffushi',
};

describe('Phase 3c — notification content', () => {
  it('the fallback email carries exactly the four things the plan names', () => {
    const mail = fallbackEmail('provider@example.test', 'user-1', accept);
    expect(mail.text).toContain('Cleaning'); // booking type
    expect(mail.text).toContain('Aishath'); // customer first name
    expect(mail.text).toContain('Dh. Meedhoo'); // job location island
    expect(mail.text.toLowerCase()).toContain('open the raajjepro app'); // the instruction
  });

  it('the fallback email has no link, no amount and no phone number', () => {
    for (const context of [accept, emergency]) {
      const mail = fallbackEmail('provider@example.test', 'user-1', context);
      for (const text of [mail.subject, mail.text]) {
        expect(text).not.toMatch(/https?:\/\//i);
        expect(text).not.toMatch(/www\./i);
        expect(text).not.toMatch(/\bMVR\b/i);
        expect(text).not.toMatch(/\+?\d[\d\s-]{5,}/);
      }
    }
  });

  it('it says in words that we never send links, because that is the point', () => {
    const mail = fallbackEmail('provider@example.test', 'user-1', accept);
    expect(mail.text.toLowerCase()).toContain('never put links');
  });

  it('the fallback email goes on the notification channel, never the OTP one', () => {
    // Three SES configuration sets exist so a complaint spike on booking mail
    // cannot degrade the reputation OTP depends on.
    expect(fallbackEmail('p@example.test', 'user-1', accept).channel).toBe('notification');
    expect(fallbackEmail('p@example.test', 'user-1', emergency).channel).toBe('notification');
  });

  it('the recipient user id is carried so Phase 10b can look the message up by user', () => {
    expect(fallbackEmail('p@example.test', 'user-42', accept).recipientUserId).toBe('user-42');
  });

  it('the push payload obeys the same restraint, and carries the ack handle', () => {
    const message = pushMessage('dispatch-1', accept);
    expect(message.data.dispatchId).toBe('dispatch-1');
    expect(message.data.kind).toBe('booking_accept_prompt');
    for (const text of [message.title, message.body]) {
      expect(text).not.toMatch(/https?:\/\//i);
      expect(text).not.toMatch(/\bMVR\b/i);
    }
  });

  it('the rule is enforced at runtime, not only in this file', () => {
    // A later phase adding a notification kind gets the check whether or not
    // it remembers to write a test for it.
    expect(() => {
      assertContentRules('Tap https://raajjepro.mv/jobs', 'x');
    }).toThrow(NotificationContentError);
    expect(() => {
      assertContentRules('The job pays MVR 450', 'x');
    }).toThrow(NotificationContentError);
    expect(() => {
      assertContentRules('Call 7712345 now', 'x');
    }).toThrow(NotificationContentError);
    expect(() => {
      assertContentRules('A Cleaning job in Dh. Meedhoo', 'x');
    }).not.toThrow();
  });
});
