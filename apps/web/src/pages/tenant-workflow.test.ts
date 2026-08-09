import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const tenantPage = readFileSync(new URL('./tenant.tsx', import.meta.url), 'utf8')
const navigation = readFileSync(new URL('../navigation.tsx', import.meta.url), 'utf8')
const styles = readFileSync(new URL('../index.css', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../lib/api.ts', import.meta.url), 'utf8')
const routes = readFileSync(new URL('../routes/index.tsx', import.meta.url), 'utf8')
const authPage = readFileSync(new URL('./auth.tsx', import.meta.url), 'utf8')
const guards = readFileSync(new URL('../routes/guards.tsx', import.meta.url), 'utf8')

test('tenant workflow does not depend on hardcoded demo event ids', () => {
  assert.doesNotMatch(navigation, /event_001/)
  assert.ok(navigation.includes("event ? `/app/events/${event.id}`"))
})

test('mobile more opens an overflow menu instead of linking directly to settings', () => {
  assert.doesNotMatch(navigation, /to: '\/app\/settings', label: 'More'/)
  assert.match(navigation, /MobileBottomNav\(\{ event, showPlatformLink/)
  assert.match(navigation, /mobile-more-menu/)
  assert.match(navigation, /overflowNav\(event, showPlatformLink\)/)
  for (const label of ['Pledges', 'Outstanding', 'Share List', 'Messages', 'Reports', 'Users', 'Settings']) {
    assert.match(navigation, new RegExp(label))
  }
})

test('registration intent survives OTP and allows onboarding after tenant reset', () => {
  assert.match(authPage, /location\.pathname === '\/register'/)
  assert.match(authPage, /localStorage\.setItem\(postAuthDestinationKey, '\/onboarding'\)/)
  assert.match(authPage, /preferredDestination === '\/onboarding' && accessibleMembershipCount\(context\) === 0/)
  assert.match(authPage, /!hasActivePlatformAccess\(context\) && accessibleMembershipCount\(context\) === 0/)
  assert.match(guards, /const hasAccessibleTenant = Boolean\(session\.userContext\?\.tenantMemberships\.some\(isAccessibleTenantMembership\)\)/)
  assert.match(guards, /onboardingCompleted && hasAccessibleTenant/)
})

test('financial pages render explicit empty and error states instead of blank lists', () => {
  for (const copy of [
    'No members have been added to this event yet.',
    'No pledges have been recorded yet.',
    'No payments have been recorded yet.',
    'Unable to load members',
    'Unable to load pledges',
    'Unable to load payments',
  ]) {
    assert.match(tenantPage, new RegExp(copy.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  }
  assert.doesNotMatch(tenantPage, /return null/)
})

test('record payment flow uses route event context and stable idempotency per attempt', () => {
  assert.match(tenantPage, /useActiveEventContext\(eventId\)/)
  assert.match(tenantPage, /const \[idempotencyKey, resetIdempotencyKey\] = useState\(\(\) => crypto\.randomUUID\(\)\)/)
  assert.match(tenantPage, /idempotencyKey, pledgeId/)
  assert.doesNotMatch(tenantPage, /idempotencyKey: crypto\.randomUUID\(\)/)
})

test('API client preserves structured errors and bypasses browser cache', () => {
  assert.match(apiClient, /requestId: string \| null/)
  assert.match(apiClient, /cache: 'no-store'/)
  assert.match(apiClient, /Cache-Control', 'no-cache'/)
})

test('payment confirmation SMS states are visible without waiting for delivery', () => {
  assert.match(tenantPage, /Payment recorded successfully/)
  assert.match(tenantPage, /Confirmation queued/)
  assert.match(tenantPage, /No phone number/)
  assert.match(tenantPage, /SMS disabled/)
  assert.match(tenantPage, /Send SMS notifications/)
  assert.match(tenantPage, /role="switch"/)
})

test('tenant SMS history route and cards are present', () => {
  assert.match(routes, /path: 'messages', element: <SmsHistoryPage \/>/)
  assert.match(apiClient, /messages: \(tenantId: string\)/)
  assert.match(apiClient, /messageWorkerDiagnostics: \(tenantId: string\)/)
  assert.match(apiClient, /processQueuedMessages: \(tenantId: string/)
  assert.match(tenantPage, /SMS delivery history and balance reminder controls/)
  assert.match(tenantPage, /messages-stats/)
  assert.match(tenantPage, /messages-list/)
  assert.match(tenantPage, /Send queued/)
  assert.match(tenantPage, /Worker queue check accepted/)
  assert.match(tenantPage, /workerDiagnostics\.claimableCount/)
  assert.match(tenantPage, /No SMS messages yet/)
  assert.match(tenantPage, /SMS delivery failed/)
})

test('share list page fetches by tenant and event and exposes explicit states', () => {
  assert.match(routes, /path: 'events\/:eventId\/share', element: <ShareListPage \/>/)
  assert.match(apiClient, /whatsappSharePreview: \(tenantId: string, eventId: string, payload/)
  assert.match(tenantPage, /queryKey: \['whatsapp-share-preview', tenantId, eventId, previewPayload\]/)
  assert.match(tenantPage, /enabled: canQuery && !settings\.isLoading/)
  assert.match(tenantPage, /Unable to load the share list\./)
  assert.match(tenantPage, /No pledge records are available for this list\./)
  assert.match(tenantPage, /Copy List/)
})

test('events page creates events from server subscription usage', () => {
  assert.match(apiClient, /createEvent: \(tenantId: string, payload/)
  assert.match(tenantPage, /subscriptionEventUsage\(subscription\)/)
  assert.match(tenantPage, /usage\.available > 0/)
  assert.match(tenantPage, /Your package allows \$\{usage\.limit\} active/)
  assert.match(tenantPage, /CreateEventForm/)
  assert.match(tenantPage, /await session\.selectTenant\(tenantId\)/)
  assert.match(tenantPage, /await session\.refreshContext\(\)/)
})

test('batch 4 report routes and report states are implemented', () => {
  for (const route of [
    "path: 'events/:eventId/reports'",
    "path: 'events/:eventId/reports/:reportType'",
  ]) {
    assert.match(routes, new RegExp(route.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  }
  assert.match(apiClient, /eventReport: \(tenantId: string, eventId: string, reportType: string/)
  for (const copy of ['Collection Summary', 'Pledge Report', 'Payment Methods', 'Collectors', 'Member Statement']) {
    assert.match(tenantPage, new RegExp(copy))
  }
  assert.match(tenantPage, /No pledges match the selected filters\./)
  assert.match(tenantPage, /No payments were found for this period\./)
  assert.match(tenantPage, /All recorded pledges are fully paid\./)
  assert.match(tenantPage, /Apply \{filterCount/)
  assert.match(tenantPage, /queryKey: \['event-report', tenantId, eventId, reportType, payload\]/)
})

test('batch 5 report export sheet and binary download client are implemented', () => {
  assert.match(apiClient, /apiDownload/)
  assert.match(apiClient, /exportEventReport: \(tenantId: string, eventId: string, reportType: string/)
  assert.match(apiClient, /Content-Disposition/)
  assert.match(tenantPage, /ExportReportSheet/)
  assert.match(tenantPage, /reportExportFormats/)
  assert.match(tenantPage, /Preparing report/)
  assert.match(tenantPage, /Report ready/)
  assert.match(tenantPage, /navigator\.share/)
  assert.match(tenantPage, /downloadReportBlob/)
  assert.match(tenantPage, /openPrintableReport/)
})

test('shared mobile UI has responsive overflow menu and safe card layouts', () => {
  assert.match(styles, /\.mobile-more-menu/)
  assert.match(styles, /\.mobile-more-grid/)
  assert.match(styles, /max-height: min\(68svh, 460px\)/)
  assert.match(styles, /\.amount-triplet,[\s\S]*grid-template-columns: 1fr/)
  assert.match(styles, /overflow-wrap: anywhere/)
  assert.match(styles, /@media \(min-width: 640px\)[\s\S]*\.amount-triplet/)
})

test('dashboard tabs, settings, and event nav active states are stabilized', () => {
  assert.match(navigation, /\{ to: '\/app\/events', label: 'Events', icon: CalendarDays, end: true \}/)
  assert.match(tenantPage, /settings-overview/)
  assert.match(tenantPage, /settings-grid/)
  assert.match(styles, /\.event-tabs a,[\s\S]*justify-content: center/)
  assert.match(styles, /\.event-tabs a,[\s\S]*text-align: center/)
  assert.match(styles, /@media \(min-width: 960px\)[\s\S]*\.settings-grid[\s\S]*grid-template-columns: repeat\(3, minmax\(0, 1fr\)\)/)
})
