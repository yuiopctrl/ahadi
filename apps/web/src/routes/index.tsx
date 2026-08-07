import { createBrowserRouter, Navigate } from 'react-router-dom'
import { AuthLayout } from '../layouts/AuthLayout'
import { PlatformAppLayout } from '../layouts/PlatformAppLayout'
import { TenantAppLayout } from '../layouts/TenantAppLayout'
import { AuthPage } from '../pages/auth'
import { PlatformPage } from '../pages/platform'
import { EventDetailPage, MemberDetailPage, OutstandingPage, PaymentEntryPage, ReceiptPage, ReportsPage, ShareListPage, SmsHistoryPage, TenantDashboardPage, TenantListPage, TenantSettingsPage, TenantUsersPage } from '../pages/tenant'
import { AuthenticatedRoute, OnboardingRoute, PinUnlockedRoute, PlatformOwnerRoute, PublicRoute, TenantRoute } from './guards'

export const router = createBrowserRouter([
  {
    element: <PublicRoute />,
    children: [
      {
        element: <AuthLayout />,
        children: [
          { path: '/login', element: <AuthPage mode="login" title="Welcome back" subtitle="Sign in with your phone number to continue." /> },
          { path: '/platform/login', element: <AuthPage mode="login" title="Platform Login" subtitle="Sign in with your phone number to open the platform console." /> },
          { path: '/verify-otp', element: <AuthPage mode="otp" title="Verify OTP" subtitle="Enter the code sent to your phone." /> },
          { path: '/register', element: <AuthPage mode="register" title="Register" subtitle="Create a tenant workspace for your committee." /> },
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
    children: [{ path: '/onboarding', element: <AuthPage mode="onboarding" title="Onboarding" subtitle="Confirm your tenant profile and event defaults." /> }],
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
                  { path: 'members', element: <TenantListPage title="Members" kind="members" /> },
                  { path: 'payments', element: <TenantListPage title="Payments" kind="payments" /> },
                  { path: 'messages', element: <SmsHistoryPage /> },
                  { path: 'reports', element: <ReportsPage /> },
                  { path: 'users', element: <TenantUsersPage /> },
                  { path: 'settings', element: <TenantSettingsPage /> },
                ],
              },
            ],
          },
          {
            element: <PlatformOwnerRoute />,
            children: [
              {
                path: '/platform',
                element: <PlatformAppLayout />,
                children: [
                  { index: true, element: <PlatformPage title="Overview" /> },
                  { path: 'tenants', element: <PlatformPage title="Tenants" /> },
                  { path: 'plans', element: <PlatformPage title="Packages & Subscriptions" /> },
                  { path: 'subscriptions', element: <PlatformPage title="Subscriptions" /> },
                  { path: 'sms', element: <PlatformPage title="SMS" /> },
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
