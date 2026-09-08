import type { Clock } from '../../core/clock.js';
import type { PrismaClient } from '../../generated/prisma/client.js';

/**
 * "Alert if the email fallback exceeds 5% of accept prompts in a rolling day
 * — that indicates a push-integration regression, not user preference"
 * (§Phase 3c).
 */
export const FALLBACK_ALERT_RATE = 0.05;

/**
 * The metric is scoped to the accept prompt, exactly as the plan words it.
 * Emergency dispatches are excluded on purpose: they email in parallel every
 * single time by design, so folding them in would peg the rate near 100% and
 * the alert would never mean anything again.
 */
export const FALLBACK_METRIC_KIND = 'booking_accept_prompt' as const;

/** A rolling day. */
export const ROLLING_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * §5's email-deliverability targets, and why there are two of them: the 2% is
 * ours, the 5% is AWS's. SES places an account under review above 5% bounce
 * and can pause sending above 10%, so breaching it costs the channel itself.
 * Email is the only thing behind push, so losing it is not a degraded
 * notification — it is no notification.
 */
export const BOUNCE_WARN_RATE = 0.02;
export const BOUNCE_ALERT_RATE = 0.05;
export const COMPLAINT_ALERT_RATE = 0.001;

export interface HealthLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
  error(obj: Record<string, unknown>, msg: string): void;
}

export interface FallbackRate {
  prompts: number;
  fallbacks: number;
  /** Null when no prompts went out at all — a rate over zero is not zero, it is unknown. */
  rate: number | null;
  breaching: boolean;
}

export interface ReputationRate {
  sent: number;
  bounced: number;
  complained: number;
  bounceRate: number | null;
  complaintRate: number | null;
}

/**
 * The metrics §Phase 3c asks to be *watched* rather than merely collected.
 *
 * They are emitted as structured log records with stable `event` names, which
 * is where this phase's responsibility ends: §Phase 21 wires those into APM
 * and is where "the email-fallback alert fires when forced above threshold"
 * is proved end to end. Nothing here sends an email — Phase 10b owns admin
 * alerting and its recipient configuration does not exist yet, and an alert
 * about email delivery that is itself delivered by email is a poor design in
 * any case.
 */
export class NotificationHealth {
  constructor(private readonly deps: { prisma: PrismaClient; clock: Clock; log: HealthLogger }) {}

  async fallbackRate(now: Date = this.deps.clock()): Promise<FallbackRate> {
    // Bounded at BOTH ends. `gte` alone makes "the rolling day" mean
    // "everything since yesterday, including the future", which is wrong on
    // its face and quietly wrong whenever rows carry a clock that is not the
    // one asking — a backfill, a replayed job, a test moving time.
    const since = new Date(now.getTime() - ROLLING_WINDOW_MS);
    const where = {
      kind: FALLBACK_METRIC_KIND,
      createdAt: { gte: since, lte: now },
    } as const;
    const [prompts, fallbacks] = await Promise.all([
      this.deps.prisma.pushDispatch.count({ where }),
      this.deps.prisma.pushDispatch.count({ where: { ...where, emailSentAt: { not: null } } }),
    ]);
    const rate = prompts === 0 ? null : fallbacks / prompts;
    return { prompts, fallbacks, rate, breaching: rate !== null && rate > FALLBACK_ALERT_RATE };
  }

  async reputationRate(now: Date = this.deps.clock()): Promise<ReputationRate> {
    const since = new Date(now.getTime() - ROLLING_WINDOW_MS);
    const window = { gte: since, lte: now };
    const [sent, bounced, complained] = await Promise.all([
      // Everything the vendor accepted, whatever became of it afterwards —
      // that is the denominator SES itself uses.
      this.deps.prisma.emailMessage.count({
        where: {
          createdAt: window,
          status: { in: ['sent', 'delivered', 'bounced', 'complained', 'delivery_delayed'] },
        },
      }),
      this.deps.prisma.emailMessage.count({
        where: { createdAt: window, status: 'bounced' },
      }),
      this.deps.prisma.emailMessage.count({
        where: { createdAt: window, status: 'complained' },
      }),
    ]);
    return {
      sent,
      bounced,
      complained,
      bounceRate: sent === 0 ? null : bounced / sent,
      complaintRate: sent === 0 ? null : complained / sent,
    };
  }

  /** Computes both and logs what it found, at a level that matches the reading. */
  async check(now: Date = this.deps.clock()): Promise<{
    fallback: FallbackRate;
    reputation: ReputationRate;
  }> {
    const [fallback, reputation] = await Promise.all([
      this.fallbackRate(now),
      this.reputationRate(now),
    ]);

    const fallbackRecord = {
      event: 'notification.fallback_rate',
      windowHours: ROLLING_WINDOW_MS / 3_600_000,
      kind: FALLBACK_METRIC_KIND,
      prompts: fallback.prompts,
      fallbacks: fallback.fallbacks,
      rate: fallback.rate,
      threshold: FALLBACK_ALERT_RATE,
    };
    if (fallback.breaching) {
      this.deps.log.error(
        fallbackRecord,
        'email fallback rate above 5% of accept prompts — suspect a push-integration regression',
      );
    } else {
      this.deps.log.info(fallbackRecord, 'email fallback rate within threshold');
    }

    const reputationRecord = {
      event: 'email.reputation',
      windowHours: ROLLING_WINDOW_MS / 3_600_000,
      sent: reputation.sent,
      bounced: reputation.bounced,
      complained: reputation.complained,
      bounceRate: reputation.bounceRate,
      complaintRate: reputation.complaintRate,
    };
    const bounceRate = reputation.bounceRate;
    const complaintRate = reputation.complaintRate;
    if (
      (bounceRate !== null && bounceRate > BOUNCE_ALERT_RATE) ||
      (complaintRate !== null && complaintRate > COMPLAINT_ALERT_RATE)
    ) {
      this.deps.log.error(
        reputationRecord,
        'email reputation at AWS review levels — SES can pause sending, which removes the only fallback channel',
      );
    } else if (bounceRate !== null && bounceRate > BOUNCE_WARN_RATE) {
      this.deps.log.warn(reputationRecord, 'email bounce rate above our own 2% target');
    } else {
      this.deps.log.info(reputationRecord, 'email reputation within targets');
    }

    return { fallback, reputation };
  }
}
