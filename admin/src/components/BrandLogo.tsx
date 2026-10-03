type BrandLogoProps = {
  size?: 'sm' | 'md' | 'lg'
  showWordmark?: boolean
  subtitle?: string
  className?: string
  variant?: 'light' | 'dark'
}

const sizes = {
  sm: 'h-8 w-8',
  md: 'h-10 w-10',
  lg: 'h-14 w-14',
}

export function BrandLogo({
  size = 'md',
  showWordmark = true,
  subtitle,
  className = '',
  variant = 'light',
}: BrandLogoProps) {
  const titleClass = variant === 'dark' ? 'text-white' : 'text-sw-ink'
  const subtitleClass = variant === 'dark' ? 'text-sw-secondary' : 'text-sw-muted'

  return (
    <div className={`flex items-center gap-3 ${className}`}>
      <img
        src="/strollwiselogo.jpg"
        alt="StrollWise"
        className={`${sizes[size]} rounded-lg object-cover shadow-sm ring-1 ring-white/10`}
      />
      {showWordmark ? (
        <div>
          <div className={`font-black tracking-tight leading-none ${titleClass}`}>
            StrollWise
          </div>
          {subtitle ? (
            <div className={`text-[11px] font-semibold mt-0.5 uppercase tracking-wide ${subtitleClass}`}>
              {subtitle}
            </div>
          ) : (
            <div className="h-0.5 w-7 rounded-full bg-sw-secondary mt-1.5" />
          )}
        </div>
      ) : null}
    </div>
  )
}
