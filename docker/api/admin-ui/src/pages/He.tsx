import { useEffect, useState } from 'react'
import api from '../lib/api'

export default function He() {
  const [loading, setLoading] = useState(false)
  const [applying, setApplying] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const [my_v4, setMyV4] = useState('')
  const [he_server_v4, setHeServerV4] = useState('')
  const [he_tun_client6, setHeTunClient6] = useState('')
  const [he_tun_server6, setHeTunServer6] = useState('')
  const [he_routed_prefix, setHeRoutedPrefix] = useState('')
  const [mtu, setMtu] = useState(1480)
  const [use_default_route, setUseDefaultRoute] = useState(false)

  const load = async () => {
    setLoading(true); setError(null); setMessage(null)
    try {
      const { data } = await api.get('/he/status')
      const he = data.he || {}
      setMyV4(he.MY_V4 || '')
      setHeServerV4(he.HE_SERVER_V4 || '')
      setHeTunClient6(he.HE_TUN_CLIENT6 || '')
      setHeTunServer6(he.HE_TUN_SERVER6 || '')
      setHeRoutedPrefix(he.HE_ROUTED_PREFIX || '')
      setMtu(Number(he.HE_TUN_MTU || 1480))
      setUseDefaultRoute((he.USE_HE_DEFAULT_ROUTE || '0') === '1')
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally {
      setLoading(false)
    }
  }

  const apply = async () => {
    setApplying(true); setError(null); setMessage(null)
    try {
      await api.post('/he/apply', { my_v4, he_server_v4, he_tun_client6, he_tun_server6, he_routed_prefix, mtu, use_default_route })
      setMessage('Applied successfully. Check Status > Routes and Ping6 in Diagnostics.')
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally {
      setApplying(false)
    }
  }

  useEffect(() => { load() }, [])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Hurricane Electric Tunnel</h1>
        <button className="btn" onClick={load} disabled={loading || applying}>{loading ? 'Loading…' : 'Refresh'}</button>
      </div>
      {error && <div className="card text-red-300">{error}</div>}
      {message && <div className="card text-green-300">{message}</div>}

      <div className="card space-y-3">
        <div className="grid md:grid-cols-2 gap-3">
          <input className="input" placeholder="Your public IPv4 (MY_V4)" value={my_v4} onChange={e=>setMyV4(e.target.value)} />
          <input className="input" placeholder="HE server IPv4 (SERVER_V4)" value={he_server_v4} onChange={e=>setHeServerV4(e.target.value)} />
          <input className="input" placeholder="Tunnel client IPv6 (CLIENT6)" value={he_tun_client6} onChange={e=>setHeTunClient6(e.target.value)} />
          <input className="input" placeholder="Tunnel server IPv6 (SERVER6)" value={he_tun_server6} onChange={e=>setHeTunServer6(e.target.value)} />
          <input className="input" placeholder="Routed /64 or /48 prefix" value={he_routed_prefix} onChange={e=>setHeRoutedPrefix(e.target.value)} />
          <input className="input" type="number" placeholder="MTU" value={mtu} onChange={e=>setMtu(Number(e.target.value||1480))} />
        </div>
        <label className="flex items-center gap-2 text-sm text-slate-300">
          <input type="checkbox" checked={use_default_route} onChange={e=>setUseDefaultRoute(e.target.checked)} />
          Use HE as default IPv6 route
        </label>
        <div>
          <button className="btn" onClick={apply} disabled={applying || !my_v4 || !he_server_v4 || !he_tun_client6 || !he_tun_server6 || !he_routed_prefix}>
            {applying ? 'Applying…' : 'Apply'}
          </button>
        </div>
        <div className="text-xs text-slate-400">
          Tip: If not using default route, we install a policy route so traffic sourced from your routed prefix uses the tunnel.
        </div>
      </div>
    </div>
  )
}
