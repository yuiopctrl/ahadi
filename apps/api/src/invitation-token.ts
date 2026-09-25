import { createHmac, timingSafeEqual } from 'node:crypto'
import { env } from './env.js'

// Signed capability token for public invitation links, per RSVP-1's public
// token design: base64url(invitationId + "." + tokenVersion) + "." +
// base64url(HMAC-SHA256(secret, payload)). Stateless -- nothing about the
// token itself is stored in the database, only the plain integer
// public_token_version on the invitation row, which the signature's payload
// must match. Rotating that integer (rpc_rotate_invitation_public_token)
// invalidates every previously issued token instantly, without needing a
// token blocklist.
//
// The database independently re-checks token_version against the live row
// on every public read/write (see rpc_get_public_invitation_detail /
// rpc_submit_public_invitation_rsvp) -- this module only proves "the holder
// of this string once had a version-N capability for this invitation," it
// does not itself guarantee the capability is still current.

const invitationIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function sign(payload: string): string {
  return createHmac('sha256', env.INVITATION_PUBLIC_TOKEN_SECRET).update(payload).digest('base64url')
}

export function signInvitationToken(invitationId: string, tokenVersion: number): string {
  const payload = `${invitationId}.${tokenVersion}`
  const encodedPayload = Buffer.from(payload, 'utf8').toString('base64url')
  return `${encodedPayload}.${sign(payload)}`
}

export function buildPublicInvitationUrl(invitationId: string, tokenVersion: number): string {
  const token = signInvitationToken(invitationId, tokenVersion)
  const base = env.INVITATION_PUBLIC_APP_BASE_URL.replace(/\/+$/, '')
  return `${base}/${token}`
}

export interface VerifiedInvitationToken {
  invitationId: string
  tokenVersion: number
}

export function verifyInvitationToken(token: string): VerifiedInvitationToken | null {
  if (typeof token !== 'string' || token.length === 0 || token.length > 512) {
    return null
  }
  const parts = token.split('.')
  if (parts.length !== 2) {
    return null
  }
  const encodedPayload = parts[0]
  const signature = parts[1]
  if (!encodedPayload || !signature) {
    return null
  }
  let payload: string
  try {
    payload = Buffer.from(encodedPayload, 'base64url').toString('utf8')
  } catch {
    return null
  }

  const expectedSignature = sign(payload)
  const providedBuffer = Buffer.from(signature)
  const expectedBuffer = Buffer.from(expectedSignature)
  if (providedBuffer.length !== expectedBuffer.length || !timingSafeEqual(providedBuffer, expectedBuffer)) {
    return null
  }

  const match = payload.match(/^(.+)\.(\d+)$/)
  if (!match) {
    return null
  }
  const invitationId = match[1]
  const versionText = match[2]
  if (!invitationId || !versionText || !invitationIdPattern.test(invitationId)) {
    return null
  }
  const tokenVersion = Number(versionText)
  if (!Number.isInteger(tokenVersion) || tokenVersion < 1) {
    return null
  }

  return { invitationId, tokenVersion }
}
