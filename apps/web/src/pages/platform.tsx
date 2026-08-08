import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, Building2, CheckCircle2, Flag, HeartHandshake, MessageSquareText, Package, ShieldCheck } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { useState } from 'react'
import { EmptyState, ErrorState, LoadingState, PageContainer, PageHeader, StatCard, StatusBadge } from '../components/ui'
import { api } from '../lib/api'

interface PlatformTenantRow {
  id: string
  code: string
  name: string
  phone_e164: string
  email: string | null
  status: string
  lifecycle_tag?: string
  commercial_status?: string
  created_at: string
  plan_code: string | null
  plan_name: string | null
  subscription_status: string | null
  trial_ends_at: string | null
  current_period_end: string | null
  active_event_count: number
  member_count?: number
  failed_sms_count?: number
  health?: string
  health_warning?: string | null
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

function asString(value: unknown, fallback = '') {
  return typeof value === 'string' && value.trim() ? value : fallback
}

function asNumber(value: unknown, fallback = 0) {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

function asRows(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value as Record<string, unknown>[] : []
}

function formatDate(value: unknown) {
  const text = asString(value)
  return text ? new Date(text).toLocaleDateString() : '-'
}

function healthTone(value: unknown) {
  const health = asString(value, 'UNKNOWN')
  if (health === 'HEALTHY') return 'success'
  if (health === 'BLOCKED') return 'danger'
  return 'warning'
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
    return <PageContainer><LoadingState title="Loading platform data" message="Checking authorized platform context." /></PageContainer>
  }
  if (dashboardQuery.isError || tenantsQuery.isError || plansQuery.isError) {
    return <PageContainer><ErrorState title="Unable to load platform data" message="Refresh and try again." /></PageContainer>
  }

  const stats = dashboardQuery.data ?? {}

  return (
    <PageContainer>
      <PageHeader title={title} description="Platform owner controls for tenants, packages, SMS activity and audit oversight." />
      {title === 'Overview' ? (
        <>
          <section className="stats-grid">
            <StatCard label="Tenants" value={String(stats.totalTenants ?? 0)} meta={`${stats.activeTenants ?? 0} active`} icon={Building2} />
            <StatCard label="Trial Tenants" value={String(stats.trialTenants ?? 0)} meta={`${stats.suspendedTenants ?? 0} suspended`} icon={Package} />
            <StatCard label="Open Support" value={String(stats.openSupportRequests ?? 0)} meta={`${stats.newFeedbackItems ?? 0} new feedback`} icon={HeartHandshake} tone="warning" />
            <StatCard label="Error Signals" value={String(stats.frontendErrors14d ?? 0)} meta="Last 14 days" icon={AlertTriangle} tone="danger" />
          </section>
          <OverviewPanel />
        </>
      ) : null}
      {title === 'Tenants' ? <TenantTable tenants={tenantsQuery.data ?? []} /> : null}
      {title === 'Packages & Subscriptions' ? <PlansTable plans={plansQuery.data ?? []} /> : null}
      {!['Overview', 'Tenants', 'Packages & Subscriptions'].includes(title) ? <EmptyState title="Protected platform boundary" message="This area is reserved while its production workflow is finalized." /> : null}
    </PageContainer>
  )
}

export function PlatformBetaPage() {
  const queryClient = useQueryClient()
  const [inviteName, setInviteName] = useState('')
  const [lastCode, setLastCode] = useState<string | null>(null)
  const betaQuery = useQuery({ queryKey: ['platform-beta'], queryFn: async () => (await api.platformBeta()).data })
  const settings = betaQuery.data?.['settings'] as Record<string, unknown> | undefined
  const invitations = asRows(betaQuery.data?.['invitations'])
  const recentRegistrations = asRows(betaQuery.data?.['recentRegistrations'])
  const funnel = betaQuery.data?.['funnel'] as Record<string, unknown> | undefined
  const updateSettings = useMutation({
    mutationFn: async (registrationMode: string) => api.updateRolloutSettings({
      registrationMode,
      betaModeEnabled: settings?.['betaModeEnabled'] ?? true,
      defaultTrialDays: settings?.['defaultTrialDays'] ?? 14,
      supportEmail: settings?.['supportEmail'] ?? null,
      supportPhone: settings?.['supportPhone'] ?? null,
      maintenanceNotice: settings?.['maintenanceNotice'] ?? null,
      maintenanceMode: settings?.['maintenanceMode'] ?? 'OFF',
      minimumSupportedWebVersion: settings?.['minimumSupportedWebVersion'] ?? null,
    }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['platform-beta'] }),
  })
  const createInvite = useMutation({
    mutationFn: async () => api.createBetaInvitation({ intendedName: inviteName || null }),
    onSuccess: (result) => {
      setLastCode(asString(result.data.code))
      setInviteName('')
      void queryClient.invalidateQueries({ queryKey: ['platform-beta'] })
    },
  })

