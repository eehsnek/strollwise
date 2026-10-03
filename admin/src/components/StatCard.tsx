import { colors } from '../theme/colors'

export function StatCard({
  label,
  value,
  hint,
  accent = colors.primary,
}: {
  label: string
  value: string | number
  hint?: string
  accent?: string
}) {
  return (
    <div className="bg-sw-surface rounded-2xl border border-sw-border p-5 shadow-sm relative overflow-hidden">
      <div
        className="absolute top-0 left-0 w-1 h-full rounded-l-2xl"
        style={{ backgroundColor: accent }}
      />
      <div className="text-[11px] font-bold uppercase tracking-wider text-sw-muted pl-2">
        {label}
      </div>
      <div className="text-3xl font-black mt-1 text-sw-ink pl-2">{value}</div>
      {hint ? <div className="text-xs text-sw-muted mt-1 pl-2">{hint}</div> : null}
    </div>
  )
}
