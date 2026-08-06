export type OtpDiagnosticStage =
  | 'OTP_REQUEST_RECEIVED'
  | 'PHONE_NORMALIZED'
  | 'SUPABASE_OTP_REQUEST_STARTED'
  | 'SMS_HOOK_RECEIVED'
  | 'SMS_HOOK_SIGNATURE_VERIFIED'
  | 'SMS_HOOK_PAYLOAD_VALIDATED'
  | 'SMS_PROVIDER_REQUEST_STARTED'
  | 'SMS_PROVIDER_RESPONSE_RECEIVED'
  | 'SMS_PROVIDER_ACCEPTED'
  | 'SMS_HOOK_COMPLETED'
  | 'SUPABASE_OTP_REQUEST_COMPLETED'
  | 'PHONE_VALIDATION_FAILED'
  | 'SUPABASE_PHONE_PROVIDER_DISABLED'
  | 'SUPABASE_RATE_LIMITED'
  | 'SUPABASE_HOOK_FAILED'
  | 'SMS_HOOK_SIGNATURE_INVALID'
  | 'SMS_HOOK_HEADERS_MISSING'
  | 'SMS_HOOK_BODY_NOT_RAW'
  | 'SMS_HOOK_PHONE_INVALID'
  | 'SMS_HOOK_PAYLOAD_INVALID'
  | 'SMS_PROVIDER_NETWORK_ERROR'
  | 'SMS_PROVIDER_TIMEOUT'
  | 'SMS_PROVIDER_HTTP_ERROR'
  | 'SMS_PROVIDER_REJECTED'
  | 'SUPABASE_AUTH_UNKNOWN_ERROR'

export type SafeLogger = Pick<Console, 'error' | 'info' | 'warn'>

export function maskPhoneForLog(phone: string): string {
  if (phone.length < 8) {
    return '***'
  }
  return `${phone.slice(0, 5)}*****${phone.slice(-3)}`
}

export function logOtpDiagnostic(logger: SafeLogger, stage: OtpDiagnosticStage, details: Record<string, unknown> = {}) {
  const level = stage.includes('FAILED') || stage.includes('INVALID') || stage.includes('ERROR') || stage.includes('REJECTED') || stage.includes('DISABLED') ? 'warn' : 'info'
  logger[level]('Ahadi OTP diagnostic', {
    stage,
    ...details,
  })
}
