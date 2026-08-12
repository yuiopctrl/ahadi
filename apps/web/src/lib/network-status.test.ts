import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const networkStatus = readFileSync(new URL('./network-status.tsx', import.meta.url), 'utf8')
const providers = readFileSync(new URL('../app/providers.tsx', import.meta.url), 'utf8')

test('network status starts checking and only shows offline after a runtime browser offline signal', () => {
  assert.match(networkStatus, /export type NetworkState = 'CHECKING' \| 'ONLINE' \| 'OFFLINE'/)
  assert.match(networkStatus, /function initialNetworkStatus\(\): NetworkState \{\s+return 'CHECKING'\s+\}/)
  assert.match(networkStatus, /const offlineEventGraceMs = 2500/)
  assert.match(networkStatus, /function handleOffline\(\) \{[\s\S]+window\.setTimeout/)
  assert.match(networkStatus, /navigator\.onLine === false/)
  assert.match(networkStatus, /setStatus\('OFFLINE'\)/)
  assert.match(networkStatus, /status === 'OFFLINE' \?/)
})

test('network status does not fetch health during refresh', () => {
  assert.doesNotMatch(networkStatus, /fetch\(/)
  assert.doesNotMatch(networkStatus, /healthUrl/)
  assert.doesNotMatch(networkStatus, /TypeError/)
  assert.match(networkStatus, /return online \? 'ONLINE' : 'OFFLINE'/)
  assert.doesNotMatch(networkStatus, /localStorage|sessionStorage|indexedDB|cookies/)
})

test('global providers include confirmed offline banner provider', () => {
  assert.match(providers, /NetworkStatusProvider/)
  assert.match(providers, /<NetworkStatusProvider>[\s\S]+<SessionProvider>/)
})
