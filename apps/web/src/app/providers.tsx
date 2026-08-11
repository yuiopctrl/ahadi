import { QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { queryClient } from '../lib/query-client'
import { NetworkStatusProvider } from '../lib/network-status'
import { SessionProvider } from '../stores/session-store'

interface AppProvidersProps {
  children: ReactNode
}

export function AppProviders({ children }: AppProvidersProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <NetworkStatusProvider>
        <SessionProvider>{children}</SessionProvider>
      </NetworkStatusProvider>
    </QueryClientProvider>
  )
}
