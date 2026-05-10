.PHONY: dev test lint format-check

dev:
	uv run uvicorn app.main:app --host $${API_HOST:-127.0.0.1} --port $${API_PORT:-8765}

test:
	uv run pytest

lint:
	uv run ruff check

format-check:
	uv run ruff format --check