  if (betaQuery.isLoading) return <PageContainer><LoadingState title="Loading beta rollout" message="Gathering rollout status and invitations." /></PageContainer>
  if (betaQuery.isError) return <PageContainer><ErrorState title="Unable to load beta rollout" message="Check platform permissions and retry." /></PageContainer>

  return (
    <PageContainer>
      <PageHeader title="Beta Rollout" description="Control registration policy, invitations, activation signals and beta tenant health." />
      <section className="stats-grid">
        <StatCard label="Mode" value={asString(settings?.['registrationMode'], 'OPEN')} meta={settings?.['betaModeEnabled'] ? 'Beta enabled' : 'Beta disabled'} icon={Flag} />
        <StatCard label="Invitations" value={String(invitations.length)} meta={`${invitations.filter((item) => asString(item.status) === 'ACTIVE').length} active`} icon={ShieldCheck} />
        <StatCard label="Registrations" value={String(recentRegistrations.length)} meta="Recent workspaces" icon={Building2} />
        <StatCard label="Activation" value={String(asNumber(funnel?.['paymentRecorded']))} meta="Tenants with payments" icon={CheckCircle2} tone="success" />
      </section>
      <article className="platform-panel">
        <div className="panel-header">
          <div><h2>Registration Policy</h2><p>Existing tenants and platform login remain available in every mode.</p></div>
          <StatusBadge tone={asString(settings?.['registrationMode']) === 'PAUSED' ? 'warning' : 'success'}>{asString(settings?.['registrationMode'], 'OPEN')}</StatusBadge>
        </div>
        <div className="segmented-row">
          {['OPEN', 'INVITE_ONLY', 'PAUSED'].map((mode) => <button key={mode} type="button" className={asString(settings?.['registrationMode'], 'OPEN') === mode ? 'active' : ''} disabled={updateSettings.isPending} onClick={() => updateSettings.mutate(mode)}>{mode.replace('_', ' ')}</button>)}
        </div>
      </article>
      <article className="platform-panel">
        <div className="panel-header"><div><h2>Invitations</h2><p>Create one-time beta invite codes. Full codes are shown only immediately after creation.</p></div></div>
        <div className="inline-form">
          <input placeholder="Intended organization optional" value={inviteName} onChange={(event) => setInviteName(event.target.value)} />
          <button type="button" disabled={createInvite.isPending} onClick={() => createInvite.mutate()}>{createInvite.isPending ? 'Creating...' : 'Create Invite'}</button>
        </div>
        {lastCode ? <p className="success-note">New code: <strong>{lastCode}</strong></p> : null}
        <SimpleTable rows={invitations} columns={['displayCodeSuffix', 'status', 'intendedName', 'useCount', 'maxUses', 'expiresAt']} />
      </article>
      <article className="platform-panel">
        <div className="panel-header"><div><h2>Recent Registrations</h2><p>New workspaces and health warnings.</p></div></div>
        <SimpleTable rows={recentRegistrations} columns={['code', 'name', 'lifecycleTag', 'commercialStatus', 'health', 'createdAt']} />
      </article>
    </PageContainer>
  )
}

