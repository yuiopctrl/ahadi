import type { UserContext, UserProfile } from '@ahadi/types'

type JsonRecord = Record<string, unknown>

function jsonRecord(value: unknown): JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as JsonRecord : {}
}

function stringValue(record: JsonRecord, camelKey: string, snakeKey: string, fallback = ''): string {
  const value = record[camelKey] ?? record[snakeKey]
  return typeof value === 'string' ? value : fallback
}

function nullableStringValue(record: JsonRecord, camelKey: string, snakeKey: string): string | null {
  const value = record[camelKey] ?? record[snakeKey]
  return typeof value === 'string' && value.trim() !== '' ? value : null
}

export function normalizeProfile(value: unknown): UserProfile | null {
  const profile = jsonRecord(value)
  const id = stringValue(profile, 'id', 'id')
  if (!id) {
    return null
  }

  return {
    ...profile,
    id,
    fullName: stringValue(profile, 'fullName', 'full_name'),
    phoneE164: stringValue(profile, 'phoneE164', 'phone_e164'),
    email: nullableStringValue(profile, 'email', 'email'),
    avatarUrl: nullableStringValue(profile, 'avatarUrl', 'avatar_url'),
    status: stringValue(profile, 'status', 'status', 'PENDING') as UserProfile['status'],
    preferredLanguage: stringValue(profile, 'preferredLanguage', 'preferred_language', 'sw') as UserProfile['preferredLanguage'],
    onboardingCompletedAt: nullableStringValue(profile, 'onboardingCompletedAt', 'onboarding_completed_at'),
  } as UserProfile
}

export function normalizeUserContext(value: unknown): UserContext {
  const context = jsonRecord(value)
  return {
    ...context,
    profile: normalizeProfile(context['profile']),
  } as unknown as UserContext
}
