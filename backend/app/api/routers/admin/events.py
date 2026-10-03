from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import verify_admin_token
from app.core.database import get_db
from app.services.admin_events import subscribe

router = APIRouter(prefix="/events", tags=["admin"])


@router.get("")
async def admin_event_stream(
    token: str = Query(..., description="JWT for EventSource (cannot send Authorization header)"),
    db: Session = Depends(get_db),
) -> StreamingResponse:
    verify_admin_token(token, db)

    async def generate():
        queue: asyncio.Queue[str] = asyncio.Queue(maxsize=128)
        loop = asyncio.get_running_loop()

        def push(data: str) -> None:
            loop.call_soon_threadsafe(queue.put_nowait, data)

        unsubscribe = subscribe(push)
        try:
            yield f"data: {json.dumps({'type': 'connected'})}\n\n"
            while True:
                try:
                    data = await asyncio.wait_for(queue.get(), timeout=25.0)
                    yield f"data: {data}\n\n"
                except asyncio.TimeoutError:
                    yield ": keepalive\n\n"
        finally:
            unsubscribe()

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
