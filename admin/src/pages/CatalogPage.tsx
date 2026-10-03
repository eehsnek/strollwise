import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api, downloadExport } from '../api/client'
import type { AdminCatalogEntry } from '../api/types'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'
import { travelerMixStyles } from '../theme/colors'

export function CatalogPage() {
  const [exportError, setExportError] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['catalog'],
    queryFn: () => api<AdminCatalogEntry[]>('/admin/catalog/zones'),
    refetchInterval: LIVE_POLL_MS.catalog,
  })

  async function download(fmt: 'json' | 'csv') {
    setExportError('')
    try {
      await downloadExport(`/admin/analytics/export/zones?fmt=${fmt}`, `zones.${fmt}`)
    } catch (err) {
      setExportError(err instanceof Error ? err.message : 'Export failed')
    }
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="Zone Catalog"
        description="Researcher-assigned zone names for Metro Cebu — synced to the backend zone API used by the mobile app."
        actions={
          <>
            <Button variant="secondary" onClick={() => download('csv')}>Export CSV</Button>
            <Button variant="secondary" onClick={() => download('json')}>Export JSON</Button>
          </>
        }
      />

      {exportError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {exportError}
        </div>
      ) : null}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-2">
        <Card padding="p-4">
          <div className="text-[11px] font-bold uppercase text-sw-muted">Catalog zones</div>
          <div className="text-2xl font-black mt-1">{data?.length ?? '—'}</div>
        </Card>
        <Card padding="p-4">
          <div className="text-[11px] font-bold uppercase text-sw-muted">Local-dominant</div>
          <div className="text-2xl font-black mt-1 text-green-700">
            {data?.filter((e) => e.zone_type === 'LOCAL').length ?? '—'}
          </div>
        </Card>
        <Card padding="p-4">
          <div className="text-[11px] font-bold uppercase text-sw-muted">International-dominant</div>
          <div className="text-2xl font-black mt-1 text-blue-700">
            {data?.filter((e) => e.zone_type === 'INTERNATIONAL').length ?? '—'}
          </div>
        </Card>
      </div>

      <Card className="p-0 overflow-auto max-h-[60vh]">
        <table className="w-full text-sm">
          <thead className="bg-sw-bg-alt sticky top-0">
            <tr>
              <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">ID</th>
              <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Name</th>
              <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">City</th>
              <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Type</th>
              <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Radius</th>
              <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Local ratio</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={6} className="p-6 text-sw-muted">Loading…</td></tr>
            ) : (
              data?.map((e) => {
                const mixKey = e.zone_type.toLowerCase()
                const mixStyle = travelerMixStyles[mixKey === 'local' ? 'local' : mixKey === 'international' ? 'international' : 'mixed']
                return (
                  <tr key={e.zone_id} className="border-t border-sw-border hover:bg-sw-bg-alt/40">
                    <td className="p-3 font-mono text-xs">{e.zone_id}</td>
                    <td className="p-3 font-bold">{e.zone_name}</td>
                    <td className="p-3 text-sw-muted">{e.city}</td>
                    <td className="p-3">
                      <span
                        className="text-[11px] font-bold uppercase px-2 py-0.5 rounded-full"
                        style={{ backgroundColor: mixStyle?.bg, color: mixStyle?.text }}
                      >
                        {e.zone_type}
                      </span>
                    </td>
                    <td className="p-3">{e.radius_km} km</td>
                    <td className="p-3">{(e.default_local_ratio * 100).toFixed(0)}%</td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </Card>
    </div>
  )
}
