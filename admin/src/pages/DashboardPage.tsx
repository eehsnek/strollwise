import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { api } from '../api/client'
import type { AdminAnalyticsOverview, AdminDashboardStats } from '../api/types'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { QueryState } from '../components/QueryState'
import { StatCard } from '../components/StatCard'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'
import { colors } from '../theme/colors'

export function DashboardPage() {
  const { data, isPending, isError, error } = useQuery({
    queryKey: ['dashboard'],
    queryFn: () => api<AdminDashboardStats>('/admin/dashboard/stats'),
    refetchInterval: LIVE_POLL_MS.dashboard,
  })

  const { data: analytics, isError: analyticsError } = useQuery({
    queryKey: ['analytics-overview'],
    queryFn: () => api<AdminAnalyticsOverview>('/admin/analytics/overview'),
    refetchInterval: LIVE_POLL_MS.dashboard,
  })

  const pulse = analytics?.city_pulse as { city_activity?: string; crowd_level_percent?: number } | undefined
  const chartData = data?.reports_last_30_days ?? []

  return (
    <QueryState isLoading={isPending} isError={isError} error={error} loadingLabel="Loading dashboard…">
      {!data ? null : (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard"
        description="Research console for StrollWise — monitor tag validation, zone intelligence, and contributor activity across Metro Cebu."
        actions={
          <>
            <Link to="/moderation">
              <Button>Review queue</Button>
            </Link>
            <Link to="/analytics">
              <Button variant="secondary">Export data</Button>
            </Link>
          </>
        }
      />

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
        <StatCard
          label="Pending reports"
          value={data.pending_reports}
          hint="Awaiting validation"
          accent={colors.accent}
        />
        <StatCard
          label="Flagged reports"
          value={data.flagged_reports}
          hint="Needs review"
          accent={colors.alert}
        />
        <StatCard
          label="Active zones"
          value={data.active_zones}
          hint="On public map"
          accent={colors.secondary}
        />
        <StatCard
          label="Local contributors"
          value={`${Math.round(data.local_contributor_ratio * 100)}%`}
          hint={`${data.total_users} total users`}
          accent={colors.travelerLocal}
        />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <Card className="xl:col-span-2 h-80 min-w-0 flex flex-col">
          <h2 className="font-black text-sw-ink mb-4 shrink-0">Reports (last 30 days)</h2>
          {chartData.length > 0 ? (
            <div className="min-h-0 min-w-0 flex-1">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartData}>
                  <XAxis dataKey="date" tick={{ fontSize: 11 }} stroke={colors.mutedText} />
                  <YAxis allowDecimals={false} stroke={colors.mutedText} />
                  <Tooltip />
                  <Line
                    type="monotone"
                    dataKey="count"
                    stroke={colors.primary}
                    strokeWidth={3}
                    dot={{ fill: colors.primary, r: 3 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <p className="flex flex-1 items-center justify-center text-center text-sw-muted text-sm px-4">
              No reports in the last 30 days yet.
            </p>
          )}
        </Card>

        <Card>
          <h2 className="font-black text-sw-ink mb-4">City pulse</h2>
          {pulse ? (
            <dl className="space-y-4 text-sm">
              <div>
                <dt className="text-sw-muted font-semibold uppercase text-[11px]">Activity</dt>
                <dd className="text-2xl font-black capitalize text-sw-primary-dark mt-1">
                  {pulse.city_activity ?? '—'}
                </dd>
              </div>
              <div>
                <dt className="text-sw-muted font-semibold uppercase text-[11px]">Crowd level</dt>
                <dd className="text-xl font-bold mt-1">{pulse.crowd_level_percent ?? 0}%</dd>
              </div>
              <div>
                <dt className="text-sw-muted font-semibold uppercase text-[11px]">Defined zones</dt>
                <dd className="text-xl font-bold mt-1">{analytics?.zones_defined ?? 0}</dd>
              </div>
              <div>
                <dt className="text-sw-muted font-semibold uppercase text-[11px]">Emerging zones</dt>
                <dd className="text-xl font-bold mt-1">{analytics?.zones_emerging ?? 0}</dd>
              </div>
            </dl>
          ) : analyticsError ? (
            <p className="text-sm text-red-700">Could not load city pulse.</p>
          ) : (
            <p className="text-sw-muted text-sm">Loading city pulse…</p>
          )}
        </Card>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-l-4 border-l-sw-primary">
          <h3 className="font-bold text-sw-ink">Moderation</h3>
          <p className="text-sm text-sw-muted mt-1 mb-3">
            Approve, reject, or flag pending tag submissions before they affect the public map.
          </p>
          <Link to="/moderation" className="text-sm font-bold text-sw-primary-dark">
            Open queue →
          </Link>
        </Card>
        <Card className="border-l-4 border-l-sw-secondary">
          <h3 className="font-bold text-sw-ink">Zone validation</h3>
          <p className="text-sm text-sw-muted mt-1 mb-3">
            Inspect confidence scores and lifecycle states for merged zones shown in the mobile app.
          </p>
          <Link to="/zones" className="text-sm font-bold text-sw-lagoon">
            View zones →
          </Link>
        </Card>
        <Card className="border-l-4 border-l-sw-accent">
          <h3 className="font-bold text-sw-ink">Thesis export</h3>
          <p className="text-sm text-sw-muted mt-1 mb-3">
            Download anonymized reports, zone registry, and audit trails for research documentation.
          </p>
          <Link to="/analytics" className="text-sm font-bold text-amber-700">
            Export data →
          </Link>
        </Card>
      </div>
    </div>
      )}
    </QueryState>
  )
}
