# Requirements V02: Reorganized UI, Local Conversation History, Runtime Toggles

Date: 2026-05-13
Supersedes: docs/archived/20260513_REQUIREMENTS_UI_HISTORY.md
Triggered by: docs/archived/20260513_REQUIREMENTS_UI_HISTORY_ASSESSMENT_CODEX.md
Anchors: docs/20260513_TODO_MOBILE_UI_HISTORY_V02.md and docs/20260513_TODO_API_RUNTIME_CONFIG_V02.md
Related: docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md

## Changes from V01

- Added a hard prerequisite: API must propagate the stored Hermes session identifier on every Hermes request. Today api/app/services/hermes.py:103-107 sends only `model`, `messages`, `stream`. Long-gap resume cannot ship until this is resolved.
- Added an `assistant_text` protocol frame. Without it, mobile cannot persist assistant bubbles reliably; only answer audio is sent today.
- Redefined intermediary modes. `deterministic` means deterministic routing direct to Hermes (no front-LLM router). `llm` means the front-LLM router may answer trivial turns or call Hermes. Neither mode silences real answers.
- Persistence trigger moved from `HermesProgressKind.finished` to `turn_end` with `canceled != true`. TTS or playback may fail after Hermes finishes.
- Documented that live runtime frames apply at the next read of the WebSocket text channel, which can be delayed during long Hermes/TTS work. Effective semantics: applied at the next turn boundary.
- Separated two ideas explicitly: local SQLite is the device's UI history; Hermes session/conversation propagation is what restores Hermes agent memory. They share identifiers but are different layers.

## Goals

- Reorganize the main mobile screen so the server is the title, conversation history lives in a left drawer, and Settings lives in a right sheet.
- Add a scrollable, bubble-style conversation transcript on the main screen.
- Persist conversation history locally on the device, scoped per server profile.
- Allow the user to switch the intermediary routing (deterministic-direct-to-Hermes vs front-LLM router) at runtime; changes take effect at the next turn boundary.
- Expose VAD and barge-in tunables as sliders in Settings, all adjustable at the next turn boundary.
- Resume a past conversation so the Hermes agent retains context, even after long gaps, once Hermes session propagation is in place.

## Non-goals

- No on-device STT or on-device VAD beyond the existing energy-based barge-in.
- No cross-device sync of conversation history (single device only in v1).
- No third-party Swift packages.
- No new authentication flow.

## Hard prerequisites for long-gap resume

The following must land before drawer Resume can claim to restore Hermes context:

1. Resolve docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md by confirming the Hermes contract for session memory. Candidates: `/responses` with `conversation: <id>` (HermesVoice approach), an `X-Hermes-Session-Id` or `X-Hermes-Session-Key` header, or a Chat Completions extension.
2. Implement the chosen contract in api/app/services/hermes.py so every Hermes request carries the stored identifier.
3. Add a test asserting the outgoing Hermes request body or headers contain that identifier.

Until those land, the drawer ships read-only with Resume disabled (or marked "best-effort within 5 minutes").

## Main screen layout

ASCII wireframe:

```
+-----------------------------------------+
| [≡]    Hermes Production Server   [⚙]   |   <- top of safe area
|         (tappable, wraps, large)        |
|-----------------------------------------|
|  Mic RMS  ▮▮▮▮▯▯▯  Assistant: idle      |
|  [Hermes activity compact strip]        |
|  [   Start voice   ]                    |
|-----------------------------------------|
|                                         |
|                          ┌─────────────┐|
|                          │ user text   ││
|                          └─────────────┘|
|  ┌─────────────┐                        |
|  │ assistant   │                        |
|  │ text bubble │                        |
|  └─────────────┘                        |
|                                         |
+-----------------------------------------+
```

Behaviors (unchanged from V01):

- Hamburger button on the top left opens a drawer of past conversations for the active server.
- Gear button on the top right opens the Settings sheet.
- Server name is tappable and presents the existing ServerRegistryView as a sheet.
- "Hello, HermesWhisper02" line is removed.
- The standalone Servers button and Logout button are removed; Logout moves into Settings.
- Bubble transcript: user trailing, assistant leading, 80 percent max width, `.textSelection(.enabled)` per bubble.

## Drawer flow

- Drawer lists local sessions for the active server, newest first.
- Each row shows a short preview, updated_at, message count.
- Tap pushes a read-only ConversationDetailView using the same bubble renderer.
- Detail view has a Resume button; enabled only when Hermes session propagation is in place (see prerequisites).
- Swipe-to-delete removes the local row only. Long-term UI label can read "Remove from this device".
- Drawer list reloads after each completed turn (preview and message count refresh) and after profile switch.

## Settings flow

Sections in order:

1. Intermediary routing: segmented picker, Deterministic or LLM. Default LLM. Persists per profile.
2. Server-side VAD sliders (sent via protocol frames).
3. Client-side barge-in sliders (applied to live BargeInDetector).
4. Voice interaction mode picker (moved from main screen).
5. Logout.

Effective timing: live frames may be queued behind an active turn; changes apply at the next turn boundary.

## Local conversation store

- One SQLite file per server profile under `Application Support/HermesWhisper02/conversations/<server_profile_id>.sqlite`.
- Schema mirrors HermesVoice's `voice_sessions` and `voice_messages`.

