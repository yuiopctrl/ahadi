import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { IncomingMessage, ServerResponse } from 'node:http'
import { Socket } from 'node:net'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import type { Request, Response } from 'express'
import { Webhook } from 'standardwebhooks'
import { app } from '../../../app.js'
import type { AuthenticationSmsInput } from '../providers/auth-sms-provider.js'
import { createSendSmsHookHandler, normalizeSupabaseHookSecret } from './send-sms-hook.controller.js'

const base64Secret = Buffer.from('ahadi-send-sms-hook-test-secret').toString('base64')
const hookSecret = `v1,whsec_${base64Secret}`
const controllerSource = readFileSync(fileURLToPath(import.meta.resolve('./send-sms-hook.controller.ts')), 'utf8')
const validPayload = JSON.stringify({
  user: { phone: '+255712345678' },
  sms: { otp: '123456' },
})
const realisticSupabasePayload = {
  user: {
    id: '6481a5c1-3d37-4a56-9f6a-bee08c554965',
    aud: 'authenticated',
    role: 'authenticated',
    email: '',
    phone: '+255712345678',
    app_metadata: {
      provider: 'phone',
      providers: ['phone'],
    },
    user_metadata: {},
    identities: [],
    created_at: '2026-08-06T10:00:00.000Z',
    updated_at: '2026-08-06T10:00:00.000Z',
    is_anonymous: false,
  },
  sms: {
    otp: '123456',
  },
}

interface CapturedResponse {
  statusCode: number
  payload: unknown
}

interface LogCapture {
  entries: string[]
  logger: Pick<Console, 'error' | 'info' | 'warn'>
}

interface ExpressLayer {
  name: string
  route?: {
    path?: string
    methods?: Record<string, boolean>
    stack?: ExpressLayer[]
  }
}

interface AppRequestInit {
  body?: string
  headers?: Record<string, string>
  method?: string
}

interface AppDispatchResponse {
  body: string
  status: number
}

function createSignedHeaders(payload: string) {
  const webhook = new Webhook(normalizeSupabaseHookSecret(hookSecret))
  const timestamp = new Date()
  const messageId = randomUUID()
  return {
    'webhook-id': messageId,
    'webhook-signature': webhook.sign(messageId, timestamp, payload),
    'webhook-timestamp': String(Math.floor(timestamp.getTime() / 1000)),
  }
}

function createRequest(body: Buffer | Record<string, unknown>, headers: Record<string, string> = {}): Request {
  const lowerHeaders = new Map(Object.entries(headers).map(([key, value]) => [key.toLowerCase(), value]))
  return {
    body,
    requestId: 'req_test',
    get(name: string) {
      return lowerHeaders.get(name.toLowerCase())
    },
    header(name: string) {
      return lowerHeaders.get(name.toLowerCase())
    },
  } as unknown as Request
}

function createResponse() {
  const captured: CapturedResponse = {
    statusCode: 200,
    payload: undefined,
  }
  const response: Pick<Response, 'json' | 'status'> = {
    status(code: number) {
      captured.statusCode = code
      return response as Response
    },
    json(payload: unknown) {
      captured.payload = payload
      return response as Response
    },
  }
  return { captured, response: response as Response }
}

function createLogCapture(): LogCapture {
  const entries: string[] = []
  const capture = (...data: unknown[]) => {
    entries.push(JSON.stringify(data))
  }
  return {
    entries,
    logger: {
      error: capture,
      info: capture,
      warn: capture,
    },
  }
}

async function invokeHook(options: {
  body?: Buffer | Record<string, unknown>
  headers?: Record<string, string>
  sendAuthenticationSms?: (input: AuthenticationSmsInput) => Promise<void>
  logger?: Pick<Console, 'error' | 'info' | 'warn'>
}) {
  const { captured, response } = createResponse()
  const handler = createSendSmsHookHandler({
    hookSecret,
    logger: options.logger ?? createLogCapture().logger,
    sendAuthenticationSms: options.sendAuthenticationSms ?? (async () => undefined),
  })
  await handler(createRequest(options.body ?? Buffer.from(validPayload), options.headers ?? createSignedHeaders(validPayload)), response)
  return captured
}

