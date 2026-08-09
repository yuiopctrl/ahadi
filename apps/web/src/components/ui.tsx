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
import { useMemo, useState } from 'react'
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

export interface DataTableColumn<T> {
  key: string
  header: string
  render: (row: T) => ReactNode
  sortValue?: (row: T) => string | number | Date | null | undefined
  align?: 'left' | 'right' | 'center'
  hideOnMobile?: boolean
}

interface DataTableProps<T> {
  rows: T[]
  columns: Array<DataTableColumn<T>>
  getRowKey: (row: T, index: number) => string
  title?: string
  searchValue?: string
  onSearchChange?: (value: string) => void
  searchPlaceholder?: string
  filters?: ReactNode
  pageSizeOptions?: number[]
  initialPageSize?: number
  emptyTitle: string
  emptyMessage?: string
  mobileRender?: (row: T) => ReactNode
}

export function DataTable<T>({
  rows,
  columns,
  getRowKey,
  title,
  searchValue,
  onSearchChange,
  searchPlaceholder = 'Search',
  filters,
  pageSizeOptions = [10, 25, 50],
  initialPageSize = 25,
  emptyTitle,
  emptyMessage,
  mobileRender,
}: DataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string>(columns.find((column) => column.sortValue)?.key ?? columns[0]?.key ?? '')
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc')
  const [pageSize, setPageSize] = useState(initialPageSize)
  const [page, setPage] = useState(1)
  const sortedRows = useMemo(() => {
    const column = columns.find((item) => item.key === sortKey && item.sortValue)
    if (!column?.sortValue) return rows
    return [...rows].sort((left, right) => {
      const leftValue = normalizeSortValue(column.sortValue?.(left))
      const rightValue = normalizeSortValue(column.sortValue?.(right))
      const result = leftValue.localeCompare(rightValue, undefined, { numeric: true, sensitivity: 'base' })
      return sortDirection === 'asc' ? result : -result
    })
  }, [columns, rows, sortDirection, sortKey])
  const totalPages = Math.max(1, Math.ceil(sortedRows.length / pageSize))
  const currentPage = Math.min(page, totalPages)
  const visibleRows = sortedRows.slice((currentPage - 1) * pageSize, currentPage * pageSize)
  const searchable = typeof searchValue === 'string' && onSearchChange

  function toggleSort(column: DataTableColumn<T>) {
    if (!column.sortValue) return
    setPage(1)
    if (sortKey === column.key) {
      setSortDirection((current) => current === 'asc' ? 'desc' : 'asc')
      return
    }
    setSortKey(column.key)
    setSortDirection('asc')
  }

  return (
    <section className="data-table-shell">
      <div className="data-table-toolbar">
        <div>
          {title ? <strong>{title}</strong> : null}
          <span>{rows.length} {rows.length === 1 ? 'row' : 'rows'}</span>
        </div>
        {searchable ? (
          <label className="data-table-search">
            <Search size={17} aria-hidden />
            <input
              type="search"
              value={searchValue}
              onChange={(event) => { setPage(1); onSearchChange(event.target.value) }}
              placeholder={searchPlaceholder}
            />
          </label>
        ) : null}
        {filters}
        <label className="data-table-page-size">
          <span>Rows</span>
          <select value={pageSize} onChange={(event) => { setPage(1); setPageSize(Number(event.target.value)) }}>
            {pageSizeOptions.map((option) => <option key={option} value={option}>{option}</option>)}
          </select>
        </label>
      </div>
      {rows.length ? (
        <>
          <div className="data-table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  {columns.map((column) => (
                    <th key={column.key} className={`cell-${column.align ?? 'left'} ${column.hideOnMobile ? 'hide-mobile' : ''}`}>
                      <button type="button" disabled={!column.sortValue} onClick={() => toggleSort(column)}>
                        {column.header}
                        {sortKey === column.key ? <span>{sortDirection === 'asc' ? 'Asc' : 'Desc'}</span> : null}
                      </button>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {visibleRows.map((row, index) => (
                  <tr key={getRowKey(row, index)}>
                    {columns.map((column) => <td key={column.key} className={`cell-${column.align ?? 'left'} ${column.hideOnMobile ? 'hide-mobile' : ''}`}>{column.render(row)}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="data-table-mobile">
            {visibleRows.map((row, index) => <div className="data-table-mobile-row" key={getRowKey(row, index)}>{mobileRender ? mobileRender(row) : columns.filter((column) => !column.hideOnMobile).map((column) => <div key={column.key}><span>{column.header}</span><strong>{column.render(row)}</strong></div>)}</div>)}
          </div>
          <div className="data-table-footer">
            <span>Page {currentPage} of {totalPages}</span>
            <div className="inline-actions">
              <button type="button" disabled={currentPage <= 1} onClick={() => setPage((value) => Math.max(1, value - 1))}>Previous</button>
              <button type="button" disabled={currentPage >= totalPages} onClick={() => setPage((value) => value + 1)}>Next</button>
            </div>
          </div>
        </>
      ) : <EmptyState title={emptyTitle} message={emptyMessage} />}
    </section>
  )
}

function normalizeSortValue(value: string | number | Date | null | undefined) {
  if (value instanceof Date) return value.toISOString()
  if (typeof value === 'number') return String(value).padStart(20, '0')
  return String(value ?? '')
}
