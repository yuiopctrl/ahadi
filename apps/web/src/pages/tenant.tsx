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
import { api } from '../lib/api'
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

function useTenantId() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  if (!tenantId) {
    throw new Error('Select a tenant first')
  }
  return tenantId
}

function useEventContext(eventId: string | undefined) {
  const session = useSessionStore()
  return session.selectedTenantContext?.events.find((event) => event.id === eventId) ?? session.selectedTenantContext?.events[0] ?? null
}

function invalidateEvent(queryClient: ReturnType<typeof useQueryClient>, tenantId: string, eventId: string) {
  void queryClient.invalidateQueries({ queryKey: ['event-summary', tenantId, eventId] })
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
  const tenantId = useTenantId()
  const fallbackEvent = useEventContext(undefined)
  const eventId = params.eventId ?? fallbackEvent?.id ?? ''
  const event = useEventContext(eventId)
  const [search] = useSearchParams()
  const queryClient = useQueryClient()
  const summaryQuery = useQuery({ queryKey: ['event-summary', tenantId, eventId], queryFn: async () => (await api.eventFinancialSummary(tenantId, eventId)).data, enabled: Boolean(eventId) })
  const membersQuery = useQuery({ queryKey: ['event-members', tenantId, eventId], queryFn: async () => (await api.eventMembers(tenantId, eventId)).data, enabled: Boolean(eventId) })
  const pledgesQuery = useQuery({ queryKey: ['event-pledges', tenantId, eventId], queryFn: async () => (await api.eventPledges(tenantId, eventId)).data, enabled: Boolean(eventId) })
  const paymentsQuery = useQuery({ queryKey: ['event-payments', tenantId, eventId], queryFn: async () => (await api.eventPayments(tenantId, eventId)).data, enabled: Boolean(eventId) })

  const summary = summaryQuery.data ?? {}
  const collectionPercent = asNumber(summary.totalPledged) > 0 ? Math.round((asNumber(summary.totalAllocatedToPledges) / asNumber(summary.totalPledged)) * 100) : 0

  if (summaryQuery.isLoading) {
    return <LoadingState title="Loading event" message="Fetching pledge and payment totals." />
  }
  if (summaryQuery.isError) {
    return <ErrorState title="Unable to load event" message="Check event access and tenant context." />
  }

  return (
    <PageContainer>
      <PageHeader
        title={event?.name ?? 'Event Overview'}
        description={event?.eventDate ? `Event date ${asDate(event.eventDate)}` : 'Member pledges, installment collections and receipts.'}
        action={
          <Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new`}>
            <Plus size={18} aria-hidden />
            Record Payment
          </Link>
        }
      />
      <section className="stats-grid">
        <StatCard label="Total Pledged" value={moneyText(summary.totalPledged)} meta={`${asNumber(summary.membersWithPledges)} pledge members`} icon={Users} />
        <StatCard label="Collected" value={moneyText(summary.totalAllocatedToPledges)} meta={`${collectionPercent}% collected`} icon={CheckCircle2} tone="success" />
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
        <MembersPanel tenantId={tenantId} eventId={eventId} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId, eventId)} initialSearch={search.get('q') ?? ''} />
      ) : null}
      {section === 'pledges' ? <PledgesPanel tenantId={tenantId} eventId={eventId} pledges={pledgesQuery.data ?? []} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId, eventId)} /> : null}
      {section === 'payments' ? <PaymentsPanel tenantId={tenantId} eventId={eventId} payments={paymentsQuery.data ?? []} summary={summary} refresh={() => invalidateEvent(queryClient, tenantId, eventId)} /> : null}
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

function MembersPanel({ tenantId, eventId, members, refresh, initialSearch }: { tenantId: string; eventId: string; members: Row[]; refresh: () => void; initialSearch: string }) {
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
        <button className="desktop-primary-button" type="button" onClick={() => setShowForm(true)}>
          <Plus size={18} aria-hidden />
          Add Member
        </button>
      </div>
      {showForm ? <MemberForm tenantId={tenantId} eventId={eventId} onDone={() => { setShowForm(false); refresh() }} /> : null}
      <div className="finance-card-list">
        {filtered.map((member) => <MemberCard key={asString(member.event_member_id)} member={member} eventId={eventId} />)}
      </div>
      <button className="mobile-sticky-button" type="button" onClick={() => setShowForm(true)}>Add Member</button>
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

function PledgesPanel({ tenantId, eventId, pledges, members, refresh }: { tenantId: string; eventId: string; pledges: Row[]; members: Row[]; refresh: () => void }) {
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
      <button className="desktop-primary-button" type="button" onClick={() => setFormOpen(true)}><Plus size={18} aria-hidden /> Record Pledge</button>
      {formOpen ? <PledgeForm tenantId={tenantId} eventId={eventId} members={members} onDone={() => { setFormOpen(false); refresh() }} /> : null}
      <div className="finance-card-list">
        {filtered.map((pledge) => <PledgeCard key={asString(pledge.pledge_id)} pledge={pledge} eventId={eventId} />)}
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
      <label>Member<select value={form.eventMemberId} onChange={(event) => setForm((current) => ({ ...current, eventMemberId: event.target.value }))}><option value="">Select member</option>{members.map((member) => <option key={asString(member.event_member_id)} value={asString(member.event_member_id)}>{asString(member.full_name)}</option>)}</select></label>
      <Input label="Amount" inputMode="decimal" value={form.amount} onChange={(amount) => setForm((current) => ({ ...current, amount }))} />
      <Input label="Due date optional" type="date" value={form.dueDate} onChange={(dueDate) => setForm((current) => ({ ...current, dueDate }))} />
      <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
      <Input label="Change reason when reducing" value={form.changeReason} onChange={(changeReason) => setForm((current) => ({ ...current, changeReason }))} />
      {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
      <div className="sheet-actions"><button type="button" onClick={onDone}>Cancel</button><button className="primary-button" type="submit">Save Pledge</button></div>
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

function PaymentsPanel({ tenantId, eventId, payments, summary, refresh }: { tenantId: string; eventId: string; payments: Row[]; summary: Row; refresh: () => void }) {
  const today = payments.filter((payment) => new Date(asString(payment.payment_date)).toDateString() === new Date().toDateString())
  return (
    <section className="finance-section">
      <div className="stats-grid">
        <StatCard label="Today" value={moneyText(summary.paymentsToday)} icon={CreditCard} />
        <StatCard label="Unallocated" value={moneyText(summary.totalUnallocated)} icon={Clock3} tone="warning" />
        <StatCard label="Confirmed" value={String(payments.filter((payment) => payment.status === 'CONFIRMED').length)} icon={CheckCircle2} tone="success" />
      </div>
      <Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new`}><Plus size={18} aria-hidden /> Record Payment</Link>
      <div className="finance-card-list">
        {payments.map((payment) => <PaymentCard key={asString(payment.payment_id)} payment={payment} eventId={eventId} tenantId={tenantId} onReverse={refresh} />)}
        {!today.length && payments.length ? <p className="privacy-note">No payments recorded today.</p> : null}
      </div>
    </section>
  )
}

