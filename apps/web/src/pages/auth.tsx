import { useMutation, useQuery } from '@tanstack/react-query'
import { ArrowLeft, CheckCircle2, LockKeyhole } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import type { OnboardingPayload, SubscriptionPlan, TenantMembershipContext, UserContext } from '@ahadi/types'
import { normalizeTanzaniaPhone, onboardingPayloadSchema, setupPinSchema } from '@ahadi/validation'
import { api, ApiClientError } from '../lib/api'
import { supabase } from '../lib/supabase'
import { getPostAuthDestination, hasActivePlatformAccess, hasTenantWorkspaceAccess } from '../routes/access'
import { getSingleActiveMembership, useSessionStore } from '../stores/session-store'
import { MoneyDisplay, StatusBadge } from '../components/ui'
import { PinEntry, canSubmitPin } from '../components/pin-entry'

type AuthMode = 'login' | 'forgotPin' | 'otp' | 'pin' | 'register' | 'onboarding' | 'selectTenant' | 'workspace'
type OnboardingIntent = 'FIRST_TENANT' | 'CREATE_ADDITIONAL_TENANT'

interface AuthPageProps {
  title: string
  subtitle: string
  mode: AuthMode
}

const phoneDraftKey = 'ahadi:verification-phone'
const onboardingDraftKey = 'ahadi:onboarding-draft'
const additionalOrganizationDraftKey = 'ahadi:additional-organization-draft'
const postAuthDestinationKey = 'ahadi:post-auth-destination'

interface OnboardingDraft {
  planCode: string
  tenantName: string
  tenantPhone: string
  tenantEmail: string
  adminFullName: string
  adminEmail: string
  preferredLanguage: 'sw' | 'en'
  firstEventName: string
  eventType: OnboardingPayload['eventType']
  customEventType: string
  eventDate: string
  venue: string
  targetAmount: string
  pledgeDeadline: string
  betaInvitationCode: string
  confirmed: boolean
}

interface PlanApiRow extends Partial<SubscriptionPlan> {
  billing_interval?: SubscriptionPlan['billingInterval']
  display_order?: number
  included_sms?: number
  is_active?: boolean
  is_public?: boolean
  max_active_events?: number
  max_members?: number
  max_users?: number
  price_amount?: number | string
  trial_days?: number
}

const defaultDraft: OnboardingDraft = {
  planCode: '',
  tenantName: '',
  tenantPhone: '',
  tenantEmail: '',
  adminFullName: '',
  adminEmail: '',
  preferredLanguage: 'sw',
  firstEventName: '',
  eventType: 'WEDDING',
  customEventType: '',
  eventDate: '',
  venue: '',
  targetAmount: '',
  pledgeDeadline: '',
  betaInvitationCode: '',
  confirmed: false,
}

