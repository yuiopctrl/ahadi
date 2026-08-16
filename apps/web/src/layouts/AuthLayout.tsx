import { Outlet } from 'react-router-dom'

export function AuthLayout() {
  return (
    <div className="auth-layout">
      <section className="auth-panel" aria-label="Changisha authentication">
        <div className="auth-brand">
          <img className="brand-icon" src="/brand/app_icon.png" alt="" aria-hidden="true" />
          <img className="brand-wordmark" src="/brand/wordmark.png" alt="Changisha" />
          <p>Community pledges, collected with care.</p>
        </div>
        <Outlet />
      </section>
    </div>
  )
}
