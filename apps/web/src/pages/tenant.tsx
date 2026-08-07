import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  Clock3,
  CreditCard,
  FileText,
  Plus,
  Printer,
  Search,
  Share2,
  Users,
} from 'lucide-react'
import { useMemo, useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import type { EventSummary } from '@ahadi/types'
import { EmptyState, ErrorState, LoadingState, PageContainer, PageHeader, SearchInput, StatCard, StatusBadge } from '../components/ui'
import { api, ApiClientError } from '../lib/api'
import { useSessionStore } from '../stores/session-store'

type EventSection = 'overview' | 'members' | 'pledges' | 'payments' | 'messages'
type Row = Record<string, unknown>

const paymentMethods = ['CASH', 'M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA', 'BANK_TRANSFER', 'CHEQUE', 'OTHER']

function asString(value: unknown, fallback = '') {
  return typeof value === 'string' && value ? value : fallback
}

function asNumber(value: unknown) {
  const number = Number(value)
  return Number.isFinite(number) ? number : 0
}

function displayValue(value: unknown, fallback = 'Not set') {
  if (typeof value === 'string' && value) return value
  if (typeof value === 'number' && Number.isFinite(value)) return String(value)
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  return fallback
}

function asDate(value: unknown) {
  return typeof value === 'string' && value ? new Date(value).toLocaleDateString('en-TZ') : 'Not set'
}

function asDateTime(value: unknown) {
  return typeof value === 'string' && value ? new Date(value).toLocaleString('en-TZ') : 'Not set'
}

function moneyText(value: unknown) {
  return new Intl.NumberFormat('en-TZ', { style: 'currency', currency: 'TZS', maximumFractionDigits: 0 }).format(asNumber(value))
}

function statusTone(status: unknown): 'success' | 'warning' | 'danger' | 'neutral' {
  if (status === 'PAID' || status === 'CONFIRMED' || status === 'ACTIVE') return 'success'
  if (status === 'OVERDUE' || status === 'REVERSED' || status === 'CANCELLED') return 'danger'
  if (status === 'PARTIALLY_PAID' || status === 'PENDING') return 'warning'
  return 'neutral'
}

function errorMessage(error: unknown, fallback: string) {
  if (error instanceof ApiClientError) {
    return `${error.code}${error.requestId ? ` · Request ${error.requestId}` : ''}`
  }
  if (error instanceof Error) {
    return error.message
  }
  return fallback
}

function smsStatusText(notification: unknown) {
  const value = jsonRecord(notification)
  if (value.smsQueued === true) return 'Confirmation queued'
  if (value.reason === 'NO_PHONE') return 'No phone number'
  if (value.reason === 'SMS_DISABLED') return 'SMS disabled'
  if (value.reason === 'PAYMENT_REVERSED') return 'Payment reversed'
  return 'Not queued'
}

function jsonRecord(value: unknown): Row {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Row : {}
}

function maskPhone(value: unknown) {
  const phone = asString(value, '')
  return phone ? phone.replace(/[0-9](?=[0-9]{3})/g, '*') : 'No phone'
}

function useActiveEventContext(routeEventId: string | undefined) {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const tenantContext = session.selectedTenantContext
  const fallbackEvent = tenantContext?.events[0] ?? null
  const eventId = routeEventId ?? fallbackEvent?.id ?? ''
  const event = eventId ? tenantContext?.events.find((candidate) => candidate.id === eventId) ?? null : null
  const permissions = new Set(tenantContext?.permissions ?? session.userContext?.tenantMemberships.find((membership) => membership.tenantId === tenantId)?.permissions ?? [])
  const error = !tenantId
    ? 'Select a tenant first.'
    : !tenantContext
      ? 'Tenant context is not loaded.'
      : !eventId
        ? 'No active event is available for this tenant.'
        : !event
          ? 'This event does not belong to the selected tenant or is not accessible.'
          : null

  return {
    event,
    eventId,
    tenantId,
    eventStatus: event?.status ?? null,
    canView: permissions.has('events.view') || permissions.has('members.view') || permissions.has('pledges.view') || permissions.has('payments.view'),
    canCollect: permissions.has('members.create') || permissions.has('pledges.create') || permissions.has('payments.create'),
    canManage: permissions.has('events.update') || permissions.has('payments.reverse'),
    loading: session.isLoading,
    error,
  }
}

function invalidateEvent(queryClient: ReturnType<typeof useQueryClient>, tenantId: string, eventId: string) {
  void queryClient.invalidateQueries({ queryKey: ['event-financial-summary', tenantId, eventId] })
  void queryClient.invalidateQueries({ queryKey: ['event-members', tenantId, eventId] })
  void queryClient.invalidateQueries({ queryKey: ['event-pledges', tenantId, eventId] })
  void queryClient.invalidateQueries({ queryKey: ['event-payments', tenantId, eventId] })
}

export function TenantDashboardPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const event = session.selectedTenantContext?.events[0] ?? null

  if (!tenantId || !event) {
    return (
      <PageContainer>
        <EmptyState title="No active event" message="Create an event during onboarding or select a tenant with an active event." />
      </PageContainer>
    )
  }

  return <EventDetailPage />
}

export function TenantListPage({ title, kind }: { title: string; kind: 'events' | 'members' | 'payments' | 'messages' | 'reports' | 'settings' }) {
  const session = useSessionStore()
  const event = session.selectedTenantContext?.events[0] ?? null
  const eventLink = event ? `/app/events/${event.id}` : '/app'

  if (!event) {
    return (
      <PageContainer>
        <PageHeader title={title} description="Open an active event workspace to manage members, pledges, payments and receipts." />
        <EmptyState title="No active event" message="This tenant does not have an accessible event yet." />
      </PageContainer>
    )
  }

  return (
    <PageContainer>
      <PageHeader title={title} description="Open the active event workspace to manage members, pledges, payments and receipts." />
      <div className="toolbar-row">
        <SearchInput placeholder={`Search ${title.toLowerCase()}`} />
      </div>
      <section className="cards-list">
        <Link to={kind === 'members' ? `${eventLink}/members` : kind === 'payments' ? `${eventLink}/payments` : eventLink} className="summary-card">
          {kind === 'payments' ? <CreditCard size={20} aria-hidden /> : <CalendarDays size={20} aria-hidden />}
          <div>
            <strong>{event?.name ?? 'Current event'}</strong>
            <span>{kind === 'members' ? 'Member directory and pledge progress' : kind === 'payments' ? 'Collections and receipts' : 'Event financial overview'}</span>
          </div>
          <StatusBadge tone="success">Open</StatusBadge>
        </Link>
      </section>
    </PageContainer>
  )
}

