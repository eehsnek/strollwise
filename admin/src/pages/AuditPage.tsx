import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { api, downloadExport } from '../api/client'
import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'
import { useState } from 'react'

type AuditList = {
  items: {
    id: string
    action_type: string
    entity_type: string
    entity_id?: string | null
    created_at: string
  }[]
  total: number
}

export function AuditPage() {
  const [exportError, setExportError] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['audit'],
    queryFn: () => api<AuditList>('/admin/audit?page_size=100'),
    refetchInterval: LIVE_POLL_MS.audit,
  })

  async function exportAudit() {
    setExportError('')
    try {
      await downloadExport('/admin/analytics/export/audit?fmt=csv', 'audit.csv')
    } catch (err) {
      setExportError(err instanceof Error ? err.message : 'Export failed')
    }
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="Audit Log"
        description="Immutable trail of admin moderation actions and mobile app report events."
        actions={
          <>
            <Button variant="secondary" onClick={exportAudit}>Export CSV</Button>
            <Link to="/analytics">
              <Button variant="ghost">Analytics overview</Button>
            </Link>
          </>
        }
      />

      {exportError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {exportError}
        </div>
      ) : null}

      <Card className="p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-sw-bg-alt text-left sticky top-0">
            <tr>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Time</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Action</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Entity</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Entity ID</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={4} className="p-6 text-sw-muted">Loading…</td></tr>
            ) : (
              data?.items.map((e) => (
                <tr key={e.id} className="border-t border-sw-border hover:bg-sw-bg-alt/40">
                  <td className="p-3 text-xs whitespace-nowrap">
                    {new Date(e.created_at).toLocaleString()}
                  </td>
                  <td className="p-3">
                    <Badge variant="default" value={e.action_type.replace(/\./g, ' ')} label={e.action_type} />
                  </td>
                  <td className="p-3 font-semibold">{e.entity_type}</td>
                  <td className="p-3 font-mono text-xs text-sw-muted">{e.entity_id ?? '—'}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <div className="px-4 py-2 text-xs text-sw-muted border-t border-sw-border">
          {data?.total ?? 0} entries — auto-refreshes when the mobile app submits tags
        </div>
      </Card>
    </div>
  )
}
