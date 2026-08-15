import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const app = readFileSync(new URL('./app.ts', import.meta.url), 'utf8')

test('mobile users endpoint supports server-side search and pagination', () => {
  assert.match(app, /const listTenantUsersQuerySchema = z\.object/)
  assert.match(app, /app\.get\('\/api\/v1\/users'/)
  assert.match(app, /matchesNameOrPhoneSearch\(row, query\.search, \['full_name', 'fullName'\], \['phone_e164', 'phoneE164', 'phone'\]\)/)
  assert.match(app, /rows\.slice\(query\.offset, query\.offset \+ query\.limit\)/)
})

test('profile update only exposes full name and email', () => {
  const profileRoute = app.slice(
    app.indexOf("app.patch('/api/v1/profile'"),
    app.indexOf("app.post('/api/v1/auth/verify-pin'"),
  )
  assert.match(app, /const updateProfileSchema = z\.object/)
  assert.match(profileRoute, /app\.patch\('\/api\/v1\/profile'/)
  assert.match(profileRoute, /full_name: input\.fullName/)
  assert.match(profileRoute, /email: input\.email/)
  assert.doesNotMatch(profileRoute, /phone_e164: input/)
})
