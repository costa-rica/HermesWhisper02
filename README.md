# HermesWhisper02

## Project Overview

HermesWhisper02 is a Swift iOS and FastAPI monorepo for real-time voice access to the Hermes AI Agent (https://hermes-agent.nousresearch.com/). The API uses FastAPI, Pipecat, SQLite, Loguru, and OpenAI providers; the mobile app uses SwiftUI, AVFoundation, URLSession WebSockets, and Keychain-backed per-server auth.

## Setup

1. Install shared tooling.
   - Install `uv`: `brew install uv`.
   - Install `xcodegen`: `brew install xcodegen`.
   - Use Xcode with iOS 17 or newer simulator support.

2. Set up the API.
   - Go to `api/`: `cd api`.
   - Sync dependencies: `uv sync`.
   - Create local config from the example: `cp .env.example .env`.
   - Fill in local secrets in `.env`.
   - Run tests: `uv run pytest`.

3. Set up the iOS project.
   - Go to `mobile/ios/HermesWhisper02/`.
   - Generate the Xcode project: `xcodegen generate`.
   - List schemes: `xcodebuild -list -project HermesWhisper02.xcodeproj`.
   - Run tests with `xcodebuild test` after the local Xcode toolchain is healthy.

## Usage

1. Run the API locally.

```bash
cd api
uv run uvicorn app.main:app --host 127.0.0.1 --port 8765
```

2. Check health.

```bash
curl http://127.0.0.1:8765/api/health
```

3. Open the iOS app.
   - Open `mobile/ios/HermesWhisper02/HermesWhisper02.xcodeproj` in Xcode.
   - Select the `HermesWhisper02` scheme.
   - Run on an iOS 17 or newer simulator.

4. Current implementation status.
   - API phases 0 through 6b are implemented and committed.
   - Mobile phase 0 scaffold is committed.
   - Mobile `xcodebuild` verification is blocked on this workstation by local Xcode toolchain failures, not project code.

## Project Structure

```text
HermesWhisper02/
├── api/
│   ├── app/
│   │   ├── main.py                  # FastAPI app factory and router wiring
│   │   ├── config.py                # Pydantic settings and env validation
│   │   ├── db.py                    # SQLite bootstrap and access helpers
│   │   ├── errors.py                # API error envelope
│   │   ├── routes/
│   │   │   ├── health.py            # GET /api/health
│   │   │   ├── mobile_auth.py       # POST /api/auth/login and /verify
│   │   │   ├── server_info.py       # GET /api/server/info
│   │   │   └── voice_ws.py          # WS /ws/voice
│   │   ├── services/
│   │   │   ├── pipeline.py          # Mock voice pipeline
│   │   │   ├── front_llm.py         # Front answer path
│   │   │   ├── hermes.py            # Hermes tool client
│   │   │   ├── stt.py               # STT provider factory
│   │   │   └── tts.py               # TTS provider factory
│   │   └── pipecat_processors/
│   │       ├── ack_processor.py     # Deterministic ack processor
│   │       └── ws_transport_adapter.py
│   ├── tests/
│   ├── pyproject.toml
│   └── uv.lock
├── mobile/
│   └── ios/
│       └── HermesWhisper02/
│           ├── HermesWhisper02.xcodeproj/
│           ├── HermesWhisper02/
│           │   ├── App/
│           │   ├── Auth/
│           │   ├── ServerRegistry/
│           │   ├── Voice/
│           │   ├── Models/
│           │   └── Util/
│           ├── HermesWhisper02Tests/
│           └── project.yml
├── docs/
│   ├── 20260510_REQUIREMENTS.md
│   ├── 20260510_PROTOCOL_V01.md
│   ├── 20260510_PLAN_API_V01.md
│   └── 20260510_PLAN_MOBILE_V01.md
├── AGENTS.md
└── README.md
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

- [Requirements](docs/20260510_REQUIREMENTS.md)
- [Protocol v1](docs/20260510_PROTOCOL_V01.md)
- [API plan](docs/20260510_PLAN_API_V01.md)
- [Mobile plan](docs/20260510_PLAN_MOBILE_V01.md)
- [API errors](docs/ERROR_REQUIREMENTS.md)
- [Python logging](docs/LOGGING_PYTHON_V06.md)
- [TODO guidance](docs/TODO_LIST_GUIDANCE.md)
- [Commit message guidance](docs/CommitMessagesGuidance.md)
- [README format](docs/README_FORMAT.md)
