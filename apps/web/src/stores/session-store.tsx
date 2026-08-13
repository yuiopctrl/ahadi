/* eslint-disable react-refresh/only-export-components */
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { Session } from '@supabase/supabase-js'
import type { TenantContext, UserContext } from '@ahadi/types'
import { api, ApiClientError } from '../lib/api'
import { supabase } from '../lib/supabase'

export interface SessionLockState {
  isLocked: boolean
  lockReason: 'idle' | 'manual' | 'startup' | null
  lastActivityAt: number
  lock: (reason?: SessionLockState['lockReason']) => void
  unlock: () => void
  reset: () => void
}

export type BootstrapState =
  | 'INITIALIZING'
  | 'RESTORING_SESSION'
  | 'RESOLVING_ACCESS'
  | 'READY'
  | 'UNAUTHENTICATED'
  | 'ERROR'

export type AuthStatus = 'INITIALIZING' | 'AUTHENTICATED' | 'UNAUTHENTICATED' | 'ERROR'

export type AccessState = {
  platform: {
    status: 'LOADING' | 'ACTIVE' | 'INACTIVE' | 'NONE' | 'ERROR'
    role?: UserContext['platformRole']
  }
  tenant: {
    status: 'LOADING' | 'READY' | 'ONBOARDING_REQUIRED' | 'NONE' | 'ERROR'
  }
}

interface SessionStore {
  isLoading: boolean
  authStatus: AuthStatus
  accessState: AccessState
  bootstrapState: BootstrapState
  bootstrapError: string | null
  session: Session | null
  userContext: UserContext | null
  selectedTenantId: string | null
  selectedEventId: string | null
  selectedTenantContext: TenantContext | null
  lockState: SessionLockState
  refreshContext: () => Promise<UserContext | null>
  selectTenant: (tenantId: string) => Promise<TenantContext>
  selectEvent: (eventId: string | null) => void
  clearTenant: (clearStoredEvents?: boolean) => void
  signOut: () => Promise<void>
}

const SessionContext = createContext<SessionStore | null>(null)

const selectedTenantStorageKey = 'ahadi:selected-tenant-id'
const activePlatformRoles = new Set(['PLATFORM_OWNER', 'PLATFORM_ADMIN', 'PLATFORM_SUPPORT', 'PLATFORM_AUDITOR'])

function selectedEventStorageKey(tenantId: string) {
  return `ahadi:selected-event-id:${tenantId}`
}

function clearStoredEventSelections() {
  for (const key of Object.keys(localStorage)) {
    if (key.startsWith('ahadi:selected-event-id:')) {
      localStorage.removeItem(key)
    }
  }
}

function hasActivePlatformIdentity(context: UserContext | null) {
  return Boolean(context?.platformStatus === 'ACTIVE' && context.platformRole && activePlatformRoles.has(context.platformRole))
}

function isBootstrapLoading(state: BootstrapState) {
  return state === 'INITIALIZING' || state === 'RESTORING_SESSION' || state === 'RESOLVING_ACCESS'
}

function authStatusForBootstrap(state: BootstrapState, session: Session | null): AuthStatus {
  if (isBootstrapLoading(state)) return 'INITIALIZING'
  if (state === 'ERROR') return 'ERROR'
  if (state === 'UNAUTHENTICATED') return 'UNAUTHENTICATED'
  return session ? 'AUTHENTICATED' : 'UNAUTHENTICATED'
}

function accessStateForBootstrap(state: BootstrapState, context: UserContext | null): AccessState {
  if (isBootstrapLoading(state)) {
    return { platform: { status: 'LOADING' }, tenant: { status: 'LOADING' } }
  }
  if (state === 'ERROR') {
    return { platform: { status: 'ERROR' }, tenant: { status: 'ERROR' } }
  }
  const activeMemberships = context?.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE') ?? []
  return {
    platform: hasActivePlatformIdentity(context)
      ? { status: 'ACTIVE', role: context?.platformRole }
      : context?.platformRole || context?.platformStatus
        ? { status: 'INACTIVE', role: context.platformRole }
        : { status: 'NONE' },
    tenant: activeMemberships.length
      ? context?.onboardingCompleted
        ? { status: 'READY' }
        : { status: 'ONBOARDING_REQUIRED' }
      : { status: 'NONE' },
  }
}

function isExpiredSessionError(error: unknown) {
  return error instanceof ApiClientError && error.code === 'SESSION_REQUIRED'
}

