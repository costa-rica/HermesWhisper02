# TODO API V02: Hermes Session Propagation, Assistant Text, Runtime Config, Long-Gap Resume

Date: 2026-05-13
Supersedes: docs/archived/20260513_TODO_API_RUNTIME_CONFIG.md
Triggered by: docs/archived/20260513_TODO_API_RUNTIME_CONFIG_ASSESSMENT_CODEX.md
Anchor: docs/20260513_REQUIREMENTS_UI_HISTORY_V02.md
Pairs with: docs/20260513_TODO_MOBILE_UI_HISTORY_V02.md
Related: docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md

Conventions:

- Run all commands from `api/` using `uv` per api/AGENTS.md.
- Use Loguru only; no PII or secrets in logs.
- Error shapes follow docs/ERROR_REQUIREMENTS.md.

## Changes from V01

- Re-ordered the phases so Hermes session propagation and `assistant_text` ship before long-gap resume.
- Redefined deterministic mode as deterministic routing direct to Hermes, not ack-only.
- Added explicit voice_store methods (`get_session_for_owner`, `list_recent_messages`).
- Documented that runtime frames apply at the next turn boundary because the WS loop is not reading text during active turns.

## Phase 1 — Protocol additions (own commit)

Edit docs/20260510_PROTOCOL_V01.md before any server changes (per root AGENTS.md "Protocol" rules).

Tasks:

- [x] Add to `client_hello`:
  - `intermediary_mode`: `"deterministic"` or `"llm"`. Default `"llm"`.
  - `audio_params`: optional object with any subset of `speech_rms_threshold`, `end_silence_seconds`, `min_turn_seconds`, `max_turn_seconds`.
- [x] New client to server frames:
  - `set_intermediary_mode { mode }`
  - `set_audio_params { ... }`
- [x] New server to client frames:
  - `assistant_text { turn_id, text, final, ts }` emitted after Hermes streaming finishes with the assembled final answer text.
  - `runtime_config_applied { fields: [...], values: { ... } }`.
- [x] Document semantics:
  - All runtime applies happen at the next turn boundary, not mid-turn.
  - Out-of-range values are clamped; the ack carries the clamped values.
  - `deterministic` routes substantive transcripts directly to Hermes, bypassing the front-LLM router.
  - `llm` keeps the existing front-LLM router behavior.
- [x] `protocol_version` remains 1 (additive only).

Commit: `docs: protocol additions for runtime config and assistant_text (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 1)`.

## Phase 2 — Hermes session propagation

Required before any long-gap resume work.

Tasks:

- [x] Resolve docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md. Pick a contract: `/responses` with `conversation`, header (`X-Hermes-Session-Id` or `X-Hermes-Session-Key`), or chat-completions extension.
- [x] Update docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md with the chosen approach as its own commit.
- [ ] Implement in api/app/services/hermes.py:
  - [x] Add the identifier to the outgoing request body and/or headers per the chosen contract.
  - [x] Keep `HERMES_MOCK=true` path intact for Mac dev.
- [x] Add `tests/test_hermes_session_propagation.py`:
  - [x] Mock the httpx call; assert the outgoing request contains the identifier in the agreed location.
  - [x] Mocked mode still works (no live HTTP).

Checks before checking off:

- [x] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): propagate Hermes session id on every request (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 2)`.

## Phase 3 — Emit assistant_text frame

Tasks:

- [x] In api/app/services/front_llm.py (or its caller in voice_ws.py), accumulate the streamed Hermes deltas into a final answer string.
- [x] After Hermes finishes (and before `turn_end`), send `assistant_text { turn_id, text, final: true, ts }` over the WebSocket.
- [x] Keep the assembled assistant text available to `voice_ws.py` for persistence only after `turn_end` succeeds.
- [x] If the turn is canceled, do not send `assistant_text final=true` and do not persist the assistant row.
- [x] Add `tests/test_assistant_text_frame.py`:
  - [x] Complete turn → one `assistant_text final=true` frame with non-empty text.
  - [x] Canceled turn → no `assistant_text final=true` frame; no assistant row persisted.

Checks before checking off:

- [x] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): emit assistant_text on turn completion (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 3)`.

## Phase 4 — Per-session runtime config

Tasks:

- [x] Add `app/services/session_runtime_config.py` with a dataclass:
  - `intermediary_mode: Literal["deterministic","llm"] = "llm"`
  - `speech_rms_threshold: float = 0.003`
  - `end_silence_seconds: float = 1.1`
  - `min_turn_seconds: float = 0.8`
  - `max_turn_seconds: float = 8.0`
  - Method `apply_partial(updates: dict) -> dict` returning the clamped fields and values.
- [x] In `app/routes/voice_ws.py`:
  - [x] Replace the four module-level constants with reads from a per-connection `SessionRuntimeConfig`.
  - [x] Pass the config into `AudioTurnSegmenter` so each new turn picks up the latest values at the next silence boundary.
  - [x] On `client_hello`, populate the config from `intermediary_mode` and `audio_params` (clamped).
- [x] In `app/services/front_llm.py`:
  - [x] When `intermediary_mode == "deterministic"`, route substantive transcripts straight to Hermes without front-LLM intervention. Do not skip producing an answer.
  - [x] When `intermediary_mode == "llm"`, keep the existing router logic (ack for trivial, Hermes for substantive).
