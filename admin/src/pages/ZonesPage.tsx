import { useQuery } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { api } from '../api/client'
import type { AdminZone, AdminZoneValidation } from '../api/types'
import { Badge } from '../components/Badge'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'
import { colors } from '../theme/colors'

export function ZonesPage() {
  const [filter, setFilter] = useState<'all' | 'defined' | 'emerging' | 'unthreshold'>('all')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['zones'],
    queryFn: () => api<AdminZone[]>('/admin/zones'),
    refetchInterval: LIVE_POLL_MS.zones,
  })

  const { data: validation } = useQuery({
    queryKey: ['zone-validation', selectedId],
    queryFn: () => api<AdminZoneValidation>(`/admin/zones/${selectedId}/validation`),
    enabled: !!selectedId,
  })

  const filtered = useMemo(() => {
    let rows = data ?? []
    if (filter !== 'all') rows = rows.filter((z) => z.lifecycle_state === filter)
    const q = search.trim().toLowerCase()
    if (q) rows = rows.filter((z) => z.display_name.toLowerCase().includes(q))
    return rows.sort((a, b) => b.confidence_score - a.confidence_score)
  }, [data, filter, search])

  const counts = useMemo(() => {
    const all = data ?? []
    return {
      all: all.length,
      defined: all.filter((z) => z.lifecycle_state === 'defined').length,
      emerging: all.filter((z) => z.lifecycle_state === 'emerging').length,
      unthreshold: all.filter((z) => z.lifecycle_state === 'unthreshold').length,
    }
  }, [data])

  return (
    <div className="space-y-4">
      <PageHeader
        title="Zone Validation"
        description="Mirrors the mobile app validation dashboard — confidence, lifecycle, and traveler mix for each merged zone."
      />

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex gap-2 flex-wrap">
          {(['all', 'defined', 'emerging', 'unthreshold'] as const).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setFilter(f)}
              className={`px-3 py-1.5 rounded-xl text-xs font-bold border capitalize ${
                filter === f
                  ? 'bg-sw-map-ink text-white border-sw-map-ink'
                  : 'bg-sw-surface border-sw-border text-sw-muted'
              }`}
            >
              {f} ({counts[f]})
            </button>
          ))}
        </div>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search zone name…"
          className="border border-sw-border rounded-xl px-3 py-2 text-sm bg-sw-surface sm:ml-auto w-full sm:w-56"
        />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <Card className="xl:col-span-2 p-0 overflow-hidden">
          <div className="overflow-auto max-h-[65vh]">
            <table className="w-full text-sm">
              <thead className="bg-sw-bg-alt sticky top-0">
                <tr>
                  <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Zone</th>
                  <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Mix</th>
                  <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Lifecycle</th>
                  <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Confidence</th>
                  <th className="p-3 text-left text-[11px] uppercase font-bold text-sw-muted">Signals</th>
                </tr>
              </thead>
              <tbody>
                {isLoading ? (
                  <tr><td colSpan={5} className="p-6 text-sw-muted">Loading…</td></tr>
                ) : (
                  filtered.map((z) => (
                    <tr
                      key={z.zone_id}
                      className={`border-t border-sw-border cursor-pointer hover:bg-sw-bg-alt/50 ${
                        selectedId === z.zone_id ? 'bg-sw-secondary/10' : ''
                      }`}
                      onClick={() => setSelectedId(z.zone_id)}
                    >
                      <td className="p-3">
                        <div className="font-bold text-sw-ink">{z.display_name}</div>
                        <div className="text-xs text-sw-muted">{z.live_status.replace(/_/g, ' ')}</div>
                      </td>
                      <td className="p-3">
                        {z.traveler_mix ? (
                          <Badge variant="mix" value={z.traveler_mix} />
                        ) : (
                          '—'
                        )}
                      </td>
                      <td className="p-3">
                        <Badge variant="lifecycle" value={z.lifecycle_state} />
                      </td>
                      <td className="p-3">
                        <div className="flex items-center gap-2">
                          <div className="w-16 h-2 rounded-full bg-sw-border overflow-hidden">
                            <div
                              className="h-full rounded-full"
                              style={{
                                width: `${Math.min(z.confidence_score, 100)}%`,
                                backgroundColor: colors.primary,
                              }}
                            />
                          </div>
                          <span className="font-bold">{z.confidence_score.toFixed(0)}%</span>
                        </div>
                      </td>
                      <td className="p-3 font-semibold">{z.report_count}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </Card>

        <Card className="h-fit sticky top-6">
          <h2 className="font-black text-sw-ink mb-3">Validation dashboard</h2>
          {!selectedId || !validation ? (
            <p className="text-sm text-sw-muted">Select a zone to inspect validation metrics shown in the mobile app.</p>
          ) : (
            <dl className="grid grid-cols-2 gap-3 text-sm">
              <ValidationTile label="Total signals" value={validation.total_signals} />
              <ValidationTile label="Matching" value={validation.matching_signals} />
              <ValidationTile label="Confidence" value={`${validation.confidence.toFixed(0)}%`} />
              <ValidationTile
                label="Updated"
                value={
                  validation.last_updated
                    ? new Date(validation.last_updated).toLocaleDateString()
                    : '—'
                }
              />
              <div className="col-span-2 bg-sw-bg rounded-xl p-3">
                <dt className="text-[10px] font-bold uppercase text-sw-muted">Top agreed category</dt>
                <dd className="font-bold capitalize mt-1">{validation.top_category ?? '—'}</dd>
              </div>
              <div className="col-span-2">
                <Badge variant="lifecycle" value={validation.lifecycle_state} />
              </div>
            </dl>
          )}
        </Card>
      </div>
    </div>
  )
}

function ValidationTile({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-sw-bg rounded-xl p-3">
      <dt className="text-[10px] font-bold uppercase text-sw-muted">{label}</dt>
      <dd className="text-lg font-black text-sw-ink mt-0.5">{value}</dd>
    </div>
  )
}
