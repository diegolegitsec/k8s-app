import { Router } from 'express'
import redis from '../lib/redis.js'

const router = Router()

const MAX_VALUE_LENGTH = 1000

function validateId(raw) {
  const num = Number(raw)
  return Number.isInteger(num) && num > 0 ? num : null
}

async function getLoggingState() {
  const val = await redis.get('config:logging')
  return val !== 'false'
}

router.get('/', async (req, res) => {
  try {
    const ids = await redis.sMembers('entries:index')
    const entries = await Promise.all(ids.map(id => redis.hGetAll(`entry:${id}`)))
    const sorted = entries
      .filter(e => e && e.id)
      .sort((a, b) => Number(a.id) - Number(b.id))
    res.json({ data: sorted, logging: await getLoggingState() })
  } catch {
    res.status(500).json({ error: 'Internal server error' })
  }
})

router.get('/:id', async (req, res) => {
  try {
    const numId = validateId(req.params.id)
    if (!numId) return res.status(400).json({ error: 'id must be a positive integer' })

    const entry = await redis.hGetAll(`entry:${numId}`)
    if (!entry || !entry.id) return res.status(404).json({ error: 'Not found' })
    res.json({ data: entry, logging: await getLoggingState() })
  } catch {
    res.status(500).json({ error: 'Internal server error' })
  }
})

router.post('/', async (req, res) => {
  try {
    const { id, value } = req.body
    const numId = validateId(id)
    if (!numId) return res.status(400).json({ error: 'id must be a positive integer' })

    if (!value || typeof value !== 'string' || !value.trim()) {
      return res.status(400).json({ error: 'value must be a non-empty string' })
    }
    if (value.length > MAX_VALUE_LENGTH) {
      return res.status(400).json({ error: `value exceeds maximum length of ${MAX_VALUE_LENGTH}` })
    }

    const exists = await redis.hExists(`entry:${numId}`, 'id')
    if (exists) return res.status(409).json({ error: `Entry with id ${numId} already exists` })

    await redis.hSet(`entry:${numId}`, { id: String(numId), value: value.trim() })
    await redis.sAdd('entries:index', String(numId))
    res.status(201).json({ data: { id: String(numId), value: value.trim() }, logging: await getLoggingState() })
  } catch {
    res.status(500).json({ error: 'Internal server error' })
  }
})

router.delete('/:id', async (req, res) => {
  try {
    const numId = validateId(req.params.id)
    if (!numId) return res.status(400).json({ error: 'id must be a positive integer' })

    const exists = await redis.hExists(`entry:${numId}`, 'id')
    if (!exists) return res.status(404).json({ error: 'Not found' })
    await redis.del(`entry:${numId}`)
    await redis.sRem('entries:index', String(numId))
    res.json({ message: 'deleted', logging: await getLoggingState() })
  } catch {
    res.status(500).json({ error: 'Internal server error' })
  }
})

export default router
