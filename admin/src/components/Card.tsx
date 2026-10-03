import type { ReactNode } from 'react'

export function Card({
  children,
  className = '',
  padding = 'p-5',
}: {
  children: ReactNode
  className?: string
  padding?: string
}) {
  return (
    <div
      className={`bg-sw-surface rounded-2xl border border-sw-border shadow-sm ${padding} ${className}`}
    >
      {children}
    </div>
  )
}
