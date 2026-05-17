import { Router } from 'express'
import redis from '../lib/redis.js'

const router = Router()

router.get('/status', async (req, res) => {
  const val = await redis.get('config:logging')
  res.json({ logging: val !== 'false' })
})

router.post('/toggle', async (req, res) => {
  const val = await redis.get('config:logging')
  const current = val !== 'false'
  await redis.set('config:logging', String(!current))
  res.json({ logging: !current })
})

export default router
