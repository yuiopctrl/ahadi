import { Link } from 'react-router-dom'

interface AuthPageProps {
  title: string
  subtitle: string
  mode: 'login' | 'otp' | 'pin' | 'register' | 'onboarding'
}

export function AuthPage({ title, subtitle, mode }: AuthPageProps) {
  const primaryLabel =
    mode === 'login'
      ? 'Continue'
      : mode === 'otp'
        ? 'Verify code'
        : mode === 'pin'
          ? 'Save PIN'
          : mode === 'register'
            ? 'Create account'
            : 'Finish setup'

  return (
    <form className="auth-form">
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {mode === 'otp' ? (
        <label>
          Verification code
          <input inputMode="numeric" placeholder="123456" />
        </label>
      ) : null}
      {mode === 'pin' ? (
        <label>
          Secure PIN
          <input inputMode="numeric" type="password" placeholder="4 digits" />
        </label>
      ) : null}
      {mode === 'register' || mode === 'onboarding' ? (
        <label>
          Committee or organization name
          <input placeholder="Mrema Family Committee" />
        </label>
      ) : null}
      <label>
        Phone number
        <input inputMode="tel" placeholder="+255 712 345 678" />
      </label>
      <button type="button" className="primary-button">
        {primaryLabel}
      </button>
      <p className="auth-link">
        <Link to="/register">Create tenant</Link>
        <Link to="/login">Sign in</Link>
      </p>
    </form>
  )
}
