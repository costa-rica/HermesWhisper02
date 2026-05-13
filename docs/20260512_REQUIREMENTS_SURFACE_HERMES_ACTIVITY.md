# Requirements — surface Hermes activity in the mobile app

Date: 2026-05-12
Scope: API (`api/`) and Mobile (`mobile/`).
Companion docs: [20260510_PROTOCOL_V01.md](20260510_PROTOCOL_V01.md), [20260510_PLAN_API_V01.md](20260510_PLAN_API_V01.md), [20260510_PLAN_MOBILE_V01.md](20260510_PLAN_MOBILE_V01.md).

## Context

When the front LLM (`gpt-4o-mini`) calls the `call_hermes` tool, Hermes may run for 30 seconds to several minutes before producing a speakable answer. Today the user hears the deterministic ack ("On it.") and then silence until Hermes finishes, even though Hermes itself is emitting structured progress events (tool calls, actions, steps) the whole time, like the activity feed shown in Telegram.

Goal: keep the current architecture (Whisper STT → front LLM → `call_hermes` → Hermes → TTS) and add a read-only live activity window in the iOS app that streams Hermes's per-step events in real time. This is for visibility only. It does not alter audio, the ack path, or the answer path.

## Feasibility

Three confirmed facts make this practical.

1. Hermes already emits a Server-Sent Events stream at `POST /responses` with `Accept: text/event-stream` and typed events. HermesVoice's `api/app/services/hermes.py` (lines 147–193) parses `event:` and `data:` lines and routes by `etype` / `event_name`, then filters to one type (`SPEAKABLE_EVENT = "response.output_text.delta"`) and discards the rest. The other event types are present in that stream. HermesVoice simply ignores them.
2. HermesWhisper02's current [api/app/services/hermes.py](../api/app/services/hermes.py) is more primitive. It does plain `aiter_text()` and does not parse SSE at all. It needs to be upgraded to SSE parsing to expose non-speakable events.
3. The wire protocol [docs/20260510_PROTOCOL_V01.md](20260510_PROTOCOL_V01.md) §4.2 only has `assistant_state` (`ack` / `thinking` / `answer` / `idle`), which is coarse. A new server→client frame for per-step Hermes activity needs to be added. This is a small additive protocol change.

## Decisions baked in

| Topic                  | v1 choice                                                                 |
| ---------------------- | ------------------------------------------------------------------------- |
| Event filter           | `tool_call` and `tool_result` only. Other non-speakable events dropped.   |
| History across turns   | Per-turn only. Cleared at the start of each new turn.                     |
| Audio path             | Untouched. Activity frames are observability-only.                        |
| Persistence            | None. Ephemeral live display only.                                        |
| Protocol versioning    | Additive frame. No `protocol_version` bump.                               |

## Recommended approach

Four layers, all additive. None modify the existing ack or answer audio paths.

### 1. API — parse SSE and emit non-speakable events as a stream

File: [api/app/services/hermes.py](../api/app/services/hermes.py).

- Switch from `aiter_text()` to SSE line parsing modeled on HermesVoice's `hermes.py` lines 147–193. Handle `event:`, `data:`, `[DONE]`, JSON parse per line.
- Replace the current single-purpose generator with one that yields a typed union, for example `HermesEvent = SpeakableDelta(text) | ProgressEvent(kind, text, raw)`.
- `kind` is restricted to `tool_call` and `tool_result` only, derived from the corresponding Hermes SSE event types. Every other non-speakable event is dropped at this layer and not forwarded to the WS. This keeps the activity panel clean and matches the chosen event filter.
- The mock branch (`HERMES_MOCK=true`) should emit a couple of fake progress events so the mobile UI can be tested without the real Hermes.

### 2. API — forward progress events through the pipeline to the WS

Files: [api/app/services/front_llm.py](../api/app/services/front_llm.py), [api/app/pipecat_processors/ws_transport_adapter.py](../api/app/pipecat_processors/ws_transport_adapter.py).

