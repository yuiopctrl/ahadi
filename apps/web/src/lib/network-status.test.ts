import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const networkStatus = readFileSync(new URL('./network-status.tsx', import.meta.url), 'utf8')
const providers = readFileSync(new URL('../app/providers.tsx', import.meta.url), 'utf8')

test('network status starts from browser online state and does not show offline while checking', () => {
  assert.match(networkStatus, /export type NetworkStatus = 'checking' \| 'online' \| 'offline'/)
  assert.match(networkStatus, /navigator\.onLine === false[\s\S]+return 'offline'/)
  assert.match(networkStatus, /return 'checking'/)
  assert.match(networkStatus, /status === 'offline' \?/)
})

test('network status health check uses configured API URL and unauthenticated health endpoint', () => {
  assert.match(networkStatus, /apiUrl\.replace\(\/\\\/\$\/, ''\).*\/health/)
  assert.match(networkStatus, /credentials: 'omit'/)
  assert.match(networkStatus, /cache: 'no-store'/)
})

test('network status treats HTTP responses as online and only fetch failures as offline candidates', () => {
  assert.match(networkStatus, /await fetchHealth\(controller\.signal\)[\s\S]+return 'online'/)
  assert.match(networkStatus, /if \(!isConnectivityFailure\(error\)\) \{\s+return 'online'/)
  assert.match(networkStatus, /error instanceof TypeError/)
  assert.match(networkStatus, /AbortError/)
  assert.match(networkStatus, /attempts = 2/)
})

test('global providers include confirmed offline banner provider', () => {
  assert.match(providers, /NetworkStatusProvider/)
  assert.match(providers, /<NetworkStatusProvider>[\s\S]+<SessionProvider>/)
})
