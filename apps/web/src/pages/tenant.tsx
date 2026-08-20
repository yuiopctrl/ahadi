import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  Clock3,
  Copy,
  CreditCard,
  FileText,
  KeyRound,
  MessageCircle,
  Pencil,
  Plus,
  Printer,
  Search,
  Send,
  Share2,
  Users,
} from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import type { FormEvent, ReactNode } from 'react'
import { Link, NavLink, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import type { EventSummary, SubscriptionPlan } from '@ahadi/types'
import { PinEntry, canSubmitPin } from '../components/pin-entry'
import { DataTable, EmptyState, ErrorState, LoadingState, MoneyDisplay, PageContainer, PageHeader, SearchInput, StatCard, StatusBadge } from '../components/ui'
import type { DataTableColumn } from '../components/ui'
import { api, ApiClientError } from '../lib/api'
import { useSessionStore } from '../stores/session-store'

type EventSection = 'overview' | 'members' | 'pledges' | 'payments' | 'messages'
type Row = Record<string, unknown>

const paymentMethods = ['CASH', 'M_PESA', 'AIRTEL_MONEY', 'MIX_BY_YAS', 'HALOPESA', 'BANK_TRANSFER', 'CHEQUE', 'OTHER']
const recordPaymentRowsPerPage = 5
const recordPaymentSearchMinLength = 3
const recordPaymentSearchDebounceMs = 300
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
type WhatsappSummaryRow = {
  label: string
  valueSource: string
  visible: boolean
  order: number
}
type WhatsappAlamaLabels = {
  completed: string
  partial: string
  noPledge: string
}
const defaultWhatsappSummaryRows: WhatsappSummaryRow[] = [
  { label: 'Jumla ya Ahadi', valueSource: 'TOTAL_PLEDGED', visible: true, order: 1 },
  { label: 'Jumla CASH', valueSource: 'CASH_RECEIVED', visible: true, order: 2 },
]
const defaultWhatsappAlamaLabels: WhatsappAlamaLabels = {
  completed: 'Amemaliza',
  partial: 'Amepunguza',
  noPledge: 'Hajatoa Ahadi',
}
const defaultWhatsappSummarySources = [
  { valueSource: 'TOTAL_PLEDGED', label: 'Total Pledged' },
  { valueSource: 'TOTAL_RECEIVED', label: 'Total Received' },
  { valueSource: 'TOTAL_OUTSTANDING', label: 'Outstanding' },
  { valueSource: 'CASH_RECEIVED', label: 'Cash Received' },
  { valueSource: 'MOBILE_MONEY_RECEIVED', label: 'Mobile Money Received' },
  { valueSource: 'M_PESA_RECEIVED', label: 'M-Pesa Received' },
  { valueSource: 'AIRTEL_MONEY_RECEIVED', label: 'Airtel Money Received' },
  { valueSource: 'MIX_BY_YAS_RECEIVED', label: 'Mix by Yas Received' },
  { valueSource: 'HALOPESA_RECEIVED', label: 'HaloPesa Received' },
  { valueSource: 'BANK_RECEIVED', label: 'Bank Received' },
  { valueSource: 'CHEQUE_RECEIVED', label: 'Cheque Received' },
  { valueSource: 'OTHER_RECEIVED', label: 'Other Received' },
]
const eventTypes = ['WEDDING', 'SENDOFF', 'FUNERAL', 'FUNDRAISER', 'BIRTHDAY', 'GRADUATION', 'RELIGIOUS', 'OTHER']
const tenantRoleOptions = [
  { value: 'EVENT_ADMIN', label: 'Event Admin' },
  { value: 'TREASURER', label: 'Treasurer' },
  { value: 'COLLECTOR', label: 'Collector' },
  { value: 'VIEWER', label: 'Viewer' },
  { value: 'TENANT_OWNER', label: 'Owner' },
]
const tenantRoleLabels: Record<string, string> = {
  TENANT_OWNER: 'Owner',
  EVENT_ADMIN: 'Event Admin',
  TREASURER: 'Treasurer',
  COLLECTOR: 'Collector',
  VIEWER: 'Viewer',
}
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

function titleCaseMemberName(value: unknown, fallback = 'Member') {
  const name = asString(value, fallback).trim().replace(/\s+/g, ' ')
  return name.toLocaleLowerCase('en-TZ').replace(/(^|[\s'-])\p{L}/gu, (match) => match.toLocaleUpperCase('en-TZ'))
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

function roleLabel(value: unknown) {
  return tenantRoleLabels[asString(value)] ?? asString(value, 'No role')
}

function userRoles(value: unknown) {
  return Array.isArray(value) ? value.map(String).filter(Boolean) : []
}

function userRoleText(value: unknown) {
  const roles = userRoles(value)
  return roles.length ? roles.map(roleLabel).join(', ') : 'No role'
}

function tenantUserStatusLabel(value: unknown) {
  const status = asString(value, 'ACTIVE')
  if (status === 'INVITED') return 'Invited'
  if (status === 'SUSPENDED') return 'Suspended'
  if (status === 'REMOVED') return 'Removed'
  return status === 'ACTIVE' ? 'Active' : titleCaseMemberName(status, 'Inactive')
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

function billingIntervalText(value: unknown) {
  return asString(value, 'CUSTOM').toLowerCase().replaceAll('_', ' ')
}

function activeEventLimitLabel(value: unknown) {
  const limit = asNumber(value)
  if (limit <= 0) return 'No active events'
  return limit === 1 ? '1 active event' : `${limit} active events`
}

function usageNumber(row: Row, keys: string[]) {
  for (const key of keys) {
    const value = row[key]
    if (value !== undefined && value !== null && value !== '') return asNumber(value)
  }
  return 0
}

function normalizePlanRow(row: Row): SubscriptionPlan {
  return {
    id: asString(row.id),
    code: asString(row.code),
    name: asString(row.name, asString(row.code, 'Package')),
    description: asString(row.description),
    currency: asString(row.currency, 'TZS'),
    priceAmount: asNumber(row.priceAmount ?? row.price_amount),
    billingInterval: asString(row.billingInterval ?? row.billing_interval, 'CUSTOM') as SubscriptionPlan['billingInterval'],
    trialDays: asNumber(row.trialDays ?? row.trial_days),
    maxActiveEvents: asNumber(row.maxActiveEvents ?? row.max_active_events),
    maxMembers: asNumber(row.maxMembers ?? row.max_members),
    maxUsers: asNumber(row.maxUsers ?? row.max_users),
    includedSms: asNumber(row.includedSms ?? row.included_sms),
    features: jsonRecord(row.features),
    isPublic: row.isPublic !== false && row.is_public !== false,
    isActive: row.isActive !== false && row.is_active !== false,
    displayOrder: asNumber(row.displayOrder ?? row.display_order),
  }
}

function normalizeWhatsappSummaryRows(value: unknown): WhatsappSummaryRow[] {
  if (!Array.isArray(value)) return defaultWhatsappSummaryRows
  const rows = value.map((row, index) => {
    const record = jsonRecord(row)
    return {
      label: asString(record.label, defaultWhatsappSummaryRows[index]?.label ?? 'Muhtasari'),
      valueSource: asString(record.valueSource, defaultWhatsappSummaryRows[index]?.valueSource ?? 'TOTAL_PLEDGED'),
      visible: record.visible !== false,
      order: asNumber(record.order) || index + 1,
    }
  }).filter((row) => row.label && row.valueSource)
  return rows.length ? rows.sort((left, right) => left.order - right.order).map((row, index) => ({ ...row, order: index + 1 })) : defaultWhatsappSummaryRows
}

function normalizeWhatsappSummarySources(value: unknown) {
  if (!Array.isArray(value)) return defaultWhatsappSummarySources
  const sources = value.map((source) => {
    const record = jsonRecord(source)
    return {
      valueSource: asString(record.valueSource),
      label: asString(record.label, asString(record.valueSource)),
    }
  }).filter((source) => source.valueSource)
  return sources.length ? sources : defaultWhatsappSummarySources
}

function normalizeWhatsappAlamaLabels(value: unknown): WhatsappAlamaLabels {
  const record = jsonRecord(value)
  return {
    completed: asString(record.completed, defaultWhatsappAlamaLabels.completed),
    partial: asString(record.partial, defaultWhatsappAlamaLabels.partial),
    noPledge: asString(record.noPledge, defaultWhatsappAlamaLabels.noPledge),
  }
}

function statusTone(status: unknown): 'success' | 'warning' | 'danger' | 'neutral' {
  if (status === 'PAID' || status === 'CONFIRMED' || status === 'ACTIVE' || status === 'TRIAL') return 'success'
  if (status === 'OVERDUE' || status === 'REVERSED' || status === 'CANCELLED' || status === 'SUSPENDED') return 'danger'
  if (status === 'PARTIALLY_PAID' || status === 'PENDING' || status === 'PAST_DUE' || status === 'EXPIRED') return 'warning'
  return 'neutral'
}

function phoneKey(value: unknown) {
  return asString(value).replace(/\D/g, '').replace(/^255/, '0')
}

function rowStatusLabel(value: unknown, fallback = 'Active') {
  return asString(value, fallback).replaceAll('_', ' ')
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

function smsPreviewTooLongText(preview: Row) {
  const remaining = asNumber(preview.remainingCharacters)
  return remaining < 0 ? `Message is ${Math.abs(remaining)} characters too long.` : `${remaining} characters remaining.`
}

function smsPreviewTone(preview: Row): 'success' | 'warning' | 'danger' | 'neutral' {
  if (preview.valid === false) return 'danger'
  const characters = asNumber(preview.characters)
  const max = Math.max(asNumber(preview.maxCharacters), 1)
  if (characters >= max || characters / max >= 0.9) return 'warning'
  return 'success'
}

function SmsCharacterCounter({ preview }: { preview: Row }) {
  return <StatusBadge tone={smsPreviewTone(preview)}>{asNumber(preview.characters)} / {asNumber(preview.maxCharacters)} · {smsPreviewTooLongText(preview)}</StatusBadge>
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
  const reason = asString(row.ineligibleReason, '')
  return asNumber(row.outstandingAmount ?? row.outstanding_amount) > 0 && Boolean(row.smsEnabled ?? row.sms_enabled) && Boolean(asString(row.phone ?? row.phone_e164, '')) && (!reason || reason === 'RECENTLY_SENT')
}

function canSendCompletedPledgeSms(row: Row) {
  const reason = asString(row.ineligibleReason, '')
  return asNumber(row.outstandingAmount ?? row.outstanding_amount) <= 0 && Boolean(row.smsEnabled ?? row.sms_enabled) && Boolean(asString(row.phone ?? row.phone_e164, '')) && (!reason || reason === 'RECENTLY_SENT')
}

function hasActivePledge(row: Row) {
  return Boolean(asString(row.pledge_id ?? row.pledgeId, '')) && asString(row.pledge_status ?? row.pledgeStatus, '') !== 'CANCELLED'
}

function jsonRecord(value: unknown): Row {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Row : {}
}

function jsonArray(value: unknown): Row[] {
  return Array.isArray(value) ? value.filter((item): item is Row => typeof item === 'object' && item !== null && !Array.isArray(item)) : []
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
  const selectedEvent = session.selectedEventId ? tenantContext?.events.find((candidate) => candidate.id === session.selectedEventId) ?? null : null
  const eventId = routeEventId ?? selectedEvent?.id ?? fallbackEvent?.id ?? ''
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
  const events = session.selectedTenantContext?.events ?? []
  const event = session.selectedEventId ? events.find((candidate) => candidate.id === session.selectedEventId) ?? events[0] ?? null : events[0] ?? null

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
  const events = session.selectedTenantContext?.events ?? []
  const event = session.selectedEventId ? events.find((candidate) => candidate.id === session.selectedEventId) ?? events[0] ?? null : events[0] ?? null
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
        <DataTable
          title="Events"
          rows={tenantContext.events}
          columns={[
            { key: 'event', header: 'Event', render: (tenantEvent) => <Link to={`/app/events/${tenantEvent.id}`}><strong>{tenantEvent.name}</strong><small>{asString((tenantEvent as unknown as Row).venue, 'No venue')}</small></Link>, sortValue: (tenantEvent) => tenantEvent.name },
            { key: 'type', header: 'Type', render: (tenantEvent) => <span>{tenantEvent.eventType}</span>, sortValue: (tenantEvent) => tenantEvent.eventType },
            { key: 'date', header: 'Date', render: (tenantEvent) => <span>{asDate(tenantEvent.eventDate)}</span>, sortValue: (tenantEvent) => tenantEvent.eventDate ?? '' },
            { key: 'members', header: 'Members', render: (tenantEvent) => <span>{asNumber((tenantEvent as unknown as Row).memberCount)}</span>, sortValue: (tenantEvent) => asNumber((tenantEvent as unknown as Row).memberCount), align: 'right' },
            { key: 'pledged', header: 'Pledged', render: (tenantEvent) => <span>{moneyText((tenantEvent as unknown as Row).totalPledged)}</span>, sortValue: (tenantEvent) => asNumber((tenantEvent as unknown as Row).totalPledged), align: 'right' },
            { key: 'collected', header: 'Collected', render: (tenantEvent) => <span>{moneyText((tenantEvent as unknown as Row).totalCollected ?? (tenantEvent as unknown as Row).totalPaid)}</span>, sortValue: (tenantEvent) => asNumber((tenantEvent as unknown as Row).totalCollected ?? (tenantEvent as unknown as Row).totalPaid), align: 'right' },
            { key: 'outstanding', header: 'Outstanding', render: (tenantEvent) => <span>{moneyText((tenantEvent as unknown as Row).totalOutstanding)}</span>, sortValue: (tenantEvent) => asNumber((tenantEvent as unknown as Row).totalOutstanding), align: 'right' },
            { key: 'status', header: 'Status', render: (tenantEvent) => <StatusBadge tone={statusTone(tenantEvent.status)}>{tenantEvent.status}</StatusBadge>, sortValue: (tenantEvent) => tenantEvent.status },
            { key: 'actions', header: 'Actions', render: (tenantEvent) => <Link to={`/app/events/${tenantEvent.id}`}>Open</Link>, align: 'right' },
          ]}
          getRowKey={(tenantEvent) => tenantEvent.id}
          emptyTitle="No events yet"
          emptyMessage={canCreate ? 'Create your first event to begin collecting pledges.' : blockedMessage || 'No accessible events are available.'}
        />
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

export function ContactsPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const queryClient = useQueryClient()
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('ACTIVE')
  const [formOpen, setFormOpen] = useState(false)
  const contacts = useQuery({ queryKey: ['contacts', tenantId], queryFn: async () => (await api.contacts(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const rows = contacts.data ?? []
  const filtered = rows.filter((contact) => {
    const searchText = `${contact.full_name ?? ''} ${contact.phone_e164 ?? ''} ${contact.member_code ?? ''}`.toLowerCase()
    const status = asString(contact.status, 'ACTIVE')
    const statusMatches =
      filter === 'ALL' ||
      (filter === 'SMS_ENABLED' ? contact.sms_enabled !== false : filter === 'SMS_DISABLED' ? contact.sms_enabled === false : status === filter)
    return statusMatches && searchText.includes(query.toLowerCase())
  })
  const columns: Array<DataTableColumn<Row>> = [
    { key: 'name', header: 'Name', render: (row) => <Link to={`/app/contacts/${asString(row.member_id)}`}><strong>{titleCaseMemberName(row.full_name, '')}</strong><small>{asString(row.email, 'No email')}</small></Link>, sortValue: (row) => titleCaseMemberName(row.full_name, '') },
    { key: 'phone', header: 'Phone', render: (row) => <span>{asString(row.phone_e164, 'No phone')}</span>, sortValue: (row) => asString(row.phone_e164) },
    { key: 'location', header: 'Location', render: (row) => <span>{asString(row.location, 'Not set')}</span>, sortValue: (row) => asString(row.location) },
    { key: 'events', header: 'Events', render: (row) => <span>{asNumber(row.event_count)} Events</span>, sortValue: (row) => asNumber(row.event_count), align: 'right' },
    { key: 'sms', header: 'SMS', render: (row) => <StatusBadge tone={row.sms_enabled === false ? 'warning' : 'success'}>{row.sms_enabled === false ? 'Disabled' : 'Enabled'}</StatusBadge>, sortValue: (row) => row.sms_enabled === false ? 'disabled' : 'enabled' },
    { key: 'status', header: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{rowStatusLabel(row.status)}</StatusBadge>, sortValue: (row) => asString(row.status) },
    { key: 'created', header: 'Created', render: (row) => <span>{asDate(row.created_at)}</span>, sortValue: (row) => asString(row.created_at), hideOnMobile: true },
    { key: 'actions', header: 'Actions', render: (row) => <ContactActions contact={row} tenantId={tenantId ?? ''} onChanged={() => void queryClient.invalidateQueries({ queryKey: ['contacts', tenantId] })} />, align: 'right' },
  ]

  if (!tenantId) return <ErrorState title="Unable to load contacts" message="Select a tenant first." />
  if (contacts.isLoading) return <LoadingState title="Loading contacts" message="Fetching tenant contact directory." />
  if (contacts.isError) return <ErrorState title="Unable to load contacts" message={errorMessage(contacts.error, 'Contacts could not be loaded.')} />

  return (
    <PageContainer>
      <PageHeader
        title="Contacts"
        description="Reusable tenant contact directory. Contacts are added to events only when selected."
        action={<button className="desktop-primary-button" type="button" onClick={() => setFormOpen((current) => !current)}><Plus size={18} aria-hidden /> Add Contact</button>}
      />
      {formOpen ? <ContactForm tenantId={tenantId} contacts={rows} onDone={() => { setFormOpen(false); void queryClient.invalidateQueries({ queryKey: ['contacts', tenantId] }) }} /> : null}
      <DataTable
        title="Contact Directory"
        rows={filtered}
        columns={columns}
        getRowKey={(row) => asString(row.member_id)}
        searchValue={query}
        onSearchChange={setQuery}
        searchPlaceholder="Search name or phone"
        filters={<label className="data-table-page-size"><span>Filter</span><select value={filter} onChange={(event) => setFilter(event.target.value)}>{['ACTIVE', 'ALL', 'ARCHIVED', 'SMS_ENABLED', 'SMS_DISABLED'].map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label>}
        emptyTitle="No contacts found."
        emptyMessage={rows.length ? 'Change the search or filter.' : 'Add a contact to build your reusable directory.'}
        mobileRender={(row) => (
          <>
            <div><span>Name</span><strong>{titleCaseMemberName(row.full_name, '')}</strong></div>
            <div><span>Phone</span><strong>{asString(row.phone_e164, 'No phone')}</strong></div>
            <div><span>Events</span><strong>{asNumber(row.event_count)} Events</strong></div>
            <div><span>Status</span><strong>{rowStatusLabel(row.status)}</strong></div>
            <div><span>Actions</span><strong><Link to={`/app/contacts/${asString(row.member_id)}`}>View</Link></strong></div>
          </>
        )}
      />
    </PageContainer>
  )
}

function ContactActions({ contact, tenantId, onChanged }: { contact: Row; tenantId: string; onChanged: () => void }) {
  const archive = useMutation({
    mutationFn: () => api.updateMember(tenantId, asString(contact.member_id), { status: 'ARCHIVED' }),
    onSuccess: onChanged,
  })
  return (
    <details className="row-actions-menu">
      <summary aria-label={`Actions for ${titleCaseMemberName(contact.full_name, 'contact')}`}>...</summary>
      <div>
        <Link to={`/app/contacts/${asString(contact.member_id)}`}>View</Link>
        <Link to={`/app/contacts/${asString(contact.member_id)}?edit=1`}>Edit</Link>
        <Link to="/app/events">Add to Event</Link>
        {asString(contact.status) !== 'ARCHIVED' ? <button type="button" disabled={archive.isPending} onClick={() => archive.mutate()}>{archive.isPending ? 'Archiving...' : 'Archive'}</button> : null}
      </div>
    </details>
  )
}

function ContactForm({ tenantId, contacts, eventId, onDone }: { tenantId: string; contacts: Row[]; eventId?: string; onDone: () => void }) {
  const [form, setForm] = useState({ fullName: '', phone: '', alternativePhone: '', email: '', location: '', notes: '', smsEnabled: true })
  const duplicate = form.phone ? contacts.find((contact) => phoneKey(contact.phone_e164) === phoneKey(form.phone) && phoneKey(contact.phone_e164)) : null
  const mutation = useMutation({
    mutationFn: async () => {
      const result = await api.createContact(tenantId, form)
      const memberId = asString(result.data.member_id)
      if (eventId && memberId) {
        await api.attachEventMember(tenantId, eventId, { memberId })
      }
      return result
    },
    onSuccess: onDone,
  })
  return (
    <form className="mobile-sheet form-grid" onSubmit={(event) => { event.preventDefault(); if (!duplicate) mutation.mutate() }}>
      <div className="panel-header">
        <div>
          <h2>{eventId ? 'Add New Contact to Event' : 'Add Contact'}</h2>
          <p>{eventId ? 'Create one tenant contact and attach it to this event.' : 'Create a tenant contact without requiring an event or pledge.'}</p>
        </div>
      </div>
      <Input label="Name" value={form.fullName} onChange={(fullName) => setForm((current) => ({ ...current, fullName }))} />
      <Input label="Phone optional" inputMode="tel" value={form.phone} onChange={(phone) => setForm((current) => ({ ...current, phone }))} />
      {duplicate ? (
        <section className="state-card state-card-danger">
          <h2>A contact with this phone already exists.</h2>
          <p>{titleCaseMemberName(duplicate.full_name, '')} · {asString(duplicate.phone_e164)}</p>
          <div className="inline-actions">
            <Link to={`/app/contacts/${asString(duplicate.member_id)}`}>View Existing Contact</Link>
            {eventId ? <button type="button" onClick={() => api.attachEventMember(tenantId, eventId, { memberId: asString(duplicate.member_id) }).then(onDone)}>Add Existing Contact to Event</button> : null}
          </div>
        </section>
      ) : null}
      <Input label="Alternative phone optional" inputMode="tel" value={form.alternativePhone} onChange={(alternativePhone) => setForm((current) => ({ ...current, alternativePhone }))} />
      <Input label="Email optional" value={form.email} onChange={(email) => setForm((current) => ({ ...current, email }))} />
      <Input label="Location optional" value={form.location} onChange={(location) => setForm((current) => ({ ...current, location }))} />
      <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
      <label className="switch-row">
        <span><strong>Send SMS notifications</strong><small>{form.phone ? 'This contact can receive event SMS after being added to an event.' : 'Add a phone number before enabling SMS.'}</small></span>
        <input type="checkbox" role="switch" checked={form.smsEnabled && Boolean(form.phone)} disabled={!form.phone} onChange={(event) => setForm((current) => ({ ...current, smsEnabled: event.target.checked }))} />
      </label>
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Contact could not be saved.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onDone}>Cancel</button>
        <button className="primary-button" type="submit" disabled={mutation.isPending || Boolean(duplicate) || !form.fullName.trim()}>{mutation.isPending ? 'Saving...' : eventId ? 'Create and Add' : 'Save Contact'}</button>
      </div>
    </form>
  )
}

export function ContactDetailPage() {
  const { memberId = '' } = useParams()
  const [search] = useSearchParams()
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const queryClient = useQueryClient()
  const [editing, setEditing] = useState(search.get('edit') === '1')
  const [eventId, setEventId] = useState('')
  const detail = useQuery({ queryKey: ['contact-detail', tenantId, memberId], queryFn: async () => (await api.contactDetail(tenantId ?? '', memberId)).data, enabled: Boolean(tenantId && memberId) })
  const attach = useMutation({
    mutationFn: () => api.attachEventMember(tenantId ?? '', eventId, { memberId }),
    onSuccess: () => {
      setEventId('')
      void queryClient.invalidateQueries({ queryKey: ['contact-detail', tenantId, memberId] })
      void queryClient.invalidateQueries({ queryKey: ['contacts', tenantId] })
    },
  })
  if (!tenantId) return <ErrorState title="Unable to load contact" message="Select a tenant first." />
  if (detail.isLoading) return <LoadingState title="Loading contact" />
  if (detail.isError || !detail.data) return <ErrorState title="Unable to load contact" message={errorMessage(detail.error, 'Contact could not be loaded.')} />

  const contact = jsonRecord(detail.data.contact)
  const events = jsonArray(detail.data.events)
  const contactForEdit = { ...contact, member_id: contact.id, member_status: contact.status }
  const columns: Array<DataTableColumn<Row>> = [
    { key: 'event', header: 'Event Name', render: (row) => <Link to={`/app/events/${asString(row.event_id)}/members/${asString(row.event_member_id)}`}><strong>{asString(row.event_name)}</strong><small>{asString(row.event_type)}</small></Link>, sortValue: (row) => asString(row.event_name) },
    { key: 'date', header: 'Event Date', render: (row) => <span>{asDate(row.event_date)}</span>, sortValue: (row) => asString(row.event_date) },
    { key: 'status', header: 'Participation Status', render: (row) => <StatusBadge tone={statusTone(row.participation_status)}>{rowStatusLabel(row.participation_status)}</StatusBadge>, sortValue: (row) => asString(row.participation_status) },
    { key: 'pledge', header: 'Pledge', render: (row) => <span>{moneyText(row.pledged_amount)}</span>, sortValue: (row) => asNumber(row.pledged_amount), align: 'right' },
    { key: 'paid', header: 'Paid', render: (row) => <span>{moneyText(row.paid_amount)}</span>, sortValue: (row) => asNumber(row.paid_amount), align: 'right' },
    { key: 'outstanding', header: 'Outstanding', render: (row) => <span>{moneyText(row.outstanding_amount)}</span>, sortValue: (row) => asNumber(row.outstanding_amount), align: 'right' },
  ]
  const availableEvents = session.selectedTenantContext?.events.filter((event) => !events.some((row) => asString(row.event_id) === event.id && asString(row.participation_status) === 'ACTIVE')) ?? []
  return (
    <PageContainer>
      <PageHeader title={titleCaseMemberName(contact.full_name, 'Contact')} description={`${asString(contact.member_code)} · ${asString(contact.phone_e164, 'No phone')}`} action={<div className="inline-actions"><Link to="/app/contacts"><ArrowLeft size={18} aria-hidden /> Contacts</Link><button className="desktop-primary-button" type="button" onClick={() => setEditing((current) => !current)}><Pencil size={18} aria-hidden /> {editing ? 'Close' : 'Edit Contact'}</button></div>} />
      <section className="content-panel">
        <div className="panel-header">
          <div><h2>Contact Information</h2><p>This tenant-level record can be reused across events.</p></div>
          <StatusBadge tone={statusTone(contact.status)}>{rowStatusLabel(contact.status)}</StatusBadge>
        </div>
        {editing ? <MemberEditForm tenantId={tenantId} member={contactForEdit} onCancel={() => setEditing(false)} onSaved={() => { setEditing(false); void detail.refetch(); void queryClient.invalidateQueries({ queryKey: ['contacts', tenantId] }) }} /> : (
          <>
            <ReviewLine label="Phone" value={asString(contact.phone_e164, 'Not set')} />
            <ReviewLine label="Alternative phone" value={asString(contact.alternative_phone_e164, 'Not set')} />
            <ReviewLine label="Email" value={asString(contact.email, 'Not set')} />
            <ReviewLine label="Location" value={asString(contact.location, 'Not set')} />
            <ReviewLine label="SMS" value={contact.sms_enabled === false ? 'Disabled' : 'Enabled'} />
            <ReviewLine label="Notes" value={asString(contact.notes, 'Not set')} />
          </>
        )}
      </section>
      <section className="content-panel">
        <div className="panel-header">
          <div><h2>Add to Event</h2><p>Only selected contacts become members of an event.</p></div>
        </div>
        <div className="inline-actions">
          <select value={eventId} onChange={(event) => setEventId(event.target.value)}>
            <option value="">Select event</option>
            {availableEvents.map((event) => <option key={event.id} value={event.id}>{event.name}</option>)}
          </select>
          <button type="button" disabled={!eventId || attach.isPending || asString(contact.status) === 'ARCHIVED'} onClick={() => attach.mutate()}>{attach.isPending ? 'Adding...' : 'Add to Event'}</button>
        </div>
        {attach.error ? <p className="field-error">{errorMessage(attach.error, 'Contact could not be added to event.')}</p> : null}
      </section>
      <DataTable
        title="Events"
        rows={events}
        columns={columns}
        getRowKey={(row) => asString(row.event_member_id)}
        emptyTitle="No event participation yet."
        emptyMessage="Add this contact to an event before recording pledges or payments."
      />
    </PageContainer>
  )
}

const activityActionLabels: Record<string, string> = {
  'contact.created': 'Contact added',
  'contact.updated': 'Contact edited',
  'contact.archived': 'Contact archived',
  'contact.reactivated': 'Contact reactivated',
  'member.created': 'Member added',
  'event_member.attached': 'Contact added to event',
  'event_member.removed': 'Member removed from event',
  'pledge.upserted': 'Pledge updated',
  'pledge.cancelled': 'Pledge cancelled',
  'payment.recorded': 'Payment recorded',
  'payment.reversed': 'Payment reversed',
  'event.created': 'Event created',
  'user.invited': 'User invited',
  'user.role_changed': 'User role changed',
}

function activityActionLabel(action: string) {
  return activityActionLabels[action] ?? action.replaceAll('.', ' ').replaceAll('_', ' ').replace(/(^|\s)\S/g, (match) => match.toUpperCase())
}

const activityFieldLabels: Record<string, string> = {
  full_name: 'Full Name',
  phone_e164: 'Phone',
  alternative_phone_e164: 'Alternative Phone',
  email: 'Email',
  location: 'Location',
  notes: 'Notes',
  status: 'Status',
  sms_enabled: 'SMS Enabled',
  preferred_language: 'Preferred Language',
  pledged_amount: 'Pledge Amount',
  payment_method: 'Payment Method',
}

function activityFieldLabel(key: string) {
  return activityFieldLabels[key] ?? key.split('_').filter(Boolean).map((part) => part[0]?.toUpperCase() + part.slice(1)).join(' ')
}

function activityValueText(value: unknown) {
  if (value === null || value === undefined) return '—'
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  const text = String(value).trim()
  return text ? text : '—'
}

function activitySubjectLabel(row: Row) {
  const newValues = jsonRecord(row.newValues ?? row.new_values)
  const oldValues = jsonRecord(row.oldValues ?? row.old_values)
  const name = newValues.full_name ?? oldValues.full_name
  if (typeof name === 'string' && name.trim()) return titleCaseMemberName(name, '')
  return asString(row.eventName ?? row.event_name)
}

export function TenantActivityPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const [search, setSearch] = useState('')
  const [entityType, setEntityType] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [offset, setOffset] = useState(0)
  const [selected, setSelected] = useState<Row | null>(null)
  const pageSize = 20

  function updateSearch(value: string) { setSearch(value); setOffset(0) }
  function updateEntityType(value: string) { setEntityType(value); setOffset(0) }
  function updateDateFrom(value: string) { setDateFrom(value); setOffset(0) }
  function updateDateTo(value: string) { setDateTo(value); setOffset(0) }

  const activity = useQuery({
    queryKey: ['activity', tenantId, search, entityType, dateFrom, dateTo, offset],
    queryFn: () => api.activity(tenantId ?? '', { search, entityType, dateFrom, dateTo, limit: pageSize, offset }),
    enabled: Boolean(tenantId),
  })

  const rows = activity.data?.data ?? []
  const pagination = jsonRecord(activity.data?.pagination)
  const hasMore = pagination.hasMore === true
  const totalRows = asNumber(pagination.totalRows)

  const columns: Array<DataTableColumn<Row>> = [
    { key: 'when', header: 'Date & Time', render: (row) => <span>{asDateTime(row.createdAt ?? row.created_at)}</span> },
    { key: 'user', header: 'User', render: (row) => <span>{asString(row.actorName ?? row.actor_name, 'System')}</span> },
    { key: 'action', header: 'Action', render: (row) => <span>{activityActionLabel(asString(row.action))}</span> },
    { key: 'item', header: 'Item', render: (row) => <span>{activitySubjectLabel(row) || '—'}</span> },
    { key: 'event', header: 'Event', render: (row) => <span>{asString(row.eventName ?? row.event_name, '—')}</span> },
    { key: 'details', header: 'Details', render: (row) => <button type="button" onClick={() => setSelected(row)}>View</button>, align: 'right' },
  ]

  if (!tenantId) return <ErrorState title="Unable to load activity" message="Select a tenant first." />
  if (activity.isLoading) return <LoadingState title="Loading activity" message="Fetching organization activity." />
  if (activity.isError) return <ErrorState title="Unable to load activity" message={errorMessage(activity.error, 'Activity could not be loaded.')} />

  return (
    <PageContainer>
      <PageHeader title="Activity" description="A record of meaningful changes made across your organization." />
      <DataTable
        title="Organization Activity"
        rows={rows}
        columns={columns}
        getRowKey={(row) => asString(row.id)}
        searchValue={search}
        onSearchChange={updateSearch}
        searchPlaceholder="Search activity"
        pageSizeOptions={[pageSize]}
        initialPageSize={pageSize}
        filters={(
          <>
            <label className="data-table-page-size">
              <span>Item</span>
              <select value={entityType} onChange={(event) => updateEntityType(event.target.value)}>
                <option value="">All</option>
                <option value="member">Contacts</option>
                <option value="payment">Payments</option>
                <option value="pledge">Pledges</option>
                <option value="event">Events</option>
                <option value="tenant_user">Users</option>
              </select>
            </label>
            <label className="data-table-page-size">
              <span>From</span>
              <input type="date" value={dateFrom} onChange={(event) => updateDateFrom(event.target.value)} />
            </label>
            <label className="data-table-page-size">
              <span>To</span>
              <input type="date" value={dateTo} onChange={(event) => updateDateTo(event.target.value)} />
            </label>
          </>
        )}
        emptyTitle="No activity yet."
        emptyMessage="Meaningful organization changes will appear here as they happen."
        mobileRender={(row) => (
          <>
            <div><span>User</span><strong>{asString(row.actorName ?? row.actor_name, 'System')}</strong></div>
            <div><span>Action</span><strong>{activityActionLabel(asString(row.action))}{activitySubjectLabel(row) ? `: ${activitySubjectLabel(row)}` : ''}</strong></div>
            <div><span>When</span><strong>{asDateTime(row.createdAt ?? row.created_at)}</strong></div>
            <div><span>Details</span><strong><button type="button" onClick={() => setSelected(row)}>View</button></strong></div>
          </>
        )}
      />
      <div className="inline-actions">
        <button type="button" disabled={offset === 0} onClick={() => setOffset((current) => Math.max(0, current - pageSize))}>Previous</button>
        <span>{totalRows ? `${offset + 1}-${Math.min(offset + pageSize, totalRows)} of ${totalRows}` : ''}</span>
        <button type="button" disabled={!hasMore} onClick={() => setOffset((current) => current + pageSize)}>Next</button>
      </div>
      {selected ? <ActivityDetailPanel row={selected} onClose={() => setSelected(null)} /> : null}
    </PageContainer>
  )
}

function ActivityDetailPanel({ row, onClose }: { row: Row; onClose: () => void }) {
  const newValues = jsonRecord(row.newValues ?? row.new_values)
  const oldValues = jsonRecord(row.oldValues ?? row.old_values)
  const changedKeys = Array.from(new Set([...Object.keys(oldValues), ...Object.keys(newValues)])).sort()
  const reason = asString(row.reason)
  const eventName = asString(row.eventName ?? row.event_name)

  return (
    <section className="mobile-sheet form-grid">
      <div className="panel-header">
        <div>
          <h2>{activityActionLabel(asString(row.action))}</h2>
          <p>{asDateTime(row.createdAt ?? row.created_at)}</p>
        </div>
      </div>
      <div><span>Actor</span><strong>{asString(row.actorName ?? row.actor_name, 'System')}</strong></div>
      <div><span>Entity</span><strong>{activityFieldLabel(asString(row.entityType ?? row.entity_type))}</strong></div>
      {eventName ? <div><span>Event</span><strong>{eventName}</strong></div> : null}
      {reason ? <div><span>Reason</span><strong>{reason}</strong></div> : null}
      {changedKeys.length ? (
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>Field</th><th>Old value</th><th>New value</th></tr></thead>
            <tbody>
              {changedKeys.map((key) => (
                <tr key={key}>
                  <td>{activityFieldLabel(key)}</td>
                  <td>{activityValueText(oldValues[key])}</td>
                  <td><strong>{activityValueText(newValues[key])}</strong></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
      <div className="sheet-actions">
        <button type="button" onClick={onClose}>Close</button>
      </div>
    </section>
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
  const sectionTitle = section === 'overview' ? 'Dashboard' : section.charAt(0).toUpperCase() + section.slice(1)
  const sectionDescription = section === 'overview'
    ? 'Collection progress, recent payments and pledge deadlines for the active event.'
    : section === 'members'
      ? 'Manage the contacts attached to this event and review pledge progress.'
      : section === 'pledges'
        ? 'Create and monitor pledge commitments, due dates and balances.'
        : section === 'payments'
          ? 'Record collections, review receipts and monitor payment activity.'
          : 'Event workspace.'

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
        title={sectionTitle}
        description={eventStatus === 'ACTIVE' ? sectionDescription : `Event status is ${eventStatus ?? 'unknown'}. Payments require an ACTIVE event.`}
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
            <MembersPanel tenantId={tenantId ?? ''} eventId={eventId} members={membersQuery.data ?? []} refresh={() => invalidateEvent(queryClient, tenantId ?? '', eventId)} initialSearch={search.get('q') ?? ''} canCreate={activeEvent.canCollect} />
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
          <Link to={`/app/messages?eventId=${eventId}&segment=balance-reminder`}>Send Reminders</Link>
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

function MembersPanel({ tenantId, eventId, members, refresh, initialSearch, canCreate }: { tenantId: string; eventId: string; members: Row[]; refresh: () => void; initialSearch: string; canCreate: boolean }) {
  const [query, setQuery] = useState(initialSearch)
  const [memberEntryMode, setMemberEntryMode] = useState<'existing' | 'new' | null>(null)
  const contacts = useQuery({ queryKey: ['contacts', tenantId], queryFn: async () => (await api.contacts(tenantId)).data, enabled: Boolean(tenantId && memberEntryMode === 'new') })
  const filtered = members.filter((member) => `${member.full_name ?? ''} ${member.phone_e164 ?? ''} ${member.member_code ?? ''}`.toLowerCase().includes(query.toLowerCase()))
  const columns: Array<DataTableColumn<Row>> = [
    { key: 'name', header: 'Name', render: (member) => <Link to={`/app/events/${eventId}/members/${asString(member.event_member_id)}`}><strong>{titleCaseMemberName(member.full_name, '')}</strong><small>{asString(member.member_code)}</small></Link>, sortValue: (member) => titleCaseMemberName(member.full_name, '') },
    { key: 'phone', header: 'Phone', render: (member) => <span>{asString(member.phone_e164, 'No phone')}</span>, sortValue: (member) => asString(member.phone_e164) },
    { key: 'category', header: 'Category', render: (member) => <span>{asString(member.category, 'No category')}</span>, sortValue: (member) => asString(member.category) },
    { key: 'pledge', header: 'Pledge', render: (member) => <span>{moneyText(member.pledged_amount)}</span>, sortValue: (member) => asNumber(member.pledged_amount), align: 'right' },
    { key: 'paid', header: 'Paid', render: (member) => <span>{moneyText(member.total_allocated)}</span>, sortValue: (member) => asNumber(member.total_allocated), align: 'right' },
    { key: 'outstanding', header: 'Outstanding', render: (member) => <span>{moneyText(member.outstanding_amount)}</span>, sortValue: (member) => asNumber(member.outstanding_amount), align: 'right' },
    { key: 'status', header: 'Status', render: (member) => <StatusBadge tone={statusTone(member.pledge_status)}>{asString(member.pledge_status, 'No Pledge')}</StatusBadge>, sortValue: (member) => asString(member.pledge_status) },
    { key: 'sms', header: 'SMS', render: (member) => <StatusBadge tone={member.sms_enabled === false ? 'warning' : 'success'}>{member.sms_enabled === false ? 'Disabled' : 'Enabled'}</StatusBadge>, sortValue: (member) => member.sms_enabled === false ? 'disabled' : 'enabled' },
    { key: 'actions', header: 'Actions', render: (member) => {
      const eventMemberId = asString(member.event_member_id)
      return <div className="inline-actions">{hasActivePledge(member) ? <Link to={`/app/events/${eventId}/payments/new?eventMemberId=${eventMemberId}&pledgeId=${asString(member.pledge_id)}`}>Pay</Link> : <Link to={`/app/events/${eventId}/pledges`}>Create Pledge</Link>}<Link to={`/app/events/${eventId}/members/${eventMemberId}`}>View</Link></div>
    }, align: 'right' },
  ]

  return (
    <section className="finance-section">
      {canCreate ? (
        <section className="member-action-panel">
          <div>
            <strong>Build Event Member List</strong>
            <span>Add existing tenant contacts or create a new contact and attach them to this event.</span>
          </div>
          <button className="desktop-primary-button" type="button" onClick={() => setMemberEntryMode((current) => current ? null : 'existing')}><Users size={18} aria-hidden /> {memberEntryMode ? 'Close' : 'Add Members'}</button>
        </section>
      ) : null}
      {memberEntryMode ? (
        <section className="member-entry-panel">
          <div className="segmented-control">
            <button className={memberEntryMode === 'existing' ? 'active' : ''} type="button" onClick={() => setMemberEntryMode('existing')}><Users size={16} aria-hidden /> Existing Contacts</button>
            <button className={memberEntryMode === 'new' ? 'active' : ''} type="button" onClick={() => setMemberEntryMode('new')}><Plus size={16} aria-hidden /> New Contact</button>
          </div>
          {memberEntryMode === 'existing' ? <EventContactPicker tenantId={tenantId} eventId={eventId} onDone={() => { setMemberEntryMode(null); refresh() }} /> : null}
          {memberEntryMode === 'new' ? <ContactForm tenantId={tenantId} contacts={contacts.data ?? []} eventId={eventId} onDone={() => { setMemberEntryMode(null); refresh() }} /> : null}
        </section>
      ) : null}
      <DataTable
        title="Event Members"
        rows={filtered.map((member, index) => ({ ...member, sequenceNumber: index + 1 })) as Row[]}
        columns={[{ key: 'sn', header: 'S/N', render: (member) => <span>{asNumber(member.sequenceNumber)}</span>, sortValue: (member) => asNumber(member.sequenceNumber), align: 'right' }, ...columns]}
        getRowKey={(member) => asString(member.event_member_id)}
        searchValue={query}
        onSearchChange={setQuery}
        searchPlaceholder="Search members"
        emptyTitle="No members have been added to this event yet."
        emptyMessage={canCreate ? 'Use Add Members to select contacts for this event.' : 'You do not have permission to add members.'}
        mobileRender={(member) => <MemberCard member={member} eventId={eventId} />}
      />
    </section>
  )
}

function EventContactPicker({ tenantId, eventId, onDone }: { tenantId: string; eventId: string; onDone: () => void }) {
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<string[]>([])
  const contacts = useQuery({ queryKey: ['event-available-contacts', tenantId, eventId], queryFn: async () => (await api.availableContactsForEvent(tenantId, eventId)).data, enabled: Boolean(tenantId && eventId) })
  const rows = contacts.data ?? []
  const filtered = rows.filter((contact) => `${contact.full_name ?? ''} ${contact.phone_e164 ?? ''} ${contact.member_code ?? ''}`.toLowerCase().includes(query.toLowerCase()))
  const attach = useMutation({
    mutationFn: async () => {
      await Promise.all(selected.map((memberId) => api.attachEventMember(tenantId, eventId, { memberId })))
    },
    onSuccess: onDone,
  })
  if (contacts.isLoading) return <LoadingState title="Loading contacts" message="Finding contacts not yet attached to this event." />
  if (contacts.isError) return <ErrorState title="Unable to load contacts" message={errorMessage(contacts.error, 'Available contacts could not be loaded.')} />
  const visibleIds = filtered.map((contact) => asString(contact.member_id)).filter(Boolean)
  const columns: Array<DataTableColumn<Row>> = [
    { key: 'select', header: 'Select', render: (contact) => <input type="checkbox" checked={selected.includes(asString(contact.member_id))} onChange={(event) => setSelected((current) => event.target.checked ? [...current, asString(contact.member_id)] : current.filter((id) => id !== asString(contact.member_id)))} />, align: 'center' },
    { key: 'name', header: 'Name', render: (contact) => <strong>{titleCaseMemberName(contact.full_name, '')}</strong>, sortValue: (contact) => titleCaseMemberName(contact.full_name, '') },
    { key: 'phone', header: 'Phone', render: (contact) => <span>{asString(contact.phone_e164, 'No phone')}</span>, sortValue: (contact) => asString(contact.phone_e164) },
    { key: 'code', header: 'Contact Code', render: (contact) => <span>{asString(contact.member_code)}</span>, sortValue: (contact) => asString(contact.member_code) },
    { key: 'events', header: 'Other Events', render: (contact) => <span>{asNumber(contact.other_event_count)}</span>, sortValue: (contact) => asNumber(contact.other_event_count), align: 'right' },
  ]
  return (
    <section className="mobile-sheet form-grid">
      <div className="panel-header">
        <div>
          <h2>Add Members</h2>
          <p>Select existing contacts for this event. No duplicate contact rows are created.</p>
        </div>
      </div>
      <div className="inline-actions">
        <button type="button" onClick={() => setSelected(visibleIds)}>Select All Visible</button>
        <button type="button" onClick={() => setSelected([])}>Clear</button>
      </div>
      <DataTable
        rows={filtered}
        columns={columns}
        getRowKey={(contact) => asString(contact.member_id)}
        searchValue={query}
        onSearchChange={setQuery}
        searchPlaceholder="Search contacts"
        emptyTitle="No available contacts."
        emptyMessage="Contacts already attached to this event are hidden."
      />
      {attach.error ? <p className="field-error">{errorMessage(attach.error, 'Selected contacts could not be added.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onDone}>Cancel</button>
        <button className="primary-button" type="button" disabled={!selected.length || attach.isPending} onClick={() => attach.mutate()}>{attach.isPending ? 'Adding...' : `Add Selected Members (${selected.length})`}</button>
      </div>
    </section>
  )
}

function MemberCard({ member, eventId }: { member: Row; eventId: string }) {
  const dueDate = member.effective_due_date ?? member.due_date
  return (
    <article className="finance-card">
      <div className="card-title-row">
        <div>
          <strong>{titleCaseMemberName(member.full_name)}</strong>
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
        {hasActivePledge(member) ? <Link to={`/app/events/${eventId}/payments/new?eventMemberId=${asString(member.event_member_id)}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link> : <Link to={`/app/events/${eventId}/pledges`}>Create Pledge</Link>}
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
      {!members.length ? <EmptyState title="No members available for pledges." message="Add a member before creating a pledge." /> : null}
      {members.length ? (
        <DataTable
          title="Pledges"
          rows={filtered}
          columns={[
            { key: 'member', header: 'Member', render: (pledge) => <strong>{titleCaseMemberName(pledge.member_name, '')}</strong>, sortValue: (pledge) => titleCaseMemberName(pledge.member_name, '') },
            { key: 'phone', header: 'Phone', render: (pledge) => <span>{asString(pledge.phone_e164, 'No phone')}</span>, sortValue: (pledge) => asString(pledge.phone_e164) },
            { key: 'category', header: 'Category', render: (pledge) => <span>{asString(pledge.category, 'No category')}</span>, sortValue: (pledge) => asString(pledge.category) },
            { key: 'pledged', header: 'Pledged', render: (pledge) => <span>{moneyText(pledge.pledged_amount)}</span>, sortValue: (pledge) => asNumber(pledge.pledged_amount), align: 'right' },
            { key: 'paid', header: 'Paid', render: (pledge) => <span>{moneyText(pledge.total_allocated)}</span>, sortValue: (pledge) => asNumber(pledge.total_allocated), align: 'right' },
            { key: 'outstanding', header: 'Outstanding', render: (pledge) => <span>{moneyText(pledge.outstanding_amount)}</span>, sortValue: (pledge) => asNumber(pledge.outstanding_amount), align: 'right' },
            { key: 'due', header: 'Due Date', render: (pledge) => <span>{asDate(pledge.effective_due_date ?? pledge.due_date)}</span>, sortValue: (pledge) => asString(pledge.effective_due_date ?? pledge.due_date) },
            { key: 'status', header: 'Status', render: (pledge) => <StatusBadge tone={statusTone(pledge.status)}>{asString(pledge.status)}</StatusBadge>, sortValue: (pledge) => asString(pledge.status) },
            { key: 'actions', header: 'Actions', render: (pledge) => <Link to={`/app/events/${eventId}/payments/new?eventMemberId=${asString(pledge.event_member_id)}&pledgeId=${asString(pledge.pledge_id)}`}>Record Payment</Link>, align: 'right' },
          ]}
          getRowKey={(pledge) => asString(pledge.pledge_id)}
          emptyTitle={pledges.length > 0 ? 'No pledges match this filter.' : 'No pledges have been recorded yet.'}
          emptyMessage={pledges.length > 0 ? 'Choose another pledge status.' : canCreate ? 'Use Record Pledge to create the first pledge.' : 'You do not have permission to create pledges.'}
          mobileRender={(pledge) => <PledgeCard pledge={pledge} eventId={eventId} />}
        />
      ) : null}
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
      <label>Member<select value={form.eventMemberId} onChange={(event) => setForm((current) => ({ ...current, eventMemberId: event.target.value }))}><option value="">Select member</option>{members.map((member) => <option key={asString(member.event_member_id)} value={asString(member.event_member_id)}>{titleCaseMemberName(member.full_name, '')}</option>)}</select></label>
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
        <div><strong>{titleCaseMemberName(pledge.member_name)}</strong><span>{asString(pledge.phone_e164, 'No phone')} · Due {asDate(dueDate)} · {dueType}</span></div>
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
      <DataTable
        title="Payments"
        rows={payments}
        columns={[
          { key: 'date', header: 'Date', render: (payment) => <span>{asDate(payment.payment_date)}</span>, sortValue: (payment) => asString(payment.payment_date) },
          { key: 'receipt', header: 'Receipt', render: (payment) => payment.receipt_number ? <Link to={`/app/receipts/${asString(payment.receipt_id)}`}>{asString(payment.receipt_number)}</Link> : <span>No receipt</span>, sortValue: (payment) => asString(payment.receipt_number) },
          { key: 'member', header: 'Member', render: (payment) => <strong>{titleCaseMemberName(payment.member_name, '')}</strong>, sortValue: (payment) => titleCaseMemberName(payment.member_name, '') },
          { key: 'amount', header: 'Amount', render: (payment) => <span>{moneyText(payment.amount)}</span>, sortValue: (payment) => asNumber(payment.amount), align: 'right' },
          { key: 'method', header: 'Method', render: (payment) => <span>{asString(payment.payment_method)}</span>, sortValue: (payment) => asString(payment.payment_method) },
          { key: 'reference', header: 'Reference', render: (payment) => <span>{asString(payment.transaction_reference, 'None')}</span>, sortValue: (payment) => asString(payment.transaction_reference) },
          { key: 'collector', header: 'Collector', render: (payment) => <span>{asString(payment.received_by, 'Ahadi user')}</span>, sortValue: (payment) => asString(payment.received_by) },
          { key: 'status', header: 'Status', render: (payment) => <StatusBadge tone={statusTone(payment.status)}>{asString(payment.status)}</StatusBadge>, sortValue: (payment) => asString(payment.status) },
          { key: 'actions', header: 'Actions', render: (payment) => <PaymentTableActions payment={payment} eventId={eventId} tenantId={tenantId} onReverse={refresh} />, align: 'right' },
        ]}
        getRowKey={(payment) => asString(payment.payment_id)}
        emptyTitle="No payments have been recorded yet."
        emptyMessage={canCreate ? 'Use Record Payment after adding a member and pledge.' : 'You do not have permission to record payments.'}
        mobileRender={(payment) => <PaymentCard payment={payment} eventId={eventId} tenantId={tenantId} onReverse={refresh} />}
      />
      {!today.length && payments.length ? <p className="privacy-note">No payments recorded today.</p> : null}
    </section>
  )
}

function PaymentTableActions({ payment, eventId, tenantId, onReverse }: { payment: Row; eventId: string; tenantId: string; onReverse: () => void }) {
  const [reason] = useState('Correction requested')
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const reverse = useMutation({
    mutationFn: () => api.reversePayment(tenantId, eventId, asString(payment.payment_id), { reason, idempotencyKey }),
    onSuccess: onReverse,
  })
  return (
    <div className="inline-actions">
      {payment.receipt_number ? <Link to={`/app/receipts/${asString(payment.receipt_id)}`}>Receipt</Link> : null}
      {payment.status === 'CONFIRMED' ? <button type="button" disabled={reverse.isPending} onClick={() => reverse.mutate()}>{reverse.isPending ? 'Reversing...' : 'Reverse'}</button> : null}
    </div>
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
        <div><strong>{titleCaseMemberName(payment.member_name)}</strong><span>{asString(payment.receipt_number, 'No receipt')} · {asDate(payment.payment_date)}</span></div>
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
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const detail = useQuery({ queryKey: ['member-detail', tenantId, eventId, eventMemberId], queryFn: async () => (await api.eventMemberDetail(tenantId ?? '', eventId, eventMemberId)).data, enabled: Boolean(tenantId && eventId && eventMemberId && !activeEvent.error) })
  const reportTenantContext = useSessionStore().selectedTenantContext
  const permissions = new Set(reportTenantContext?.permissions ?? [])
  const [reminderOpen, setReminderOpen] = useState(false)
  const [pledgeRequestOpen, setPledgeRequestOpen] = useState(false)
  const [editing, setEditing] = useState(false)
  const [removeOpen, setRemoveOpen] = useState(false)
  const [removeReason, setRemoveReason] = useState('Member removed from event')
  const removeMember = useMutation({
    mutationFn: () => api.removeEventMember(tenantId ?? '', eventId, eventMemberId, { reason: removeReason }),
    onSuccess: () => {
      if (tenantId) {
        invalidateEvent(queryClient, tenantId, eventId)
        void queryClient.invalidateQueries({ queryKey: ['member-detail', tenantId, eventId, eventMemberId] })
      }
      navigate(`/app/events/${eventId}/members`, { replace: true })
    },
  })
  if (activeEvent.error) return <ErrorState title="Unable to open member" message={activeEvent.error} />
  if (detail.isLoading) return <LoadingState title="Loading member" />
  if (detail.isError || !detail.data) return <ErrorState title="Unable to load member" message={errorMessage(detail.error, 'Member detail could not be loaded.')} />
  const member = detail.data.member
  const dueDate = member.effective_due_date ?? member.due_date
  const canUpdateMember = permissions.has('members.update')
  const refreshMember = () => {
    if (tenantId) {
      invalidateEvent(queryClient, tenantId, eventId)
      void queryClient.invalidateQueries({ queryKey: ['member-detail', tenantId, eventId, eventMemberId] })
    }
  }
  const canRemoveMember = permissions.has('members.assign_event')
  return (
    <PageContainer>
      <PageHeader
        title={titleCaseMemberName(member.full_name)}
        description={`${asString(member.phone_e164, 'No phone')} · ${asString(member.category, 'No category')}`}
        action={hasActivePledge(member) ? <Link className="desktop-primary-button" to={`/app/events/${eventId}/payments/new?eventMemberId=${eventMemberId}&pledgeId=${asString(member.pledge_id)}`}>Record Payment</Link> : <Link className="desktop-primary-button" to={`/app/events/${eventId}/pledges`}>Create Pledge</Link>}
      />
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
          <div className="inline-actions">
            <StatusBadge tone={statusTone(member.event_member_status)}>{asString(member.event_member_status, 'ACTIVE')}</StatusBadge>
            {canUpdateMember ? <button type="button" onClick={() => setEditing((current) => !current)}><Pencil size={18} aria-hidden /> {editing ? 'Close' : 'Edit'}</button> : null}
            {canRemoveMember ? <button type="button" onClick={() => setRemoveOpen((current) => !current)}>{removeOpen ? 'Cancel Remove' : 'Remove from Event'}</button> : null}
          </div>
        </div>
        {removeOpen ? (
          <section className="danger-action-panel">
            <div>
              <strong>Remove member and roll back event finances</strong>
              <span>This reverses confirmed payments, cancels active pledges and removes this member from the event. Tenant contact details remain available in Contacts.</span>
            </div>
            <label>Reason<textarea rows={3} value={removeReason} onChange={(event) => setRemoveReason(event.target.value)} /></label>
            {removeMember.error ? <p className="field-error">{errorMessage(removeMember.error, 'Member could not be removed from event.')}</p> : null}
            <div className="sheet-actions">
              <button type="button" onClick={() => setRemoveOpen(false)}>Keep Member</button>
              <button className="button-danger" type="button" disabled={removeMember.isPending || !removeReason.trim()} onClick={() => removeMember.mutate()}>{removeMember.isPending ? 'Removing...' : 'Remove and Roll Back'}</button>
            </div>
          </section>
        ) : null}
        {editing ? (
          <MemberEditForm
            key={asString(member.member_id)}
            tenantId={tenantId ?? ''}
            member={member}
            onCancel={() => setEditing(false)}
            onSaved={() => {
              setEditing(false)
              refreshMember()
            }}
          />
        ) : (
          <>
            <ReviewLine label="Alternative phone" value={asString(member.alternative_phone_e164, 'Not set')} />
            <ReviewLine label="Email" value={asString(member.email, 'Not set')} />
            <ReviewLine label="Location" value={asString(member.location, 'Not set')} />
            <ReviewLine label="SMS notifications" value={member.sms_enabled === false ? 'Disabled' : 'Enabled'} />
            <ReviewLine label="Pledge due date" value={`${asDate(dueDate)} (${member.has_custom_due_date ? 'custom' : 'event default'})`} />
            <ReviewLine label="Last reminder" value={reminderStatusText(member)} />
          </>
        )}
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

function MemberEditForm({ tenantId, member, onCancel, onSaved }: { tenantId: string; member: Row; onCancel: () => void; onSaved: () => void }) {
  const memberId = asString(member.member_id)
  const hasNotes = Object.prototype.hasOwnProperty.call(member, 'notes')
  const hasPreferredLanguage = Object.prototype.hasOwnProperty.call(member, 'preferred_language')
  const hasMemberStatus = Object.prototype.hasOwnProperty.call(member, 'member_status')
  const [form, setForm] = useState({
    fullName: asString(member.full_name),
    phoneE164: asString(member.phone_e164),
    alternativePhoneE164: asString(member.alternative_phone_e164),
    email: asString(member.email),
    location: asString(member.location),
    notes: asString(member.notes),
    preferredLanguage: asString(member.preferred_language, 'sw'),
    smsEnabled: member.sms_enabled !== false,
    memberStatus: asString(member.member_status, 'ACTIVE'),
  })
  const mutation = useMutation({
    mutationFn: () => {
      const payload: Record<string, unknown> = {
        fullName: titleCaseMemberName(form.fullName),
        phoneE164: form.phoneE164 || null,
        alternativePhoneE164: form.alternativePhoneE164 || null,
        email: form.email || null,
        location: form.location || null,
        smsEnabled: Boolean(form.phoneE164) && form.smsEnabled,
      }
      if (hasNotes) payload.notes = form.notes || null
      if (hasPreferredLanguage) payload.preferredLanguage = form.preferredLanguage
      if (hasMemberStatus) payload.status = form.memberStatus
      return api.updateMember(tenantId, memberId, payload)
    },
    onSuccess: onSaved,
  })
  if (!memberId) {
    return <p className="field-error">Member record id is missing, so this profile cannot be edited.</p>
  }
  return (
    <form className="form-grid" onSubmit={(event) => { event.preventDefault(); if (!mutation.isPending) mutation.mutate() }}>
      <Input label="Full name" value={form.fullName} onChange={(fullName) => setForm((current) => ({ ...current, fullName }))} />
      <Input label="Phone number" inputMode="tel" value={form.phoneE164} onChange={(phoneE164) => setForm((current) => ({ ...current, phoneE164 }))} />
      <Input label="Alternative phone optional" inputMode="tel" value={form.alternativePhoneE164} onChange={(alternativePhoneE164) => setForm((current) => ({ ...current, alternativePhoneE164 }))} />
      <Input label="Email optional" value={form.email} onChange={(email) => setForm((current) => ({ ...current, email }))} />
      <Input label="Location optional" value={form.location} onChange={(location) => setForm((current) => ({ ...current, location }))} />
      {hasPreferredLanguage ? <label>Preferred language<select value={form.preferredLanguage} onChange={(event) => setForm((current) => ({ ...current, preferredLanguage: event.target.value }))}><option value="sw">Swahili</option><option value="en">English</option></select></label> : null}
      {hasMemberStatus ? <label>Status<select value={form.memberStatus} onChange={(event) => setForm((current) => ({ ...current, memberStatus: event.target.value }))}><option value="ACTIVE">Active</option><option value="INACTIVE">Inactive</option><option value="ARCHIVED">Archived</option></select></label> : null}
      {hasNotes ? <label>Notes<textarea value={form.notes} onChange={(event) => setForm((current) => ({ ...current, notes: event.target.value }))} rows={3} /></label> : null}
      <label className="switch-row">
        <span><strong>SMS notifications</strong><small>{form.phoneE164 ? 'Payment confirmations and reminders can be queued.' : 'Add a phone number before enabling SMS.'}</small></span>
        <input type="checkbox" role="switch" checked={form.smsEnabled && Boolean(form.phoneE164)} disabled={!form.phoneE164} onChange={(event) => setForm((current) => ({ ...current, smsEnabled: event.target.checked }))} />
      </label>
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Member details could not be saved.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onCancel}>Cancel</button>
        <button className="primary-button" type="submit" disabled={mutation.isPending || !tenantId || !memberId || !form.fullName.trim()}>{mutation.isPending ? 'Saving...' : 'Save Changes'}</button>
      </div>
    </form>
  )
}

export function PaymentEntryPage() {
  const { eventId = '' } = useParams()
  const [search] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const activeEvent = useActiveEventContext(eventId)
  const tenantId = activeEvent.tenantId
  const outstandingMembers = useQuery({ queryKey: ['event-outstanding-members', tenantId, eventId, 'record-payment'], queryFn: async () => (await api.eventOutstandingMembers(tenantId ?? '', eventId)).data, enabled: Boolean(tenantId && eventId && !activeEvent.error) })
  const memberPledgeLookup = useQuery({ queryKey: ['event-members', tenantId, eventId, 'record-payment-pledge-lookup'], queryFn: async () => (await api.eventMembers(tenantId ?? '', eventId)).data, enabled: Boolean(tenantId && eventId && !activeEvent.error) })
  const [memberSearch, setMemberSearch] = useState('')
  const [debouncedMemberSearch, setDebouncedMemberSearch] = useState('')
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
  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedMemberSearch(memberSearch.trim()), recordPaymentSearchDebounceMs)
    return () => window.clearTimeout(timer)
  }, [memberSearch])
  const memberRows = outstandingMembers.data ?? []
  const pledgeRows = memberPledgeLookup.data ?? []
  const paymentPledgeId = (member: Row) => {
    const direct = asString(member.pledgeId ?? member.pledge_id)
    if (direct) return direct
    const eventMemberId = asString(member.eventMemberId ?? member.event_member_id)
    const lookup = pledgeRows.find((row) => asString(row.event_member_id ?? row.eventMemberId) === eventMemberId && hasActivePledge(row))
    return asString(lookup?.pledge_id ?? lookup?.pledgeId)
  }
  const payableMembers = memberRows.filter((member) => asNumber(member.outstandingAmount ?? member.outstanding_amount) > 0 && paymentPledgeId(member))
  const searchReady = debouncedMemberSearch.length >= recordPaymentSearchMinLength
  const shortSearch = memberSearch.trim().length > 0 && memberSearch.trim().length < recordPaymentSearchMinLength
  const filteredMembers = searchReady
    ? payableMembers.filter((member) => `${member.fullName ?? member.full_name ?? ''} ${member.phone ?? member.phone_e164 ?? ''}`.toLowerCase().includes(debouncedMemberSearch.toLowerCase()))
    : payableMembers
  const selectedMember = payableMembers.find((member) => asString(member.eventMemberId ?? member.event_member_id) === form.eventMemberId && paymentPledgeId(member) === form.pledgeId)
  const outstanding = asNumber(selectedMember?.outstandingAmount ?? selectedMember?.outstanding_amount)
  const paymentAmount = asNumber(form.amount)
  function selectPaymentMember(member: Row) {
    setForm((current) => ({ ...current, eventMemberId: asString(member.eventMemberId ?? member.event_member_id), pledgeId: paymentPledgeId(member), amount: '', transactionReference: '', providerName: '', notes: '' }))
  }
  function clearPaymentMember() {
    setForm((current) => ({ ...current, eventMemberId: '', pledgeId: '', amount: '', transactionReference: '', providerName: '', notes: '' }))
  }
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
  if (outstandingMembers.isLoading || memberPledgeLookup.isLoading) return <LoadingState title="Loading payable members" message="Fetching outstanding pledge balances for payment entry." />
  if (outstandingMembers.isError) return <ErrorState title="Unable to load payable members" message={errorMessage(outstandingMembers.error, 'Outstanding members could not be loaded for payment entry.')} />
  if (memberPledgeLookup.isError) return <ErrorState title="Unable to load pledge lookup" message={errorMessage(memberPledgeLookup.error, 'Pledge records could not be loaded for payment entry.')} />
  return (
    <PageContainer>
      <PageHeader title="Record Payment" description="Select a member, confirm the amount and generate a receipt." action={<Link to={`/app/events/${eventId}`}><ArrowLeft size={18} aria-hidden /> Back</Link>} />
      <form className="payment-flow" onSubmit={(event: FormEvent) => { event.preventDefault(); if (!mutation.isPending) mutation.mutate() }}>
        {!selectedMember ? (
          <>
            {shortSearch ? <p className="privacy-note">Enter at least 3 characters to search.</p> : null}
            <DataTable
              title="Outstanding Members"
              rows={filteredMembers}
              columns={[
                { key: 'member', header: 'Member', render: (member) => <strong>{titleCaseMemberName(member.fullName ?? member.full_name)}</strong>, sortValue: (member) => titleCaseMemberName(member.fullName ?? member.full_name, '') },
                { key: 'phone', header: 'Phone', render: (member) => <span>{asString(member.phone ?? member.phone_e164, 'No phone')}</span>, sortValue: (member) => asString(member.phone ?? member.phone_e164) },
                { key: 'pledged', header: 'Pledged', render: (member) => <span>{moneyText(member.pledgedAmount ?? member.pledged_amount)}</span>, sortValue: (member) => asNumber(member.pledgedAmount ?? member.pledged_amount), align: 'right' },
                { key: 'paid', header: 'Paid', render: (member) => <span>{moneyText(member.totalPaid ?? member.total_paid ?? member.total_allocated)}</span>, sortValue: (member) => asNumber(member.totalPaid ?? member.total_paid ?? member.total_allocated), align: 'right' },
                { key: 'outstanding', header: 'Outstanding', render: (member) => <strong>{moneyText(member.outstandingAmount ?? member.outstanding_amount)}</strong>, sortValue: (member) => asNumber(member.outstandingAmount ?? member.outstanding_amount), align: 'right' },
                { key: 'due', header: 'Due Date', render: (member) => <span>{asDate(member.dueDate ?? member.effective_due_date ?? member.due_date)}</span>, sortValue: (member) => asString(member.dueDate ?? member.effective_due_date ?? member.due_date) },
                { key: 'actions', header: 'Action', render: (member) => <button type="button" onClick={() => selectPaymentMember(member)}>Select</button>, align: 'right' },
              ]}
              getRowKey={(member) => asString(member.eventMemberId ?? member.event_member_id)}
              searchValue={memberSearch}
              onSearchChange={setMemberSearch}
              searchPlaceholder="Search name or phone"
              pageSizeOptions={[recordPaymentRowsPerPage]}
              initialPageSize={recordPaymentRowsPerPage}
              emptyTitle={searchReady ? 'No payable members match your search.' : 'No outstanding pledge balances.'}
              emptyMessage={memberRows.length ? 'Try another name or phone number.' : 'Members with outstanding pledges in this event will appear here.'}
              mobileRender={(member) => (
                <>
                  <div><span>Member</span><strong>{titleCaseMemberName(member.fullName ?? member.full_name)}</strong></div>
                  <div><span>Phone</span><strong>{asString(member.phone ?? member.phone_e164, 'No phone')}</strong></div>
                  <div><span>Pledged</span><strong>{moneyText(member.pledgedAmount ?? member.pledged_amount)}</strong></div>
                  <div><span>Paid</span><strong>{moneyText(member.totalPaid ?? member.total_paid ?? member.total_allocated)}</strong></div>
                  <div><span>Outstanding</span><strong>{moneyText(member.outstandingAmount ?? member.outstanding_amount)}</strong></div>
                  <div><span>Due Date</span><strong>{asDate(member.dueDate ?? member.effective_due_date ?? member.due_date)}</strong></div>
                  <div><span>Action</span><strong><button type="button" onClick={() => selectPaymentMember(member)}>Select</button></strong></div>
                </>
              )}
            />
            {memberRows.length > 0 && !payableMembers.length ? <EmptyState title="No active pledges available." message="Create a pledge for a member before recording payment." /> : null}
          </>
        ) : null}
        {selectedMember ? <>
          <PaymentMemberSnapshot member={selectedMember} onChangeMember={clearPaymentMember} />
          <Input label="Amount received" inputMode="decimal" value={form.amount} onChange={(amount) => setForm((current) => ({ ...current, amount }))} />
          <div className="quick-amounts"><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(outstanding) }))}>Outstanding</button><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(Math.round(outstanding / 2)) }))}>Half</button><button type="button" onClick={() => setForm((current) => ({ ...current, amount: String(asNumber(selectedMember?.pledgedAmount ?? selectedMember?.pledged_amount)) }))}>Pledged</button></div>
          <ReviewLine label="Outstanding after payment" value={form.amount ? moneyText(Math.max(outstanding - paymentAmount, 0)) : moneyText(outstanding)} />
          <ReviewLine label="Excess / unallocated amount" value={form.amount && paymentAmount > outstanding ? moneyText(paymentAmount - outstanding) : 'None'} />
          <label>Payment method<select value={form.paymentMethod} onChange={(event) => setForm((current) => ({ ...current, paymentMethod: event.target.value }))}>{paymentMethods.map((method) => <option key={method} value={method}>{method}</option>)}</select></label>
          <Input label="Payment date and time" type="datetime-local" value={form.paymentDate} onChange={(paymentDate) => setForm((current) => ({ ...current, paymentDate }))} />
          <Input label="Transaction reference optional" value={form.transactionReference} onChange={(transactionReference) => setForm((current) => ({ ...current, transactionReference }))} />
          <Input label="Provider name optional" value={form.providerName} onChange={(providerName) => setForm((current) => ({ ...current, providerName }))} />
          <Input label="Notes optional" value={form.notes} onChange={(notes) => setForm((current) => ({ ...current, notes }))} />
          {mutation.error ? <p className="field-error">{mutation.error.message}</p> : null}
          <button className="primary-button" type="submit" disabled={mutation.isPending || !form.pledgeId || !form.amount || !tenantId}>{mutation.isPending ? 'Recording...' : 'Confirm and Generate Receipt'}</button>
        </> : null}
      </form>
    </PageContainer>
  )
}

function PaymentMemberSnapshot({ member, onChangeMember }: { member: Row; onChangeMember: () => void }) {
  return (
    <section className="payment-context-panel">
      <div className="panel-header">
        <div>
          <span className="eyebrow">Selected Member</span>
          <h2>{titleCaseMemberName(member.fullName ?? member.full_name, 'Selected Member')}</h2>
          <p>{asString(member.phone ?? member.phone_e164, 'No phone')}</p>
        </div>
        <button type="button" onClick={onChangeMember}>Change member</button>
      </div>
      <div className="payment-context-amounts">
        <span><small>Pledged</small>{moneyText(member.pledgedAmount ?? member.pledged_amount)}</span>
        <span><small>Paid</small>{moneyText(member.totalPaid ?? member.total_paid ?? member.total_allocated)}</span>
        <span className="payment-context-outstanding"><small>Outstanding</small>{moneyText(member.outstandingAmount ?? member.outstanding_amount)}</span>
      </div>
      <div className="payment-context-meta">
        {asString(member.dueDate ?? member.effective_due_date ?? member.due_date) ? <ReviewLine label="Due date" value={asDate(member.dueDate ?? member.effective_due_date ?? member.due_date)} /> : null}
        <ReviewLine label="Status" value={<StatusBadge tone={statusTone(member.pledgeStatus ?? member.pledge_status)}>{asString(member.pledgeStatus ?? member.pledge_status, 'PENDING').replaceAll('_', ' ')}</StatusBadge>} />
      </div>
    </section>
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
        <ReviewLine label="Member" value={`${titleCaseMemberName(data.member_name, '')} · ${asString(data.member_phone)}`} />
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
  const eventMemberId = asString(member.eventMemberId ?? member.event_member_id)
  const preview = useQuery({ queryKey: ['sms-preview', tenantId, eventId, eventMemberId, 'BALANCE_REMINDER'], queryFn: async () => (await api.smsPreview(tenantId, eventId, { templateCode: 'BALANCE_REMINDER', eventMemberId })).data, enabled: Boolean(tenantId && eventId && eventMemberId) })
  const mutation = useMutation({
    mutationFn: () => api.sendBalanceReminder(tenantId, eventId, { eventMemberId, idempotencyKey }),
    onSuccess: onSent,
  })
  const previewData = preview.data ?? {}
  return (
    <section className="mobile-sheet form-grid">
      <div className="panel-header">
        <div>
          <h2>Send Reminder</h2>
          <p>{titleCaseMemberName(member.fullName ?? member.full_name)} · {maskPhone(member.phone ?? member.phone_e164)}</p>
        </div>
      </div>
      <ReviewLine label="Pledged" value={moneyText(member.pledgedAmount ?? member.pledged_amount)} />
      <ReviewLine label="Paid" value={moneyText(member.totalPaid ?? member.total_paid ?? member.total_allocated)} />
      <ReviewLine label="Outstanding" value={moneyText(member.outstandingAmount ?? member.outstanding_amount)} />
      <ReviewLine label="Due date" value={asDate(member.dueDate ?? member.effective_due_date ?? member.due_date)} />
      {preview.isLoading ? <LoadingState title="Generating SMS preview" /> : null}
      {preview.isError ? <p className="field-error">{errorMessage(preview.error, 'SMS preview could not be generated.')}</p> : null}
      {preview.data ? <SmsCharacterCounter preview={previewData} /> : null}
      <article className="content-panel">
        <p>{asString(previewData.message, 'Preview will be rendered again by the server before queueing.')}</p>
      </article>
      {mutation.data?.data?.queued === false ? <p className="field-error">{asString(mutation.data.data.reason, 'Reminder was not queued.')}</p> : null}
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Reminder could not be queued.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onClose}>Cancel</button>
        <button className="primary-button" type="button" disabled={mutation.isPending || previewData.valid !== true} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : 'Send SMS'}</button>
      </div>
    </section>
  )
}

function PledgeRequestSheet({ tenantId, eventId, eventMemberId, eventName, onClose, onSent }: { tenantId: string; eventId: string; eventMemberId: string; eventName: string; onClose: () => void; onSent: () => void }) {
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const members = useQuery({ queryKey: ['no-pledge-members', tenantId, eventId, eventMemberId], queryFn: async () => (await api.eventNoPledgeMembers(tenantId, eventId)).data, enabled: Boolean(tenantId && eventId && eventMemberId) })
  const settings = useQuery({ queryKey: ['sms-settings', tenantId], queryFn: async () => (await api.smsSettings(tenantId)).data, enabled: Boolean(tenantId) })
  const preview = useQuery({ queryKey: ['sms-preview', tenantId, eventId, eventMemberId, 'PLEDGE_REQUEST'], queryFn: async () => (await api.smsPreview(tenantId, eventId, { templateCode: 'PLEDGE_REQUEST', eventMemberId })).data, enabled: Boolean(tenantId && eventId && eventMemberId) })
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
          <p>{titleCaseMemberName(member.fullName)} · {asString(member.maskedPhone, maskPhone(member.phone))}</p>
        </div>
        <StatusBadge tone={eligibility.tone}>{eligibility.label}</StatusBadge>
      </div>
      <ReviewLine label="Event" value={eventName} />
      <ReviewLine label="Sender ID" value={asString(settings.data?.senderId, 'MICHANGO')} />
      {preview.isLoading ? <LoadingState title="Generating SMS preview" /> : null}
      {preview.isError ? <p className="field-error">{errorMessage(preview.error, 'SMS preview could not be generated.')}</p> : null}
      {preview.data ? <SmsCharacterCounter preview={preview.data} /> : null}
      <article className="content-panel">
        <p>{asString(preview.data?.message ?? member.messagePreview, 'Preview will be rendered again by the server before queueing.')}</p>
      </article>
      {mutation.data?.data?.queued === false ? <p className="field-error">{asString(mutation.data.data.reason, 'Pledge request was not queued.')}</p> : null}
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Pledge request could not be queued.')}</p> : null}
      <div className="sheet-actions">
        <button type="button" onClick={onClose}>Cancel</button>
        <button className="primary-button" type="button" disabled={Boolean(member.ineligibleReason) || mutation.isPending || preview.data?.valid !== true} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : 'Send SMS'}</button>
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
  const [headerText, setHeaderText] = useState<string | null>(null)
  const [footerText, setFooterText] = useState<string | null>(null)
  const [summaryRows, setSummaryRows] = useState<WhatsappSummaryRow[] | null>(null)
  const [showPaymentInstructions, setShowPaymentInstructions] = useState<boolean | null>(null)
  const [paymentInstructions, setPaymentInstructions] = useState<string | null>(null)
  const [showAlama, setShowAlama] = useState<boolean | null>(null)
  const [alamaLabels, setAlamaLabels] = useState<WhatsappAlamaLabels | null>(null)
  const [copyMessage, setCopyMessage] = useState('')
  const [selectedPart, setSelectedPart] = useState(0)
  const canQuery = Boolean(tenantId && eventId && !activeEvent.error)
  const settings = useQuery({ queryKey: ['whatsapp-share-settings', tenantId, eventId], queryFn: async () => (await api.whatsappShareSettings(tenantId ?? '', eventId)).data, enabled: canQuery })
  const canFinancial = Boolean(settings.data?.canUseFinancialFormats) || sessionPermissions.has('shares.whatsapp.financial')
  const effectiveFormat = !canFinancial && isFinancialWhatsappFormat(format) ? 'PRIVACY' : (format || asString(settings.data?.defaultListFormat, canFinancial ? 'DETAILED' : 'PRIVACY'))
  const effectiveSort = sort || asString(settings.data?.defaultSort, 'ORIGINAL')
  const effectiveIncludeSummary = effectiveFormat === 'PRIVACY' && includeSummary === null ? false : (includeSummary ?? settings.data?.defaultIncludeSummary !== false)
  const effectiveIncludeEventDate = includeEventDate ?? (settings.data?.includeEventDate === true)
  const effectiveIncludeEventPaymentInstructions = settings.data?.includeEventPaymentInstructions === true
  const effectiveIncludeMobileMoneyInstructions = settings.data?.includeMobileMoneyInstructions === true
  const effectiveIncludeBankInstructions = settings.data?.includeBankInstructions === true
  const effectiveHeaderText = headerText ?? asString(settings.data?.headerText, '')
  const effectiveFooterText = footerText ?? asString(settings.data?.footerText, '')
  const summarySources = normalizeWhatsappSummarySources(settings.data?.availableSummarySources)
  const effectiveSummaryRows = summaryRows ?? normalizeWhatsappSummaryRows(settings.data?.summaryRows)
  const effectiveShowPaymentInstructions = showPaymentInstructions ?? settings.data?.showPaymentInstructions !== false
  const effectivePaymentInstructions = paymentInstructions ?? asString(settings.data?.paymentInstructions, '')
  const effectiveShowAlama = showAlama ?? settings.data?.showAlama !== false
  const effectiveAlamaLabels = alamaLabels ?? normalizeWhatsappAlamaLabels(settings.data?.alamaLabels)
  const presentationPayload = {
    showPaymentInstructions: effectiveShowPaymentInstructions,
    paymentInstructions: effectivePaymentInstructions || null,
    showAlama: effectiveShowAlama,
    alamaLabels: effectiveAlamaLabels,
  }

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
    summaryRows: effectiveSummaryRows,
    ...presentationPayload,
  }
  const preview = useQuery({
    queryKey: ['whatsapp-share-preview', tenantId, eventId, previewPayload],
    queryFn: async () => (await api.whatsappSharePreview(tenantId ?? '', eventId, previewPayload)).data,
    enabled: canQuery && !settings.isLoading,
  })
  const saveSettings = useMutation({
    mutationFn: () => canFinancial
      ? api.saveWhatsappShareSettings(tenantId ?? '', eventId, {
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
        summaryRows: effectiveSummaryRows,
        ...presentationPayload,
      })
      : api.saveWhatsappSharePresentationSettings(tenantId ?? '', eventId, presentationPayload),
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
  const selectedFormat = whatsappFormats.find((item) => item.value === effectiveFormat) ?? whatsappFormats[0]
  const optionCount = [
    effectiveIncludeSummary,
    effectiveIncludeEventDate,
    effectiveShowPaymentInstructions,
    effectiveShowAlama,
    includeWithoutPledges,
  ].filter(Boolean).length

  function commitSummaryRows(rows: WhatsappSummaryRow[]) {
    setSummaryRows(rows.map((row, index) => ({ ...row, order: index + 1 })))
  }

  function updateSummaryRow(index: number, patch: Partial<WhatsappSummaryRow>) {
    commitSummaryRows(effectiveSummaryRows.map((row, rowIndex) => rowIndex === index ? { ...row, ...patch } : row))
  }

  function moveSummaryRow(index: number, direction: -1 | 1) {
    const nextIndex = index + direction
    if (nextIndex < 0 || nextIndex >= effectiveSummaryRows.length) return
    const rows = [...effectiveSummaryRows]
    const [row] = rows.splice(index, 1)
    if (!row) return
    rows.splice(nextIndex, 0, row)
    commitSummaryRows(rows)
  }

  function addSummaryRow() {
    const source = summarySources.find((item) => !effectiveSummaryRows.some((row) => row.valueSource === item.valueSource)) ?? summarySources[0]
    if (!source) return
    commitSummaryRows([...effectiveSummaryRows, { label: source.label, valueSource: source.valueSource, visible: true, order: effectiveSummaryRows.length + 1 }])
  }

  function resetSummaryRows() {
    setSummaryRows(normalizeWhatsappSummaryRows(settings.data?.defaultSummaryRows))
  }

  function updateAlamaLabel(key: keyof WhatsappAlamaLabels, value: string) {
    setAlamaLabels({ ...effectiveAlamaLabels, [key]: value })
  }

  function resetPaymentInstructions() {
    setPaymentInstructions(asString(settings.data?.defaultPaymentInstructions, ''))
    setShowPaymentInstructions(true)
  }

  function resetAlamaLabels() {
    setAlamaLabels(normalizeWhatsappAlamaLabels(settings.data?.defaultAlamaLabels))
    setShowAlama(true)
  }

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
      <PageHeader title="Share List" description={activeEvent.event?.name ? `${activeEvent.event.name} WhatsApp list` : 'WhatsApp-ready event list'} action={<Link to={`/app/events/${eventId}`}><ArrowLeft size={18} aria-hidden /> Back</Link>} />
      <section className="share-summary-grid">
        <article>
          <span>Format</span>
          <strong>{selectedFormat?.label ?? effectiveFormat}</strong>
        </article>
        <article>
          <span>Members</span>
          <strong>{asNumber(data.memberCount)}</strong>
        </article>
        <article>
          <span>Characters</span>
          <strong>{asNumber(data.textLength)}</strong>
        </article>
        <article>
          <span>Parts</span>
          <strong>{Math.max(parts.length, text ? 1 : 0)}</strong>
        </article>
      </section>
      <section className="share-layout">
        <div className="share-controls">
          <article className="share-builder-card">
            <div className="share-section-heading">
              <div>
                <h2>List Format</h2>
                <p>{canFinancial ? 'Financial and privacy formats are available.' : 'Privacy-friendly format only.'}</p>
              </div>
              <StatusBadge tone={canFinancial ? 'success' : 'neutral'}>{canFinancial ? 'Financial' : 'Privacy'}</StatusBadge>
            </div>
            <div className="share-format-grid">
              {whatsappFormats.filter((item) => canFinancial || !isFinancialWhatsappFormat(item.value)).map((item) => (
                <button className={effectiveFormat === item.value ? 'share-format-option active' : 'share-format-option'} type="button" key={item.value} onClick={() => {
                  setFormat(item.value)
                  if (item.value === 'PRIVACY') setIncludeSummary(false)
                }}>
                  <strong>{item.label}</strong>
                  <span>{item.description}</span>
                </button>
              ))}
            </div>
          </article>
          <article className="share-builder-card">
            <div className="share-section-heading">
              <div>
                <h2>Filters</h2>
                <p>{statusFilter === 'ALL' ? 'All statuses' : statusFilter.replaceAll('_', ' ')}</p>
              </div>
            </div>
            <section className="share-filter-grid">
              <label>Status<select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>{whatsappStatuses.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
              <label>Category<select value={categoryId} onChange={(event) => setCategoryId(event.target.value)}><option value="">All categories</option>{categories.map((category) => <option key={asString(category.id)} value={asString(category.id)}>{asString(category.name)}</option>)}</select></label>
              <label>Sort<select value={effectiveSort} onChange={(event) => setSort(event.target.value)}>{whatsappSorts.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
              <label>Phone<select value={phoneFilter} onChange={(event) => setPhoneFilter(event.target.value)}><option value="ALL">All</option><option value="WITH_PHONE">Members with Phone</option><option value="WITHOUT_PHONE">Members without Phone</option></select></label>
              <label>Search<input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Member or code" /></label>
            </section>
            <label className="share-toggle-row"><input type="checkbox" checked={includeWithoutPledges} onChange={(event) => setIncludeWithoutPledges(event.target.checked)} /> <span><strong>Include registered members without pledges</strong><small>Marks members without pledges using 🙏🏿.</small></span></label>
          </article>
          <article className="share-builder-card">
            <div className="share-section-heading">
              <div>
                <h2>Options</h2>
                <p>{optionCount} enabled</p>
              </div>
            </div>
            <div className="share-toggle-grid">
              <label className="share-toggle-row"><input type="checkbox" checked={effectiveIncludeSummary} onChange={(event) => setIncludeSummary(event.target.checked)} disabled={effectiveFormat === 'PRIVACY' && !canFinancial} /> <span>Summary</span></label>
              <label className="share-toggle-row"><input type="checkbox" checked={effectiveIncludeEventDate} onChange={(event) => setIncludeEventDate(event.target.checked)} /> <span>Event Date</span></label>
            </div>
            <section className="share-editor-section">
              <div className="card-title-row">
                <strong>Payment Instructions</strong>
                {asString(settings.data?.defaultPaymentInstructions) ? <button type="button" onClick={resetPaymentInstructions}>Reset Payment Instructions</button> : null}
              </div>
              <label className="share-toggle-row"><input type="checkbox" checked={effectiveShowPaymentInstructions} onChange={(event) => setShowPaymentInstructions(event.target.checked)} /> <span>Show Payment Instructions</span></label>
              <label>Instructions<textarea value={effectivePaymentInstructions} onChange={(event) => setPaymentInstructions(event.target.value)} rows={4} placeholder="TUMA KWA&#10;JINA LA MPOKEAJI&#10;NAMBA AU AKAUNTI" /></label>
              {effectivePaymentInstructions ? <pre className="whatsapp-preview compact">{effectivePaymentInstructions}</pre> : null}
            </section>
            {canFinancial && effectiveFormat !== 'PRIVACY' ? (
              <section className="share-summary-builder">
                <div className="card-title-row">
                  <strong>Muhtasari</strong>
                  <div className="card-actions">
                    <button type="button" onClick={addSummaryRow}>Add Row</button>
                    <button type="button" onClick={resetSummaryRows}>Reset to Default</button>
                  </div>
                </div>
                {effectiveSummaryRows.map((row, index) => (
                  <div className="summary-row-editor" key={`${row.valueSource}-${index}`}>
                    <label>Label<input value={row.label} onChange={(event) => updateSummaryRow(index, { label: event.target.value })} /></label>
                    <label>Value Source<select value={row.valueSource} onChange={(event) => {
                      const source = summarySources.find((item) => item.valueSource === event.target.value)
                      updateSummaryRow(index, { valueSource: event.target.value, label: row.label || source?.label || event.target.value })
                    }}>{summarySources.map((source) => <option key={source.valueSource} value={source.valueSource}>{source.label}</option>)}</select></label>
                    <label>Visible<select value={row.visible ? 'YES' : 'NO'} onChange={(event) => updateSummaryRow(index, { visible: event.target.value === 'YES' })}><option value="YES">Visible</option><option value="NO">Hidden</option></select></label>
                    <label>Order<input type="number" min={1} value={row.order} onChange={(event) => updateSummaryRow(index, { order: Number(event.target.value) || index + 1 })} /></label>
                    <div className="card-actions">
                      <button type="button" disabled={index === 0} onClick={() => moveSummaryRow(index, -1)}>Up</button>
                      <button type="button" disabled={index === effectiveSummaryRows.length - 1} onClick={() => moveSummaryRow(index, 1)}>Down</button>
                    </div>
                  </div>
                ))}
              </section>
            ) : null}
            <section className="share-editor-section">
              <div className="card-title-row">
                <strong>Alama</strong>
                <button type="button" onClick={resetAlamaLabels}>Reset Alama to Default</button>
              </div>
              <label className="share-toggle-row"><input type="checkbox" checked={effectiveShowAlama} onChange={(event) => setShowAlama(event.target.checked)} /> <span>Show Alama</span></label>
              <div className="alama-grid">
                <label><span>✅✅</span><input value={effectiveAlamaLabels.completed} onChange={(event) => updateAlamaLabel('completed', event.target.value)} /></label>
                <label><span>☑️</span><input value={effectiveAlamaLabels.partial} onChange={(event) => updateAlamaLabel('partial', event.target.value)} /></label>
                <label><span>🙏🏿</span><input value={effectiveAlamaLabels.noPledge} onChange={(event) => updateAlamaLabel('noPledge', event.target.value)} /></label>
              </div>
            </section>
            {canFinancial ? (
              <div className="share-text-grid">
                <label>Header Text<textarea value={effectiveHeaderText} onChange={(event) => setHeaderText(event.target.value)} rows={3} placeholder={asString(settings.data?.defaultHeaderText)} /></label>
                <label>Footer Text<textarea value={effectiveFooterText} onChange={(event) => setFooterText(event.target.value)} rows={3} placeholder="Karibuni sana kwa michango na ahadi." /></label>
              </div>
            ) : null}
            {saveSettings.error ? <p className="field-error">{errorMessage(saveSettings.error, 'Share settings could not be saved.')}</p> : null}
            <div className="sheet-actions">
              {canFinancial ? <button type="button" onClick={() => { setHeaderText(''); setFooterText('') }}>Reset to Default</button> : null}
              <button className="primary-button" type="button" disabled={saveSettings.isPending} onClick={() => saveSettings.mutate()}>{saveSettings.isPending ? 'Saving...' : 'Save Settings'}</button>
            </div>
          </article>
        </div>
        <aside className="share-preview-panel">
          <div className="share-preview-header">
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
          {copyMessage ? <p className="share-copy-result">{copyMessage}</p> : null}
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
  const bulkSmsPreview = useQuery({
    queryKey: ['sms-bulk-preview', tenantId, eventId, 'BALANCE_REMINDER', selected],
    queryFn: async () => (await api.smsBulkPreview(tenantId ?? '', eventId, { templateCode: 'BALANCE_REMINDER', eventMemberIds: selected })).data,
    enabled: bulkPreview && selected.length > 0 && Boolean(tenantId && eventId),
  })
  const bulkPreviewRows = jsonArray(bulkSmsPreview.data?.previews)
  const validBulkPreviewRows = bulkPreviewRows.filter((preview) => preview.valid === true)
  const bulkMutation = useMutation({
    mutationFn: () => api.sendBulkBalanceReminders(tenantId ?? '', eventId, { eventMemberIds: validBulkPreviewRows.map((preview) => asString(jsonRecord(preview.member).eventMemberId)), idempotencyKey: bulkIdempotencyKey }),
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
      <DataTable
        title="Outstanding Members"
        rows={filtered}
        columns={[
          { key: 'member', header: 'Member', render: (row) => <Link to={`/app/events/${eventId}/members/${asString(row.eventMemberId)}`}><strong>{titleCaseMemberName(row.fullName, '')}</strong><small>{asString(row.memberCode)}</small></Link>, sortValue: (row) => titleCaseMemberName(row.fullName, '') },
          { key: 'phone', header: 'Phone', render: (row) => <span>{asString(row.phone, 'No phone')}</span>, sortValue: (row) => asString(row.phone) },
          { key: 'pledged', header: 'Pledged', render: (row) => <span>{moneyText(row.pledgedAmount)}</span>, sortValue: (row) => asNumber(row.pledgedAmount), align: 'right' },
          { key: 'paid', header: 'Paid', render: (row) => <span>{moneyText(row.totalPaid)}</span>, sortValue: (row) => asNumber(row.totalPaid), align: 'right' },
          { key: 'outstanding', header: 'Outstanding', render: (row) => <span>{moneyText(row.outstandingAmount)}</span>, sortValue: (row) => asNumber(row.outstandingAmount), align: 'right' },
          { key: 'due', header: 'Due', render: (row) => <span>{asDate(row.dueDate)}</span>, sortValue: (row) => asString(row.dueDate) },
          { key: 'days', header: 'Days Overdue', render: (row) => <span>{asNumber(row.daysOverdue)}</span>, sortValue: (row) => asNumber(row.daysOverdue), align: 'right' },
          { key: 'lastReminder', header: 'Last Reminder', render: (row) => <span>{reminderStatusText(row)}</span>, sortValue: (row) => asString(row.lastReminder) },
          { key: 'actions', header: 'Actions', render: (row) => {
            const eventMemberId = asString(row.eventMemberId)
            const eligible = canSendBalanceReminder(row)
            return <div className="inline-actions">{selectionMode ? <input aria-label={`Select ${titleCaseMemberName(row.fullName, 'member')}`} type="checkbox" disabled={!eligible} checked={selected.includes(eventMemberId)} onChange={(event) => setSelected((current) => event.target.checked ? [...current, eventMemberId] : current.filter((id) => id !== eventMemberId))} /> : null}{permissions.has('messages.send') && eligible ? <button type="button" onClick={() => setSingleMember(row)}>SMS</button> : null}<Link to={`/app/events/${eventId}/members/${eventMemberId}`}>View</Link></div>
          }, align: 'right' },
        ]}
        getRowKey={(row) => asString(row.eventMemberId)}
        emptyTitle={rows.length ? 'No members match these filters.' : 'No outstanding balances.'}
        emptyMessage={rows.length ? 'Change the filter or search text.' : 'Members with unpaid pledge balances will appear here.'}
      />
      {selectionMode && selected.length ? <div className="mobile-action-bar"><button type="button" onClick={() => setBulkPreview(true)}>Send Reminders ({selected.length})</button></div> : null}
      {singleMember ? <BalanceReminderSheet tenantId={tenantId ?? ''} eventId={eventId} member={singleMember} onClose={() => setSingleMember(null)} onSent={() => { setSingleMember(null); void outstanding.refetch() }} /> : null}
      {bulkPreview ? <section className="mobile-sheet form-grid">
        <h2>Review Reminders</h2>
        <ReviewLine label="Selected" value={String(selectedRows.length)} />
        <ReviewLine label="Eligible" value={String(asNumber(bulkSmsPreview.data?.eligible) || eligibleSelected.length)} />
        <ReviewLine label="Ready" value={String(asNumber(bulkSmsPreview.data?.validMessages))} />
        <ReviewLine label="Too Long" value={String(asNumber(bulkSmsPreview.data?.overCharacterLimit))} />
        <ReviewLine label="No Phone" value={String(asNumber(bulkSmsPreview.data?.noPhone) || skipped.noPhone)} />
        <ReviewLine label="SMS Disabled" value={String(asNumber(bulkSmsPreview.data?.smsDisabled) || skipped.smsDisabled)} />
        <ReviewLine label="Recently Sent" value={String(asNumber(bulkSmsPreview.data?.recentlySent) || skipped.recentlySent)} />
        <ReviewLine label="Estimated SMS" value={String(validBulkPreviewRows.length)} />
        {bulkSmsPreview.isLoading ? <LoadingState title="Generating bulk SMS preview" /> : null}
        {bulkSmsPreview.error ? <p className="field-error">{errorMessage(bulkSmsPreview.error, 'Bulk SMS preview could not be generated.')}</p> : null}
        <div className="finance-card-list">{bulkPreviewRows.map((preview) => {
          const member = jsonRecord(preview.member)
          return <article className="content-panel" key={asString(member.eventMemberId)}><div className="panel-header"><div><h3>{titleCaseMemberName(member.name)}</h3><p>{asString(member.phoneMasked, 'No phone')}</p></div><SmsCharacterCounter preview={preview} /></div><p>{asString(preview.message)}</p></article>
        })}</div>
        {bulkMutation.data ? <p className="privacy-note">Queued: {asString(bulkMutation.data.data.queued)} · Batch {asString(bulkMutation.data.data.batchId)}</p> : null}
        {bulkMutation.error ? <p className="field-error">{errorMessage(bulkMutation.error, 'Bulk reminders could not be queued.')}</p> : null}
        <div className="sheet-actions"><button type="button" onClick={() => setBulkPreview(false)}>Back</button><button className="primary-button" type="button" disabled={!validBulkPreviewRows.length || bulkMutation.isPending || bulkSmsPreview.isLoading} onClick={() => bulkMutation.mutate()}>{bulkMutation.isPending ? 'Queueing...' : `Send ${validBulkPreviewRows.length} SMS`}</button></div>
      </section> : null}
    </PageContainer>
  )
}

export function SmsHistoryPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const eventOptions = session.selectedTenantContext?.events ?? []
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()
  const canSendMessages = permissions.has('messages.send')
  const requestedEventId = searchParams.get('eventId')
  const preferredMessageEventId = requestedEventId ?? session.selectedEventId
  const eventId = preferredMessageEventId && eventOptions.some((event) => event.id === preferredMessageEventId) ? preferredMessageEventId : 'ALL'
  const [status, setStatus] = useState('ALL')
  const [type, setType] = useState('ALL')
  const [query, setQuery] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [pledgeRequestOpen, setPledgeRequestOpen] = useState(searchParams.get('segment') === 'pledge-request')
  const [balanceReminderOpen, setBalanceReminderOpen] = useState(searchParams.get('segment') === 'balance-reminder' || searchParams.get('segment') === 'reminders')
  const [completedPledgeOpen, setCompletedPledgeOpen] = useState(searchParams.get('segment') === 'completed-pledges' || searchParams.get('segment') === 'pledge-completed')
  function handleMessageEventFilter(value: string) {
    const nextParams = new URLSearchParams(searchParams)
    if (value !== 'ALL') {
      session.selectEvent(value)
      nextParams.set('eventId', value)
    } else {
      nextParams.delete('eventId')
    }
    setSearchParams(nextParams, { replace: true })
  }
  const messages = useQuery({ queryKey: ['sms-history', tenantId], queryFn: async () => (await api.messages(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const processQueued = useMutation({
    mutationFn: () => api.processQueuedMessages(tenantId ?? '', 25),
    onSuccess: () => void messages.refetch(),
  })
  const workerDiagnostics = jsonRecord(processQueued.data?.data.diagnostics)
  const blockedCounts = jsonRecord(workerDiagnostics.blockedCounts)
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
  const activeEvent = session.selectedEventId ? eventOptions.find((event) => event.id === session.selectedEventId) ?? eventOptions[0] ?? null : eventOptions[0] ?? null
  const messageActionEventId = eventId !== 'ALL' ? eventId : activeEvent?.id
  const messageActionEvent = eventOptions.find((event) => event.id === messageActionEventId) ?? activeEvent ?? null

  if (!tenantId) return <ErrorState title="Unable to load SMS history" message="Select a tenant first." />
  if (messages.isLoading) return <LoadingState title="Loading messages" message="Fetching SMS confirmation history." />
  if (messages.isError) return <ErrorState title="Unable to load messages" message={errorMessage(messages.error, 'SMS history could not be loaded.')} />

  return (
    <PageContainer>
      <PageHeader
        title="Messages"
        description="SMS delivery history and balance reminder controls for this tenant."
        action={<div className="inline-actions">{canSendMessages ? <button type="button" disabled={processQueued.isPending || queuedCount === 0} onClick={() => processQueued.mutate()}><Send size={18} aria-hidden /> {processQueued.isPending ? 'Sending...' : 'Send queued'}</button> : null}{canSendMessages && messageActionEventId ? <button className="desktop-primary-button" type="button" onClick={() => setBalanceReminderOpen((current) => !current)}><Clock3 size={18} aria-hidden /> Reminders</button> : null}</div>}
      />
      <MessagesSubnav />
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
      {processQueued.data ? (
        <p className="message-send-result">
          Worker queue check accepted · Claimable {displayValue(workerDiagnostics.claimableCount, '0')} · Processing {displayValue(blockedCounts.processingNow, '0')} · Stale {displayValue(blockedCounts.staleProcessing, '0')} · Blocked sender {displayValue(blockedCounts.inactiveSenderId, '0')}
        </p>
      ) : null}
      {processQueued.error ? <p className="field-error">Unable to process queued messages: {errorMessage(processQueued.error, 'Send attempt failed.')}</p> : null}
      {messageActionEventId ? (
        <section className="content-panel pledge-request-summary">
          <div className="panel-header">
            <div>
              <h2>Completed Pledge SMS</h2>
              <p>{messageActionEvent?.name ?? 'Selected event'} · select paid members and preview the completion SMS before queueing.</p>
            </div>
            {canSendMessages ? <button className="primary-button inline-action" type="button" onClick={() => setCompletedPledgeOpen((current) => !current)}>{completedPledgeOpen ? 'Hide Selection' : 'Send Completed SMS'}</button> : null}
          </div>
          {completedPledgeOpen && canSendMessages ? <CompletedPledgeSelection tenantId={tenantId} eventId={messageActionEventId} eventName={messageActionEvent?.name ?? 'Event'} onQueued={() => { void messages.refetch(); void queryClient.invalidateQueries({ queryKey: ['completed-pledge-members', tenantId, messageActionEventId] }) }} /> : null}
        </section>
      ) : null}
      {messageActionEventId ? (
        <section className="content-panel pledge-request-summary">
          <div className="panel-header">
            <div>
              <h2>Outstanding SMS Reminders</h2>
              <p>{messageActionEvent?.name ?? 'Selected event'} · select one member or all ready members, then preview the SMS before queueing.</p>
            </div>
            {canSendMessages ? <button className="primary-button inline-action" type="button" onClick={() => setBalanceReminderOpen((current) => !current)}>{balanceReminderOpen ? 'Hide Selection' : 'Send Reminder SMS'}</button> : null}
          </div>
          {balanceReminderOpen && canSendMessages ? <BalanceReminderSelection tenantId={tenantId} eventId={messageActionEventId} eventName={messageActionEvent?.name ?? 'Event'} onQueued={() => { void messages.refetch(); void queryClient.invalidateQueries({ queryKey: ['event-outstanding-members', tenantId, messageActionEventId] }) }} /> : null}
        </section>
      ) : null}
      {messageActionEventId ? (
        <section className="content-panel pledge-request-summary">
          <div className="panel-header">
            <div>
              <h2>Members Without Pledge</h2>
              <p>{messageActionEvent?.name ?? 'Selected event'} · request pledges without mixing them into outstanding balances.</p>
            </div>
            {canSendMessages ? <button className="primary-button inline-action" type="button" onClick={() => setPledgeRequestOpen((current) => !current)}>{pledgeRequestOpen ? 'Hide Selection' : 'Send Pledge Request'}</button> : null}
          </div>
          {pledgeRequestOpen && canSendMessages ? <PledgeRequestSelection tenantId={tenantId} eventId={messageActionEventId} eventName={messageActionEvent?.name ?? 'Event'} onQueued={() => { void messages.refetch(); void queryClient.invalidateQueries({ queryKey: ['no-pledge-members', tenantId, messageActionEventId] }) }} /> : null}
        </section>
      ) : null}
      <div className="messages-layout">
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
              <label>Event<select value={eventId} onChange={(event) => handleMessageEventFilter(event.target.value)}><option value="ALL">All events</option>{eventOptions.map((event) => <option key={event.id} value={event.id}>{event.name}</option>)}</select></label>
              <label>From<input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
              <label>To<input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} /></label>
            </div>
          </div>
          <div className="messages-list">
            <DataTable
              title="Message History"
              rows={filtered}
              columns={[
                { key: 'date', header: 'Date', render: (message) => <span>{asDateTime(message.created_at)}</span>, sortValue: (message) => asString(message.created_at) },
                { key: 'member', header: 'Member', render: (message) => <strong>{titleCaseMemberName(message.member_name, 'Recipient')}</strong>, sortValue: (message) => titleCaseMemberName(message.member_name, '') },
                { key: 'event', header: 'Event', render: (message) => <span>{asString(message.event_name, 'No event')}</span>, sortValue: (message) => asString(message.event_name) },
                { key: 'template', header: 'Template', render: (message) => <span>{asString(message.template_code, 'Message')}</span>, sortValue: (message) => asString(message.template_code) },
                { key: 'provider', header: 'Provider', render: (message) => <span>{asString(message.provider, 'SMS')}</span>, sortValue: (message) => asString(message.provider) },
                { key: 'sender', header: 'Sender ID', render: (message) => <span>{asString(message.sender_id, 'MICHANGO')}</span>, sortValue: (message) => asString(message.sender_id) },
                { key: 'characters', header: 'Characters', render: (message) => <span>{asNumber(message.character_count)}</span>, sortValue: (message) => asNumber(message.character_count), align: 'right' },
                { key: 'status', header: 'Status', render: (message) => <StatusBadge tone={statusTone(message.status)}>{asString(message.status, 'QUEUED')}</StatusBadge>, sortValue: (message) => asString(message.status) },
                { key: 'actions', header: 'Actions', render: (message) => <MessageTableActions message={message} tenantId={tenantId} canResend={canSendMessages} onResent={() => void messages.refetch()} />, align: 'right' },
              ]}
              getRowKey={(message) => asString(message.id)}
              emptyTitle={rows.length ? 'No messages match these filters.' : 'No SMS messages yet.'}
              emptyMessage={rows.length ? 'Change the status, event, or search text.' : 'Payment confirmations will appear here after payments are recorded.'}
              mobileRender={(message) => <MessageHistoryCard message={message} tenantId={tenantId} canResend={canSendMessages} onResent={() => void messages.refetch()} />}
            />
          </div>
        </section>
      </div>
    </PageContainer>
  )
}

function MessagesSubnav() {
  return (
    <nav className="messages-subnav" aria-label="Messages navigation">
      <NavLink to="/app/messages" end>Message History</NavLink>
      <NavLink to="/app/messages/templates">Templates</NavLink>
      <NavLink to="/app/messages/settings">Settings</NavLink>
    </nav>
  )
}

export function SmsTemplatesPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const queryClient = useQueryClient()
  const canManageTemplates = permissions.has('messages.manage_templates')
  const templates = useQuery({ queryKey: ['sms-templates', tenantId], queryFn: async () => (await api.smsTemplates(tenantId ?? '')).data, enabled: Boolean(tenantId && canManageTemplates) })

  if (!tenantId) return <ErrorState title="Unable to load SMS templates" message="Select a tenant first." />
  if (!canManageTemplates) return <ErrorState title="SMS templates unavailable" message="You do not have permission to manage message templates." />

  return (
    <PageContainer>
      <PageHeader title="Message Templates" description="Tenant overrides for supported pledge and payment SMS templates." />
      <MessagesSubnav />
      <SmsTemplateManager tenantId={tenantId} templates={templates.data ?? []} loading={templates.isLoading} onSaved={() => void queryClient.invalidateQueries({ queryKey: ['sms-templates', tenantId] })} />
      {templates.isError ? <p className="field-error">{errorMessage(templates.error, 'SMS templates could not be loaded.')}</p> : null}
    </PageContainer>
  )
}

export function SmsSettingsPage() {
  const session = useSessionStore()
  const tenantId = session.selectedTenantId
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const queryClient = useQueryClient()
  const canManageSettings = permissions.has('messages.manage_settings')
  const settings = useQuery({ queryKey: ['sms-settings', tenantId], queryFn: async () => (await api.smsSettings(tenantId ?? '')).data, enabled: Boolean(tenantId && canManageSettings) })

  if (!tenantId) return <ErrorState title="Unable to load SMS settings" message="Select a tenant first." />
  if (!canManageSettings) return <ErrorState title="SMS settings unavailable" message="You do not have permission to manage message settings." />

  return (
    <PageContainer>
      <PageHeader title="Message Settings" description="Tenant-level SMS status, provider, and Sender ID preferences." />
      <MessagesSubnav />
      <SmsSettingsPanel key={`${String(settings.data?.smsEnabled)}-${asString(settings.data?.provider, 'NEXTSMS')}-${asString(settings.data?.senderId, 'MICHANGO')}`} tenantId={tenantId} settings={settings.data ?? null} loading={settings.isLoading} onSaved={() => void queryClient.invalidateQueries({ queryKey: ['sms-settings', tenantId] })} />
      {settings.isError ? <p className="field-error">{errorMessage(settings.error, 'SMS settings could not be loaded.')}</p> : null}
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

function balanceReminderEligibility(row: Row) {
  const reason = asString(row.ineligibleReason)
  if (!reason) return { label: 'Ready', tone: 'success' as const }
  if (reason === 'NO_PHONE') return { label: 'No Phone', tone: 'danger' as const }
  if (reason === 'SMS_DISABLED') return { label: 'SMS Disabled', tone: 'warning' as const }
  if (reason === 'RECENTLY_SENT') return { label: 'Recently Sent', tone: 'warning' as const }
  if (reason === 'NO_OUTSTANDING') return { label: 'No Outstanding', tone: 'neutral' as const }
  return { label: reason.replaceAll('_', ' '), tone: 'neutral' as const }
}

function completedPledgeEligibility(row: Row) {
  const reason = asString(row.ineligibleReason)
  if (reason === 'NO_PHONE') return { label: 'No Phone', tone: 'danger' as const }
  if (reason === 'SMS_DISABLED') return { label: 'SMS Disabled', tone: 'warning' as const }
  if (reason === 'RECENTLY_SENT') return { label: 'Sent Before', tone: 'warning' as const }
  if (reason === 'NO_COMPLETED_PLEDGE') return { label: 'Not Completed', tone: 'neutral' as const }
  if (asString(row.lastCompletedPledgeSmsAt)) return { label: 'Sent Before', tone: 'warning' as const }
  return { label: 'Ready', tone: 'success' as const }
}

function BalanceReminderSelection({ tenantId, eventId, eventName, onQueued }: { tenantId: string; eventId: string; eventName: string; onQueued: () => void }) {
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('ALL')
  const [filter, setFilter] = useState('ALL')
  const [selected, setSelected] = useState<string[]>([])
  const [previewOpen, setPreviewOpen] = useState(false)
  const [idempotencyKey, resetIdempotencyKey] = useState(() => crypto.randomUUID())
  const members = useQuery({ queryKey: ['event-outstanding-members', tenantId, eventId], queryFn: async () => (await api.eventOutstandingMembers(tenantId, eventId)).data, enabled: Boolean(tenantId && eventId) })
  const rows = members.data ?? []
  const categories = Array.from(new Set(rows.map((row) => asString(row.category, 'No category')))).sort()
  const filtered = rows.filter((row) => {
    const queryMatches = `${row.fullName ?? ''} ${row.memberCode ?? ''} ${row.phone ?? ''}`.toLowerCase().includes(query.toLowerCase())
    const categoryMatches = category === 'ALL' || asString(row.category, 'No category') === category
    const reason = asString(row.ineligibleReason, '')
    const filterMatches =
      filter === 'ALL' ||
      (filter === 'OVERDUE' && asNumber(row.daysOverdue) > 0) ||
      (filter === 'DUE_SOON' && row.isDueSoon === true) ||
      (filter === 'PARTIAL' && row.pledgeStatus === 'PARTIALLY_PAID') ||
      (filter === 'UNPAID' && row.pledgeStatus === 'PENDING') ||
      (filter === 'SMS_AVAILABLE' && !reason) ||
      (filter === 'SMS_DISABLED' && reason === 'SMS_DISABLED')
    return queryMatches && categoryMatches && filterMatches
  })
  const eligibleVisible = filtered.filter(canSendBalanceReminder)
  const selectedRows = rows.filter((row) => selected.includes(asString(row.eventMemberId)))
  const eligibleSelected = selectedRows.filter(canSendBalanceReminder)
  const skipped = {
    noPhone: selectedRows.filter((row) => asString(row.ineligibleReason) === 'NO_PHONE').length,
    smsDisabled: selectedRows.filter((row) => asString(row.ineligibleReason) === 'SMS_DISABLED').length,
    recentlySent: selectedRows.filter((row) => asString(row.ineligibleReason) === 'RECENTLY_SENT').length,
    noOutstanding: selectedRows.filter((row) => asString(row.ineligibleReason) === 'NO_OUTSTANDING').length,
  }
  const bulkPreview = useQuery({
    queryKey: ['sms-bulk-preview', tenantId, eventId, 'BALANCE_REMINDER', 'messages-page', selected],
    queryFn: async () => (await api.smsBulkPreview(tenantId, eventId, { templateCode: 'BALANCE_REMINDER', eventMemberIds: selected })).data,
    enabled: previewOpen && selected.length > 0,
  })
  const previewRows = jsonArray(bulkPreview.data?.previews)
  const validPreviewRows = previewRows.filter((preview) => preview.valid === true)
  const mutation = useMutation({
    mutationFn: () => api.sendBulkBalanceReminders(tenantId, eventId, { eventMemberIds: validPreviewRows.map((preview) => asString(jsonRecord(preview.member).eventMemberId)), idempotencyKey }),
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
  const totalOutstanding = rows.reduce((sum, row) => sum + asNumber(row.outstandingAmount), 0)

  if (members.isLoading) return <LoadingState title="Loading outstanding members" />
  if (members.isError) return <ErrorState title="Unable to load outstanding members" message={errorMessage(members.error, 'Outstanding members could not be loaded.')} />

  return (
    <div className="pledge-request-panel">
      <div className="messages-filter-grid">
        <label>Search<input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name, phone or member code" /></label>
        <label>Category<select value={category} onChange={(event) => setCategory(event.target.value)}><option value="ALL">All categories</option>{categories.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
        <label>Filter<select value={filter} onChange={(event) => setFilter(event.target.value)}>{['ALL', 'OVERDUE', 'DUE_SOON', 'PARTIAL', 'UNPAID', 'SMS_AVAILABLE', 'SMS_DISABLED'].map((item) => <option key={item} value={item}>{item.replaceAll('_', ' ')}</option>)}</select></label>
      </div>
      <div className="mini-stat-row">
        <span>{rows.length} outstanding</span>
        <span>{moneyText(totalOutstanding)} total</span>
        <span>{eligibleVisible.length} ready visible</span>
        <span>{selected.length} selected</span>
      </div>
      <div className="inline-actions">
        <button type="button" onClick={selectAllVisible} disabled={!eligibleVisible.length}>Select All Ready</button>
        <button type="button" onClick={() => setSelected([])} disabled={!selected.length}>Clear</button>
        <button className="primary-button" type="button" onClick={() => setPreviewOpen(true)} disabled={!eligibleSelected.length}>Preview Reminders ({eligibleSelected.length})</button>
      </div>
      <div className="finance-card-list">
        {filtered.map((row) => {
          const eventMemberId = asString(row.eventMemberId)
          const eligibility = balanceReminderEligibility(row)
          const eligible = canSendBalanceReminder(row)
          return (
            <article className="finance-card pledge-request-card" key={eventMemberId}>
              <label className="checkbox-line">
                <input type="checkbox" checked={selected.includes(eventMemberId)} disabled={!eligible} onChange={() => toggle(eventMemberId)} />
                <span><strong>{titleCaseMemberName(row.fullName)}</strong><small>{maskPhone(row.phone)} · {asString(row.category, 'No category')} · {asString(row.memberCode)}</small></span>
              </label>
              <div className="amount-triplet">
                <span><small>Pledged</small>{moneyText(row.pledgedAmount)}</span>
                <span><small>Paid</small>{moneyText(row.totalPaid)}</span>
                <span><small>Outstanding</small>{moneyText(row.outstandingAmount)}</span>
              </div>
              <div className="card-title-row">
                <span>Due {asDate(row.dueDate)} · Last reminder: {reminderStatusText(row)}</span>
                <StatusBadge tone={eligibility.tone}>{eligibility.label}</StatusBadge>
              </div>
            </article>
          )
        })}
        {!rows.length ? <EmptyState title="No outstanding balances." message="Members with unpaid pledge balances will appear here." /> : null}
        {rows.length > 0 && !filtered.length ? <EmptyState title="No members match these filters." message="Try another name, category, or reminder status." /> : null}
      </div>
      {previewOpen ? <section className="mobile-sheet form-grid">
        <h2>Review Reminder SMS</h2>
        <ReviewLine label="Event" value={eventName} />
        <ReviewLine label="Selected" value={String(selectedRows.length)} />
        <ReviewLine label="Eligible" value={String(asNumber(bulkPreview.data?.eligible) || eligibleSelected.length)} />
        <ReviewLine label="Ready" value={String(asNumber(bulkPreview.data?.validMessages))} />
        <ReviewLine label="Too Long" value={String(asNumber(bulkPreview.data?.overCharacterLimit))} />
        <ReviewLine label="No Phone" value={String(asNumber(bulkPreview.data?.noPhone) || skipped.noPhone)} />
        <ReviewLine label="SMS Disabled" value={String(asNumber(bulkPreview.data?.smsDisabled) || skipped.smsDisabled)} />
        <ReviewLine label="Recently Sent" value={String(asNumber(bulkPreview.data?.recentlySent) || skipped.recentlySent)} />
        <ReviewLine label="No Outstanding" value={String(asNumber(bulkPreview.data?.noOutstanding) || skipped.noOutstanding)} />
        <ReviewLine label="Estimated SMS" value={String(validPreviewRows.length)} />
        {bulkPreview.isLoading ? <LoadingState title="Generating reminder SMS preview" /> : null}
        {bulkPreview.error ? <p className="field-error">{errorMessage(bulkPreview.error, 'Reminder SMS preview could not be generated.')}</p> : null}
        <div className="finance-card-list">{previewRows.map((preview) => {
          const member = jsonRecord(preview.member)
          return <article className="content-panel" key={asString(member.eventMemberId)}><div className="panel-header"><div><h3>{titleCaseMemberName(member.name)}</h3><p>{asString(member.phoneMasked, 'No phone')}</p></div><SmsCharacterCounter preview={preview} /></div><p>{asString(preview.message)}</p></article>
        })}</div>
        {mutation.data ? <p className="privacy-note">Queued: {asString(mutation.data.data.queued)} · Batch {asString(mutation.data.data.batchId)}</p> : null}
        {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Reminder SMS could not be queued.')}</p> : null}
        <div className="sheet-actions"><button type="button" onClick={() => setPreviewOpen(false)}>Cancel</button><button className="primary-button" type="button" disabled={!validPreviewRows.length || mutation.isPending || bulkPreview.isLoading} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : `Send ${validPreviewRows.length} SMS`}</button></div>
      </section> : null}
    </div>
  )
}

function CompletedPledgeSelection({ tenantId, eventId, eventName, onQueued }: { tenantId: string; eventId: string; eventName: string; onQueued: () => void }) {
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('ALL')
  const [selected, setSelected] = useState<string[]>([])
  const [previewOpen, setPreviewOpen] = useState(false)
  const [idempotencyKey, resetIdempotencyKey] = useState(() => crypto.randomUUID())
  const members = useQuery({ queryKey: ['completed-pledge-members', tenantId, eventId], queryFn: async () => (await api.eventCompletedPledgeMembers(tenantId, eventId)).data, enabled: Boolean(tenantId && eventId) })
  const rows = members.data ?? []
  const categories = Array.from(new Set(rows.map((row) => asString(row.category, 'No category')))).sort()
  const filtered = rows.filter((row) => {
    const queryMatches = `${row.fullName ?? ''} ${row.memberCode ?? ''} ${row.phone ?? ''}`.toLowerCase().includes(query.toLowerCase())
    const categoryMatches = category === 'ALL' || asString(row.category, 'No category') === category
    return queryMatches && categoryMatches
  })
  const eligibleVisible = filtered.filter(canSendCompletedPledgeSms)
  const selectedRows = rows.filter((row) => selected.includes(asString(row.eventMemberId)))
  const eligibleSelected = selectedRows.filter(canSendCompletedPledgeSms)
  const skipped = {
    noPhone: selectedRows.filter((row) => asString(row.ineligibleReason) === 'NO_PHONE').length,
    smsDisabled: selectedRows.filter((row) => asString(row.ineligibleReason) === 'SMS_DISABLED').length,
    noCompletedPledge: selectedRows.filter((row) => asString(row.ineligibleReason) === 'NO_COMPLETED_PLEDGE').length,
  }
  const bulkPreview = useQuery({
    queryKey: ['sms-bulk-preview', tenantId, eventId, 'PLEDGE_COMPLETED', 'messages-page', selected],
    queryFn: async () => (await api.smsBulkPreview(tenantId, eventId, { templateCode: 'PLEDGE_COMPLETED', eventMemberIds: selected })).data,
    enabled: previewOpen && selected.length > 0,
  })
  const previewRows = jsonArray(bulkPreview.data?.previews)
  const validPreviewRows = previewRows.filter((preview) => preview.valid === true)
  const mutation = useMutation({
    mutationFn: () => api.sendBulkCompletedPledgeSms(tenantId, eventId, { eventMemberIds: validPreviewRows.map((preview) => asString(jsonRecord(preview.member).eventMemberId)), idempotencyKey }),
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
  const totalPaid = rows.reduce((sum, row) => sum + asNumber(row.totalPaid), 0)

  if (members.isLoading) return <LoadingState title="Loading completed pledges" />
  if (members.isError) return <ErrorState title="Unable to load completed pledges" message={errorMessage(members.error, 'Completed pledge members could not be loaded.')} />

  return (
    <div className="pledge-request-panel">
      <div className="messages-filter-grid">
        <label>Search<input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name, phone or member code" /></label>
        <label>Category<select value={category} onChange={(event) => setCategory(event.target.value)}><option value="ALL">All categories</option>{categories.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
      </div>
      <div className="mini-stat-row">
        <span>{rows.length} completed</span>
        <span>{moneyText(totalPaid)} collected</span>
        <span>{eligibleVisible.length} ready visible</span>
        <span>{selected.length} selected</span>
      </div>
      <div className="inline-actions">
        <button type="button" onClick={selectAllVisible} disabled={!eligibleVisible.length}>Select All Ready</button>
        <button type="button" onClick={() => setSelected([])} disabled={!selected.length}>Clear</button>
        <button className="primary-button" type="button" onClick={() => setPreviewOpen(true)} disabled={!eligibleSelected.length}>Preview Completed SMS ({eligibleSelected.length})</button>
      </div>
      <div className="finance-card-list">
        {filtered.map((row) => {
          const eventMemberId = asString(row.eventMemberId)
          const eligibility = completedPledgeEligibility(row)
          const eligible = canSendCompletedPledgeSms(row)
          return (
            <article className="finance-card pledge-request-card" key={eventMemberId}>
              <label className="checkbox-line">
                <input type="checkbox" checked={selected.includes(eventMemberId)} disabled={!eligible} onChange={() => toggle(eventMemberId)} />
                <span><strong>{titleCaseMemberName(row.fullName)}</strong><small>{asString(row.maskedPhone, maskPhone(row.phone))} · {asString(row.category, 'No category')} · {asString(row.memberCode)}</small></span>
              </label>
              <div className="amount-triplet">
                <span><small>Pledged</small>{moneyText(row.pledgedAmount)}</span>
                <span><small>Paid</small>{moneyText(row.totalPaid)}</span>
                <span><small>Completed</small>{asDateTime(row.completedAt)}</span>
              </div>
              <div className="card-title-row">
                <span>Last completed SMS: {asDateTime(row.lastCompletedPledgeSmsAt)}</span>
                <StatusBadge tone={eligibility.tone}>{eligibility.label}</StatusBadge>
              </div>
            </article>
          )
        })}
        {!rows.length ? <EmptyState title="No completed pledges." message="Members whose pledges are fully paid will appear here." /> : null}
        {rows.length > 0 && !filtered.length ? <EmptyState title="No completed pledges match these filters." message="Try another name or category." /> : null}
      </div>
      {previewOpen ? <section className="mobile-sheet form-grid">
        <h2>Review Completed Pledge SMS</h2>
        <ReviewLine label="Event" value={eventName} />
        <ReviewLine label="Selected" value={String(selectedRows.length)} />
        <ReviewLine label="Eligible" value={String(asNumber(bulkPreview.data?.eligible) || eligibleSelected.length)} />
        <ReviewLine label="Ready" value={String(asNumber(bulkPreview.data?.validMessages))} />
        <ReviewLine label="Too Long" value={String(asNumber(bulkPreview.data?.overCharacterLimit))} />
        <ReviewLine label="No Phone" value={String(asNumber(bulkPreview.data?.noPhone) || skipped.noPhone)} />
        <ReviewLine label="SMS Disabled" value={String(asNumber(bulkPreview.data?.smsDisabled) || skipped.smsDisabled)} />
        <ReviewLine label="No Completed Pledge" value={String(asNumber(bulkPreview.data?.noCompletedPledge) || skipped.noCompletedPledge)} />
        <ReviewLine label="Estimated SMS" value={String(validPreviewRows.length)} />
        {bulkPreview.isLoading ? <LoadingState title="Generating completed pledge SMS preview" /> : null}
        {bulkPreview.error ? <p className="field-error">{errorMessage(bulkPreview.error, 'Completed pledge SMS preview could not be generated.')}</p> : null}
        <div className="finance-card-list">{previewRows.map((preview) => {
          const member = jsonRecord(preview.member)
          return <article className="content-panel" key={asString(member.eventMemberId)}><div className="panel-header"><div><h3>{titleCaseMemberName(member.name)}</h3><p>{asString(member.phoneMasked, 'No phone')}</p></div><SmsCharacterCounter preview={preview} /></div><p>{asString(preview.message)}</p></article>
        })}</div>
        {mutation.data ? <p className="privacy-note">Queued: {asString(mutation.data.data.queued)} · Batch {asString(mutation.data.data.batchId)}</p> : null}
        {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Completed pledge SMS could not be queued.')}</p> : null}
        <div className="sheet-actions"><button type="button" onClick={() => setPreviewOpen(false)}>Cancel</button><button className="primary-button" type="button" disabled={!validPreviewRows.length || mutation.isPending || bulkPreview.isLoading} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : `Send ${validPreviewRows.length} SMS`}</button></div>
      </section> : null}
    </div>
  )
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
  const bulkPreview = useQuery({
    queryKey: ['sms-bulk-preview', tenantId, eventId, 'PLEDGE_REQUEST', selected],
    queryFn: async () => (await api.smsBulkPreview(tenantId, eventId, { templateCode: 'PLEDGE_REQUEST', eventMemberIds: selected })).data,
    enabled: previewOpen && selected.length > 0,
  })
  const previewRows = jsonArray(bulkPreview.data?.previews)
  const validPreviewRows = previewRows.filter((preview) => preview.valid === true)
  const mutation = useMutation({
    mutationFn: () => api.sendBulkPledgeRequests(tenantId, eventId, { eventMemberIds: validPreviewRows.map((preview) => asString(jsonRecord(preview.member).eventMemberId)), idempotencyKey }),
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
                <span><strong>{titleCaseMemberName(row.fullName)}</strong><small>{asString(row.maskedPhone, maskPhone(row.phone))} · {asString(row.category, 'No category')}</small></span>
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
        <ReviewLine label="Eligible" value={String(asNumber(bulkPreview.data?.eligible) || eligibleSelected.length)} />
        <ReviewLine label="Ready" value={String(asNumber(bulkPreview.data?.validMessages))} />
        <ReviewLine label="Too Long" value={String(asNumber(bulkPreview.data?.overCharacterLimit))} />
        <ReviewLine label="No Phone" value={String(asNumber(bulkPreview.data?.noPhone) || skipped.noPhone)} />
        <ReviewLine label="SMS Disabled" value={String(asNumber(bulkPreview.data?.smsDisabled) || skipped.smsDisabled)} />
        <ReviewLine label="Recently Sent" value={String(asNumber(bulkPreview.data?.recentlySent) || skipped.recentlySent)} />
        <ReviewLine label="Has Pledge" value={String(asNumber(bulkPreview.data?.hasPledge) || skipped.hasPledge)} />
        <ReviewLine label="Estimated SMS" value={String(validPreviewRows.length)} />
        {bulkPreview.isLoading ? <LoadingState title="Generating bulk SMS preview" /> : null}
        {bulkPreview.error ? <p className="field-error">{errorMessage(bulkPreview.error, 'Bulk SMS preview could not be generated.')}</p> : null}
        <div className="finance-card-list">{previewRows.map((preview) => {
          const member = jsonRecord(preview.member)
          return <article className="content-panel" key={asString(member.eventMemberId)}><div className="panel-header"><div><h3>{titleCaseMemberName(member.name)}</h3><p>{asString(member.phoneMasked, 'No phone')}</p></div><SmsCharacterCounter preview={preview} /></div><p>{asString(preview.message)}</p></article>
        })}</div>
        {mutation.data ? <p className="privacy-note">Queued: {asString(mutation.data.data.queued)} · Allowed: {asString(mutation.data.data.allowedBySmsBalance, 'unlimited')} · Batch {asString(mutation.data.data.batchId)}</p> : null}
        {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'Pledge requests could not be queued.')}</p> : null}
        <div className="sheet-actions"><button type="button" onClick={() => setPreviewOpen(false)}>Cancel</button><button className="primary-button" type="button" disabled={!validPreviewRows.length || mutation.isPending || bulkPreview.isLoading} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Queueing...' : `Send ${validPreviewRows.length} SMS`}</button></div>
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
            <strong>{titleCaseMemberName(message.member_name, 'Recipient')}</strong>
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
          <span><small>Characters</small>{asNumber(message.character_count)} / {asNumber(message.max_characters_at_send)}</span>
          <span><small>Attempts</small>{String(asNumber(message.attempt_count))}</span>
        </div>
        {preview ? <p className="message-preview">{preview}</p> : null}
        {failed || cancelled ? <div className="message-error-callout"><strong>{cancelled ? 'Cancelled' : asString(message.last_error_code, 'Delivery failed')}</strong><span>{cancelled ? asString(message.last_error_message, 'Member has already pledged') : asString(message.last_error_message, 'SMS delivery failed.')}</span></div> : null}
        {failed && canResend ? <RetrySmsButton tenantId={tenantId} outboxId={asString(message.id)} onDone={onResent} /> : null}
      </div>
    </article>
  )
}

function MessageTableActions({ message, tenantId, canResend, onResent }: { message: Row; tenantId: string; canResend: boolean; onResent: () => void }) {
  const status = asString(message.status, 'QUEUED')
  return (
    <div className="inline-actions">
      {asString(message.event_id) && asString(message.event_member_id) ? <Link to={`/app/events/${asString(message.event_id)}/members/${asString(message.event_member_id)}`}>Member</Link> : null}
      {status === 'FAILED' && canResend ? <RetrySmsButton tenantId={tenantId} outboxId={asString(message.id)} onDone={onResent} /> : null}
    </div>
  )
}

function renderPreviewTemplate(body: string) {
  return body.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_match, key: string) => smsPreviewValues[key] ?? '')
}

function SmsSettingsPanel({ tenantId, settings, loading, onSaved }: { tenantId: string; settings: Row | null; loading: boolean; onSaved: () => void }) {
  const [smsEnabled, setSmsEnabled] = useState(Boolean(settings?.smsEnabled ?? true))
  const [provider, setProvider] = useState(asString(settings?.provider ?? settings?.selectedProvider, 'NEXTSMS'))
  const [senderId, setSenderId] = useState(asString(settings?.senderId, 'MICHANGO'))
  const providers = jsonArray(settings?.providers)
  const selectedProvider = providers.find((item) => asString(item.code) === provider) ?? providers[0] ?? null
  const senderIds = Array.isArray(selectedProvider?.senderIds) ? selectedProvider.senderIds.map((item) => asString(item)).filter(Boolean) : []
  const mutation = useMutation({
    mutationFn: () => api.saveSmsSettings(tenantId, { smsEnabled, provider, senderId, defaultLanguage: asString(settings?.defaultLanguage, 'sw') }),
    onSuccess: (result) => {
      setSmsEnabled(Boolean(result.data.smsEnabled ?? true))
      setProvider(asString(result.data.provider ?? result.data.selectedProvider, 'NEXTSMS'))
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
        <StatusBadge>{provider} · {senderId}</StatusBadge>
      </div>
      <label className="checkbox-line"><input type="checkbox" checked={smsEnabled} onChange={(event) => setSmsEnabled(event.target.checked)} /> SMS Enabled</label>
      <label>SMS Provider<select value={provider} onChange={(event) => {
        const nextProvider = event.target.value
        const nextProviderRow = providers.find((item) => asString(item.code) === nextProvider) ?? null
        const nextSenderIds = Array.isArray(nextProviderRow?.senderIds) ? nextProviderRow.senderIds.map((item) => asString(item)).filter(Boolean) : []
        setProvider(nextProvider)
        setSenderId(nextSenderIds[0] ?? '')
      }}>{providers.map((item) => <option key={asString(item.code)} value={asString(item.code)}>{asString(item.name, asString(item.code))}</option>)}</select></label>
      <label>Sender ID<select value={senderId} onChange={(event) => setSenderId(event.target.value)}>{senderIds.map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
      {!providers.length ? <p className="field-error">No active SMS provider is available.</p> : null}
      {selectedProvider && !senderIds.length ? <p className="field-error">Provider unavailable: no active Sender ID is configured.</p> : null}
      {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'SMS settings could not be saved.')}</p> : null}
      <div className="sheet-actions"><button className="primary-button" type="button" disabled={mutation.isPending || !provider || !senderId} onClick={() => mutation.mutate()}>{mutation.isPending ? 'Saving...' : 'Save Settings'}</button></div>
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
  const samplePreview = renderPreviewTemplate(currentBody)
  const maxCharacters = asNumber(template?.maxCharacters)
  const sampleCharacters = samplePreview.length
  const sampleOverLimit = maxCharacters > 0 && sampleCharacters > maxCharacters
  return (
    <article className="content-panel">
      <div className="panel-header">
        <div>
          <h3>{option.label}</h3>
          <p>{template?.hasTenantOverride ? 'Tenant override active.' : 'Using system default.'}</p>
        </div>
        <StatusBadge tone={sampleOverLimit ? 'warning' : 'success'}>{sampleCharacters} / {maxCharacters || asString(template?.maxCharacters, 'max')} sample</StatusBadge>
      </div>
      <label>Template<textarea value={currentBody} onChange={(event) => setBody(event.target.value)} rows={4} /></label>
      <p className="privacy-note">{option.variables.map((variable) => `{{${variable}}}`).join(' ')}</p>
      <p className="privacy-note">Template Characters: {currentBody.length} · Sample Preview Characters: {sampleCharacters} · Maximum: {maxCharacters || asString(template?.maxCharacters, 'Not loaded')}</p>
      {sampleOverLimit ? <p className="field-error">Sample preview exceeds the limit. Messages exceeding the maximum after rendering cannot be sent.</p> : null}
      <div className="template-preview-card"><p>{samplePreview}</p></div>
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
  const queryClient = useQueryClient()
  const tenantId = session.selectedTenantId
  const permissions = new Set(session.selectedTenantContext?.permissions ?? [])
  const currentRoles = session.selectedTenantContext?.roles ?? []
  const canGrantOwner = currentRoles.includes('TENANT_OWNER')
  const canInvite = permissions.has('users.invite')
  const canManageRoles = permissions.has('users.manage_roles')
  const canSuspend = permissions.has('users.suspend')
  const [inviteOpen, setInviteOpen] = useState(false)
  const [inviteFullName, setInviteFullName] = useState('')
  const [invitePhone, setInvitePhone] = useState('')
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteRole, setInviteRole] = useState('VIEWER')
  const [roleDrafts, setRoleDrafts] = useState<Record<string, string>>({})
  const users = useQuery({ queryKey: ['tenant-users', tenantId], queryFn: async () => (await api.tenantUsers(tenantId ?? '')).data, enabled: Boolean(tenantId) })
  const roleOptions = tenantRoleOptions.filter((option) => option.value !== 'TENANT_OWNER' || canGrantOwner)

  function refreshUsers() {
    void queryClient.invalidateQueries({ queryKey: ['tenant-users', tenantId] })
    if (tenantId) {
      void session.selectTenant(tenantId)
    }
  }

  const invite = useMutation({
    mutationFn: async () => api.inviteTenantUser(tenantId ?? '', { fullName: inviteFullName, phone: invitePhone, email: inviteEmail || null, role: inviteRole }),
    onSuccess: () => {
      setInviteFullName('')
      setInvitePhone('')
      setInviteEmail('')
      setInviteRole('VIEWER')
      setInviteOpen(false)
      refreshUsers()
    },
  })
  const updateRole = useMutation({
    mutationFn: async ({ tenantUserId, role }: { tenantUserId: string; role: string }) => api.updateTenantUserRole(tenantId ?? '', tenantUserId, role),
    onSuccess: refreshUsers,
  })
  const suspend = useMutation({ mutationFn: async (tenantUserId: string) => api.suspendTenantUser(tenantId ?? '', tenantUserId), onSuccess: refreshUsers })
  const reactivate = useMutation({ mutationFn: async (tenantUserId: string) => api.reactivateTenantUser(tenantId ?? '', tenantUserId), onSuccess: refreshUsers })
  const remove = useMutation({ mutationFn: async (tenantUserId: string) => api.removeTenantUser(tenantId ?? '', tenantUserId), onSuccess: refreshUsers })
  const resend = useMutation({ mutationFn: async (invitationId: string) => api.resendTenantInvitation(tenantId ?? '', invitationId), onSuccess: refreshUsers })

  if (!tenantId) return <ErrorState title="Unable to load users" message="Select a tenant first." />
  if (!permissions.has('users.view')) return <ErrorState title="Users access denied" message="Your tenant role does not include user management access." />
  if (users.isLoading) return <LoadingState title="Loading users" message="Fetching tenant team members." />
  if (users.isError) return <ErrorState title="Unable to load users" message={errorMessage(users.error, 'Tenant users could not be loaded.')} />

  const rows = users.data ?? []
  const pendingAction = updateRole.isPending || suspend.isPending || reactivate.isPending || remove.isPending || resend.isPending

  function tenantUserId(row: Row) {
    return asString(row.tenant_user_id)
  }

  function invitationId(row: Row) {
    return asString(row.invitation_id)
  }

  function currentRole(row: Row) {
    return userRoles(row.roles)[0] ?? 'VIEWER'
  }

  function displayName(row: Row) {
    return asString(row.full_name, asString(row.email, asString(row.phone_e164, 'User')))
  }

  function saveRole(row: Row) {
    const id = tenantUserId(row)
    const nextRole = roleDrafts[id] ?? currentRole(row)
    if (id && nextRole !== currentRole(row)) {
      updateRole.mutate({ tenantUserId: id, role: nextRole })
    }
  }

  function removeUser(row: Row) {
    const id = tenantUserId(row)
    if (id && window.confirm(`Remove ${displayName(row)} from this organization?`)) {
      remove.mutate(id)
    }
  }

  function renderActions(row: Row) {
    const id = tenantUserId(row)
    const inviteId = invitationId(row)
    const status = asString(row.status, 'ACTIVE')
    if (inviteId && !id) {
      return <div className="inline-actions">{canInvite ? <button type="button" disabled={pendingAction} onClick={() => resend.mutate(inviteId)}>Resend Invitation</button> : null}</div>
    }
    return (
      <div className="inline-actions">
        {canManageRoles && id ? (
          <>
            <select aria-label={`Role for ${displayName(row)}`} value={roleDrafts[id] ?? currentRole(row)} disabled={pendingAction} onChange={(event) => setRoleDrafts((current) => ({ ...current, [id]: event.target.value }))}>
              {roleOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
            <button type="button" disabled={pendingAction || (roleDrafts[id] ?? currentRole(row)) === currentRole(row)} onClick={() => saveRole(row)}>Save</button>
          </>
        ) : null}
        {canSuspend && id && status === 'ACTIVE' ? <button type="button" disabled={pendingAction} onClick={() => suspend.mutate(id)}>Suspend</button> : null}
        {canSuspend && id && status === 'SUSPENDED' ? <button type="button" disabled={pendingAction} onClick={() => reactivate.mutate(id)}>Reactivate</button> : null}
        {canManageRoles && id ? <button type="button" disabled={pendingAction} onClick={() => removeUser(row)}>Remove</button> : null}
      </div>
    )
  }

  return (
    <PageContainer>
      <PageHeader
        title="Users & Roles"
        description="People who can access this organization and their tenant roles."
        action={canInvite ? <button className="desktop-primary-button" type="button" onClick={() => setInviteOpen((current) => !current)}><Plus size={18} aria-hidden /> Invite User</button> : null}
      />
      {inviteOpen ? (
        <form className="mobile-sheet form-grid" onSubmit={(event) => { event.preventDefault(); invite.mutate() }}>
          <label>Full Name<input value={inviteFullName} onChange={(event) => setInviteFullName(event.target.value)} required /></label>
          <label>Phone Number<input value={invitePhone} inputMode="tel" onChange={(event) => setInvitePhone(event.target.value)} placeholder="+255..." required /></label>
          <label>Email<input value={inviteEmail} type="email" onChange={(event) => setInviteEmail(event.target.value)} /></label>
          <label>Role<select value={inviteRole} onChange={(event) => setInviteRole(event.target.value)}>{roleOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
          {invite.data?.data?.alreadyPending ? <p className="field-error">An invitation is already pending for this phone number. Use Resend Invitation from the table.</p> : null}
          {invite.error ? <p className="field-error">{errorMessage(invite.error, 'Invitation could not be created.')}</p> : null}
          <div className="sheet-actions">
            <button type="button" onClick={() => setInviteOpen(false)}>Cancel</button>
            <button className="primary-button" type="submit" disabled={invite.isPending || !inviteFullName.trim() || !invitePhone.trim()}>{invite.isPending ? 'Inviting...' : 'Invite User'}</button>
          </div>
        </form>
      ) : null}
      {updateRole.error ? <p className="field-error">{errorMessage(updateRole.error, 'Role could not be updated.')}</p> : null}
      {suspend.error ? <p className="field-error">{errorMessage(suspend.error, 'User could not be suspended.')}</p> : null}
      {reactivate.error ? <p className="field-error">{errorMessage(reactivate.error, 'User could not be reactivated.')}</p> : null}
      {remove.error ? <p className="field-error">{errorMessage(remove.error, 'User could not be removed.')}</p> : null}
      {resend.error ? <p className="field-error">{errorMessage(resend.error, 'Invitation could not be resent.')}</p> : null}
      <DataTable
        title="Organization Users"
        rows={rows}
        columns={[
          { key: 'name', header: 'Name', render: (user) => <strong>{displayName(user)}{asString(user.email) ? <small>{asString(user.email)}</small> : null}</strong>, sortValue: (user) => displayName(user) },
          { key: 'phone', header: 'Phone', render: (user) => <span>{asString(user.phone_e164, 'No phone')}</span>, sortValue: (user) => asString(user.phone_e164) },
          { key: 'role', header: 'Role', render: (user) => <span>{userRoleText(user.roles)}</span>, sortValue: (user) => userRoleText(user.roles) },
          { key: 'status', header: 'Status', render: (user) => <StatusBadge tone={statusTone(user.status)}>{tenantUserStatusLabel(user.status)}</StatusBadge>, sortValue: (user) => asString(user.status) },
          { key: 'lastSeen', header: 'Last Active', render: (user) => <span>{asDateTime(user.last_seen_at ?? user.updated_at ?? user.joined_at)}</span>, sortValue: (user) => asString(user.last_seen_at ?? user.updated_at ?? user.joined_at) },
          { key: 'actions', header: 'Actions', render: renderActions, align: 'right' },
        ]}
        getRowKey={(user) => asString(user.row_id, asString(user.tenant_user_id, asString(user.invitation_id)))}
        emptyTitle="No tenant users found."
        emptyMessage="Tenant owners appear here after onboarding and invitations."
        mobileRender={(user) => (
          <>
            <div><span>Name</span><strong>{displayName(user)}</strong></div>
            <div><span>Phone</span><strong>{asString(user.phone_e164, 'No phone')}</strong></div>
            <div><span>Role</span><strong>{userRoleText(user.roles)}</strong></div>
            <div><span>Status</span><strong>{tenantUserStatusLabel(user.status)}</strong></div>
            <div>{renderActions(user)}</div>
          </>
        )}
      />
    </PageContainer>
  )
}

export function TenantChangePinPage() {
  const [currentPin, setCurrentPin] = useState('')
  const [newPin, setNewPin] = useState('')
  const [confirmNewPin, setConfirmNewPin] = useState('')
  const [successMessage, setSuccessMessage] = useState('')
  const mutation = useMutation({
    mutationFn: async () => api.changePin(currentPin, newPin, confirmNewPin),
    onSuccess: () => {
      setCurrentPin('')
      setNewPin('')
      setConfirmNewPin('')
      setSuccessMessage('PIN changed successfully')
    },
  })
  const ready = canSubmitPin({ pin: currentPin, isPending: mutation.isPending, isSubmitting: false })
    && canSubmitPin({ pin: newPin, confirmPin: confirmNewPin, isPending: mutation.isPending, isSubmitting: false })
    && newPin === confirmNewPin

  function submit(event?: FormEvent) {
    event?.preventDefault()
    setSuccessMessage('')
    if (ready) {
      mutation.mutate()
    }
  }

  return (
    <PageContainer>
      <PageHeader title="Change PIN" description="Update the 4-digit PIN used with your phone number." />
      <form className="mobile-sheet form-grid" onSubmit={submit}>
        <PinEntry label="Current PIN" value={currentPin} disabled={mutation.isPending} autoFocus onChange={setCurrentPin} onEnterComplete={() => submit()} />
        <PinEntry label="New PIN" value={newPin} disabled={mutation.isPending} onChange={setNewPin} onEnterComplete={() => submit()} />
        <PinEntry label="Confirm New PIN" value={confirmNewPin} disabled={mutation.isPending} onChange={setConfirmNewPin} onComplete={() => submit()} onEnterComplete={() => submit()} />
        {newPin && confirmNewPin && newPin !== confirmNewPin ? <p className="field-error">PINs do not match.</p> : null}
        {successMessage ? <p className="success-message"><KeyRound size={16} aria-hidden /> {successMessage}</p> : null}
        {mutation.error ? <p className="field-error">{errorMessage(mutation.error, 'PIN could not be changed.')}</p> : null}
        <div className="sheet-actions">
          <button className="primary-button" type="submit" disabled={!ready}>{mutation.isPending ? 'Changing...' : 'Change PIN'}</button>
        </div>
      </form>
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
  const plans = useQuery({ queryKey: ['public-plans'], queryFn: async () => ((await api.plans()).data as Row[]).map(normalizePlanRow) })

  if (!tenantId) return <ErrorState title="Unable to load billing" message="Select a tenant first." />
  if (billing.isLoading) return <LoadingState title="Loading billing" message="Fetching subscription invoices and gateway status." />
  if (billing.isError || !billing.data) return <ErrorState title="Unable to load billing" message={errorMessage(billing.error, 'Billing could not be loaded.')} />

  const subscription = jsonRecord(billing.data.subscription)
  const limits = jsonRecord(subscription.limits)
  const eventUsage = jsonRecord(subscription.eventUsage ?? subscription.event_usage)
  const usage = Object.keys(eventUsage).length ? eventUsage : limits
  const usedEventSlots = usageNumber(usage, ['used', 'usedEventSlots', 'used_event_slots'])
  const maxEventSlots = usageNumber(usage, ['limit', 'maxEventSlots', 'max_event_slots'])
  const availableEventSlots = usageNumber(usage, ['available', 'availableEventSlots', 'available_event_slots'])
  const includedSms = usageNumber(limits, ['includedSms', 'included_sms'])
  const usagePercent = maxEventSlots > 0 ? Math.min(100, Math.round((usedEventSlots / maxEventSlots) * 100)) : 0
  const invoices = rows(billing.data.invoices)
  const payments = rows(billing.data.payments)
  const pendingIntents = rows(billing.data.pendingIntents)
  const payableInvoices = invoices.filter(invoicePayable)
  const currentPlanCode = asString(subscription.planCode ?? subscription.plan_code)

  return (
    <PageContainer>
      <PageHeader title="Billing" description="Tenant subscription status, package limits, invoices and verified payment attempts." action={<Link to="/app/settings">Settings</Link>} />
      <section className="stats-grid">
        <StatCard label="Package" value={asString(subscription.planName, 'Not set')} meta={asString(subscription.status, 'No status')} icon={FileText} />
        <StatCard label="Open Balance" value={moneyText(payableInvoices.reduce((sum, invoice) => sum + asNumber(invoice.amount_due ?? invoice.amountDue), 0))} meta={`${payableInvoices.length} payable invoices`} icon={CreditCard} tone={payableInvoices.length ? 'warning' : 'success'} />
        <StatCard label="Verified Payments" value={String(payments.length)} meta={`${pendingIntents.length} pending attempts`} icon={CheckCircle2} />
      </section>
      <section className="finance-card-list">
        <article className="finance-card subscription-summary-card">
          <div className="card-title-row">
            <div><strong>{asString(subscription.planName, 'No package selected')}</strong><span>{session.selectedTenantContext?.tenant.name ?? 'Current organization'}</span></div>
            <StatusBadge tone={statusTone(subscription.status)}>{asString(subscription.status, 'UNKNOWN')}</StatusBadge>
          </div>
          <div className="amount-triplet">
            <span><small>{asString(subscription.status) === 'TRIAL' ? 'Trial Ends' : 'Renews'}</small>{asDate(subscription.trialEndsAt ?? subscription.trial_ends_at ?? subscription.currentPeriodEnd ?? subscription.current_period_end)}</span>
            <span><small>Used Event Slots</small>{usedEventSlots} / {maxEventSlots}</span>
            <span><small>Available Slots</small>{availableEventSlots}</span>
          </div>
          <progress max={100} value={usagePercent} aria-label="Event slot usage" />
          <div className="card-actions">
            <a href="#available-packages">Change Plan</a>
          </div>
        </article>
        <article className="finance-card">
          <div className="card-title-row">
            <div><strong>Limits enforced by package</strong><span>Backend checks remain active even when buttons are hidden or disabled.</span></div>
            <MessageCircle size={18} aria-hidden />
          </div>
          <div className="amount-triplet">
            <span><small>Included SMS</small>{includedSms}</span>
            <span><small>Members</small>{displayValue(limits.maxMembers ?? limits.max_members)}</span>
            <span><small>Users</small>{displayValue(limits.maxUsers ?? limits.max_users)}</span>
          </div>
        </article>
      </section>
      <section className="finance-card-list" id="available-packages">
        <div className="section-heading">
          <div><h2>Available Packages</h2><p>Compare public packages. Upgrade and downgrade activation is handled through Ahadi billing until automated package switching is enabled.</p></div>
        </div>
        {plans.isLoading ? <LoadingState title="Loading packages" message="Fetching public subscription packages." /> : null}
        {plans.isError ? <ErrorState title="Unable to load packages" message={errorMessage(plans.error, 'Packages could not be loaded.')} /> : null}
        {(plans.data ?? []).map((plan) => (
          <article className={plan.code === currentPlanCode ? 'package-card selected' : 'package-card'} key={plan.code}>
            <div className="card-title-row">
              <strong>{plan.code === currentPlanCode ? `${plan.name} · Current` : plan.name}</strong>
              {plan.code === currentPlanCode ? <StatusBadge tone="success">CURRENT</StatusBadge> : null}
            </div>
            <MoneyDisplay amount={plan.priceAmount} currency={plan.currency} />
            <span>{billingIntervalText(plan.billingInterval)} billing, {plan.trialDays} trial days</span>
            <small>{activeEventLimitLabel(plan.maxActiveEvents)} · {plan.maxUsers} users · {plan.maxMembers} members · {plan.includedSms} SMS</small>
          </article>
        ))}
      </section>
      <section className="finance-card-list">
        <div className="section-heading">
          <div><h2>Invoices</h2><p>Subscription invoices and confirmed payment state from the existing billing integration.</p></div>
        </div>
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
  const navigate = useNavigate()
  const params = useParams()
  const routeReportType = asString(params.reportType)
  const events = session.selectedTenantContext?.events ?? []
  const selectedSessionEvent = session.selectedEventId ? events.find((candidate) => candidate.id === session.selectedEventId) ?? null : null
  const event = params.eventId ? events.find((candidate) => candidate.id === params.eventId) ?? null : selectedSessionEvent ?? events[0] ?? null
  const tenantId = session.selectedTenantId
  const activeEventId = params.eventId ?? selectedSessionEvent?.id ?? event?.id ?? ''
  const activeEvent = events.find((candidate) => candidate.id === activeEventId) ?? event

  function handleReportEventChange(eventId: string) {
    session.selectEvent(eventId)
    if (params.eventId) {
      navigate(`/app/events/${eventId}/reports`)
    }
  }

  if (!tenantId || !activeEvent) return <ErrorState title="Unable to load reports" message="Open a tenant with an accessible event first." />
  if (routeReportType) {
    return <ReportDetailPage tenantId={tenantId} eventId={activeEvent.id} eventName={activeEvent.name} reportType={routeReportType} />
  }

  return (
    <PageContainer>
      <PageHeader title="Reports" description={`Server-calculated reports for ${activeEvent.name}.`} />
      {events.length > 1 ? (
        <section className="filter-bar">
          <label>Event<select value={activeEvent.id} onChange={(event) => handleReportEventChange(event.target.value)}>{events.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
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
        {reportType === 'member-statement' ? <label>Member<select value={draft.eventMemberId} onChange={(event) => setDraft((current) => ({ ...current, eventMemberId: event.target.value }))}><option value="">First matching member</option>{members.map((member) => <option key={asString(member.eventMemberId)} value={asString(member.eventMemberId)}>{titleCaseMemberName(member.name, '')} · {asString(member.memberCode)}</option>)}</select></label> : null}
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
      {!report.isLoading && !report.isError && rows.length ? (
        <DataTable
          title="Report Rows"
          rows={rows}
          columns={reportTableColumns(reportType, rows)}
          getRowKey={(row, index) => `${reportType}-${index}-${asString(row.id ?? row.paymentId ?? row.pledgeId ?? row.date)}`}
          emptyTitle={emptyReportMessage(reportType)}
          emptyMessage="Adjust the report filters or add financial records to this event."
          initialPageSize={Number(filters.pageSize)}
          pageSizeOptions={[25, 50, 100]}
          mobileRender={(row) => <ReportRowCard reportType={reportType} row={row} summary={summary} />}
        />
      ) : null}
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

function reportTableColumns(reportType: string, rows: Row[]): Array<DataTableColumn<Row>> {
  if (reportType === 'pledges') {
    return [
      { key: 'member', header: 'Member', render: (row) => <strong>{titleCaseMemberName(row.member, titleCaseMemberName(row.memberName, ''))}</strong>, sortValue: (row) => titleCaseMemberName(row.member ?? row.memberName, '') },
      { key: 'phone', header: 'Phone', render: (row) => <span>{asString(row.phone, 'No phone')}</span>, sortValue: (row) => asString(row.phone) },
      { key: 'category', header: 'Category', render: (row) => <span>{asString(row.category, 'No category')}</span>, sortValue: (row) => asString(row.category) },
      { key: 'pledged', header: 'Pledged', render: (row) => <span>{moneyText(row.pledged)}</span>, sortValue: (row) => asNumber(row.pledged), align: 'right' },
      { key: 'paid', header: 'Paid', render: (row) => <span>{moneyText(row.paid)}</span>, sortValue: (row) => asNumber(row.paid), align: 'right' },
      { key: 'outstanding', header: 'Outstanding', render: (row) => <span>{moneyText(row.outstanding)}</span>, sortValue: (row) => asNumber(row.outstanding), align: 'right' },
      { key: 'dueDate', header: 'Due Date', render: (row) => <span>{asDate(row.dueDate)}</span>, sortValue: (row) => asString(row.dueDate) },
      { key: 'status', header: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{asString(row.status, 'Report')}</StatusBadge>, sortValue: (row) => asString(row.status) },
    ]
  }
  if (reportType === 'payments') {
    return [
      { key: 'date', header: 'Date', render: (row) => <span>{asDateTime(row.date ?? row.paymentDate)}</span>, sortValue: (row) => asString(row.date ?? row.paymentDate) },
      { key: 'receipt', header: 'Receipt', render: (row) => <span>{asString(row.receipt ?? row.receiptNumber, 'No receipt')}</span>, sortValue: (row) => asString(row.receipt ?? row.receiptNumber) },
      { key: 'member', header: 'Member', render: (row) => <strong>{titleCaseMemberName(row.member ?? row.memberName, '')}</strong>, sortValue: (row) => titleCaseMemberName(row.member ?? row.memberName, '') },
      { key: 'amount', header: 'Amount', render: (row) => <span>{moneyText(row.amount)}</span>, sortValue: (row) => asNumber(row.amount), align: 'right' },
      { key: 'method', header: 'Method', render: (row) => <span>{asString(row.method ?? row.paymentMethod)}</span>, sortValue: (row) => asString(row.method ?? row.paymentMethod) },
      { key: 'reference', header: 'Reference', render: (row) => <span>{asString(row.reference ?? row.transactionReference, 'None')}</span>, sortValue: (row) => asString(row.reference ?? row.transactionReference) },
      { key: 'status', header: 'Status', render: (row) => <StatusBadge tone={statusTone(row.status)}>{asString(row.status, 'Report')}</StatusBadge>, sortValue: (row) => asString(row.status) },
    ]
  }
  if (reportType === 'outstanding') {
    return [
      { key: 'member', header: 'Member', render: (row) => <strong>{titleCaseMemberName(row.member ?? row.memberName, '')}</strong>, sortValue: (row) => titleCaseMemberName(row.member ?? row.memberName, '') },
      { key: 'phone', header: 'Phone', render: (row) => <span>{asString(row.phone, 'No phone')}</span>, sortValue: (row) => asString(row.phone) },
      { key: 'pledged', header: 'Pledged', render: (row) => <span>{moneyText(row.pledged)}</span>, sortValue: (row) => asNumber(row.pledged), align: 'right' },
      { key: 'paid', header: 'Paid', render: (row) => <span>{moneyText(row.paid)}</span>, sortValue: (row) => asNumber(row.paid), align: 'right' },
      { key: 'outstanding', header: 'Outstanding', render: (row) => <span>{moneyText(row.outstanding)}</span>, sortValue: (row) => asNumber(row.outstanding), align: 'right' },
      { key: 'due', header: 'Due', render: (row) => <span>{asDate(row.dueDate ?? row.due)}</span>, sortValue: (row) => asString(row.dueDate ?? row.due) },
      { key: 'daysOverdue', header: 'Days Overdue', render: (row) => <span>{asNumber(row.daysOverdue)}</span>, sortValue: (row) => asNumber(row.daysOverdue), align: 'right' },
    ]
  }
  const keys = Object.keys(rows[0] ?? {}).filter((key) => !['id', 'pledgeId', 'paymentId', 'eventMemberId', 'memberId', 'collectorId'].includes(key)).slice(0, 8)
  return keys.map((key) => ({
    key,
    header: key.replace(/([A-Z])/g, ' $1'),
    render: (row: Row) => <span>{reportRowValue(key, row[key])}</span>,
    sortValue: (row: Row) => typeof row[key] === 'number' ? asNumber(row[key]) : asString(row[key]),
    align: ['amount', 'total', 'pledged', 'paid', 'outstanding', 'collected'].some((word) => key.toLowerCase().includes(word)) ? 'right' : 'left',
  }))
}

function ReportSummaryCards({ reportType, summary }: { reportType: string; summary: Row }) {
  const entries: Array<[string, unknown]> = reportType === 'summary'
    ? [['Event Target', summary.eventTarget], ['Total Pledged', summary.totalPledged], ['Collected', summary.totalReceived], ['Allocated', summary.totalAllocatedToPledges], ['Unallocated', summary.totalUnallocated], ['Outstanding', summary.totalOutstanding], ['Collection Rate', `${asNumber(summary.collectionRate)}%`], ['Coverage', `${asNumber(summary.pledgeCoverageAgainstTarget)}%`], ['Members', summary.memberCount], ['With Pledges', summary.membersWithPledges], ['Without Pledges', summary.membersWithoutPledges], ['Fully Paid', summary.fullyPaidCount], ['Partial', summary.partiallyPaidCount], ['Unpaid', summary.unpaidCount], ['Overdue', summary.overdueCount]]
    : Object.entries(summary).slice(0, 6)
  return <section className="stats-grid">{entries.map(([label, value]) => <StatCard key={label} label={label} value={typeof value === 'number' || String(label).toLowerCase().includes('amount') || String(label).toLowerCase().includes('total') || ['Pledged', 'Collected', 'Allocated', 'Unallocated', 'Outstanding', 'Net Confirmed'].some((word) => String(label).includes(word)) ? moneyText(value) : displayValue(value)} icon={FileText} />)}</section>
}

function reportRowValue(key: string, value: unknown) {
  const normalized = key.toLowerCase()
  if (normalized === 'member' || normalized === 'membername' || normalized === 'fullname') return titleCaseMemberName(value, '')
  if (normalized.includes('date') || normalized.includes('payment') && String(value).includes('T')) return asDateTime(value)
  return displayValue(value)
}

function ReportRowCard({ reportType, row, summary }: { reportType: string; row: Row; summary: Row }) {
  if (reportType === 'summary') {
    return <article className="finance-card">{Object.entries(row).map(([key, value]) => <ReviewLine key={key} label={key} value={displayValue(value)} />)}</article>
  }
  if (reportType === 'member-statement') {
    const member = jsonRecord(summary.member)
    const pledge = jsonRecord(summary.pledge)
    return <article className="finance-card"><div className="card-title-row"><div><strong>{titleCaseMemberName(member.name, 'Member Statement')}</strong><span>{asString(member.memberCode)} · {asString(member.phone, 'No phone')}</span></div><StatusBadge>{asString(row.status, asString(pledge.status))}</StatusBadge></div><ReviewLine label="Date" value={asDateTime(row.date)} /><ReviewLine label="Type" value={displayValue(row.type)} /><ReviewLine label="Receipt" value={displayValue(row.receipt)} /><ReviewLine label="Method" value={displayValue(row.method)} /><ReviewLine label="Amount" value={moneyText(row.amount)} /></article>
  }
  const memberTitle = asString(row.member, '')
  const title = memberTitle ? titleCaseMemberName(memberTitle, '') : asString(row.collectorName ?? row.paymentMethod ?? row.eventName, reportTitle(reportType))
  return <article className="finance-card"><div className="card-title-row"><div><strong>{title}</strong><span>{asString(row.memberCode ?? row.paymentNumber ?? row.receiptNumber ?? row.category, '')}</span></div><StatusBadge tone={statusTone(row.status)}>{asString(row.status ?? row.paymentMethod, 'Report')}</StatusBadge></div><div className="amount-triplet">{Object.entries(row).filter(([key]) => ['pledged', 'paid', 'outstanding', 'amount', 'allocatedAmount', 'unallocatedAmount', 'netConfirmedAmount', 'grossAmount', 'reversedAmount', 'netCollected', 'grossRecorded'].includes(key)).slice(0, 3).map(([key, value]) => <span key={key}><small>{key.replace(/([A-Z])/g, ' $1')}</small>{moneyText(value)}</span>)}</div>{Object.entries(row).filter(([key]) => !['pledgeId', 'paymentId', 'eventMemberId', 'memberId', 'collectorId'].includes(key)).slice(0, 8).map(([key, value]) => <ReviewLine key={key} label={key.replace(/([A-Z])/g, ' $1')} value={reportRowValue(key, value)} />)}</article>
}

function Input({ label, value, onChange, inputMode, type = 'text' }: { label: string; value: string; onChange: (value: string) => void; inputMode?: 'decimal' | 'tel'; type?: string }) {
  return <label>{label}<input inputMode={inputMode} type={type} value={value} onChange={(event) => onChange(event.target.value)} /></label>
}

function ReviewLine({ label, value }: { label: string; value: ReactNode }) {
  return <div className="review-line"><span>{label}</span><strong>{value}</strong></div>
}
