import { useEffect, useState } from 'react'
import api from '../lib/api'

export default function Smtp() {
  const [loading, setLoading] = useState(false)
  const [applying, setApplying] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const [inboundUser, setInboundUser] = useState('')
  const [inboundPass, setInboundPass] = useState('')

  const [relay_host, setRelayHost] = useState('')
  const [relay_port, setRelayPort] = useState(587)
  const [relay_user, setRelayUser] = useState('')
  const [relay_pass, setRelayPass] = useState('')

  const load = async () => {
    setLoading(true); setError(null); setMessage(null)
    try {
      const { data } = await api.get('/smtp/status')
      const s = data.smtp || {}
      setInboundUser(s.inbound_user || '')
      setInboundPass(s.inbound_pass || '')
      const r = s.relay || {}
      setRelayHost(r.host || '')
      setRelayPort(Number(r.port || 587))
      setRelayUser(r.user || '')
      setRelayPass('') // never prefill password
    } catch (e: any) {
      setError(e?.response?.data?.error || e.message)
    } finally {
      setLoading(false)
    }
  }

  const apply = async () => {
    setApplying(true); setError(null); setMessage(null)
    try {
      await api.post('/smtp/apply', { relay_host, relay_port, relay_user, relay_pass })
      setMessage('SMTP relay settings applied. Postfix reloaded/restarted.')
      setRelayPass('')
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
        <h1 className="text-xl font-semibold">SMTP Relay</h1>
        <button className="btn" onClick={load} disabled={loading || applying}>{loading ? 'Loading…' : 'Refresh'}</button>
      </div>
      {error && <div className="card text-red-300">{error}</div>}
      {message && <div className="card text-green-300">{message}</div>}

      <div className="card space-y-3">
        <h2 className="font-semibold">Inbound credentials (Boxion submission)</h2>
        <div className="grid md:grid-cols-2 gap-3">
          <input className="input" value={inboundUser} readOnly placeholder="SMTP user" />
          <input className="input" value={inboundPass} readOnly placeholder="SMTP password" />
        </div>
        <div className="text-xs text-slate-400">
          Your apps can submit mail to this Boxion relay on ports 587 or 2525 (STARTTLS required).
        </div>
        <div className="text-xs text-slate-400">
          Example (YunoHost): set outgoing SMTP server to this host, port 2525, STARTTLS, auth with above user/pass.
        </div>
      </div>

      <div className="card space-y-3">
        <h2 className="font-semibold">Upstream relay (optional)</h2>
        <div className="grid md:grid-cols-2 gap-3">
          <input className="input" placeholder="Relay host (leave empty to disable)" value={relay_host} onChange={e=>setRelayHost(e.target.value)} />
          <input className="input" type="number" placeholder="Port" value={relay_port} onChange={e=>setRelayPort(Number(e.target.value||587))} />
          <input className="input" placeholder="Username" value={relay_user} onChange={e=>setRelayUser(e.target.value)} />
          <input className="input" type="password" placeholder="Password (not shown)" value={relay_pass} onChange={e=>setRelayPass(e.target.value)} />
        </div>
        <div>
          <button className="btn" onClick={apply} disabled={applying}>
            {applying ? 'Applying…' : 'Apply'}
          </button>
        </div>
        <div className="text-xs text-slate-400">
          When configured, Boxion will relay mail via the upstream server with authentication.
        </div>
      </div>
    </div>
  )
}
