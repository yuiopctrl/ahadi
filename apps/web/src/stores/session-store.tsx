/* eslint-disable react-refresh/only-export-components */
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import type { TenantContext, UserContext } from '@ahadi/types'
import { api } from '../lib/api'
import { supabase } from '../lib/supabase'

export interface SessionLockState {
  isLocked: boolean
  lockReason: 'idle' | 'manual' | 'startup' | null
  lastActivityAt: number
  lock: (reason?: SessionLockState['lockReason']) => void
  unlock: () => void
  reset: () => void
}

interface SessionStore {
  isLoading: boolean
  session: Session | null
  userContext: UserContext | null
  selectedTenantId: string | null
  selectedEventId: string | null
  selectedTenantContext: TenantContext | null
  lockState: SessionLockState
  refreshContext: () => Promise<UserContext | null>
  selectTenant: (tenantId: string) => Promise<TenantContext>
  selectEvent: (eventId: string | null) => void
  clearTenant: () => void
  signOut: () => Promise<void>
}

const SessionContext = createContext<SessionStore | null>(null)

const selectedTenantStorageKey = 'ahadi:selected-tenant-id'

function selectedEventStorageKey(tenantId: string) {
  return `ahadi:selected-event-id:${tenantId}`
}

function storedEventIdForTenant(tenantId: string, context: TenantContext) {
  const storedEventId = localStorage.getItem(selectedEventStorageKey(tenantId))
  return context.events.some((event) => event.id === storedEventId) ? storedEventId : context.events[0]?.id ?? null
}

function createLockState(
  isLocked: boolean,
  lockReason: SessionLockState['lockReason'],
  lastActivityAt: number,
  setLocked: (value: boolean) => void,
  setLockReason: (value: SessionLockState['lockReason']) => void,
  setLastActivityAt: (value: number) => void,
): SessionLockState {
  return {
    isLocked,
    lockReason,
    lastActivityAt,
    lock: (reason = 'manual') => {
      setLocked(true)
      setLockReason(reason)
      setLastActivityAt(Date.now())
    },
    unlock: () => {
      setLocked(false)
      setLockReason(null)
      setLastActivityAt(Date.now())
    },
    reset: () => {
      setLocked(false)
      setLockReason(null)
      setLastActivityAt(Date.now())
    },
  }
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [isLoading, setIsLoading] = useState(true)
  const [session, setSession] = useState<Session | null>(null)
  const [userContext, setUserContext] = useState<UserContext | null>(null)
  const [selectedTenantId, setSelectedTenantId] = useState<string | null>(() => localStorage.getItem(selectedTenantStorageKey))
  const [selectedEventId, setSelectedEventId] = useState<string | null>(null)
  const [selectedTenantContext, setSelectedTenantContext] = useState<TenantContext | null>(null)
  const [isLocked, setLocked] = useState(true)
  const [lockReason, setLockReason] = useState<SessionLockState['lockReason']>('startup')
  const [lastActivityAt, setLastActivityAt] = useState(() => Date.now())

  const lockState = useMemo(
    () => createLockState(isLocked, lockReason, lastActivityAt, setLocked, setLockReason, setLastActivityAt),
    [isLocked, lockReason, lastActivityAt],
  )

  const refreshContext = useCallback(async () => {
    const { data } = await supabase.auth.getSession()
    setSession(data.session)
    if (!data.session) {
      setUserContext(null)
      setSelectedEventId(null)
      setSelectedTenantContext(null)
      return null
    }
    const response = await api.me()
    setUserContext(response.data)
    return response.data
  }, [])

  const selectTenant = useCallback(async (tenantId: string) => {
    const response = await api.tenantContext(tenantId)
    localStorage.setItem(selectedTenantStorageKey, tenantId)
    setSelectedTenantId(tenantId)
    setSelectedTenantContext(response.data)
    setSelectedEventId(storedEventIdForTenant(tenantId, response.data))
    return response.data
  }, [])

  const selectEvent = useCallback((eventId: string | null) => {
    setSelectedEventId(eventId)
    if (!selectedTenantId) {
      return
    }
    if (eventId) {
      localStorage.setItem(selectedEventStorageKey(selectedTenantId), eventId)
    } else {
      localStorage.removeItem(selectedEventStorageKey(selectedTenantId))
    }
  }, [selectedTenantId])

  const clearTenant = useCallback(() => {
    localStorage.removeItem(selectedTenantStorageKey)
    setSelectedTenantId(null)
    setSelectedEventId(null)
    setSelectedTenantContext(null)
  }, [])

  const signOut = useCallback(async () => {
    await api.logout().catch(() => undefined)
    await supabase.auth.signOut()
    clearTenant()
    setSession(null)
    setUserContext(null)
    lockState.reset()
  }, [clearTenant, lockState])

  useEffect(() => {
    let cancelled = false
    async function restore() {
      setIsLoading(true)
      try {
        const context = await refreshContext()
        if (cancelled) {
          return
        }
        const activeMemberships = context?.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE') ?? []
        const storedTenant = selectedTenantId && activeMemberships.some((membership) => membership.tenantId === selectedTenantId)
        if (storedTenant) {
          await selectTenant(selectedTenantId)
        } else if (activeMemberships.length === 1) {
          await selectTenant(activeMemberships[0]?.tenantId ?? '')
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false)
        }
      }
    }
    void restore()
    const { data } = supabase.auth.onAuthStateChange(() => {
      void restore()
    })
    return () => {
      cancelled = true
      data.subscription.unsubscribe()
    }
  }, [refreshContext, selectTenant, selectedTenantId])

  const value = useMemo<SessionStore>(
    () => ({
      isLoading,
      session,
      userContext,
      selectedTenantId,
      selectedEventId,
      selectedTenantContext,
      lockState,
      refreshContext,
      selectTenant,
      selectEvent,
      clearTenant,
      signOut,
    }),
    [clearTenant, isLoading, lockState, refreshContext, selectEvent, selectTenant, selectedEventId, selectedTenantContext, selectedTenantId, session, signOut, userContext],
  )

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
}

export function useSessionStore(): SessionStore {
  const store = useContext(SessionContext)
  if (!store) {
    throw new Error('useSessionStore must be used inside SessionProvider')
  }
  return store
}

export { getSingleActiveMembership } from './session-selection'
