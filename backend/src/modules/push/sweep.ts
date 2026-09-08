import type { Clock } from '../../core/clock.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import { readContext, type NotificationDispatcher } from './dispatcher.js';

export interface SweepLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
  error(obj: Record<string, unknown>, msg: string): void;
}

/**
 * The third rung: "if push is permitted but delivery is unconfirmed after 30
 * minutes, send email" (§Phase 3c).
 *
 * A job, not a check-on-read (backend/CLAUDE.md: "If a transition should
 * happen at a time, a job makes it happen at that time"). Check-on-read would
 * be worse than useless here — nobody reads a dispatch row, so the email would
 * simply never go.
 *
 * A dispatch is due when its timer has passed, no device has acked it, and no
 * email has gone yet. Confirmation clears the timer implicitly by failing that
 * middle condition; the ack endpoint also nulls `fallbackDueAt` so the partial
 * index stays small.
 */
export class FallbackSweep {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      dispatcher: NotificationDispatcher;
      clock: Clock;
      log: SweepLogger;
    },
  ) {}

  async run(now: Date = this.deps.clock()): Promise<{ sent: number; skipped: number }> {
    const due = await this.deps.prisma.pushDispatch.findMany({
      where: { fallbackDueAt: { lte: now }, emailSentAt: null, confirmedAt: null },
      // Oldest first: if a backlog has built up, the provider who has been
      // waiting longest is the one who most needs the mail.
      orderBy: { fallbackDueAt: 'asc' },
      take: 500,
    });

    let sent = 0;
    let skipped = 0;
    for (const dispatch of due) {
      const context = readContext(dispatch.kind, dispatch.context);
      if (context === null) {
        skipped += 1;
        this.deps.log.error(
          { event: 'notification.fallback_unsendable', dispatchId: dispatch.id },
          'fallback email skipped: the stored notification context is unreadable',
        );
        // Clear the timer so an unreadable row is not retried every minute
        // forever. The row keeps `emailSentAt` null, which is the honest
        // record: no email went.
        await this.deps.prisma.pushDispatch.update({
          where: { id: dispatch.id },
          data: { fallbackDueAt: null },
        });
        continue;
      }
      try {
        await this.deps.dispatcher.sendFallback(dispatch, context, 'unconfirmed_after_window', now);
        sent += 1;
        this.deps.log.warn(
          {
            event: 'notification.fallback',
            dispatchId: dispatch.id,
            kind: dispatch.kind,
            urgency: dispatch.urgency,
            reason: 'unconfirmed_after_window',
          },
          'email fallback invoked',
        );
      } catch (error) {
        // One bad recipient must not stop the sweep for everyone behind it.
        // The row keeps its due timer, so the next run tries again.
        skipped += 1;
        this.deps.log.error(
          { err: error, dispatchId: dispatch.id },
          'fallback email failed to send',
        );
      }
    }
    return { sent, skipped };
  }
}
