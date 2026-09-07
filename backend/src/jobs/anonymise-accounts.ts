import type { AccountAnonymiser, DeletionBlocker } from '../modules/account/anonymise.js';
import type { JobDefinition } from './runner.js';

export const ANONYMISE_JOB_NAME = 'anonymise-deleted-accounts';

/** Every five minutes: anonymise frozen accounts that are due (plan §Phase 3). */
export function anonymiseAccountsJob(
  anonymiser: AccountAnonymiser,
  blocker: DeletionBlocker,
): JobDefinition {
  return {
    name: ANONYMISE_JOB_NAME,
    everyMs: 5 * 60_000,
    async run(now) {
      await anonymiser.runDue(now, blocker);
    },
  };
}