async function dispatchAppRequest(path: string, init: AppRequestInit = {}): Promise<AppDispatchResponse> {
  const body = init.body ?? ''
  const socket = new Socket()
  Object.defineProperty(socket, 'remoteAddress', { value: '127.0.0.1' })
  const request = new IncomingMessage(socket)
  request.method = init.method ?? 'GET'
  request.url = path
  request.headers = {
    ...(init.headers ?? {}),
    ...(body ? { 'content-length': String(Buffer.byteLength(body)) } : {}),
  }
  request.push(body)
  request.push(null)

  const response = new ServerResponse(request)
  const chunks: Buffer[] = []

  return await new Promise<AppDispatchResponse>((resolve, reject) => {
    response.on('error', reject)
    const writableResponse = response as ServerResponse & {
      end: (chunk?: unknown) => ServerResponse
      write: (chunk: unknown) => boolean
    }
    writableResponse.write = (chunk: unknown) => {
      if (chunk !== undefined) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)))
      }
      return true
    }
    writableResponse.end = (chunk?: unknown) => {
      if (chunk !== undefined) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)))
      }
      resolve({
        body: Buffer.concat(chunks).toString('utf8'),
        status: response.statusCode,
      })
      return response
    }
    ;(app as unknown as (request: IncomingMessage, response: ServerResponse) => void)(request, response)
  })
}

function getAppStack(): ExpressLayer[] {
  const router = (app as unknown as { router?: { stack?: ExpressLayer[] } }).router
  assert.ok(router?.stack)
  return router.stack
}

test('valid signed payload returns 200', async () => {
  const response = await invokeHook({})
  assert.equal(response.statusCode, 200)
  assert.deepEqual(response.payload, {})
})

test('complete Supabase user object with additional fields passes', async () => {
  const payload = JSON.stringify(realisticSupabasePayload)
  const calls: AuthenticationSmsInput[] = []
  const response = await invokeHook({
    body: Buffer.from(payload),
    headers: createSignedHeaders(payload),
    sendAuthenticationSms: async (input) => {
      calls.push(input)
    },
  })
  assert.equal(response.statusCode, 200)
  assert.equal(calls.length, 1)
  assert.equal(calls[0]?.to, '+255712345678')
  assert.match(calls[0]?.message ?? '', /^123456 /)
})

test('top-level and sms additional fields pass', async () => {
  const payload = JSON.stringify({
    ...realisticSupabasePayload,
    event: 'send_sms',
    sms: {
      ...realisticSupabasePayload.sms,
      provider_hint: 'supabase',
    },
  })
  const calls: AuthenticationSmsInput[] = []
  const response = await invokeHook({
    body: Buffer.from(payload),
    headers: createSignedHeaders(payload),
    sendAuthenticationSms: async (input) => {
      calls.push(input)
    },
  })
  assert.equal(response.statusCode, 200)
  assert.equal(calls.length, 1)
})

test('app is configured with expected trust proxy value', () => {
  assert.equal(app.get('trust proxy'), 1)
})

test('requests through X-Forwarded-For do not trigger express-rate-limit validation error', async () => {
  const response = await dispatchAppRequest('/auth/hooks/send-sms', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': '203.0.113.10',
    },
    body: '{}',
  })
  assert.equal(response.status, 401)
  assert.doesNotMatch(response.body, /ERR_ERL_UNEXPECTED_X_FORWARDED_FOR/)
})

test('normalizeSupabaseHookSecret removes only the version prefix', () => {
  assert.equal(normalizeSupabaseHookSecret('v1,whsec_abc123'), 'whsec_abc123')
})

test('normalizeSupabaseHookSecret leaves constructor-ready secret unchanged', () => {
  assert.equal(normalizeSupabaseHookSecret('whsec_abc123'), 'whsec_abc123')
})

test('webhook verify result is not passed to JSON.parse', () => {
  assert.doesNotMatch(controllerSource, /JSON\.parse\s*\(\s*verifiedPayload\s*\)/)
})

test('invalid signature returns 401', async () => {
  const headers = { ...createSignedHeaders(validPayload), 'webhook-signature': 'v1,not-valid' }
  const response = await invokeHook({ headers })
  assert.equal(response.statusCode, 401)
  assert.equal((response.payload as { error: { code: string } }).error.code, 'INVALID_WEBHOOK_SIGNATURE')
})

test('missing signature returns 401', async () => {
  const response = await invokeHook({ headers: {} })
  assert.equal(response.statusCode, 401)
})

test('parsed object instead of Buffer is rejected', async () => {
  const response = await invokeHook({ body: JSON.parse(validPayload) as Record<string, unknown> })
  assert.equal(response.statusCode, 401)
})

