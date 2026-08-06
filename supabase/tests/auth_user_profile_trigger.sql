begin;

do $$
declare
  test_user_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    id,
    aud,
    role,
    phone,
    phone_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values (
    test_user_id,
    'authenticated',
    'authenticated',
    '+255712345678',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

  if not exists (
    select 1
    from public.profiles
    where id = test_user_id
      and phone_e164 = '+255712345678'
      and email is null
  ) then
    raise exception 'phone-only auth user profile trigger failed';
  end if;
end;
$$;

rollback;
