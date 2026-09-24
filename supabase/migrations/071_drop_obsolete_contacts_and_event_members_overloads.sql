-- Migration 070 replaced rpc_list_contacts(uuid) with
-- rpc_list_contacts(uuid, text, integer, integer) and left the old
-- 2-argument rpc_list_event_members(uuid, uuid) in place alongside the new
-- 9-argument rpc_list_event_members(...). Since every parameter the new
-- functions add beyond the old signature has a default, PostgREST cannot
-- always disambiguate a call against both overloads (and calling with only
-- p_tenant_id/p_event_id is genuinely ambiguous between "the 1-arg/2-arg
-- legacy function" and "the new function using all its defaults") -- this
-- surfaced in production as rpc_list_contacts requests failing outright,
-- and once the legacy rpc_list_contacts(uuid) was removed by hand, as
-- GET /api/v1/contacts silently returning zero rows (see app.ts's new
-- expectPaginatedListResponse guard, added in the same fix, for why that
-- symptom is now caught immediately instead of silently producing "0
-- contacts").
--
-- rpc_list_contacts(uuid) has already been dropped by hand directly in
-- production, so its drop below is `if exists` purely to keep this
-- migration idempotent/safe to run anywhere (fresh databases still have
-- it). rpc_list_event_members(uuid, uuid) has NOT been dropped anywhere
-- yet and is the actual live bug this migration fixes.
--
-- The new 4-arg / 9-arg functions (added in migration 070) are untouched.

drop function if exists public.rpc_list_contacts(uuid);
drop function if exists public.rpc_list_event_members(uuid, uuid);

notify pgrst, 'reload schema';
