/* eslint-disable react-refresh/only-export-components */
import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'

export type NetworkState = 'CHECKING' | 'ONLINE' | 'OFFLINE'

export function resolveNetworkStatus({
  online = typeof navigator === 'undefined' ? true : navigator.onLine,
}: {
  online?: boolean
} = {}): NetworkState {
  return online ? 'ONLINE' : 'OFFLINE'
}

function initialNetworkStatus(): NetworkState {
  return 'CHECKING'
}

const offlineEventGraceMs = 2500

export function NetworkStatusProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<NetworkState>(initialNetworkStatus)
  const offlineTimerRef = useRef<number | null>(null)

  useEffect(() => {
    function clearOfflineTimer() {
      if (offlineTimerRef.current !== null) {
        window.clearTimeout(offlineTimerRef.current)
        offlineTimerRef.current = null
      }
    }

    function handleOnline() {
      clearOfflineTimer()
      setStatus('ONLINE')
    }

    function handleOffline() {
      clearOfflineTimer()
      offlineTimerRef.current = window.setTimeout(() => {
        if (navigator.onLine === false) {
          setStatus('OFFLINE')
        }
      }, offlineEventGraceMs)
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    if (resolveNetworkStatus() === 'OFFLINE') {
      handleOffline()
    } else {
      handleOnline()
    }

    return () => {
      clearOfflineTimer()
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
    }
  }, [])

  return (
    <>
      {status === 'OFFLINE' ? (
        <div className="offline-banner" role="status">
          <strong>Ahadi is offline</strong>
          <span>Reconnect to continue managing pledges and payments.</span>
        </div>
      ) : null}
      {children}
    </>
  )
}
