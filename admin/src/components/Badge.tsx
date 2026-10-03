import { statusStyles, lifecycleStyles, travelerMixStyles } from '../theme/colors'

type BadgeVariant = 'status' | 'lifecycle' | 'mix' | 'default'

export function Badge({
  label,
  variant = 'default',
  value,
}: {
  label?: string
  variant?: BadgeVariant
  value: string
}) {
  let style = { bg: '#EEF2F7', text: '#475569' }
  const key = value.toLowerCase()

  if (variant === 'status' && statusStyles[key]) style = statusStyles[key]
  if (variant === 'lifecycle' && lifecycleStyles[key]) style = lifecycleStyles[key]
  if (variant === 'mix' && travelerMixStyles[key]) style = travelerMixStyles[key]

  return (
    <span
      className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-bold uppercase tracking-wide"
      style={{ backgroundColor: style.bg, color: style.text }}
    >
      {label ?? value.replace(/_/g, ' ')}
    </span>
  )
}
