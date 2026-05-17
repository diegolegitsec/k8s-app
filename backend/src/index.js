import express from 'express'
import cors from 'cors'
import redis from './lib/redis.js'
import entriesRouter from './routes/entries.js'
import loggingRouter from './routes/logging.js'

const app = express()

app.use(cors())
app.use(express.json())

app.use(async (req, res, next) => {
  const val = await redis.get('config:logging')
  if (val !== 'false') {
    console.log(`${new Date().toISOString()} ${req.method} ${req.path}`)
  }
  next()
})

app.use('/api/entries', entriesRouter)
app.use('/api/logging', loggingRouter)

app.get('/api/health', (req, res) => res.json({ status: 'ok' }))

const port = process.env.PORT || 3000
app.listen(port, () => console.log(`Backend listening on :${port}`))
