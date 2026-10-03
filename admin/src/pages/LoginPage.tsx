import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ApiError, checkApiHealth, getToken, login } from '../api/client'
import { BrandLogo } from '../components/BrandLogo'
import { Button } from '../components/Button'
import { colors } from '../theme/colors'

export function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const adminRequired = (location.state as { reason?: string } | null)?.reason === 'admin_required'
  const [email, setEmail] = useState('admin@strollwise.dev')
  const [password, setPassword] = useState('admin123456')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [apiOk, setApiOk] = useState<boolean | null>(null)

  useEffect(() => {
    checkApiHealth().then(setApiOk)
  }, [])

  useEffect(() => {
    if (getToken()) navigate('/', { replace: true })
  }, [navigate])

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError('')
    try {
      await login(email.trim(), password)
      navigate('/')
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message)
      } else if (err instanceof TypeError) {
        setError(
          'Cannot reach the backend API. Start it with: cd backend && ./scripts/dev.sh',
        )
      } else {
        setError(err instanceof Error ? err.message : 'Login failed')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div
      className="min-h-screen flex items-center justify-center p-4 relative overflow-hidden"
      style={{
        background: `linear-gradient(145deg, ${colors.backgroundAlt} 0%, ${colors.background} 45%, #fffef5 100%)`,
      }}
    >
      <div
        className="absolute inset-0 flex items-center justify-center pointer-events-none opacity-[0.06]"
        aria-hidden
      >
        <img src="/strollwiselogo.jpg" alt="" className="w-80 h-80 object-cover rounded-full" />
      </div>

      <form
        onSubmit={onSubmit}
        className="relative bg-white/95 backdrop-blur-sm p-8 rounded-[28px] shadow-xl w-full max-w-md border border-white"
        style={{ boxShadow: '0 12px 24px rgba(15, 23, 42, 0.08)' }}
      >
        <BrandLogo size="md" subtitle="Admin Console" className="mb-6" />

        <h1 className="text-xl font-black text-sw-ink">Researcher sign in</h1>
        <p className="text-sm text-sw-muted mt-1 mb-6">
          Review pending tags, validate zones, and export thesis data.
        </p>

        {apiOk === false ? (
          <div className="mb-4 text-sm text-amber-900 bg-amber-50 border border-amber-200 p-3 rounded-xl">
            Backend API is not reachable. Run{' '}
            <code className="text-xs bg-white px-1 py-0.5 rounded">cd backend && ./scripts/dev.sh</code>
          </div>
        ) : null}

        {adminRequired ? (
          <div className="mb-4 text-sm text-amber-900 bg-amber-50 border border-amber-200 p-3 rounded-xl">
            Your session does not have admin access. Sign in with an admin account.
          </div>
        ) : null}

        {error === 'Admin access required' ? (
          <div className="mb-4 text-sm text-red-700 bg-red-50 border border-red-100 p-3 rounded-xl space-y-2">
            <p>This account exists but does not have admin privileges.</p>
            <p className="text-xs text-red-600">
              Repair the default admin:{' '}
              <code className="bg-white px-1 py-0.5 rounded">
                cd backend && ./scripts/reset_admin.sh
              </code>
            </p>
          </div>
        ) : error ? (
          <div className="mb-4 text-sm text-red-700 bg-red-50 border border-red-100 p-3 rounded-xl">
            {error}
          </div>
        ) : null}

        <label className="block text-sm font-bold text-sw-ink mb-1">Email</label>
        <input
          className="w-full border border-sw-border rounded-xl px-3 py-2.5 mb-4 focus:outline-none focus:ring-2 focus:ring-sw-primary/40"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          type="email"
          required
        />

        <label className="block text-sm font-bold text-sw-ink mb-1">Password</label>
        <input
          className="w-full border border-sw-border rounded-xl px-3 py-2.5 mb-6 focus:outline-none focus:ring-2 focus:ring-sw-primary/40"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          type="password"
          required
        />

        <Button type="submit" disabled={loading} className="w-full py-3">
          {loading ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>
    </div>
  )
}
