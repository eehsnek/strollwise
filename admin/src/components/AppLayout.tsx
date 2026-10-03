import { useQuery } from '@tanstack/react-query'
import { Link, NavLink, Navigate, Outlet } from 'react-router-dom'
import { apiDocsUrl, fetchMe, getToken, setToken } from '../api/client'
import { useAdminLiveUpdates } from '../hooks/useAdminLiveUpdates'
import { BrandLogo } from './BrandLogo'

const nav = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/moderation', label: 'Moderation' },
  { to: '/zones', label: 'Zones' },
  { to: '/users', label: 'Users' },
  { to: '/catalog', label: 'Catalog' },
  { to: '/analytics', label: 'Analytics' },
  { to: '/pipeline', label: 'Pipeline' },
  { to: '/settings', label: 'Settings' },
  { to: '/audit', label: 'Audit Log' },
]

function navClass({ isActive }: { isActive: boolean }) {
  return [
    'px-3 py-2.5 rounded-xl text-sm font-semibold block transition-colors',
    isActive
      ? 'bg-sw-primary text-white shadow-sm'
      : 'text-sw-secondary hover:bg-white/10 hover:text-white',
  ].join(' ')
}

export function AppLayout() {
  const token = getToken()
  const { data: me, isLoading, isError } = useQuery({
    queryKey: ['auth', 'me'],
    queryFn: fetchMe,
    enabled: Boolean(token),
  })
  const { connected } = useAdminLiveUpdates()

  if (!token) return <Navigate to="/login" replace />
  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-sw-bg text-sw-muted">
        Checking admin access…
      </div>
    )
  }
  if (isError || !me?.is_admin) {
    setToken(null)
    return <Navigate to="/login" replace state={{ reason: 'admin_required' }} />
  }

  return (
    <div className="min-h-screen flex bg-sw-bg">
      <aside className="w-60 bg-sw-map-ink text-white p-4 flex flex-col gap-1 shrink-0">
        <Link to="/" className="mb-5 px-1 block">
          <BrandLogo size="sm" subtitle="Admin Console" variant="dark" />
        </Link>

        <nav className="flex flex-col gap-0.5 flex-1">
          {nav.map((item) => (
            <NavLink key={item.to} to={item.to} end={item.end} className={navClass}>
              {item.label}
            </NavLink>
          ))}
        </nav>

        <div className="mt-4 pt-4 border-t border-white/10 space-y-2">
          <div className="px-3 flex items-center gap-2 text-[10px] font-bold uppercase tracking-wide">
            <span
              className={`w-2 h-2 rounded-full ${connected ? 'bg-sw-primary animate-pulse' : 'bg-white/30'}`}
              aria-hidden
            />
            <span className={connected ? 'text-sw-primary' : 'text-white/40'}>
              {connected ? 'Live — mobile sync' : 'Polling fallback'}
            </span>
          </div>
          <a
            href={apiDocsUrl()}
            target="_blank"
            rel="noreferrer"
            className="block px-3 py-2 text-xs font-semibold text-sw-secondary hover:text-white"
          >
            API docs ↗
          </a>
          <p className="px-3 text-[10px] text-white/40 leading-relaxed">
            Paired with the StrollWise mobile app for crowd-sourced zone intelligence in Metro Cebu.
          </p>
          <button
            type="button"
            className="w-full px-3 py-2 text-left text-sm font-semibold text-white/60 hover:text-white rounded-xl hover:bg-white/5"
            onClick={() => {
              setToken(null)
              window.location.href = '/login'
            }}
          >
            Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 p-6 lg:p-8 overflow-auto min-w-0">
        <Outlet />
      </main>
    </div>
  )
}
