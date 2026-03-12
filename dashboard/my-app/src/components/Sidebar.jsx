import { useState } from 'react'
import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard, Map, PhoneCall, ShieldAlert,
  FileText, Menu, X, Zap
} from 'lucide-react'

const navItems = [
  { to: '/', icon: LayoutDashboard, label: 'Overview' },
  { to: '/heatmap', icon: Map, label: 'Heatmap' },
  { to: '/calls', icon: PhoneCall, label: 'Call Log' },
  { to: '/scam-database', icon: ShieldAlert, label: 'Scam DB' },
  { to: '/reports', icon: FileText, label: 'Reports' },
]

export default function Sidebar() {
  const [open, setOpen] = useState(false)

  return (
    <>
      {/* Mobile hamburger */}
      <button
        className="lg:hidden fixed top-4 left-4 z-50 bg-[#0f1117] border border-[#1e2535] rounded-lg p-2 text-[#7dd3fc]"
        onClick={() => setOpen(!open)}
      >
        {open ? <X size={20} /> : <Menu size={20} />}
      </button>

      {/* Overlay */}
      {open && (
        <div
          className="lg:hidden fixed inset-0 bg-black/60 z-40"
          onClick={() => setOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={`
          fixed top-0 left-0 h-full w-64 z-40
          bg-[#0a0d14] border-r border-[#1e2535]
          flex flex-col
          transition-transform duration-300
          ${open ? 'translate-x-0' : '-translate-x-full'}
          lg:translate-x-0 lg:static lg:h-screen
        `}
      >
        {/* Logo */}
        <div className="flex items-center gap-3 px-6 py-6 border-b border-[#1e2535]">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#38bdf8] to-[#6366f1] flex items-center justify-center shadow-lg shadow-sky-500/20">
            <Zap size={16} className="text-white" />
          </div>
          <div>
            <span className="text-white font-bold text-lg tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>
              Zentra
            </span>
            <p className="text-[#4a5568] text-xs">Scam Intelligence</p>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
          {navItems.map(({ to, icon: Icon, label }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              onClick={() => setOpen(false)}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all duration-150
                ${isActive
                  ? 'bg-gradient-to-r from-sky-500/20 to-indigo-500/10 text-sky-400 border border-sky-500/20'
                  : 'text-[#6b7a99] hover:text-[#a8b8d0] hover:bg-[#111827]'
                }`
              }
            >
              <Icon size={17} />
              {label}
            </NavLink>
          ))}
        </nav>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-[#1e2535]">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span className="text-xs text-[#4a5568]">Live Monitoring</span>
          </div>
        </div>
      </aside>
    </>
  )
}