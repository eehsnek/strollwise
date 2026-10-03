"""Writes immutable audit trail rows for sensitive user actions.

The audit log is append-only. Failures never block the main request —
we log and continue so a misbehaving schema never breaks a legitimate
user action.
"""
from __future__ import annotations

import logging
from typing import Any
from uuid import UUID

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog

log = logging.getLogger(__name__)


class AuditService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def record(
        self,
        *,
        actor_user_id: UUID | None,
        action_type: str,
        entity_type: str,
        entity_id: UUID | str | None = None,
        payload: dict[str, Any] | None = None,
    ) -> None:
        entry = AuditLog(
            actor_user_id=actor_user_id,
            action_type=action_type,
            entity_type=entity_type,
            entity_id=str(entity_id) if entity_id is not None else None,
            payload_json=payload,
        )
        try:
            # SAVEPOINT: never roll back the outer transaction (e.g. a pending
            # report insert) when audit logging alone fails.
            with self.db.begin_nested():
                self.db.add(entry)
                self.db.flush()
        except SQLAlchemyError as exc:
            log.warning("Failed to write audit log %s/%s: %s", entity_type, action_type, exc)
