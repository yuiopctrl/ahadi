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

function asDate(value: unknown) {
  return typeof value === 'string' && value ? new Date(value).toLocaleDateString('en-TZ') : 'Not set'
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
            <MembersPanel tenantId={tenantId ?? ''} eventId={eventId} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId ?? '', eventId)} initialSearch={search.get('q') ?? ''} canCreate={activeEvent.canCollect} />
      ) : null}
      {section === 'pledges' ? (
        pledgesQuery.isLoading || membersQuery.isLoading ? <LoadingState title="Loading pledges" message="Fetching pledges and members." /> :
          pledgesQuery.isError ? <ErrorState title="Unable to load pledges" message={errorMessage(pledgesQuery.error, 'Pledges could not be loaded.')} /> :
            membersQuery.isError ? <ErrorState title="Unable to load members" message={errorMessage(membersQuery.error, 'Members could not be loaded for pledge creation.')} /> :
              <PledgesPanel tenantId={tenantId ?? ''} eventId={eventId} pledges={pledgesQuery.data ?? []} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId ?? '', eventId)} canCreate={activeEvent.canCollect} />
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

function MembersPanel({ tenantId, eventId, members, refresh, initialSearch, canCreate }: { tenantId: string; eventId: string; members: Row[]; refresh: () => void; initialSearch: string; canCreate: boolean }) {
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
      {showForm ? <MemberForm tenantId={tenantId} eventId={eventId} onDone={() => { setShowForm(false); refresh() }} /> : null}
      <div className="finance-card-list">
        {filtered.map((member) => <MemberCard key={asString(member.event_member_id)} member={member} eventId={eventId} />)}
        {!members.length ? <EmptyState title="No members have been added to this event yet." message={canCreate ? 'Use Add Member to register the first contributor.' : 'You do not have permission to add members.'} /> : null}
        {members.length > 0 && !filtered.length ? <EmptyState title="No members match your search." message="Try a different name, phone number or member code." /> : null}
      </div>
      {canCreate ? <button className="mobile-sticky-button" type="button" onClick={() => setShowForm(true)}>Add Member</button> : null}
    </section>
  )
}

function MemberForm({ tenantId, eventId, onDone }: { tenantId: string; eventId: string; onDone: () => void }) {
  const [form, setForm] = useState({ fullName: '', phone: '', alternativePhone: '', email: '', location: '', notes: '', initialPledgeAmount: '', initialPledgeDueDate: '' })
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
      <Input label="Pledge due date optional" type="date" value={form.initialPledgeDueDate} onChange={(initialPledgeDueDate) => setForm((current) => ({ ...current, initialPledgeDueDate }))} />
      <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
      {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onDone}>Cancel</button>
        <button className="primary-button" type="submit" disabled={mutation.isPending}>{mutation.isPending ? 'Saving...' : 'Create Member'}</button>
      </div>
    </form>
  )
}

