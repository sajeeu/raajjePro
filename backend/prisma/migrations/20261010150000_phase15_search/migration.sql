-- §Phase 15 — Search & Discovery: "search endpoint with filters, sort,
-- pagination, appropriate indexes".
--
-- Hand-written throughout. Prisma has no syntax for extensions it does not
-- manage, for SQL functions, or for an expression index — and this migration
-- is nothing but those three. No table or column changes.

-- Both are PostgreSQL contrib modules, bundled with the stock image like
-- `btree_gist` (Phase 9a), so neither needs a package.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- The free-text fold — the SQL half of `modules/search/fold.ts`, and the same
-- three rules island search applies (§0.0 item 12, `location/normalise.ts`):
--
--   - **accents ignored**, so `male` finds `Malé` — `unaccent`;
--   - **the Dhivehi apostrophe ignored on both sides**, so `kondey` finds
--     `Kon'dey` — dropped outright, never turned into a word break;
--   - **case ignored** — `lower`.
--
-- Everything else that is not a letter or a digit becomes one space, so words
-- stay words and a typed `%` or `_` can never reach a LIKE as a wildcard.
--
-- Every name is schema-qualified: PostgreSQL 17+ builds an index under a
-- restricted search_path, so an unqualified call inside a function body is not
-- found there.
--
-- Declared IMMUTABLE so an index can be built on it. `unaccent(text)` alone is
-- only STABLE because it looks its dictionary up through `search_path`; naming
-- the dictionary explicitly is the documented way to make the call fixed.
CREATE FUNCTION public.rp_search_fold(value text) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
  AS $$
    SELECT btrim(regexp_replace(
      lower(regexp_replace(public.unaccent('public.unaccent'::regdictionary, value), '[''’ʼ`]', '', 'g')),
      '[^a-z0-9]+', ' ', 'g'))
  $$;

-- A listing's own searchable text: name, short description and tags (Phase 15
-- ruling Q4). The category name and the provider's business name are matched
-- through their own tables, so renaming either needs no rewrite here.
--
-- A function rather than an inline expression because `array_to_string` is
-- STABLE, and an index expression must be IMMUTABLE throughout. Over `text[]`
-- its output cannot change between calls; the wrapper says so.
CREATE FUNCTION public.rp_listing_search_doc(name text, short_description text, tags text[]) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$
    SELECT public.rp_search_fold(
      coalesce(name, '') || ' ' || coalesce(short_description, '') || ' ' || coalesce(array_to_string(tags, ' '), ''))
  $$;

-- Trigram GIN indexes: what makes `LIKE '%token%'` an index scan rather than a
-- sequential one. Matching is *anywhere* in the text, exactly as island search
-- matches anywhere in a name, so a b-tree prefix index would not serve it.
CREATE INDEX "listing_search_doc_trgm_idx"
  ON "listing" USING gin (public.rp_listing_search_doc("name", "short_description", "tags") public.gin_trgm_ops);

CREATE INDEX "provider_profile_business_name_trgm_idx"
  ON "provider_profile" USING gin (public.rp_search_fold(coalesce("business_name", '')) public.gin_trgm_ops);

-- The price sort and the price-range filter read these. Partial on what is
-- public, because nothing else is ever searched.
CREATE INDEX "listing_search_price_idx"
  ON "listing" ("price_laari", "price_min_laari")
  WHERE "status" = 'published' AND "visibility" = 'active' AND "deleted_at" IS NULL;
