import {
  AlertTriangle,
  CalendarClock,
  CheckCircle2,
  ChevronDown,
  CircleDollarSign,
  Filter,
  Loader2,
  Search,
  X,
} from 'lucide-react'
import type { ComponentType, ReactNode } from 'react'
import type { EventSummary, TenantMembershipContext } from '@ahadi/types'

type IconType = ComponentType<{ size?: number; className?: string; 'aria-hidden'?: boolean }>

interface PageHeaderProps {
  title: string
  description?: string
  action?: ReactNode
}

export function PageHeader({ title, description, action }: PageHeaderProps) {
  return (
    <header className="page-header">
      <div>
        <p className="eyebrow">Ahadi</p>
        <h1>{title}</h1>
        {description ? <p className="page-description">{description}</p> : null}
      </div>
      {action ? <div className="page-header-action">{action}</div> : null}
    </header>
  )
}

interface PageContainerProps {
  children: ReactNode
  narrow?: boolean
}

export function PageContainer({ children, narrow = false }: PageContainerProps) {
  return <main className={narrow ? 'page-container page-container-narrow' : 'page-container'}>{children}</main>
}

interface StatCardProps {
  label: string
  value: string
  meta?: string
  icon?: IconType
  tone?: 'neutral' | 'success' | 'warning' | 'danger'
}

export function StatCard({ label, value, meta, icon: Icon = CircleDollarSign, tone = 'neutral' }: StatCardProps) {
  return (
    <article className={`stat-card stat-card-${tone}`}>
      <div className="stat-icon">
        <Icon size={20} aria-hidden />
      </div>
      <div>
        <p>{label}</p>
        <strong>{value}</strong>
        {meta ? <span>{meta}</span> : null}
      </div>
    </article>
  )
}

interface StateProps {
  title: string
  message?: string
}

export function EmptyState({ title, message }: StateProps) {
  return (
    <section className="state-card">
      <CalendarClock size={28} aria-hidden />
      <h2>{title}</h2>
      {message ? <p>{message}</p> : null}
    </section>
  )
}

export function LoadingState({ title, message }: StateProps) {
  return (
    <section className="state-card">
      <Loader2 className="spin" size={28} aria-hidden />
      <h2>{title}</h2>
      {message ? <p>{message}</p> : null}
    </section>
  )
}

export function ErrorState({ title, message }: StateProps) {
  return (
    <section className="state-card state-card-danger">
      <AlertTriangle size={28} aria-hidden />
      <h2>{title}</h2>
      {message ? <p>{message}</p> : null}
    </section>
  )
}

interface MoneyDisplayProps {
  amount: number
  currency?: string
}

export function MoneyDisplay({ amount, currency = 'TZS' }: MoneyDisplayProps) {
  return (
    <span className="money">
      {new Intl.NumberFormat('en-TZ', {
        style: 'currency',
        currency,
        maximumFractionDigits: 0,
      }).format(amount)}
    </span>
  )
}

interface StatusBadgeProps {
  children: ReactNode
  tone?: 'success' | 'warning' | 'danger' | 'neutral'
}

export function StatusBadge({ children, tone = 'neutral' }: StatusBadgeProps) {
  return <span className={`status-badge status-${tone}`}>{children}</span>
}

interface SearchInputProps {
  placeholder: string
}

export function SearchInput({ placeholder }: SearchInputProps) {
  return (
    <label className="search-input">
      <Search size={18} aria-hidden />
      <input type="search" placeholder={placeholder} />
    </label>
  )
}

export function FilterButton() {
  return (
    <button className="icon-text-button" type="button">
      <Filter size={18} aria-hidden />
      Filters
    </button>
  )
}

interface MobileActionBarProps {
  label?: string
}

export function MobileActionBar({ label = 'Record Payment' }: MobileActionBarProps) {
  return (
    <div className="mobile-action-bar">
      <button type="button">
        <CircleDollarSign size={20} aria-hidden />
        {label}
      </button>
    </div>
  )
}

interface ConfirmDialogProps {
  title: string
  message: string
}

export function ConfirmDialog({ title, message }: ConfirmDialogProps) {
  return (
    <dialog className="confirm-dialog">
      <h2>{title}</h2>
      <p>{message}</p>
      <div className="dialog-actions">
        <button type="button">Cancel</button>
        <button type="button" className="button-danger">
          Confirm
        </button>
      </div>
    </dialog>
  )
}

interface AppDrawerProps {
  title: string
  children: ReactNode
}

export function AppDrawer({ title, children }: AppDrawerProps) {
  return (
    <aside className="app-drawer" aria-label={title}>
      <div className="drawer-header">
        <h2>{title}</h2>
        <button type="button" aria-label="Close">
          <X size={18} aria-hidden />
        </button>
      </div>
      {children}
    </aside>
  )
}

export function TenantSwitcherDisplay({ tenant }: { tenant: TenantMembershipContext | null }) {
  return (
    <button className="tenant-switcher" type="button" aria-label="Current tenant">
      <span>{tenant?.tenantName ?? 'No tenant selected'}</span>
      <small>{tenant?.subscription?.planName ?? 'Setup required'}</small>
      <ChevronDown size={16} aria-hidden />
    </button>
  )
}

export function EventContextDisplay({ event }: { event: EventSummary | null }) {
  return (
    <div className="event-context">
      <CheckCircle2 size={16} aria-hidden />
      <span>{event?.name ?? 'No active event'}</span>
    </div>
  )
}
