import { useMutation, useQuery } from '@tanstack/react-query'
import { ArrowLeft, CheckCircle2, LockKeyhole } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import type { OnboardingPayload, SubscriptionPlan, TenantMembershipContext } from '@ahadi/types'
import { normalizeTanzaniaPhone, onboardingPayloadSchema, setupPinSchema } from '@ahadi/validation'
import { api, ApiClientError } from '../lib/api'
import { supabase } from '../lib/supabase'
import { hasActivePlatformAccess } from '../routes/access'
import { getSingleActiveMembership, useSessionStore } from '../stores/session-store'
import { MoneyDisplay, StatusBadge } from '../components/ui'

type AuthMode = 'login' | 'otp' | 'pin' | 'register' | 'onboarding' | 'selectTenant'

interface AuthPageProps {
  title: string
  subtitle: string
  mode: AuthMode
}

const phoneDraftKey = 'ahadi:verification-phone'
const onboardingDraftKey = 'ahadi:onboarding-draft'
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

export function AuthPage({ title, subtitle, mode }: AuthPageProps) {
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
  return <LoginPage title={title} subtitle={mode === 'register' ? 'Create your first tenant after phone verification.' : subtitle} />
}

function LoginPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const location = useLocation()
  const [phone, setPhone] = useState(localStorage.getItem(phoneDraftKey) ?? '')
  const [error, setError] = useState<string | null>(null)
  const mutation = useMutation({
    mutationFn: async () => {
      const normalized = normalizeTanzaniaPhone(phone)
      await api.requestOtp(normalized)
      localStorage.setItem(phoneDraftKey, normalized)
      if (location.pathname.startsWith('/platform')) {
        localStorage.setItem(postAuthDestinationKey, '/platform')
      } else {
        localStorage.removeItem(postAuthDestinationKey)
      }
      return normalized
    },
    onSuccess: () => navigate('/verify-otp'),
    onError: (nextError) => setError(errorMessage(nextError)),
  })

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <label>
        Phone number
        <input inputMode="tel" placeholder="0712 345 678" value={phone} onChange={(event) => setPhone(event.target.value)} />
      </label>
      {error ? <p className="field-error">{error}</p> : null}
      <button className="primary-button" type="button" disabled={mutation.isPending} onClick={() => mutation.mutate()}>
        {mutation.isPending ? 'Sending...' : 'Continue'}
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
      const preferredDestination = localStorage.getItem(postAuthDestinationKey)
      const hasPin = await api.hasPin()
      if (!hasPin.hasPin) {
        navigate('/setup-pin', { replace: true })
        return
      }
      session.lockState.unlock()
      if (preferredDestination === '/platform' && hasActivePlatformAccess(context)) {
        localStorage.removeItem(postAuthDestinationKey)
        navigate('/platform', { replace: true })
        return
      }
      if (hasActivePlatformAccess(context) && !(context?.tenantMemberships.length ?? 0)) {
        navigate('/platform', { replace: true })
        return
      }
      if (!context?.onboardingCompleted) {
        navigate('/onboarding', { replace: true })
        return
      }
      const singleTenant = getSingleActiveMembership(context)
      if (singleTenant) {
        await session.selectTenant(singleTenant.tenantId)
        navigate('/app', { replace: true })
        return
      }
      navigate('/select-tenant', { replace: true })
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

function PinPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const session = useSessionStore()
  const [pin, setPin] = useState('')
  const [confirmPin, setConfirmPin] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [remaining, setRemaining] = useState<number | null>(null)
  const hasPinQuery = useQuery({
    queryKey: ['has-pin'],
    queryFn: api.hasPin,
  })
  const returningDevice = Boolean(hasPinQuery.data?.hasPin && session.lockState.isLocked)
  const mutation = useMutation({
    mutationFn: async () => {
      if (returningDevice) {
        return api.verifyPin(pin)
      }
      setupPinSchema.parse({ pin, confirmPin })
      await api.setPin(pin, confirmPin)
      return { ok: true, lockedUntil: null }
    },
    onSuccess: async (result) => {
      if (!result.ok) {
        setPin('')
        setRemaining(result.remainingAttempts ?? null)
        setError(result.lockedUntil ? `PIN is locked until ${new Date(result.lockedUntil).toLocaleTimeString()}` : 'Incorrect PIN')
        return
      }
      session.lockState.unlock()
      const context = await session.refreshContext()
      const preferredDestination = localStorage.getItem(postAuthDestinationKey)
      if (preferredDestination === '/platform' && hasActivePlatformAccess(context)) {
        localStorage.removeItem(postAuthDestinationKey)
        navigate('/platform', { replace: true })
        return
      }
      if (hasActivePlatformAccess(context) && !(context?.tenantMemberships.length ?? 0)) {
        navigate('/platform', { replace: true })
        return
      }
      if (!context?.onboardingCompleted) {
        navigate('/onboarding', { replace: true })
        return
      }
      const singleTenant = getSingleActiveMembership(context)
      if (singleTenant) {
        await session.selectTenant(singleTenant.tenantId)
        navigate('/app', { replace: true })
        return
      }
      navigate('/select-tenant', { replace: true })
    },
    onError: (nextError) => {
      setPin('')
      setError(errorMessage(nextError))
    },
  })

  return (
    <form className="auth-form" onSubmit={(event) => event.preventDefault()}>
      <div>
        <h1>{returningDevice ? 'Unlock Ahadi' : title}</h1>
        <p>{returningDevice ? 'Enter your four-digit application PIN for this authenticated device.' : subtitle}</p>
      </div>
      <div className="security-note">
        <LockKeyhole size={20} aria-hidden />
        <span>PIN unlocks this device only. Full logout, session expiry, or a new device requires OTP again.</span>
      </div>
      <label>
        PIN
        <input inputMode="numeric" type="password" maxLength={4} value={pin} onChange={(event) => setPin(event.target.value.replace(/\D/g, '').slice(0, 4))} />
      </label>
      {!returningDevice ? (
        <label>
          Confirm PIN
          <input
            inputMode="numeric"
            type="password"
            maxLength={4}
            value={confirmPin}
            onChange={(event) => setConfirmPin(event.target.value.replace(/\D/g, '').slice(0, 4))}
          />
        </label>
      ) : null}
      {error ? <p className="field-error">{error}{remaining !== null ? ` (${remaining} attempts left)` : ''}</p> : null}
      <button className="primary-button" type="button" disabled={pin.length !== 4 || mutation.isPending} onClick={() => mutation.mutate()}>
        {mutation.isPending ? 'Checking...' : returningDevice ? 'Unlock' : 'Continue'}
      </button>
    </form>
  )
}

function OnboardingPage() {
  const navigate = useNavigate()
  const session = useSessionStore()
  const [step, setStep] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [draft, setDraft] = useState<OnboardingDraft>(() => {
    const stored = localStorage.getItem(onboardingDraftKey)
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
    localStorage.setItem(onboardingDraftKey, JSON.stringify(draft))
  }, [draft])

  const mutation = useMutation({
    mutationFn: async () => {
      const payload: OnboardingPayload = {
        planCode: draft.planCode,
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
      localStorage.removeItem(onboardingDraftKey)
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

  return (
    <main className="onboarding-layout">
      <section className="onboarding-shell">
        <header className="onboarding-header">
          <div>
            <p className="eyebrow">Step {step + 1} of 5</p>
            <h1>{steps[step]}</h1>
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
          <button type="button" disabled={isRegistrationPaused || (step === 0 && isInviteOnly && !draft.betaInvitationCode.trim())} onClick={() => setStep((value) => Math.min(4, value + 1))}>Continue</button>
        ) : (
          <button type="button" disabled={!draft.confirmed || mutation.isPending || isRegistrationPaused || (isInviteOnly && !draft.betaInvitationCode.trim())} onClick={() => mutation.mutate()}>
            {mutation.isPending ? 'Creating...' : 'Create Account'}
          </button>
        )}
      </div>
    </main>
  )
}

function TenantSelectionPage({ title, subtitle }: Pick<AuthPageProps, 'title' | 'subtitle'>) {
  const navigate = useNavigate()
  const session = useSessionStore()
  const memberships = session.userContext?.tenantMemberships.filter((membership) => membership.membershipStatus === 'ACTIVE' && (membership.tenantStatus === 'ACTIVE' || membership.tenantStatus === 'TRIAL')) ?? []

  useEffect(() => {
    const singleTenant = getSingleActiveMembership(session.userContext)
    if (singleTenant) {
      void session.selectTenant(singleTenant.tenantId).then(() => navigate('/app', { replace: true }))
    }
  }, [navigate, session])

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
            <strong>{membership.tenantName}</strong>
            <span>{membership.tenantCode} · {membership.subscription?.status ?? 'No subscription'}</span>
            <small>{membership.roles.join(', ') || 'Member'} · {membership.accessibleEvents.filter((event) => event.status === 'ACTIVE').length} active events</small>
            <StatusBadge tone={membership.tenantStatus === 'ACTIVE' || membership.tenantStatus === 'TRIAL' ? 'success' : 'danger'}>{membership.tenantStatus}</StatusBadge>
          </button>
        ))}
      </div>
      {session.userContext?.isPlatformUser && session.userContext.platformStatus === 'ACTIVE' && session.userContext.platformPermissions.includes('platform.dashboard.view') ? (
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
