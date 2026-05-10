from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException


class ErrorBody(BaseModel):
    code: str
    message: str
    status: int
    details: Any = None


class ErrorEnvelope(BaseModel):
    error: ErrorBody


class APIError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        status: int = 500,
        details: Any = None,
    ) -> None:
        self.code = code
        self.message = message
        self.status = status
        self.details = details


def error_response(error: APIError) -> JSONResponse:
    envelope = ErrorEnvelope(
        error=ErrorBody(
            code=error.code,
            message=error.message,
            status=error.status,
            details=error.details,
        )
    )
    return JSONResponse(status_code=error.status, content=envelope.model_dump())


async def api_error_handler(_request: Request, exc: APIError) -> JSONResponse:
    return error_response(exc)


async def validation_error_handler(_request: Request, exc: RequestValidationError) -> JSONResponse:
    return error_response(
        APIError(
            code="VALIDATION_ERROR",
            message="Request validation failed",
            status=400,
            details=exc.errors(),
        )
    )


async def http_error_handler(_request: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = "NOT_FOUND" if exc.status_code == 404 else "INTERNAL_ERROR"
    if exc.status_code in {401, 403}:
        code = "AUTH_FAILED" if exc.status_code == 401 else "FORBIDDEN"
    return error_response(APIError(code=code, message=str(exc.detail), status=exc.status_code))


def install_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(APIError, api_error_handler)
    app.add_exception_handler(RequestValidationError, validation_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_error_handler)
