-- Splits `could_not_ask` into a provider-side and a customer-side reason, so
-- the paused banner can stop naming the provider for a week the customer's
-- own unsettled dispatch fee blocked. Additive: `could_not_ask` stays in the
-- type for rows written before the split, which cannot be told apart after
-- the fact and are attributed to neither party. Nothing writes it any more.
ALTER TYPE "recurring_miss_reason" ADD VALUE 'provider_unavailable';
ALTER TYPE "recurring_miss_reason" ADD VALUE 'customer_blocked';
