import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { api } from '../api/client'
import type { AdminUserList } from '../api/types'
import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import { Card } from '../components/Card'
import { PageHeader } from '../components/PageHeader'
import { LIVE_POLL_MS } from '../hooks/useAdminLiveUpdates'

export function UsersPage() {
  const qc = useQueryClient()
  const [search, setSearch] = useState('')

  const [toggleError, setToggleError] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['users', search],
    queryFn: () =>
      api<AdminUserList>(
        `/admin/users?page_size=100${search ? `&search=${encodeURIComponent(search)}` : ''}`,
      ),
    refetchInterval: LIVE_POLL_MS.users,
  })

  const toggle = useMutation({
    mutationFn: ({ id, is_admin }: { id: string; is_admin: boolean }) =>
      api(`/admin/users/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_admin }),
      }),
    onSuccess: () => {
      setToggleError('')
      qc.invalidateQueries({ queryKey: ['users'] })
    },
    onError: (err: Error) => setToggleError(err.message),
  })

  return (
    <div className="space-y-4">
      <PageHeader
        title="Users"
        description="Manage contributor accounts from the StrollWise mobile app. Promote researchers to admin access."
        actions={
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search email or name…"
            className="border border-sw-border rounded-xl px-3 py-2 text-sm bg-sw-surface w-56"
          />
        }
      />

      {toggleError ? (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {toggleError}
        </div>
      ) : null}

      <Card className="p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-sw-bg-alt text-left">
            <tr>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">User</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Type</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Reports</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Role</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Status</th>
              <th className="p-3 text-[11px] uppercase font-bold text-sw-muted">Actions</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={6} className="p-6 text-sw-muted">Loading…</td></tr>
            ) : (
              data?.items.map((u) => (
                <tr key={u.id} className="border-t border-sw-border">
                  <td className="p-3">
                    <div className="font-bold">{u.email}</div>
                    {u.display_name ? (
                      <div className="text-xs text-sw-muted">{u.display_name}</div>
                    ) : null}
                  </td>
                  <td className="p-3 capitalize text-sw-muted">{u.user_type?.replace(/_/g, ' ') ?? '—'}</td>
                  <td className="p-3 font-bold">{u.report_count}</td>
                  <td className="p-3">
                    {u.is_admin ? (
                      <Badge variant="default" value="admin" label="Admin" />
                    ) : (
                      <span className="text-sw-muted">Contributor</span>
                    )}
                  </td>
                  <td className="p-3">
                    <Badge variant="status" value={u.is_active ? 'visible' : 'removed'} label={u.is_active ? 'Active' : 'Inactive'} />
                  </td>
                  <td className="p-3">
                    <Button
                      variant="ghost"
                      className="!px-2 !py-1 text-xs"
                      onClick={() => toggle.mutate({ id: u.id, is_admin: !u.is_admin })}
                    >
                      {u.is_admin ? 'Revoke admin' : 'Make admin'}
                    </Button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </Card>
    </div>
  )
}
