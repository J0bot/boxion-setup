import { useEffect, useState } from 'react'

export default function TokenGate() {
  const [token, setToken] = useState(localStorage.getItem('boxion_token') || '')

  useEffect(() => {
    if (token) localStorage.setItem('boxion_token', token)
  }, [token])

  return (
    <div className="flex items-center gap-2">
      <input
        className="input"
        style={{ width: 360 }}
        type="password"
        placeholder="Bearer token (master or OTP)"
        value={token}
        onChange={(e) => setToken(e.target.value)}
      />
      <button className="btn" onClick={() => localStorage.setItem('boxion_token', token)}>Save</button>
      <button className="btn" onClick={() => { setToken(''); localStorage.removeItem('boxion_token') }}>Clear</button>
    </div>
  )
}
