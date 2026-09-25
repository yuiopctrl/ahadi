import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { CalendarDays, CheckCircle2, Clock, MapPin, Users } from 'lucide-react'
import { api, ApiClientError } from '../lib/api'

interface InvitationData {
  invitation: { displayName: string; maxGuests: number }
  event: {
    name: string
    message: string | null
    date: string | null
    time: string | null
    venueName: string | null
    venueAddress: string | null
    mapsUrl: string | null
    hostDisplayName: string | null
  }
  rsvpSettings: { enabled: boolean; deadline: string | null; allowLateRsvp: boolean; canRespond: boolean }
  rsvp: { response: 'ATTENDING' | 'MAYBE' | 'NOT_ATTENDING'; attendingCount: number; guestNames: string[]; respondedAt: string } | null
  template: { layoutKey: string; config: Record<string, unknown> } | null
}

type Response = 'ATTENDING' | 'MAYBE' | 'NOT_ATTENDING'

function formatDate(value: string | null) {
  if (!value) return null
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return value
  return parsed.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })
}

function formatDeadline(value: string | null) {
  if (!value) return null
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return value
  return parsed.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
}

// Every domain error the public API can raise for a GET is mapped to one of
// two guest-facing states here: PGRST codes, Postgres messages and internal
// ids are never rendered. INVITATION_CANCELLED and an invalid/expired token
// intentionally render the SAME generic "not available" copy -- telling
// them apart would let a guest (or an attacker probing tokens) learn
// whether a given link was ever valid, which is exactly the kind of detail
// this page must not leak.
function unavailableReasonFrom(error: unknown): string {
  if (error instanceof ApiClientError) {
    if (error.code === 'INVITATION_NOT_ACTIVE') {
      return 'This invitation is not yet available.'
    }
  }
  return 'This invitation is not available.'
}