function PaymentCard({ payment, eventId, tenantId, onReverse }: { payment: Row; eventId: string; tenantId?: string; onReverse?: () => void }) {
  const [reason, setReason] = useState('')
  const reverse = useMutation({
    mutationFn: () => api.reversePayment(tenantId ?? '', eventId, asString(payment.payment_id), { reason, idempotencyKey: crypto.randomUUID() }),
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
  const tenantId = useTenantId()
  const detail = useQuery({ queryKey: ['member-detail', tenantId, eventId, eventMemberId], queryFn: async () => (await api.eventMemberDetail(tenantId, eventId, eventMemberId)).data })
  if (detail.isLoading) return <LoadingState title="Loading member" />
  if (detail.isError || !detail.data) return <ErrorState title="Unable to load member" />
  const member = detail.data.member
  return (
    <PageContainer>
      <PageHeader title={asString(member.full_name, 'Member')} description={`${asString(member.phone_e164, 'No phone')} · ${asString(member.category, 'No category')}`} action={<Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new?eventMemberId=${eventMemberId}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link>} />
      <section className="stats-grid">
        <StatCard label="Pledged" value={moneyText(member.pledged_amount)} icon={FileText} />
        <StatCard label="Paid" value={moneyText(member.total_allocated)} icon={CheckCircle2} tone="success" />
        <StatCard label="Outstanding" value={moneyText(member.outstanding_amount)} icon={Clock3} tone="warning" />
      </section>
      <div className="finance-card-list">{detail.data.payments.map((payment) => <PaymentCard key={asString(payment.payment_id)} payment={payment} eventId={eventId} />)}</div>
    </PageContainer>
  )
}

export function PaymentEntryPage() {
  const { eventId = '' } = useParams()
  const [search] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const tenantId = useTenantId()
  const members = useQuery({ queryKey: ['event-members', tenantId, eventId], queryFn: async () => (await api.eventMembers(tenantId, eventId)).data })
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
  const selectedMember = members.data?.find((member) => member.event_member_id === form.eventMemberId)
  const outstanding = asNumber(selectedMember?.outstanding_amount)
  const mutation = useMutation({
    mutationFn: () => api.recordPayment(tenantId, eventId, { ...form, amount: Number(form.amount), paymentDate: new Date(form.paymentDate).toISOString(), idempotencyKey: crypto.randomUUID(), pledgeId: form.pledgeId || null }),
    onSuccess: (result) => {
      invalidateEvent(queryClient, tenantId, eventId)
      const receiptId = asString(result.data.receipt_id)
      navigate(receiptId ? `/app/receipts/${receiptId}` : `/app/events/${eventId}/payments`, { replace: true })
    },
  })
  return (
    <PageContainer narrow>
      <PageHeader title="Record Payment" description="Select a member, confirm the amount and generate a receipt." action={<Link to={`/app/events/${eventId}`}><ArrowLeft size={18} aria-hidden /> Back</Link>} />
      <form className="payment-flow" onSubmit={(event: FormEvent) => { event.preventDefault(); if (!mutation.isPending) mutation.mutate() }}>
        <label>Member<select value={form.eventMemberId} onChange={(event) => setForm((current) => ({ ...current, eventMemberId: event.target.value, pledgeId: asString(members.data?.find((member) => member.event_member_id === event.target.value)?.pledge_id) }))}><option value="">Select member</option>{(members.data ?? []).map((member) => <option key={asString(member.event_member_id)} value={asString(member.event_member_id)}>{asString(member.full_name)} - {moneyText(member.outstanding_amount)} outstanding</option>)}</select></label>
        {selectedMember ? <div className="review-stack"><ReviewLine label="Pledge" value={moneyText(selectedMember.pledged_amount)} /><ReviewLine label="Outstanding" value={moneyText(selectedMember.outstanding_amount)} /><ReviewLine label="Excess warning" value={form.amount && Number(form.amount) > outstanding ? moneyText(Number(form.amount) - outstanding) : 'None'} /></div> : null}
        <Input label="Amount received" inputMode="decimal" value={form.amount} onChange={(amount) => setForm((current) => ({ ...current, amount }))} />
        <div className="quick-amounts"><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(outstanding) }))}>Outstanding</button><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(Math.round(outstanding / 2)) }))}>Half</button><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(asNumber(selectedMember?.pledged_amount)) }))}>Pledged</button></div>
        <label>Payment method<select value={form.paymentMethod} onChange={(event) => setForm((current) => ({ ...current, paymentMethod: event.target.value }))}>{paymentMethods.map((method) => <option key={method} value={method}>{method}</option>)}</select></label>
        <Input label="Payment date and time" type="datetime-local" value={form.paymentDate} onChange={(paymentDate) => setForm((current) => ({ ...current, paymentDate }))} />
        <Input label="Transaction reference optional" value={form.transactionReference} onChange={(transactionReference) => setForm((current) => ({ ...current, transactionReference }))} />
        <Input label="Provider name optional" value={form.providerName} onChange={(providerName) => setForm((current) => ({ ...current, providerName }))} />
        <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
        {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
        <button className="primary-button" type="submit" disabled={mutation.isPending || !form.eventMemberId || !form.amount}>{mutation.isPending ? 'Recording...' : 'Confirm and Generate Receipt'}</button>
      </form>
    </PageContainer>
  )
}

export function ReceiptPage() {
  const { receiptId = '' } = useParams()
  const tenantId = useTenantId()
  const receipt = useQuery({ queryKey: ['receipt', tenantId, receiptId], queryFn: async () => (await api.receipt(tenantId, receiptId)).data })
  if (receipt.isLoading) return <LoadingState title="Loading receipt" />
  if (receipt.isError || !receipt.data) return <ErrorState title="Unable to load receipt" />
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
