import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { env } from './env'

export type NetworkStatus = 'checking' | 'online' | 'offline'

const healthCheckTimeoutMs = 3500
const healthCheckRetryDelayMs = 700

export function healthUrl(apiUrl = env.apiUrl) {
  return `${apiUrl.replace(/\/$/, '')}/health`
}

export function isConnectivityFailure(error: unknown) {
  return error instanceof TypeError || error instanceof DOMException && error.name === 'AbortError'
}

async function fetchHealth(signal: AbortSignal) {
  const response = await fetch(healthUrl(), {
    cache: 'no-store',
    credentials: 'omit',
    headers: { Accept: 'application/json' },
    signal,
  })
  return response.status
}

export async function resolveNetworkStatus({
  online = typeof navigator === 'undefined' ? true : navigator.onLine,
  attempts = 2,
  retryDelayMs = healthCheckRetryDelayMs,
  timeoutMs = healthCheckTimeoutMs,
}: {
  online?: boolean
  attempts?: number
  retryDelayMs?: number
  timeoutMs?: number
} = {}): Promise<NetworkStatus> {
  if (!online) {
    return 'offline'
  }

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const controller = new AbortController()
    const timeout = window.setTimeout(() => controller.abort(), timeoutMs)
    try {
      await fetchHealth(controller.signal)
      return 'online'
    } catch (error) {
      if (!isConnectivityFailure(error)) {
        return 'online'
      }
      if (attempt < attempts - 1) {
        await new Promise((resolve) => window.setTimeout(resolve, retryDelayMs))
      }
    } finally {
      window.clearTimeout(timeout)
    }
  }

  return 'offline'
}

function initialNetworkStatus(): NetworkStatus {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    return 'offline'
  }
  return 'checking'
}

export function NetworkStatusProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<NetworkStatus>(initialNetworkStatus)

  useEffect(() => {
    let cancelled = false

    async function check() {
      if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        setStatus('offline')
        return
      }
      setStatus('checking')
      const nextStatus = await resolveNetworkStatus()
      if (!cancelled) {
        setStatus(nextStatus)
      }
    }

    function handleOnline() {
      void check()
    }

    function handleOffline() {
      setStatus('offline')
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    void check()

    return () => {
      cancelled = true
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
    }
  }, [])

  return (
    <>
      {status === 'offline' ? (
        <div className="offline-banner" role="status">
          <strong>Ahadi is offline</strong>
          <span>Reconnect to continue managing pledges and payments.</span>
        </div>
      ) : null}
      {children}
    </>
  )
}