export function PublicInvitationPage() {
  const { token } = useParams<{ token: string }>()
  const [state, setState] = useState<'loading' | 'error' | 'ready'>('loading')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [data, setData] = useState<InvitationData | null>(null)
  const [response, setResponse] = useState<Response>('ATTENDING')
  const [guestCount, setGuestCount] = useState(1)
  const [guestNames, setGuestNames] = useState<string[]>([])
  const [note, setNote] = useState('')
  const [editing, setEditing] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submitted, setSubmitted] = useState(false)

  function load() {
    if (!token) {
      // Reported asynchronously (not directly in the effect body) so React
      // doesn't flag a synchronous setState-in-effect.
      Promise.resolve().then(() => {
        setState('error')
        setErrorMessage('This invitation is not available.')
      })
      return
    }
    Promise.resolve()
      .then(() => setState('loading'))
      .then(() => api.publicInvitation(token))
      .then((result) => {
        const payload = result.data as unknown as InvitationData
        setData(payload)
        setState('ready')
        if (payload.rsvp) {
          setResponse(payload.rsvp.response)
          setGuestCount(payload.rsvp.attendingCount || 1)
          setGuestNames(payload.rsvp.guestNames.length ? payload.rsvp.guestNames : [])
        }
      })
      .catch((error: unknown) => {
        setState('error')
        setErrorMessage(unavailableReasonFrom(error))
      })
  }

  useEffect(load, [token])

  async function submit() {
    if (!token) return
    setSubmitting(true)
    setSubmitError(null)
    try {
      const result = await api.submitPublicRsvp(token, {
        response,
        attendingCount: response === 'NOT_ATTENDING' ? 0 : guestCount,
        guestNames: response === 'NOT_ATTENDING' ? [] : guestNames.filter((name) => name.trim().length > 0),
        note: note.trim() || undefined,
      })
      const submittedData = result.data as { response: Response; attendingCount: number; guestNames: string[]; respondedAt: string }
      setData((current) =>
        current
          ? {
              ...current,
              rsvp: {
                response: submittedData.response,
                attendingCount: submittedData.attendingCount,
                guestNames: submittedData.guestNames,
                respondedAt: submittedData.respondedAt,
              },
            }
          : current,
      )
      setSubmitted(true)
      setEditing(false)
    } catch (error) {
      setSubmitError(publicRsvpErrorMessage(error))
    } finally {
      setSubmitting(false)
    }
  }

  if (state === 'loading') {
    return (
      <PublicShell>
        <div className="flex flex-col items-center gap-3 py-16 text-[var(--color-muted)]">
          <div className="h-8 w-8 animate-spin rounded-full border-2 border-[var(--color-border)] border-t-[var(--color-primary)]" />
          <p>Loading your invitation…</p>
        </div>
      </PublicShell>
    )
  }

  if (state === 'error' || !data) {
    return (
      <PublicShell>
        <div className="flex flex-col items-center gap-2 py-12 text-center">
          <h1 className="text-xl font-bold text-[var(--color-text)]">Invitation unavailable</h1>
          <p className="text-[var(--color-muted)]">{errorMessage}</p>
        </div>
      </PublicShell>
    )
  }

  const { invitation, event, rsvpSettings } = data
  const deadlineText = formatDeadline(rsvpSettings.deadline)
  const showReadOnly = !!data.rsvp && !rsvpSettings.canRespond && !editing

  return (
    <PublicShell>
      <div className="space-y-1 text-center">
        {event.hostDisplayName && <p className="text-sm font-medium uppercase tracking-wide text-[var(--color-muted)]">{event.hostDisplayName} invites you</p>}
        <h1 className="text-2xl font-extrabold text-[var(--color-text)]">{invitation.displayName}</h1>
        <p className="text-lg font-semibold text-[var(--color-primary)]">{event.name}</p>
        {event.message && <p className="pt-1 text-sm text-[var(--color-muted)]">{event.message}</p>}
      </div>

      <div className="mt-6 space-y-3 rounded-2xl border border-[var(--color-border)] bg-[var(--color-background)] p-4">
        {event.date && (
          <div className="flex items-center gap-3 text-sm text-[var(--color-text)]">
            <CalendarDays size={18} className="shrink-0 text-[var(--color-primary)]" aria-hidden />
            <span>
              {formatDate(event.date)}
              {event.time ? ` · ${event.time}` : ''}
            </span>
          </div>
        )}
        {(event.venueName || event.venueAddress) && (
          <div className="flex items-start gap-3 text-sm text-[var(--color-text)]">
            <MapPin size={18} className="mt-0.5 shrink-0 text-[var(--color-primary)]" aria-hidden />
            <span>
              {event.venueName}
              {event.venueAddress ? <span className="block text-[var(--color-muted)]">{event.venueAddress}</span> : null}
            </span>
          </div>
        )}
        <div className="flex items-center gap-3 text-sm text-[var(--color-text)]">
          <Users size={18} className="shrink-0 text-[var(--color-primary)]" aria-hidden />
          <span>Up to {invitation.maxGuests} guest{invitation.maxGuests === 1 ? '' : 's'}</span>
        </div>
        {deadlineText && (
          <div className="flex items-center gap-3 text-sm text-[var(--color-muted)]">
            <Clock size={18} className="shrink-0 text-[var(--color-primary)]" aria-hidden />
            <span>RSVP by {deadlineText}</span>
          </div>
        )}
        {event.mapsUrl && (
          <a
            href={event.mapsUrl}
            target="_blank"
            rel="noreferrer"
            className="mt-1 inline-flex items-center gap-2 rounded-lg bg-[var(--color-primary)] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[var(--color-primary-strong)]"
          >
            <MapPin size={16} aria-hidden /> Get Directions
          </a>
        )}
      </div>

      <div className="mt-6 border-t border-[var(--color-border)] pt-6">
        {submitted && !editing ? (
          <SuccessSummary
            response={response}
            guestCount={response === 'NOT_ATTENDING' ? 0 : guestCount}
            event={event}
            canEdit={rsvpSettings.canRespond}
            onEdit={() => setEditing(true)}
          />
        ) : !rsvpSettings.enabled ? (
          <ClosedNotice message="RSVP is not currently available." />
        ) : showReadOnly ? (
          <ExistingRsvpReadOnly rsvp={data.rsvp!} maxGuests={invitation.maxGuests} />
        ) : !rsvpSettings.canRespond && !data.rsvp ? (
          <ClosedNotice message="RSVP is closed." />
        ) : (
          <RsvpForm
            response={response}
            onResponseChange={setResponse}
            guestCount={guestCount}
            onGuestCountChange={setGuestCount}
            guestNames={guestNames}
            onGuestNamesChange={setGuestNames}
            note={note}
            onNoteChange={setNote}
            maxGuests={invitation.maxGuests}
            existing={data.rsvp}
            deadlinePassed={!rsvpSettings.canRespond}
            allowLateRsvp={rsvpSettings.allowLateRsvp}
            submitting={submitting}
            submitError={submitError}
            onSubmit={submit}
            onCancelEdit={data.rsvp ? () => setEditing(false) : undefined}
          />
        )}
      </div>
    </PublicShell>
  )
}