test('missing webhook-id returns 401', async () => {
  const { 'webhook-id': _webhookId, ...headers } = createSignedHeaders(validPayload)
  void _webhookId
  const response = await invokeHook({ headers })
  assert.equal(response.statusCode, 401)
})

test('missing webhook-timestamp returns 401', async () => {
  const { 'webhook-timestamp': _webhookTimestamp, ...headers } = createSignedHeaders(validPayload)
  void _webhookTimestamp
  const response = await invokeHook({ headers })
  assert.equal(response.statusCode, 401)
})

test('missing webhook-signature returns 401', async () => {
  const { 'webhook-signature': _webhookSignature, ...headers } = createSignedHeaders(validPayload)
  void _webhookSignature
  const response = await invokeHook({ headers })
  assert.equal(response.statusCode, 401)
})

test('modified body after signing returns 401', async () => {
  const tamperedPayload = JSON.stringify({
    user: { phone: '+255712345678' },
    sms: { otp: '654321' },
  })
  const response = await invokeHook({ body: Buffer.from(tamperedPayload), headers: createSignedHeaders(validPayload) })
  assert.equal(response.statusCode, 401)
})

test('valid signature missing phone returns 400', async () => {
  const payload = JSON.stringify({ user: {}, sms: { otp: '123456' } })
  const response = await invokeHook({ body: Buffer.from(payload), headers: createSignedHeaders(payload) })
  assert.equal(response.statusCode, 400)
  assert.equal((response.payload as { error: { code: string } }).error.code, 'INVALID_SMS_HOOK_PAYLOAD')
})

test('missing user returns 400 and provider is not called', async () => {
  const payload = JSON.stringify({ sms: { otp: '123456' } })
  let calls = 0
  const response = await invokeHook({
    body: Buffer.from(payload),
    headers: createSignedHeaders(payload),
    sendAuthenticationSms: async () => {
      calls += 1
    },
  })
  assert.equal(response.statusCode, 400)
  assert.equal(calls, 0)
})

test('valid signature missing OTP returns 400', async () => {
  const payload = JSON.stringify({ user: { phone: '+255712345678' }, sms: {} })
  const response = await invokeHook({ body: Buffer.from(payload), headers: createSignedHeaders(payload) })
  assert.equal(response.statusCode, 400)
})

test('missing sms returns 400', async () => {
  const payload = JSON.stringify({ user: { phone: '+255712345678' } })
  const response = await invokeHook({ body: Buffer.from(payload), headers: createSignedHeaders(payload) })
  assert.equal(response.statusCode, 400)
})

test('non-numeric OTP returns 400', async () => {
  const payload = JSON.stringify({ user: { phone: '+255712345678' }, sms: { otp: 'abc123' } })
  const response = await invokeHook({ body: Buffer.from(payload), headers: createSignedHeaders(payload) })
  assert.equal(response.statusCode, 400)
})

test('four-to-ten digit numeric OTP passes', async () => {
  for (const otp of ['1234', '1234567890']) {
    const payload = JSON.stringify({ user: { phone: '+255712345678' }, sms: { otp } })
    const response = await invokeHook({ body: Buffer.from(payload), headers: createSignedHeaders(payload) })
    assert.equal(response.statusCode, 200)
  }
})

test('invalid phone returns 400', async () => {
  const payload = JSON.stringify({ user: { phone: '+15551234567' }, sms: { otp: '123456' } })
  const response = await invokeHook({ body: Buffer.from(payload), headers: createSignedHeaders(payload) })
  assert.equal(response.statusCode, 400)
})

test('valid payload calls provider exactly once', async () => {
  let calls = 0
  const response = await invokeHook({
    sendAuthenticationSms: async () => {
      calls += 1
    },
  })
  assert.equal(response.statusCode, 200)
  assert.equal(calls, 1)
})

test('invalid payload never calls provider', async () => {
  const payload = JSON.stringify({ user: { phone: '+255712345678' }, sms: { otp: 'not-numeric' } })
  let calls = 0
  const response = await invokeHook({
    body: Buffer.from(payload),
    headers: createSignedHeaders(payload),
    sendAuthenticationSms: async () => {
      calls += 1
    },
  })
  assert.equal(response.statusCode, 400)
  assert.equal(calls, 0)
})

test('provider rejection returns 502', async () => {
  const response = await invokeHook({
    sendAuthenticationSms: async () => {
      throw new Error('provider rejected')
    },
  })
  assert.equal(response.statusCode, 502)
  assert.equal((response.payload as { error: { code: string } }).error.code, 'SMS_PROVIDER_FAILED')
})

