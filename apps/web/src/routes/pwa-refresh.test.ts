import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const viteConfig = readFileSync(new URL('../../vite.config.ts', import.meta.url), 'utf8')
const devServiceWorker = readFileSync(new URL('../../public/sw.js', import.meta.url), 'utf8')
const offlinePage = readFileSync(new URL('../../public/offline.html', import.meta.url), 'utf8')
const main = readFileSync(new URL('../main.tsx', import.meta.url), 'utf8')

test('production PWA refresh serves the SPA entry instead of the offline page', () => {
  assert.match(viteConfig, /navigateFallback: '\/index\.html'/)
  assert.match(viteConfig, /navigateFallbackDenylist: \[\/\^\\\/api\\\//)
  assert.match(viteConfig, /cleanupOutdatedCaches: true/)
  assert.match(viteConfig, /clientsClaim: true/)
  assert.match(viteConfig, /skipWaiting: true/)
  assert.match(viteConfig, /registerType: 'autoUpdate'/)
  assert.match(viteConfig, /globIgnores: \['\*\*\/offline\.html'\]/)
  assert.doesNotMatch(viteConfig, /includeAssets: \['favicon\.svg', 'offline\.html'\]/)
  assert.doesNotMatch(viteConfig, /navigateFallback: '\/offline\.html'/)
})

test('platform and tenant refresh paths are covered by the SPA navigation fallback', () => {
  assert.match(viteConfig, /navigateFallback: '\/index\.html'/)
  assert.doesNotMatch(viteConfig, /navigateFallbackAllowlist: \[\/\^\\\/app/)
  assert.doesNotMatch(viteConfig, /navigateFallbackAllowlist: \[\/\^\\\/platform/)
})

test('development stale service workers are self-clearing', () => {
  assert.match(devServiceWorker, /self\.registration\.unregister\(\)/)
  assert.match(devServiceWorker, /caches\.keys\(\)/)
  assert.match(devServiceWorker, /client\.navigate\(client\.url\)/)
  assert.match(main, /navigator\.serviceWorker\.controller/)
  assert.match(main, /window\.location\.reload\(\)/)
})

test('cached offline page recovers automatically when browser is online', () => {
  assert.match(offlinePage, /if \(!navigator\.onLine\) return/)
  assert.match(offlinePage, /navigator\.serviceWorker\.getRegistrations\(\)/)
  assert.match(offlinePage, /registration\.unregister\(\)/)
  assert.match(offlinePage, /caches\.keys\(\)/)
  assert.match(offlinePage, /window\.location\.replace\(window\.location\.href\)/)
})
