import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { api } from '../api/client'
import type { AdminPipelineResult } from '../api/types'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'

const jobs = [
  {
    id: 'rebuild-cells',
    label: 'Rebuild H3 cells',
    desc: 'Recompute cell aggregates from approved reports',
  },
  {
    id: 'rebuild-places',
    label: 'Rebuild places',
    desc: 'Regenerate place footprints from H3 clusters',
  },
  {
    id: 'rebuild-zones',
    label: 'Rebuild zones',
    desc: 'Refresh merged zones shown on the mobile map',
  },
  {
    id: 'rebuild-all',
    label: 'Full pipeline',
    desc: 'Cells → places → zones (same as seed tail)',
  },
  {
    id: 'invalidate-cache',
    label: 'Invalidate cache',
    desc: 'Clear Redis zone and analytics cache',
  },
] as const

export function PipelinePage() {
  const qc = useQueryClient()
  const [lastResult, setLastResult] = useState<AdminPipelineResult | null>(null)
  const [runError, setRunError] = useState('')

  const run = useMutation({
    mutationFn: (job: (typeof jobs)[number]['id']) =>
      api<AdminPipelineResult>(`/admin/pipeline/${job}`, { method: 'POST' }),
    onSuccess: (data) => {
      setRunError('')
      setLastResult(data)
      qc.invalidateQueries({ queryKey: ['zones'] })
      qc.invalidateQueries({ queryKey: ['dashboard'] })
      qc.invalidateQueries({ queryKey: ['analytics'] })
    },
    onError: (err: Error) => {
      setLastResult(null)
      setRunError(err.message)
    },
  })

  return (
    <div className="space-y-4">
      <PageHeader
        title="Pipeline Controls"
        description="Trigger the same aggregation pipeline that powers the StrollWise explore map and zone feed."
      />

      {runError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {runError}
        </div>
      ) : null}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 max-w-3xl">
        {jobs.map((job) => (
          <Card key={job.id} padding="p-5">
            <h3 className="font-black text-sw-ink">{job.label}</h3>
            <p className="text-sm text-sw-muted mt-1 mb-4">{job.desc}</p>
            <Button
              variant="secondary"
              disabled={run.isPending}
              onClick={() => run.mutate(job.id)}
            >
              {run.isPending ? 'Running…' : 'Run job'}
            </Button>
          </Card>
        ))}
      </div>

      {lastResult ? (
        <Card className="border-sw-primary/30 bg-sw-primary/5">
          <div className="font-bold text-sw-primary-dark">{lastResult.message}</div>
          <pre className="mt-2 text-xs overflow-auto text-sw-secondary">
            {JSON.stringify(lastResult.affected_counts, null, 2)}
          </pre>
        </Card>
      ) : null}
    </div>
  )
}
