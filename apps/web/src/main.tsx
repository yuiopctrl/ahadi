import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { env } from './lib/env'

console.info(`Ahadi web ${env.appVersion} (${env.buildCommit})`)

if (import.meta.env.DEV && 'serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((registrations) => {
    const hadController = Boolean(navigator.serviceWorker.controller)
    for (const registration of registrations) {
      registration.unregister()
    }
    if (hadController) {
      window.location.reload()
    }
  })
  if ('caches' in window) caches.keys().then((keys) => {
    for (const key of keys) {
      caches.delete(key)
    }
  })
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
