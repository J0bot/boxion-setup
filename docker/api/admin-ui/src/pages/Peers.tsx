import { useEffect, useState } from 'react'
import api from '../lib/api'

type Peer = { id: number; name: string; ipv6_address: string }

export default function Peers() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [peers, setPeers] = useState<Peer[]>([])

  const load = async () => {
    setLoading(true); setError(null)
    try {
      const { data } = await api.get('/peers/list')
      setPeers(data.peers || [])
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
        <h1 className="text-xl font-semibold">Peers</h1>
        <button className="btn" onClick={load} disabled={loading}>{loading ? 'Loading…' : 'Refresh'}</button>
      </div>
      {error && <div className="card text-red-300">{error}</div>}
      <div className="card">
        <table className="w-full text-sm">
          <thead className="text-slate-400">
            <tr>
              <th className="text-left py-2">ID</th>
              <th className="text-left py-2">Name</th>
              <th className="text-left py-2">IPv6</th>
            </tr>
          </thead>
          <tbody>
            {peers.map(p => (
              <tr key={p.id} className="border-t border-slate-800">
                <td className="py-2">{p.id}</td>
                <td className="py-2">{p.name}</td>
                <td className="py-2 font-mono text-xs">{p.ipv6_address}</td>
              </tr>
            ))}
            {peers.length === 0 && !loading && (
              <tr><td className="py-3 text-slate-400" colSpan={3}>No peers yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
