import type { Clock } from '../../core/clock.js';
import type { PrismaClient, PushDispatch } from '../../generated/prisma/client.js';
import type {
  EmailFallbackReason,
  NotificationKind,
  NotificationUrgency,
} from '../../generated/prisma/enums.js';
import type { EmailSender } from '../email/types.js';
import { fallbackEmail, pushMessage } from './content.js';
import type { NotificationContext, PushSender } from './types.js';

/**
 * The half of the context that is stored on the row. `kind` is a column, so
 * it is rebuilt from there rather than written twice and allowed to disagree.
 */
export type StoredContext = Omit<NotificationContext, 'kind'>;

export function storeContext(context: NotificationContext): StoredContext {
  const { bookingType, customerFirstName, islandName } = context;
  return { bookingType, customerFirstName, islandName };
}

/**
 * Rebuilds the context from a stored row. A row written by an older build
 * could be missing a field; rather than send a mail reading "undefined", the
 * sweep treats that as unsendable and says so.
 */
export function readContext(kind: NotificationKind, stored: unknown): NotificationContext | null {
  if (typeof stored !== 'object' || stored === null) return null;
  const { bookingType, customerFirstName, islandName } = stored as Record<string, unknown>;
  if (
    typeof bookingType !== 'string' ||
    typeof customerFirstName !== 'string' ||
    typeof islandName !== 'string'
  ) {
    return null;
  }
  return { kind, bookingType, customerFirstName, islandName };
}

/**
 * How long a push may go unconfirmed before the email goes.
 *
 * §Phase 3c fixes this at 30 minutes and explains what it replaced: an earlier
 * revision said "fails to deliver within the acceptance window", and the
 * acceptance window is 24 hours — so a fallback could arrive at hour 23, on a
 * booking that had died at hour two. It is a constant here rather than a
 * config knob precisely so it cannot drift back onto some other window.
 */
export const FALLBACK_AFTER_MINUTES = 30;

export interface DispatchInput {
  userId: string;
  urgency: NotificationUrgency;
  context: NotificationContext;
  /** The booking this is about, when there is one. Not a foreign key — Phase 17 owns bookings. */
  subjectId?: string;
}

export interface DispatchResult {
  dispatchId: string;
  pushAttempted: number;
  pushSent: number;
  emailSent: boolean;
  emailReason: EmailFallbackReason | null;
  /** Set when the 30-minute rung is armed and the sweep job will decide later. */
  fallbackDueAt: Date | null;
}

export interface DispatcherLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

const noopLogger: DispatcherLogger = { info: () => undefined, warn: () => undefined };

/**
 * The fallback chain (§Phase 3c), and the only place it is written down.
 *
 * Three paths, and which one a notification takes is decided before anything
 * is sent:
 *
 *  1. **Emergency — push and email in parallel, always.** No ladder. The
 *     response window is 30 minutes (§1c, Round 22), which is the same length
 *     as the whole unconfirmed-delivery timer; waiting it out would mean the
 *     email arrives as the window closes.
 *
 *  2. **Push cannot arrive — email immediately, in parallel with the (futile)
 *     push attempt.** The plan names one case: OS permission already known
 *     denied. This build treats "no live device registration at all" the same
 *     way, under its own reason code, because the reasoning is identical —
 *     push cannot land, so waiting half an hour only makes the provider late.
 *     That extension is a decision, recorded in
 *     docs/decisions/15-phase-3c-push.md, not something the plan says.
 *     The push is still attempted, because permission state is the app's
 *     last report and the user may have turned it back on since.
 *
 *  3. **Push might arrive — send it, arm the timer.** `fallbackDueAt` is set
 *     to now + 30 minutes and the sweep job sends the email if, at that point,
 *     no device has acked. A vendor accepting the message is not an ack.
 *
 * Every path writes a `push_dispatch` row before anything leaves the process,
 * so an email that goes out is always attributable and the 5% metric can
 * never miss one.
 */
