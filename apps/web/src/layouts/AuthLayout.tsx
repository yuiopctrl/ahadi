import { Outlet } from 'react-router-dom'

export function AuthLayout() {
  return (
    <div className="auth-layout">
      <section className="auth-panel" aria-label="Ahadi authentication">
        <div className="auth-brand">
          <span className="brand-mark">A</span>
          <div>
            <strong>Ahadi</strong>
            <p>Community pledges, collected with care.</p>
          </div>
        </div>
        <Outlet />
      </section>
    </div>
  )
}
