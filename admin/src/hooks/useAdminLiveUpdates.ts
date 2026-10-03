import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { API_URL, getToken } from '../api/client'

function invalidateForEvent(qc: ReturnType<typeof useQueryClient>, type: string) {
  switch (type) {
    case 'report.created':
    case 'report.approved':
    case 'report.rejected':
    case 'report.flagged':
      qc.invalidateQueries({ queryKey: ['moderation'] })
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      qc.invalidateQueries({ queryKey: ['audit'] })
      qc.invalidateQueries({ queryKey: ['analytics'] })
      qc.invalidateQueries({ queryKey: ['analytics-overview'] })
      qc.invalidateQueries({ queryKey: ['users'] })
      break
    case 'zones.updated':
      qc.invalidateQueries({ queryKey: ['zones'] })
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      qc.invalidateQueries({ queryKey: ['analytics'] })
      qc.invalidateQueries({ queryKey: ['analytics-overview'] })
      break
    case 'dashboard.refresh':
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      qc.invalidateQueries({ queryKey: ['analytics-overview'] })
      break
    case 'catalog.updated':
      qc.invalidateQueries({ queryKey: ['catalog'] })
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      break
    default:
      break
  }
}

/** Subscribe to backend SSE so admin refreshes when the mobile app submits tags. */
export function useAdminLiveUpdates() {
  const qc = useQueryClient()
  const [connected, setConnected] = useState(false)

  useEffect(() => {
    const token = getToken()
    if (!token) return

    const url = `${API_URL}/api/v1/admin/events?token=${encodeURIComponent(token)}`
    const es = new EventSource(url)

    es.onopen = () => setConnected(true)
    es.onerror = () => setConnected(false)
    es.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data) as { type?: string }
        if (msg.type && msg.type !== 'connected') {
          invalidateForEvent(qc, msg.type)
        }
      } catch {
        /* ignore malformed events */
      }
    }

    return () => {
      es.close()
      setConnected(false)
    }
  }, [qc])

  return { connected }
}

/** Fallback polling when SSE is unavailable (same data the mobile app writes). */
export const LIVE_POLL_MS = {
  dashboard: 30_000,
  moderation: 15_000,
  zones: 30_000,
  audit: 30_000,
  users: 60_000,
  catalog: 60_000,
  analytics: 60_000,
} as const