function MemberCard({ member, eventId }: { member: Row; eventId: string }) {
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
      <div className="card-actions">
        <Link to={`/app/events/${eventId}/payments/new?eventMemberId=${asString(member.event_member_id)}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link>
        <Link to={`/app/events/${eventId}/members/${asString(member.event_member_id)}`}>Details</Link>
      </div>
    </article>
  )
}

function PledgesPanel({ tenantId, eventId, pledges, members, refresh, canCreate }: { tenantId: string; eventId: string; pledges: Row[]; members: Row[]; refresh: () => void; canCreate: boolean }) {
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
      {formOpen ? <PledgeForm tenantId={tenantId} eventId={eventId} members={members} onDone={() => { setFormOpen(false); refresh() }} /> : null}
      <div className="finance-card-list">
        {filtered.map((pledge) => <PledgeCard key={asString(pledge.pledge_id)} pledge={pledge} eventId={eventId} />)}
        {!members.length ? <EmptyState title="No members available for pledges." message="Add a member before creating a pledge." /> : null}
        {members.length > 0 && !pledges.length ? <EmptyState title="No pledges have been recorded yet." message={canCreate ? 'Use Record Pledge to create the first pledge.' : 'You do not have permission to create pledges.'} /> : null}
        {pledges.length > 0 && !filtered.length ? <EmptyState title="No pledges match this filter." message="Choose another pledge status." /> : null}
      </div>
    </section>
  )
}

function PledgeForm({ tenantId, eventId, members, onDone }: { tenantId: string; eventId: string; members: Row[]; onDone: () => void }) {
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
      <Input label="Due date optional" type="date" value={form.dueDate} onChange={(dueDate) => setForm((current) => ({ ...current, dueDate }))} />
      <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
      <Input label="Change reason when reducing" value={form.changeReason} onChange={(changeReason) => setForm((current) => ({ ...current, changeReason }))} />
      {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
      <div className="sheet-actions"><button type="button" onClick={onDone}>Cancel</button><button className="primary-button" type="submit" disabled={!form.eventMemberId || !form.amount || mutation.isPending}>{mutation.isPending ? 'Saving...' : 'Save Pledge'}</button></div>
    </form>
  )
}

function PledgeCard({ pledge, eventId }: { pledge: Row; eventId: string }) {
  return (
    <article className="finance-card">
      <div className="card-title-row">
        <div><strong>{asString(pledge.member_name, 'Member')}</strong><span>{asString(pledge.phone_e164, 'No phone')} · Due {asDate(pledge.due_date)}</span></div>
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
  return (
    <PageContainer>
      <PageHeader title={asString(member.full_name, 'Member')} description={`${asString(member.phone_e164, 'No phone')} · ${asString(member.category, 'No category')}`} action={<Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new?eventMemberId=${eventMemberId}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link>} />
      <section className="stats-grid">
        <StatCard label="Pledged" value={moneyText(member.pledged_amount)} icon={FileText} />
        <StatCard label="Paid" value={moneyText(member.total_allocated)} icon={CheckCircle2} tone="success" />
        <StatCard label="Outstanding" value={moneyText(member.outstanding_amount)} icon={Clock3} tone="warning" />
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
      navigate(receiptId ? `/app/receipts/${receiptId}` : `/app/events/${eventId}/payments`, { replace: true })
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
        <label>Search member<input type="search" value={memberSearch} onChange={(event) => setMemberSearch(event.target.value)} placeholder="Name, phone or member code" /></label>
        <label>Member<select value={form.eventMemberId} onChange={(event) => setForm((current) => ({ ...current, eventMemberId: event.target.value, pledgeId: asString(memberRows.find((member) => member.event_member_id === event.target.value)?.pledge_id) }))}><option value="">Select member</option>{filteredMembers.map((member) => <option key={asString(member.event_member_id)} value={asString(member.event_member_id)}>{asString(member.full_name)} - {moneyText(member.outstanding_amount)} outstanding</option>)}</select></label>
        {!memberRows.length ? <EmptyState title="No members have been added to this event yet." message="Add a member before recording a payment." /> : null}
        {memberRows.length > 0 && !filteredMembers.length ? <EmptyState title="No members match your search." message="Try a different name, phone number or member code." /> : null}
        {selectedMember ? <div className="review-stack">
          <ReviewLine label="Member" value={`${asString(selectedMember.full_name)} · ${asString(selectedMember.member_code)}`} />
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
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const receipt = useQuery({ queryKey: ['receipt', tenantId, receiptId], queryFn: async () => (await api.receipt(tenantId ?? '', receiptId)).data, enabled: Boolean(tenantId && receiptId) })
  if (!tenantId) return <ErrorState title="Unable to load receipt" message="Select a tenant before opening receipts." />
  if (receipt.isLoading) return <LoadingState title="Loading receipt" />
  if (receipt.isError || !receipt.data) return <ErrorState title="Unable to load receipt" message={errorMessage(receipt.error, 'Receipt could not be loaded.')} />
  const data = receipt.data
  return (
    <PageContainer narrow>
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
        <footer className="receipt-actions"><button type="button" onClick={() => window.print()}><Printer size={18} aria-hidden /> Print</button><button type="button" onClick={() => void navigator.share?.({ title: asString(data.receipt_number), text: `${asString(data.receipt_number)} ${moneyText(data.payment_amount)}` })}><Share2 size={18} aria-hidden /> Share</button></footer>
      </article>
    </PageContainer>
  )
}

function Input({ label, value, onChange, inputMode, type = 'text' }: { label: string; value: string; onChange: (value: string) => void; inputMode?: 'decimal' | 'tel'; type?: string }) {
  return <label>{label}<input inputMode={inputMode} type={type} value={value} onChange={(event) => onChange(event.target.value)} /></label>
}

function ReviewLine({ label, value }: { label: string; value: string }) {
  return <div className="review-line"><span>{label}</span><strong>{value}</strong></div>
}
