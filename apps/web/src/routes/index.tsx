import { createBrowserRouter, Navigate } from 'react-router-dom'
import { AuthLayout } from '../layouts/AuthLayout'
import { PlatformAppLayout } from '../layouts/PlatformAppLayout'
import { TenantAppLayout } from '../layouts/TenantAppLayout'
import { AuthPage } from '../pages/auth'
import { PlatformBetaPage, PlatformBillingGatewaysPage, PlatformBillingReconciliationPage, PlatformErrorsPage, PlatformFeaturesPage, PlatformFeedbackPage, PlatformPage, PlatformSmsProvidersPage, PlatformSupportPage, PlatformTenantDetailPage } from '../pages/platform'
import { ContactDetailPage, ContactsPage, EventDetailPage, MemberDetailPage, OutstandingPage, PaymentEntryPage, ReceiptPage, ReportsPage, ShareListPage, SmsHistoryPage, SmsSettingsPage, SmsTemplatesPage, TenantBillingInvoicePage, TenantBillingPage, TenantDashboardPage, TenantHelpPage, TenantListPage, TenantSettingsPage, TenantUsersPage } from '../pages/tenant'
import { AuthenticatedRoute, OnboardingRoute, PinUnlockedRoute, PlatformGuard, PublicRoute, TenantRoute } from './guards'

export const router = createBrowserRouter([
  {
    element: <PublicRoute />,
    children: [
      {
        element: <AuthLayout />,
        children: [
          { path: '/login', element: <AuthPage mode="login" title="Sign in to Ahadi" subtitle="For existing Ahadi users with an organization, platform role, or both." /> },
          { path: '/platform/login', element: <AuthPage mode="login" title="Ahadi Platform Administration" subtitle="Sign in to manage Ahadi tenants and platform operations." /> },
          { path: '/forgot-pin', element: <AuthPage mode="forgotPin" title="Reset PIN" subtitle="Verify your phone number, set a new PIN, and continue to Ahadi." /> },
          { path: '/verify-otp', element: <AuthPage mode="otp" title="Verify OTP" subtitle="Enter the code sent to your phone." /> },
          { path: '/register', element: <AuthPage mode="register" title="Create your Ahadi organization" subtitle="Start a new organization for events, pledges and payments." /> },
        ],
      },
    ],
  },
  {
    element: <AuthenticatedRoute />,
    children: [
      {
        element: <AuthLayout />,
        children: [{ path: '/setup-pin', element: <AuthPage mode="pin" title="Set up PIN" subtitle="Create a secure PIN for fast mobile access." /> }],
      },
    ],
  },
  {
    element: <OnboardingRoute />,
    children: [
      { path: '/onboarding', element: <AuthPage mode="onboarding" title="Onboarding" subtitle="Confirm your tenant profile and event defaults." /> },
      { path: '/organizations/new', element: <AuthPage mode="onboarding" title="Create another organization" subtitle="This organization will have its own events, users, settings and subscription." /> },
    ],
  },
  {
    element: <AuthenticatedRoute />,
    children: [
      {
        element: <PinUnlockedRoute />,
        children: [
          {
            path: '/select-tenant',
            element: <AuthPage mode="selectTenant" title="Select Tenant" subtitle="Choose the tenant workspace to open." />,
          },
          {
            path: '/choose-workspace',
            element: <AuthPage mode="workspace" title="Choose Workspace" subtitle="Choose where you want to work in Ahadi." />,
          },
          {
            element: <TenantRoute />,
            children: [
              {
                path: '/app',
                element: <TenantAppLayout />,
                children: [
                  { index: true, element: <TenantDashboardPage /> },
                  { path: 'events', element: <TenantListPage title="Events" kind="events" /> },
                  { path: 'events/:eventId', element: <EventDetailPage /> },
                  { path: 'events/:eventId/members', element: <EventDetailPage section="members" /> },
                  { path: 'events/:eventId/members/:eventMemberId', element: <MemberDetailPage /> },
                  { path: 'events/:eventId/pledges', element: <EventDetailPage section="pledges" /> },
                  { path: 'events/:eventId/outstanding', element: <OutstandingPage /> },
                  { path: 'events/:eventId/share', element: <ShareListPage /> },
                  { path: 'events/:eventId/reports', element: <ReportsPage /> },
                  { path: 'events/:eventId/reports/:reportType', element: <ReportsPage /> },
                  { path: 'events/:eventId/payments', element: <EventDetailPage section="payments" /> },
                  { path: 'events/:eventId/payments/new', element: <PaymentEntryPage /> },
                  { path: 'events/:eventId/messages', element: <EventDetailPage section="messages" /> },
                  { path: 'receipts/:receiptId', element: <ReceiptPage /> },
                  { path: 'contacts', element: <ContactsPage /> },
                  { path: 'contacts/:memberId', element: <ContactDetailPage /> },
                  { path: 'members', element: <ContactsPage /> },
                  { path: 'payments', element: <TenantListPage title="Payments" kind="payments" /> },
                  { path: 'messages', element: <SmsHistoryPage /> },
                  { path: 'messages/templates', element: <SmsTemplatesPage /> },
                  { path: 'messages/settings', element: <SmsSettingsPage /> },
                  { path: 'reports', element: <ReportsPage /> },
                  { path: 'users', element: <TenantUsersPage /> },
                  { path: 'help', element: <TenantHelpPage /> },
                  { path: 'settings', element: <TenantSettingsPage /> },
                  { path: 'settings/messages', element: <SmsSettingsPage /> },
                  { path: 'settings/billing', element: <TenantBillingPage /> },
                  { path: 'settings/billing/invoices/:invoiceId', element: <TenantBillingInvoicePage /> },
                ],
              },
            ],
          },
          {
            element: <PlatformGuard />,
            children: [
              {
                path: '/platform',
                element: <PlatformAppLayout />,
                children: [
                  { index: true, element: <PlatformPage title="Overview" /> },
                  { path: 'beta', element: <PlatformBetaPage /> },
                  { path: 'tenants', element: <PlatformPage title="Tenants" /> },
                  { path: 'tenants/:tenantId', element: <PlatformTenantDetailPage /> },
                  { path: 'support', element: <PlatformSupportPage /> },
                  { path: 'feedback', element: <PlatformFeedbackPage /> },
                  { path: 'features', element: <PlatformFeaturesPage /> },
                  { path: 'plans', element: <PlatformPage title="Packages & Subscriptions" /> },
                  { path: 'subscriptions', element: <PlatformPage title="Subscriptions" /> },
                  { path: 'billing/gateways', element: <PlatformBillingGatewaysPage /> },
                  { path: 'billing/reconciliation', element: <PlatformBillingReconciliationPage /> },
                  { path: 'sms', element: <PlatformSmsProvidersPage /> },
                  { path: 'system/errors', element: <PlatformErrorsPage /> },
                  { path: 'audit', element: <PlatformPage title="Audit Logs" /> },
                  { path: 'settings', element: <PlatformPage title="System Settings" /> },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
  { path: '*', element: <Navigate to="/app" replace /> },
])
