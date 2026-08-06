import { useQuery } from '@tanstack/react-query'
import { Building2, MessageSquareText, Package, ShieldCheck } from 'lucide-react'
import { EmptyState, LoadingState, PageContainer, PageHeader, StatCard, StatusBadge } from '../components/ui'
import { api } from '../lib/api'

interface PlatformTenantRow {
  id: string
  code: string
  name: string
  phone_e164: string
  status: string
  created_at: string
  tenant_subscriptions?: Array<{
    status: string
    trial_ends_at: string | null
    current_period_end: string | null
    subscription_plans?: { code: string; name: string } | null
  }>
  events?: Array<{ id: string; status: string }>
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

  if (dashboardQuery.isLoading || tenantsQuery.isLoading) {
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
      {title === 'Tenants' ? <TenantTable tenants={tenantsQuery.data ?? []} /> : <OverviewPanel />}
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
              <th>Phone</th>
              <th>Status</th>
              <th>Plan</th>
              <th>Subscription</th>
              <th>Period</th>
              <th>Events</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {tenants.map((tenant) => {
              const subscription = tenant.tenant_subscriptions?.[0]
              return (
                <tr key={tenant.id}>
                  <td>{tenant.code}</td>
                  <td>{tenant.name}</td>
                  <td>{tenant.phone_e164}</td>
                  <td>{tenant.status}</td>
                  <td>{subscription?.subscription_plans?.name ?? 'None'}</td>
                  <td>{subscription?.status ?? 'None'}</td>
                  <td>{subscription?.trial_ends_at ?? subscription?.current_period_end ?? '-'}</td>
                  <td>{tenant.events?.filter((event) => event.status === 'ACTIVE').length ?? 0}</td>
                  <td>{new Date(tenant.created_at).toLocaleDateString()}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </article>
  )
}
