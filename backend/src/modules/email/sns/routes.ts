import type { FastifyInstance } from 'fastify';

import { ok } from '../../../core/envelope.js';
import { AppError, AuthorizationError, ValidationError } from '../../../core/errors.js';
import { applySesEvent, sesEventSchema } from './events.js';
import { isSnsUrl } from './validator.js';

/** The spec's code for a message that fails SNS structure, host or signature checks. */
export class InvalidSnsSignatureError extends AppError {
  constructor() {
    super(400, 'INVALID_SNS_SIGNATURE', 'SNS signature or structure invalid');
  }
}

/** GETs an SNS SubscribeURL and throws on a non-2xx response. The default `confirmSubscription`, used when AppDeps does not supply one. */
async function defaultConfirmSubscription(url: string): Promise<void> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`subscription confirmation returned ${String(res.status)}`);
}

/**
 * POST /v1/webhooks/ses-events — the SNS HTTPS subscription for the three SES
 * configuration sets' event destinations. No session: the SNS signature is
 * the authentication. Always 200 once an event is stored so SNS stops
 * retrying; a rejected message gets 400/403 and is not stored.
 */
export async function registerSesEventRoutes(app: FastifyInstance): Promise<void> {
  await app.register((scope) => {
    // SNS posts text/plain. Take the raw string: the validator needs the exact bytes that were signed.
    scope.addContentTypeParser(
      ['text/plain', 'application/json'],
      { parseAs: 'string' },
      (_req, body, done) => {
        done(null, body);
      },
    );

    scope.post(
      '/v1/webhooks/ses-events',
      { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } },
      async (request, reply) => {
        const raw = typeof request.body === 'string' ? request.body : '';
        let message;
        try {
          message = await app.deps.snsValidator.validate(raw);
        } catch (error) {
          request.log.warn(
            { err: error instanceof Error ? error.message : 'unknown' },
            'sns message rejected',
          );
          throw new InvalidSnsSignatureError();
        }

        const expectedTopic = app.config.email.eventsTopicArn;
        if (expectedTopic !== null && message.TopicArn !== expectedTopic) {
          throw new AuthorizationError(
            'UNEXPECTED_SNS_TOPIC',
            'Notification is not from the configured topic',
          );
        }

        if (message.Type === 'SubscriptionConfirmation') {
          if (message.SubscribeURL === undefined || !isSnsUrl(message.SubscribeURL)) {
            throw new InvalidSnsSignatureError();
          }
          const confirmSubscription = app.deps.confirmSubscription ?? defaultConfirmSubscription;
          await confirmSubscription(message.SubscribeURL);
          request.log.info({ topic: message.TopicArn }, 'sns subscription confirmed');
          return reply.send(ok({ confirmed: true }));
        }
        if (message.Type === 'UnsubscribeConfirmation') {
          request.log.warn({ topic: message.TopicArn }, 'sns unsubscribe confirmation received');
          return reply.send(ok({ acknowledged: true }));
        }

        let payload: unknown;
        try {
          payload = JSON.parse(message.Message);
        } catch {
          throw new ValidationError(
            [{ path: 'Message', message: 'not JSON' }],
            'SNS message rejected',
          );
        }
        const parsed = sesEventSchema.safeParse(payload);
        if (!parsed.success) {
          throw new ValidationError(
            [{ path: 'Message', message: 'not an SES event' }],
            'SNS message rejected',
          );
        }
        const result = await applySesEvent(
          app.deps.prisma,
          app.deps.clock,
          message.MessageId,
          parsed.data,
          payload,
        );
        return reply.send(ok({ result }));
      },
    );
  });
}