function bootstrapErrorMessage(error: unknown) {
  if (error instanceof ApiClientError) {
    return error.message
  }
  if (error instanceof Error) {
    return error.message
  }
  return 'Unable to restore your session. Please try again.'
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
  const queryClient = useQueryClient()
  const [bootstrapState, setBootstrapState] = useState<BootstrapState>('INITIALIZING')
  const [bootstrapError, setBootstrapError] = useState<string | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [userContext, setUserContext] = useState<UserContext | null>(null)
  const [selectedTenantId, setSelectedTenantId] = useState<string | null>(() => localStorage.getItem(selectedTenantStorageKey))
  const [selectedEventId, setSelectedEventId] = useState<string | null>(null)
  const [selectedTenantContext, setSelectedTenantContext] = useState<TenantContext | null>(null)
  const [isLocked, setLocked] = useState(true)
  const [lockReason, setLockReason] = useState<SessionLockState['lockReason']>('startup')
  const [lastActivityAt, setLastActivityAt] = useState(() => Date.now())
  const selectedTenantIdRef = useRef(selectedTenantId)
  const restoreRunIdRef = useRef(0)

  const lockState = useMemo(
    () => createLockState(isLocked, lockReason, lastActivityAt, setLocked, setLockReason, setLastActivityAt),
    [isLocked, lockReason, lastActivityAt],
  )

  const resetLockState = useCallback(() => {
    setLocked(false)
    setLockReason(null)
    setLastActivityAt(Date.now())
  }, [])

  useEffect(() => {
    selectedTenantIdRef.current = selectedTenantId
  }, [selectedTenantId])

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
    await queryClient.cancelQueries()
    localStorage.setItem(selectedTenantStorageKey, tenantId)
    setSelectedTenantId(tenantId)
    setSelectedTenantContext(response.data)
    setSelectedEventId(storedEventIdForTenant(tenantId, response.data))
    await queryClient.invalidateQueries()
    return response.data
  }, [queryClient])

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

  const clearTenant = useCallback((clearStoredEvents = false) => {
    localStorage.removeItem(selectedTenantStorageKey)
    if (clearStoredEvents) {
      clearStoredEventSelections()
    }
    setSelectedTenantId(null)
    setSelectedEventId(null)
    setSelectedTenantContext(null)
  }, [])

  const signOut = useCallback(async () => {
    await queryClient.cancelQueries()
    await api.logout().catch(() => undefined)
    await supabase.auth.signOut()
    clearTenant(true)
    setSession(null)
    setUserContext(null)
    queryClient.clear()
    resetLockState()
  }, [clearTenant, queryClient, resetLockState])

  const restoreTenantSelection = useCallback(async (context: UserContext) => {
    const activeMemberships = context.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE')
    const storedTenantId = selectedTenantIdRef.current
    const storedTenant = storedTenantId && activeMemberships.some((membership) => membership.tenantId === storedTenantId)
    const singleTenant = !hasActivePlatformIdentity(context) && activeMemberships.length === 1 ? activeMemberships[0] : null
    const tenantId = storedTenant ? storedTenantId : singleTenant?.tenantId ?? null

    if (!tenantId) {
      if (storedTenantId && !storedTenant) {
        clearTenant()
      }
      return
    }

    try {
      await selectTenant(tenantId)
    } catch {
      if (selectedTenantIdRef.current === tenantId) {
        clearTenant()
      }
    }
  }, [clearTenant, selectTenant])

  useEffect(() => {
    let cancelled = false
    async function restore() {
      const restoreRunId = restoreRunIdRef.current + 1
      restoreRunIdRef.current = restoreRunId
      setBootstrapState('RESTORING_SESSION')
      setBootstrapError(null)
      try {
        const { data } = await supabase.auth.getSession()
        if (cancelled || restoreRunId !== restoreRunIdRef.current) {
          return
        }
        setSession(data.session)
        if (!data.session) {
          setUserContext(null)
          clearTenant(true)
          resetLockState()
          setBootstrapState('UNAUTHENTICATED')
          return
        }

        setBootstrapState('RESOLVING_ACCESS')
        const context = await refreshContext()
        if (cancelled || restoreRunId !== restoreRunIdRef.current || !context) {
          return
        }
        await restoreTenantSelection(context)
        if (!cancelled && restoreRunId === restoreRunIdRef.current) {
          setBootstrapState('READY')
        }
      } catch (error) {
        if (cancelled || restoreRunId !== restoreRunIdRef.current) {
          return
        }
        if (isExpiredSessionError(error)) {
          await supabase.auth.signOut().catch(() => undefined)
          setSession(null)
          setUserContext(null)
          clearTenant(true)
          resetLockState()
          setBootstrapState('UNAUTHENTICATED')
          return
        }
        setBootstrapError(bootstrapErrorMessage(error))
        setBootstrapState('ERROR')
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
  }, [clearTenant, refreshContext, resetLockState, restoreTenantSelection])

  const isLoading = isBootstrapLoading(bootstrapState)
  const authStatus = authStatusForBootstrap(bootstrapState, session)
  const accessState = accessStateForBootstrap(bootstrapState, userContext)

  const value = useMemo<SessionStore>(
    () => ({
      isLoading,
      authStatus,
      accessState,
      bootstrapState,
      bootstrapError,
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
    [accessState, authStatus, bootstrapError, bootstrapState, clearTenant, isLoading, lockState, refreshContext, selectEvent, selectTenant, selectedEventId, selectedTenantContext, selectedTenantId, session, signOut, userContext],
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
