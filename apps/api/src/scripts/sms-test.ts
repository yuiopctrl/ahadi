import { normalizeTanzaniaPhone } from '@ahadi/validation'
import { maskPhoneForLog } from '../diagnostics.js'
import { env } from '../env.js'
import { formatWebBulkSmsPhone, sendAuthenticationSms, SmsProviderError } from '../modules/auth/providers/auth-sms-provider.js'

function getPhoneArgument(): string | null {
  const withEquals = process.argv.find((argument) => argument.startsWith('--phone='))
  if (withEquals) {
    return withEquals.slice('--phone='.length)
  }
  const index = process.argv.indexOf('--phone')
  return index >= 0 ? (process.argv[index + 1] ?? null) : null
}

async function main() {
  const rawPhone = getPhoneArgument()
  if (!rawPhone) {
    console.error('Usage: pnpm --dir apps/api sms:test --phone=+2557XXXXXXXX')
    process.exitCode = 1
    return
  }

  let phone: string
  try {
    phone = normalizeTanzaniaPhone(rawPhone)
  } catch {
    console.error(JSON.stringify({ ok: false, category: 'PHONE_VALIDATION_FAILED' }))
    process.exitCode = 1
    return
  }

  try {
    const destinationFormat = formatWebBulkSmsPhone(phone)
    const result = await sendAuthenticationSms({
      requestId: 'sms_test',
      to: phone,
      message: 'Ahadi SMS provider configuration test.',
    })
    console.log(
      JSON.stringify({
        ok: true,
        senderId: env.SMS_SENDER_ID.trim(),
        destinationFormat,
        destinationIsArray: true,
        maskedPhone: maskPhoneForLog(phone),
        providerHttpStatus: result.providerHttpStatus,
        accepted: result.accepted,
        providerStatusCode: result.providerStatusCode,
        providerMessageId: result.providerMessageId,
        safeReason: result.safeReason,
      }),
    )
  } catch (error) {
    if (error instanceof SmsProviderError) {
      const destinationFormat = formatWebBulkSmsPhone(phone)
      console.log(
        JSON.stringify({
          ok: false,
          senderId: env.SMS_SENDER_ID.trim(),
          destinationFormat,
          destinationIsArray: true,
          maskedPhone: maskPhoneForLog(phone),
          category: error.status === undefined ? 'SMS_PROVIDER_NETWORK_ERROR' : 'SMS_PROVIDER_REJECTED',
          providerHttpStatus: error.status,
          providerStatusCode: error.providerStatusCode,
          accepted: error.providerAccepted,
          safeReason: error.providerReason,
        }),
      )
      process.exitCode = 1
      return
    }

    console.log(JSON.stringify({ ok: false, maskedPhone: maskPhoneForLog(phone), category: 'SMS_PROVIDER_NETWORK_ERROR' }))
    process.exitCode = 1
  }
}

await main()