function numberValue(value: number | string | undefined, fallback = 0) {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

function normalizePlan(row: PlanApiRow): SubscriptionPlan {
  return {
    id: row.id ?? row.code ?? '',
    code: row.code ?? '',
    name: row.name ?? 'Plan',
    description: row.description ?? '',
    currency: row.currency ?? 'TZS',
    priceAmount: numberValue(row.priceAmount ?? row.price_amount),
    billingInterval: row.billingInterval ?? row.billing_interval ?? 'CUSTOM',
    trialDays: numberValue(row.trialDays ?? row.trial_days),
    maxActiveEvents: numberValue(row.maxActiveEvents ?? row.max_active_events),
    maxMembers: numberValue(row.maxMembers ?? row.max_members),
    maxUsers: numberValue(row.maxUsers ?? row.max_users),
    includedSms: numberValue(row.includedSms ?? row.included_sms),
    features: row.features ?? {},
    isPublic: row.isPublic ?? row.is_public ?? true,
    isActive: row.isActive ?? row.is_active ?? true,
    displayOrder: numberValue(row.displayOrder ?? row.display_order),
  }
}

function formatBillingInterval(plan: Pick<SubscriptionPlan, 'billingInterval'>) {
  return (plan.billingInterval ?? 'CUSTOM').toLowerCase()
}

function activeEventLimitLabel(count: number) {
  return count === 1 ? '1 active event' : `Up to ${count} active events`
}

const onboardingFieldLabels: Record<string, string> = {
  adminEmail: 'administrator email',
  adminFullName: 'administrator full name',
  betaInvitationCode: 'beta invitation code',
  customEventType: 'custom event type',
  eventDate: 'event date',
  firstEventName: 'event name',
  planCode: 'package',
  pledgeDeadline: 'pledge deadline',
  preferredLanguage: 'preferred language',
  targetAmount: 'target amount',
  tenantEmail: 'organization email',
  tenantName: 'organization name',
  tenantPhone: 'organization phone number',
  venue: 'venue',
}

function onboardingValidationMessage(error: { issues: { message: string; path: PropertyKey[] }[] }) {
  const issue = error.issues[0]
  const path = issue?.path.join('.') ?? ''
  const label = onboardingFieldLabels[path] ?? path
  return label ? `Check ${label}: ${issue?.message ?? 'invalid value'}` : 'Check the onboarding details and try again.'
}

function errorMessage(error: unknown) {
  if (error instanceof ApiClientError) {
    if (error.code === 'PIN_TOO_WEAK') {
      return 'Choose a stronger 4-digit PIN. Avoid repeated, sequential, or very common numbers.'
    }
    if (error.code === 'PIN_INVALID') {
      return 'Incorrect PIN. Try again.'
    }
    if (error.code === 'PIN_LOCKED') {
      return 'PIN is temporarily locked after too many attempts. Try again shortly.'
    }
    return error.message
  }
  if (error instanceof Error) {
    if (error.message.trim().startsWith('{') || error.message.includes('"code"')) {
      return 'Check the PIN and try again.'
    }
    return error.message
  }
  return 'Something went wrong'
}

async function routeAfterAuthentication({
  context,
  navigate,
  session,
}: {
  context: UserContext | null
  navigate: ReturnType<typeof useNavigate>
  session: ReturnType<typeof useSessionStore>
}) {
  const preferredDestination = localStorage.getItem(postAuthDestinationKey)
  const destination = getPostAuthDestination(context, preferredDestination)
  localStorage.removeItem(postAuthDestinationKey)
  const singleTenant = destination === '/app' ? getSingleActiveMembership(context) : null
  if (singleTenant) {
    await session.selectTenant(singleTenant.tenantId)
  }
  navigate(destination, { replace: true })
}

export function AuthPage({ title, subtitle, mode }: AuthPageProps) {
  if (mode === 'forgotPin') {
    return <ForgotPinPage title={title} subtitle={subtitle} />
  }
  if (mode === 'otp') {
    return <OtpPage title={title} subtitle={subtitle} />
  }
  if (mode === 'pin') {
    return <PinPage title={title} subtitle={subtitle} />
  }
  if (mode === 'onboarding') {
    return <OnboardingPage />
  }
  if (mode === 'selectTenant') {
    return <TenantSelectionPage title={title} subtitle={subtitle} />
  }
  if (mode === 'workspace') {
    return <WorkspaceChooserPage title={title} subtitle={subtitle} />
  }
  if (mode === 'register') {
    return <OtpRequestPage title={title} subtitle={subtitle} />
  }
  return <LoginPage title={title} subtitle={subtitle} />
}

function LoginPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const location = useLocation()
  const routeState = location.state as { from?: { pathname?: string } } | null
  const session = useSessionStore()
  const [phone, setPhone] = useState(localStorage.getItem(phoneDraftKey) ?? '')
  const [pin, setPin] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const submittingRef = useRef(false)

  function storePostAuthDestination() {
    if (location.pathname.startsWith('/platform')) {
      const requestedPlatformPath = routeState?.from?.pathname?.startsWith('/platform') ? routeState.from.pathname : '/platform'
      localStorage.setItem(postAuthDestinationKey, requestedPlatformPath === '/platform/login' ? '/platform' : requestedPlatformPath)
    } else if (routeState?.from?.pathname === '/organizations/new') {
      localStorage.setItem(postAuthDestinationKey, '/organizations/new')
    } else {
      localStorage.removeItem(postAuthDestinationKey)
    }
  }

  const mutation = useMutation({
    mutationFn: async (values: { phone: string; pin: string }) => {
      const normalized = normalizeTanzaniaPhone(values.phone)
      localStorage.setItem(phoneDraftKey, normalized)
      storePostAuthDestination()
      const response = await api.loginWithPin(normalized, values.pin)
      await supabase.auth.setSession({
        access_token: response.session.access_token,
        refresh_token: response.session.refresh_token,
      })
      return normalized
    },
    onSuccess: async () => {
      submittingRef.current = false
      setIsSubmitting(false)
      session.lockState.unlock()
      const context = await session.refreshContext()
      await routeAfterAuthentication({ context, navigate, session })
    },
    onError: (nextError) => {
      submittingRef.current = false
      setIsSubmitting(false)
      setPin('')
      setError(errorMessage(nextError))
    },
  })
  const loginPending = mutation.isPending || isSubmitting
  const loginReady = canSubmitPin({ pin, isPending: mutation.isPending, isSubmitting })

  function submitLogin(nextPin = pin) {
    if (!canSubmitPin({ pin: nextPin, isPending: mutation.isPending, isSubmitting: submittingRef.current })) {
      return
    }
    if (mutation.isPending || submittingRef.current) {
      return
    }
    submittingRef.current = true
    setIsSubmitting(true)
    setError(null)
    mutation.mutate({ phone, pin: nextPin })
  }

  return (
    <form className="auth-form" onSubmit={(event) => {
      event.preventDefault()
      submitLogin()
    }}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <label>
        Phone number
        <input inputMode="tel" autoComplete="tel" placeholder="0712 345 678" value={phone} disabled={loginPending} onChange={(event) => setPhone(event.target.value)} />
      </label>
      <PinEntry
        label="PIN"
        value={pin}
        disabled={loginPending}
        onChange={setPin}
        onComplete={(nextPin) => submitLogin(nextPin)}
        onEnterComplete={() => submitLogin()}
      />
      {error ? <p className="field-error">{error}</p> : null}
      {error?.includes('No verified Ahadi account') ? (
        <button className="text-button" type="button" onClick={() => navigate('/register')}>
          Create an organization
        </button>
      ) : null}
      <button className="primary-button" type="submit" disabled={!loginReady}>
        {mutation.isPending ? 'Signing in...' : 'Login'}
      </button>
      {location.pathname === '/login' ? (
        <>
          <button className="text-button" type="button" onClick={() => navigate('/forgot-pin')}>
            Forgot PIN?
          </button>
          <button className="text-button" type="button" onClick={() => navigate('/register')}>
            Create a new organization
          </button>
          <button className="text-button" type="button" onClick={() => navigate('/platform/login')}>
            Platform Administration
          </button>
        </>
      ) : null}
      {location.pathname === '/platform/login' ? (
        <button className="text-button" type="button" onClick={() => navigate('/login')}>
          Existing Ahadi account login
        </button>
      ) : null}
      <p className="privacy-note">We use your phone number only to secure your Ahadi account and send requested verification messages.</p>
    </form>
  )
}

function OtpRequestPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const [phone, setPhone] = useState(localStorage.getItem(phoneDraftKey) ?? '')
  const [error, setError] = useState<string | null>(null)
  const mutation = useMutation({
    mutationFn: async () => {
      const normalized = normalizeTanzaniaPhone(phone)
      await api.requestOtp(normalized)
      localStorage.setItem(phoneDraftKey, normalized)
      localStorage.setItem(postAuthDestinationKey, '/onboarding')
      return normalized
    },
    onSuccess: () => navigate('/verify-otp'),
    onError: (nextError) => setError(errorMessage(nextError)),
  })

  return (
    <form className="auth-form" onSubmit={(event) => {
      event.preventDefault()
      mutation.mutate()
    }}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <label>
        Phone number
        <input inputMode="tel" autoComplete="tel" placeholder="0712 345 678" value={phone} disabled={mutation.isPending} onChange={(event) => setPhone(event.target.value)} />
      </label>
      {error ? <p className="field-error">{error}</p> : null}
      <button className="primary-button" type="submit" disabled={mutation.isPending}>
        {mutation.isPending ? 'Sending...' : 'Continue'}
      </button>
      <button className="text-button" type="button" onClick={() => navigate('/login')}>
        I already have an account
      </button>
      <p className="privacy-note">We use your phone number only to secure your Ahadi account and send requested verification messages.</p>
    </form>
  )
}

function OtpPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const session = useSessionStore()
  const [digits, setDigits] = useState('')
  const [seconds, setSeconds] = useState(45)
  const [error, setError] = useState<string | null>(null)
  const phone = localStorage.getItem(phoneDraftKey) ?? ''

  useEffect(() => {
    const timer = window.setInterval(() => setSeconds((value) => Math.max(0, value - 1)), 1000)
    return () => window.clearInterval(timer)
  }, [])

  const mutation = useMutation({
    mutationFn: async (token: string) => {
      const response = await api.verifyOtp(phone, token)
      await supabase.auth.setSession({
        access_token: response.session.access_token,
        refresh_token: response.session.refresh_token,
      })
    },
    onSuccess: async () => {
      const context = await session.refreshContext()
      const hasPin = await api.hasPin()
      if (!hasPin.hasPin) {
        navigate('/setup-pin', { replace: true })
        return
      }
      session.lockState.unlock()
      await routeAfterAuthentication({ context, navigate, session })
    },
    onError: (nextError) => {
      setDigits('')
      setError(errorMessage(nextError))
    },
  })

  useEffect(() => {
    if (digits.length === 6 && !mutation.isPending) {
      mutation.mutate(digits)
    }
  }, [digits, mutation])

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <p className="phone-summary">Code sent to {phone || 'your phone'}</p>
      <label>
        Six-digit code
        <input
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={6}
          placeholder="123456"
          value={digits}
          onChange={(event) => setDigits(event.target.value.replace(/\D/g, '').slice(0, 6))}
        />
      </label>
      {error ? <p className="field-error">{error}</p> : null}
      <button className="primary-button" type="button" disabled={digits.length !== 6 || mutation.isPending} onClick={() => mutation.mutate(digits)}>
        {mutation.isPending ? 'Verifying...' : 'Verify code'}
      </button>
      <button className="text-button" type="button" onClick={() => navigate('/login')}>
        Change phone
      </button>
      <p className="privacy-note">Resend available in {seconds}s. OTP is never stored by Ahadi.</p>
    </form>
  )
}

function ForgotPinPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const session = useSessionStore()
  const [step, setStep] = useState<'phone' | 'otp' | 'pin'>('phone')
  const [phone, setPhone] = useState(localStorage.getItem(phoneDraftKey) ?? '')
  const [token, setToken] = useState('')
  const [pin, setPin] = useState('')
  const [confirmPin, setConfirmPin] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const submittingRef = useRef(false)

  const requestMutation = useMutation({
    mutationFn: async () => {
      const normalized = normalizeTanzaniaPhone(phone)
      await api.requestOtp(normalized)
      localStorage.setItem(phoneDraftKey, normalized)
      return normalized
    },
    onSuccess: (normalized) => {
      submittingRef.current = false
      setIsSubmitting(false)
      setPhone(normalized)
      setError(null)
      setStep('otp')
    },
    onError: (nextError) => {
      submittingRef.current = false
      setIsSubmitting(false)
      setError(errorMessage(nextError))
    },
  })

  const verifyMutation = useMutation({
    mutationFn: async (nextToken: string) => {
      const normalized = normalizeTanzaniaPhone(phone)
      const response = await api.verifyOtp(normalized, nextToken)
      await supabase.auth.setSession({
        access_token: response.session.access_token,
        refresh_token: response.session.refresh_token,
      })
    },
    onSuccess: () => {
      submittingRef.current = false
      setIsSubmitting(false)
      setError(null)
      setStep('pin')
    },
    onError: (nextError) => {
      submittingRef.current = false
      setIsSubmitting(false)
      setToken('')
      setError(errorMessage(nextError))
    },
  })

  const pinMutation = useMutation({
    mutationFn: async (values: { pin: string; confirmPin: string }) => {
      setupPinSchema.parse(values)
      await api.setPin(values.pin, values.confirmPin)
    },
    onSuccess: async () => {
      submittingRef.current = false
      setIsSubmitting(false)
      session.lockState.unlock()
      const context = await session.refreshContext()
      await routeAfterAuthentication({ context, navigate, session })
    },
    onError: (nextError) => {
      submittingRef.current = false
      setIsSubmitting(false)
      setPin('')
      setConfirmPin('')
      setError(errorMessage(nextError))
    },
  })

  function requestReset() {
    if (requestMutation.isPending || submittingRef.current) return
    submittingRef.current = true
    setIsSubmitting(true)
    setError(null)
    requestMutation.mutate()
  }

  function verifyReset(nextToken = token) {
    if (nextToken.length !== 6 || verifyMutation.isPending || submittingRef.current) return
    submittingRef.current = true
    setIsSubmitting(true)
    setError(null)
    verifyMutation.mutate(nextToken)
  }

  function submitPin(nextPin = pin, nextConfirmPin = confirmPin) {
    if (!canSubmitPin({ pin: nextPin, confirmPin: nextConfirmPin, isPending: pinMutation.isPending, isSubmitting: submittingRef.current })) return
    submittingRef.current = true
    setIsSubmitting(true)
    setError(null)
    pinMutation.mutate({ pin: nextPin, confirmPin: nextConfirmPin })
  }

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {step === 'phone' ? (
        <>
          <label>
            Phone number
            <input inputMode="tel" autoComplete="tel" placeholder="0712 345 678" value={phone} disabled={requestMutation.isPending} onChange={(event) => setPhone(event.target.value)} />
          </label>
          {error ? <p className="field-error">{error}</p> : null}
          <button className="primary-button" type="button" disabled={requestMutation.isPending || isSubmitting} onClick={requestReset}>
            {requestMutation.isPending ? 'Sending...' : 'Send reset code'}
          </button>
        </>
      ) : null}
      {step === 'otp' ? (
        <>
          <p className="phone-summary">Code sent to {phone || 'your phone'}</p>
          <label>
            Six-digit code
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              placeholder="123456"
              value={token}
              disabled={verifyMutation.isPending}
              onChange={(event) => {
                const nextToken = event.target.value.replace(/\D/g, '').slice(0, 6)
                setToken(nextToken)
                if (nextToken.length === 6) {
                  verifyReset(nextToken)
                }
              }}
            />
          </label>
          {error ? <p className="field-error">{error}</p> : null}
          <button className="primary-button" type="button" disabled={token.length !== 6 || verifyMutation.isPending || isSubmitting} onClick={() => verifyReset()}>
            {verifyMutation.isPending ? 'Verifying...' : 'Verify code'}
          </button>
        </>
      ) : null}
      {step === 'pin' ? (
        <>
          <PinEntry label="New PIN" value={pin} disabled={pinMutation.isPending || isSubmitting} autoFocus onChange={setPin} onEnterComplete={() => submitPin()} />
          <PinEntry
            label="Confirm new PIN"
            value={confirmPin}
            disabled={pinMutation.isPending || isSubmitting}
            onChange={setConfirmPin}
            onComplete={(nextConfirmPin) => submitPin(pin, nextConfirmPin)}
            onEnterComplete={() => submitPin()}
          />
          {error ? <p className="field-error">{error}</p> : null}
          <button className="primary-button" type="button" disabled={!canSubmitPin({ pin, confirmPin, isPending: pinMutation.isPending, isSubmitting })} onClick={() => submitPin()}>
            {pinMutation.isPending ? 'Saving...' : 'Set PIN and Login'}
          </button>
        </>
      ) : null}
      <button className="text-button" type="button" onClick={() => navigate('/login')}>
        Back to Login
      </button>
    </form>
  )
}

function PinPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const location = useLocation()
  const routeState = location.state as { postAuthDestination?: string } | null
  const session = useSessionStore()
  const [pin, setPin] = useState('')
  const [confirmPin, setConfirmPin] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [remaining, setRemaining] = useState<number | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const submittingRef = useRef(false)
  const hasPinQuery = useQuery({
    queryKey: ['has-pin'],
    queryFn: api.hasPin,
  })
  const returningDevice = Boolean(hasPinQuery.data?.hasPin && session.lockState.isLocked)
  const mutation = useMutation({
    mutationFn: async (values: { pin: string; confirmPin: string }) => {
      if (returningDevice) {
        return api.verifyPin(values.pin)
      }
      setupPinSchema.parse({ pin: values.pin, confirmPin: values.confirmPin })
      await api.setPin(values.pin, values.confirmPin)
      return { ok: true, lockedUntil: null }
    },
    onSuccess: async (result) => {
      if (!result.ok) {
        submittingRef.current = false
        setIsSubmitting(false)
        setPin('')
        setConfirmPin('')
        setRemaining(result.remainingAttempts ?? null)
        setError(result.lockedUntil ? `PIN is locked until ${new Date(result.lockedUntil).toLocaleTimeString()}` : 'Incorrect PIN')
        return
      }
      session.lockState.unlock()
      const context = await session.refreshContext()
      if (routeState?.postAuthDestination) {
        localStorage.setItem(postAuthDestinationKey, routeState.postAuthDestination)
      }
      await routeAfterAuthentication({ context, navigate, session })
    },
    onError: (nextError) => {
      submittingRef.current = false
      setIsSubmitting(false)
      setPin('')
      setConfirmPin('')
      setError(errorMessage(nextError))
    },
  })
  const pinSubmissionPending = mutation.isPending || isSubmitting

  function submitPin(nextPin = pin, nextConfirmPin = confirmPin) {
    if (!canSubmitPin({ pin: nextPin, confirmPin: returningDevice ? undefined : nextConfirmPin, isPending: mutation.isPending, isSubmitting: submittingRef.current })) {
      return
    }
    submittingRef.current = true
    setIsSubmitting(true)
    setError(null)
    setRemaining(null)
    mutation.mutate({ pin: nextPin, confirmPin: nextConfirmPin })
  }

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{returningDevice ? 'Unlock Ahadi' : title}</h1>
        <p>{returningDevice ? 'Enter your four-digit application PIN for this authenticated device.' : subtitle}</p>
      </div>
      <div className="security-note">
        <LockKeyhole size={20} aria-hidden />
        <span>PIN protects account access. Full logout, session expiry, or a new device signs in with phone and PIN.</span>
      </div>
      <PinEntry
        label="PIN"
        value={pin}
        disabled={pinSubmissionPending}
        autoFocus
        onChange={setPin}
        onComplete={(nextPin) => {
          if (returningDevice) {
            submitPin(nextPin, confirmPin)
          }
        }}
        onEnterComplete={() => submitPin()}
      />
      {!returningDevice ? (
        <PinEntry
          label="Confirm PIN"
          value={confirmPin}
          disabled={pinSubmissionPending}
          onChange={setConfirmPin}
          onComplete={(nextConfirmPin) => submitPin(pin, nextConfirmPin)}
          onEnterComplete={() => submitPin()}
        />
      ) : null}
      {error ? <p className="field-error">{error}{remaining !== null ? ` (${remaining} attempts left)` : ''}</p> : null}
      <button className="primary-button" type="button" disabled={!canSubmitPin({ pin, confirmPin: returningDevice ? undefined : confirmPin, isPending: mutation.isPending, isSubmitting })} onClick={() => submitPin()}>
        {mutation.isPending ? 'Checking...' : returningDevice ? 'Unlock' : 'Continue'}
      </button>
    </form>
  )
}

function OnboardingPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const session = useSessionStore()
  const intent: OnboardingIntent = location.pathname.replace(/\/+$/, '') === '/organizations/new' ? 'CREATE_ADDITIONAL_TENANT' : 'FIRST_TENANT'
  const draftKey = intent === 'CREATE_ADDITIONAL_TENANT' ? additionalOrganizationDraftKey : onboardingDraftKey
  const currentTenantId = session.selectedTenantId
  const [step, setStep] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [draft, setDraft] = useState<OnboardingDraft>(() => {
    const stored = localStorage.getItem(draftKey)
    return stored ? ({ ...defaultDraft, ...JSON.parse(stored) } as OnboardingDraft) : defaultDraft
  })
  const plansQuery = useQuery({
    queryKey: ['plans'],
    queryFn: async () => ((await api.plans()).data as PlanApiRow[]).map(normalizePlan),
  })
  const rolloutQuery = useQuery({
    queryKey: ['rollout-settings'],
    queryFn: async () => (await api.rolloutSettings()).data,
  })
  const selectedPlan = plansQuery.data?.find((plan) => plan.code === draft.planCode)
  const registrationMode = String(rolloutQuery.data?.['registrationMode'] ?? 'OPEN')
  const isInviteOnly = registrationMode === 'INVITE_ONLY'
  const isRegistrationPaused = registrationMode === 'PAUSED'

  useEffect(() => {
    localStorage.setItem(draftKey, JSON.stringify(draft))
  }, [draft, draftKey])

  const mutation = useMutation({
    mutationFn: async () => {
      const payload: OnboardingPayload = {
        planCode: draft.planCode,
        onboardingIntent: intent,
        tenantName: draft.tenantName,
        tenantPhone: draft.tenantPhone || session.userContext?.profile?.phoneE164 || '',
        tenantEmail: draft.tenantEmail || null,
        adminFullName: draft.adminFullName,
        adminEmail: draft.adminEmail || null,
        preferredLanguage: draft.preferredLanguage,
        firstEventName: draft.firstEventName,
        eventType: draft.eventType,
        customEventType: draft.customEventType || null,
        eventDate: draft.eventDate || null,
        venue: draft.venue || null,
        targetAmount: draft.targetAmount ? Number(draft.targetAmount) : null,
        pledgeDeadline: draft.pledgeDeadline || null,
        betaInvitationCode: draft.betaInvitationCode || null,
        idempotencyKey: crypto.randomUUID(),
      }
      const parsedPayload = onboardingPayloadSchema.safeParse(payload)
      if (!parsedPayload.success) {
        throw new Error(onboardingValidationMessage(parsedPayload.error))
      }
      return api.completeOnboarding(parsedPayload.data)
    },
    onSuccess: async (result) => {
      localStorage.removeItem(draftKey)
      await session.refreshContext()
      const onboardingResult = result as { tenant_id?: string; tenantId?: string; event_id?: string; eventId?: string }
      const tenantId = onboardingResult.tenant_id ?? onboardingResult.tenantId
      const eventId = onboardingResult.event_id ?? onboardingResult.eventId
      if (tenantId) {
        await session.selectTenant(tenantId)
      }
      navigate(eventId ? `/app/events/${eventId}` : '/app', { replace: true })
    },
    onError: (nextError) => setError(errorMessage(nextError)),
  })

  const setField = <K extends keyof OnboardingDraft>(key: K, value: OnboardingDraft[K]) => setDraft((current) => ({ ...current, [key]: value }))
  const steps = ['Package', 'Organization', 'Admin', 'Event', 'Review']
  const heading = intent === 'CREATE_ADDITIONAL_TENANT' ? 'Create another organization' : steps[step]
  const subtext = intent === 'CREATE_ADDITIONAL_TENANT' ? 'This organization will have its own events, users, settings and subscription.' : null

  function cancelOnboarding() {
    localStorage.removeItem(draftKey)
    if (intent === 'CREATE_ADDITIONAL_TENANT') {
      navigate(currentTenantId ? '/app' : '/select-tenant', { replace: true })
      return
    }
    navigate('/login', { replace: true })
  }

  return (
    <main className="onboarding-layout">
      <section className="onboarding-shell">
        <header className="onboarding-header">
          <div>
            <p className="eyebrow">Step {step + 1} of 5</p>
            <h1>{heading}</h1>
            {subtext ? <p>{subtext}</p> : null}
          </div>
          <div className="progress-dots" aria-label="Onboarding progress">
            {steps.map((item, index) => (
              <span className={index <= step ? 'active' : ''} key={item} />
            ))}
          </div>
        </header>
        {step === 0 ? (
          <div className="package-stack">
            {rolloutQuery.data?.['maintenanceNotice'] ? <p className="notice-banner">{String(rolloutQuery.data['maintenanceNotice'])}</p> : null}
            {isRegistrationPaused ? (
              <p className="field-error">New workspace registration is temporarily paused. Existing tenants can still sign in.</p>
            ) : null}
            {isInviteOnly ? (
              <label className="invite-code-field">
                Beta invitation code
                <input value={draft.betaInvitationCode} placeholder="AHADI-BETA-XXXXXX" onChange={(event) => setField('betaInvitationCode', event.target.value.toUpperCase())} />
              </label>
            ) : null}
            {(plansQuery.data ?? []).map((plan) => (
              <button className={draft.planCode === plan.code ? 'package-card selected' : 'package-card'} key={plan.code} type="button" onClick={() => setField('planCode', plan.code)}>
                <strong>{plan.name}</strong>
                <MoneyDisplay amount={plan.priceAmount} />
                <span>{formatBillingInterval(plan)} billing, {plan.trialDays ?? 0} trial days</span>
                <small>{activeEventLimitLabel(plan.maxActiveEvents)} · {plan.maxUsers} users · {plan.maxMembers} members · {plan.includedSms} SMS</small>
              </button>
            ))}
          </div>
        ) : null}
        {step === 1 ? (
          <div className="form-grid">
            <Input label="Organization or committee name" value={draft.tenantName} onChange={(value) => setField('tenantName', value)} />
            <Input label="Phone number" value={draft.tenantPhone || session.userContext?.profile?.phoneE164 || ''} inputMode="tel" onChange={(value) => setField('tenantPhone', value)} />
            <Input label="Email optional" value={draft.tenantEmail} onChange={(value) => setField('tenantEmail', value)} />
            <Readonly label="Country" value="Tanzania" />
            <Readonly label="Currency" value="TZS" />
            <Readonly label="Timezone" value="Africa/Dar_es_Salaam" />
          </div>
        ) : null}
        {step === 2 ? (
          <div className="form-grid">
            <Input label="Full name" value={draft.adminFullName} onChange={(value) => setField('adminFullName', value)} />
            <Readonly label="Authenticated phone" value={session.userContext?.profile?.phoneE164 ?? 'Verified phone'} />
            <Input label="Email optional" value={draft.adminEmail} onChange={(value) => setField('adminEmail', value)} />
            <label>
              Preferred language
              <select value={draft.preferredLanguage} onChange={(event) => setField('preferredLanguage', event.target.value as 'sw' | 'en')}>
                <option value="sw">Kiswahili</option>
                <option value="en">English</option>
              </select>
            </label>
          </div>
        ) : null}
        {step === 3 ? (
          <div className="form-grid">
            <Input label="Event name" value={draft.firstEventName} onChange={(value) => setField('firstEventName', value)} />
            <label>
              Event type
              <select value={draft.eventType} onChange={(event) => setField('eventType', event.target.value as OnboardingPayload['eventType'])}>
                {['WEDDING', 'SENDOFF', 'FUNERAL', 'FUNDRAISER', 'BIRTHDAY', 'GRADUATION', 'RELIGIOUS', 'OTHER'].map((item) => (
                  <option key={item} value={item}>{item}</option>
                ))}
              </select>
            </label>
            {draft.eventType === 'OTHER' ? <Input label="Custom event type" value={draft.customEventType} onChange={(value) => setField('customEventType', value)} /> : null}
            <Input label="Event date optional" type="date" value={draft.eventDate} onChange={(value) => setField('eventDate', value)} />
            <Input label="Venue optional" value={draft.venue} onChange={(value) => setField('venue', value)} />
            <Input label="Target amount optional" inputMode="decimal" value={draft.targetAmount} onChange={(value) => setField('targetAmount', value)} />
            <Input label="Pledge deadline optional" type="date" value={draft.pledgeDeadline} onChange={(value) => setField('pledgeDeadline', value)} />
          </div>
        ) : null}
        {step === 4 ? (
          <div className="review-stack">
            <Review title="Package" value={selectedPlan ? `${selectedPlan.name} · ${activeEventLimitLabel(selectedPlan.maxActiveEvents)}` : 'Select a package'} />
            <Review title="Organization" value={`${draft.tenantName || 'Not set'} · ${draft.tenantPhone || 'No phone'}`} />
            <Review title="Administrator" value={`${draft.adminFullName || 'Not set'} · ${draft.preferredLanguage === 'sw' ? 'Kiswahili' : 'English'}`} />
            <Review title="First event" value={`${draft.firstEventName || 'Not set'} · ${draft.eventType}`} />
            <label className="checkbox-row">
              <input type="checkbox" checked={draft.confirmed} onChange={(event) => setField('confirmed', event.target.checked)} />
              I confirm these details are correct.
            </label>
          </div>
        ) : null}
        {error ? <p className="field-error">{error}</p> : null}
      </section>
      <div className="onboarding-action-bar">
        <button type="button" disabled={step === 0 || mutation.isPending} onClick={() => setStep((value) => Math.max(0, value - 1))}>
          <ArrowLeft size={18} aria-hidden />
          Back
        </button>
        {step < 4 ? (
          <button className="primary-button" type="button" disabled={isRegistrationPaused || (step === 0 && isInviteOnly && !draft.betaInvitationCode.trim())} onClick={() => setStep((value) => Math.min(4, value + 1))}>Continue</button>
        ) : (
          <button className="primary-button" type="button" disabled={!draft.confirmed || mutation.isPending || isRegistrationPaused || (isInviteOnly && !draft.betaInvitationCode.trim())} onClick={() => mutation.mutate()}>
            {mutation.isPending ? 'Creating...' : intent === 'CREATE_ADDITIONAL_TENANT' ? 'Create Organization' : 'Create Account'}
          </button>
        )}
        <button type="button" disabled={mutation.isPending} onClick={cancelOnboarding}>Cancel</button>
      </div>
    </main>
  )
}

function WorkspaceChooserPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const session = useSessionStore()
  const canOpenTenant = hasTenantWorkspaceAccess(session.userContext)
  const canOpenPlatform = hasActivePlatformAccess(session.userContext)

  async function openOrganization() {
    const singleTenant = getSingleActiveMembership(session.userContext)
    if (singleTenant) {
      await session.selectTenant(singleTenant.tenantId)
      navigate('/app', { replace: true })
      return
    }
    navigate('/select-tenant', { replace: true })
  }

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {canOpenTenant ? (
        <button type="button" className="tenant-card" onClick={() => void openOrganization()}>
          <strong>Organization</strong>
          <span>Manage events, contacts, pledges and payments.</span>
        </button>
      ) : null}
      {canOpenTenant ? (
        <button type="button" className="tenant-card" onClick={() => navigate('/organizations/new')}>
          <strong>Create another organization</strong>
          <span>Start a separate organization with its own package, data and settings.</span>
        </button>
      ) : null}
      {canOpenPlatform ? (
        <button type="button" className="tenant-card" onClick={() => navigate('/platform', { replace: true })}>
          <strong>Platform Administration</strong>
          <span>Manage Ahadi tenants and platform operations.</span>
        </button>
      ) : null}
      {!canOpenTenant && !canOpenPlatform ? (
        <p className="field-error">No workspace access is enabled for this account.</p>
      ) : null}
    </form>
  )
}

function TenantSelectionPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const session = useSessionStore()
  const memberships = session.userContext?.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE' && (membership.tenantStatus === 'ACTIVE' || membership.tenantStatus === 'TRIAL')) ?? []

  async function chooseTenant(membership: TenantMembershipContext) {
    await session.selectTenant(membership.tenantId)
    navigate('/app', { replace: true })
  }

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <div className="tenant-card-stack">
        {memberships.map((membership) => (
          <button type="button" className="tenant-card" key={membership.tenantId} onClick={() => void chooseTenant(membership)}>
            <strong>{membership.tenantId === session.selectedTenantId ? `✓ ${membership.tenantName}` : membership.tenantName}</strong>
            <span>{membership.tenantCode} · {membership.subscription?.status ?? 'No subscription'}</span>
            <small>{membership.roles.join(', ') || 'Member'} · {membership.accessibleEvents.filter((event) => event.status === 'ACTIVE').length} active events</small>
            <StatusBadge tone={membership.tenantStatus === 'ACTIVE' || membership.tenantStatus === 'TRIAL' ? 'success' : 'danger'}>{membership.tenantStatus}</StatusBadge>
          </button>
        ))}
      </div>
      {!memberships.length ? (
        <div className="security-note">
          <CheckCircle2 size={20} aria-hidden />
          <span>No organization workspace is linked to this account yet.</span>
        </div>
      ) : null}
      <button type="button" className="text-button" onClick={() => navigate(memberships.length ? '/organizations/new' : '/register')}>
        {memberships.length ? 'Create another organization' : 'Create a new organization'}
      </button>
      {hasActivePlatformAccess(session.userContext) ? (
        <button type="button" className="text-button" onClick={() => navigate('/platform')}>
          Open Platform Console
        </button>
      ) : null}
    </form>
  )
}

function Input({
  label,
  value,
  onChange,
  inputMode,
  type = 'text',
}: {
  label: string
  value: string
  onChange: (value: string) => void
  inputMode?: 'text' | 'tel' | 'numeric' | 'decimal'
  type?: string
}) {
  return (
    <label>
      {label}
      <input type={type} inputMode={inputMode} value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  )
}

function Readonly({ label, value }: { label: string; value: string }) {
  return (
    <label>
      {label}
      <input value={value} readOnly />
    </label>
  )
}

function Review({ title, value }: { title: string; value: string }) {
  return (
    <div className="review-card">
      <CheckCircle2 size={18} aria-hidden />
      <div>
        <strong>{title}</strong>
        <span>{value}</span>
      </div>
    </div>
  )
}
