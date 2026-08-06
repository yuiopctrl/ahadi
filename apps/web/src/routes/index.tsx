import { createBrowserRouter, Navigate } from 'react-router-dom'
import { AuthLayout } from '../layouts/AuthLayout'
import { PlatformAppLayout } from '../layouts/PlatformAppLayout'
import { TenantAppLayout } from '../layouts/TenantAppLayout'
import { AuthPage } from '../pages/auth'
import { PlatformPage } from '../pages/platform'
import { EventDetailPage, TenantDashboardPage, TenantListPage } from '../pages/tenant'
import { AuthenticatedRoute, OnboardingRoute, PinUnlockedRoute, PlatformOwnerRoute, PublicRoute, TenantRoute } from './guards'

export const router = createBrowserRouter([
  {
    element: <PublicRoute />,
    children: [
      {
        element: <AuthLayout />,
        children: [
          { path: '/login', element: <AuthPage mode="login" title="Welcome back" subtitle="Sign in with your phone number to continue." /> },
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
                  { path: 'events/:eventId/pledges', element: <EventDetailPage section="pledges" /> },
                  { path: 'events/:eventId/payments', element: <EventDetailPage section="payments" /> },
                  { path: 'events/:eventId/messages', element: <EventDetailPage section="messages" /> },
                  { path: 'members', element: <TenantListPage title="Members" kind="members" /> },
                  { path: 'payments', element: <TenantListPage title="Payments" kind="payments" /> },
                  { path: 'messages', element: <TenantListPage title="Messages" kind="messages" /> },
                  { path: 'reports', element: <TenantListPage title="Reports" kind="reports" /> },
                  { path: 'settings', element: <TenantListPage title="Settings" kind="settings" /> },
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
