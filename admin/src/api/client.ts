/** Empty = same-origin; Vite dev server proxies /api to the backend. */
export const API_URL = (import.meta.env.VITE_API_URL ?? '').replace(/\/$/, '')
const TOKEN_KEY = 'strollwise_admin_token'

export function getToken(): string | null {
  return sessionStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null) {
  if (token) sessionStorage.setItem(TOKEN_KEY, token)
  else sessionStorage.removeItem(TOKEN_KEY)
}

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

export async function api<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> | undefined),
  }
  const token = getToken()
  if (token) headers.Authorization = `Bearer ${token}`

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 15_000)
  let res: Response
  try {
    res = await fetch(`${API_URL}/api/v1${path}`, {
      ...options,
      headers,
      signal: options.signal ?? controller.signal,
    })
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new ApiError(408, 'Request timed out — is the backend running?')
    }
    throw err
  } finally {
    clearTimeout(timeout)
  }
  if (!res.ok) {
    let detail = res.statusText
    try {
      const body = await res.json()
      if (Array.isArray(body.detail)) {
        detail = body.detail.map((d: { msg?: string }) => d.msg).join('; ')
      } else {
        detail = body.detail ?? detail
      }
    } catch {
      /* ignore */
    }
    throw new ApiError(res.status, String(detail))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  if (!text) return undefined as T
  return JSON.parse(text) as T
}

export async function checkApiHealth(): Promise<boolean> {
  try {
    const res = await fetch(`${API_URL}/health`)
    return res.ok
  } catch {
    return false
  }
}

export async function login(email: string, password: string) {
  const data = await api<{ access_token: string; user: { is_admin: boolean } }>(
    '/auth/login',
    { method: 'POST', body: JSON.stringify({ email, password }) },
  )
  if (!data.user.is_admin) {
    throw new ApiError(403, 'Admin access required')
  }
  setToken(data.access_token)
  return data
}

export async function fetchMe() {
  return api<{ email: string; is_admin: boolean; display_name?: string }>('/auth/me')
}

export function exportUrl(path: string, fmt: 'json' | 'csv') {
  const token = getToken()
  const sep = path.includes('?') ? '&' : '?'
  return `${API_URL}/api/v1${path}${sep}fmt=${fmt}&token=${token ?? ''}`
}

export function apiDocsUrl(): string {
  const base = API_URL || 'http://127.0.0.1:8000'
  return `${base.replace(/\/$/, '')}/docs`
}

export async function downloadExport(path: string, filename: string): Promise<void> {
  const token = getToken()
  const res = await fetch(`${API_URL}/api/v1${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  })
  if (!res.ok) {
    let detail = res.statusText
    try {
      const body = await res.json()
      detail = body.detail ?? detail
    } catch {
      /* ignore */
    }
    throw new ApiError(res.status, String(detail))
  }
  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
