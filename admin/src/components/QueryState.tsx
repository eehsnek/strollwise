import type { ReactNode } from 'react'

export function QueryState({
  isLoading,
  isError,
  error,
  loadingLabel = 'Loading…',
  children,
}: {
  isLoading: boolean
  isError: boolean
  error: Error | null
  loadingLabel?: string
  children: ReactNode
}) {
  if (isLoading) {
    return <div className="text-sw-muted animate-pulse py-8">{loadingLabel}</div>
  }
  if (isError) {
    return (
      <div className="rounded-2xl border border-red-200 bg-red-50 p-5 text-red-800">
        <div className="font-bold">Failed to load data</div>
        <p className="text-sm mt-1">{error?.message ?? 'Unknown error'}</p>
        <p className="text-xs mt-2 text-red-600">
          Ensure the backend is running and you are signed in as an admin.
        </p>
      </div>
    )
  }
  return <>{children}</>
}
