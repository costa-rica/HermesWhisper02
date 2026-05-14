# CTO onboarding

## 1. One-paragraph summary

HermesWhisper02 is a Swift iOS plus FastAPI monorepo for a real-time voice client in front of a Hermes AI Agent. The iOS app is intended to capture microphone audio, stream PCM over WebSocket, receive TTS audio, and manage per-server auth; current mobile code is mostly scaffolded placeholders (see `mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceView.swift`). The API implements health, server info, email-code auth, SQLite persistence, a WebSocket protocol envelope, and a mocked voice pipeline with deterministic acknowledgments and Hermes-as-tool behavior (see `api/app/routes/voice_ws.py`, `api/app/services/pipeline.py`). The Swift/FastAPI protocol is version 1 and is the cross-track source of truth (see `docs/20260510_PROTOCOL_V01.md`).

## 2. Tech stack

- Languages and versions:
  - Python `>=3.12,<3.14` for the API (see `api/pyproject.toml`).
  - Swift / SwiftUI targeting iOS 17 (see `mobile/ios/HermesWhisper02/project.yml`).
- API framework and key libraries:
  - FastAPI and Uvicorn for HTTP/WebSocket serving.
  - Pipecat pinned as `pipecat-ai[openai,silero]~=0.0.108`, currently wrapped by local mock/adaptor classes rather than a full production Pipecat runtime path.
  - Pydantic settings, Loguru, PyJWT, HTTPX, aiosqlite, python-dotenv (see `api/pyproject.toml`).
- Mobile frameworks:
  - SwiftUI, Foundation, OSLog now; planned AVFoundation, Security, Network/URLSession WebSockets (see `docs/20260510_PLAN_MOBILE_V01.md` and scaffold files under `mobile/ios/HermesWhisper02/HermesWhisper02/`).
- Database and storage:
  - SQLite at `DB_PATH`, bootstrapped directly from `api/app/db.py`; no migrations framework exists.
  - Mobile server registry is planned for Application Support JSON; credentials are planned for Keychain (see `mobile/AGENTS.md`).
- Runtime / deployment target:
  - Local API runs with `uv run uvicorn app.main:app --host 127.0.0.1 --port 8765`.
  - Planned production target is `fsdc-avatar08` behind `Maestro04` Nginx, but deployment artifacts are not present yet (see `docs/20260510_PLAN_API_V01.md`).

## 3. Repository layout

```text
.
|-- api/       FastAPI backend, SQLite schema, auth, voice WS route, service layer, tests.
|-- docs/      Requirements, protocol, API/mobile phase plans, logging/error guidance.
|-- mobile/    iOS SwiftUI app scaffold and XcodeGen project config.
|-- AGENTS.md  Repo-wide agent and workflow instructions.
|-- CLAUDE.md  Pointer to AGENTS.md.
`-- README.md  Setup, current status, env example, and high-level project tree.
```

Read first:

- `docs/20260510_PROTOCOL_V01.md`: Swift-to-API contract.
- `api/app/routes/voice_ws.py`: current WebSocket lifecycle and protocol handling.
- `api/app/services/pipeline.py`: current mocked ack/answer voice pipeline.
- `api/app/db.py`: complete current SQLite schema.
- `docs/20260510_PLAN_API_V01.md` and `docs/20260510_PLAN_MOBILE_V01.md`: implemented vs planned phase boundaries.

## 4. Architecture

```text
iOS SwiftUI app
  planned: mic PCM16 frames + bearer token
        |
        | WSS /ws/voice, protocol_version=1
        v
FastAPI API
  routes: /api/health, /api/server/info, /api/auth/login, /api/auth/verify, /ws/voice
        |
        +--> SQLite: users, email codes, voice sessions/messages, turn state
        |
        +--> voice pipeline: mock STT -> deterministic ack -> front answer processor -> mock/OpenAI TTS shape
                 |
                 +--> Hermes tool client, mocked locally or POST/stream to HERMES_BASE_URL