export class NotificationDispatcher {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      push: PushSender;
      email: EmailSender;
      clock: Clock;
      log?: DispatcherLogger;
    },
  ) {}

  private get log(): DispatcherLogger {
    return this.deps.log ?? noopLogger;
  }

  async dispatch(input: DispatchInput): Promise<DispatchResult> {
    const now = this.deps.clock();
    const user = await this.deps.prisma.user.findUnique({
      where: { id: input.userId },
      select: { id: true, pushPermission: true },
    });
    if (user === null) throw new Error(`no such user: ${input.userId}`);

    const liveDevices = await this.deps.prisma.deviceToken.count({
      where: { userId: input.userId, revokedAt: null },
    });

    const emergency = input.urgency === 'emergency';
    const reason: EmailFallbackReason | null = emergency
      ? 'emergency_parallel'
      : user.pushPermission === 'denied'
        ? 'permission_denied'
        : liveDevices === 0
          ? 'no_registered_device'
          : null;

    const dispatch = await this.deps.prisma.pushDispatch.create({
      data: {
        userId: input.userId,
        kind: input.context.kind,
        urgency: input.urgency,
        ...(input.subjectId === undefined ? {} : { subjectId: input.subjectId }),
        context: storeContext(input.context),
        createdAt: now,
        // Armed only on path 3. On paths 1 and 2 the email is going out right
        // now, so there is nothing for the sweep to come back to.
        fallbackDueAt:
          reason === null ? new Date(now.getTime() + FALLBACK_AFTER_MINUTES * 60_000) : null,
      },
    });

    // Push and email go out together, not in sequence: "in parallel with the
    // (futile) push attempt. Do not wait." Awaiting the push first would make
    // the immediate email as slow as the vendor call it was meant to bypass.
    const [pushResult] = await Promise.all([
      this.deps.push.send(input.userId, dispatch.id, pushMessage(dispatch.id, input.context)),
      reason === null ? Promise.resolve() : this.sendFallback(dispatch, input.context, reason, now),
    ]);

    if (reason !== null) {
      this.log.warn(
        {
          event: 'notification.fallback',
          dispatchId: dispatch.id,
          kind: input.context.kind,
          urgency: input.urgency,
          reason,
          liveDevices,
        },
        'email fallback invoked',
      );
    }

    return {
      dispatchId: dispatch.id,
      pushAttempted: pushResult.attempted,
      pushSent: pushResult.sent,
      emailSent: reason !== null,
      emailReason: reason,
      fallbackDueAt: reason === null ? (dispatch.fallbackDueAt ?? null) : null,
    };
  }

  /**
   * Sends the fallback mail and stamps the dispatch. Called on paths 1 and 2
   * inline, and by the sweep job on path 3 — one implementation, so the mail
   * and the bookkeeping cannot diverge between the rungs.
   *
   * Suppression is honoured by `EmailService` before the transport is ever
   * contacted (Phase 2), so a bounced-out address produces a `suppressed`
   * message row rather than a send. The dispatch still records the attempt:
   * "we tried and this address is dead" is exactly what Phase 10b needs to
   * see when asked whether a provider was reachable.
   */
  async sendFallback(
    dispatch: Pick<PushDispatch, 'id' | 'userId'>,
    context: NotificationContext,
    reason: EmailFallbackReason,
    now: Date,
  ): Promise<void> {
    // Read here rather than passed in: the sweep job calls this half an hour
    // after dispatch, by which time the address may have changed. One lookup,
    // one place, so both rungs mail wherever the account is now.
    const recipient = await this.deps.prisma.user.findUniqueOrThrow({
      where: { id: dispatch.userId },
      select: { email: true },
    });
    const outcome = await this.deps.email.send(
      fallbackEmail(recipient.email, dispatch.userId, context),
    );
    await this.deps.prisma.pushDispatch.update({
      where: { id: dispatch.id },
      data: {
        emailSentAt: now,
        emailReason: reason,
        emailMessageId: outcome.messageId,
        fallbackDueAt: null,
      },
    });
  }
}
