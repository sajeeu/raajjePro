import {
  ANONYMISE_JOB_NAME,
  type AccountAnonymiser,
  type DeletionBlocker,
} from '../modules/account/anonymise.js';
import type { JobDefinition, JobLogger } from './runner.js';

export { ANONYMISE_JOB_NAME };

/** Every five minutes: anonymise frozen accounts that are due (plan §Phase 3). */
export function anonymiseAccountsJob(
  anonymiser: AccountAnonymiser,
  blocker: DeletionBlocker,
  log: JobLogger,
): JobDefinition {
  return {
    name: ANONYMISE_JOB_NAME,
    everyMs: 5 * 60_000,
    async run(now) {
      const { processed, failed } = await anonymiser.runDue(now, blocker);
      log.info({ job: ANONYMISE_JOB_NAME, processed, failed }, 'anonymisation run complete');
    },
  };
}
