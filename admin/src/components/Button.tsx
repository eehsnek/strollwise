import type { ButtonHTMLAttributes, ReactNode } from 'react'

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'warning'

const variants: Record<Variant, string> = {
  primary: 'bg-sw-primary hover:bg-sw-primary-dark text-white shadow-sm',
  secondary: 'bg-sw-secondary/20 hover:bg-sw-secondary/30 text-sw-map-ink',
  ghost: 'bg-transparent hover:bg-sw-bg-alt text-sw-muted hover:text-sw-ink',
  danger: 'bg-sw-alert hover:bg-red-600 text-white',
  warning: 'bg-amber-500 hover:bg-amber-600 text-white',
}

export function Button({
  children,
  variant = 'primary',
  className = '',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode
  variant?: Variant
}) {
  return (
    <button
      type="button"
      className={`inline-flex items-center justify-center gap-2 px-3.5 py-2 rounded-xl text-sm font-bold transition-colors disabled:opacity-50 ${variants[variant]} ${className}`}
      {...props}
    >
      {children}
    </button>
  )
}
