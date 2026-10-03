export type AdminReport = {
  id: string
  h3_index: string
  category: string
  tags: string[]
  note_text?: string | null
  visibility_status: string
  confidence_score: number
  contributor_count: number
  duplicate_count: number
  created_at: string
}

export type AdminReportList = {
  items: AdminReport[]
  total: number
  page: number
  page_size: number
}

export type AdminCellContext = {
  h3_index: string
  pending_count: number
  visible_count: number
  flagged_count: number
  distinct_contributors: number
  top_category: string | null
  category_agreement: number
  threshold: number
  threshold_met: boolean
}

export type AdminReportDetail = AdminReport & {
  cell_context: AdminCellContext
}

export type AdminZoneValidation = {
  zone_id: string
  display_name: string
  total_signals: number
  matching_signals: number
  confidence: number
  top_category: string | null
  last_updated: string | null
  lifecycle_state: string
}

export type AdminDashboardStats = {
  pending_reports: number
  flagged_reports: number
  active_zones: number
  total_users: number
  local_contributor_ratio: number
  reports_last_30_days: { date: string; count: number }[]
}

export type AdminZone = {
  zone_id: string
  display_name: string
  slug: string
  traveler_mix?: string | null
  function_type?: string | null
  live_status: string
  confidence_score: number
  report_count: number
  is_active: boolean
  lifecycle_state: string
}

export type AdminUser = {
  id: string
  email: string
  display_name?: string | null
  user_type?: string | null
  is_active: boolean
  is_admin: boolean
  report_count: number
  created_at: string
}

export type AdminUserList = {
  items: AdminUser[]
  total: number
}

export type AdminCatalogEntry = {
  zone_id: string
  zone_name: string
  city: string
  zone_type: string
  radius_km: number
  center_lat: number
  center_lng: number
  characteristics: string[]
  default_local_ratio: number
  is_active: boolean
}

export type AdminSystemConfig = {
  pending_min_reports_per_cell: number
  pending_agreement_ratio: number
  report_cooldown_hours_per_cell: number
  report_max_per_user_per_hour: number
  h3_resolution: number
}

export type AdminAuditEntry = {
  id: string
  action_type: string
  entity_type: string
  entity_id?: string | null
  created_at: string
}

export type AdminAnalyticsOverview = {
  pending_reports: number
  flagged_reports: number
  visible_reports: number
  active_zones: number
  local_contributors: number
  international_contributors: number
  domestic_contributors: number
  zones_emerging: number
  zones_defined: number
  city_pulse: Record<string, unknown>
}

export type AdminPipelineResult = {
  job: string
  message: string
  affected_counts: Record<string, number>
}
