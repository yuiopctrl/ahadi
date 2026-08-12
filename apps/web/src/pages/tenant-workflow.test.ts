import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const tenantPage = readFileSync(new URL('./tenant.tsx', import.meta.url), 'utf8')
const navigation = readFileSync(new URL('../navigation.tsx', import.meta.url), 'utf8')
const tenantLayout = readFileSync(new URL('../layouts/TenantAppLayout.tsx', import.meta.url), 'utf8')
const sessionStore = readFileSync(new URL('../stores/session-store.tsx', import.meta.url), 'utf8')
const styles = readFileSync(new URL('../index.css', import.meta.url), 'utf8')
const apiClient = readFileSync(new URL('../lib/api.ts', import.meta.url), 'utf8')
const routes = readFileSync(new URL('../routes/index.tsx', import.meta.url), 'utf8')
const authPage = readFileSync(new URL('./auth.tsx', import.meta.url), 'utf8')
const guards = readFileSync(new URL('../routes/guards.tsx', import.meta.url), 'utf8')
const access = readFileSync(new URL('../routes/access.ts', import.meta.url), 'utf8')
const validation = readFileSync(new URL('../../../../packages/validation/src/index.ts', import.meta.url), 'utf8')
const onboardingIntentMigration = readFileSync(new URL('../../../../supabase/migrations/053_additional_tenant_onboarding_intent.sql', import.meta.url), 'utf8')

test('tenant workflow does not depend on hardcoded demo event ids', () => {
  assert.doesNotMatch(navigation, /event_001/)
  assert.ok(navigation.includes("event ? `/app/events/${event.id}`"))
})

