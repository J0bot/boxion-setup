import { useEffect, useState } from 'react'
import api from '../lib/api'

export default function Dashboard() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [diag, setDiag] = useState<Record<string, string>>({})

  const load = async () => {
    setLoading(true); setError(null)
    try {
      const { data } = await api.get('/status')
      setDiag(data.diag || {})
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Dashboard</h1>
        <button className="btn" onClick={load} disabled={loading}>{loading ? 'Loading…' : 'Refresh'}</button>
      </div>
      {error && <div className="card text-red-300">{error}</div>}
      <div className="grid md:grid-cols-2 gap-4">
        {Object.keys(diag).length === 0 && !loading && !error && (
          <div className="text-slate-400">No diagnostics yet. Ensure a valid master token is set.</div>
        )}
        {Object.entries(diag).map(([k, v]) => (
          <div key={k} className="card">
            <div className="mb-2 text-sm font-semibold text-slate-200">{k}</div>
            <pre className="whitespace-pre-wrap text-xs text-slate-300">{v}</pre>
          </div>
        ))}
      </div>
    </div>
  )
}