```
CREATE TABLE voice_sessions (
    id TEXT PRIMARY KEY,                  -- WS session_id from session_started
    server_profile_id TEXT NOT NULL,
    hermes_conversation_id TEXT NOT NULL, -- conversation_id from session_started
    title TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    last_message_preview TEXT,
    message_count INTEGER NOT NULL DEFAULT 0,
    archived_at TEXT
);

CREATE INDEX idx_voice_sessions_updated
    ON voice_sessions(archived_at, updated_at DESC);

CREATE TABLE voice_messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    turn_id TEXT,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    text TEXT NOT NULL,
    final INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    FOREIGN KEY(session_id) REFERENCES voice_sessions(id)
);

CREATE INDEX idx_voice_messages_session_created
    ON voice_messages(session_id, created_at ASC);
```

Conceptual layering:

- Device SQLite renders the UI history.
- Hermes-side memory is preserved by sending the stored `hermes_conversation_id` with every Hermes request (per the Hermes contract chosen above).
- The two layers share identifiers; they are not the same storage.

## Persistence trigger

- On final transcript: stash pending user text in memory (not yet committed).
- On `assistant_text { final: true }`: stash pending assistant text in memory.
- On `turn_end` with `canceled != true`: commit both pending messages to SQLite under the active session and refresh drawer state.
- On `turn_end` with `canceled == true`: discard pending assistant text; keep pending user text if the upstream design decides to (TBD in mobile TODO phase 2).

## Resume contract

- Client opens a WebSocket and sends `client_hello.session_id = <stored session_id>`.
- If the API still has the session warm, behavior is identical to today.
- If older than `SESSION_RESUME_WINDOW_SEC` (300):
  1. API looks up `voice_sessions` by `session_id` and verifies `owner_id` matches.
  2. API loads up to `LONG_RESUME_MAX_MESSAGES` most-recent rows from `voice_messages`, reversed to chronological.
  3. API rebuilds front_llm context and continues to use the original `conversation_id` on outgoing Hermes calls.
  4. API responds with `session_started { resumed: true }` and the original `conversation_id`.
- If session is not found, client falls back to a new session. The local row remains as read-only history.
- `session_id` and `hermes_conversation_id` stay distinct on the wire and in the local row.

## Intermediary routing definitions

- `deterministic`: deterministic routing direct to Hermes. The front-LLM router does not answer; non-trivial transcripts go to Hermes verbatim. Trivial-ack heuristics are bypassed.
- `llm`: the existing front-LLM router behavior. Front-LLM may produce short answers for trivial transcripts and calls Hermes otherwise.
- The toggle never silences answers. Both modes produce a Hermes-grade answer for substantive turns.
- Default: `llm`.

## Tunable parameters inventory

Server-side (sent via `client_hello.audio_params` or `set_audio_params`):

| Name                  | Default | Unit            | Range        | Source                          |
|-----------------------|---------|-----------------|--------------|---------------------------------|
| speech_rms_threshold  | 0.003   | normalized 0..1 | 0.001 – 0.05 | api/app/routes/voice_ws.py:29   |
| end_silence_seconds   | 1.1     | seconds         | 0.3 – 3.0    | api/app/routes/voice_ws.py:28   |
| min_turn_seconds      | 0.8     | seconds         | 0.2 – 2.0    | api/app/routes/voice_ws.py:26   |
| max_turn_seconds      | 8.0     | seconds         | 5.0 – 30.0   | api/app/routes/voice_ws.py:27   |

Client-side (applied locally to BargeInDetector.Config):

| Name                          | Default | Unit            | Range       | Source                                              |
|-------------------------------|---------|-----------------|-------------|-----------------------------------------------------|
| barge_in_rms_threshold        | 0.025   | normalized 0..1 | 0.01 – 0.10 | mobile/.../Voice/BargeInDetector.swift:7            |
| barge_in_window_duration      | 0.05    | seconds         | 0.01 – 0.20 | mobile/.../Voice/BargeInDetector.swift:6            |
| barge_in_consecutive_windows  | 2       | count           | 1 – 5       | mobile/.../Voice/BargeInDetector.swift:8            |

Out-of-range values are clamped server-side; the ack frame echoes the clamped values.

## Protocol delta against docs/20260510_PROTOCOL_V01.md

Additions only; `protocol_version` stays at 1.

- `client_hello` gains:
  - `intermediary_mode`: `"deterministic"` or `"llm"`. Default `"llm"`.
  - `audio_params`: object with any subset of the four server-side keys above.
- New client to server frames:
  - `set_intermediary_mode { mode }`
  - `set_audio_params { speech_rms_threshold?, end_silence_seconds?, min_turn_seconds?, max_turn_seconds? }`
- New server to client frames:
  - `assistant_text { turn_id, text, final, ts }` emitted once Hermes streaming completes with the final assembled answer text. Used to populate assistant bubbles.
  - `runtime_config_applied { fields: [...], values: { ... } }` echoed after a successful apply.
- Effective-timing semantics:
  - Frames are read on the WebSocket text channel; while a turn is being processed the loop may not be reading text.
  - All applies are deferred to the next transcript/turn boundary; never mid-turn.
  - Mobile UI should treat changes as "applied next turn".

## Open contract questions to resolve before implementation

- Hermes session contract: which mechanism does Hermes accept (`conversation` body field on `/responses`, header on chat completions, or other)? Tracked in docs/20260512_HERMES_HTTP_CONTRACT_DISCOVERY.md.

## Out of scope

- Audio gain and downlink volume sliders.
- Persisting Hermes activity log expansion preference.
- iPad NavigationSplitView treatment beyond the iPhone layout.
- Cross-device history sync.

## Risks tracked

- If the Hermes contract is not resolvable in this round, ship V02 with Resume disabled and document the gap.
- If `assistant_text` cannot be implemented immediately, mobile persistence buffers a placeholder for the assistant bubble and waits to commit until the frame is available. UI may show "(assistant audio only)" for historic rows from that period.