- The `call_hermes` tool handler in `FrontAnswerProcessor.answer` currently uses `collect_hermes_text`, which awaits the full string. Replace with iteration over the new typed generator. Speakable deltas continue to be accumulated into a `TextFrame` (fixing answer-side streaming is a separate concern). Progress events are pushed to a side-channel callback supplied by the transport.
- In the transport adapter, add a `send_hermes_progress(turn_id, kind, text)` method that serializes to a new JSON frame `hermes_progress` and writes it on the same `/ws/voice` WebSocket. Reuse the existing JSON-write path. No binary involvement.
- This is purely informational. It must not delay, gate, or interfere with `audio_chunk` frames. No backpressure linkage to the audio path.

### 3. Protocol — add `hermes_progress` frame

File: [docs/20260510_PROTOCOL_V01.md](20260510_PROTOCOL_V01.md) §4.2.

Add a new server → client text frame.

```
| `hermes_progress` | { "turn_id", "kind": "tool_call" | "tool_result", "text": str, "ts": float } |
```

No version bump. Additive frames are forward-compatible because v1 clients ignore unknown `type` values per §3. Document that this frame is for observability only and not required for protocol correctness.

### 4. Mobile — live activity panel

Files (created during PLAN_MOBILE phase 6 and extended here).

- [mobile/ios/HermesWhisper02/HermesWhisper02/Voice/ProtocolEnvelope.swift](../mobile/ios/HermesWhisper02/HermesWhisper02/Voice/ProtocolEnvelope.swift). Add a `HermesProgress` case to the discriminated union to match the new frame.
- [mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceSocket.swift](../mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceSocket.swift). Emit a `VoiceEvent.hermesProgress(...)` on receipt.
- [mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceController.swift](../mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceController.swift). Maintain an `@Observable` per-turn list of progress events. Cleared at the start of each new turn (on the first `transcript {is_final: true}` for the new `turn_id`). No cross-turn history retained.
- New view `HermesActivityView.swift`. A SwiftUI scroll view bound to the per-turn list. Each row shows `kind` (icon), `text`, and elapsed seconds since `turn_started`. Auto-scroll to bottom.
- Wire into `VoiceView` as either a dedicated tab or a collapsible bottom sheet.

No third-party dependencies. Standard SwiftUI, async/await, and `AsyncStream`, consistent with [mobile/AGENTS.md](../mobile/AGENTS.md).

## Files to read or modify

- Modify
  - [api/app/services/hermes.py](../api/app/services/hermes.py)
  - [api/app/services/front_llm.py](../api/app/services/front_llm.py)
  - [api/app/pipecat_processors/ws_transport_adapter.py](../api/app/pipecat_processors/ws_transport_adapter.py)
  - [docs/20260510_PROTOCOL_V01.md](20260510_PROTOCOL_V01.md)
- Reference for the SSE parsing pattern
  - `HermesVoice/api/app/services/hermes.py`
- Mobile additions land in the PLAN_MOBILE phase 6 file set or a small phase 6.5 addendum.

## Verification

1. API unit test. Drive [api/app/services/hermes.py](../api/app/services/hermes.py) against a captured SSE fixture (one `tool_call`, several text deltas, `[DONE]`). Assert the generator yields the expected mix of `ProgressEvent` and `SpeakableDelta` values in order.
2. API integration test. Extend `tests/test_pipeline_smoke.py` with `HERMES_MOCK=true` and assert that the WS transport receives at least one `hermes_progress` JSON frame interleaved with the audio frames.
3. Mobile unit test. Extend `ProtocolEnvelopeTests` to round-trip a `hermes_progress` frame.
4. End-to-end manual. With the deployed API and a real Hermes turn that uses tools, run the mobile app on a simulator or device and confirm the activity panel populates in real time while audio is silent between ack and answer.

## Out of scope

- Audible filler ("Still working on that…") during long Hermes thinks. That is a separate larger UX decision.
- Streaming the answer path itself (replacing `collect_hermes_text` with chunked TTS). Also a separate concern. This document only addresses visibility.
- Persisting progress events to the SQLite store. Current intent is ephemeral live display only.
