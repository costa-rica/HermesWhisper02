# API agent instructions

## Scope

- Applies to files under `api/`.
- Follow the root `AGENTS.md` plus these API-specific rules.

## Tooling

- Use `uv` for dependency management and command execution.
- Run API commands from `api/`.
- Use Python `>=3.12,<3.14`.
- Keep `pyproject.toml` and `uv.lock` in sync after dependency changes.

## Commands

1. Run tests: `uv run pytest`.
2. Run lint: `uv run ruff check`.
3. Run format check: `uv run ruff format --check`.
4. Run the dev server: `uv run uvicorn app.main:app --host 127.0.0.1 --port 8765`.

## FastAPI conventions

- Keep route modules in `app/routes/`.
- Keep service boundaries in `app/services/`.
- Keep custom Pipecat processors and transport adapters in `app/pipecat_processors/`.
- Use the shared `APIError` and error handlers from `app/errors.py`.
- All API errors must match `docs/ERROR_REQUIREMENTS.md`.

## Logging

- Use Loguru only.
- Keep logging setup centralized in `app/logging_config.py`.
- Follow `docs/LOGGING_PYTHON_V06.md`.
- Log stage timings for voice pipeline work without logging PII or secrets.

## Configuration

- Add every app-read environment variable to `api/.env.example`.
- Keep required startup settings in `app/config.py`.
- Missing required logging/config variables should fail fast and name the variable.

## Voice pipeline

- Pin Pipecat versions in `pyproject.toml`.
- Confirm Pipecat class names against the installed version before using them.
- Keep Hermes mocked on Mac with `HERMES_MOCK=true`.
- Live Hermes integration is Ubuntu-only unless the user says otherwise.

## Persistence

- Use SQLite through `app/db.py`.
- Preserve WAL, busy timeout, and serialized-write behavior.
- Persist only completed voice turns when implementing resume behavior.
