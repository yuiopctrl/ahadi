import {
  CalendarDays,
  CheckCircle2,
  Clock3,
  CreditCard,
  MessageSquareText,
  PieChart,
  Plus,
  Users,
} from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import {
  EmptyState,
  FilterButton,
  MoneyDisplay,
  PageContainer,
  PageHeader,
  SearchInput,
  StatCard,
  StatusBadge,
} from '../components/ui'

const payments = [
  { id: 'PAY-1042', name: 'Joseph K.', amount: 250000, event: 'Neema & Baraka Wedding', status: 'Confirmed' },
  { id: 'PAY-1041', name: 'Rehema M.', amount: 80000, event: 'Community medical fund', status: 'Pending' },
  { id: 'PAY-1040', name: 'David L.', amount: 120000, event: 'Sendoff committee', status: 'Confirmed' },
]

export function TenantDashboardPage() {
  return (
    <PageContainer>
      <PageHeader
        title="Dashboard"
        description="Track pledges, collections and committee follow-up across active events."
        action={
          <button type="button" className="desktop-primary-button">
            <Plus size={18} aria-hidden />
            Record Payment
          </button>
        }
      />
      <section className="stats-grid">
        <StatCard label="Active Events" value="7" meta="3 collecting this week" icon={CalendarDays} />
        <StatCard label="Total Pledged" value="TZS 42.8M" meta="Across all active events" icon={PieChart} />
        <StatCard label="Total Collected" value="TZS 31.4M" meta="73% collection rate" icon={CheckCircle2} tone="success" />
        <StatCard label="Total Outstanding" value="TZS 11.4M" meta="92 open installments" icon={Clock3} tone="warning" />
      </section>
      <section className="dashboard-grid">
        <article className="content-panel">
          <div className="panel-header">
            <div>
              <h2>Recent Payments</h2>
              <p>Latest confirmed and pending member contributions.</p>
            </div>
            <StatusBadge tone="success">Collection Rate 73%</StatusBadge>
          </div>
          <div className="payment-list">
            {payments.map((payment) => (
              <div className="payment-card" key={payment.id}>
                <div>
                  <strong>{payment.name}</strong>
                  <span>{payment.event}</span>
                </div>
                <div>
                  <MoneyDisplay amount={payment.amount} />
                  <StatusBadge tone={payment.status === 'Confirmed' ? 'success' : 'warning'}>{payment.status}</StatusBadge>
                </div>
              </div>
            ))}
          </div>
        </article>
        <article className="content-panel">
          <div className="panel-header">
            <div>
              <h2>Upcoming Deadlines</h2>
              <p>Installments needing attention before committee meetings.</p>
            </div>
          </div>
          <div className="deadline-list">
            <div>
              <strong>Wedding venue installment</strong>
              <span>Due Aug 12</span>
            </div>
            <div>
              <strong>Funeral transport pledge round</strong>
              <span>Due Aug 14</span>
            </div>
            <div>
              <strong>SMS reminder batch</strong>
              <span>Due Aug 16</span>
            </div>
          </div>
        </article>
      </section>
    </PageContainer>
  )
}

export function TenantListPage({ title, kind }: { title: string; kind: 'events' | 'members' | 'payments' | 'messages' | 'reports' | 'settings' }) {
  const description = {
    events: 'Manage weddings, sendoffs, funerals and community fundraising drives.',
    members: 'View contributors, committee members and pledge assignments.',
    payments: 'Review collections, mobile money references and installment progress.',
    messages: 'Prepare reminders and collection updates for event members.',
    reports: 'Monitor pledge performance and transaction summaries.',
    settings: 'Configure users, branding, event defaults and tenant controls.',
  }[kind]

  return (
    <PageContainer>
      <PageHeader
        title={title}
        description={description}
        action={
          <button type="button" className="desktop-primary-button">
            <Plus size={18} aria-hidden />
            New
          </button>
        }
      />
      <div className="toolbar-row">
        <SearchInput placeholder={`Search ${title.toLowerCase()}`} />
        <FilterButton />
      </div>
      <section className="cards-list">
        <Link to="/app/events/event_001" className="summary-card">
          <CalendarDays size={20} aria-hidden />
          <div>
            <strong>Neema & Baraka Wedding</strong>
            <span>156 members, TZS 18.6M pledged</span>
          </div>
          <StatusBadge tone="success">Active</StatusBadge>
        </Link>
        <div className="summary-card">
          <Users size={20} aria-hidden />
          <div>
            <strong>Family committee group</strong>
            <span>Collection owners and payment verifiers</span>
          </div>
          <StatusBadge>Tenant</StatusBadge>
        </div>
        <div className="summary-card">
          {kind === 'messages' ? <MessageSquareText size={20} aria-hidden /> : <CreditCard size={20} aria-hidden />}
          <div>
            <strong>August follow-up batch</strong>
            <span>Ready for review after payment reconciliation</span>
          </div>
          <StatusBadge tone="warning">Draft</StatusBadge>
        </div>
      </section>
    </PageContainer>
  )
}

export function EventDetailPage({ section = 'overview' }: { section?: 'overview' | 'members' | 'pledges' | 'payments' | 'messages' }) {
  const params = useParams()
  const title = section === 'overview' ? 'Event Overview' : `Event ${section[0]?.toUpperCase() ?? ''}${section.slice(1)}`

  return (
    <PageContainer>
      <PageHeader title={title} description={`Event ${params.eventId ?? 'event'} context, prepared for pledge workflows.`} />
      <section className="stats-grid">
        <StatCard label="Pledged" value="TZS 18.6M" meta="156 contributors" icon={PieChart} />
        <StatCard label="Collected" value="TZS 13.2M" meta="71% complete" icon={CheckCircle2} tone="success" />
        <StatCard label="Outstanding" value="TZS 5.4M" meta="43 installments" icon={Clock3} tone="warning" />
      </section>
      <EmptyState title="Workflow foundation ready" message="Detailed pledge and payment business logic will be added in a later implementation step." />
    </PageContainer>
  )
}
