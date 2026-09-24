import { MutationCache, QueryCache, QueryClient } from '@tanstack/react-query'
import { ApiClientError } from './api'

// Centralized session-expiry detection, mirroring the Flutter tenant
// app's ApiClient.onSessionExpired: one place notices a live (post-
// bootstrap) query/mutation came back with an expired/invalid session,
// instead of every page having to check for it itself. SessionProvider
// registers the actual handler (it owns the React-scoped sign-out logic);
// this module only detects and forwards the event.
let sessionExpiredHandler: (() => void) | null = null

export function setSessionExpiredHandler(handler: (() => void) | null) {
  sessionExpiredHandler = handler
}

function isSessionExpiredError(error: unknown) {
  return error instanceof ApiClientError && error.code === 'SESSION_REQUIRED'
}

function notifySessionExpiredIfNeeded(error: unknown) {
  if (isSessionExpiredError(error)) {
    sessionExpiredHandler?.()
  }
}

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
  queryCache: new QueryCache({ onError: notifySessionExpiredIfNeeded }),
  mutationCache: new MutationCache({ onError: notifySessionExpiredIfNeeded }),
})