export function PlatformSupportPage() {
  const queryClient = useQueryClient()
  const supportQuery = useQuery({ queryKey: ['platform-support'], queryFn: async () => (await api.platformSupport()).data })
  const [note, setNote] = useState('')
  const updateTicket = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => api.updatePlatformSupportRequest(id, { status, note: note || null }),
    onSuccess: () => {
      setNote('')
      void queryClient.invalidateQueries({ queryKey: ['platform-support'] })
    },
  })
  const rows = supportQuery.data ?? []

  if (supportQuery.isLoading) return <PageContainer><LoadingState title="Loading support desk" message="Fetching tenant support tickets." /></PageContainer>
  if (supportQuery.isError) return <PageContainer><ErrorState title="Unable to load support desk" message="Check platform support permission." /></PageContainer>

  return (
    <PageContainer>
      <PageHeader title="Support Desk" description="Tenant support queue with safe status updates and notes." />
      <article className="platform-panel">
        <div className="panel-header"><div><h2>Open Requests</h2><p>{rows.length} tickets in the support queue.</p></div></div>
        <div className="support-ticket-list">
          {rows.map((row) => (
            <section className="support-ticket" key={asString(row.id)}>
              <div><strong>{asString(row.ticket_number)} · {asString(row.subject)}</strong><span>{asString(row.tenant_name)} · {asString(row.category)} · {formatDate(row.created_at)}</span></div>
              <StatusBadge tone={asString(row.status) === 'OPEN' ? 'warning' : 'neutral'}>{asString(row.status)}</StatusBadge>
              <textarea placeholder="Resolution note optional" value={note} onChange={(event) => setNote(event.target.value)} />
              <div className="inline-actions">
                <button type="button" onClick={() => updateTicket.mutate({ id: asString(row.id), status: 'IN_PROGRESS' })}>Start</button>
                <button type="button" onClick={() => updateTicket.mutate({ id: asString(row.id), status: 'RESOLVED' })}>Resolve</button>
              </div>
            </section>
          ))}
        </div>
      </article>
    </PageContainer>
  )
}

export function PlatformFeedbackPage() {
  const query = useQuery({ queryKey: ['platform-feedback'], queryFn: async () => (await api.platformFeedback()).data })
  if (query.isLoading) return <PageContainer><LoadingState title="Loading feedback" message="Reading beta feedback." /></PageContainer>
  if (query.isError) return <PageContainer><ErrorState title="Unable to load feedback" message="Check feedback permission." /></PageContainer>
  return (
    <PageContainer>
      <PageHeader title="Feedback" description="Product feedback submitted from tenant workspaces." />
      <SimpleTable rows={query.data ?? []} columns={['tenant_name', 'category', 'message', 'page', 'status', 'created_at']} />
    </PageContainer>
  )
}

export function PlatformFeaturesPage() {
  const queryClient = useQueryClient()
  const query = useQuery({ queryKey: ['platform-features'], queryFn: async () => (await api.platformFeatures()).data })
  const mutation = useMutation({
    mutationFn: async (row: Record<string, unknown>) => api.updateFeatureFlag(asString(row.key), { enabledGlobally: !row.enabled_globally, betaOnly: row.beta_only }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['platform-features'] }),
  })
  if (query.isLoading) return <PageContainer><LoadingState title="Loading feature flags" message="Reading rollout switches." /></PageContainer>
  if (query.isError) return <PageContainer><ErrorState title="Unable to load feature flags" message="Check feature permission." /></PageContainer>
  return (
    <PageContainer>
      <PageHeader title="Feature Flags" description="Global beta-controlled features with server-side enforcement." />
      <article className="platform-panel">
        <div className="feature-flag-list">
          {(query.data ?? []).map((row) => (
            <section className="feature-flag-row" key={asString(row.key)}>
              <div><strong>{asString(row.key)}</strong><span>{asString(row.description)}</span></div>
              <StatusBadge tone={row.enabled_globally ? 'success' : 'danger'}>{row.enabled_globally ? 'Enabled' : 'Disabled'}</StatusBadge>
              <button type="button" disabled={mutation.isPending} onClick={() => mutation.mutate(row)}>{row.enabled_globally ? 'Disable' : 'Enable'}</button>
            </section>
          ))}
        </div>
      </article>
    </PageContainer>
  )
}

