import { useEffect, useState } from 'react'
import api from '../lib/api'

type Mapping = { domain: string; http: string | null; tls: string | null }

export default function Proxy() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [items, setItems] = useState<Mapping[]>([])

  const [domain, setDomain] = useState('')
  const [ipv6, setIpv6] = useState('')
  const [httpPort, setHttpPort] = useState(80)
  const [tlsPort, setTlsPort] = useState(443)
  const [busy, setBusy] = useState(false)

  const load = async () => {
    setLoading(true); setError(null)
    try {
      const { data } = await api.get('/proxy/mappings')
      setItems(data.mappings || [])
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally {
      setLoading(false)
    }
  }

  const add = async () => {
    setBusy(true); setError(null)
    try {
      await api.post('/proxy/add', { domain, ipv6, http_port: httpPort, tls_port: tlsPort })
      setDomain(''); setIpv6(''); setHttpPort(80); setTlsPort(443)
      await load()
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally { setBusy(false) }
  }

  const removeDomain = async (d: string) => {
    setBusy(true); setError(null)
    try { await api.post('/proxy/remove', { domain: d }); await load() }
    catch (e: any) { setError(e?.response?.data?.error || e.message) }
    finally { setBusy(false) }
  }

  const reloadProxy = async () => {
    setBusy(true); setError(null)
    try { await api.post('/proxy/reload'); }
    catch (e: any) { setError(e?.response?.data?.error || e.message) }
    finally { setBusy(false) }
  }

  useEffect(() => { load() }, [])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Proxy Mappings</h1>
        <div className="flex items-center gap-2">
          <button className="btn" onClick={load} disabled={loading || busy}>{loading ? 'Loading…' : 'Refresh'}</button>
          <button className="btn" onClick={reloadProxy} disabled={busy}>Reload Proxy</button>
        </div>
      </div>
      {error && <div className="card text-red-300">{error}</div>}

      <div className="card space-y-3">
        <div className="text-sm font-semibold text-slate-300">Add mapping</div>
        <div className="grid md:grid-cols-5 gap-3">
          <input className="input" placeholder="Domain (e.g. app.example.com)" value={domain} onChange={e=>setDomain(e.target.value)} />
          <input className="input" placeholder="IPv6 (without brackets)" value={ipv6} onChange={e=>setIpv6(e.target.value)} />
          <input className="input" type="number" placeholder="HTTP port" value={httpPort} onChange={e=>setHttpPort(Number(e.target.value||80))} />
          <input className="input" type="number" placeholder="TLS port" value={tlsPort} onChange={e=>setTlsPort(Number(e.target.value||443))} />
          <button className="btn" onClick={add} disabled={busy || !domain || !ipv6}>Add</button>
        </div>
      </div>

      <div className="card">
        <table className="w-full text-sm">
          <thead className="text-slate-400">
            <tr>
              <th className="text-left py-2">Domain</th>
              <th className="text-left py-2">HTTP target</th>
              <th className="text-left py-2">TLS target</th>
              <th className="text-right py-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {items.map((m) => (
              <tr key={m.domain} className="border-t border-slate-800">
                <td className="py-2">{m.domain}</td>
                <td className="py-2 font-mono text-xs">{m.http || '-'}</td>
                <td className="py-2 font-mono text-xs">{m.tls || '-'}</td>
                <td className="py-2 text-right">
                  <button className="btn" onClick={() => removeDomain(m.domain)} disabled={busy}>Remove</button>
                </td>
              </tr>
            ))}
            {items.length === 0 && !loading && (
              <tr><td className="py-3 text-slate-400" colSpan={4}>No mappings yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
