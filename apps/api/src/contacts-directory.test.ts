import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import assert from 'node:assert/strict'
import test from 'node:test'

const root = join(process.cwd(), '..', '..')

function migration(name: string) {
  return readFileSync(join(root, 'supabase', 'migrations', name), 'utf8')
}

test('contacts directory migration preserves tenant contacts separate from event members', () => {
  const baseMembersMigration = migration('011_members_and_event_members.sql')
  const contactsMigration = migration('047_contacts_directory.sql')

  assert.match(baseMembersMigration, /create table public\.members/)
  assert.match(baseMembersMigration, /create table public\.event_members/)
  assert.match(baseMembersMigration, /unique \(event_id, member_id\)/)
  assert.match(baseMembersMigration, /member_id uuid not null references public\.members\(id\) on delete restrict/)

  assert.match(contactsMigration, /create or replace function public\.rpc_create_contact/)
  assert.match(contactsMigration, /insert into public\.members/)
  assert.doesNotMatch(contactsMigration.match(/create or replace function public\.rpc_create_contact[\s\S]+?end;\n\$\$/)?.[0] ?? '', /insert into public\.event_members/)
  assert.match(contactsMigration, /rpc_list_contacts_available_for_event/)
  assert.match(contactsMigration, /current_em\.id is null/)
  assert.match(contactsMigration, /rpc_get_contact_detail/)
  assert.match(contactsMigration, /em\.member_id = p_member_id/)
})
