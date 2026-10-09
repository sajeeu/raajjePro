import { describe, expect, it } from 'vitest';

import { pauseCauseOf } from '../src/modules/bookings/recurring.js';

/**
 * §1c's honest framing, §1f: the paused banner names the provider only when
 * every miss in the run was theirs.
 */
describe('pauseCauseOf — whose three misses paused a series', () => {
  it('names the provider only when all three are on the provider’s side', () => {
    expect(pauseCauseOf(['declined', 'timed_out', 'no_open_slot'])).toBe('provider');
    expect(pauseCauseOf(['provider_unavailable', 'declined', 'declined'])).toBe('provider');
  });

  it('attributes a run blocked only by the customer’s own fee to the customer', () => {
    expect(pauseCauseOf(['customer_blocked', 'customer_blocked', 'customer_blocked'])).toBe(
      'customer',
    );
  });

  it('names neither party for a mix', () => {
    expect(pauseCauseOf(['declined', 'declined', 'customer_blocked'])).toBe('mixed');
    expect(pauseCauseOf(['customer_blocked', 'timed_out', 'customer_blocked'])).toBe('mixed');
  });

  it('names neither party for a pre-split could_not_ask, which cannot be told apart', () => {
    expect(pauseCauseOf(['declined', 'declined', 'could_not_ask'])).toBe('mixed');
    expect(pauseCauseOf(['could_not_ask', 'could_not_ask', 'could_not_ask'])).toBe('mixed');
  });
});
