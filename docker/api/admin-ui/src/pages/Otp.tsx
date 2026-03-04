import { useEffect, useState } from 'react'
import api from '../lib/api'

type OtpRow = { token: string; expires_at: string; used: number }

export default function Otp() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [items, setItems] = useState<OtpRow[]>([])
  const [ttl, setTtl] = useState(600)
  const [newToken, setNewToken] = useState<string | null>(null)

  const load = async () => {
    setLoading(true); setError(null)
    try {
      const { data } = await api.get('/otp/list')
      setItems(data.otps || [])
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally {
      setLoading(false)
    }
  }

  const create = async () => {
    setError(null)
    try {
      const { data } = await api.post('/otp/create', { ttl })
      setNewToken(data.token)
      await load()
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    }
  }

  useEffect(() => { load() }, [])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">OTP Tokens</h1>
        <button className="btn" onClick={load} disabled={loading}>{loading ? 'Loading…' : 'Refresh'}</button>
      </div>
      {error && <div className="card text-red-300">{error}</div>}

      <div className="card space-y-3">
        <div className="flex items-center gap-3">
          <input className="input" type="number" value={ttl} onChange={e => setTtl(Math.max(60, Number(e.target.value||0)))} style={{width:160}} />
          <span className="text-sm text-slate-400">TTL seconds (min 60)</span>
          <button className="btn" onClick={create}>Create OTP</button>
        </div>
        {newToken && (
          <div className="text-sm">
            <div className="mb-1 text-slate-300">New token (single-use):</div>
            <div className="flex items-center gap-2">
              <code className="px-2 py-1 rounded bg-slate-800 text-xs break-all">{newToken}</code>
              <button className="btn" onClick={() => navigator.clipboard.writeText(newToken)}>Copy</button>
            </div>
          </div>
        )}
      </div>

      <div className="card">
        <table className="w-full text-sm">
          <thead className="text-slate-400">
            <tr>
              <th className="text-left py-2">Token</th>
              <th className="text-left py-2">Expires</th>
              <th className="text-left py-2">Used</th>
            </tr>
          </thead>
          <tbody>
            {items.map((r) => (
              <tr key={r.token} className="border-t border-slate-800">
                <td className="py-2"><code className="text-xs break-all">{r.token}</code></td>
                <td className="py-2">{r.expires_at}</td>
                <td className="py-2">{r.used ? 'Yes' : 'No'}</td>
              </tr>
            ))}
            {items.length === 0 && !loading && (
              <tr><td className="py-3 text-slate-400" colSpan={3}>No OTPs yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
