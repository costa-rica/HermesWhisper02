# HermesWhisper02 API

## Project Overview

The HermesWhisper02 API is a FastAPI backend for real-time voice sessions between the iOS client and the Hermes AI Agent. It uses Pipecat-shaped voice pipeline components, SQLite persistence, Loguru logging, JWT auth, email-code login, and OpenAI STT/TTS/front-LLM provider boundaries.

## Setup

1. Install `uv`.

```bash
brew install uv
```

2. Install dependencies.

```bash
cd api
uv sync
```

3. Create local configuration.

```bash
cp .env.example .env
```

4. Fill in local secrets in `.env`.
   - `JWT_SECRET` is required.
   - `OPENAI_API_KEY` is required for OpenAI smoke tests and real OpenAI provider use.
   - Keep `HERMES_MOCK=true` on Mac development machines.

5. Seed the first user when you need auth login locally.

```bash
uv run python scripts/seed_user.py
```

## Usage

1. Run the API server.

```bash
uv run uvicorn app.main:app --host 127.0.0.1 --port 8765
```

2. Or use the helper script.

```bash
./scripts/run_dev.sh
```

3. Check health.

```bash
curl http://127.0.0.1:8765/api/health
```

4. Check server info.

```bash
curl http://127.0.0.1:8765/api/server/info
```

5. Login flow.
   - `POST /api/auth/login` with email and password.
   - `POST /api/auth/verify` with email and 6-digit code.
   - Use the returned bearer token for `Authorization: Bearer <token>`.

6. Voice WebSocket.
   - URL: `ws://127.0.0.1:8765/ws/voice`.
   - Auth: `Authorization: Bearer <token>`.
   - First frame must be `client_hello` per `docs/20260510_PROTOCOL_V01.md`.

## Testing

1. Run the normal test suite.

```bash
uv run pytest
```

2. Run lint.

```bash
uv run ruff check
```

3. Run format check.

```bash
uv run ruff format --check
```

4. Run all phase-level checks together.

```bash
uv run pytest
uv run ruff check
uv run ruff format --check
```

5. Run the gated OpenAI smoke test.

```bash
RUN_OPENAI_SMOKE=1 uv run dotenv run -- pytest tests/test_pipeline_openai_smoke.py -q
```

6. Notes.
   - Normal tests do not require OpenAI credentials.
   - The OpenAI smoke test requires `OPENAI_API_KEY`.
   - Tests that call external services are marked `integration`.

## Project Structure

```text
api/
├── app/
│   ├── main.py                    # FastAPI app factory
│   ├── config.py                  # Pydantic settings
│   ├── db.py                      # SQLite bootstrap and helpers
│   ├── errors.py                  # Standard API error envelope
│   ├── auth.py                    # Bearer-token user dependency
│   ├── routes/
│   │   ├── health.py              # GET /api/health
│   │   ├── mobile_auth.py         # Login and verify routes
│   │   ├── server_info.py         # GET /api/server/info
│   │   └── voice_ws.py            # WS /ws/voice
│   ├── services/
│   │   ├── pipeline.py            # Mock voice pipeline
│   │   ├── front_llm.py           # Front answer path
│   │   ├── hermes.py              # Hermes tool client
│   │   ├── stt.py                 # STT provider factory
│   │   ├── tts.py                 # TTS provider factory
│   │   └── voice_store.py         # Session/message persistence
│   └── pipecat_processors/
│       ├── ack_processor.py       # Deterministic ack processor
│       ├── mocks.py               # Mock STT/TTS components
│       └── ws_transport_adapter.py
├── tests/
├── scripts/
│   ├── run_dev.sh
│   └── seed_user.py
├── .env.example
├── pyproject.toml
└── uv.lock
```

## .env

```env
NAME_APP=hermes-whisper-02-api
RUN_ENVIRONMENT=development
PATH_TO_LOGS=./logs
LOG_MAX_SIZE_IN_MB=3
LOG_MAX_FILES=3

API_HOST=127.0.0.1
API_PORT=8765
PUBLIC_BASE_URL=https://api.hermes-whisper.dashanddata.com

FRONT_LLM_PROVIDER=openai
FRONT_LLM_MODEL=gpt-4o-mini
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OLLAMA_BASE_URL=http://127.0.0.1:11434

STT_PROVIDER=mock
STT_MODEL=gpt-4o-mini-transcribe
TTS_PROVIDER=mock
TTS_MODEL=tts-1
TTS_VOICE=alloy

HERMES_BASE_URL=http://127.0.0.1:8642
HERMES_CHAT_PATH=/v1/chat/completions
HERMES_MODEL=hermes-agent
HERMES_API_KEY=
HERMES_MOCK=true

DB_PATH=./var/voice_store.sqlite
JWT_SECRET=
TOKEN_TTL_SECONDS=2592000
SESSION_RESUME_WINDOW_SEC=300

EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USER=nrodrig1@gmail.com
EMAIL_PASSWORD=
EMAIL_FROM=HermesWhisper <nrodrig1@gmail.com>
EMAIL_DEV_CONSOLE_ONLY=true

WS_QUERY_TOKEN_FALLBACK_ENABLED=false
```

## References

- [API plan](../docs/20260510_PLAN_API_V01.md)
- [Protocol v1](../docs/20260510_PROTOCOL_V01.md)
- [Requirements](../docs/20260510_REQUIREMENTS.md)
- [API errors](../docs/ERROR_REQUIREMENTS.md)
- [Python logging](../docs/LOGGING_PYTHON_V06.md)
- [TODO guidance](../docs/TODO_LIST_GUIDANCE.md)
- [Commit message guidance](../docs/CommitMessagesGuidance.md)
