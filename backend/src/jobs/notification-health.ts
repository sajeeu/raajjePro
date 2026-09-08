import type { NotificationHealth } from '../modules/push/health.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const NOTIFICATION_HEALTH_JOB_NAME = 'notification-health';

/**
 * Every five minutes, compute the two rolling-day rates §Phase 3c asks to be
 * watched and emit them (`NotificationHealth.check` decides the level). The
 * window is a day, so five minutes is ample; the point is that the numbers
 * reach the log continuously rather than only when someone goes looking.
 */
export function notificationHealthJob(health: NotificationHealth, log: JobLogger): JobDefinition {
  return {
    name: NOTIFICATION_HEALTH_JOB_NAME,
    everyMs: 5 * 60_000,
    async run(now) {
      const { fallback } = await health.check(now);
      log.info(
        { job: NOTIFICATION_HEALTH_JOB_NAME, breaching: fallback.breaching },
        'notification health check complete',
      );
    },
  };
}