test('successful provider call receives expected phone and message', async () => {
  const calls: Array<{ message: string; to: string }> = []
  const response = await invokeHook({
    sendAuthenticationSms: async (input) => {
      calls.push(input)
    },
  })
  assert.equal(response.statusCode, 200)
  assert.deepEqual(calls, [
    {
      requestId: 'req_test',
      to: '+255712345678',
      message: '123456 ni namba yako ya uthibitisho ya Ahadi. Usimpe mtu mwingine.',
    },
  ])
})

test('successful provider call receives normalized phone number', async () => {
  const payload = JSON.stringify({
    user: { phone: '0712 345 678' },
    sms: { otp: '123456' },
  })
  const calls: Array<{ message: string; to: string }> = []
  const response = await invokeHook({
    body: Buffer.from(payload),
    headers: createSignedHeaders(payload),
    sendAuthenticationSms: async (input) => {
      calls.push(input)
    },
  })
  assert.equal(response.statusCode, 200)
  assert.equal(calls[0]?.to, '+255712345678')
})

test('raw OTP never appears in HTTP responses', async () => {
  const response = await invokeHook({
    sendAuthenticationSms: async () => {
      throw new Error('provider rejected')
    },
  })
  assert.doesNotMatch(JSON.stringify(response.payload), /123456/)
})

test('OTP and raw body are not written to logs', async () => {
  const logCapture = createLogCapture()
  const response = await invokeHook({ logger: logCapture.logger })
  assert.equal(response.statusCode, 200)
  const logs = logCapture.entries.join('\n')
  assert.doesNotMatch(logs, /123456/)
  assert.doesNotMatch(logs, /whsec_/)
  assert.doesNotMatch(logs, new RegExp(base64Secret))
  assert.doesNotMatch(logs, /\+255712345678/)
  assert.doesNotMatch(logs, /"sms"/)
  assert.match(logs, /\+2557\*{5}678/)
})

test('normal JSON API routes still parse JSON correctly', async () => {
  const response = await dispatchAppRequest('/api/v1/auth/request-otp', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: '{}',
  })
  const payload = JSON.parse(response.body) as { error?: { code?: string } }
  assert.equal(response.status, 400)
  assert.equal(payload.error?.code, 'INVALID_INPUT')
})

test('development auth sms status endpoint returns safe configuration booleans', async () => {
  const response = await dispatchAppRequest('/api/v1/dev/auth-sms-status')
  const payload = JSON.parse(response.body) as Record<string, unknown>
  assert.equal(response.status, 200)
  assert.equal(payload['hookSecretConfigured'], true)
  assert.equal(payload['hookSecretFormatValid'], true)
  assert.equal(payload['smsProviderUrlConfigured'], true)
  assert.equal(payload['smsUsernameConfigured'], true)
  assert.equal(payload['smsPasswordConfigured'], true)
  assert.equal(payload['smsSenderIdConfigured'], true)
  assert.equal(payload['trustProxyHops'], 1)
  assert.equal('smsUsername' in payload, false)
  assert.equal('smsPassword' in payload, false)
  assert.equal('hookSecret' in payload, false)
})

test('global express.json does not run before raw body verification', () => {
  const stack = getAppStack()
  const hookIndex = stack.findIndex((layer) => layer.route?.path === '/auth/hooks/send-sms')
  const jsonIndex = stack.findIndex((layer) => layer.name === 'jsonParser')
  assert.ok(hookIndex >= 0)
  assert.ok(jsonIndex >= 0)
  assert.ok(hookIndex < jsonIndex)
})

test('normal api v1 JSON endpoints remain behind express.json', () => {
  const stack = getAppStack()
  const jsonIndex = stack.findIndex((layer) => layer.name === 'jsonParser')
  const requestOtpIndex = stack.findIndex((layer) => layer.route?.path === '/api/v1/auth/request-otp')
  assert.ok(jsonIndex >= 0)
  assert.ok(requestOtpIndex >= 0)
  assert.ok(jsonIndex < requestOtpIndex)
})

test('route exists at /auth/hooks/send-sms', () => {
  const route = getAppStack().find((layer) => layer.route?.path === '/auth/hooks/send-sms')
  assert.equal(route?.route?.methods?.['post'], true)
})

test('route does not require X-Tenant-ID', async () => {
  const response = await invokeHook({})
  assert.equal(response.statusCode, 200)
})

test('route does not require bearer token', async () => {
  const response = await invokeHook({})
  assert.equal(response.statusCode, 200)
})
