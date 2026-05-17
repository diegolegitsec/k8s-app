import { useState, useEffect } from 'react'

export default function App() {
  const [entries, setEntries] = useState([])
  const [id, setId] = useState('')
  const [value, setValue] = useState('')
  const [logging, setLogging] = useState(false)
  const [error, setError] = useState('')

  async function fetchEntries() {
    const res = await fetch('/api/entries')
    const data = await res.json()
    setEntries(data.data)
    setLogging(data.logging)
  }

  useEffect(() => {
    fetchEntries()
    fetch('/api/logging/status')
      .then(r => r.json())
      .then(d => setLogging(d.logging))
  }, [])

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    const res = await fetch('/api/entries', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: Number(id), value })
    })
    const data = await res.json()
    if (!res.ok) {
      setError(data.error || 'Failed to create entry')
      return
    }
    setId('')
    setValue('')
    fetchEntries()
  }

  async function handleDelete(entryId) {
    await fetch(`/api/entries/${entryId}`, { method: 'DELETE' })
    fetchEntries()
  }

  async function handleToggleLogging() {
    const res = await fetch('/api/logging/toggle', { method: 'POST' })
    const data = await res.json()
    setLogging(data.logging)
  }

  return (
    <div className="container">
      <header>
        <h1>K8s App</h1>
        <button
          className={`toggle-btn ${logging ? 'active' : ''}`}
          onClick={handleToggleLogging}
        >
          Logging: {logging ? 'ON' : 'OFF'}
        </button>
      </header>

      <section className="form-section">
        <h2>Add Entry</h2>
        <form onSubmit={handleSubmit}>
          <input
            type="number"
            placeholder="Numeric ID"
            value={id}
            onChange={e => setId(e.target.value)}
            required
          />
          <input
            type="text"
            placeholder="Text value"
            value={value}
            onChange={e => setValue(e.target.value)}
            required
          />
          <button type="submit">Add</button>
        </form>
        {error && <p className="error">{error}</p>}
      </section>

      <section className="list-section">
        <h2>Entries ({entries.length})</h2>
        {entries.length === 0 ? (
          <p className="empty">No entries yet.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Value</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {entries.map(entry => (
                <tr key={entry.id}>
                  <td>{entry.id}</td>
                  <td>{entry.value}</td>
                  <td>
                    <button
                      className="delete-btn"
                      onClick={() => handleDelete(entry.id)}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  )
}
