import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { api, downloadExport } from '../api/client'
import type { AdminAnalyticsOverview } from '../api/types'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { QueryState } from '../components/QueryState'
import { StatCard } from '../components/StatCard'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'
import { colors } from '../theme/colors'

const barColors = [colors.travelerLocal, colors.travelerInternational, colors.secondary]

export function AnalyticsPage() {
  const [exportError, setExportError] = useState('')

  const { data, isPending, isError, error } = useQuery({
    queryKey: ['analytics'],
    queryFn: () => api<AdminAnalyticsOverview>('/admin/analytics/overview'),
    refetchInterval: LIVE_POLL_MS.analytics,
  })

  async function download(path: string, fmt: 'json' | 'csv', filename: string) {
    setExportError('')
    try {
      await downloadExport(`/admin/analytics/export/${path}?fmt=${fmt}`, filename)
    } catch (err) {
      setExportError(err instanceof Error ? err.message : 'Export failed')
    }
  }

  if (isPending || isError || !data) {
    return (
      <QueryState isLoading={isPending} isError={isError} error={error} loadingLabel="Loading analytics…">
        {null}
      </QueryState>
    )
  }

  const chartData = [
    { name: 'Local', value: data.local_contributors, key: 'local' },
    { name: 'International', value: data.international_contributors, key: 'intl' },
    { name: 'Domestic', value: data.domestic_contributors, key: 'domestic' },
  ]

  return (
    <div className="space-y-6">
      <PageHeader
        title="Analytics & Export"
        description="Thesis-ready exports and contributor breakdowns — anonymized, aggregated by H3 cell."
        actions={
          <>
            <Button variant="secondary" onClick={() => download('reports', 'csv', 'reports.csv')}>Reports CSV</Button>
            <Button variant="secondary" onClick={() => download('zones', 'json', 'zones.json')}>Zones JSON</Button>
            <Button onClick={() => download('audit', 'csv', 'audit.csv')}>Audit CSV</Button>
            <Link to="/audit">
              <Button variant="ghost">View audit log</Button>
            </Link>
          </>
        }
      />

      {exportError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {exportError}
        </div>
      ) : null}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Visible reports" value={data.visible_reports} accent={colors.primary} />
        <StatCard label="Defined zones" value={data.zones_defined} accent={colors.travelerLocal} />
        <StatCard label="Emerging zones" value={data.zones_emerging} accent={colors.accent} />
        <StatCard label="Active zones" value={data.active_zones} accent={colors.secondary} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Card className="h-72">
          <h2 className="font-black text-sw-ink mb-4">Contributor types</h2>
          <ResponsiveContainer width="100%" height="85%">
            <BarChart data={chartData}>
              <XAxis dataKey="name" tick={{ fontSize: 12 }} />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Bar dataKey="value" radius={[8, 8, 0, 0]}>
                {chartData.map((_, i) => (
                  <Cell key={chartData[i].key} fill={barColors[i % barColors.length]} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card>
          <h2 className="font-black text-sw-ink mb-4">Research questions supported</h2>
          <ul className="space-y-3 text-sm text-sw-secondary">
            <li className="flex gap-2">
              <span className="text-sw-primary font-bold">•</span>
              Local vs international spatial knowledge differences in Metro Cebu
            </li>
            <li className="flex gap-2">
              <span className="text-sw-primary font-bold">•</span>
              Zone lifecycle progression (unthreshold → emerging → defined)
            </li>
            <li className="flex gap-2">
              <span className="text-sw-primary font-bold">•</span>
              Community validation thresholds and moderation audit trail
            </li>
          </ul>
        </Card>
      </div>
    </div>
  )
}
