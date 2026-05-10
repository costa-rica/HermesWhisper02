#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
exec uv run uvicorn app.main:app --host "${API_HOST:-127.0.0.1}" --port "${API_PORT:-8765}"
