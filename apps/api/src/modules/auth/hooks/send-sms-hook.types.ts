import { z } from 'zod'

export const sendSmsHookPayloadSchema = z
  .object({
    user: z
      .object({
        phone: z.string().trim().min(1),
      })
      .passthrough(),
    sms: z
      .object({
        otp: z.string().trim().regex(/^[0-9]{4,10}$/, {
          message: 'OTP must contain only digits.',
        }),
      })
      .passthrough(),
  })
  .passthrough()

export type SendSmsHookPayload = z.infer<typeof sendSmsHookPayloadSchema>
