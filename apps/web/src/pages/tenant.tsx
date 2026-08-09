import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  Clock3,
  Copy,
  CreditCard,
  FileText,
  MessageCircle,
  Plus,
  Printer,
  Search,
  Send,
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
const whatsappFormats = [
  { value: 'DETAILED', label: 'Detailed', description: 'Pledged and paid amounts with symbols.' },
  { value: 'PRIVACY', label: 'Privacy-Friendly', description: 'Names and status symbols only.' },
  { value: 'PAYMENT_PROGRESS', label: 'Payment Progress', description: 'Committee paid / pledged view.' },
  { value: 'OUTSTANDING_FOLLOW_UP', label: 'Outstanding Follow-Up', description: 'Members who still owe money.' },
]
const whatsappSorts = [
  ['ORIGINAL', 'Original Order'],
  ['NAME_ASC', 'Name A-Z'],
  ['PLEDGED_DESC', 'Pledged Amount: High to Low'],
  ['PAID_FIRST', 'Paid First'],
  ['OUTSTANDING_FIRST', 'Outstanding First'],
]
const whatsappStatuses = [
  ['ALL', 'All'],
  ['PAID', 'Paid'],
  ['PARTIAL', 'Partial'],
  ['UNPAID', 'Unpaid'],
  ['OVERDUE', 'Overdue'],
]
const eventTypes = ['WEDDING', 'SENDOFF', 'FUNERAL', 'FUNDRAISER', 'BIRTHDAY', 'GRADUATION', 'RELIGIOUS', 'OTHER']
const reportCards = [
  { type: 'summary', title: 'Collection Summary', description: 'Targets, pledged totals, collections, coverage and member status counts.' },
  { type: 'pledges', title: 'Pledge Report', description: 'Member pledge balances, due dates, payment progress and pledge status.' },
  { type: 'payments', title: 'Payments', description: 'Confirmed, reversed and cancelled payment rows with receipt and collector details.' },
  { type: 'outstanding', title: 'Outstanding', description: 'Members with unpaid pledge balances, due status, reminders and last payment.' },
  { type: 'payment-methods', title: 'Payment Methods', description: 'Collection totals grouped by cash, mobile money, bank and other methods.' },
  { type: 'collectors', title: 'Collectors', description: 'Operational collection totals grouped by user who received the payment.' },
  { type: 'member-statement', title: 'Member Statement', description: 'Single member pledge, transaction history, outstanding and credit summary.' },
]
const reportExportFormats: Record<string, Array<'CSV' | 'XLSX' | 'PDF' | 'PRINT'>> = {
  summary: ['PDF', 'PRINT'],
  pledges: ['XLSX', 'CSV', 'PDF', 'PRINT'],
  payments: ['XLSX', 'CSV', 'PDF', 'PRINT'],
  outstanding: ['XLSX', 'CSV', 'PDF', 'PRINT'],
  'payment-methods': ['XLSX', 'PDF', 'PRINT'],
  collectors: ['XLSX', 'PDF', 'PRINT'],
  'member-statement': ['PDF', 'PRINT'],
}
const smsTemplateOptions = [
  { code: 'ALL', label: 'All messages', variables: [] },
  { code: 'PLEDGE_REQUEST', label: 'Pledge Request', variables: ['member_name', 'event_name', 'event_date', 'pledge_deadline'] },
  { code: 'PLEDGE_REGISTRATION', label: 'Pledge Registration', variables: ['member_name', 'pledge_amount', 'event_name', 'due_date'] },
  { code: 'PAYMENT_CONFIRMATION', label: 'Payment Confirmation', variables: ['member_name', 'payment_amount', 'payment_method', 'event_name', 'balance', 'receipt_number'] },
  { code: 'BALANCE_REMINDER', label: 'Balance Reminder', variables: ['member_name', 'event_name', 'balance', 'due_date'] },
  { code: 'PLEDGE_COMPLETED', label: 'Pledge Completed', variables: ['member_name', 'pledge_amount', 'event_name'] },
] as const
const smsPreviewValues: Record<string, string> = {
  member_name: 'Asha Mrema',
  pledge_amount: '500,000',
  payment_amount: '100,000',
  payment_method: 'M-Pesa',
  event_name: 'Harusi ya Asha',
  balance: '400,000',
  receipt_number: 'RCT-00024',
  due_date: '15/08/2026',
  event_date: '11/09/2027',
  pledge_deadline: '01/09/2027',
}

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

function reminderStatusText(row: Row) {
  const status = asString(row.lastBalanceReminderStatus, '')
  const time = row.lastBalanceReminderAt
  if (!status) return 'Never Sent'
  return `${status}${time ? ` · ${asDateTime(time)}` : ''}`
}

function canSendBalanceReminder(row: Row) {
  return asNumber(row.outstandingAmount ?? row.outstanding_amount) > 0 && Boolean(row.smsEnabled ?? row.sms_enabled) && Boolean(asString(row.phone ?? row.phone_e164, '')) && !row.ineligibleReason
}

function jsonRecord(value: unknown): Row {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Row : {}
}

function maskPhone(value: unknown) {
  const phone = asString(value, '')
  return phone ? phone.replace(/[0-9](?=[0-9]{3})/g, '*') : 'No phone'
}

function isFinancialWhatsappFormat(format: string) {
  return format !== 'PRIVACY'
}

function subscriptionEventUsage(subscription: Row) {
  const eventUsage = jsonRecord(subscription.eventUsage)
  const limits = jsonRecord(subscription.limits)
  return {
    used: asNumber(eventUsage.used ?? limits.used ?? limits.usedEventSlots),
    limit: asNumber(eventUsage.limit ?? limits.limit ?? limits.maxEventSlots),
    available: asNumber(eventUsage.available ?? limits.available ?? limits.availableEventSlots),
    planCurrentMaxActiveEvents: asNumber(eventUsage.planCurrentMaxActiveEvents ?? limits.planCurrentMaxActiveEvents),
    subscriptionSnapshotMaxActiveEvents: asNumber(eventUsage.subscriptionSnapshotMaxActiveEvents ?? limits.subscriptionSnapshotMaxActiveEvents),
    effectiveMaxActiveEvents: asNumber(eventUsage.effectiveMaxActiveEvents ?? limits.effectiveMaxActiveEvents ?? eventUsage.limit ?? limits.maxEventSlots),
  }
}

async function copyPlainText(text: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text)
    return
  }
  const textarea = document.createElement('textarea')
  textarea.value = text
  textarea.setAttribute('readonly', 'true')
  textarea.style.position = 'fixed'
  textarea.style.left = '-9999px'
  document.body.appendChild(textarea)
  textarea.select()
  document.execCommand('copy')
  textarea.remove()
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
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const tenantId = session.selectedTenantId
  const tenantContext = session.selectedTenantContext
  const event = session.selectedTenantContext?.events[0] ?? null
  const eventLink = event ? `/app/events/${event.id}` : '/app'
  const [showEventForm, setShowEventForm] = useState(false)

  if (kind === 'events') {
    if (!tenantId || !tenantContext) {
      return (
        <PageContainer>
          <PageHeader title={title} description="Select a tenant to view and create events." />
          <EmptyState title="No tenant selected" message="Choose a tenant workspace first." />
        </PageContainer>
      )
    }
    const subscription = jsonRecord(tenantContext.subscription)
    const usage = subscriptionEventUsage(subscription)
    const canCreate = tenantContext.permissions.includes('events.create') && tenantContext.accessState !== 'READ_ONLY' && tenantContext.accessState !== 'BLOCKED' && usage.available > 0
    const blockedMessage = tenantContext.accessState === 'READ_ONLY'
      ? 'Your subscription is currently read-only. Resolve the subscription state before creating another event.'
      : usage.available <= 0
        ? `Your package allows ${usage.limit} active ${usage.limit === 1 ? 'event' : 'events'}. You are currently using ${usage.used}.`
        : !tenantContext.permissions.includes('events.create')
          ? 'Your tenant role does not include permission to create events.'
          : ''
    return (
      <PageContainer>
        <PageHeader
          title={title}
          description="Create and open tenant events."
          action={<button className="desktop-primary-button" type="button" disabled={!canCreate} onClick={() => setShowEventForm(true)}><Plus size={18} aria-hidden /> Create Event</button>}
        />
        <section className="stats-grid">
          <StatCard label="Used Slots" value={String(usage.used)} icon={CalendarDays} />
          <StatCard label="Package Limit" value={String(usage.limit)} meta={usage.limit === 1 ? '1 active event' : `Up to ${usage.limit} active events`} icon={FileText} />
          <StatCard label="Available" value={String(usage.available)} tone={usage.available > 0 ? 'success' : 'warning'} icon={CheckCircle2} />
        </section>
        {blockedMessage && !showEventForm ? <p className="field-error">{blockedMessage}</p> : null}
        {showEventForm ? <CreateEventForm
          tenantId={tenantId}
          onCancel={() => setShowEventForm(false)}
          onCreated={async (created) => {
            setShowEventForm(false)
            await session.selectTenant(tenantId)
            await session.refreshContext()
            void queryClient.invalidateQueries({ queryKey: ['tenant-settings-summary', tenantId] })
            navigate(`/app/events/${asString(created.eventId ?? created.event_id ?? created.id)}`)
          }}
        /> : null}
        <section className="cards-list">
          {tenantContext.events.map((tenantEvent) => (
            <Link to={`/app/events/${tenantEvent.id}`} className="summary-card" key={tenantEvent.id}>
              <CalendarDays size={20} aria-hidden />
              <div>
                <strong>{tenantEvent.name}</strong>
                <span>{tenantEvent.eventDate ? `Event date ${asDate(tenantEvent.eventDate)}` : tenantEvent.eventType}</span>
              </div>
              <StatusBadge tone={statusTone(tenantEvent.status)}>{tenantEvent.status}</StatusBadge>
            </Link>
          ))}
          {!tenantContext.events.length ? <EmptyState title="No events yet" message={canCreate ? 'Create your first event to begin collecting pledges.' : blockedMessage || 'No accessible events are available.'} /> : null}
        </section>
        {canCreate ? <button className="mobile-sticky-button" type="button" onClick={() => setShowEventForm(true)}>Create Event</button> : null}
      </PageContainer>
    )
  }

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

