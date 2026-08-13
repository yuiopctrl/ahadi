import { z } from 'zod'

const tzPhoneRegex = /^\+255[67][0-9]{8}$/

export function normalizeTanzaniaPhone(input: string): string {
  const trimmed = input.trim()
  const cleaned = trimmed.startsWith('+')
    ? `+${trimmed.slice(1).replace(/\D/g, '')}`
    : trimmed.replace(/\D/g, '')

  if (tzPhoneRegex.test(cleaned)) {
    return cleaned
  }

  if (/^255[67][0-9]{8}$/.test(cleaned)) {
    return `+${cleaned}`
  }

  if (/^0[67][0-9]{8}$/.test(cleaned)) {
    return `+255${cleaned.slice(1)}`
  }

  throw new Error('INVALID_PHONE')
}

export const tanzaniaPhoneSchema = z
  .string()
  .min(1)
  .transform((value, context) => {
    try {
      return normalizeTanzaniaPhone(value)
    } catch {
      context.addIssue({ code: 'custom', message: 'Invalid Tanzanian phone number' })
      return z.NEVER
    }
  })

export const uuidHeaderSchema = z.string().uuid()
export const planCodeSchema = z.string().trim().min(1).transform((value) => value.toUpperCase())

export const eventTypeSchema = z.enum([
  'WEDDING',
  'SENDOFF',
  'FUNERAL',
  'FUNDRAISER',
  'BIRTHDAY',
  'GRADUATION',
  'RELIGIOUS',
  'OTHER',
])

export const tzsAmountSchema = z.coerce.number().finite().nonnegative().max(999_999_999_999.99)

export const requestOtpSchema = z.object({
  phone: tanzaniaPhoneSchema,
})

export const verifyOtpSchema = z.object({
  phone: tanzaniaPhoneSchema,
  token: z.string().regex(/^[0-9]{6}$/),
})

const weakPins = new Set(['0000', '1111', '1234', '4321'])

const nullableEmailSchema = z.union([z.email(), z.literal(''), z.null()]).optional().transform((value) => value || null)
const nullableDateSchema = z.union([z.iso.date(), z.literal(''), z.null()]).optional().transform((value) => value || null)
const nullableTextSchema = (max: number) => z.union([z.string().trim().max(max), z.literal(''), z.null()]).optional().transform((value) => value || null)

export function isWeakPin(pin: string): boolean {
  return !/^[0-9]{4}$/.test(pin) || weakPins.has(pin) || /^([0-9])\1{3}$/.test(pin)
}

export const setupPinSchema = z
  .object({
    pin: z.string().regex(/^[0-9]{4}$/),
    confirmPin: z.string().regex(/^[0-9]{4}$/).optional(),
  })
  .superRefine((value, context) => {
    if (isWeakPin(value.pin)) {
      context.addIssue({ code: 'custom', path: ['pin'], message: 'Choose a stronger PIN' })
    }
    if (value.confirmPin !== undefined && value.pin !== value.confirmPin) {
      context.addIssue({ code: 'custom', path: ['confirmPin'], message: 'PINs do not match' })
    }
  })

export const verifyPinSchema = z.object({
  pin: z.string().regex(/^[0-9]{4}$/),
})

export const changePinSchema = z
  .object({
    currentPin: z.string().regex(/^[0-9]{4}$/),
    newPin: z.string().regex(/^[0-9]{4}$/),
    confirmNewPin: z.string().regex(/^[0-9]{4}$/),
  })
  .superRefine((value, context) => {
    if (isWeakPin(value.newPin)) {
      context.addIssue({ code: 'custom', path: ['newPin'], message: 'Choose a stronger PIN' })
    }
    if (value.newPin !== value.confirmNewPin) {
      context.addIssue({ code: 'custom', path: ['confirmNewPin'], message: 'PINs do not match' })
    }
  })

export const phonePinLoginSchema = z.object({
  phone: tanzaniaPhoneSchema,
  pin: z.string().regex(/^[0-9]{4}$/),
})

export const organizationSchema = z.object({
  tenantName: z.string().trim().min(2).max(120),
  tenantPhone: tanzaniaPhoneSchema,
  tenantEmail: nullableEmailSchema,
  countryCode: z.literal('TZ').default('TZ'),
  currency: z.literal('TZS').default('TZS'),
  timezone: z.literal('Africa/Dar_es_Salaam').default('Africa/Dar_es_Salaam'),
})

export const administratorProfileSchema = z.object({
  adminFullName: z.string().trim().min(2).max(120),
  adminPhone: tanzaniaPhoneSchema,
  adminEmail: nullableEmailSchema,
  preferredLanguage: z.enum(['sw', 'en']),
})

export const eventSetupSchema = z
  .object({
    firstEventName: z.string().trim().min(2).max(160),
    eventType: eventTypeSchema,
    customEventType: nullableTextSchema(80),
    eventDate: nullableDateSchema,
    venue: nullableTextSchema(160),
    targetAmount: tzsAmountSchema.optional().nullable(),
    pledgeDeadline: nullableDateSchema,
  })
  .superRefine((value, context) => {
    if (value.eventType === 'OTHER' && !value.customEventType) {
      context.addIssue({ code: 'custom', path: ['customEventType'], message: 'Custom event type is required' })
    }
  })

export const onboardingPayloadSchema = z
  .object({
    planCode: planCodeSchema,
    onboardingIntent: z.enum(['FIRST_TENANT', 'CREATE_ADDITIONAL_TENANT']).optional().default('FIRST_TENANT'),
    betaInvitationCode: nullableTextSchema(64),
    idempotencyKey: z.string().uuid(),
  })
  .and(organizationSchema)
  .and(administratorProfileSchema.omit({ adminPhone: true }))
  .and(eventSetupSchema)

export const tenantContextHeaderSchema = z.object({
  tenantId: uuidHeaderSchema,
})