```

Requests enter through `app.main:create_app`, which installs error handlers and mounts route modules (see `api/app/main.py`). REST auth is email/password to a six-digit email code, then an HS256 bearer JWT (see `api/app/routes/mobile_auth.py`, `api/app/services/tokens.py`). Voice sessions start with an authenticated WebSocket, a required `client_hello`, then `session_started`; binary client frames are interpreted as 16 kHz mono PCM, and after one second of buffered audio the current implementation emits a mocked transcript, ack audio, answer audio, `turn_end`, and `idle` (see `api/app/routes/voice_ws.py`). The documented target architecture is Pipecat transport -> VAD -> STT -> context -> deterministic ack plus front LLM -> TTS -> transport, but the production-grade Pipecat pipeline and mobile audio path are not complete (see `docs/20260510_REQUIREMENTS.md`, `api/app/services/pipeline.py`).

State lives in SQLite on the API. Mobile state is currently an in-memory `AppEnvironment`; planned registry and Keychain files are mostly empty placeholders (see `mobile/ios/HermesWhisper02/HermesWhisper02/App/AppEnvironment.swift`, `ServerRegistryStore.swift`, `KeychainStore.swift`). There are no implemented background workers or queues. Async work is request-local: FastAPI async routes, SQLite access, HTTPX streaming for Hermes, and WebSocket loops.

## 5. Data model

- `users`: login principals with `id`, unique `email`, `password_hash`, `created_at`; used by auth and WebSocket token validation (see `api/app/db.py`, `api/app/routes/mobile_auth.py`).
- `email_codes`: one active 2FA code per email with expiration; replaced on every login attempt and deleted after successful verify.
- `voice_sessions`: session identity owned by a user, plus `conversation_id`; used for WebSocket session start/resume.
- `voice_messages`: persisted conversation messages by session and role (`user`, `assistant`, `system`); service helpers exist, but the live WebSocket path does not yet persist completed turns.
- `turn_state`: planned idempotency/latency state for ack/answer turn lifecycle; table exists, phase-7 behavior is not implemented (see `docs/20260510_PLAN_API_V01.md`).
- Mobile `ServerProfile`: Codable model with `id`, `displayName`, `baseURL`, optional `notes`, and `authKind`; storage is not implemented yet (see `mobile/ios/HermesWhisper02/HermesWhisper02/ServerRegistry/ServerProfile.swift`).
- `TokenClaims`: JWT payload model with `sub`, `email`, `exp` (see `api/app/models.py`).

There is no migrations folder. Schema changes are currently made by editing the `SCHEMA` string in `api/app/db.py`, so migration/upgrade behavior for existing production data is undefined.

## 6. External integrations

- OpenAI:
  - Used for planned/runtime STT, TTS, and front LLM service factories.
  - Auth uses `OPENAI_API_KEY` from API environment settings.
  - Factories are in `api/app/services/stt.py`, `api/app/services/tts.py`, and `api/app/services/front_llm.py`.
- Anthropic and Ollama:
  - Config fields exist (`ANTHROPIC_API_KEY`, `OLLAMA_BASE_URL`), but current code only builds an OpenAI front LLM service and rejects non-OpenAI providers (see `api/app/config.py`, `api/app/services/front_llm.py`).
- Hermes AI Agent:
  - Used as the answer tool for substantive requests.
  - Local default is mocked with `HERMES_MOCK=true`; non-mock mode posts to `${HERMES_BASE_URL}/chat` without an auth mechanism in this repo (see `api/app/services/hermes.py`).
- SMTP / Gmail:
  - Used to send login codes outside dev-console mode.
  - Credentials come from `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USER`, `EMAIL_PASSWORD`, `EMAIL_FROM`, `EMAIL_DEV_CONSOLE_ONLY` (see `api/app/services/mailer.py`, `api/.env.example`).
- iOS Keychain:
  - Planned for per-server bearer credentials; `KeychainStore.swift` is still empty.

## 7. Running it locally

Prerequisites:

- `uv` for the API.
- Xcode with iOS 17 simulator support and `xcodegen` for the iOS project.

API:

1. `cd api`
2. `uv sync`
3. `cp .env.example .env`
4. Set at least `JWT_SECRET`; set `OPENAI_API_KEY` only for OpenAI/integration smoke paths.
5. `uv run pytest`
6. `uv run uvicorn app.main:app --host 127.0.0.1 --port 8765`
7. `curl http://127.0.0.1:8765/api/health`

