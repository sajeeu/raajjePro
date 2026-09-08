import type { Clock } from '../../core/clock.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import type { DeviceTokenRepository } from './repository.js';
import {
  UnregisteredTokenError,
  type PushDeliveryOutcome,
  type PushMessage,
  type PushSender,
  type PushTarget,
  type PushTransport,
} from './types.js';

export interface PushSenderLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

const noopLogger: PushSenderLogger = { info: () => undefined, warn: () => undefined };

/**
 * The one sender (§Phase 3c). Fans a message out to every live device the
 * user has, records a `push_delivery` row per device, and reports what
 * happened. Two things it deliberately does NOT do:
 *
 *  - It does not decide whether an email should also go. That is the fallback
 *    chain, and it lives in `dispatcher.ts` so there is exactly one place the
 *    rungs are written down.
 *  - It does not treat a vendor's acceptance as delivery. FCM and APNs both
 *    return an id the moment they take the message, which says nothing about
 *    whether the phone was on. Only the app calling the ack endpoint sets
 *    `confirmedAt`, and only that satisfies the 30-minute rung.
 *
 * A vendor reporting a dead token revokes that registration on the spot —
 * this is the "cleanup" half of §Phase 3c's multi-device Done-when clause.
 */
export class PushService implements PushSender {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      transport: PushTransport;
      devices: DeviceTokenRepository;
      clock: Clock;
      log?: PushSenderLogger;
    },
  ) {}

  private get log(): PushSenderLogger {
    return this.deps.log ?? noopLogger;
  }

  async send(
    userId: string,
    dispatchId: string,
    message: PushMessage,
  ): Promise<{ attempted: number; sent: number; outcomes: PushDeliveryOutcome[] }> {
    const targets = await this.deps.devices.liveFor(userId);
    // Devices are independent: one vendor being slow must not hold up the
    // others, and one failing must not abandon the rest. Settled, not raced.
    const outcomes = await Promise.all(
      targets.map((device) =>
        this.deliverOne(dispatchId, message, {
          deviceTokenId: device.id,
          token: device.token,
          platform: device.platform,
        }),
      ),
    );
    const sent = outcomes.filter((o) => o.status === 'sent').length;
    this.log.info(
      { event: 'push.fanout', dispatchId, attempted: outcomes.length, sent },
      'push fan-out complete',
    );
    return { attempted: outcomes.length, sent, outcomes };
  }

  private async deliverOne(
    dispatchId: string,
    message: PushMessage,
    target: PushTarget,
  ): Promise<PushDeliveryOutcome> {
    try {
      const { providerMessageId } = await this.deps.transport.deliver(message, target);
      await this.record(dispatchId, target.deviceTokenId, 'sent', providerMessageId, null);
      return {
        deviceTokenId: target.deviceTokenId,
        status: 'sent',
        providerMessageId,
        failureReason: null,
        unregistered: false,
      };
    } catch (error) {
      const unregistered = error instanceof UnregisteredTokenError;
      // The class name only: a vendor message can echo the device token.
      const failureReason = error instanceof Error ? error.name : 'UnknownError';
      if (unregistered) {
        await this.deps.devices.revokeById(target.deviceTokenId, 'unregistered');
        this.log.info(
          { event: 'push.token_revoked', deviceTokenId: target.deviceTokenId },
          'device token revoked: the vendor no longer recognises it',
        );
      } else {
        this.log.warn(
          { event: 'push.delivery_failed', dispatchId, failureReason },
          'push delivery failed',
        );
      }
      await this.record(dispatchId, target.deviceTokenId, 'failed', null, failureReason);
      return {
        deviceTokenId: target.deviceTokenId,
        status: 'failed',
        providerMessageId: null,
        failureReason,
        unregistered,
      };
    }
  }

  private async record(
    dispatchId: string,
    deviceTokenId: string,
    status: 'sent' | 'failed',
    providerMessageId: string | null,
    failureReason: string | null,
  ): Promise<void> {
    await this.deps.prisma.pushDelivery.create({
      data: { dispatchId, deviceTokenId, status, providerMessageId, failureReason },
    });
  }
}
