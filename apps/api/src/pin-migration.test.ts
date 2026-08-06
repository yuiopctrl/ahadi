import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/009_fix_pin_credentials_and_rpc.sql', import.meta.url), 'utf8')
const apiApp = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('PIN migration enables pgcrypto without moving an existing extension', () => {
  assert.match(migration, /create schema if not exists extensions;/i)
  assert.match(migration, /create extension if not exists pgcrypto\s+with schema extensions;/i)
  assert.match(migration, /select namespace\.nspname into pgcrypto_schema/i)
  assert.match(migration, /%1\$I\.crypt\(p_pin, %1\$I\.gen_salt\('bf', 10\)\)/)
})

test('PIN migration keeps credentials private and complete', () => {
  assert.match(migration, /create table if not exists private\.user_pin_credentials/i)
  for (const column of ['user_id uuid primary key references auth.users(id) on delete cascade', 'pin_hash text not null', 'failed_attempts integer not null default 0', 'locked_until timestamptz', 'last_changed_at timestamptz not null default now()', 'last_verified_at timestamptz', 'created_at timestamptz not null default now()', 'updated_at timestamptz not null default now()']) {
    assert.match(migration, new RegExp(column.replace(/[().]/g, '\\$&'), 'i'))
  }
  assert.match(migration, /revoke all on private\.user_pin_credentials from anon, authenticated;/i)
  assert.doesNotMatch(migration, /grant\s+.+on private\.user_pin_credentials\s+to authenticated/i)
})

test('rpc_set_my_pin stores only a hash and never returns it', () => {
  assert.match(migration, /create or replace function public\.rpc_set_my_pin\(p_pin text\)/i)
  assert.match(migration, /v_pin_hash := %1\$I\.crypt/i)
  assert.match(migration, /pin_hash = excluded\.pin_hash/i)
  assert.match(migration, /failed_attempts = 0/i)
  assert.match(migration, /locked_until = null/i)

  const setPinFunction = migration.slice(migration.indexOf('create or replace function public.rpc_set_my_pin'), migration.indexOf('create or replace function public.rpc_verify_my_pin'))
  const returnStatement = setPinFunction.match(/return jsonb_build_object\([\s\S]*?\);/i)?.[0] ?? ''
  assert.match(returnStatement, /'ok', true/i)
  assert.doesNotMatch(returnStatement, /pin_hash|v_pin_hash|p_pin/i)
})

test('API calls rpc_set_my_pin with the p_pin argument name', () => {
  assert.match(apiApp, /client\.rpc\('rpc_set_my_pin', \{ p_pin: input\.pin \}\)/)
  assert.doesNotMatch(apiApp, /client\.rpc\('rpc_set_my_pin', \{ pin: input\.pin \}\)/)
})
