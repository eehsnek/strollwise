from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.schemas.user import UserPublic
from app.utils.user_type_utils import apply_user_type_to_user


class AuthError(Exception):
    """Authentication or registration failure."""


class AuthService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.users = UserRepository(db)

    def register(self, payload: RegisterRequest) -> TokenResponse:
        email = payload.email.lower()
        if self.users.get_by_email(email) is not None:
            raise AuthError("Email already registered")
        user = User(
            email=email,
            password_hash=hash_password(payload.password),
            display_name=payload.display_name,
            country_of_origin=payload.country_of_origin,
            city_of_origin=payload.city_of_origin,
            user_type=payload.user_type,
            traveler_type="mixed",
            nationality=payload.nationality,
            age_range=payload.age_range,
            accepted_research_consent=payload.accepted_research_consent,
            accepted_privacy_terms_at=(
                datetime.now(timezone.utc)  # noqa: UP017
                if payload.accepted_research_consent
                else None
            ),
        )
        apply_user_type_to_user(user)
        self.users.create(user)
        self.db.commit()
        self.db.refresh(user)
        return self._token_for(user)

    def login(self, payload: LoginRequest) -> TokenResponse:
        user = self.users.get_by_email(payload.email.lower())
        if user is None or not verify_password(payload.password, user.password_hash):
            raise AuthError("Invalid email or password")
        if not user.is_active:
            raise AuthError("Account disabled")
        return self._token_for(user)

    def _token_for(self, user: User) -> TokenResponse:
        token = create_access_token(user.id, extra_claims={"email": user.email})
        return TokenResponse(
            access_token=token,
            token_type="bearer",
            user=UserPublic.model_validate(user),
        )