Seed a local user with `uv run python scripts/seed_user.py` from `api/` after configuring `.env` (see `api/scripts/seed_user.py`). Development auth logs 2FA codes through Loguru when `EMAIL_DEV_CONSOLE_ONLY=true`; do not use that setting as a production assumption.

iOS:

1. `cd mobile/ios/HermesWhisper02`
2. `xcodegen generate`
3. `xcodebuild -list -project HermesWhisper02.xcodeproj`
4. Open the generated project or run the build/test commands from `mobile/AGENTS.md`.

Gotchas: the README says mobile `xcodebuild` verification was blocked on this workstation by local Xcode toolchain failures, not project code; the current app is a placeholder; API WebSockets require a bearer token and `client_hello` (see `README.md`, `api/app/routes/voice_ws.py`).

## 8. Deployment

There is no implemented deployment surface in the repository: no Dockerfile, CI config, deploy directory, systemd unit, or Nginx config was found. The documented deployment plan is a `uv`-run FastAPI service on `fsdc-avatar08`, bound to `127.0.0.1:8765`, with TLS/WebSocket proxying through `Maestro04` Nginx and secrets in `/etc/hermes-whisper-02/env` (see `docs/20260510_PLAN_API_V01.md`). Rollback is not documented. Mobile distribution is documented as local-install via Xcode for v1; TestFlight is deferred (see `docs/20260510_PLAN_MOBILE_V01.md`).

## 9. Testing

API tests under `api/tests/` cover health, auth, tokens, mailer dev mode, server info, voice store CRUD, WebSocket protocol behavior, ack processing, mock front answers, and OpenAI factory wiring. Run `cd api && uv run pytest`; run lint/format with `uv run ruff check` and `uv run ruff format --check` (see `api/AGENTS.md`). The OpenAI smoke test is marked `integration` and skipped unless `OPENAI_API_KEY` and `RUN_OPENAI_SMOKE=1` are set (see `api/tests/test_pipeline_openai_smoke.py`).

Mobile testing has only `SanityTests.swift` plus placeholder UI test scaffolding. The mobile plan calls for XCTest coverage of registry, Keychain, protocol envelope, audio capture, WebSocket behavior, playback, and barge-in, but those implementations are not present yet (see `docs/20260510_PLAN_MOBILE_V01.md`).

## 10. Active areas of work

- API phases 0 through 6b appear implemented in source and checked in plan boxes; phase 7 persistence/resume, phase 9 live Hermes integration, and phase 10 deployment artifacts remain open (see `docs/20260510_PLAN_API_V01.md`).
- The API pipeline is still mocked: `/ws/voice` calls `build_pipeline()` without settings and processes one-second audio buffers through `MockVoicePipeline` (see `api/app/routes/voice_ws.py`, `api/app/services/pipeline.py`).
- Mobile is at scaffold/placeholder maturity despite phase files existing; registry, auth, audio, playback, WebSocket, and protocol files mostly contain empty structs/classes (see `mobile/ios/HermesWhisper02/HermesWhisper02/`).
- Deployment and operational hardening are planned but absent from the tree.
- Git history in this checkout contains only one visible commit, so active work is better inferred from plan checkboxes and TODO markers than from commit trends (`git log --oneline -30`).

## 11. Open questions for the project owner

- What is the authoritative Hermes `/chat` streaming contract, including request/response shape, error semantics, timeouts, and authentication if any? The repo currently assumes unauthenticated POST streaming to `${HERMES_BASE_URL}/chat`.
- Should SQLite schema evolution be handled by a migrations tool before production, or is destructive bootstrap acceptable for v1?
- What is the expected production rollback process for API and mobile releases? No CI/CD, deploy scripts, or rollback docs are present.
- Is `fsdc-avatar08` still the only production target, and what are the exact internal IP, system user, log path, DB path, and Nginx host responsibilities?
- Should Anthropic/Ollama remain documented as supported front LLM providers when current code rejects them?
- What acceptance threshold decides whether the current serial ack/answer pipeline is sufficient or whether phase 8 `ParallelPipeline` work must happen?
- Who owns mobile signing, device testing, and TestFlight timing? Current docs defer TestFlight and note local Xcode verification problems.
