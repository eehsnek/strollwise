import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { api } from '../api/client'
import type { AdminSystemConfig } from '../api/types'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'

const fields = [
  ['pending_min_reports_per_cell', 'Min contributors per H3 cell', 1],
  ['pending_agreement_ratio', 'Category agreement ratio (0–1)', 0.05],
  ['report_cooldown_hours_per_cell', 'Cooldown hours per cell', 1],
  ['report_max_per_user_per_hour', 'Max reports per user / hour', 1],
  ['h3_resolution', 'H3 resolution', 1],
] as const

export function SettingsPage() {
  const qc = useQueryClient()
  const { data } = useQuery({
    queryKey: ['config'],
    queryFn: () => api<AdminSystemConfig>('/admin/config'),
  })
  const [form, setForm] = useState<Partial<AdminSystemConfig>>({})
  const [saved, setSaved] = useState(false)

  const [saveError, setSaveError] = useState('')

  const save = useMutation({
    mutationFn: () =>
      api<AdminSystemConfig>('/admin/config', {
        method: 'PATCH',
        body: JSON.stringify(form),
      }),
    onSuccess: () => {
      setSaveError('')
      qc.invalidateQueries({ queryKey: ['config'] })
      setForm({})
      setSaved(true)
      setTimeout(() => setSaved(false), 3000)
    },
    onError: (err: Error) => setSaveError(err.message),
  })

  if (!data) return <div className="text-sw-muted">Loading settings…</div>

  const values = { ...data, ...form }

  return (
    <div className="space-y-4 max-w-2xl">
      <PageHeader
        title="Validation Settings"
        description="Runtime thresholds for crowd-based tag approval — same rules used by the StrollWise mobile app pipeline."
      />

      {saveError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {saveError}
        </div>
      ) : null}

      <Card className="space-y-5">
        {fields.map(([key, label, step]) => (
          <label key={key} className="block">
            <span className="text-sm font-bold text-sw-ink">{label}</span>
            <input
              type="number"
              step={step}
              className="mt-1.5 w-full border border-sw-border rounded-xl px-3 py-2.5 bg-sw-bg focus:outline-none focus:ring-2 focus:ring-sw-primary/30"
              value={values[key]}
              onChange={(e) =>
                setForm((f) => ({
                  ...f,
                  [key]:
                    key === 'pending_agreement_ratio'
                      ? parseFloat(e.target.value)
                      : parseInt(e.target.value, 10),
                }))
              }
            />
          </label>
        ))}

        <div className="flex items-center gap-3 pt-2">
          <Button
            disabled={save.isPending || Object.keys(form).length === 0}
            onClick={() => save.mutate()}
          >
            Save changes
          </Button>
          {saved ? <span className="text-sm font-bold text-sw-primary-dark">Saved ✓</span> : null}
        </div>
      </Card>

      <Card className="bg-sw-bg-alt border-sw-secondary/30">
        <p className="text-sm text-sw-muted">
          Default auto-approval requires <strong>{values.pending_min_reports_per_cell}</strong> distinct
          contributors in the same H3 cell with{' '}
          <strong>{Math.round(values.pending_agreement_ratio * 100)}%</strong> category agreement —
          matching the thesis validation model.
        </p>
      </Card>
    </div>
  )
}
