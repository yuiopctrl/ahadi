import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const viteConfig = readFileSync(new URL('../../vite.config.ts', import.meta.url), 'utf8')

test('production PWA refresh serves the SPA entry instead of the offline page', () => {
  assert.match(viteConfig, /navigateFallback: '\/index\.html'/)
  assert.match(viteConfig, /navigateFallbackDenylist: \[\/\^\\\/api\\\//)
  assert.match(viteConfig, /cleanupOutdatedCaches: true/)
  assert.match(viteConfig, /clientsClaim: true/)
  assert.match(viteConfig, /skipWaiting: true/)
  assert.doesNotMatch(viteConfig, /navigateFallback: '\/offline\.html'/)
})