export function EventDetailPage({ section = 'overview' }: { section?: EventSection }) {
  const params = useParams()
  const activeEvent = useActiveEventContext(params.eventId)
  const { tenantId, eventId, event, eventStatus } = activeEvent
  const [search] = useSearchParams()
  const queryClient = useQueryClient()
  const canQuery = Boolean(tenantId && eventId && !activeEvent.error)
  const summaryQuery = useQuery({ queryKey: ['event-financial-summary', tenantId, eventId], queryFn: async () => (await api.eventFinancialSummary(tenantId ?? '', eventId)).data, enabled: canQuery })
  const membersQuery = useQuery({ queryKey: ['event-members', tenantId, eventId], queryFn: async () => (await api.eventMembers(tenantId ?? '', eventId)).data, enabled: canQuery })
  const pledgesQuery = useQuery({ queryKey: ['event-pledges', tenantId, eventId], queryFn: async () => (await api.eventPledges(tenantId ?? '', eventId)).data, enabled: canQuery })
  const paymentsQuery = useQuery({ queryKey: ['event-payments', tenantId, eventId], queryFn: async () => (await api.eventPayments(tenantId ?? '', eventId)).data, enabled: canQuery })

  const summary = summaryQuery.data ?? {}
  const totalAllocated = asNumber(summary.totalAllocated ?? summary.totalAllocatedToPledges)
  const collectionPercent = asNumber(summary.totalPledged) > 0 ? Math.round((totalAllocated / asNumber(summary.totalPledged)) * 100) : 0

  if (activeEvent.loading || summaryQuery.isLoading) {
    return <LoadingState title="Loading event" message="Fetching pledge and payment totals." />
  }
  if (activeEvent.error) {
    return <ErrorState title="Unable to open event" message={activeEvent.error} />
  }
  if (summaryQuery.isError) {
    return <ErrorState title="Unable to load event" message={errorMessage(summaryQuery.error, 'Check event access and tenant context.')} />
  }
  if (!activeEvent.canView) {
    return <ErrorState title="Event access denied" message="Your tenant role does not include permission to view this event." />
  }

  return (
    <PageContainer>
      <PageHeader
        title={event?.name ?? 'Event Overview'}
        description={eventStatus === 'ACTIVE' ? (event?.eventDate ? `Event date ${asDate(event.eventDate)}` : 'Member pledges, installment collections and receipts.') : `Event status is ${eventStatus ?? 'unknown'}. Payments require an ACTIVE event.`}
        action={
          activeEvent.canCollect && eventStatus === 'ACTIVE' ? <Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new`}>
            <Plus size={18} aria-hidden />
            Record Payment
          </Link> : null
        }
      />
      <section className="stats-grid">
        <StatCard label="Total Pledged" value={moneyText(summary.totalPledged)} meta={`${asNumber(summary.membersWithPledges)} pledge members`} icon={Users} />
        <StatCard label="Collected" value={moneyText(totalAllocated)} meta={`${collectionPercent}% collected`} icon={CheckCircle2} tone="success" />
        <StatCard label="Outstanding" value={moneyText(summary.totalOutstanding)} meta={`${asNumber(summary.overdueCount)} overdue`} icon={Clock3} tone="warning" />
      </section>
      <nav className="event-tabs" aria-label="Event sections">
        {(['overview', 'members', 'pledges', 'payments'] as EventSection[]).map((item) => (
          <Link className={section === item ? 'active' : ''} key={item} to={item === 'overview' ? `/app/events/${eventId}` : `/app/events/${eventId}/${item}`}>
            {item}
          </Link>
        ))}
      </nav>
      {section === 'overview' ? (
        <OverviewCards eventId={eventId} summary={summary} payments={paymentsQuery.data ?? []} pledges={pledgesQuery.data ?? []} />
      ) : null}
      {section === 'members' ? (
        membersQuery.isLoading ? <LoadingState title="Loading members" message="Fetching event members." /> :
          membersQuery.isError ? <ErrorState title="Unable to load members" message={errorMessage(membersQuery.error, 'Members could not be loaded.')} /> :
            <MembersPanel tenantId={tenantId ?? ''} event={event} eventId={eventId} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId ?? '', eventId)} initialSearch={search.get('q') ?? ''} canCreate={activeEvent.canCollect} />
      ) : null}
      {section === 'pledges' ? (
        pledgesQuery.isLoading || membersQuery.isLoading ? <LoadingState title="Loading pledges" message="Fetching pledges and members." /> :
          pledgesQuery.isError ? <ErrorState title="Unable to load pledges" message={errorMessage(pledgesQuery.error, 'Pledges could not be loaded.')} /> :
            membersQuery.isError ? <ErrorState title="Unable to load members" message={errorMessage(membersQuery.error, 'Members could not be loaded for pledge creation.')} /> :
              <PledgesPanel tenantId={tenantId ?? ''} event={event} eventId={eventId} pledges={pledgesQuery.data ?? []} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId ?? '', eventId)} canCreate={activeEvent.canCollect} />
      ) : null}
      {section === 'payments' ? (
        paymentsQuery.isLoading ? <LoadingState title="Loading payments" message="Fetching installment payments." /> :
          paymentsQuery.isError ? <ErrorState title="Unable to load payments" message={errorMessage(paymentsQuery.error, 'Payments could not be loaded.')} /> :
            <PaymentsPanel tenantId={tenantId ?? ''} eventId={eventId} payments={paymentsQuery.data ?? []} summary={summary} refresh={() => invalidateEvent(queryClient, tenantId ?? '', eventId)} canCreate={activeEvent.canCollect && eventStatus === 'ACTIVE'} />
      ) : null}
    </PageContainer>
  )
}

function OverviewCards({ eventId, summary, payments, pledges }: { eventId: string; summary: Row; payments: Row[]; pledges: Row[] }) {
  return (
    <section className="finance-grid">
      <article className="content-panel">
        <div className="panel-header">
          <div>
            <h2>Collection Progress</h2>
            <p>{asNumber(summary.memberCount)} members, {asNumber(summary.fullyPaidCount)} fully paid.</p>
          </div>
          <StatusBadge tone="success">{asNumber(summary.fullyPaidCount)} paid</StatusBadge>
        </div>
        <div className="mini-stat-row">
          <span>Partial: {asNumber(summary.partiallyPaidCount)}</span>
          <span>Unpaid: {asNumber(summary.unpaidCount)}</span>
          <span>Overdue: {asNumber(summary.overdueCount)}</span>
        </div>
        <Link className="primary-button inline-action" to={`/app/events/${eventId}/payments/new`}>Record Payment</Link>
      </article>
      <article className="content-panel">
        <div className="panel-header">
          <div>
            <h2>Recent Payments</h2>
            <p>Latest confirmed and reversed installments.</p>
          </div>
        </div>
        <div className="finance-card-list">
          {payments.slice(0, 4).map((payment) => <PaymentCard key={asString(payment.payment_id)} payment={payment} eventId={eventId} />)}
          {!payments.length ? <EmptyState title="No payments yet" message="Record the first installment from the payment action." /> : null}
        </div>
      </article>
      <article className="content-panel">
        <div className="panel-header">
          <div>
            <h2>Upcoming Deadlines</h2>
            <p>Open pledges ordered by due date.</p>
          </div>
        </div>
        <div className="finance-card-list">
          {pledges.filter((pledge) => pledge.status !== 'PAID').slice(0, 4).map((pledge) => <PledgeCard key={asString(pledge.pledge_id)} pledge={pledge} eventId={eventId} />)}
          {!pledges.length ? <EmptyState title="No pledges yet" message="Create pledges from member or pledge pages." /> : null}
        </div>
      </article>
    </section>
  )
}

function MembersPanel({ tenantId, event, eventId, members, refresh, initialSearch, canCreate }: { tenantId: string; event: EventSummary | null; eventId: string; members: Row[]; refresh: () => void; initialSearch: string; canCreate: boolean }) {
  const [query, setQuery] = useState(initialSearch)
  const [showForm, setShowForm] = useState(false)
  const filtered = members.filter((member) => `${member.full_name ?? ''} ${member.phone_e164 ?? ''} ${member.member_code ?? ''}`.toLowerCase().includes(query.toLowerCase()))

  return (
    <section className="finance-section">
      <div className="toolbar-row">
        <label className="search-input">
          <Search size={18} aria-hidden />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search members" />
        </label>
        {canCreate ? <button className="desktop-primary-button" type="button" onClick={() => setShowForm(true)}>
          <Plus size={18} aria-hidden />
          Add Member
        </button> : null}
      </div>
      {showForm ? <MemberForm tenantId={tenantId} event={event} eventId={eventId} onDone={() => { setShowForm(false); refresh() }} /> : null}
      <div className="finance-card-list">
        {filtered.map((member) => <MemberCard key={asString(member.event_member_id)} member={member} eventId={eventId} />)}
        {!members.length ? <EmptyState title="No members have been added to this event yet." message={canCreate ? 'Use Add Member to register the first contributor.' : 'You do not have permission to add members.'} /> : null}
        {members.length > 0 && !filtered.length ? <EmptyState title="No members match your search." message="Try a different name, phone number or member code." /> : null}
      </div>
      {canCreate ? <button className="mobile-sticky-button" type="button" onClick={() => setShowForm(true)}>Add Member</button> : null}
    </section>
  )
}

function MemberForm({ tenantId, event, eventId, onDone }: { tenantId: string; event: EventSummary | null; eventId: string; onDone: () => void }) {
  const [form, setForm] = useState({ fullName: '', phone: '', alternativePhone: '', email: '', location: '', notes: '', smsEnabled: true, initialPledgeAmount: '', initialPledgeDueDate: '' })
  const mutation = useMutation({
    mutationFn: () => api.createEventMember(tenantId, eventId, { ...form, initialPledgeAmount: form.initialPledgeAmount ? Number(form.initialPledgeAmount) : null, initialPledgeDueDate: form.initialPledgeDueDate || null }),
    onSuccess: onDone,
  })
  return (
    <form className="mobile-sheet form-grid" onSubmit={(event) => { event.preventDefault(); mutation.mutate() }}>
      <Input label="Full name" value={form.fullName} onChange={(fullName) => setForm((current) => ({ ...current, fullName }))} />
      <Input label="Phone number" inputMode="tel" value={form.phone} onChange={(phone) => setForm((current) => ({ ...current, phone }))} />
      <Input label="Alternative phone optional" inputMode="tel" value={form.alternativePhone} onChange={(alternativePhone) => setForm((current) => ({ ...current, alternativePhone }))} />
      <Input label="Email optional" value={form.email} onChange={(email) => setForm((current) => ({ ...current, email }))} />
      <Input label="Location optional" value={form.location} onChange={(location) => setForm((current) => ({ ...current, location }))} />
      <Input label="Initial pledge optional" inputMode="decimal" value={form.initialPledgeAmount} onChange={(initialPledgeAmount) => setForm((current) => ({ ...current, initialPledgeAmount }))} />
      <Input label="Custom pledge due date optional" type="date" value={form.initialPledgeDueDate} onChange={(initialPledgeDueDate) => setForm((current) => ({ ...current, initialPledgeDueDate }))} />
      <p className="privacy-note">Default due date: {asDate(event?.pledgeDeadline)}. Leave blank to follow the event deadline.</p>
      <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
      <label className="switch-row">
        <span><strong>Send SMS notifications</strong><small>{form.phone ? 'Payment confirmations will be queued after receipt creation.' : 'Add a phone number to send payment confirmations.'}</small></span>
        <input type="checkbox" role="switch" checked={form.smsEnabled && Boolean(form.phone)} disabled={!form.phone} onChange={(event) => setForm((current) => ({ ...current, smsEnabled: event.target.checked }))} />
      </label>
      {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onDone}>Cancel</button>
        <button className="primary-button" type="submit" disabled={mutation.isPending}>{mutation.isPending ? 'Saving...' : 'Create Member'}</button>
      </div>
    </form>
  )
}

function MemberCard({ member, eventId }: { member: Row; eventId: string }) {
  const dueDate = member.effective_due_date ?? member.due_date
  return (
    <article className="finance-card">
      <div className="card-title-row">
        <div>
          <strong>{asString(member.full_name, 'Member')}</strong>
          <span>{asString(member.phone_e164, 'No phone')} · {asString(member.category, 'No category')}</span>
        </div>
        <StatusBadge tone={statusTone(member.pledge_status)}>{asString(member.pledge_status, 'NO PLEDGE')}</StatusBadge>
      </div>
      <div className="amount-triplet">
        <span><small>Pledged</small>{moneyText(member.pledged_amount)}</span>
        <span><small>Paid</small>{moneyText(member.total_allocated)}</span>
        <span><small>Outstanding</small>{moneyText(member.outstanding_amount)}</span>
      </div>
      {member.pledge_id ? <p className="privacy-note">Due {asDate(dueDate)} · {member.has_custom_due_date ? 'custom' : 'event default'}</p> : null}
      <div className="card-actions">
        <Link to={`/app/events/${eventId}/payments/new?eventMemberId=${asString(member.event_member_id)}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link>
        <Link to={`/app/events/${eventId}/members/${asString(member.event_member_id)}`}>Details</Link>
      </div>
    </article>
  )
}

function PledgesPanel({ tenantId, event, eventId, pledges, members, refresh, canCreate }: { tenantId: string; event: EventSummary | null; eventId: string; pledges: Row[]; members: Row[]; refresh: () => void; canCreate: boolean }) {
  const [filter, setFilter] = useState('ALL')
  const [formOpen, setFormOpen] = useState(false)
  const filtered = pledges.filter((pledge) => filter === 'ALL' || pledge.status === filter)
  const totals = useMemo(() => ({
    pledged: pledges.reduce((sum, pledge) => sum + asNumber(pledge.pledged_amount), 0),
    paid: pledges.reduce((sum, pledge) => sum + asNumber(pledge.total_allocated), 0),
    outstanding: pledges.reduce((sum, pledge) => sum + asNumber(pledge.outstanding_amount), 0),
  }), [pledges])
  return (
    <section className="finance-section">
      <div className="mini-stat-row">
        <span>{moneyText(totals.pledged)} pledged</span>
        <span>{moneyText(totals.paid)} paid</span>
        <span>{moneyText(totals.outstanding)} outstanding</span>
      </div>
      <div className="segmented-row">
        {['ALL', 'PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE'].map((item) => <button className={filter === item ? 'active' : ''} key={item} type="button" onClick={() => setFilter(item)}>{item.replace('PARTIALLY_', '')}</button>)}
      </div>
      {canCreate ? <button className="desktop-primary-button" type="button" onClick={() => setFormOpen(true)}><Plus size={18} aria-hidden /> Record Pledge</button> : null}
      {formOpen ? <PledgeForm tenantId={tenantId} event={event} eventId={eventId} members={members} onDone={() => { setFormOpen(false); refresh() }} /> : null}
      <div className="finance-card-list">
        {filtered.map((pledge) => <PledgeCard key={asString(pledge.pledge_id)} pledge={pledge} eventId={eventId} />)}
        {!members.length ? <EmptyState title="No members available for pledges." message="Add a member before creating a pledge." /> : null}
        {members.length > 0 && !pledges.length ? <EmptyState title="No pledges have been recorded yet." message={canCreate ? 'Use Record Pledge to create the first pledge.' : 'You do not have permission to create pledges.'} /> : null}
        {pledges.length > 0 && !filtered.length ? <EmptyState title="No pledges match this filter." message="Choose another pledge status." /> : null}
      </div>
    </section>
  )
}

function PledgeForm({ tenantId, event, eventId, members, onDone }: { tenantId: string; event: EventSummary | null; eventId: string; members: Row[]; onDone: () => void }) {
  const [form, setForm] = useState({ eventMemberId: '', amount: '', dueDate: '', notes: '', changeReason: '' })
  const mutation = useMutation({
    mutationFn: () => api.upsertPledge(tenantId, eventId, { eventMemberId: form.eventMemberId, amount: Number(form.amount), dueDate: form.dueDate || null, notes: form.notes || null, changeReason: form.changeReason || null }),
    onSuccess: onDone,
  })
  return (
    <form className="mobile-sheet form-grid" onSubmit={(event) => { event.preventDefault(); mutation.mutate() }}>
      {!members.length ? <EmptyState title="No members available" message="Add a member before creating a pledge." /> : null}
      <label>Member<select value={form.eventMemberId} onChange={(event) => setForm((current) => ({ ...current, eventMemberId: event.target.value }))}><option value="">Select member</option>{members.map((member) => <option key={asString(member.event_member_id)} value={asString(member.event_member_id)}>{asString(member.full_name)}</option>)}</select></label>
      <Input label="Amount" inputMode="decimal" value={form.amount} onChange={(amount) => setForm((current) => ({ ...current, amount }))} />
      <Input label="Custom due date optional" type="date" value={form.dueDate} onChange={(dueDate) => setForm((current) => ({ ...current, dueDate }))} />
      <p className="privacy-note">Default due date: {asDate(event?.pledgeDeadline)}. Leave blank to follow the event deadline.</p>
      <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
      <Input label="Change reason when reducing" value={form.changeReason} onChange={(changeReason) => setForm((current) => ({ ...current, changeReason }))} />
      {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
      <div className="sheet-actions"><button type="button" onClick={onDone}>Cancel</button><button className="primary-button" type="submit" disabled={!form.eventMemberId || !form.amount || mutation.isPending}>{mutation.isPending ? 'Saving...' : 'Save Pledge'}</button></div>
    </form>
  )
}

function PledgeCard({ pledge, eventId }: { pledge: Row; eventId: string }) {
  const dueDate = pledge.effective_due_date ?? pledge.due_date
  const dueType = pledge.has_custom_due_date ? 'custom' : 'event default'
  return (
    <article className="finance-card">
      <div className="card-title-row">
        <div><strong>{asString(pledge.member_name, 'Member')}</strong><span>{asString(pledge.phone_e164, 'No phone')} · Due {asDate(dueDate)} · {dueType}</span></div>
        <StatusBadge tone={statusTone(pledge.status)}>{asString(pledge.status)}</StatusBadge>
      </div>
      <progress max={Math.max(asNumber(pledge.pledged_amount), 1)} value={asNumber(pledge.total_allocated)} />
      <div className="amount-triplet">
        <span><small>Pledged</small>{moneyText(pledge.pledged_amount)}</span>
        <span><small>Paid</small>{moneyText(pledge.total_allocated)}</span>
        <span><small>Outstanding</small>{moneyText(pledge.outstanding_amount)}</span>
      </div>
      <div className="card-actions"><Link to={`/app/events/${eventId}/payments/new?eventMemberId=${asString(pledge.event_member_id)}&pledgeId=${asString(pledge.pledge_id)}`}>Record Payment</Link></div>
    </article>
  )
}

function PaymentsPanel({ tenantId, eventId, payments, summary, refresh, canCreate }: { tenantId: string; eventId: string; payments: Row[]; summary: Row; refresh: () => void; canCreate: boolean }) {
  const today = payments.filter((payment) => new Date(asString(payment.payment_date)).toDateString() === new Date().toDateString())
  return (
    <section className="finance-section">
      <div className="stats-grid">
        <StatCard label="Today" value={moneyText(summary.paymentsToday)} icon={CreditCard} />
        <StatCard label="Unallocated" value={moneyText(summary.totalUnallocated)} icon={Clock3} tone="warning" />
        <StatCard label="Confirmed" value={String(payments.filter((payment) => payment.status === 'CONFIRMED').length)} icon={CheckCircle2} tone="success" />
      </div>
      {canCreate ? <Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new`}><Plus size={18} aria-hidden /> Record Payment</Link> : null}
      <div className="finance-card-list">
        {payments.map((payment) => <PaymentCard key={asString(payment.payment_id)} payment={payment} eventId={eventId} tenantId={tenantId} onReverse={refresh} />)}
        {!payments.length ? <EmptyState title="No payments have been recorded yet." message={canCreate ? 'Use Record Payment after adding a member and pledge.' : 'You do not have permission to record payments.'} /> : null}
        {!today.length && payments.length ? <p className="privacy-note">No payments recorded today.</p> : null}
      </div>
    </section>
  )
}

function PaymentCard({ payment, eventId, tenantId, onReverse }: { payment: Row; eventId: string; tenantId?: string; onReverse?: () => void }) {
  const [reason, setReason] = useState('')
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const reverse = useMutation({
    mutationFn: () => api.reversePayment(tenantId ?? '', eventId, asString(payment.payment_id), { reason, idempotencyKey }),
    onSuccess: onReverse,
  })
  return (
    <article className="finance-card">
      <div className="card-title-row">
        <div><strong>{asString(payment.member_name, 'Member')}</strong><span>{asString(payment.receipt_number, 'No receipt')} · {asDate(payment.payment_date)}</span></div>
        <StatusBadge tone={statusTone(payment.status)}>{asString(payment.status)}</StatusBadge>
      </div>
      <div className="amount-triplet">
        <span><small>Amount</small>{moneyText(payment.amount)}</span>
        <span><small>Allocated</small>{moneyText(payment.allocated_amount)}</span>
        <span><small>Excess</small>{moneyText(payment.unallocated_amount)}</span>
      </div>
      <div className="card-actions">
        {payment.receipt_number ? <Link to={`/app/receipts/${asString(payment.receipt_id)}`}>Receipt</Link> : null}
        {tenantId && payment.status === 'CONFIRMED' ? <button type="button" onClick={() => reason ? reverse.mutate() : setReason('Correction requested')}>Reverse</button> : null}
      </div>
    </article>
  )
}

export function MemberDetailPage() {
  const { eventId = '', eventMemberId = '' } = useParams()
  const activeEvent = useActiveEventContext(eventId)
  const tenantId = activeEvent.tenantId
  const detail = useQuery({ queryKey: ['member-detail', tenantId, eventId, eventMemberId], queryFn: async () => (await api.eventMemberDetail(tenantId ?? '', eventId, eventMemberId)).data, enabled: Boolean(tenantId && eventId && eventMemberId && !activeEvent.error) })
  if (activeEvent.error) return <ErrorState title="Unable to open member" message={activeEvent.error} />
  if (detail.isLoading) return <LoadingState title="Loading member" />
  if (detail.isError || !detail.data) return <ErrorState title="Unable to load member" message={errorMessage(detail.error, 'Member detail could not be loaded.')} />
  const member = detail.data.member
  const dueDate = member.effective_due_date ?? member.due_date
  return (
    <PageContainer>
      <PageHeader title={asString(member.full_name, 'Member')} description={`${asString(member.phone_e164, 'No phone')} · ${asString(member.category, 'No category')}`} action={<Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new?eventMemberId=${eventMemberId}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link>} />
      <section className="stats-grid">
        <StatCard label="Pledged" value={moneyText(member.pledged_amount)} icon={FileText} />
        <StatCard label="Paid" value={moneyText(member.total_allocated)} icon={CheckCircle2} tone="success" />
        <StatCard label="Outstanding" value={moneyText(member.outstanding_amount)} icon={Clock3} tone="warning" />
      </section>
      <section className="content-panel">
        <div className="panel-header">
          <div>
            <h2>Member Profile</h2>
            <p>{asString(member.member_code, 'No member code')} · Event member {eventMemberId}</p>
          </div>
          <StatusBadge tone={statusTone(member.event_member_status)}>{asString(member.event_member_status, 'ACTIVE')}</StatusBadge>
        </div>
        <ReviewLine label="Alternative phone" value={asString(member.alternative_phone_e164, 'Not set')} />
        <ReviewLine label="Email" value={asString(member.email, 'Not set')} />
        <ReviewLine label="Location" value={asString(member.location, 'Not set')} />
        <ReviewLine label="Pledge due date" value={`${asDate(dueDate)} (${member.has_custom_due_date ? 'custom' : 'event default'})`} />
      </section>
      <div className="finance-card-list">
        {detail.data.payments.map((payment) => <PaymentCard key={asString(payment.payment_id)} payment={payment} eventId={eventId} />)}
        {!detail.data.payments.length ? <EmptyState title="No payments for this member yet." message="Record a payment to generate the first receipt." /> : null}
      </div>
    </PageContainer>
  )
}

export function PaymentEntryPage() {
  const { eventId = '' } = useParams()
  const [search] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const activeEvent = useActiveEventContext(eventId)
  const tenantId = activeEvent.tenantId
  const members = useQuery({ queryKey: ['event-members', tenantId, eventId], queryFn: async () => (await api.eventMembers(tenantId ?? '', eventId)).data, enabled: Boolean(tenantId && eventId && !activeEvent.error) })
  const [memberSearch, setMemberSearch] = useState('')
  const [idempotencyKey, resetIdempotencyKey] = useState(() => crypto.randomUUID())
  const [form, setForm] = useState({
    eventMemberId: search.get('eventMemberId') ?? '',
    pledgeId: search.get('pledgeId') ?? '',
    amount: '',
    paymentMethod: 'CASH',
    paymentDate: new Date().toISOString().slice(0, 16),
    transactionReference: '',
    providerName: '',
    notes: '',
  })
  const memberRows = members.data ?? []
  const filteredMembers = memberRows.filter((member) => `${member.full_name ?? ''} ${member.phone_e164 ?? ''} ${member.member_code ?? ''}`.toLowerCase().includes(memberSearch.toLowerCase()))
  const selectedMember = memberRows.find((member) => member.event_member_id === form.eventMemberId)
  const outstanding = asNumber(selectedMember?.outstanding_amount)
  const paymentAmount = asNumber(form.amount)
  const mutation = useMutation({
    mutationFn: () => api.recordPayment(tenantId ?? '', eventId, { ...form, amount: Number(form.amount), paymentDate: new Date(form.paymentDate).toISOString(), idempotencyKey, pledgeId: form.pledgeId || null }),
    onSuccess: (result) => {
      if (tenantId) {
        invalidateEvent(queryClient, tenantId, eventId)
      }
      resetIdempotencyKey(crypto.randomUUID())
      const receiptId = asString(result.data.receipt_id)
      const notification = jsonRecord(result.data.notification)
      const sms = notification.smsQueued === true ? 'queued' : asString(notification.reason, 'not_queued').toLowerCase()
      navigate(receiptId ? `/app/receipts/${receiptId}?paymentRecorded=1&sms=${encodeURIComponent(sms)}` : `/app/events/${eventId}/payments`, { replace: true })
    },
  })
  if (activeEvent.error) return <ErrorState title="Unable to record payment" message={activeEvent.error} />
  if (activeEvent.eventStatus !== 'ACTIVE') return <ErrorState title="Payments require an active event" message={`This event is ${activeEvent.eventStatus ?? 'not active'}.`} />
  if (members.isLoading) return <LoadingState title="Loading members" message="Fetching members for payment entry." />
  if (members.isError) return <ErrorState title="Unable to load members" message={errorMessage(members.error, 'Members could not be loaded for payment entry.')} />
  return (
    <PageContainer narrow>
      <PageHeader title="Record Payment" description="Select a member, confirm the amount and generate a receipt." action={<Link to={`/app/events/${eventId}`}><ArrowLeft size={18} aria-hidden /> Back</Link>} />
      <form className="payment-flow" onSubmit={(event: FormEvent) => { event.preventDefault(); if (!mutation.isPending) mutation.mutate() }}>
        {!selectedMember ? (
          <>
            <label>Search member<input type="search" value={memberSearch} onChange={(event) => setMemberSearch(event.target.value)} placeholder="Name, phone or member code" /></label>
            <div className="finance-card-list">
              {filteredMembers.slice(0, 8).map((member) => (
                <button
                  className="finance-card"
                  key={asString(member.event_member_id)}
                  type="button"
                  onClick={() => setForm((current) => ({ ...current, eventMemberId: asString(member.event_member_id), pledgeId: asString(member.pledge_id) }))}
                >
                  <div className="card-title-row">
                    <div><strong>{asString(member.full_name, 'Member')}</strong><span>{asString(member.phone_e164, 'No phone')} · {asString(member.member_code)}</span></div>
                    <StatusBadge tone={statusTone(member.pledge_status)}>{moneyText(member.outstanding_amount)} outstanding</StatusBadge>
                  </div>
                </button>
              ))}
            </div>
            {!memberRows.length ? <EmptyState title="No members have been added to this event yet." message="Add a member before recording a payment." /> : null}
            {memberRows.length > 0 && !filteredMembers.length ? <EmptyState title="No members match your search." message="Try a different name, phone number or member code." /> : null}
          </>
        ) : null}
        {selectedMember ? <div className="review-stack">
          <div className="panel-header">
            <div>
              <h2>{asString(selectedMember.full_name, 'Selected member')}</h2>
              <p>{asString(selectedMember.member_code)} · {asString(selectedMember.phone_e164, 'No phone')}</p>
            </div>
            <button type="button" onClick={() => setForm((current) => ({ ...current, eventMemberId: '', pledgeId: '' }))}>Change</button>
          </div>
          <ReviewLine label="Pledge" value={moneyText(selectedMember.pledged_amount)} />
          <ReviewLine label="Paid" value={moneyText(selectedMember.total_allocated)} />
          <ReviewLine label="Outstanding before payment" value={moneyText(selectedMember.outstanding_amount)} />
          <ReviewLine label="Outstanding after payment" value={moneyText(Math.max(outstanding - paymentAmount, 0))} />
          <ReviewLine label="Excess / unallocated amount" value={form.amount && paymentAmount > outstanding ? moneyText(paymentAmount - outstanding) : 'None'} />
        </div> : null}
        <Input label="Amount received" inputMode="decimal" value={form.amount} onChange={(amount) => setForm((current) => ({ ...current, amount }))} />
        <div className="quick-amounts"><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(outstanding) }))}>Outstanding</button><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(Math.round(outstanding / 2)) }))}>Half</button><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(asNumber(selectedMember?.pledged_amount)) }))}>Pledged</button></div>
        <label>Payment method<select value={form.paymentMethod} onChange={(event) => setForm((current) => ({ ...current, paymentMethod: event.target.value }))}>{paymentMethods.map((method) => <option key={method} value={method}>{method}</option>)}</select></label>
        <Input label="Payment date and time" type="datetime-local" value={form.paymentDate} onChange={(paymentDate) => setForm((current) => ({ ...current, paymentDate }))} />
        <Input label="Transaction reference optional" value={form.transactionReference} onChange={(transactionReference) => setForm((current) => ({ ...current, transactionReference }))} />
        <Input label="Provider name optional" value={form.providerName} onChange={(providerName) => setForm((current) => ({ ...current, providerName }))} />
        <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
        {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
        <button className="primary-button" type="submit" disabled={mutation.isPending || !form.eventMemberId || !form.amount || !tenantId}>{mutation.isPending ? 'Recording...' : 'Confirm and Generate Receipt'}</button>
      </form>
    </PageContainer>
  )
}

export function ReceiptPage() {
  const { receiptId = '' } = useParams()
  const [search] = useSearchParams()
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const receipt = useQuery({ queryKey: ['receipt', tenantId, receiptId], queryFn: async () => (await api.receipt(tenantId ?? '', receiptId)).data, enabled: Boolean(tenantId && receiptId) })
  if (!tenantId) return <ErrorState title="Unable to load receipt" message="Select a tenant before opening receipts." />
  if (receipt.isLoading) return <LoadingState title="Loading receipt" />
  if (receipt.isError || !receipt.data) return <ErrorState title="Unable to load receipt" message={errorMessage(receipt.error, 'Receipt could not be loaded.')} />
  const data = receipt.data
  const successSms = search.get('sms')
  const smsConfirmation = jsonRecord(data.smsConfirmation)
  return (
    <PageContainer narrow>
      {search.get('paymentRecorded') ? <section className="content-panel">
        <div className="panel-header">
          <div>
            <h2>Payment recorded successfully</h2>
            <p>Receipt: {asString(data.receipt_number, 'Receipt')}</p>
          </div>
          <StatusBadge tone={successSms === 'queued' ? 'success' : 'neutral'}>{successSms === 'queued' ? 'Confirmation queued' : smsStatusText({ reason: successSms?.toUpperCase() })}</StatusBadge>
        </div>
      </section> : null}
      <article className="receipt-document">
        <header><strong>{asString(data.tenant_name, 'Ahadi')}</strong><span>{asString(data.event_name, 'Event')}</span></header>
        <h1>{asString(data.receipt_number, 'Receipt')}</h1>
        <StatusBadge tone={statusTone(data.payment_status)}>{asString(data.payment_status)}</StatusBadge>
        {data.payment_status === 'REVERSED' ? <p className="field-error">This receipt is reversed. Reason: {asString(data.reversal_reason, 'Not specified')}</p> : null}
        <ReviewLine label="Member" value={`${asString(data.member_name)} · ${asString(data.member_phone)}`} />
        <ReviewLine label="Amount received" value={moneyText(data.payment_amount)} />
        <ReviewLine label="Payment method" value={asString(data.payment_method)} />
        <ReviewLine label="Reference" value={asString(data.transaction_reference, 'None')} />
        <ReviewLine label="Pledged" value={moneyText(data.pledged_amount)} />
        <ReviewLine label="Paid toward pledge" value={moneyText(data.total_paid_toward_pledge)} />
        <ReviewLine label="Remaining pledge balance" value={moneyText(data.outstanding_amount)} />
        <ReviewLine label="Unallocated excess" value={moneyText(data.unallocated_excess)} />
        <ReviewLine label="Received by" value={asString(data.received_by, 'Ahadi user')} />
        <ReviewLine label="SMS Confirmation" value={asString(smsConfirmation.status, successSms === 'queued' ? 'Queued' : 'Not queued')} />
        <footer className="receipt-actions"><button type="button" onClick={() => window.print()}><Printer size={18} aria-hidden /> Print</button><button type="button" onClick={() => void navigator.share?.({ title: asString(data.receipt_number), text: `${asString(data.receipt_number)} ${moneyText(data.payment_amount)}` })}><Share2 size={18} aria-hidden /> Share</button></footer>
      </article>
    </PageContainer>
  )
}

export function SmsHistoryPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const eventOptions = session.selectedTenantContext?.events ?? []
  const [status, setStatus] = useState('ALL')
  const [eventId, setEventId] = useState('ALL')
  const [query, setQuery] = useState('')
  const messages = useQuery({ queryKey: ['sms-history', tenantId], queryFn: async () => (await api.messages(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const rows = messages.data ?? []
  const filtered = rows.filter((message) => {
    const statusMatches = status === 'ALL' || message.status === status
    const eventMatches = eventId === 'ALL' || message.event_id === eventId
    const queryMatches = `${message.member_name ?? ''} ${message.phone_e164 ?? ''} ${message.template_code ?? ''}`.toLowerCase().includes(query.toLowerCase())
    return statusMatches && eventMatches && queryMatches
  })

  if (!tenantId) return <ErrorState title="Unable to load SMS history" message="Select a tenant first." />
  if (messages.isLoading) return <LoadingState title="Loading messages" message="Fetching SMS confirmation history." />
  if (messages.isError) return <ErrorState title="Unable to load messages" message={errorMessage(messages.error, 'SMS history could not be loaded.')} />

  return (
    <PageContainer>
      <PageHeader title="Messages" description="Payment confirmation SMS history for this tenant." />
      <section className="filter-bar">
        <label>Status<select value={status} onChange={(event) => setStatus(event.target.value)}>{['ALL', 'QUEUED', 'PROCESSING', 'SENT', 'DELIVERED', 'FAILED', 'CANCELLED'].map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
        <label>Event<select value={eventId} onChange={(event) => setEventId(event.target.value)}><option value="ALL">All events</option>{eventOptions.map((event) => <option key={event.id} value={event.id}>{event.name}</option>)}</select></label>
        <label>Search<input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Member or phone" /></label>
      </section>
      <div className="finance-card-list">
        {filtered.map((message) => <article className="finance-card" key={asString(message.id)}>
          <div className="card-title-row">
            <div>
              <strong>{asString(message.member_name, 'Recipient')}</strong>
              <span>{maskPhone(message.phone_e164)} · {asString(message.event_name, 'No event')}</span>
            </div>
            <StatusBadge tone={statusTone(message.status)}>{asString(message.status, 'QUEUED')}</StatusBadge>
          </div>
          <div className="amount-triplet">
            <span><small>Template</small>{asString(message.template_code, 'Message')}</span>
            <span><small>Created</small>{asDateTime(message.created_at)}</span>
            <span><small>Sent</small>{asDateTime(message.sent_at)}</span>
          </div>
          {message.status === 'FAILED' ? <p className="field-error">{asString(message.last_error_message, 'SMS delivery failed.')}</p> : null}
        </article>)}
        {!rows.length ? <EmptyState title="No SMS messages yet." message="Payment confirmations will appear here after payments are recorded." /> : null}
        {rows.length > 0 && !filtered.length ? <EmptyState title="No messages match these filters." message="Change the status, event, or search text." /> : null}
      </div>
    </PageContainer>
  )
}

export function TenantUsersPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const users = useQuery({ queryKey: ['tenant-users', tenantId], queryFn: async () => (await api.tenantUsers(tenantId ?? '')).data, enabled: Boolean(tenantId) })

  if (!tenantId) return <ErrorState title="Unable to load users" message="Select a tenant first." />
  if (!permissions.has('users.view')) return <ErrorState title="Users access denied" message="Your tenant role does not include user management access." />
  if (users.isLoading) return <LoadingState title="Loading users" message="Fetching tenant team members." />
  if (users.isError) return <ErrorState title="Unable to load users" message={errorMessage(users.error, 'Tenant users could not be loaded.')} />

  const rows = users.data ?? []
  return (
    <PageContainer>
      <PageHeader
        title="Users"
        description="Tenant team members, tenant roles and event assignments."
        action={permissions.has('users.invite') ? <button className="desktop-primary-button" type="button" disabled>Invite User</button> : null}
      />
      <div className="finance-card-list">
        {rows.map((user) => {
          const roles = Array.isArray(user.roles) ? user.roles.map(String) : []
          const assignedEvents = Array.isArray(user.assigned_events) ? user.assigned_events.map(jsonRecord) : []
          return (
            <article className="finance-card" key={asString(user.tenant_user_id)}>
              <div className="card-title-row">
                <div>
                  <strong>{asString(user.full_name, 'User')}</strong>
                  <span>{asString(user.phone_e164, 'No phone')} · {asString(user.email, 'No email')}</span>
                </div>
                <StatusBadge tone={statusTone(user.status)}>{asString(user.status, 'ACTIVE')}</StatusBadge>
              </div>
              <div className="amount-triplet">
                <span><small>Roles</small>{roles.join(', ') || 'No role'}</span>
                <span><small>Events</small>{assignedEvents.map((event) => asString(event.name)).filter(Boolean).join(', ') || 'All permitted events'}</span>
                <span><small>Joined</small>{asDate(user.joined_at ?? user.created_at)}</span>
              </div>
              <div className="card-actions">
                {permissions.has('users.manage_roles') ? <button type="button" disabled>Manage Roles</button> : null}
                {permissions.has('users.suspend') && !roles.includes('TENANT_OWNER') ? <button type="button" disabled>Suspend</button> : null}
              </div>
            </article>
          )
        })}
        {!rows.length ? <EmptyState title="No tenant users found." message="Tenant owners appear here after onboarding and invitations." /> : null}
      </div>
    </PageContainer>
  )
}

export function TenantSettingsPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const settings = useQuery({ queryKey: ['tenant-settings-summary', tenantId], queryFn: async () => (await api.settingsSummary(tenantId ?? '')).data, enabled: Boolean(tenantId) })

  if (!tenantId) return <ErrorState title="Unable to load settings" message="Select a tenant first." />
  if (settings.isLoading) return <LoadingState title="Loading settings" message="Fetching tenant configuration." />
  if (settings.isError || !settings.data) return <ErrorState title="Unable to load settings" message={errorMessage(settings.error, 'Settings could not be loaded.')} />

  const data = settings.data
  const organization = jsonRecord(data.organization)
  const receipts = jsonRecord(data.receipts)
  const payments = jsonRecord(data.payments)
  const notifications = jsonRecord(data.notifications)
  const subscription = jsonRecord(data.subscription)
  const limits = jsonRecord(subscription.limits)
  const security = jsonRecord(data.security)

  return (
    <PageContainer>
      <PageHeader title="Settings" description="Tenant configuration summary. Provider secrets are intentionally hidden." />
      <section className="finance-grid">
        <SettingsPanel title="Organization" rows={[['Name', organization.name], ['Code', organization.code], ['Phone', organization.phoneE164], ['Email', organization.email], ['Timezone', organization.timezone], ['Currency', organization.currency], ['Status', organization.status]]} />
        <SettingsPanel title="Receipts" rows={[['Receipt prefix', receipts.receiptPrefix], ['Logo', receipts.logoUrl ? 'Configured' : 'Not set'], ['Primary color', receipts.primaryColor]]} />
        <SettingsPanel title="Payments" rows={[['Mobile money instructions', payments.mobileMoneyInstructions], ['Bank instructions', payments.bankPaymentInstructions]]} />
        <SettingsPanel title="Notifications" rows={[['SMS sender', notifications.smsSenderName], ['Payment confirmations', notifications.paymentConfirmations ? 'Enabled' : 'Disabled']]} />
        <SettingsPanel title="Subscription" rows={[['Package', subscription.planName], ['Status', subscription.status], ['Used slots', limits.usedEventSlots], ['Max slots', limits.maxEventSlots], ['Available slots', limits.availableEventSlots], ['Period ends', subscription.currentPeriodEnd]]} />
        <SettingsPanel title="Security" rows={[['PIN required', security.pinRequired ? 'Yes' : 'No'], ['Tenant roles', Array.isArray(security.roles) ? security.roles.join(', ') : 'Not set']]} />
      </section>
    </PageContainer>
  )
}

function SettingsPanel({ title, rows }: { title: string; rows: Array<[string, unknown]> }) {
  return (
    <article className="content-panel">
      <div className="panel-header">
        <div>
          <h2>{title}</h2>
        </div>
      </div>
      {rows.map(([label, value]) => <ReviewLine key={label} label={label} value={displayValue(value)} />)}
    </article>
  )
}

export function ReportsPage() {
  const session = useSessionStore()
  const event = session.selectedTenantContext?.events[0] ?? null
  const tenantId = session.selectedTenantId
  const summary = useQuery({ queryKey: ['reports-financial-summary', tenantId, event?.id], queryFn: async () => (await api.eventFinancialSummary(tenantId ?? '', event?.id ?? '')).data, enabled: Boolean(tenantId && event?.id) })

  if (!tenantId || !event) return <ErrorState title="Unable to load reports" message="Open a tenant with an accessible event first." />
  if (summary.isLoading) return <LoadingState title="Loading reports" message="Fetching event financial summary." />
  if (summary.isError) return <ErrorState title="Unable to load reports" message={errorMessage(summary.error, 'Reports could not be loaded.')} />

  const data = summary.data ?? {}
  return (
    <PageContainer>
      <PageHeader title="Reports" description={`${event.name} financial summary and forthcoming report modules.`} />
      <section className="stats-grid">
        <StatCard label="Total pledged" value={moneyText(data.totalPledged)} icon={FileText} />
        <StatCard label="Collected" value={moneyText(data.totalAllocated ?? data.totalAllocatedToPledges)} icon={CheckCircle2} tone="success" />
        <StatCard label="Outstanding" value={moneyText(data.totalOutstanding)} icon={Clock3} tone="warning" />
      </section>
      <section className="finance-grid">
        <article className="content-panel">
          <div className="panel-header"><div><h2>Collection Summary</h2><p>{asNumber(data.memberCount)} members, {asNumber(data.membersWithPledges)} with pledges.</p></div></div>
          <ReviewLine label="Fully paid" value={String(asNumber(data.fullyPaidCount))} />
          <ReviewLine label="Partially paid" value={String(asNumber(data.partiallyPaidCount))} />
          <ReviewLine label="Unpaid" value={String(asNumber(data.unpaidCount))} />
          <ReviewLine label="Overdue" value={String(asNumber(data.overdueCount))} />
        </article>
        {['Member Statement', 'Outstanding Pledges', 'Payment Export', 'SMS Delivery'].map((title) => (
          <article className="content-panel" key={title}>
            <div className="panel-header"><div><h2>{title}</h2><p>Forthcoming report module.</p></div><StatusBadge>Forthcoming</StatusBadge></div>
          </article>
        ))}
      </section>
    </PageContainer>
  )
}

function Input({ label, value, onChange, inputMode, type = 'text' }: { label: string; value: string; onChange: (value: string) => void; inputMode?: 'decimal' | 'tel'; type?: string }) {
  return <label>{label}<input inputMode={inputMode} type={type} value={value} onChange={(event) => onChange(event.target.value)} /></label>
}

function ReviewLine({ label, value }: { label: string; value: string }) {
  return <div className="review-line"><span>{label}</span><strong>{value}</strong></div>
}
