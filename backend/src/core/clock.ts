/** Time is injected so idle timeouts and expiries are tested by moving a clock, not by waiting. */
export type Clock = () => Date;

export const systemClock: Clock = () => new Date();
