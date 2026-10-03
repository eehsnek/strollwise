/** StrollWise brand palette — mirrors frontend/lib/app/theme/colors.dart */
export const colors = {
  background: '#F2F4F5',
  backgroundAlt: '#EAF2F7',
  surface: '#FFFFFF',
  primaryText: '#0F172A',
  secondaryText: '#475569',
  mutedText: '#64748B',
  border: '#E2E8F0',
  borderStrong: '#CBD5E1',
  primary: '#39C97A',
  primaryDark: '#1F9B57',
  secondary: '#87C0E2',
  accent: '#F0D85A',
  alert: '#EF4444',
  mapInk: '#082F49',
  lagoon: '#6FA8C9',
  travelerLocal: '#22C55E',
  travelerInternational: '#3B82F6',
  travelerMixed: '#2FB7C8',
} as const

export const travelerMixStyles: Record<string, { bg: string; text: string; label: string }> = {
  local: { bg: '#DDF5E8', text: '#15803D', label: 'Local' },
  international: { bg: '#DCEBFF', text: '#1D4ED8', label: 'International' },
  mixed: { bg: '#D9F6F4', text: '#0F766E', label: 'Mixed' },
}

export const lifecycleStyles: Record<string, { bg: string; text: string }> = {
  defined: { bg: '#DDF5E8', text: '#15803D' },
  emerging: { bg: '#FFF4CC', text: '#A16207' },
  unthreshold: { bg: '#EEF2F7', text: '#64748B' },
}

export const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: '#FFF4CC', text: '#A16207' },
  visible: { bg: '#DDF5E8', text: '#15803D' },
  flagged: { bg: '#FDE2E2', text: '#991B1B' },
  removed: { bg: '#EEF2F7', text: '#64748B' },
}
