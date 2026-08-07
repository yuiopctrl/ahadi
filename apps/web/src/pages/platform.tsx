import { useQuery } from '@tanstack/react-query'
import { Building2, MessageSquareText, Package, ShieldCheck } from 'lucide-react'
import { EmptyState, LoadingState, PageContainer, PageHeader, StatCard, StatusBadge } from '../components/ui'
import { api } from '../lib/api'

interface PlatformTenantRow {
  id: string
  code: string
  name: string
  phone_e164: string
  email: string | null
  status: string
  created_at: string
  plan_code: string | null
  plan_name: string | null
  subscription_status: string | null
  trial_ends_at: string | null
  current_period_end: string | null
  active_event_count: number
}

interface PlatformPlanRow {
  id: string
  code: string
  name: string
  currency: string
  price_amount: number
  billing_interval: string
  max_active_events: number
  max_users: number
  max_members: number
  included_sms: number
  is_active: boolean
  is_public: boolean
}

export function PlatformPage({ title }: { title: string }) {
  const dashboardQuery = useQuery({
    queryKey: ['platform-dashboard'],
    queryFn: async () => (await api.platformDashboard()).data,
    enabled: title === 'Overview',
  })
  const tenantsQuery = useQuery({
    queryKey: ['platform-tenants'],
    queryFn: async () => (await api.platformTenants()).data as PlatformTenantRow[],
    enabled: title === 'Tenants',
  })
  const plansQuery = useQuery({
    queryKey: ['platform-plans'],
    queryFn: async () => (await api.platformPlans()).data as PlatformPlanRow[],
    enabled: title === 'Packages & Subscriptions',
  })

  if (dashboardQuery.isLoading || tenantsQuery.isLoading || plansQuery.isLoading) {
    return (
      <PageContainer>
        <LoadingState title="Loading platform data" message="Checking authorized platform context." />
      </PageContainer>
    )
  }

  const stats = dashboardQuery.data

  return (
    <PageContainer>
      <PageHeader title={title} description="Platform owner controls for tenants, packages, SMS activity and audit oversight." />
      <section className="stats-grid">
        <StatCard label="Tenants" value={String(stats?.totalTenants ?? 0)} meta={`${stats?.activeTenants ?? 0} active`} icon={Building2} />
        <StatCard label="Trial Tenants" value={String(stats?.trialTenants ?? 0)} meta={`${stats?.suspendedTenants ?? 0} suspended`} icon={Package} />
        <StatCard label="Events" value={String(stats?.totalEvents ?? 0)} meta="Across all tenants" icon={MessageSquareText} />
        <StatCard label="Expiring Soon" value={String(stats?.subscriptionsExpiringSoon ?? 0)} meta="Next 14 days" icon={ShieldCheck} tone="warning" />
      </section>
      {title === 'Tenants' ? <TenantTable tenants={tenantsQuery.data ?? []} /> : title === 'Packages & Subscriptions' ? <PlansTable plans={plansQuery.data ?? []} /> : <OverviewPanel />}
      <EmptyState title="Protected platform boundary" message="Actions such as suspend, delete and impersonate are intentionally disabled for this phase." />
    </PageContainer>
  )
}

function OverviewPanel() {
  return (
    <article className="platform-panel">
      <div className="panel-header">
        <div>
          <h2>Platform Operations</h2>
          <p>Safe aggregate metrics only. Pledge financial totals will appear after pledge tables exist.</p>
        </div>
        <StatusBadge tone="success">Authorized</StatusBadge>
      </div>
    </article>
  )
}

function TenantTable({ tenants }: { tenants: PlatformTenantRow[] }) {
  return (
    <article className="platform-panel">
      <div className="panel-header">
        <div>
          <h2>Tenants</h2>
          <p>Subscription and active event status across the platform.</p>
        </div>
        <StatusBadge>Read-only</StatusBadge>
      </div>
      <div className="responsive-table" role="region" aria-label="Platform tenants">
        <table>
          <thead>
            <tr>
              <th>Code</th>
              <th>Name</th>
              <th>Status</th>
              <th>Plan</th>
              <th>Subscription</th>
              <th>Period</th>
              <th>Events</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {tenants.map((tenant) => (
                <tr key={tenant.id}>
                  <td>{tenant.code}</td>
                  <td>{tenant.name}</td>
                  <td>{tenant.status}</td>
                  <td>{tenant.plan_name ?? 'None'}</td>
                  <td>{tenant.subscription_status ?? 'None'}</td>
                  <td>{tenant.trial_ends_at ?? tenant.current_period_end ?? '-'}</td>
                  <td>{tenant.active_event_count ?? 0}</td>
                  <td>{new Date(tenant.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
    </article>
  )
}

function PlansTable({ plans }: { plans: PlatformPlanRow[] }) {
  return (
    <article className="platform-panel">
      <div className="panel-header">
        <div>
          <h2>Packages</h2>
          <p>Public package configuration and limits.</p>
        </div>
        <StatusBadge>Read-only</StatusBadge>
      </div>
      <div className="responsive-table" role="region" aria-label="Platform plans">
        <table>
          <thead>
            <tr>
              <th>Plan</th>
              <th>Price</th>
              <th>Interval</th>
              <th>Active events</th>
              <th>Users</th>
              <th>Members</th>
              <th>SMS</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {plans.map((plan) => (
              <tr key={plan.id}>
                <td>{plan.name}</td>
                <td>{new Intl.NumberFormat('en-TZ', { style: 'currency', currency: plan.currency, maximumFractionDigits: 0 }).format(Number(plan.price_amount))}</td>
                <td>{plan.billing_interval}</td>
                <td>{plan.max_active_events}</td>
                <td>{plan.max_users}</td>
                <td>{plan.max_members}</td>
                <td>{plan.included_sms}</td>
                <td>{plan.is_active ? 'Active' : 'Inactive'} · {plan.is_public ? 'Public' : 'Private'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </article>
  )
}