function publicRsvpErrorMessage(error: unknown): string {
  if (error instanceof ApiClientError) {
    switch (error.code) {
      case 'RSVP_DISABLED':
        return 'RSVP is not currently available.'
      case 'RSVP_DEADLINE_PASSED':
        return 'RSVP is closed.'
      case 'RSVP_GUEST_COUNT_INVALID':
        return 'Please choose a valid number of guests.'
      case 'RSVP_GUEST_NAMES_EXCEED_COUNT':
        return 'You listed more guest names than your guest count.'
      case 'INVITATION_CANCELLED':
      case 'INVITATION_TOKEN_INVALID':
      case 'INVITATION_TOKEN_EXPIRED_OR_ROTATED':
      case 'INVITATION_NOT_ACTIVE':
        return 'This invitation is not available.'
      default:
        break
    }
  }
  return 'We could not save your response. Please try again.'
}

function PublicShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-[var(--color-background)] px-4 py-8 sm:py-14">
      <div className="mx-auto w-full max-w-md rounded-3xl bg-[var(--color-card)] p-6 shadow-[0_10px_40px_rgba(23,32,51,0.08)] sm:p-8">
        {children}
      </div>
      <p className="mx-auto mt-6 max-w-md text-center text-xs text-[var(--color-muted)]">Changisha</p>
    </div>
  )
}

function ClosedNotice({ message }: { message: string }) {
  return (
    <div className="rounded-xl bg-[var(--color-warning-soft)] px-4 py-3 text-center text-sm font-medium text-[var(--color-warning)]">
      {message}
    </div>
  )
}

function ExistingRsvpReadOnly({ rsvp, maxGuests }: { rsvp: NonNullable<InvitationData['rsvp']>; maxGuests: number }) {
  return (
    <div>
      <h2 className="text-sm font-bold uppercase tracking-wide text-[var(--color-muted)]">Your RSVP</h2>
      <ResponseSummary response={rsvp.response} guestCount={rsvp.attendingCount} maxGuests={maxGuests} guestNames={rsvp.guestNames} />
      <p className="mt-3 text-xs text-[var(--color-muted)]">RSVP is closed, so this response can no longer be changed.</p>
    </div>
  )
}

function ResponseSummary({
  response,
  guestCount,
  maxGuests,
  guestNames,
}: {
  response: Response
  guestCount: number
  maxGuests: number
  guestNames: string[]
}) {
  const label = response === 'ATTENDING' ? 'Attending' : response === 'MAYBE' ? 'Maybe' : 'Not Attending'
  return (
    <div className="mt-2 rounded-xl border border-[var(--color-border)] p-4">
      <p className="text-lg font-extrabold text-[var(--color-text)]">{label}</p>
      {response !== 'NOT_ATTENDING' && (
        <p className="text-sm text-[var(--color-muted)]">
          {guestCount} of {maxGuests} guest{maxGuests === 1 ? '' : 's'}
        </p>
      )}
      {guestNames.length > 0 && (
        <ul className="mt-2 space-y-0.5 text-sm text-[var(--color-text)]">
          {guestNames.map((name, index) => (
            <li key={`${name}-${index}`}>{name}</li>
          ))}
        </ul>
      )}
    </div>
  )
}

function SuccessSummary({
  response,
  guestCount,
  event,
  canEdit,
  onEdit,
}: {
  response: Response
  guestCount: number
  event: InvitationData['event']
  canEdit: boolean
  onEdit: () => void
}) {
  return (
    <div className="text-center">
      <CheckCircle2 size={40} className="mx-auto text-[var(--color-success)]" aria-hidden />
      <h2 className="mt-2 text-lg font-extrabold text-[var(--color-text)]">Thank you. Your RSVP has been received.</h2>
      <div className="mt-4 space-y-1 text-sm text-[var(--color-text)]">
        <p>
          <span className="font-semibold">Response:</span> {response === 'ATTENDING' ? 'Attending' : response === 'MAYBE' ? 'Maybe' : 'Not Attending'}
        </p>
        {response !== 'NOT_ATTENDING' && (
          <p>
            <span className="font-semibold">Guests:</span> {guestCount}
          </p>
        )}
        {event.date && (
          <p>
            <span className="font-semibold">Date:</span> {formatDate(event.date)}
          </p>
        )}
        {event.venueName && (
          <p>
            <span className="font-semibold">Venue:</span> {event.venueName}
          </p>
        )}
      </div>
      {event.mapsUrl && (
        <a
          href={event.mapsUrl}
          target="_blank"
          rel="noreferrer"
          className="mt-4 inline-flex items-center gap-2 rounded-lg bg-[var(--color-primary)] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[var(--color-primary-strong)]"
        >
          <MapPin size={16} aria-hidden /> Get Directions
        </a>
      )}
      {canEdit && (
        <button type="button" onClick={onEdit} className="mt-4 block w-full text-sm font-semibold text-[var(--color-primary)] underline underline-offset-2">
          Change RSVP
        </button>
      )}
    </div>
  )
}