test('tenant layout navigation follows the route event instead of the tenant default', () => {
  assert.match(tenantLayout, /useMatch\('\/app\/events\/:eventId\/\*'\)/)
  assert.match(tenantLayout, /const routeEventId = eventRouteMatch\?\.params\.eventId/)
  assert.match(tenantLayout, /const event = routeEvent \?\? storedEvent \?\? fallbackEvent/)
  assert.match(tenantLayout, /<DesktopSidebar tenant=\{tenant\} event=\{event\}/)
  assert.match(tenantLayout, /<MobileBottomNav event=\{event\}/)
  assert.match(tenantLayout, /onEventChange=\{handleEventChange\}/)
  assert.match(tenantLayout, /<EventSnapshotBar event=\{event\} \/>/)
  assert.doesNotMatch(tenantLayout, /<MobileActionBar/)
  assert.doesNotMatch(tenantLayout, /Switch active event/)
  assert.doesNotMatch(tenantLayout, /<MobileTopBar[^\\n]+onEventChange/)
  assert.match(navigation, /export function MobileTopBar\(\{ tenant, showPlatformLink = false \}/)
  assert.doesNotMatch(navigation, /<EventContextDisplay event=\{event\} \/>/)
  assert.match(sessionStore, /selectedEventStorageKey\(tenantId: string\)/)
  assert.match(sessionStore, /selectedEventId: string \| null/)
  assert.match(sessionStore, /selectEvent: \(eventId: string \| null\) => void/)
  assert.match(navigation, /\{ to: event \? eventBase : '\/app', label: 'Dashboard'/)
  assert.match(navigation, /\{ to: event \? eventBase : '\/app', label: 'Home'/)
  assert.match(navigation, /\{ to: event \? `\$\{eventBase\}\/payments` : '\/app\/payments', label: 'Payments'/)
  assert.match(navigation, /\{ to: event \? `\$\{eventBase\}\/reports` : '\/app\/reports', label: 'Reports'/)
  assert.match(navigation, /\{ to: event \? `\/app\/messages\?eventId=\$\{event\.id\}` : '\/app\/messages', label: 'Messages'/)
  assert.match(tenantPage, /session\.selectedEventId \? tenantContext\?\.events\.find/)
  assert.match(tenantPage, /const activeEvent = session\.selectedEventId \? eventOptions\.find/)
})

test('mobile app chrome stays minimal and avoids global record-payment actions', () => {
  assert.match(styles, /padding-bottom: calc\(var\(--bottom-nav-height\) \+ 18px \+ env\(safe-area-inset-bottom\)\)/)
  assert.match(styles, /\.event-snapshot-actions \{\s+display: none;/)
  assert.match(styles, /@media \(min-width: 640px\)[\s\S]+\.event-snapshot-actions \{\s+display: grid;/)
  assert.doesNotMatch(styles, /padding-bottom: calc\(var\(--bottom-nav-height\) \+ 94px/)
  assert.doesNotMatch(tenantPage, /activeEvent\.canCollect && eventStatus === 'ACTIVE' \? <Link className="desktop-primary-button" to=\{`\/app\/events\/\$\{eventId\}\/payments\/new`\}/)
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
  assert.match(authPage, /routeAfterAuthentication/)
  assert.match(authPage, /getPostAuthDestination\(context, preferredDestination\)/)
  assert.match(authPage, /localStorage\.removeItem\(postAuthDestinationKey\)/)
  assert.match(guards, /const hasAccessibleTenant = Boolean\(session\.userContext\?\.tenantMemberships\.some\(isAccessibleTenantMembership\)\)/)
  assert.match(guards, /onboardingCompleted && hasAccessibleTenant/)
})

test('existing users can explicitly create another organization without old tenant redirect', () => {
  assert.match(routes, /path: '\/organizations\/new'/)
  assert.match(guards, /const normalizedPath = location\.pathname\.replace/)
  assert.match(guards, /const isAdditionalOrganizationFlow = normalizedPath === '\/organizations\/new'/)
  assert.match(guards, /!isAdditionalOrganizationFlow && session\.userContext\?\.onboardingCompleted && hasAccessibleTenant/)
  assert.match(guards, /state=\{\{ from: location \}\}/)
  assert.match(authPage, /routeState\?\.from\?\.pathname === '\/organizations\/new'/)
  assert.match(authPage, /localStorage\.setItem\(postAuthDestinationKey, '\/organizations\/new'\)/)
  assert.match(authPage, /type OnboardingIntent = 'FIRST_TENANT' \| 'CREATE_ADDITIONAL_TENANT'/)
  assert.match(authPage, /onboardingIntent: intent/)
  assert.match(authPage, /additionalOrganizationDraftKey/)
  assert.match(authPage, /Create another organization/)
  assert.match(authPage, /This organization will have its own events, users, settings and subscription\./)
  assert.match(access, /normalizedRequestedPath === '\/onboarding' \|\| normalizedRequestedPath === '\/organizations\/new'/)
})

test('additional organization onboarding uses the same tenant transaction with explicit DB intent', () => {
  assert.match(validation, /onboardingIntent: z\.enum\(\['FIRST_TENANT', 'CREATE_ADDITIONAL_TENANT'\]\)/)
  assert.match(apiClient, /completeOnboarding: \(payload: OnboardingPayload\)/)
  assert.match(onboardingIntentMigration, /p_onboarding_intent text default 'FIRST_TENANT'/)
  assert.match(onboardingIntentMigration, /normalized_intent not in \('FIRST_TENANT', 'CREATE_ADDITIONAL_TENANT'\)/)
  assert.match(onboardingIntentMigration, /if normalized_intent = 'FIRST_TENANT'[\s\S]+ONBOARDING_ALREADY_COMPLETED/)
  assert.match(onboardingIntentMigration, /insert into public\.tenant_subscriptions \([\s\S]+tenant_id/)
  assert.match(onboardingIntentMigration, /insert into public\.tenant_users \(tenant_id, user_id, status, is_owner, joined_at\)/)
  assert.match(onboardingIntentMigration, /insert into public\.event_user_assignments/)
  assert.doesNotMatch(onboardingIntentMigration, /platform_users/)
})

test('platform auth routes preserve platform context instead of falling into tenant onboarding', () => {
  assert.match(guards, /const isPlatformRoute = location\.pathname === '\/platform' \|\| location\.pathname\.startsWith\('\/platform\/'\)/)
  assert.match(guards, /<Navigate to=\{isPlatformRoute \? '\/platform\/login' : '\/login'\}/)
  assert.match(guards, /resolveAuthenticatedDestination\(\{ context: session\.userContext, requestedPath: location\.pathname \}\)/)
  assert.match(authPage, /requestedPlatformPath = routeState\?\.from\?\.pathname\?\.startsWith\('\/platform'\) \? routeState\.from\.pathname : '\/platform'/)
  assert.match(authPage, /requestedPlatformPath === '\/platform\/login' \? '\/platform' : requestedPlatformPath/)
  assert.match(authPage, /hasActivePlatformAccess\(session\.userContext\)/)
  assert.match(routes, /element: <PlatformGuard \/>/)
  assert.match(guards, /export function PlatformGuard\(\)/)
  assert.match(guards, /export function PinUnlockedRoute\(\)[\s\S]+const location = useLocation\(\)[\s\S]+postAuthDestination = location\.pathname\.startsWith\('\/platform'\) \? location\.pathname : null[\s\S]+<Navigate to="\/setup-pin" replace state=\{postAuthDestination \? \{ postAuthDestination \} : undefined\}/)
})

test('auth entry points are explicit and dual-role generic login uses workspace chooser', () => {
  assert.match(routes, /path: '\/login', element: <AuthPage mode="login" title="Sign in to Ahadi"/)
  assert.match(routes, /path: '\/platform\/login', element: <AuthPage mode="login" title="Ahadi Platform Administration"/)
  assert.match(routes, /path: '\/register', element: <AuthPage mode="register" title="Create your Ahadi organization"/)
  assert.match(routes, /path: '\/choose-workspace'[\s\S]+mode="workspace"/)
  assert.match(authPage, /function WorkspaceChooserPage/)
  assert.match(authPage, /Organization[\s\S]+Manage events, contacts, pledges and payments/)
  assert.match(authPage, /Platform Administration[\s\S]+Manage Ahadi tenants and platform operations/)
  assert.match(authPage, /Create a new organization/)
  assert.match(authPage, /Platform administration/)
  assert.match(authPage, /I already have an account/)
  assert.match(authPage, /Create another organization/)
})

test('tenant guard does not use onboarding as the fallback for accounts without tenants', () => {
  assert.match(sessionStore, /export type AccessState/)
  assert.match(authPage, /No organization workspace is linked to this account yet\./)
  assert.match(authPage, /Create a new organization/)
})

test('organization switcher exposes active tenant switching and creation from inside the app', () => {
  assert.match(navigation, /Switch Organization/)
  assert.match(navigation, /Create another organization/)
  assert.match(authPage, /membership\.tenantId === session\.selectedTenantId \? `✓ \$\{membership\.tenantName\}`/)
  assert.match(authPage, /navigate\(memberships\.length \? '\/organizations\/new' : '\/register'\)/)
  const tenantSelectionPage = authPage.slice(authPage.indexOf('function TenantSelectionPage'), authPage.indexOf('function Input'))
  assert.doesNotMatch(tenantSelectionPage, /getSingleActiveMembership\(session\.userContext\)[\s\S]+navigate\('\/app'/)
  assert.match(sessionStore, /queryClient\.cancelQueries\(\)/)
  assert.match(sessionStore, /queryClient\.invalidateQueries\(\)/)
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

test('member detail page can edit member profile fields', () => {
  assert.match(apiClient, /updateMember: \(tenantId: string, memberId: string, payload/)
  assert.match(tenantPage, /permissions\.has\('members\.update'\)/)
  assert.match(tenantPage, /MemberEditForm/)
  assert.match(tenantPage, /api\.updateMember\(tenantId, memberId/)
  assert.match(tenantPage, /Save Changes/)
  assert.match(tenantPage, /SMS notifications/)
})

test('messages page can select and preview outstanding reminder SMS', () => {
  assert.match(tenantPage, /Outstanding SMS Reminders/)
  assert.match(tenantPage, /BalanceReminderSelection/)
  assert.match(tenantPage, /api\.eventOutstandingMembers\(tenantId, eventId\)/)
  assert.match(tenantPage, /templateCode: 'BALANCE_REMINDER'/)
  assert.match(tenantPage, /api\.sendBulkBalanceReminders\(tenantId, eventId/)
  assert.match(tenantPage, /Select All Ready/)
  assert.match(tenantPage, /Review Reminder SMS/)
})

test('messages page can select and preview completed pledge SMS', () => {
  assert.match(apiClient, /eventCompletedPledgeMembers/)
  assert.match(apiClient, /sendBulkCompletedPledgeSms/)
  assert.match(tenantPage, /Completed Pledge SMS/)
  assert.match(tenantPage, /CompletedPledgeSelection/)
  assert.match(tenantPage, /templateCode: 'PLEDGE_COMPLETED'/)
  assert.match(tenantPage, /Preview Completed SMS/)
  assert.match(tenantPage, /Review Completed Pledge SMS/)
})

test('record payment flow uses route event context and stable idempotency per attempt', () => {
  assert.match(tenantPage, /useActiveEventContext\(eventId\)/)
  assert.match(tenantPage, /const \[idempotencyKey, resetIdempotencyKey\] = useState\(\(\) => crypto\.randomUUID\(\)\)/)
  assert.match(tenantPage, /idempotencyKey, pledgeId/)
  assert.match(tenantPage, /api\.eventOutstandingMembers\(tenantId \?\? '', eventId\)/)
  assert.match(tenantPage, /recordPaymentRowsPerPage = 5/)
  assert.match(tenantPage, /recordPaymentSearchMinLength = 3/)
  assert.match(tenantPage, /recordPaymentSearchDebounceMs = 300/)
  assert.match(tenantPage, /const payableMembers = memberRows\.filter\(\(member\) => asNumber\(member\.outstandingAmount \?\? member\.outstanding_amount\) > 0 && paymentPledgeId\(member\)\)/)
  assert.match(tenantPage, /Enter at least 3 characters to search\./)
  assert.match(tenantPage, /searchReady\s+\? payableMembers\.filter/)
  assert.match(tenantPage, /pageSizeOptions=\{\[recordPaymentRowsPerPage\]\}/)
  assert.match(tenantPage, /PaymentMemberSnapshot/)
  assert.match(tenantPage, /Change member/)
  assert.match(tenantPage, /No active pledges available\./)
  assert.match(tenantPage, /disabled=\{mutation\.isPending \|\| !form\.pledgeId/)
  assert.doesNotMatch(tenantPage, /idempotencyKey: crypto\.randomUUID\(\)/)
})

test('tenant contacts table hides contact code column', () => {
  const contactsPage = tenantPage.slice(tenantPage.indexOf('export function ContactsPage()'), tenantPage.indexOf('function ContactActions'))
  assert.doesNotMatch(contactsPage, /header: 'Contact Code'/)
  assert.doesNotMatch(contactsPage, /searchPlaceholder="Search name, phone or contact code"/)
  assert.match(contactsPage, /searchPlaceholder="Search name or phone"/)
  assert.match(contactsPage, /header: 'Name'/)
  assert.match(contactsPage, /header: 'Phone'/)
  assert.match(contactsPage, /header: 'Events'/)
  assert.match(contactsPage, /header: 'Status'/)
  assert.match(contactsPage, /header: 'Actions'/)
})

test('event member removal rolls back pledge and payment state from the member detail page', () => {
  assert.match(apiClient, /removeEventMember: \(tenantId: string, eventId: string, eventMemberId: string, payload/)
  assert.match(tenantPage, /Remove member and roll back event finances/)
  assert.match(tenantPage, /api\.removeEventMember\(tenantId \?\? '', eventId, eventMemberId, \{ reason: removeReason \}\)/)
  assert.match(tenantPage, /Remove and Roll Back/)
  assert.match(tenantPage, /hasActivePledge\(member\) \? <Link className="desktop-primary-button"[\s\S]+Record Payment[\s\S]+Create Pledge/)
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
  assert.match(routes, /path: 'messages\/templates', element: <SmsTemplatesPage \/>/)
  assert.match(routes, /path: 'messages\/settings', element: <SmsSettingsPage \/>/)
  assert.match(routes, /path: 'settings\/messages', element: <SmsSettingsPage \/>/)
  assert.match(apiClient, /messages: \(tenantId: string\)/)
  assert.match(apiClient, /messageWorkerDiagnostics: \(tenantId: string\)/)
  assert.match(apiClient, /processQueuedMessages: \(tenantId: string/)
  assert.match(tenantPage, /SMS delivery history and balance reminder controls/)
  assert.match(tenantPage, /MessagesSubnav/)
  assert.match(tenantPage, /Message History/)
  assert.match(tenantPage, /to="\/app\/messages\/templates"/)
  assert.match(tenantPage, /to="\/app\/messages\/settings"/)
  assert.match(tenantPage, /export function SmsTemplatesPage/)
  assert.match(tenantPage, /export function SmsSettingsPage/)
  assert.match(tenantPage, /permissions\.has\('messages\.manage_templates'\)/)
  assert.match(tenantPage, /permissions\.has\('messages\.manage_settings'\)/)
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
  assert.match(tenantPage, /Include registered members without pledges/)
  assert.doesNotMatch(tenantPage, /disabled=\{effectiveFormat !== 'PRIVACY'\}/)
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
