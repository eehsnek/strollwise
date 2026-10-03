"""Runtime system settings stored in DB, overlaying env defaults."""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings, settings
from app.models.system_setting import SystemSetting

_CONFIG_KEYS = (
    "pending_min_reports_per_cell",
    "pending_agreement_ratio",
    "report_cooldown_hours_per_cell",
    "report_max_per_user_per_hour",
    "h3_resolution",
)


class SystemSettingsService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_effective_settings(self) -> Settings:
        base = get_settings()
        overrides = self._load_overrides()
        if not overrides:
            return base
        data = base.model_dump()
        for key, value in overrides.items():
            if key in data:
                field_type = type(getattr(base, key))
                if field_type is float:
                    data[key] = float(value)
                elif field_type is int:
                    data[key] = int(value)
                else:
                    data[key] = value
        return Settings(**data)

    def get_config_dict(self) -> dict[str, int | float]:
        eff = self.get_effective_settings()
        return {
            "pending_min_reports_per_cell": eff.pending_min_reports_per_cell,
            "pending_agreement_ratio": eff.pending_agreement_ratio,
            "report_cooldown_hours_per_cell": eff.report_cooldown_hours_per_cell,
            "report_max_per_user_per_hour": eff.report_max_per_user_per_hour,
            "h3_resolution": eff.h3_resolution,
        }

    def update_config(self, updates: dict[str, int | float | None]) -> dict[str, int | float]:
        for key, value in updates.items():
            if value is None or key not in _CONFIG_KEYS:
                continue
            row = self.db.get(SystemSetting, key)
            if row is None:
                row = SystemSetting(key=key, value=str(value))
                self.db.add(row)
            else:
                row.value = str(value)
        self.db.flush()
        get_settings.cache_clear()
        return self.get_config_dict()

    def _load_overrides(self) -> dict[str, str]:
        stmt = select(SystemSetting).where(SystemSetting.key.in_(_CONFIG_KEYS))
        rows = self.db.execute(stmt).scalars()
        return {row.key: row.value for row in rows}


def effective_settings(db: Session) -> Settings:
    return SystemSettingsService(db).get_effective_settings()
