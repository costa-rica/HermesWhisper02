# Requirements: Reorganized UI, Local Conversation History, Runtime Toggles

Date: 2026-05-13
Anchors: docs/20260513_TODO_MOBILE_UI_HISTORY.md and docs/20260513_TODO_API_RUNTIME_CONFIG.md

## Goals

- Reorganize the main mobile screen so the server is the title, conversation history lives in a left drawer, and Settings lives in a right sheet.
- Add a scrollable, bubble-style conversation transcript on the main screen.
- Persist conversation history locally on the device, scoped per server profile.
- Allow the user to switch the intermediary layer (deterministic ack vs full Hermes LLM) at runtime, including mid-conversation.
- Expose VAD and barge-in tunables as sliders in Settings, all adjustable at runtime where feasible.
- Resume a past conversation so the Hermes agent retains context, even after long gaps.

## Non-goals

- No on-device STT or on-device VAD beyond the existing energy-based barge-in.
- No cross-device sync of conversation history (single-device only in v1).
- No third-party Swift packages.
- No new authentication flow.

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
|                          ┌─────────────┐|
|                          │ user text   ││
|                          └─────────────┘|
|  ┌─────────────┐                        |
|  │ assistant   │                        |
|  └─────────────┘                        |
|                                         |
+-----------------------------------------+
```

Behaviors:

- Hamburger button on the top left opens a slide-out drawer of past conversations for the active server.
- Gear button on the top right opens the Settings sheet.
- Server name is tappable and presents the existing ServerRegistryView as a sheet.
- "Hello, HermesWhisper02" line is removed.
- The standalone Servers button and Logout button are removed; Logout moves into Settings.
- The transcript area auto-scrolls to the newest bubble.
- User bubbles align trailing; assistant bubbles align leading.
- Each bubble takes up to 80 percent of the screen width.
- Each bubble has `.textSelection(.enabled)` so the user can highlight and copy text from a single bubble.

## Drawer flow (conversation history)

- Drawer lists local sessions for the active server, newest first.
- Each row shows a short title (first user line preview), updated_at, and message count.
- Tapping a row pushes a read-only ConversationDetailView that renders the bubbles with the same renderer as the live transcript.
- Detail view has a Resume button that calls VoiceController.startSession(resumeSessionID:).
- Swipe-to-delete removes the local row only; it does not touch any API-side data.
- Switching the active server profile changes the drawer list automatically.

## Settings flow

Sections in order:

1. Intermediary mode: segmented picker, Deterministic or LLM. Default LLM. Persists per server profile.
2. Server-side audio (VAD) sliders, applied to the API session via protocol frames.
3. Client-side barge-in sliders, applied locally to the live BargeInDetector.
4. Voice interaction mode picker, moved from the main screen.
5. Logout button at the bottom.

Settings changes that affect the live session apply at the next transcript boundary, never mid-turn.

## Local conversation store

- SQLite database files live in Application Support: `HermesWhisper02/conversations/<server_profile_id>.sqlite`.
- A separate file per server profile keeps scope explicit and makes deletion of a profile clean.
- Schema mirrors HermesVoice (api/app/services/voice_store.py in /Users/nick/Documents/HermesVoice).

Tables:

```
CREATE TABLE voice_sessions (
    id TEXT PRIMARY KEY,                  -- WS session_id from session_started
    server_profile_id TEXT NOT NULL,      -- redundant with file path, kept for safety
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

ID model: session_id and hermes_conversation_id stay distinct (matches the existing session_started frame in docs/20260510_PROTOCOL_V01.md). The mobile row stores both.

## Resume contract

- On Resume, the client opens a WebSocket and sends `client_hello.session_id = <stored session_id>`.
- If the API still has the session in memory, behavior is identical to today.
- If the session is older than `SESSION_RESUME_WINDOW_SEC`, the API performs a long-gap rehydrate:
  1. Look up `voice_sessions` by `session_id` and verify `owner_id` matches.
  2. Reload up to `LONG_RESUME_MAX_MESSAGES` rows from `voice_messages` (newest first, reversed before injection).
  3. Build a fresh front_llm context seeded with those messages and the stored `conversation_id`.
  4. Respond with `session_started { resumed: true }` and the same `conversation_id`.
- If the session is not found at all, the client falls back to starting a new session. The local row remains as read-only history.

## Intermediary toggle scope

- Per-session via `client_hello.intermediary_mode`.
- Live-switchable via the `set_intermediary_mode` frame.
- The server stores the value on the session's `SessionRuntimeConfig` and reads it at the next transcript boundary.
- Default is `llm`.

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
| barge_in_rms_threshold        | 0.025   | normalized 0..1 | 0.01 – 0.10 | mobile/ios/.../Voice/BargeInDetector.swift:7        |
| barge_in_window_duration      | 0.05    | seconds         | 0.01 – 0.20 | mobile/ios/.../Voice/BargeInDetector.swift:6        |
| barge_in_consecutive_windows  | 2       | count           | 1 – 5       | mobile/ios/.../Voice/BargeInDetector.swift:8        |

Values out of range are clamped server-side.

## Protocol delta against docs/20260510_PROTOCOL_V01.md

Additions only, no breaking changes.

- `client_hello` gains two optional fields:
  - `intermediary_mode`: `"deterministic"` or `"llm"`. Default `"llm"`.
  - `audio_params`: object with the four server-side keys above. Any subset allowed.
- New client to server frames:
  - `set_intermediary_mode { mode }`
  - `set_audio_params { speech_rms_threshold?, end_silence_seconds?, min_turn_seconds?, max_turn_seconds? }`
- New server to client ack frame:
  - `runtime_config_applied { fields: [...], values: { ... } }` echoed after a successful apply.
- Semantics:
  - All changes apply at the next transcript boundary, never mid-turn.
  - Out-of-range values are clamped; the ack frame contains the clamped values.

## Out of scope (future work)

- Audio gain and downlink volume sliders.
- Persisting Hermes activity log expansion preference.
- iPad NavigationSplitView treatment beyond what the iPhone layout supports.
- Cross-device history sync.