function CreateEventForm({ tenantId, onCancel, onCreated }: { tenantId: string; onCancel: () => void; onCreated: (created: Row) => Promise<void> }) {
  const [form, setForm] = useState({
    name: '',
    eventType: 'WEDDING',
    customEventType: '',
    eventDate: '',
    venue: '',
    targetAmount: '',
    pledgeDeadline: '',
  })
  const [success, setSuccess] = useState('')
  const mutation = useMutation({
    mutationFn: () => api.createEvent(tenantId, {
      name: form.name,
      eventType: form.eventType,
      customEventType: form.eventType === 'OTHER' ? form.customEventType : null,
      eventDate: form.eventDate || null,
      venue: form.venue || null,
      targetAmount: form.targetAmount ? Number(form.targetAmount) : null,
      pledgeDeadline: form.pledgeDeadline || null,
    }),
    onSuccess: async (result) => {
      setSuccess('Event created')
      await onCreated(result.data)
    },
  })

  function setField(field: keyof typeof form, value: string) {
    setForm((current) => ({ ...current, [field]: value }))
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    mutation.mutate()
  }

  return (
    <form className="mobile-sheet form-grid" onSubmit={submit}>
      <div className="panel-header">
        <div>
          <h2>Create Event</h2>
          <p>Set the basic event details. Payment instructions can be added later.</p>
        </div>
      </div>
      <label>Event name<input value={form.name} onChange={(event) => setField('name', event.target.value)} required minLength={2} /></label>
      <label>Event type<select value={form.eventType} onChange={(event) => setField('eventType', event.target.value)}>{eventTypes.map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label>
      {form.eventType === 'OTHER' ? <label>Custom event type<input value={form.customEventType} onChange={(event) => setField('customEventType', event.target.value)} required /></label> : null}
      <label>Event date<input type="date" value={form.eventDate} onChange={(event) => setField('eventDate', event.target.value)} /></label>
      <label>Venue<input value={form.venue} onChange={(event) => setField('venue', event.target.value)} /></label>
      <label>Target amount<input type="number" min="1" step="1" value={form.targetAmount} onChange={(event) => setField('targetAmount', event.target.value)} /></label>
      <label>Pledge deadline<input type="date" value={form.pledgeDeadline} onChange={(event) => setField('pledgeDeadline', event.target.value)} /></label>
      {success ? <p className="privacy-note">{success}</p> : null}
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Event could not be created.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onCancel}>Cancel</button>
        <button className="primary-button" type="submit" disabled={mutation.isPending}>{mutation.isPending ? 'Creating...' : 'Create Event'}</button>
      </div>
    </form>
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
        <Link to={`/app/events/${eventId}/outstanding`}>outstanding</Link>
        <Link to={`/app/events/${eventId}/reports`}>reports</Link>
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
          <span>No Pledge Yet: {asNumber(summary.membersWithoutPledges)} members</span>
        </div>
        <div className="card-actions">
          <Link className="primary-button inline-action" to={`/app/events/${eventId}/payments/new`}>Record Payment</Link>
          <Link to={`/app/events/${eventId}/share`}><Share2 size={16} aria-hidden /> Share List</Link>
          <Link to={`/app/events/${eventId}/outstanding`}>Send Reminders</Link>
          {asNumber(summary.membersWithoutPledges) > 0 ? <Link to={`/app/messages?eventId=${eventId}&segment=pledge-request`}>Send Request</Link> : null}
        </div>
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
  const reportTenantContext = useSessionStore().selectedTenantContext
  const permissions = new Set(reportTenantContext?.permissions ?? [])
  const [reminderOpen, setReminderOpen] = useState(false)
  const [pledgeRequestOpen, setPledgeRequestOpen] = useState(false)
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
        <ReviewLine label="Last reminder" value={reminderStatusText(member)} />
        {permissions.has('messages.send') && canSendBalanceReminder({ ...member, outstandingAmount: member.outstanding_amount, smsEnabled: member.sms_enabled, phone: member.phone_e164, fullName: member.full_name, pledgedAmount: member.pledged_amount, totalPaid: member.total_allocated, dueDate }) ? (
          <button className="primary-button inline-action" type="button" onClick={() => setReminderOpen(true)}>Send Reminder</button>
        ) : null}
        {permissions.has('messages.send') && !member.pledge_id ? (
          <button className="primary-button inline-action" type="button" onClick={() => setPledgeRequestOpen(true)}>Send Pledge Request</button>
        ) : null}
      </section>
      {reminderOpen ? <BalanceReminderSheet tenantId={tenantId ?? ''} eventId={eventId} member={{ ...member, eventMemberId, fullName: member.full_name, phone: member.phone_e164, pledgedAmount: member.pledged_amount, totalPaid: member.total_allocated, outstandingAmount: member.outstanding_amount, dueDate, messagePreview: '' }} onClose={() => setReminderOpen(false)} onSent={() => { setReminderOpen(false); void detail.refetch() }} /> : null}
      {pledgeRequestOpen ? <PledgeRequestSheet tenantId={tenantId ?? ''} eventId={eventId} eventMemberId={eventMemberId} eventName={activeEvent.event?.name ?? 'Event'} onClose={() => setPledgeRequestOpen(false)} onSent={() => { setPledgeRequestOpen(false); void detail.refetch() }} /> : null}
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

function BalanceReminderSheet({ tenantId, eventId, member, onClose, onSent }: { tenantId: string; eventId: string; member: Row; onClose: () => void; onSent: () => void }) {
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const mutation = useMutation({
    mutationFn: () => api.sendBalanceReminder(tenantId, eventId, { eventMemberId: asString(member.eventMemberId ?? member.event_member_id), idempotencyKey }),
    onSuccess: onSent,
  })
  return (
    <section className="mobile-sheet form-grid">
      <div className="panel-header">
        <div>
          <h2>Send Reminder</h2>
          <p>{asString(member.fullName ?? member.full_name, 'Member')} · {maskPhone(member.phone ?? member.phone_e164)}</p>
        </div>
      </div>
      <ReviewLine label="Pledged" value={moneyText(member.pledgedAmount ?? member.pledged_amount)} />
      <ReviewLine label="Paid" value={moneyText(member.totalPaid ?? member.total_paid ?? member.total_allocated)} />
      <ReviewLine label="Outstanding" value={moneyText(member.outstandingAmount ?? member.outstanding_amount)} />
      <ReviewLine label="Due date" value={asDate(member.dueDate ?? member.effective_due_date ?? member.due_date)} />
      <article className="content-panel">
        <p>{asString(member.messagePreview, 'Preview will be rendered again by the server before queueing.')}</p>
      </article>
      {mutation.data?.data?.queued === false ? <p className="field-error">{asString(mutation.data.data.reason, 'Reminder was not queued.')}</p> : null}
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Reminder could not be queued.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onClose}>Cancel</button>
        <button className="primary-button" type="button" disabled={mutation.isPending} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : 'Send Reminder'}</button>
      </div>
    </section>
  )
}

function PledgeRequestSheet({ tenantId, eventId, eventMemberId, eventName, onClose, onSent }: { tenantId: string; eventId: string; eventMemberId: string; eventName: string; onClose: () => void; onSent: () => void }) {
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const members = useQuery({ queryKey: ['no-pledge-members', tenantId, eventId, eventMemberId], queryFn: async () => (await api.eventNoPledgeMembers(tenantId, eventId)).data, enabled: Boolean(tenantId && eventId && eventMemberId) })
  const settings = useQuery({ queryKey: ['sms-settings', tenantId], queryFn: async () => (await api.smsSettings(tenantId)).data, enabled: Boolean(tenantId) })
  const member = (members.data ?? []).find((row) => asString(row.eventMemberId) === eventMemberId) ?? null
  const eligibility = member ? pledgeRequestEligibility(member) : { label: 'Has Pledge', tone: 'neutral' as const }
  const mutation = useMutation({
    mutationFn: () => api.sendPledgeRequest(tenantId, eventId, { eventMemberId, idempotencyKey }),
    onSuccess: onSent,
  })
  if (members.isLoading) return <LoadingState title="Loading pledge request preview" />
  if (members.isError) return <ErrorState title="Unable to prepare pledge request" message={errorMessage(members.error, 'Pledge request preview could not be loaded.')} />
  if (!member) return <ErrorState title="Pledge request unavailable" message="This member already has a pledge or is no longer active in the event." />
  return (
    <section className="mobile-sheet form-grid">
      <div className="panel-header">
        <div>
          <h2>Send Pledge Request</h2>
          <p>{asString(member.fullName, 'Member')} · {asString(member.maskedPhone, maskPhone(member.phone))}</p>
        </div>
        <StatusBadge tone={eligibility.tone}>{eligibility.label}</StatusBadge>
      </div>
      <ReviewLine label="Event" value={eventName} />
      <ReviewLine label="Sender ID" value={asString(settings.data?.senderId, 'MICHANGO')} />
      <article className="content-panel">
        <p>{asString(member.messagePreview, 'Preview will be rendered again by the server before queueing.')}</p>
      </article>
      {mutation.data?.data?.queued === false ? <p className="field-error">{asString(mutation.data.data.reason, 'Pledge request was not queued.')}</p> : null}
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Pledge request could not be queued.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onClose}>Cancel</button>
        <button className="primary-button" type="button" disabled={Boolean(member.ineligibleReason) || mutation.isPending} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : 'Send'}</button>
      </div>
    </section>
  )
}