- [x] Tests:
  - [x] `tests/test_runtime_config.py` covers clamping and apply.
  - [x] `tests/test_voice_ws_runtime.py` covers `client_hello` overrides applied on the first turn.
  - [x] Coverage for deterministic routing producing a Hermes call.

Checks before checking off:

- [x] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): per-session runtime config and routing modes (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 4)`.

## Phase 5 — Live frame handlers with next-turn semantics

Tasks:

- [x] Extend client-message dispatch in voice_ws.py to handle:
  - `set_intermediary_mode` → updates `config.intermediary_mode`, emits `runtime_config_applied`.
  - `set_audio_params` → updates fields (clamped), emits `runtime_config_applied` with clamped values.
- [x] Document explicitly in code and in the operator notes that during an active turn the WS text channel is not being read; the frame is queued and applied on the next read. Effective behavior: changes land at the next turn boundary.
- [x] Log at INFO when a runtime parameter changes (Loguru, session_id + changed field names; no PII).
- [x] Tests in `tests/test_voice_ws_runtime.py`:
  - [x] Mid-conversation switch frame applied by next turn.
  - [x] Out-of-range clamping reflected in the ack values.

Checks before checking off:

- [x] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): live runtime config frames (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 5)`.

## Phase 6 — voice_store helpers

Tasks:

- [x] In `app/services/voice_store.py` (or `app/db.py` if that is where session helpers live):
  - [x] Add `get_session_for_owner(owner_id: str, session_id: str) -> dict | None` that looks up without creating.
  - [x] Add `list_recent_messages(session_id: str, limit: int) -> list[dict]` returning newest first.
- [x] Update or keep `get_or_create_session` separate. Long-gap resume must call `get_session_for_owner` first.
- [x] Tests:
  - [x] `get_session_for_owner` returns None when missing; returns row when present and owned; rejects ownership mismatch.
  - [x] `list_recent_messages` returns at most `limit` rows in DESC order.

Checks before checking off:

- [x] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): voice_store session and message helpers (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 6)`.

## Phase 7 — Long-gap session resume

Depends on phases 2 and 6.

Tasks:

- [x] Add `LONG_RESUME_MAX_MESSAGES: int = 50` to `app/config.py` and `api/.env.example`.
- [x] In `voice_ws.py`, on `client_hello.session_id`:
  - [x] Try in-memory resume first.
  - [x] On miss, call `get_session_for_owner(principal.owner_id, session_id)`. On ownership mismatch return `APIError` per docs/ERROR_REQUIREMENTS.md.
  - [x] On a verified row, call `list_recent_messages(session_id, LONG_RESUME_MAX_MESSAGES)`, reverse to chronological, and seed a fresh front_llm context. Reuse the stored `conversation_id`.
  - [x] Respond with `session_started { resumed: true }` and the original `conversation_id`.
  - [x] On total miss, respond with `session_started { resumed: false, created: true }`.
- [x] Tests in `tests/test_voice_ws_long_resume.py`:
  - [x] Cold resume past 5 minutes returns `resumed: true` with original `conversation_id`.
  - [x] Mocked Hermes call after resume sees seeded prior context (assert front_llm receives the rehydrated messages).
  - [x] Ownership mismatch returns the documented error.
  - [x] Missing session falls back to a new one.

Checks before checking off:

- [x] `uv run pytest && uv run ruff check && uv run ruff format --check` pass.

Commit: `feat(api): long-gap session resume from DB (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 7)`.

## Phase 8 — Operator notes

Tasks:

- [ ] Append an Operator notes section with:
  - Example payloads for `set_intermediary_mode` and `set_audio_params`.
  - Example `wscat` flow for triggering long-gap resume.
  - Explicit reminder that frames apply at the next turn boundary, not mid-turn.

Commit: `docs(api): operator notes for runtime config and resume (20260513_TODO_API_RUNTIME_CONFIG_V02 phase 8)`.

## Critical files

Modified:

- docs/20260510_PROTOCOL_V01.md (phase 1, own commit)
- docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md (phase 2, own commit)
- api/app/services/hermes.py
- api/app/services/front_llm.py
- api/app/routes/voice_ws.py
- api/app/services/voice_store.py
- api/app/config.py
- api/.env.example

Added:

- api/app/services/session_runtime_config.py
- api/tests/test_hermes_session_propagation.py
- api/tests/test_assistant_text_frame.py
- api/tests/test_runtime_config.py
- api/tests/test_voice_ws_runtime.py
- api/tests/test_voice_ws_long_resume.py

Reused:

- api/app/services/voice_store.py and api/app/db.py (sessions and messages tables)
- api/app/errors.py (APIError shape)

## Operator notes (placeholder — fill in after phase 5 and 7)

- Runtime config frames are read between active turn processing steps. If a client sends `set_intermediary_mode` or `set_audio_params` while the API is processing a turn, the frame is queued by the WebSocket stack and applies on the next read, effectively the next turn boundary.
- Sending `set_intermediary_mode` mid-conversation: example payload; applied at next turn boundary.
- Sending `set_audio_params` mid-conversation: example payload; clamped echo behavior.
- Triggering long-gap resume: reconnect after >5 minutes with prior `session_id`; expect `resumed: true`.
