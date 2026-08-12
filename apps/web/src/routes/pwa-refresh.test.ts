import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const viteConfig = readFileSync(new URL('../../vite.config.ts', import.meta.url), 'utf8')
const devServiceWorker = readFileSync(new URL('../../public/sw.js', import.meta.url), 'utf8')
const main = readFileSync(new URL('../main.tsx', import.meta.url), 'utf8')
const env = readFileSync(new URL('../lib/env.ts', import.meta.url), 'utf8')
const deployDoc = readFileSync(new URL('../../../../deploy.md', import.meta.url), 'utf8')

test('production PWA service worker self-destroys to stop cached offline refreshes', () => {
  assert.match(viteConfig, /selfDestroying: true/)
  assert.match(viteConfig, /registerType: 'autoUpdate'/)
  assert.doesNotMatch(viteConfig, /navigateFallback: '\/index\.html'/)
  assert.doesNotMatch(viteConfig, /navigateFallbackDenylist/)
  assert.doesNotMatch(viteConfig, /globPatterns/)
  assert.doesNotMatch(viteConfig, /globIgnores/)
  assert.doesNotMatch(viteConfig, /includeAssets: \['favicon\.svg', 'offline\.html'\]/)
  assert.doesNotMatch(viteConfig, /navigateFallback: '\/offline\.html'/)
})

test('platform and tenant refresh paths are left to normal SPA server routing', () => {
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

test('static offline page is not shipped as a refresh destination', () => {
  assert.doesNotMatch(viteConfig, /offline\.html/)
})

test('web builds are identifiable and deploy copies the latest dist', () => {
  assert.match(env, /VITE_BUILD_COMMIT/)
  assert.match(env, /buildCommit: parsed\.data\.VITE_BUILD_COMMIT/)
  assert.match(main, /Ahadi web \$\{env\.appVersion\} \(\$\{env\.buildCommit\}\)/)
  assert.match(deployDoc, /VITE_BUILD_COMMIT="\$\(git rev-parse --short HEAD\)" pnpm --filter web build/)
  assert.match(deployDoc, /rsync -av --delete apps\/web\/dist\/ \/var\/www\/ahadi\//)
  assert.doesNotMatch(deployDoc, /--filter @ahadi\/web build/)
})
