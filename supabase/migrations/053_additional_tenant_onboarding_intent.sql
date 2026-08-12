create schema if not exists extensions;

create extension if not exists pgcrypto
with schema extensions;

do $$
declare
  pgcrypto_schema text;
begin
  select namespace.nspname into pgcrypto_schema
  from pg_extension extension
  join pg_namespace namespace on namespace.oid = extension.extnamespace
  where extension.extname = 'pgcrypto';

  if pgcrypto_schema is null then
    raise exception using
      errcode = '42883',
      message = 'pgcrypto extension is not available';
  end if;

  drop function if exists public.rpc_complete_tenant_onboarding(text, text, text, text, text, text, date, text, numeric, date, text);

  execute format($ddl$
    create or replace function public.rpc_complete_tenant_onboarding(
      p_plan_code text,
      p_tenant_name text,
      p_tenant_phone text,
      p_tenant_email text default null,
      p_first_event_name text default null,
      p_event_type text default 'OTHER',
      p_event_date date default null,
      p_venue text default null,
      p_target_amount numeric default null,
      p_pledge_deadline date default null,
      p_idempotency_key text default null,
      p_onboarding_intent text default 'FIRST_TENANT'
    )
    returns jsonb
    language plpgsql
    security definer
    set search_path = pg_catalog, public, %1$I
    as $function$
    declare
      caller uuid := auth.uid();
      key text;
      request_hash text;
      existing public.onboarding_requests%%rowtype;
      profile_record public.profiles%%rowtype;
      plan_record public.subscription_plans%%rowtype;
      role_record public.roles%%rowtype;
      tenant_id uuid;
      subscription_id uuid;
      event_id uuid;
      tenant_user_id uuid;
      tenant_code text;
      tenant_slug text;
      event_code text;
      v_result jsonb;
      normalized_phone text;
      normalized_intent text := upper(coalesce(nullif(p_onboarding_intent, ''), 'FIRST_TENANT'));
    begin
      if caller is null then
        raise exception 'SESSION_REQUIRED' using errcode = '28000';
      end if;
      if normalized_intent not in ('FIRST_TENANT', 'CREATE_ADDITIONAL_TENANT') then
        raise exception 'INVALID_INPUT' using errcode = '22023';
      end if;

      key := coalesce(nullif(p_idempotency_key, ''), md5(normalized_intent || ':' || coalesce(p_plan_code, '') || ':' || coalesce(p_tenant_name, '') || ':' || coalesce(p_first_event_name, '')));
      request_hash := encode(%1$I.digest(normalized_intent || ':' || coalesce(p_plan_code, '') || ':' || coalesce(p_tenant_name, '') || ':' || coalesce(p_tenant_phone, '') || ':' || coalesce(p_first_event_name, ''), 'sha256'), 'hex');

      perform pg_advisory_xact_lock(hashtextextended(caller::text || ':' || key, 7));

      select * into existing from public.onboarding_requests where user_id = caller and idempotency_key = key for update;
      if found and existing.result is not null then
        return existing.result;
      elsif found and existing.request_hash <> request_hash then
        raise exception 'INVALID_INPUT' using errcode = '22023';
      elsif not found then
        insert into public.onboarding_requests (user_id, idempotency_key, request_hash)
        values (caller, key, request_hash);
      end if;

      select * into profile_record from public.profiles where id = caller for update;
      if not found then
        raise exception 'SESSION_REQUIRED' using errcode = '28000';
      end if;
      if normalized_intent = 'FIRST_TENANT'
         and profile_record.onboarding_completed_at is not null
         and exists (
           select 1
           from public.tenant_users tu
           join public.tenants t on t.id = tu.tenant_id
           where tu.user_id = caller
             and tu.status <> 'REMOVED'
             and t.status not in ('ARCHIVED', 'CANCELLED')
         ) then
        raise exception 'ONBOARDING_ALREADY_COMPLETED' using errcode = '23505';
      end if;

      normalized_phone := public.normalize_tz_phone(p_tenant_phone);

      select * into plan_record
      from public.subscription_plans
      where code = upper(p_plan_code) and is_active and is_public
      for share;
      if not found or plan_record.max_active_events < 1 then
        raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
      end if;

      tenant_code := public.generate_tenant_code();
      tenant_slug := public.generate_unique_tenant_slug(p_tenant_name);

      insert into public.tenants (code, slug, name, phone_e164, email, status, created_by)
      values (tenant_code, tenant_slug, p_tenant_name, normalized_phone, nullif(p_tenant_email, ''), case when plan_record.trial_days > 0 then 'TRIAL' else 'ACTIVE' end, caller)
      returning id into tenant_id;

      insert into public.tenant_settings (tenant_id, receipt_prefix, default_event_type)
      values (tenant_id, replace(tenant_code, '-', ''), p_event_type);

      insert into public.tenant_subscriptions (
        tenant_id,
        plan_id,
        status,
        trial_ends_at,
        current_period_start,
        current_period_end,
        plan_snapshot
      )
      values (
        tenant_id,
        plan_record.id,
        case when plan_record.trial_days > 0 then 'TRIAL' else 'ACTIVE' end,
        case when plan_record.trial_days > 0 then now() + make_interval(days => plan_record.trial_days) else null end,
        now(),
        case when plan_record.billing_interval = 'MONTHLY' then now() + interval '1 month'
             when plan_record.billing_interval = 'QUARTERLY' then now() + interval '3 months'
             when plan_record.billing_interval = 'YEARLY' then now() + interval '1 year'
             else null end,
        jsonb_build_object(
          'code', plan_record.code,
          'name', plan_record.name,
          'currency', plan_record.currency,
          'price_amount', plan_record.price_amount,
          'billing_interval', plan_record.billing_interval,
          'max_active_events', plan_record.max_active_events,
          'max_members', plan_record.max_members,
          'max_users', plan_record.max_users,
          'included_sms', plan_record.included_sms,
          'features', plan_record.features
        )
      )
      returning id into subscription_id;

      insert into public.tenant_users (tenant_id, user_id, status, is_owner, joined_at)
      values (tenant_id, caller, 'ACTIVE', true, now())
      returning id into tenant_user_id;

      select * into role_record from public.roles r
      where r.code = 'TENANT_OWNER'
        and r.tenant_id is null;
      if not found then
        raise exception 'TENANT_OWNER_ROLE_MISSING' using errcode = '23503';
      end if;

      insert into public.tenant_user_roles (tenant_user_id, role_id, assigned_by)
      values (tenant_user_id, role_record.id, caller);

      event_code := public.next_event_code(tenant_id);
      insert into public.events (tenant_id, code, name, event_type, event_date, venue, target_amount, pledge_deadline, status, created_by)
      values (tenant_id, event_code, p_first_event_name, p_event_type, p_event_date, nullif(p_venue, ''), p_target_amount, p_pledge_deadline, 'ACTIVE', caller)
      returning id into event_id;

      insert into public.event_user_assignments (tenant_id, event_id, tenant_user_id, access_level, assigned_by)
      values (tenant_id, event_id, tenant_user_id, 'MANAGE', caller);

      update public.profiles
      set onboarding_completed_at = coalesce(onboarding_completed_at, now()), status = 'ACTIVE'
      where id = caller;

      perform public.write_audit_log(tenant_id, 'tenant.onboarded', 'tenant', tenant_id, null, null, jsonb_build_object('plan_code', plan_record.code, 'onboardingIntent', normalized_intent));
      perform public.write_audit_log(tenant_id, 'event.created', 'event', event_id, event_id, null, jsonb_build_object('event_code', event_code));

      v_result := jsonb_build_object(
        'tenant_id', tenant_id,
        'tenant_code', tenant_code,
        'tenant_slug', tenant_slug,
        'subscription_id', subscription_id,
        'event_id', event_id,
        'event_code', event_code,
        'onboarding_intent', normalized_intent
      );

      update public.onboarding_requests request
      set result = v_result
      where request.user_id = caller
        and request.idempotency_key = key;

      return v_result;
    end;
    $function$;
  $ddl$, pgcrypto_schema);
end;
$$;

revoke all on function public.rpc_complete_tenant_onboarding(text, text, text, text, text, text, date, text, numeric, date, text, text) from public;
grant execute on function public.rpc_complete_tenant_onboarding(text, text, text, text, text, text, date, text, numeric, date, text, text) to authenticated;
