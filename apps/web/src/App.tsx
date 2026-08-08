import { RouterProvider } from 'react-router-dom'
import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { AppProviders } from './app/providers'
import { api } from './lib/api'
import { env } from './lib/env'
import { router } from './routes'

class AppErrorBoundary extends Component<{ children: ReactNode }, { crashed: boolean }> {
  state = { crashed: false }

  static getDerivedStateFromError() {
    return { crashed: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    void api.reportFrontendError({
      appVersion: env.appVersion,
      browserSummary: navigator.userAgent.slice(0, 180),
      component: info.componentStack?.split('\n')[1]?.trim() ?? 'App',
      errorCode: error.name || 'FRONTEND_ERROR',
      metadata: { route: window.location.pathname },
      route: window.location.pathname,
    }).catch(() => undefined)
  }

  render() {
    if (this.state.crashed) {
      return (
        <main className="page-container page-container-narrow">
          <section className="state-card state-card-danger">
            <h1>Something went wrong</h1>
            <p>Refresh the page and try again. The error was reported to the Ahadi support console.</p>
          </section>
        </main>
      )
    }
    return this.props.children
  }
}

function App() {
  return (
    <AppProviders>
      <AppErrorBoundary>
        <RouterProvider router={router} />
      </AppErrorBoundary>
    </AppProviders>
  )
}

export default App
