import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { api } from '../api/client'
import type { AdminReportDetail, AdminReportList } from '../api/types'
import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { colors } from '../theme/colors'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'

const queues = [
  { id: 'pending', label: 'Pending' },
  { id: 'flagged', label: 'Flagged' },
  { id: 'duplicates', label: 'Duplicates' },
  { id: 'near_threshold', label: 'Near threshold' },
] as const

export function ModerationPage() {
  const qc = useQueryClient()
  const [queue, setQueue] = useState<(typeof queues)[number]['id']>('pending')
  const [selected, setSelected] = useState<string[]>([])
  const [focusedId, setFocusedId] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  const [actionError, setActionError] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['moderation', queue],
    queryFn: () =>
      api<AdminReportList>(`/admin/moderation/reports?queue=${queue}&page_size=100`),
    refetchInterval: LIVE_POLL_MS.moderation,
  })

  const { data: detail } = useQuery({
    queryKey: ['moderation-detail', focusedId],
    queryFn: () => api<AdminReportDetail>(`/admin/moderation/reports/${focusedId}`),
    enabled: !!focusedId,
  })

  const filtered = useMemo(() => {
    const items = data?.items ?? []
    const q = search.trim().toLowerCase()
    if (!q) return items
    return items.filter(
      (r) =>
        r.category.includes(q) ||
        r.h3_index.includes(q) ||
        r.tags.some((t) => t.includes(q)) ||
        (r.note_text ?? '').toLowerCase().includes(q),
    )
  }, [data?.items, search])

  const action = useMutation({
    mutationFn: async ({
      id,
      kind,
    }: {
      id: string
      kind: 'approve' | 'reject' | 'flag'
    }) => api(`/admin/moderation/reports/${id}/${kind}`, { method: 'POST' }),
    onSuccess: () => {
      setActionError('')
      qc.invalidateQueries({ queryKey: ['moderation'] })
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      qc.invalidateQueries({ queryKey: ['zones'] })
      setSelected([])
    },
    onError: (err: Error) => setActionError(err.message),
  })

  const bulk = useMutation({
    mutationFn: (kind: 'approve' | 'reject' | 'flag') =>
      api('/admin/moderation/reports/bulk', {
        method: 'POST',
        body: JSON.stringify({ report_ids: selected, action: kind }),
      }),
    onSuccess: () => {
      setActionError('')
      qc.invalidateQueries({ queryKey: ['moderation'] })
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      setSelected([])
    },
    onError: (err: Error) => setActionError(err.message),
  })

  return (
    <div className="space-y-4">
      <PageHeader
        title="Moderation Queue"
        description="Review pending and flagged tag submissions. Privacy-safe view — no raw GPS or user identities."
      />

      {actionError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {actionError}
        </div>
      ) : null}

      <div className="flex flex-col lg:flex-row gap-2">
        <div className="flex gap-2 flex-wrap flex-1">
          {queues.map((q) => (
            <button
              key={q.id}
              type="button"
              onClick={() => setQueue(q.id)}
              className={`px-4 py-2 rounded-xl text-sm font-bold border transition-colors ${
                queue === q.id
                  ? 'bg-sw-primary text-white border-sw-primary'
                  : 'bg-sw-surface text-sw-muted border-sw-border hover:border-sw-primary/40'
              }`}
            >
              {q.label}
            </button>
          ))}
        </div>
        <input
          placeholder="Search category, H3, tags…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="border border-sw-border rounded-xl px-3 py-2 text-sm w-full lg:w-64 bg-sw-surface"
        />
      </div>

      {selected.length > 0 ? (
        <div className="flex gap-2 flex-wrap">
          <Button onClick={() => bulk.mutate('approve')}>Bulk approve ({selected.length})</Button>
          <Button variant="warning" onClick={() => bulk.mutate('flag')}>Bulk flag</Button>
          <Button variant="danger" onClick={() => bulk.mutate('reject')}>Bulk reject</Button>
        </div>
      ) : null}

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <Card className="xl:col-span-2 p-0 overflow-hidden">
          <div className="overflow-auto max-h-[65vh]">
            <table className="w-full text-sm">
              <thead className="bg-sw-bg-alt text-left sticky top-0">
                <tr>
                  <th className="p-3 w-8" />
                  <th className="p-3 font-bold text-sw-muted text-[11px] uppercase">H3 cell</th>
                  <th className="p-3 font-bold text-sw-muted text-[11px] uppercase">Category</th>
                  <th className="p-3 font-bold text-sw-muted text-[11px] uppercase">Tags</th>
                  <th className="p-3 font-bold text-sw-muted text-[11px] uppercase">Conf.</th>
                  <th className="p-3 font-bold text-sw-muted text-[11px] uppercase">Status</th>
                  <th className="p-3 font-bold text-sw-muted text-[11px] uppercase">Actions</th>
                </tr>
              </thead>
              <tbody>
                {isLoading ? (
                  <tr><td colSpan={7} className="p-6 text-sw-muted">Loading…</td></tr>
                ) : filtered.length === 0 ? (
                  <tr><td colSpan={7} className="p-6 text-sw-muted">No reports in this queue.</td></tr>
                ) : (
                  filtered.map((r) => (
                    <tr
                      key={r.id}
                      className={`border-t border-sw-border cursor-pointer hover:bg-sw-bg-alt/60 ${
                        focusedId === r.id ? 'bg-sw-primary/5' : ''
                      }`}
                      onClick={() => setFocusedId(r.id)}
                    >
                      <td className="p-3" onClick={(e) => e.stopPropagation()}>
                        <input
                          type="checkbox"
                          checked={selected.includes(r.id)}
                          onChange={(e) =>
                            setSelected((prev) =>
                              e.target.checked
                                ? [...prev, r.id]
                                : prev.filter((x) => x !== r.id),
                            )
                          }
                        />
                      </td>
                      <td className="p-3 font-mono text-xs">{r.h3_index.slice(0, 12)}…</td>
                      <td className="p-3 font-semibold capitalize">{r.category}</td>
                      <td className="p-3 text-sw-muted max-w-[140px] truncate">{r.tags.join(', ')}</td>
                      <td className="p-3">{r.confidence_score}%</td>
                      <td className="p-3">
                        <Badge variant="status" value={r.visibility_status} />
                      </td>
                      <td className="p-3 space-x-1" onClick={(e) => e.stopPropagation()}>
                        <button type="button" className="text-sw-primary-dark font-bold text-xs" onClick={() => action.mutate({ id: r.id, kind: 'approve' })}>Approve</button>
                        <button type="button" className="text-amber-700 font-bold text-xs" onClick={() => action.mutate({ id: r.id, kind: 'flag' })}>Flag</button>
                        <button type="button" className="text-sw-alert font-bold text-xs" onClick={() => action.mutate({ id: r.id, kind: 'reject' })}>Reject</button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
          <div className="px-4 py-2 text-xs text-sw-muted border-t border-sw-border bg-sw-bg">
            {data?.total ?? 0} reports · auto-refreshes every 30s
          </div>
        </Card>

        <Card className="h-fit sticky top-6">
          <h2 className="font-black text-sw-ink mb-3">Validation context</h2>
          {!focusedId || !detail ? (
            <p className="text-sm text-sw-muted">Select a report to see cell-level validation metrics.</p>
          ) : (
            <div className="space-y-4 text-sm">
              <div>
                <div className="text-[11px] font-bold uppercase text-sw-muted">H3 cell</div>
                <div className="font-mono text-xs mt-1 break-all">{detail.h3_index}</div>
              </div>
              {detail.note_text ? (
                <div>
                  <div className="text-[11px] font-bold uppercase text-sw-muted">Note</div>
                  <p className="mt-1 text-sw-secondary">{detail.note_text}</p>
                </div>
              ) : null}
              <div className="grid grid-cols-2 gap-3">
                <Metric label="Contributors" value={detail.cell_context.distinct_contributors} />
                <Metric label="Threshold" value={detail.cell_context.threshold} />
                <Metric label="Pending in cell" value={detail.cell_context.pending_count} />
                <Metric label="Agreement" value={`${Math.round(detail.cell_context.category_agreement * 100)}%`} />
              </div>
              <div>
                <div className="text-[11px] font-bold uppercase text-sw-muted">Top category</div>
                <div className="font-semibold capitalize mt-1">{detail.cell_context.top_category ?? '—'}</div>
              </div>
              <div
                className="rounded-xl p-3 text-xs font-semibold"
                style={{
                  backgroundColor: detail.cell_context.threshold_met ? '#DDF5E8' : '#FFF4CC',
                  color: detail.cell_context.threshold_met ? colors.primaryDark : '#A16207',
                }}
              >
                {detail.cell_context.threshold_met
                  ? 'Auto-threshold met — approval will publish to the map.'
                  : `${detail.cell_context.threshold - detail.cell_context.distinct_contributors} more contributor(s) needed for auto-approval.`}
              </div>
              <div className="flex gap-2 pt-2 flex-wrap">
                <Button className="flex-1 min-w-[6rem]" onClick={() => action.mutate({ id: detail.id, kind: 'approve' })}>Approve</Button>
                <Button variant="warning" onClick={() => action.mutate({ id: detail.id, kind: 'flag' })}>Flag</Button>
                <Button variant="danger" onClick={() => action.mutate({ id: detail.id, kind: 'reject' })}>Reject</Button>
              </div>
            </div>
          )}
        </Card>
      </div>
    </div>
  )
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-sw-bg rounded-xl p-3">
      <div className="text-[10px] font-bold uppercase text-sw-muted">{label}</div>
      <div className="text-lg font-black text-sw-ink mt-0.5">{value}</div>
    </div>
  )
}