export function ShareListPage() {
  const { eventId = '' } = useParams()
  const activeEvent = useActiveEventContext(eventId)
  const tenantId = activeEvent.tenantId
  const sessionPermissions = new Set(useSessionStore().selectedTenantContext?.permissions ?? [])
  const [format, setFormat] = useState('')
  const [statusFilter, setStatusFilter] = useState('ALL')
  const [categoryId, setCategoryId] = useState('')
  const [sort, setSort] = useState('')
  const [search, setSearch] = useState('')
  const [phoneFilter, setPhoneFilter] = useState('ALL')
  const [includeWithoutPledges, setIncludeWithoutPledges] = useState(false)
  const [includeSummary, setIncludeSummary] = useState<boolean | null>(null)
  const [includeEventDate, setIncludeEventDate] = useState<boolean | null>(null)
  const [includeEventPaymentInstructions, setIncludeEventPaymentInstructions] = useState<boolean | null>(null)
  const [includeMobileMoneyInstructions, setIncludeMobileMoneyInstructions] = useState<boolean | null>(null)
  const [includeBankInstructions, setIncludeBankInstructions] = useState<boolean | null>(null)
  const [headerText, setHeaderText] = useState<string | null>(null)
  const [footerText, setFooterText] = useState<string | null>(null)
  const [copyMessage, setCopyMessage] = useState('')
  const [selectedPart, setSelectedPart] = useState(0)
  const canQuery = Boolean(tenantId && eventId && !activeEvent.error)
  const settings = useQuery({ queryKey: ['whatsapp-share-settings', tenantId, eventId], queryFn: async () => (await api.whatsappShareSettings(tenantId ?? '', eventId)).data, enabled: canQuery })
  const canFinancial = Boolean(settings.data?.canUseFinancialFormats) || sessionPermissions.has('shares.whatsapp.financial')
  const effectiveFormat = !canFinancial && isFinancialWhatsappFormat(format) ? 'PRIVACY' : (format || asString(settings.data?.defaultListFormat, canFinancial ? 'DETAILED' : 'PRIVACY'))
  const effectiveSort = sort || asString(settings.data?.defaultSort, 'ORIGINAL')
  const effectiveIncludeSummary = effectiveFormat === 'PRIVACY' && includeSummary === null ? false : (includeSummary ?? settings.data?.defaultIncludeSummary !== false)
  const effectiveIncludeEventDate = includeEventDate ?? (settings.data?.includeEventDate === true)
  const effectiveIncludeEventPaymentInstructions = includeEventPaymentInstructions ?? (settings.data?.includeEventPaymentInstructions === true)
  const effectiveIncludeMobileMoneyInstructions = includeMobileMoneyInstructions ?? (settings.data?.includeMobileMoneyInstructions === true)
  const effectiveIncludeBankInstructions = includeBankInstructions ?? (settings.data?.includeBankInstructions === true)
  const effectiveHeaderText = headerText ?? asString(settings.data?.headerText, '')
  const effectiveFooterText = footerText ?? asString(settings.data?.footerText, '')

  const previewPayload = {
    format: effectiveFormat,
    statusFilter,
    categoryId: categoryId || null,
    sort: effectiveSort,
    includeSummary: effectiveIncludeSummary,
    includeEventDate: effectiveIncludeEventDate,
    includeEventPaymentInstructions: effectiveIncludeEventPaymentInstructions,
    includeMobileMoneyInstructions: effectiveIncludeMobileMoneyInstructions,
    includeBankInstructions: effectiveIncludeBankInstructions,
    includeWithoutPledges,
    phoneFilter,
    search,
  }
  const preview = useQuery({
    queryKey: ['whatsapp-share-preview', tenantId, eventId, previewPayload],
    queryFn: async () => (await api.whatsappSharePreview(tenantId ?? '', eventId, previewPayload)).data,
    enabled: canQuery && !settings.isLoading,
  })
  const saveSettings = useMutation({
    mutationFn: () => api.saveWhatsappShareSettings(tenantId ?? '', eventId, {
      headerText: effectiveHeaderText || null,
      footerText: effectiveFooterText || null,
      includeEventName: true,
      includeEventDate: effectiveIncludeEventDate,
      includeEventPaymentInstructions: effectiveIncludeEventPaymentInstructions,
      includeMobileMoneyInstructions: effectiveIncludeMobileMoneyInstructions,
      includeBankInstructions: effectiveIncludeBankInstructions,
      defaultListFormat: effectiveFormat,
      defaultSort: effectiveSort,
      defaultIncludeSummary: effectiveIncludeSummary,
    }),
    onSuccess: () => {
      void settings.refetch()
      setCopyMessage('Settings saved')
    },
  })
  const data = preview.data ?? {}
  const text = asString(data.text, '')
  const parts = Array.isArray(data.parts) ? data.parts.map(jsonRecord) : []
  const safeSelectedPart = Math.min(selectedPart, Math.max(parts.length - 1, 0))
  const currentPart = parts[safeSelectedPart] ?? parts[0] ?? null
  const categories = Array.isArray(data.categories) ? data.categories.map(jsonRecord) : []
  const shareAvailable = typeof navigator.share === 'function'

  async function copyText(value: string, label = 'List copied') {
    await copyPlainText(value)
    setCopyMessage(label)
  }

  async function shareText(value: string) {
    if (!navigator.share) return
    await navigator.share({ text: value })
    setCopyMessage('Share opened')
  }

  function openWhatsApp(value: string) {
    window.open(`https://wa.me/?text=${encodeURIComponent(value)}`, '_blank', 'noopener,noreferrer')
  }

  if (activeEvent.error) return <ErrorState title="Unable to open share list" message={activeEvent.error} />
  if (settings.isLoading) return <LoadingState title="Loading share settings" message="Preparing WhatsApp list defaults." />
  if (settings.isError) return <ErrorState title="Unable to load share list" message={errorMessage(settings.error, 'Share settings could not be loaded.')} />

  return (
    <PageContainer>
      <PageHeader title="Share List" description="Generate WhatsApp-ready contributor lists from current event balances." action={<Link to={`/app/events/${eventId}`}><ArrowLeft size={18} aria-hidden /> Back</Link>} />
      <section className="share-layout">
        <div className="share-controls">
          <article className="content-panel">
            <div className="panel-header">
              <div>
                <h2>List Format</h2>
                <p>{canFinancial ? 'Choose a public or committee-facing format.' : 'Your role can generate Privacy-Friendly lists only.'}</p>
              </div>
            </div>
            <div className="radio-card-grid">
              {whatsappFormats.filter((item) => canFinancial || !isFinancialWhatsappFormat(item.value)).map((item) => (
                <button className={effectiveFormat === item.value ? 'radio-card active' : 'radio-card'} type="button" key={item.value} onClick={() => {
                  setFormat(item.value)
                  if (item.value === 'PRIVACY') setIncludeSummary(false)
                }}>
                  <strong>{item.label}</strong>
                  <span>{item.description}</span>
                </button>
              ))}
            </div>
          </article>
          <article className="content-panel">
            <div className="panel-header"><h2>Filters</h2></div>
            <section className="filter-bar">
              <label>Status<select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>{whatsappStatuses.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
              <label>Category<select value={categoryId} onChange={(event) => setCategoryId(event.target.value)}><option value="">All categories</option>{categories.map((category) => <option key={asString(category.id)} value={asString(category.id)}>{asString(category.name)}</option>)}</select></label>
              <label>Sort<select value={effectiveSort} onChange={(event) => setSort(event.target.value)}>{whatsappSorts.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
              <label>Phone<select value={phoneFilter} onChange={(event) => setPhoneFilter(event.target.value)}><option value="ALL">All</option><option value="WITH_PHONE">Members with Phone</option><option value="WITHOUT_PHONE">Members without Phone</option></select></label>
              <label>Search<input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Member or code" /></label>
            </section>
            <label className="checkbox-row"><input type="checkbox" checked={includeWithoutPledges} onChange={(event) => setIncludeWithoutPledges(event.target.checked)} disabled={effectiveFormat !== 'PRIVACY'} /> Include registered members without pledges</label>
          </article>
          <article className="content-panel">
            <div className="panel-header"><h2>Options</h2></div>
            <div className="settings-grid">
              <label className="checkbox-row"><input type="checkbox" checked={effectiveIncludeSummary} onChange={(event) => setIncludeSummary(event.target.checked)} disabled={effectiveFormat === 'PRIVACY' && !canFinancial} /> Include Summary</label>
              <label className="checkbox-row"><input type="checkbox" checked={effectiveIncludeEventDate} onChange={(event) => setIncludeEventDate(event.target.checked)} /> Include Event Date</label>
              <label className="checkbox-row"><input type="checkbox" checked={effectiveIncludeEventPaymentInstructions} onChange={(event) => setIncludeEventPaymentInstructions(event.target.checked)} /> Include Event Payment Instructions</label>
              <label className="checkbox-row"><input type="checkbox" checked={effectiveIncludeMobileMoneyInstructions} onChange={(event) => setIncludeMobileMoneyInstructions(event.target.checked)} /> Include Mobile Money</label>
              <label className="checkbox-row"><input type="checkbox" checked={effectiveIncludeBankInstructions} onChange={(event) => setIncludeBankInstructions(event.target.checked)} /> Include Bank Instructions</label>
            </div>
            <label>Header Text<textarea value={effectiveHeaderText} onChange={(event) => setHeaderText(event.target.value)} rows={3} placeholder={asString(settings.data?.defaultHeaderText)} /></label>
            <label>Footer Text<textarea value={effectiveFooterText} onChange={(event) => setFooterText(event.target.value)} rows={3} placeholder="Karibuni sana kwa michango na ahadi." /></label>
            {saveSettings.error ? <p className="field-error">{errorMessage(saveSettings.error, 'Share settings could not be saved.')}</p> : null}
            <div className="sheet-actions">
              <button type="button" onClick={() => { setHeaderText(''); setFooterText('') }}>Reset to Default</button>
              {canFinancial ? <button className="primary-button" type="button" disabled={saveSettings.isPending} onClick={() => saveSettings.mutate()}>{saveSettings.isPending ? 'Saving...' : 'Save Settings'}</button> : null}
            </div>
          </article>
        </div>
        <aside className="share-preview-panel">
          <div className="panel-header">
            <div>
              <h2>Live Preview</h2>
              <p>{asNumber(data.memberCount)} contributors · {asNumber(data.textLength)} characters</p>
            </div>
            <StatusBadge tone={data.isLong ? 'warning' : 'success'}>{data.isLong ? 'Long' : 'Ready'}</StatusBadge>
          </div>
          {preview.isLoading ? <LoadingState title="Generating preview" /> : null}
          {preview.isError ? <ErrorState title="Unable to load the share list." message={errorMessage(preview.error, 'Share list could not be generated.')} /> : null}
          {!preview.isLoading && !preview.isError && asNumber(data.memberCount) === 0 ? <EmptyState title="No pledge records are available for this list." message="Change the filters or add active pledges to this event." /> : null}
          {data.isLong ? <p className="field-error">This list is long and may be difficult to send as one WhatsApp message.</p> : null}
          {asNumber(data.memberCount) > 0 ? <pre className="whatsapp-preview">{text}</pre> : null}
          {parts.length > 1 ? (
            <section className="split-parts">
              <div className="card-title-row">
                <strong>Part {asNumber(currentPart?.part)} of {asNumber(currentPart?.totalParts)}</strong>
                <div className="card-actions">
                  <button type="button" disabled={safeSelectedPart <= 0} onClick={() => setSelectedPart((value) => Math.max(value - 1, 0))}>Previous</button>
                  <button type="button" disabled={safeSelectedPart >= parts.length - 1} onClick={() => setSelectedPart((value) => Math.min(value + 1, parts.length - 1))}>Next Part</button>
                </div>
              </div>
              <pre className="whatsapp-preview compact">{asString(currentPart?.text)}</pre>
            </section>
          ) : null}
          {copyMessage ? <p className="privacy-note">{copyMessage}</p> : null}
          <div className="share-actions">
            <button className="primary-button" type="button" disabled={!text} onClick={() => void copyText(text)}>
              <Copy size={18} aria-hidden /> Copy List
            </button>
            {parts.length > 1 ? <button type="button" onClick={() => void copyText(parts.map((part) => asString(part.text)).join('\n\n---\n\n'), 'All parts copied')}>Copy All Parts</button> : null}
            {parts.length > 1 && currentPart ? <button type="button" onClick={() => void copyText(asString(currentPart.text), `Part ${asNumber(currentPart.part)} copied`)}>Copy Part {asNumber(currentPart.part)}</button> : null}
            {shareAvailable ? <button type="button" disabled={!text} onClick={() => void shareText(parts.length > 1 && currentPart ? asString(currentPart.text) : text)}><Send size={18} aria-hidden /> Share</button> : null}
            <button type="button" disabled={!text} onClick={() => openWhatsApp(parts.length > 1 && currentPart ? asString(currentPart.text) : text)}><MessageCircle size={18} aria-hidden /> Open WhatsApp</button>
          </div>
        </aside>
      </section>
    </PageContainer>
  )
}

export function OutstandingPage() {
  const { eventId = '' } = useParams()
  const activeEvent = useActiveEventContext(eventId)
  const tenantId = activeEvent.tenantId
  const reportTenantContext = useSessionStore().selectedTenantContext
  const permissions = new Set(reportTenantContext?.permissions ?? [])
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('ALL')
  const [selectionMode, setSelectionMode] = useState(false)
  const [selected, setSelected] = useState<string[]>([])
  const [singleMember, setSingleMember] = useState<Row | null>(null)
  const [bulkPreview, setBulkPreview] = useState(false)
  const [bulkIdempotencyKey, resetBulkIdempotencyKey] = useState(() => crypto.randomUUID())
  const queryClient = useQueryClient()
  const outstanding = useQuery({ queryKey: ['event-outstanding-members', tenantId, eventId], queryFn: async () => (await api.eventOutstandingMembers(tenantId ?? '', eventId)).data, enabled: Boolean(tenantId && eventId && !activeEvent.error) })
  const rows = outstanding.data ?? []
  const filtered = rows.filter((row) => {
    const searchText = `${row.fullName ?? ''} ${row.phone ?? ''} ${row.memberCode ?? ''}`.toLowerCase()
    const matchesSearch = searchText.includes(query.toLowerCase())
    const reason = asString(row.ineligibleReason, '')
    const dueDate = row.dueDate
    const matchesFilter =
      filter === 'ALL' ||
      (filter === 'OVERDUE' && asNumber(row.daysOverdue) > 0) ||
      (filter === 'DUE_SOON' && row.isDueSoon === true) ||
      (filter === 'PARTIAL' && row.pledgeStatus === 'PARTIALLY_PAID') ||
      (filter === 'UNPAID' && row.pledgeStatus === 'PENDING') ||
      (filter === 'NO_DUE_DATE' && !dueDate) ||
      (filter === 'SMS_AVAILABLE' && !reason) ||
      (filter === 'SMS_DISABLED' && reason === 'SMS_DISABLED')
    return matchesSearch && matchesFilter
  })
  const eligibleVisible = filtered.filter(canSendBalanceReminder)
  const selectedRows = rows.filter((row) => selected.includes(asString(row.eventMemberId)))
  const bulkMutation = useMutation({
    mutationFn: () => api.sendBulkBalanceReminders(tenantId ?? '', eventId, { eventMemberIds: selected, idempotencyKey: bulkIdempotencyKey }),
    onSuccess: () => {
      resetBulkIdempotencyKey(crypto.randomUUID())
      setSelected([])
      setBulkPreview(false)
      setSelectionMode(false)
      void queryClient.invalidateQueries({ queryKey: ['event-outstanding-members', tenantId, eventId] })
      void queryClient.invalidateQueries({ queryKey: ['sms-history', tenantId] })
    },
  })

  if (activeEvent.error) return <ErrorState title="Unable to load outstanding members" message={activeEvent.error} />
  if (outstanding.isLoading) return <LoadingState title="Loading outstanding members" message="Fetching current balances and reminder state." />
  if (outstanding.isError) return <ErrorState title="Unable to load outstanding members" message={errorMessage(outstanding.error, 'Outstanding members could not be loaded.')} />

  const totalOutstanding = rows.reduce((sum, row) => sum + asNumber(row.outstandingAmount), 0)
  const overdue = rows.filter((row) => asNumber(row.daysOverdue) > 0).length
  const dueSoon = rows.filter((row) => row.isDueSoon === true).length
  const noDueDate = rows.filter((row) => !row.dueDate).length
  const skipped = {
    noPhone: selectedRows.filter((row) => row.ineligibleReason === 'NO_PHONE').length,
    smsDisabled: selectedRows.filter((row) => row.ineligibleReason === 'SMS_DISABLED').length,
    recentlySent: selectedRows.filter((row) => row.ineligibleReason === 'RECENTLY_SENT').length,
  }
  const eligibleSelected = selectedRows.filter(canSendBalanceReminder)

  return (
    <PageContainer>
      <PageHeader title="Outstanding" description="Current pledge balances and manual balance reminders." action={<Link to={`/app/events/${eventId}`}><ArrowLeft size={18} aria-hidden /> Back</Link>} />
      <section className="stats-grid">
        <StatCard label="Total Outstanding" value={moneyText(totalOutstanding)} icon={Clock3} tone="warning" />
        <StatCard label="Members Outstanding" value={String(rows.length)} icon={Users} />
        <StatCard label="Overdue" value={String(overdue)} icon={Clock3} tone="danger" />
        <StatCard label="Due Soon" value={String(dueSoon)} meta={`${noDueDate} no due date`} icon={CalendarDays} />
      </section>
      <section className="filter-bar">
        <label>Search<input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name, phone or member code" /></label>
        <label>Filter<select value={filter} onChange={(event) => setFilter(event.target.value)}>{['ALL', 'OVERDUE', 'DUE_SOON', 'PARTIAL', 'UNPAID', 'NO_DUE_DATE', 'SMS_AVAILABLE', 'SMS_DISABLED'].map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label>
        {permissions.has('messages.send') ? <button type="button" onClick={() => setSelectionMode((value) => !value)}>{selectionMode ? 'Done' : 'Select'}</button> : null}
        {selectionMode ? <button type="button" onClick={() => setSelected(eligibleVisible.map((row) => asString(row.eventMemberId)))}>Select All Visible</button> : null}
      </section>
      <div className="finance-card-list">
        {filtered.map((row) => {
          const eventMemberId = asString(row.eventMemberId)
          const eligible = canSendBalanceReminder(row)
          return (
            <article className="finance-card" key={eventMemberId}>
              <div className="card-title-row">
                <div>
                  <strong>{asString(row.fullName, 'Member')}</strong>
                  <span>{asString(row.phone, 'No phone')} · {asString(row.memberCode)}</span>
                </div>
                <StatusBadge tone={eligible ? 'success' : 'warning'}>{eligible ? 'SMS Available' : asString(row.ineligibleReason, 'Not eligible')}</StatusBadge>
              </div>
              <div className="amount-triplet">
                <span><small>Pledged</small>{moneyText(row.pledgedAmount)}</span>
                <span><small>Paid</small>{moneyText(row.totalPaid)}</span>
                <span><small>Outstanding</small>{moneyText(row.outstandingAmount)}</span>
              </div>
              <p className="privacy-note">Due {asDate(row.dueDate)} · {asNumber(row.daysOverdue) > 0 ? `${asNumber(row.daysOverdue)} days overdue` : row.isDueSoon ? 'due soon' : 'not overdue'} · Last reminder: {reminderStatusText(row)}</p>
              <div className="card-actions">
                {selectionMode ? <label className="checkbox-row"><input type="checkbox" disabled={!eligible} checked={selected.includes(eventMemberId)} onChange={(event) => setSelected((current) => event.target.checked ? [...current, eventMemberId] : current.filter((id) => id !== eventMemberId))} /> Select</label> : null}
                {permissions.has('messages.send') && eligible ? <button type="button" onClick={() => setSingleMember(row)}>Send Reminder</button> : null}
                <Link to={`/app/events/${eventId}/members/${eventMemberId}`}>View Member</Link>
              </div>
            </article>
          )
        })}
        {!rows.length ? <EmptyState title="No outstanding balances." message="Members with unpaid pledge balances will appear here." /> : null}
        {rows.length > 0 && !filtered.length ? <EmptyState title="No members match these filters." message="Change the filter or search text." /> : null}
      </div>
      {selectionMode && selected.length ? <div className="mobile-action-bar"><button type="button" onClick={() => setBulkPreview(true)}>Send Reminders ({selected.length})</button></div> : null}
      {singleMember ? <BalanceReminderSheet tenantId={tenantId ?? ''} eventId={eventId} member={singleMember} onClose={() => setSingleMember(null)} onSent={() => { setSingleMember(null); void outstanding.refetch() }} /> : null}
      {bulkPreview ? <section className="mobile-sheet form-grid">
        <h2>Review Reminders</h2>
        <ReviewLine label="Selected" value={String(selectedRows.length)} />
        <ReviewLine label="Eligible" value={String(eligibleSelected.length)} />
        <ReviewLine label="No Phone" value={String(skipped.noPhone)} />
        <ReviewLine label="SMS Disabled" value={String(skipped.smsDisabled)} />
        <ReviewLine label="Recently Sent" value={String(skipped.recentlySent)} />
        <ReviewLine label="Estimated SMS" value={String(eligibleSelected.length)} />
        <div className="finance-card-list">{eligibleSelected.slice(0, 3).map((row) => <article className="content-panel" key={asString(row.eventMemberId)}><p>{asString(row.messagePreview)}</p></article>)}</div>
        {bulkMutation.data ? <p className="privacy-note">Queued: {asString(bulkMutation.data.data.queued)} · Batch {asString(bulkMutation.data.data.batchId)}</p> : null}
        {bulkMutation.error ? <p className="field-error">{errorMessage(bulkMutation.error, 'Bulk reminders could not be queued.')}</p> : null}
        <div className="sheet-actions"><button type="button" onClick={() => setBulkPreview(false)}>Back</button><button className="primary-button" type="button" disabled={!eligibleSelected.length || bulkMutation.isPending} onClick={() => bulkMutation.mutate()}>{bulkMutation.isPending ? 'Queueing...' : `Queue ${eligibleSelected.length} Reminders`}</button></div>
      </section> : null}
    </PageContainer>
  )
}

export function SmsHistoryPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const eventOptions = session.selectedTenantContext?.events ?? []
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const queryClient = useQueryClient()
  const [searchParams] = useSearchParams()
  const canManageTemplates = permissions.has('messages.manage_templates')
  const canManageSettings = permissions.has('messages.manage_settings')
  const canSendMessages = permissions.has('messages.send')
  const [status, setStatus] = useState('ALL')
  const [type, setType] = useState('ALL')
  const [eventId, setEventId] = useState(searchParams.get('eventId') ?? 'ALL')
  const [query, setQuery] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [pledgeRequestOpen, setPledgeRequestOpen] = useState(searchParams.get('segment') === 'pledge-request')
  const messages = useQuery({ queryKey: ['sms-history', tenantId], queryFn: async () => (await api.messages(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const settings = useQuery({ queryKey: ['sms-settings', tenantId], queryFn: async () => (await api.smsSettings(tenantId ?? '')).data, enabled: Boolean(tenantId && canManageSettings) })
  const templates = useQuery({ queryKey: ['sms-templates', tenantId], queryFn: async () => (await api.smsTemplates(tenantId ?? '')).data, enabled: Boolean(tenantId && canManageTemplates) })
  const processQueued = useMutation({
    mutationFn: () => api.processQueuedMessages(tenantId ?? '', 25),
    onSuccess: () => void messages.refetch(),
  })
  const rows = messages.data ?? []
  const filtered = rows.filter((message) => {
    const messageStatus = asString(message.status)
    const statusMatches = status === 'ALL' || (status === 'SENT' ? ['SENT', 'DELIVERED'].includes(messageStatus) : messageStatus === status)
    const typeMatches = type === 'ALL' || message.template_code === type
    const eventMatches = eventId === 'ALL' || message.event_id === eventId
    const queryMatches = `${message.member_name ?? ''} ${message.phone_e164 ?? ''} ${message.template_code ?? ''}`.toLowerCase().includes(query.toLowerCase())
    const createdAt = asString(message.created_at, '')
    const dateMatches = (!dateFrom || createdAt >= new Date(dateFrom).toISOString()) && (!dateTo || createdAt <= new Date(`${dateTo}T23:59:59`).toISOString())
    return statusMatches && typeMatches && eventMatches && queryMatches && dateMatches
  })
  const sentCount = rows.filter((message) => ['SENT', 'DELIVERED'].includes(asString(message.status))).length
  const failedCount = rows.filter((message) => asString(message.status) === 'FAILED').length
  const queuedCount = rows.filter((message) => ['QUEUED', 'PROCESSING'].includes(asString(message.status))).length
  const deliveryRate = rows.length ? Math.round((sentCount / rows.length) * 100) : 0
  const activeEvent = eventOptions[0] ?? null
  const pledgeRequestEventId = eventId !== 'ALL' ? eventId : activeEvent?.id
  const pledgeRequestEvent = eventOptions.find((event) => event.id === pledgeRequestEventId) ?? activeEvent ?? null

  if (!tenantId) return <ErrorState title="Unable to load SMS history" message="Select a tenant first." />
  if (messages.isLoading) return <LoadingState title="Loading messages" message="Fetching SMS confirmation history." />
  if (messages.isError) return <ErrorState title="Unable to load messages" message={errorMessage(messages.error, 'SMS history could not be loaded.')} />

  return (
    <PageContainer>
      <PageHeader
        title="Messages"
        description="SMS delivery history and balance reminder controls, plus sender settings and business message templates for this tenant."
        action={<div className="inline-actions">{canSendMessages ? <button type="button" disabled={processQueued.isPending || queuedCount === 0} onClick={() => processQueued.mutate()}><Send size={18} aria-hidden /> {processQueued.isPending ? 'Sending...' : 'Send queued'}</button> : null}{activeEvent ? <Link className="desktop-primary-button" to={`/app/events/${activeEvent.id}/outstanding`}><Clock3 size={18} aria-hidden /> Reminders</Link> : null}</div>}
      />
      <section className="messages-hero">
        <div>
          <span>SMS health</span>
          <strong>{deliveryRate}%</strong>
          <p>{sentCount} sent or delivered from {rows.length} total messages.</p>
        </div>
        <div className="messages-hero-strip">
          <span><CheckCircle2 size={18} aria-hidden /> {sentCount} delivered</span>
          <span><Clock3 size={18} aria-hidden /> {queuedCount} queued</span>
          <span><FileText size={18} aria-hidden /> {failedCount} failed</span>
        </div>
      </section>
      <section className="stats-grid messages-stats">
        <StatCard label="Messages" value={String(rows.length)} meta={`${filtered.length} shown`} icon={MessageCircle} />
        <StatCard label="Delivered/Sent" value={String(sentCount)} meta={`${deliveryRate}% delivery rate`} icon={CheckCircle2} tone="success" />
        <StatCard label="Queued" value={String(queuedCount)} meta="Waiting or processing" icon={Clock3} tone="warning" />
        <StatCard label="Failed" value={String(failedCount)} meta="Needs review" icon={FileText} tone={failedCount ? 'danger' : 'neutral'} />
      </section>
      {processQueued.data ? <p className="message-send-result">Processed {displayValue(processQueued.data.data.claimed, '0')} queued messages · Sent {displayValue(processQueued.data.data.sent, '0')} · Failed {displayValue(processQueued.data.data.failed, '0')}</p> : null}
      {processQueued.error ? <p className="field-error">Unable to process queued messages: {errorMessage(processQueued.error, 'Send attempt failed.')}</p> : null}
      {pledgeRequestEventId ? (
        <section className="content-panel pledge-request-summary">
          <div className="panel-header">
            <div>
              <h2>Members Without Pledge</h2>
              <p>{pledgeRequestEvent?.name ?? 'Selected event'} · request pledges without mixing them into outstanding balances.</p>
            </div>
            {canSendMessages ? <button className="primary-button inline-action" type="button" onClick={() => setPledgeRequestOpen((current) => !current)}>{pledgeRequestOpen ? 'Hide Selection' : 'Send Pledge Request'}</button> : null}
          </div>
          {pledgeRequestOpen && canSendMessages ? <PledgeRequestSelection tenantId={tenantId} eventId={pledgeRequestEventId} eventName={pledgeRequestEvent?.name ?? 'Event'} onQueued={() => { void messages.refetch(); void queryClient.invalidateQueries({ queryKey: ['no-pledge-members', tenantId, pledgeRequestEventId] }) }} /> : null}
        </section>
      ) : null}
      <div className={(canManageTemplates || canManageSettings) ? 'messages-layout messages-layout-with-template' : 'messages-layout'}>
        <section className="messages-history-panel">
          <div className="messages-filter-panel">
            <div className="messages-filter-header">
              <div>
                <strong>Message History</strong>
                <span>{filtered.length} of {rows.length} messages</span>
              </div>
              <label className="messages-search-field">
                <Search size={18} aria-hidden />
                <input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search member or phone" />
              </label>
            </div>
            <div className="messages-status-tabs">
              {['ALL', 'QUEUED', 'SENT', 'FAILED'].map((item) => <button key={item} className={status === item ? 'active' : ''} type="button" onClick={() => setStatus(item)}>{item === 'SENT' ? 'Sent' : item.charAt(0) + item.slice(1).toLowerCase()}</button>)}
            </div>
            <div className="messages-filter-grid">
              <label>Type<select value={type} onChange={(event) => setType(event.target.value)}>{smsTemplateOptions.map((option) => <option key={option.code} value={option.code}>{option.label}</option>)}</select></label>
              <label>Status<select value={status} onChange={(event) => setStatus(event.target.value)}>{['ALL', 'QUEUED', 'PROCESSING', 'SENT', 'DELIVERED', 'FAILED', 'CANCELLED'].map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
              <label>Event<select value={eventId} onChange={(event) => setEventId(event.target.value)}><option value="ALL">All events</option>{eventOptions.map((event) => <option key={event.id} value={event.id}>{event.name}</option>)}</select></label>
              <label>From<input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
              <label>To<input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} /></label>
            </div>
          </div>
          <div className="messages-list">
            {filtered.map((message) => <MessageHistoryCard key={asString(message.id)} message={message} tenantId={tenantId} canResend={canSendMessages} onResent={() => void messages.refetch()} />)}
            {!rows.length ? <EmptyState title="No SMS messages yet." message="Payment confirmations will appear here after payments are recorded." /> : null}
            {rows.length > 0 && !filtered.length ? <EmptyState title="No messages match these filters." message="Change the status, event, or search text." /> : null}
          </div>
        </section>
        {(canManageTemplates || canManageSettings) ? (
          <aside className="messages-template-block">
            {canManageSettings ? <SmsSettingsPanel key={`${String(settings.data?.smsEnabled)}-${asString(settings.data?.senderId, 'MICHANGO')}`} tenantId={tenantId} settings={settings.data ?? null} loading={settings.isLoading} onSaved={() => void queryClient.invalidateQueries({ queryKey: ['sms-settings', tenantId] })} /> : null}
            {canManageTemplates ? <SmsTemplateManager tenantId={tenantId} templates={templates.data ?? []} loading={templates.isLoading} onSaved={() => void queryClient.invalidateQueries({ queryKey: ['sms-templates', tenantId] })} /> : null}
          </aside>
        ) : null}
      </div>
    </PageContainer>
  )
}

function messageCardClass(status: unknown) {
  const normalized = asString(status, 'QUEUED').toLowerCase().replace(/[^a-z0-9]+/g, '-')
  return `message-card message-card-${normalized}`
}

function pledgeRequestEligibility(row: Row) {
  const reason = asString(row.ineligibleReason)
  if (!reason) return { label: 'Ready', tone: 'success' as const }
  if (reason === 'NO_PHONE') return { label: 'No Phone', tone: 'danger' as const }
  if (reason === 'SMS_DISABLED') return { label: 'SMS Disabled', tone: 'warning' as const }
  if (reason === 'RECENTLY_SENT') return { label: 'Recently Sent', tone: 'warning' as const }
  if (reason === 'HAS_PLEDGE') return { label: 'Has Pledge', tone: 'neutral' as const }
  return { label: reason.replaceAll('_', ' '), tone: 'neutral' as const }
}

function PledgeRequestSelection({ tenantId, eventId, eventName, onQueued }: { tenantId: string; eventId: string; eventName: string; onQueued: () => void }) {
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('ALL')
  const [selected, setSelected] = useState<string[]>([])
  const [previewOpen, setPreviewOpen] = useState(false)
  const [idempotencyKey, resetIdempotencyKey] = useState(() => crypto.randomUUID())
  const members = useQuery({ queryKey: ['no-pledge-members', tenantId, eventId], queryFn: async () => (await api.eventNoPledgeMembers(tenantId, eventId)).data, enabled: Boolean(tenantId && eventId) })
  const rows = members.data ?? []
  const categories = Array.from(new Set(rows.map((row) => asString(row.category, 'No category')))).sort()
  const filtered = rows.filter((row) => {
    const queryMatches = `${row.fullName ?? ''} ${row.memberCode ?? ''} ${row.phone ?? ''}`.toLowerCase().includes(query.toLowerCase())
    const categoryMatches = category === 'ALL' || asString(row.category, 'No category') === category
    return queryMatches && categoryMatches
  })
  const eligibleVisible = filtered.filter((row) => !asString(row.ineligibleReason))
  const selectedRows = rows.filter((row) => selected.includes(asString(row.eventMemberId)))
  const eligibleSelected = selectedRows.filter((row) => !asString(row.ineligibleReason))
  const skipped = {
    noPhone: selectedRows.filter((row) => asString(row.ineligibleReason) === 'NO_PHONE').length,
    smsDisabled: selectedRows.filter((row) => asString(row.ineligibleReason) === 'SMS_DISABLED').length,
    recentlySent: selectedRows.filter((row) => asString(row.ineligibleReason) === 'RECENTLY_SENT').length,
    hasPledge: selectedRows.filter((row) => asString(row.ineligibleReason) === 'HAS_PLEDGE').length,
  }
  const mutation = useMutation({
    mutationFn: () => api.sendBulkPledgeRequests(tenantId, eventId, { eventMemberIds: eligibleSelected.map((row) => asString(row.eventMemberId)), idempotencyKey }),
    onSuccess: () => {
      resetIdempotencyKey(crypto.randomUUID())
      setSelected([])
      setPreviewOpen(false)
      onQueued()
      void members.refetch()
    },
  })
  const toggle = (eventMemberId: string) => setSelected((current) => current.includes(eventMemberId) ? current.filter((id) => id !== eventMemberId) : [...current, eventMemberId])
  const selectAllVisible = () => setSelected((current) => Array.from(new Set([...current, ...eligibleVisible.map((row) => asString(row.eventMemberId)).filter(Boolean)])))

  if (members.isLoading) return <LoadingState title="Loading no-pledge members" />
  if (members.isError) return <ErrorState title="Unable to load no-pledge members" message={errorMessage(members.error, 'Members without pledges could not be loaded.')} />

  return (
    <div className="pledge-request-panel">
      <div className="messages-filter-grid">
        <label>Search<input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name, phone or member code" /></label>
        <label>Category<select value={category} onChange={(event) => setCategory(event.target.value)}><option value="ALL">All categories</option>{categories.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
      </div>
      <div className="mini-stat-row">
        <span>{rows.length} without pledge</span>
        <span>{eligibleVisible.length} ready visible</span>
        <span>{selected.length} selected</span>
      </div>
      <div className="inline-actions">
        <button type="button" onClick={selectAllVisible} disabled={!eligibleVisible.length}>Select All Visible</button>
        <button type="button" onClick={() => setSelected([])} disabled={!selected.length}>Clear</button>
        <button className="primary-button" type="button" onClick={() => setPreviewOpen(true)} disabled={!eligibleSelected.length}>Send Pledge Request ({eligibleSelected.length})</button>
      </div>
      <div className="finance-card-list">
        {filtered.map((row) => {
          const eventMemberId = asString(row.eventMemberId)
          const eligibility = pledgeRequestEligibility(row)
          const eligible = !asString(row.ineligibleReason)
          return (
            <article className="finance-card pledge-request-card" key={eventMemberId}>
              <label className="checkbox-line">
                <input type="checkbox" checked={selected.includes(eventMemberId)} disabled={!eligible} onChange={() => toggle(eventMemberId)} />
                <span><strong>{asString(row.fullName, 'Member')}</strong><small>{asString(row.maskedPhone, maskPhone(row.phone))} · {asString(row.category, 'No category')}</small></span>
              </label>
              <div className="card-title-row">
                <span>Last Request: {asDateTime(row.lastPledgeRequestAt)}</span>
                <StatusBadge tone={eligibility.tone}>{eligibility.label}</StatusBadge>
              </div>
            </article>
          )
        })}
        {!rows.length ? <EmptyState title="No members without pledges." message="Everyone in this event already has an active pledge." /> : null}
        {rows.length > 0 && !filtered.length ? <EmptyState title="No members match these filters." message="Try another name or category." /> : null}
      </div>
      {previewOpen ? <section className="mobile-sheet form-grid">
        <h2>Review Pledge Requests</h2>
        <ReviewLine label="Event" value={eventName} />
        <ReviewLine label="Selected" value={String(selectedRows.length)} />
        <ReviewLine label="Eligible" value={String(eligibleSelected.length)} />
        <ReviewLine label="No Phone" value={String(skipped.noPhone)} />
        <ReviewLine label="SMS Disabled" value={String(skipped.smsDisabled)} />
        <ReviewLine label="Recently Sent" value={String(skipped.recentlySent)} />
        <ReviewLine label="Has Pledge" value={String(skipped.hasPledge)} />
        <ReviewLine label="Estimated SMS" value={String(eligibleSelected.length)} />
        <div className="finance-card-list">{eligibleSelected.slice(0, 3).map((row) => <article className="content-panel" key={asString(row.eventMemberId)}><p>{asString(row.messagePreview)}</p></article>)}</div>
        {mutation.data ? <p className="privacy-note">Queued: {asString(mutation.data.data.queued)} · Allowed: {asString(mutation.data.data.allowedBySmsBalance, 'unlimited')} · Batch {asString(mutation.data.data.batchId)}</p> : null}
        {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Pledge requests could not be queued.')}</p> : null}
        <div className="sheet-actions"><button type="button" onClick={() => setPreviewOpen(false)}>Cancel</button><button className="primary-button" type="button" disabled={!eligibleSelected.length || mutation.isPending} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : `Queue ${eligibleSelected.length} Messages`}</button></div>
      </section> : null}
    </div>
  )
}

function MessageHistoryCard({ message, tenantId, canResend, onResent }: { message: Row; tenantId: string; canResend: boolean; onResent: () => void }) {
  const status = asString(message.status, 'QUEUED')
  const type = asString(message.message_type, asString(message.template_code, 'Message'))
  const preview = asString(message.body ?? message.message_body ?? message.rendered_body ?? message.messagePreview, '')
  const failed = status === 'FAILED'
  const cancelled = status === 'CANCELLED'
  return (
    <article className={messageCardClass(status)}>
      <div className="message-card-icon">
        <MessageCircle size={20} aria-hidden />
      </div>
      <div className="message-card-content">
        <div className="message-card-top">
          <div>
            <strong>{asString(message.member_name, 'Recipient')}</strong>
            <span>{type} · {asString(message.event_name, 'No event')}</span>
          </div>
          <StatusBadge tone={statusTone(status)}>{status}</StatusBadge>
        </div>
        <div className="message-meta-grid">
          <span><small>Phone</small>{maskPhone(message.phone_e164)}</span>
          <span><small>Template</small>{asString(message.template_code, 'Message')}</span>
          <span><small>Created</small>{asDateTime(message.created_at)}</span>
          <span><small>Sent</small>{asDateTime(message.sent_at)}</span>
          <span><small>Delivered</small>{asDateTime(message.delivered_at)}</span>
          <span><small>Sender</small>{asString(message.sender_id, 'MICHANGO')}</span>
          <span><small>Provider</small>{asString(message.provider, 'SMS')}</span>
          <span><small>Attempts</small>{String(asNumber(message.attempt_count))}</span>
        </div>
        {preview ? <p className="message-preview">{preview}</p> : null}
        {failed || cancelled ? <div className="message-error-callout"><strong>{cancelled ? 'Cancelled' : asString(message.last_error_code, 'Delivery failed')}</strong><span>{cancelled ? asString(message.last_error_message, 'Member has already pledged') : asString(message.last_error_message, 'SMS delivery failed.')}</span></div> : null}
        {failed && canResend ? <RetrySmsButton tenantId={tenantId} outboxId={asString(message.id)} onDone={onResent} /> : null}
      </div>
    </article>
  )
}

function renderPreviewTemplate(body: string) {
  return body.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_match, key: string) => smsPreviewValues[key] ?? '')
}

function smsPartCount(body: string) {
  const length = body.length
  return length <= 160 ? 1 : Math.ceil(length / 153)
}

function SmsSettingsPanel({ tenantId, settings, loading, onSaved }: { tenantId: string; settings: Row | null; loading: boolean; onSaved: () => void }) {
  const [smsEnabled, setSmsEnabled] = useState(Boolean(settings?.smsEnabled ?? true))
  const [senderId, setSenderId] = useState(asString(settings?.senderId, 'MICHANGO'))
  const mutation = useMutation({
    mutationFn: () => api.saveSmsSettings(tenantId, { smsEnabled, senderId, defaultLanguage: asString(settings?.defaultLanguage, 'sw') }),
    onSuccess: (result) => {
      setSmsEnabled(Boolean(result.data.smsEnabled ?? true))
      setSenderId(asString(result.data.senderId, 'MICHANGO'))
      onSaved()
    },
  })
  if (loading) return <LoadingState title="Loading SMS settings" />
  return (
    <section className="content-panel reminder-template-panel">
      <div className="panel-header">
        <div>
          <h2>SMS Settings</h2>
          <p>{smsEnabled ? 'Business SMS is enabled.' : 'Business SMS is paused.'}</p>
        </div>
        <StatusBadge>{senderId}</StatusBadge>
      </div>
      <label className="checkbox-line"><input type="checkbox" checked={smsEnabled} onChange={(event) => setSmsEnabled(event.target.checked)} /> SMS Enabled</label>
      <label>Sender ID<select value={senderId} onChange={(event) => setSenderId(event.target.value)}>{['MICHANGO', 'SHEREHE', 'KIKAO'].map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'SMS settings could not be saved.')}</p> : null}
      <div className="sheet-actions"><button className="primary-button" type="button" disabled={mutation.isPending} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Saving...' : 'Save Settings'}</button></div>
    </section>
  )
}

function SmsTemplateManager({ tenantId, templates, loading, onSaved }: { tenantId: string; templates: Row[]; loading: boolean; onSaved: () => void }) {
  if (loading) return <LoadingState title="Loading SMS templates" />
  return (
    <section className="content-panel reminder-template-panel">
      <div className="panel-header">
        <div>
          <h2>SMS Templates</h2>
          <p>Tenant overrides for pledge and payment messages.</p>
        </div>
        <StatusBadge>{String(templates.length)} templates</StatusBadge>
      </div>
      <div className="finance-card-list">
        {smsTemplateOptions.filter((option) => option.code !== 'ALL').map((option) => {
          const template = templates.find((row) => asString(row.code) === option.code) ?? null
          return <SmsTemplateEditorCard key={option.code} tenantId={tenantId} option={option} template={template} onSaved={onSaved} />
        })}
      </div>
    </section>
  )
}

function SmsTemplateEditorCard({ tenantId, option, template, onSaved }: { tenantId: string; option: (typeof smsTemplateOptions)[number]; template: Row | null; onSaved: () => void }) {
  const [body, setBody] = useState(asString(template?.body))
  const currentBody = body || asString(template?.body)
  const mutation = useMutation({
    mutationFn: () => api.saveSmsTemplate(tenantId, option.code, { body: currentBody, language: asString(template?.language, 'sw') }),
    onSuccess: (result) => {
      setBody(asString(result.data.body))
      onSaved()
    },
  })
  const reset = useMutation({
    mutationFn: () => api.resetSmsTemplate(tenantId, option.code),
    onSuccess: (result) => {
      setBody(asString(result.data.body))
      onSaved()
    },
  })
  return (
    <article className="content-panel">
      <div className="panel-header">
        <div>
          <h3>{option.label}</h3>
          <p>{template?.hasTenantOverride ? 'Tenant override active.' : 'Using system default.'}</p>
        </div>
        <StatusBadge>{currentBody.length} chars · {smsPartCount(currentBody)} SMS</StatusBadge>
      </div>
      <label>Template<textarea value={currentBody} onChange={(event) => setBody(event.target.value)} rows={4} /></label>
      <p className="privacy-note">{option.variables.map((variable) => `{{${variable}}}`).join(' ')}</p>
      <div className="template-preview-card"><p>{renderPreviewTemplate(currentBody)}</p></div>
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Template could not be saved.')}</p> : null}
      {reset.error ? <p className="field-error">{errorMessage(reset.error, 'Template could not be reset.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" disabled={reset.isPending} onClick={() => reset.mutate()}>Reset</button>
        <button className="primary-button" type="button" disabled={mutation.isPending || !currentBody.trim()} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Saving...' : 'Save'}</button>
      </div>
    </article>
  )
}

function RetrySmsButton({ tenantId, outboxId, onDone }: { tenantId: string; outboxId: string; onDone: () => void }) {
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const mutation = useMutation({
    mutationFn: () => api.retrySms(tenantId, outboxId, idempotencyKey),
    onSuccess: onDone,
  })
  return (
    <div className="card-actions">
      <button type="button" disabled={mutation.isPending} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : 'Retry SMS'}</button>
      {mutation.data?.data?.queued === false ? <span>{asString(mutation.data.data.reason)}</span> : null}
    </div>
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

export function TenantHelpPage() {
  const session = useSessionStore()
  const queryClient = useQueryClient()
  const tenantId = session.selectedTenantId
  const activeEvent = session.selectedTenantContext?.events[0] ?? null
  const [supportSubject, setSupportSubject] = useState('')
  const [supportDescription, setSupportDescription] = useState('')
  const [supportCategory, setSupportCategory] = useState('OTHER')
  const [feedbackMessage, setFeedbackMessage] = useState('')
  const supportQuery = useQuery({ queryKey: ['support-requests', tenantId], queryFn: async () => (await api.supportRequests(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const featuresQuery = useQuery({ queryKey: ['tenant-features', tenantId], queryFn: async () => (await api.features(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const versionQuery = useQuery({ queryKey: ['version'], queryFn: async () => (await api.version()).data })
  const supportEnabled = (featuresQuery.data ?? []).some((row) => asString(row.key) === 'support_requests' && row.enabled === true)
  const createSupport = useMutation({
    mutationFn: async () => api.createSupportRequest(tenantId ?? '', {
      category: supportCategory,
      subject: supportSubject,
      description: supportDescription,
      eventId: activeEvent?.id ?? null,
      appContext: { route: window.location.pathname, appVersion: asString(versionQuery.data?.appVersion), browser: navigator.userAgent.slice(0, 120) },
    }),
    onSuccess: () => {
      setSupportSubject('')
      setSupportDescription('')
      void queryClient.invalidateQueries({ queryKey: ['support-requests', tenantId] })
    },
  })
  const createFeedback = useMutation({
    mutationFn: async () => api.createFeedback(tenantId ?? '', {
      category: 'SUGGESTION',
      message: feedbackMessage,
      eventId: activeEvent?.id ?? null,
      page: window.location.pathname,
      appContext: { route: window.location.pathname, appVersion: asString(versionQuery.data?.appVersion) },
    }),
    onSuccess: () => setFeedbackMessage(''),
  })
  const checklist = [
    ['Tenant selected', Boolean(tenantId)],
    ['Active event ready', Boolean(activeEvent)],
    ['Members page available', Boolean(activeEvent)],
    ['Payments and reports available', Boolean(activeEvent)],
  ] as const

  if (!tenantId) return <ErrorState title="No tenant selected" message="Select a tenant before opening support." />

  return (
    <PageContainer>
      <PageHeader title="Help & Support" description="Support requests, beta feedback, app version and first-run readiness for this workspace." />
      <section className="stats-grid">
        <StatCard label="Web Version" value={asString(versionQuery.data?.webVersion, '0.9.0-beta')} meta={asString(versionQuery.data?.releaseChannel, 'BETA')} icon={CheckCircle2} />
        <StatCard label="API Version" value={asString(versionQuery.data?.apiVersion, '0.9.0-beta')} meta={`Minimum ${asString(versionQuery.data?.minimumSupportedWebVersion, 'not set')}`} icon={FileText} />
        <StatCard label="Support" value={supportEnabled ? 'Enabled' : 'Unavailable'} meta={`${supportQuery.data?.length ?? 0} requests`} icon={MessageCircle} tone={supportEnabled ? 'success' : 'warning'} />
      </section>
      <section className="help-layout">
        <article className="platform-panel">
          <div className="panel-header"><div><h2>First-Run Checklist</h2><p>Signals that make reports, reminders and records useful.</p></div></div>
          <div className="checklist-grid">
            {checklist.map(([label, done]) => <span className={done ? 'checked' : ''} key={label}>{done ? 'Done' : 'Open'} {label}</span>)}
          </div>
        </article>
        <article className="platform-panel">
          <div className="panel-header"><div><h2>Contact Support</h2><p>Create a ticket with safe app context attached.</p></div></div>
          <form className="support-form" onSubmit={(event: FormEvent) => { event.preventDefault(); createSupport.mutate() }}>
            <label>Category<select value={supportCategory} onChange={(event) => setSupportCategory(event.target.value)}>{['LOGIN', 'MEMBERS', 'PLEDGES', 'PAYMENTS', 'SMS', 'REPORTS', 'SUBSCRIPTION', 'OTHER'].map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
            <label>Subject<input value={supportSubject} onChange={(event) => setSupportSubject(event.target.value)} /></label>
            <label>Description<textarea value={supportDescription} onChange={(event) => setSupportDescription(event.target.value)} /></label>
            {createSupport.error ? <p className="field-error">{createSupport.error instanceof Error ? createSupport.error.message : 'Unable to create support request.'}</p> : null}
            <button type="submit" disabled={!supportEnabled || createSupport.isPending || supportSubject.trim().length < 3 || supportDescription.trim().length < 10}>{createSupport.isPending ? 'Sending...' : 'Send Request'}</button>
          </form>
        </article>
        <article className="platform-panel">
          <div className="panel-header"><div><h2>Beta Feedback</h2><p>Send product feedback directly to the platform team.</p></div></div>
          <form className="support-form" onSubmit={(event: FormEvent) => { event.preventDefault(); createFeedback.mutate() }}>
            <label>Feedback<textarea value={feedbackMessage} onChange={(event) => setFeedbackMessage(event.target.value)} /></label>
            {createFeedback.isSuccess ? <p className="success-note">Feedback submitted.</p> : null}
            <button type="submit" disabled={createFeedback.isPending || feedbackMessage.trim().length < 3}>{createFeedback.isPending ? 'Sending...' : 'Send Feedback'}</button>
          </form>
        </article>
        <article className="platform-panel">
          <div className="panel-header"><div><h2>Recent Requests</h2><p>Your latest support tickets.</p></div></div>
          <div className="messages-list">
            {(supportQuery.data ?? []).map((request) => (
              <section className="message-history-card" key={asString(request.id)}>
                <strong>{asString(request.ticket_number)} · {asString(request.subject)}</strong>
                <span>{asString(request.category)} · {asString(request.status)} · {asString(request.created_at).slice(0, 10)}</span>
              </section>
            ))}
            {supportQuery.isLoading ? <LoadingState title="Loading requests" /> : null}
            {!supportQuery.isLoading && !(supportQuery.data ?? []).length ? <EmptyState title="No support requests yet" message="New tickets will appear here after you submit them." /> : null}
          </div>
        </article>
      </section>
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
      <section className="stats-grid settings-overview">
        <StatCard label="Tenant" value={asString(organization.name, 'Tenant')} meta={asString(organization.code, 'No code')} icon={Users} />
        <StatCard label="Package" value={asString(subscription.planName, 'Not set')} meta={asString(subscription.status, 'No status')} icon={FileText} />
        <StatCard label="Event Slots" value={`${displayValue(limits.usedEventSlots, '0')}/${displayValue(limits.maxEventSlots, '0')}`} meta={`${displayValue(limits.availableEventSlots, '0')} available`} icon={CalendarDays} />
        <StatCard label="SMS" value={notifications.paymentConfirmations ? 'Enabled' : 'Disabled'} meta={asString(notifications.smsSenderName, 'No sender')} icon={MessageCircle} tone={notifications.paymentConfirmations ? 'success' : 'warning'} />
      </section>
      <section className="settings-grid">
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

function rows(value: unknown): Row[] {
  return Array.isArray(value) ? value.map(jsonRecord) : []
}

function invoicePayable(invoice: Row) {
  return !['PAID', 'VOID'].includes(asString(invoice.status)) && asNumber(invoice.amount_due ?? invoice.amountDue) > 0
}

export function TenantBillingPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const billing = useQuery({ queryKey: ['tenant-billing-summary', tenantId], queryFn: async () => (await api.billingSummary(tenantId ?? '')).data, enabled: Boolean(tenantId) })

  if (!tenantId) return <ErrorState title="Unable to load billing" message="Select a tenant first." />
  if (billing.isLoading) return <LoadingState title="Loading billing" message="Fetching subscription invoices and gateway status." />
  if (billing.isError || !billing.data) return <ErrorState title="Unable to load billing" message={errorMessage(billing.error, 'Billing could not be loaded.')} />

  const subscription = jsonRecord(billing.data.subscription)
  const invoices = rows(billing.data.invoices)
  const payments = rows(billing.data.payments)
  const pendingIntents = rows(billing.data.pendingIntents)
  const payableInvoices = invoices.filter(invoicePayable)

  return (
    <PageContainer>
      <PageHeader title="Billing" description="Ahadi subscription invoices, verified payments and pending gateway attempts." action={<Link to="/app/settings">Settings</Link>} />
      <section className="stats-grid">
        <StatCard label="Package" value={asString(subscription.planName, 'Not set')} meta={asString(subscription.status, 'No status')} icon={FileText} />
        <StatCard label="Open Balance" value={moneyText(payableInvoices.reduce((sum, invoice) => sum + asNumber(invoice.amount_due ?? invoice.amountDue), 0))} meta={`${payableInvoices.length} payable invoices`} icon={CreditCard} tone={payableInvoices.length ? 'warning' : 'success'} />
        <StatCard label="Verified Payments" value={String(payments.length)} meta={`${pendingIntents.length} pending attempts`} icon={CheckCircle2} />
      </section>
      <section className="finance-card-list">
        {invoices.map((invoice) => (
          <article className="finance-card" key={asString(invoice.id)}>
            <div className="card-title-row">
              <div><strong>{asString(invoice.invoice_number ?? invoice.invoiceNumber, 'Invoice')}</strong><span>Due {asDate(invoice.due_date ?? invoice.dueDate)} · {asString(invoice.purpose, 'MANUAL')}</span></div>
              <StatusBadge tone={statusTone(invoice.status)}>{asString(invoice.status, 'ISSUED')}</StatusBadge>
            </div>
            <div className="amount-triplet">
              <span><small>Total</small>{moneyText(invoice.total_amount ?? invoice.totalAmount)}</span>
              <span><small>Paid</small>{moneyText(invoice.amount_paid ?? invoice.amountPaid)}</span>
              <span><small>Balance</small>{moneyText(invoice.amount_due ?? invoice.amountDue)}</span>
            </div>
            <div className="card-actions">
              <Link to={`/app/settings/billing/invoices/${asString(invoice.id)}`}>{invoicePayable(invoice) ? 'Pay Now' : 'View Invoice'}</Link>
            </div>
          </article>
        ))}
        {!invoices.length ? <EmptyState title="No subscription invoices yet" message="Invoices will appear here when a plan renewal or conversion is issued." /> : null}
      </section>
    </PageContainer>
  )
}

export function TenantBillingInvoicePage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const { invoiceId } = useParams()
  const queryClient = useQueryClient()
  const [provider, setProvider] = useState('TEST')
  const [paymentMethod, setPaymentMethod] = useState('MOBILE_MONEY')
  const [activeIntentId, setActiveIntentId] = useState('')
  const [paymentIntentIdempotencyKey, resetPaymentIntentIdempotencyKey] = useState(() => crypto.randomUUID())
  const invoice = useQuery({ queryKey: ['tenant-billing-invoice', tenantId, invoiceId], queryFn: async () => (await api.billingInvoice(tenantId ?? '', invoiceId ?? '')).data, enabled: Boolean(tenantId && invoiceId) })
  const billing = useQuery({ queryKey: ['tenant-billing-summary', tenantId], queryFn: async () => (await api.billingSummary(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const intent = useQuery({
    queryKey: ['subscription-payment-intent', tenantId, activeIntentId],
    queryFn: async () => (await api.subscriptionPaymentIntent(tenantId ?? '', activeIntentId)).data,
    enabled: Boolean(tenantId && activeIntentId),
    refetchInterval: (query) => ['PENDING', 'PROCESSING', 'CREATED'].includes(asString(query.state.data?.status)) ? 7000 : false,
  })
  const createIntent = useMutation({
    mutationFn: async () => api.createSubscriptionPaymentIntent(tenantId ?? '', invoiceId ?? '', {
      provider,
      paymentMethod,
      idempotencyKey: paymentIntentIdempotencyKey,
      returnUrl: window.location.href,
    }),
    onSuccess: (result) => {
      const id = asString(result.data.id)
      setActiveIntentId(id)
      void queryClient.invalidateQueries({ queryKey: ['tenant-billing-summary', tenantId] })
      void queryClient.invalidateQueries({ queryKey: ['tenant-billing-invoice', tenantId, invoiceId] })
      resetPaymentIntentIdempotencyKey(crypto.randomUUID())
    },
  })

  if (!tenantId || !invoiceId) return <ErrorState title="Unable to load invoice" message="Select a tenant invoice first." />
  if (invoice.isLoading || billing.isLoading) return <LoadingState title="Loading invoice" message="Fetching invoice balance and payment gateway options." />
  if (invoice.isError || !invoice.data) return <ErrorState title="Unable to load invoice" message={errorMessage(invoice.error, 'Invoice could not be loaded.')} />

  const data = invoice.data
  const gateways = rows(billing.data?.gateways).filter((gateway) => gateway.enabled === true)
  const existingPending = rows(billing.data?.pendingIntents).find((item) => asString(item.invoice_id ?? item.invoiceId) === invoiceId)
  const activeIntent = intent.data ?? (activeIntentId ? null : existingPending ?? null)
  const items = rows(data.subscription_invoice_items)
  const payable = invoicePayable(data)

  return (
    <PageContainer>
      <PageHeader title={asString(data.invoice_number ?? data.invoiceNumber, 'Invoice')} description="Subscription invoice payment is confirmed only after a verified gateway callback." action={<Link to="/app/settings/billing"><ArrowLeft size={16} aria-hidden /> Billing</Link>} />
      <section className="stats-grid">
        <StatCard label="Total" value={moneyText(data.total_amount ?? data.totalAmount)} icon={FileText} />
        <StatCard label="Paid" value={moneyText(data.amount_paid ?? data.amountPaid)} icon={CheckCircle2} tone="success" />
        <StatCard label="Balance" value={moneyText(data.amount_due ?? data.amountDue)} icon={CreditCard} tone={payable ? 'warning' : 'success'} />
        <StatCard label="Due Date" value={asDate(data.due_date ?? data.dueDate)} meta={asString(data.purpose, 'MANUAL')} icon={CalendarDays} />
      </section>
      <section className="form-layout">
        <article className="content-panel">
          <div className="panel-header"><div><h2>Invoice</h2><p>{asString(data.currency, 'TZS')} · {asString(data.status, 'ISSUED')}</p></div><StatusBadge tone={statusTone(data.status)}>{asString(data.status, 'ISSUED')}</StatusBadge></div>
          {items.length ? items.map((item) => <ReviewLine key={asString(item.id, asString(item.description))} label={asString(item.description, 'Line item')} value={moneyText(item.total_amount ?? item.totalAmount)} />) : <ReviewLine label="Invoice amount" value={moneyText(data.total_amount ?? data.totalAmount)} />}
          <ReviewLine label="Issued" value={asDate(data.issued_at ?? data.issuedAt)} />
          <ReviewLine label="Paid at" value={data.paid_at ? asDateTime(data.paid_at) : 'Not paid'} />
        </article>
        <article className="content-panel">
          <div className="panel-header"><div><h2>Pay Invoice</h2><p>{payable ? `Pay ${moneyText(data.amount_due ?? data.amountDue)}` : 'No balance is due.'}</p></div></div>
          {payable && !activeIntent ? (
            <div className="support-form">
              <label>Gateway<select value={provider} onChange={(event) => setProvider(event.target.value)}>{gateways.map((gateway) => <option key={asString(gateway.provider)} value={asString(gateway.provider)}>{asString(gateway.provider)} · {asString(gateway.referenceMode)}</option>)}</select></label>
              <label>Payment method<select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)}>{['MOBILE_MONEY', 'CONTROL_NUMBER'].map((method) => <option key={method} value={method}>{method.replace('_', ' ')}</option>)}</select></label>
              {createIntent.error ? <p className="field-error">{errorMessage(createIntent.error, 'Payment attempt could not be created.')}</p> : null}
              <button type="button" disabled={!gateways.length || createIntent.isPending} onClick={() => createIntent.mutate()}>{createIntent.isPending ? 'Creating...' : 'Pay Now'}</button>
              {!gateways.length ? <p className="privacy-note">No subscription payment gateway is currently enabled.</p> : null}
            </div>
          ) : null}
          {activeIntent ? <PaymentIntentPanel intent={jsonRecord(activeIntent)} refresh={() => void intent.refetch()} loading={intent.isFetching} /> : null}
          {!payable ? <p className="success-note">This invoice has no payable balance.</p> : null}
        </article>
      </section>
    </PageContainer>
  )
}

function PaymentIntentPanel({ intent, refresh, loading }: { intent: Row; refresh: () => void; loading: boolean }) {
  const status = asString(intent.status, 'PENDING')
  const controlNumber = asString(intent.controlNumber ?? intent.control_number)
  const checkoutUrl = asString(intent.checkoutUrl ?? intent.checkout_url)
  return (
    <div className="payment-instruction-card">
      <div className="card-title-row">
        <div><strong>{status === 'SUCCEEDED' ? 'Payment Received' : 'Waiting for Payment'}</strong><span>{asString(intent.provider)} · {moneyText(intent.amount ?? intent.requested_amount)}</span></div>
        <StatusBadge tone={statusTone(status)}>{status}</StatusBadge>
      </div>
      {controlNumber ? <ReviewLine label="Control number" value={controlNumber} /> : null}
      {asString(intent.paymentInstructions) ? <p className="privacy-note">{asString(intent.paymentInstructions)}</p> : null}
      {checkoutUrl ? <a className="primary-button inline-action" href={checkoutUrl} rel="noreferrer">Open Checkout</a> : null}
      <ReviewLine label="Invoice status" value={asString(intent.invoiceStatus, 'ISSUED')} />
      <ReviewLine label="Expires" value={asDateTime(intent.expiresAt ?? intent.expires_at)} />
      <div className="sheet-actions">
        {controlNumber ? <button type="button" onClick={() => void copyPlainText(controlNumber)}><Copy size={16} aria-hidden /> Copy Number</button> : null}
        <button type="button" disabled={loading || ['SUCCEEDED', 'FAILED', 'EXPIRED', 'CANCELLED'].includes(status)} onClick={refresh}>{loading ? 'Checking...' : 'Check Status'}</button>
      </div>
    </div>
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
  const params = useParams()
  const routeReportType = asString(params.reportType)
  const events = session.selectedTenantContext?.events ?? []
  const event = params.eventId ? events.find((candidate) => candidate.id === params.eventId) ?? null : events[0] ?? null
  const tenantId = session.selectedTenantId
  const [selectedEventId, setSelectedEventId] = useState(event?.id ?? '')
  const activeEventId = params.eventId ?? selectedEventId
  const activeEvent = events.find((candidate) => candidate.id === activeEventId) ?? event

  if (!tenantId || !activeEvent) return <ErrorState title="Unable to load reports" message="Open a tenant with an accessible event first." />
  if (routeReportType) {
    return <ReportDetailPage tenantId={tenantId} eventId={activeEvent.id} eventName={activeEvent.name} reportType={routeReportType} />
  }

  return (
    <PageContainer>
      <PageHeader title="Reports" description={`Server-calculated reports for ${activeEvent.name}.`} />
      {events.length > 1 ? (
        <section className="filter-bar">
          <label>Event<select value={activeEvent.id} onChange={(event) => setSelectedEventId(event.target.value)}>{events.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
        </section>
      ) : null}
      <section className="cards-list">
        {reportCards.map((report) => (
          <Link className="summary-card" key={report.type} to={`/app/events/${activeEvent.id}/reports/${report.type}`}>
            <FileText size={20} aria-hidden />
            <div>
              <strong>{report.title}</strong>
              <span>{report.description}</span>
            </div>
            <StatusBadge>Open</StatusBadge>
          </Link>
        ))}
      </section>
    </PageContainer>
  )
}

function reportTitle(type: string) {
  return reportCards.find((report) => report.type === type)?.title ?? 'Report'
}

function emptyReportMessage(type: string) {
  if (type === 'pledges') return 'No pledges match the selected filters.'
  if (type === 'payments') return 'No payments were found for this period.'
  if (type === 'outstanding') return 'All recorded pledges are fully paid.'
  if (type === 'member-statement') return 'No member transactions are available.'
  return 'No report rows are available.'
}

function downloadReportBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1_000)
}

function openPrintableReport(blob: Blob) {
  const url = URL.createObjectURL(blob)
  const printWindow = window.open(url, '_blank', 'noopener,noreferrer')
  if (printWindow) {
    setTimeout(() => printWindow.print(), 700)
  }
  setTimeout(() => URL.revokeObjectURL(url), 30_000)
}

async function shareReportFile(exported: { blob: Blob; contentType: string; filename: string }) {
  const file = new File([exported.blob], exported.filename, { type: exported.contentType })
  const nav = navigator as Navigator & { canShare?: (data: ShareData) => boolean }
  if (nav.canShare?.({ files: [file] }) && navigator.share) {
    await navigator.share({ files: [file], title: exported.filename })
    return
  }
  downloadReportBlob(exported.blob, exported.filename)
}

function ExportReportSheet({ reportType, rowCount, filterCount, formats, canExport, pendingFormat, isPending, error, lastExport, onExport, onClose }: { reportType: string; rowCount: number; filterCount: number; formats: Array<'CSV' | 'XLSX' | 'PDF' | 'PRINT'>; canExport: boolean; pendingFormat: 'CSV' | 'XLSX' | 'PDF' | 'PRINT' | null; isPending: boolean; error: unknown; lastExport: { blob: Blob; contentType: string; filename: string } | null; onExport: (format: 'CSV' | 'XLSX' | 'PDF' | 'PRINT') => void; onClose: () => void }) {
  return (
    <section className="mobile-sheet export-sheet">
      <div className="panel-header">
        <div>
          <h2>Export Report</h2>
          <p>{reportTitle(reportType)} · {rowCount} rows · {filterCount} filters applied</p>
        </div>
        <button type="button" onClick={onClose}>Close</button>
      </div>
      {!canExport ? <ErrorState title="Export not allowed" message="Your role can view this report but cannot export it." /> : null}
      {canExport ? <div className="export-format-grid">{formats.map((format) => <button key={format} type="button" disabled={isPending} onClick={() => onExport(format)}>{format === 'PRINT' ? <Printer size={18} aria-hidden /> : <FileText size={18} aria-hidden />}{isPending && pendingFormat === format ? 'Preparing report...' : formatLabel(format)}</button>)}</div> : null}
      {error ? <ErrorState title="Export failed" message={errorMessage(error, 'Report export could not be prepared.')} /> : null}
      {lastExport ? <div className="sheet-actions"><span>Report ready</span><button type="button" onClick={() => downloadReportBlob(lastExport.blob, lastExport.filename)}>Download</button>{lastExport.contentType.includes('pdf') ? <button className="primary-button" type="button" onClick={() => void shareReportFile(lastExport)}>Share</button> : null}</div> : null}
    </section>
  )
}

function formatLabel(format: string) {
  if (format === 'XLSX') return 'Excel'
  if (format === 'CSV') return 'CSV'
  if (format === 'PDF') return 'PDF'
  return 'Print'
}

function ReportDetailPage({ tenantId, eventId, eventName, reportType }: { tenantId: string; eventId: string; eventName: string; reportType: string }) {
  const [draft, setDraft] = useState({ search: '', status: 'ALL', filter: 'ALL', paymentMethod: 'ALL', dateFrom: '', dateTo: '', dueFrom: '', dueTo: '', category: '', sort: reportType === 'pledges' ? 'MEMBER' : reportType === 'outstanding' ? 'OUTSTANDING' : 'DATE', direction: reportType === 'pledges' ? 'ASC' : 'DESC', pageSize: '25', eventMemberId: '' })
  const [filters, setFilters] = useState(draft)
  const [page, setPage] = useState(1)
  const [exportOpen, setExportOpen] = useState(false)
  const [lastExport, setLastExport] = useState<{ blob: Blob; contentType: string; filename: string } | null>(null)
  const reportTenantContext = useSessionStore().selectedTenantContext
  const permissions = new Set(reportTenantContext?.permissions ?? [])
  const payload = {
    ...filters,
    page,
    pageSize: Number(filters.pageSize),
    category: filters.category || null,
    dateFrom: filters.dateFrom || null,
    dateTo: filters.dateTo || null,
    dueFrom: filters.dueFrom || null,
    dueTo: filters.dueTo || null,
    eventMemberId: filters.eventMemberId || null,
  }
  const report = useQuery({ queryKey: ['event-report', tenantId, eventId, reportType, payload], queryFn: async () => (await api.eventReport(tenantId, eventId, reportType, payload)).data, enabled: Boolean(tenantId && eventId && reportType) })
  const rows = Array.isArray(report.data?.data) ? report.data.data.map(jsonRecord) : []
  const summary = jsonRecord(report.data?.summary)
  const pagination = jsonRecord(report.data?.pagination)
  const members = Array.isArray(report.data?.members) ? report.data.members.map(jsonRecord) : []
  const filterCount = Object.entries(filters).filter(([key, value]) => !['pageSize', 'sort', 'direction'].includes(key) && value && value !== 'ALL').length
  const totalRows = asNumber(pagination.totalRows) || rows.length
  const exportMutation = useMutation({
    mutationFn: async (format: 'CSV' | 'XLSX' | 'PDF' | 'PRINT') => api.exportEventReport(tenantId, eventId, reportType, { format, filters: payload, sort: { field: filters.sort, direction: filters.direction } }, reportType === 'member-statement' && payload.eventMemberId ? asString(payload.eventMemberId) : undefined),
    onSuccess: async (result) => {
      setLastExport({ blob: result.blob, contentType: result.contentType, filename: result.filename })
      if (result.contentType.includes('text/html')) {
        openPrintableReport(result.blob)
        return
      }
      downloadReportBlob(result.blob, result.filename)
    },
  })

  function applyFilters(event: FormEvent) {
    event.preventDefault()
    setPage(1)
    setFilters(draft)
  }

  return (
    <PageContainer>
      <PageHeader title={reportTitle(reportType)} description={`${eventName} report`} action={<div className="inline-actions"><Link to={`/app/events/${eventId}/reports`}><ArrowLeft size={18} aria-hidden /> Reports</Link><button type="button" onClick={() => setExportOpen((value) => !value)}><Share2 size={18} aria-hidden /> Export</button></div>} />
      {exportOpen ? <ExportReportSheet reportType={reportType} rowCount={totalRows} filterCount={filterCount} canExport={permissions.has('reports.export') || Boolean(reportTenantContext?.membership?.isOwner)} formats={reportExportFormats[reportType] ?? ['PDF', 'PRINT']} pendingFormat={exportMutation.variables ?? null} isPending={exportMutation.isPending} error={exportMutation.error} lastExport={lastExport} onClose={() => setExportOpen(false)} onExport={(format) => exportMutation.mutate(format)} /> : null}
      <form className="filter-bar" onSubmit={applyFilters}>
        {reportType === 'member-statement' ? <label>Member<select value={draft.eventMemberId} onChange={(event) => setDraft((current) => ({ ...current, eventMemberId: event.target.value }))}><option value="">First matching member</option>{members.map((member) => <option key={asString(member.eventMemberId)} value={asString(member.eventMemberId)}>{asString(member.name)} · {asString(member.memberCode)}</option>)}</select></label> : null}
        <label>Search<input type="search" value={draft.search} onChange={(event) => setDraft((current) => ({ ...current, search: event.target.value }))} placeholder="Member, receipt or payment" /></label>
        {['pledges', 'payments'].includes(reportType) ? <label>Status<select value={draft.status} onChange={(event) => setDraft((current) => ({ ...current, status: event.target.value }))}>{['ALL', 'PENDING', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CONFIRMED', 'REVERSED', 'CANCELLED'].map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label> : null}
        {reportType === 'outstanding' ? <label>Filter<select value={draft.filter} onChange={(event) => setDraft((current) => ({ ...current, filter: event.target.value }))}>{['ALL', 'OVERDUE', 'DUE_SOON', 'PARTIAL', 'UNPAID'].map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label> : null}
        {['pledges', 'outstanding'].includes(reportType) ? <label>Category<input value={draft.category} onChange={(event) => setDraft((current) => ({ ...current, category: event.target.value }))} /></label> : null}
        {reportType === 'payments' ? <label>Method<select value={draft.paymentMethod} onChange={(event) => setDraft((current) => ({ ...current, paymentMethod: event.target.value }))}>{['ALL', ...paymentMethods].map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label> : null}
        {['payments', 'collectors'].includes(reportType) ? <><label>From<input type="date" value={draft.dateFrom} onChange={(event) => setDraft((current) => ({ ...current, dateFrom: event.target.value }))} /></label><label>To<input type="date" value={draft.dateTo} onChange={(event) => setDraft((current) => ({ ...current, dateTo: event.target.value }))} /></label></> : null}
        {reportType === 'pledges' ? <><label>Due From<input type="date" value={draft.dueFrom} onChange={(event) => setDraft((current) => ({ ...current, dueFrom: event.target.value }))} /></label><label>Due To<input type="date" value={draft.dueTo} onChange={(event) => setDraft((current) => ({ ...current, dueTo: event.target.value }))} /></label></> : null}
        {['pledges', 'payments', 'outstanding'].includes(reportType) ? <label>Sort<select value={draft.sort} onChange={(event) => setDraft((current) => ({ ...current, sort: event.target.value }))}>{reportSortOptions(reportType).map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label> : null}
        <label>Rows<select value={draft.pageSize} onChange={(event) => setDraft((current) => ({ ...current, pageSize: event.target.value }))}>{['25', '50', '100'].map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
        <button type="button" onClick={() => { const reset = { ...draft, search: '', status: 'ALL', filter: 'ALL', paymentMethod: 'ALL', dateFrom: '', dateTo: '', dueFrom: '', dueTo: '', category: '', eventMemberId: '' }; setDraft(reset); setFilters(reset); setPage(1) }}>Clear Filters</button>
        <button className="primary-button" type="submit">Apply {filterCount ? `(${filterCount})` : ''}</button>
      </form>
      {report.isLoading ? <LoadingState title="Loading report" message="Calculating server-side report data." /> : null}
      {report.isError ? <ErrorState title="Unable to load report" message={errorMessage(report.error, 'Report could not be loaded.')} /> : null}
      {!report.isLoading && !report.isError ? <ReportSummaryCards reportType={reportType} summary={summary} /> : null}
      {!report.isLoading && !report.isError && rows.length ? <section className="finance-card-list">{rows.map((row, index) => <ReportRowCard key={`${reportType}-${index}-${asString(row.id ?? row.paymentId ?? row.pledgeId ?? row.date)}`} reportType={reportType} row={row} summary={summary} />)}</section> : null}
      {!report.isLoading && !report.isError && !rows.length ? <EmptyState title={emptyReportMessage(reportType)} message="Adjust the report filters or add financial records to this event." /> : null}
      {!report.isLoading && !report.isError && asNumber(pagination.totalPages) > 1 ? <div className="sheet-actions"><button type="button" disabled={page <= 1} onClick={() => setPage((value) => Math.max(1, value - 1))}>Previous</button><span>Page {page} of {asNumber(pagination.totalPages)}</span><button type="button" disabled={page >= asNumber(pagination.totalPages)} onClick={() => setPage((value) => value + 1)}>Next</button></div> : null}
    </PageContainer>
  )
}

function reportSortOptions(reportType: string) {
  if (reportType === 'pledges') return ['MEMBER', 'PLEDGED', 'PAID', 'OUTSTANDING', 'DUE_DATE']
  if (reportType === 'payments') return ['DATE', 'AMOUNT', 'MEMBER']
  if (reportType === 'outstanding') return ['OUTSTANDING', 'DAYS_OVERDUE', 'DUE_DATE', 'MEMBER']
  return ['DATE']
}

function ReportSummaryCards({ reportType, summary }: { reportType: string; summary: Row }) {
  const entries: Array<[string, unknown]> = reportType === 'summary'
    ? [['Event Target', summary.eventTarget], ['Total Pledged', summary.totalPledged], ['Collected', summary.totalReceived], ['Allocated', summary.totalAllocatedToPledges], ['Unallocated', summary.totalUnallocated], ['Outstanding', summary.totalOutstanding], ['Collection Rate', `${asNumber(summary.collectionRate)}%`], ['Coverage', `${asNumber(summary.pledgeCoverageAgainstTarget)}%`], ['Members', summary.memberCount], ['With Pledges', summary.membersWithPledges], ['Without Pledges', summary.membersWithoutPledges], ['Fully Paid', summary.fullyPaidCount], ['Partial', summary.partiallyPaidCount], ['Unpaid', summary.unpaidCount], ['Overdue', summary.overdueCount]]
    : Object.entries(summary).slice(0, 6)
  return <section className="stats-grid">{entries.map(([label, value]) => <StatCard key={label} label={label} value={typeof value === 'number' || String(label).toLowerCase().includes('amount') || String(label).toLowerCase().includes('total') || ['Pledged', 'Collected', 'Allocated', 'Unallocated', 'Outstanding', 'Net Confirmed'].some((word) => String(label).includes(word)) ? moneyText(value) : displayValue(value)} icon={FileText} />)}</section>
}

function ReportRowCard({ reportType, row, summary }: { reportType: string; row: Row; summary: Row }) {
  if (reportType === 'summary') {
    return <article className="finance-card">{Object.entries(row).map(([key, value]) => <ReviewLine key={key} label={key} value={displayValue(value)} />)}</article>
  }
  if (reportType === 'member-statement') {
    const member = jsonRecord(summary.member)
    const pledge = jsonRecord(summary.pledge)
    return <article className="finance-card"><div className="card-title-row"><div><strong>{asString(member.name, 'Member Statement')}</strong><span>{asString(member.memberCode)} · {asString(member.phone, 'No phone')}</span></div><StatusBadge>{asString(row.status, asString(pledge.status))}</StatusBadge></div><ReviewLine label="Date" value={asDateTime(row.date)} /><ReviewLine label="Type" value={displayValue(row.type)} /><ReviewLine label="Receipt" value={displayValue(row.receipt)} /><ReviewLine label="Method" value={displayValue(row.method)} /><ReviewLine label="Amount" value={moneyText(row.amount)} /></article>
  }
  const title = asString(row.member ?? row.collectorName ?? row.paymentMethod ?? row.eventName, reportTitle(reportType))
  return <article className="finance-card"><div className="card-title-row"><div><strong>{title}</strong><span>{asString(row.memberCode ?? row.paymentNumber ?? row.receiptNumber ?? row.category, '')}</span></div><StatusBadge tone={statusTone(row.status)}>{asString(row.status ?? row.paymentMethod, 'Report')}</StatusBadge></div><div className="amount-triplet">{Object.entries(row).filter(([key]) => ['pledged', 'paid', 'outstanding', 'amount', 'allocatedAmount', 'unallocatedAmount', 'netConfirmedAmount', 'grossAmount', 'reversedAmount', 'netCollected', 'grossRecorded'].includes(key)).slice(0, 3).map(([key, value]) => <span key={key}><small>{key.replace(/([A-Z])/g, ' $1')}</small>{moneyText(value)}</span>)}</div>{Object.entries(row).filter(([key]) => !['pledgeId', 'paymentId', 'eventMemberId', 'memberId', 'collectorId'].includes(key)).slice(0, 8).map(([key, value]) => <ReviewLine key={key} label={key.replace(/([A-Z])/g, ' $1')} value={key.toLowerCase().includes('date') || key.toLowerCase().includes('payment') && String(value).includes('T') ? asDateTime(value) : displayValue(value)} />)}</article>
}

function Input({ label, value, onChange, inputMode, type = 'text' }: { label: string; value: string; onChange: (value: string) => void; inputMode?: 'decimal' | 'tel'; type?: string }) {
  return <label>{label}<input inputMode={inputMode} type={type} value={value} onChange={(event) => onChange(event.target.value)} /></label>
}

function ReviewLine({ label, value }: { label: string; value: string }) {
  return <div className="review-line"><span>{label}</span><strong>{value}</strong></div>
}
