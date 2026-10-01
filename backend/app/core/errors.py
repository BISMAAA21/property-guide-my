from collections.abc import Mapping
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field


class ErrorResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    code: str
    message: str
    request_id: str = Field(alias="requestId")
    field_errors: Mapping[str, str] | None = Field(default=None, alias="fieldErrors")


class ApiError(Exception):
    def __init__(
        self,
        *,
        status_code: int,
        code: str,
        message: str,
        field_errors: Mapping[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.field_errors = field_errors


def _request_id(request: Request) -> str:
    existing = getattr(request.state, "request_id", None)
    return existing if isinstance(existing, str) else str(uuid4())


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(request: Request, error: ApiError) -> JSONResponse:
        payload = ErrorResponse(
            code=error.code,
            message=error.message,
            requestId=_request_id(request),
            fieldErrors=error.field_errors,
        )
        return JSONResponse(
            status_code=error.status_code,
            content=payload.model_dump(by_alias=True),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, _error: Exception) -> JSONResponse:
        payload: dict[str, Any] = ErrorResponse(
            code="INTERNAL_ERROR",
            message="The service could not complete the request.",
            requestId=_request_id(request),
        ).model_dump(by_alias=True)
        return JSONResponse(status_code=500, content=payload)
