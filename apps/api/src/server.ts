import { app } from './app.js'
import { env } from './env.js'

const server = app.listen(env.PORT, () => {
  console.log(`Ahadi API listening on :${env.PORT}`)
})

function shutdown(signal: NodeJS.Signals) {
  console.log(`Ahadi API received ${signal}; shutting down`)
  server.close((error) => {
    if (error) {
      console.error('Ahadi API shutdown failed', error)
      process.exitCode = 1
    }
  })
}

process.once('SIGINT', shutdown)
process.once('SIGTERM', shutdown)
