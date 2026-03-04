import { Link, Route, Routes, useLocation } from 'react-router-dom'
import TokenGate from './components/TokenGate'
import Dashboard from './pages/Dashboard'
import Peers from './pages/Peers'
import Otp from './pages/Otp'
import Proxy from './pages/Proxy'
import He from './pages/He'
import Smtp from './pages/Smtp'

function NavLink({ to, label }: { to: string; label: string }) {
  const loc = useLocation()
  const active = loc.pathname === to || (to !== '/' && loc.pathname.startsWith(to))
  return (
    <Link
      to={to}
      className={`px-3 py-2 rounded-md text-sm font-medium ${active ? 'bg-slate-800 text-white' : 'text-slate-300 hover:text-white hover:bg-slate-800'}`}
    >
      {label}
    </Link>
  )
}

export default function App() {
  return (
    <div className="min-h-screen">
      <header className="border-b border-slate-800 bg-slate-900">
        <div className="mx-auto max-w-6xl px-4 py-3 flex items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <Link to="/" className="text-lg font-semibold">Boxion Admin</Link>
            <nav className="flex items-center gap-1">
              <NavLink to="/" label="Dashboard" />
              <NavLink to="/proxy" label="Proxy" />
              <NavLink to="/he" label="HE" />
              <NavLink to="/smtp" label="SMTP" />
              <NavLink to="/otp" label="OTP" />
              <NavLink to="/peers" label="Peers" />
            </nav>
          </div>
          <TokenGate />
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/proxy" element={<Proxy />} />
          <Route path="/he" element={<He />} />
          <Route path="/smtp" element={<Smtp />} />
          <Route path="/otp" element={<Otp />} />
          <Route path="/peers" element={<Peers />} />
        </Routes>
      </main>
    </div>
  )
}
