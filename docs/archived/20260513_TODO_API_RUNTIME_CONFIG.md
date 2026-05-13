# TODO API: Runtime Intermediary, VAD Params, Long-Gap Resume

Date: 2026-05-13
Anchor: docs/20260513_REQUIREMENTS_UI_HISTORY.md
Pairs with: docs/20260513_TODO_MOBILE_UI_HISTORY.md

Conventions:

- Run all commands from `api/` using `uv` per api/AGENTS.md.
- Use Loguru only; no PII or secrets in logs.
- Error shapes follow docs/ERROR_REQUIREMENTS.md.

## Phase 1 — Protocol additions

Tasks:

- [ ] Edit docs/20260510_PROTOCOL_V01.md as its own commit before any server changes (per root AGENTS.md "Protocol" rules).
- [ ] Add to `client_hello`:
  - `intermediary_mode`: optional, `"deterministic"` or `"llm"`. Default `"llm"`.
  - `audio_params`: optional object with any subset of `speech_rms_threshold`, `end_silence_seconds`, `min_turn_seconds`, `max_turn_seconds`.
- [ ] New client to server frames:
  - `set_intermediary_mode { mode }`
  - `set_audio_params { speech_rms_threshold?, end_silence_seconds?, min_turn_seconds?, max_turn_seconds? }`
- [ ] New server to client frame:
  - `runtime_config_applied { fields: [...], values: { ... } }` echoed after a successful apply.
- [ ] Document semantics: applied at the next transcript boundary, never mid-turn; out-of-range values clamped to the ranges in the requirements doc.
- [ ] Bump only the protocol doc; `protocol_version` stays at 1 since the changes are additive.

Commit: `docs: protocol additions for runtime config (20260513_TODO_API_RUNTIME_CONFIG phase 1)`.

## Phase 2 — Per-session runtime config

Tasks:

- [ ] Add `app/services/session_runtime_config.py` with a dataclass:
  - `intermediary_mode: Literal["deterministic","llm"] = "llm"`
  - `speech_rms_threshold: float = 0.003`
  - `end_silence_seconds: float = 1.1`
  - `min_turn_seconds: float = 0.8`
  - `max_turn_seconds: float = 8.0`
  - Method `apply_partial(updates: dict) -> dict` returning the clamped fields and values.
- [ ] In `app/routes/voice_ws.py`:
  - [ ] Replace module-level constants MIN_TURN_SECONDS, MAX_TURN_SECONDS, END_SILENCE_SECONDS, SPEECH_RMS_THRESHOLD with reads from the per-connection `SessionRuntimeConfig` instance.
  - [ ] Pass the config object into `AudioTurnSegmenter` so each frame reads live values; new values take effect at the next silence boundary.
  - [ ] On `client_hello`, populate the config from `intermediary_mode` and `audio_params` if present (clamped).
- [ ] In `app/services/front_llm.py`:
  - [ ] `answer()` accepts the runtime config (or just the mode) and short-circuits to the ack-only path when `intermediary_mode == "deterministic"`, never calling Hermes.

Tests:

- [ ] `tests/test_runtime_config.py` covers clamping and dataclass apply.
- [ ] `tests/test_voice_ws_runtime.py` covers `client_hello` overrides being honored on the first turn.

Checks before checking off:

- [ ] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): per-session runtime config (20260513_TODO_API_RUNTIME_CONFIG phase 2)`.

## Phase 3 — Live frame handlers

Tasks:

- [ ] Extend the client-message dispatch in `voice_ws.py` to handle:
  - `set_intermediary_mode` → updates `config.intermediary_mode`, emits `runtime_config_applied`.
  - `set_audio_params` → updates the four fields, emits `runtime_config_applied` with the clamped values.
- [ ] Log at INFO when a runtime parameter changes, using Loguru. No PII; include `session_id` and the changed field names only.
- [ ] Use the shared `APIError` and error handlers from `app/errors.py` for malformed payloads.

Tests:

- [ ] `tests/test_voice_ws_runtime.py` adds cases for mid-conversation switch frames and out-of-range clamping.
- [ ] Assert `runtime_config_applied` contents match clamped values.

Checks before checking off:

- [ ] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): live runtime config frames (20260513_TODO_API_RUNTIME_CONFIG phase 3)`.

## Phase 4 — Tests sweep and logging audit

Tasks:

- [ ] Add an integration-style test that walks: `client_hello` (deterministic) → turn 1 (no Hermes call) → `set_intermediary_mode { llm }` → turn 2 (Hermes called via mock).
- [ ] Confirm stage timings are still logged per `docs/LOGGING_PYTHON_V06.md`.
- [ ] Confirm `runtime_config_applied` is never emitted mid-turn.

Checks before checking off:

- [ ] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `test(api): runtime config integration (20260513_TODO_API_RUNTIME_CONFIG phase 4)`.

## Phase 5 — Operator notes

Tasks:

- [ ] Append a short "Operator notes" section to this TODO file describing the new frames and how to toggle them with a manual WS client.
- [ ] Add the new env knob from phase 6 (`LONG_RESUME_MAX_MESSAGES`) to `api/.env.example` once phase 6 lands.

Commit: `docs(api): operator notes for runtime config (20260513_TODO_API_RUNTIME_CONFIG phase 5)`.

## Phase 6 — Long-gap session resume

Tasks:

- [ ] Add `LONG_RESUME_MAX_MESSAGES: int = 50` to `app/config.py` and `api/.env.example`.
- [ ] In `voice_ws.py`, on `client_hello.session_id`:
  - [ ] Try the existing in-memory resume path first.
  - [ ] If not present, fetch the session row from `voice_sessions` (`db.py` / `voice_store.py`) and verify `owner_id` matches the authenticated principal. Return an `APIError` if it does not.
  - [ ] Load the last `LONG_RESUME_MAX_MESSAGES` rows from `voice_messages` ordered by `created_at DESC`, reverse to chronological, and seed a fresh `front_llm` context with them and the stored `conversation_id`.
  - [ ] Respond with `session_started { resumed: true }` and the original `conversation_id`.
- [ ] If the row is missing, respond with `session_started { resumed: false, created: true }` and a new session as today.

Tests:

- [ ] `tests/test_voice_ws_long_resume.py`:
  - [ ] Cold resume past the 5-minute window returns `resumed: true` with the original `conversation_id`.
  - [ ] Subsequent mocked Hermes call sees the prior context in the front_llm.
  - [ ] Ownership mismatch returns the documented error code.
  - [ ] Missing session falls back to a brand new one.

Checks before checking off:

- [ ] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): long-gap session resume from DB (20260513_TODO_API_RUNTIME_CONFIG phase 6)`.

## Critical files

Modified:

- docs/20260510_PROTOCOL_V01.md (phase 1, own commit)
- api/app/routes/voice_ws.py
- api/app/services/front_llm.py
- api/app/config.py
- api/.env.example

Added:

- api/app/services/session_runtime_config.py
- api/tests/test_runtime_config.py
- api/tests/test_voice_ws_runtime.py
- api/tests/test_voice_ws_long_resume.py

Reused:

- api/app/services/voice_store.py (sessions and messages tables; existing helpers for list and read)
- api/app/db.py (connection helper)
- api/app/errors.py (APIError shape)

## Operator notes (placeholder — fill in after phase 3)

- Sending `set_intermediary_mode` mid-conversation:
  - example payload, manual `wscat` invocation, and what to expect in the ack frame.
- Sending `set_audio_params` mid-conversation:
  - example payload and the clamped echo behavior.
- Triggering a long-gap resume:
  - reconnect after >5 minutes with the prior `session_id`, expect `resumed: true`.