export function PlatformErrorsPage() {
  const query = useQuery({ queryKey: ['platform-errors'], queryFn: async () => (await api.platformErrors()).data })
  if (query.isLoading) return <PageContainer><LoadingState title="Loading errors" message="Aggregating frontend error reports." /></PageContainer>
  if (query.isError) return <PageContainer><ErrorState title="Unable to load errors" message="Check system error permission." /></PageContainer>
  return (
    <PageContainer>
      <PageHeader title="Error Signals" description="Frontend error reports grouped by code and route." />
      <SimpleTable rows={query.data ?? []} columns={['error_code', 'route', 'occurrences', 'last_seen_at']} />
    </PageContainer>
  )
}

export function PlatformTenantDetailPage() {
  const { tenantId = '' } = useParams()
  const queryClient = useQueryClient()
  const [days, setDays] = useState('7')
  const [reason, setReason] = useState('')
  const detailQuery = useQuery({ queryKey: ['platform-tenant-detail', tenantId], queryFn: async () => (await api.platformTenantDetail(tenantId)).data, enabled: Boolean(tenantId) })
  const extendTrial = useMutation({
    mutationFn: async () => api.extendPlatformTenantTrial(tenantId, { days: Number(days), reason }),
    onSuccess: () => {
      setReason('')
      void queryClient.invalidateQueries({ queryKey: ['platform-tenant-detail', tenantId] })
      void queryClient.invalidateQueries({ queryKey: ['platform-tenants'] })
    },
  })
  const supportSession = useMutation({ mutationFn: async () => api.startSupportSession(tenantId, { reason: reason || 'Platform support investigation', durationMinutes: 30 }) })

  if (detailQuery.isLoading) return <PageContainer><LoadingState title="Loading tenant detail" message="Reading tenant health and activation." /></PageContainer>
  if (detailQuery.isError) return <PageContainer><ErrorState title="Unable to load tenant" message="Check platform tenant permission." /></PageContainer>

  const tenant = detailQuery.data?.['tenant'] as Record<string, unknown> | undefined
  const health = detailQuery.data?.['health'] as Record<string, unknown> | undefined
  const milestones = detailQuery.data?.['milestones'] as Record<string, unknown> | undefined

  return (
    <PageContainer>
      <PageHeader title={asString(tenant?.['name'], 'Tenant Detail')} description={`${asString(tenant?.['code'])} · ${asString(tenant?.['status'])}`} action={<Link to="/platform/tenants">Back to tenants</Link>} />
      <section className="stats-grid">
        <StatCard label="Health" value={asString(health?.['state'], 'UNKNOWN')} meta={asString(health?.['warning'], 'No warning')} icon={ShieldCheck} tone={healthTone(health?.['state'])} />
        <StatCard label="Members" value={String(asNumber(health?.['members']))} meta={`${asNumber(health?.['users'])} users`} icon={Building2} />
        <StatCard label="Events" value={String(asNumber(health?.['activeEvents']))} meta="Draft or active" icon={Flag} />
        <StatCard label="Failed SMS" value={String(asNumber(health?.['failedSmsBacklog']))} meta="Backlog" icon={MessageSquareText} tone={asNumber(health?.['failedSmsBacklog']) > 0 ? 'danger' : 'success'} />
      </section>
      <article className="platform-panel">
        <div className="panel-header"><div><h2>Activation Checklist</h2><p>Milestones tracked from tenant activity.</p></div></div>
        <div className="checklist-grid">
          {Object.entries(milestones ?? {}).map(([key, value]) => <span key={key} className={value ? 'checked' : ''}>{value ? 'Done' : 'Open'} {key}</span>)}
        </div>
      </article>
      <article className="platform-panel">
        <div className="panel-header"><div><h2>Trial & Support</h2><p>Extend trial with an audited reason or start a short support context.</p></div></div>
        <div className="inline-form">
          <input inputMode="numeric" value={days} onChange={(event) => setDays(event.target.value)} />
          <input placeholder="Reason required" value={reason} onChange={(event) => setReason(event.target.value)} />
          <button type="button" disabled={extendTrial.isPending || reason.trim().length < 3} onClick={() => extendTrial.mutate()}>Extend Trial</button>
          <button type="button" disabled={supportSession.isPending || reason.trim().length < 5} onClick={() => supportSession.mutate()}>Start Support Session</button>
        </div>
      </article>
    </PageContainer>
  )
}