function RsvpForm({
  response,
  onResponseChange,
  guestCount,
  onGuestCountChange,
  guestNames,
  onGuestNamesChange,
  note,
  onNoteChange,
  maxGuests,
  existing,
  deadlinePassed,
  allowLateRsvp,
  submitting,
  submitError,
  onSubmit,
  onCancelEdit,
}: {
  response: Response
  onResponseChange: (value: Response) => void
  guestCount: number
  onGuestCountChange: (value: number) => void
  guestNames: string[]
  onGuestNamesChange: (value: string[]) => void
  note: string
  onNoteChange: (value: string) => void
  maxGuests: number
  existing: InvitationData['rsvp']
  deadlinePassed: boolean
  allowLateRsvp: boolean
  submitting: boolean
  submitError: string | null
  onSubmit: () => void
  onCancelEdit?: () => void
}) {
  const showGuestFields = response !== 'NOT_ATTENDING'

  return (
    <div>
      <h2 className="text-sm font-bold uppercase tracking-wide text-[var(--color-muted)]">
        {existing ? 'Your RSVP' : 'Will you attend?'}
      </h2>
      {deadlinePassed && allowLateRsvp && (
        <p className="mt-1 text-xs text-[var(--color-warning)]">The RSVP deadline has passed, but a late response is still accepted.</p>
      )}

      <div className="mt-3 grid grid-cols-3 gap-2">
        {(
          [
            ['ATTENDING', 'Yes'],
            ['MAYBE', 'Maybe'],
            ['NOT_ATTENDING', 'No'],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            onClick={() => onResponseChange(value)}
            className={`rounded-xl border px-3 py-3 text-sm font-bold transition ${
              response === value
                ? 'border-[var(--color-primary)] bg-[var(--color-primary-soft)] text-[var(--color-primary)]'
                : 'border-[var(--color-border)] text-[var(--color-text)] hover:border-[var(--color-primary)]'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {showGuestFields && (
        <div className="mt-4 space-y-3">
          <label className="block text-sm font-semibold text-[var(--color-text)]">
            {response === 'ATTENDING' ? 'Guests attending' : 'Potential guests'}
            <input
              type="number"
              min={1}
              max={maxGuests}
              value={guestCount}
              onChange={(event) => onGuestCountChange(Math.max(1, Math.min(maxGuests, Number(event.target.value) || 1)))}
              className="mt-1 block w-24 rounded-lg border border-[var(--color-border)] px-3 py-2 text-base"
            />
            <span className="ml-2 text-xs font-normal text-[var(--color-muted)]">max {maxGuests}</span>
          </label>

          <div>
            <p className="text-sm font-semibold text-[var(--color-text)]">Guest names (optional)</p>
            <div className="mt-1 space-y-2">
              {guestNames.map((name, index) => (
                <input
                  key={index}
                  value={name}
                  onChange={(event) => {
                    const next = [...guestNames]
                    next[index] = event.target.value
                    onGuestNamesChange(next)
                  }}
                  placeholder={`Guest ${index + 1}`}
                  className="block w-full rounded-lg border border-[var(--color-border)] px-3 py-2 text-sm"
                />
              ))}
              <button
                type="button"
                onClick={() => onGuestNamesChange([...guestNames, ''])}
                className="text-xs font-semibold text-[var(--color-primary)]"
              >
                + Add guest name
              </button>
            </div>
          </div>
        </div>
      )}

      <label className="mt-4 block text-sm font-semibold text-[var(--color-text)]">
        Note (optional)
        <textarea
          value={note}
          onChange={(event) => onNoteChange(event.target.value)}
          rows={2}
          className="mt-1 block w-full rounded-lg border border-[var(--color-border)] px-3 py-2 text-sm"
        />
      </label>

      {submitError && <p className="mt-3 text-sm font-medium text-[var(--color-danger)]">{submitError}</p>}

      <div className="mt-5 flex gap-2">
        {onCancelEdit && (
          <button
            type="button"
            onClick={onCancelEdit}
            className="flex-1 rounded-xl border border-[var(--color-border)] px-4 py-3 text-sm font-semibold text-[var(--color-text)]"
          >
            Cancel
          </button>
        )}
        <button
          type="button"
          disabled={submitting}
          onClick={onSubmit}
          className="flex-1 rounded-xl bg-[var(--color-primary)] px-4 py-3 text-sm font-bold text-white transition hover:bg-[var(--color-primary-strong)] disabled:opacity-60"
        >
          {submitting ? 'Saving…' : response === 'ATTENDING' ? 'Confirm RSVP' : response === 'MAYBE' ? 'Save' : 'Confirm'}
        </button>
      </div>
    </div>
  )
}