function OverviewPanel() {
  return (
    <article className="platform-panel">
      <div className="panel-header">
        <div>
          <h2>Platform Operations</h2>
          <p>Aggregate health, beta rollout, support and safety controls are available from the console navigation.</p>
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
        <div><h2>Tenants</h2><p>Subscription, activation and health status across the platform.</p></div>
        <StatusBadge>Read-only</StatusBadge>
      </div>
      <div className="responsive-table" role="region" aria-label="Platform tenants">
        <table>
          <thead>
            <tr><th>Code</th><th>Name</th><th>Health</th><th>Plan</th><th>Subscription</th><th>Period</th><th>Members</th><th>Events</th><th></th></tr>
          </thead>
          <tbody>
            {tenants.map((tenant) => (
              <tr key={tenant.id}>
                <td>{tenant.code}</td>
                <td>{tenant.name}</td>
                <td><StatusBadge tone={healthTone(tenant.health)}>{tenant.health ?? 'UNKNOWN'}</StatusBadge></td>
                <td>{tenant.plan_name ?? 'None'}</td>
                <td>{tenant.subscription_status ?? 'None'}</td>
                <td>{tenant.trial_ends_at ?? tenant.current_period_end ?? '-'}</td>
                <td>{tenant.member_count ?? 0}</td>
                <td>{tenant.active_event_count ?? 0}</td>
                <td><Link to={`/platform/tenants/${tenant.id}`}>Open</Link></td>
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
        <div><h2>Packages</h2><p>Public package configuration and limits.</p></div>
        <StatusBadge>Read-only</StatusBadge>
      </div>
      <div className="responsive-table" role="region" aria-label="Platform plans">
        <table>
          <thead>
            <tr><th>Plan</th><th>Price</th><th>Interval</th><th>Active events</th><th>Users</th><th>Members</th><th>SMS</th><th>Status</th></tr>
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

function SimpleTable({ rows, columns }: { rows: Record<string, unknown>[]; columns: string[] }) {
  if (!rows.length) return <EmptyState title="No records yet" message="New operational records will appear here when activity starts." />
  return (
    <article className="platform-panel">
      <div className="responsive-table">
        <table>
          <thead><tr>{columns.map((column) => <th key={column}>{column.replaceAll('_', ' ')}</th>)}</tr></thead>
          <tbody>
            {rows.map((row, index) => (
              <tr key={asString(row.id, String(index))}>{columns.map((column) => <td key={column}>{column.endsWith('_at') || column.endsWith('At') ? formatDate(row[column]) : asString(row[column], String(row[column] ?? '-'))}</td>)}</tr>
            ))}
          </tbody>
        </table>
      </div>
    </article>
  )
}
