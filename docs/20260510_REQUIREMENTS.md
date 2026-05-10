# HermesWhisper02 — Requirements

**Status:** Draft v0.1 — requirements only, no implementation.
**Date:** 2026-05-10
**Author:** generated for nrodrig1@gmail.com
**Predecessor:** HermesVoice (see `HermesVoice/docs/20260509_MOBILE_TO_API_CHAT_FLOW.md`).

---

## 1. Purpose and scope

HermesWhisper02 is the next-generation real-time voice client/server pair that fronts the Hermes AI Agent. It replaces the bespoke STT/TTS/VAD orchestration in the HermesVoice FastAPI backend with a [Pipecat](https://github.com/pipecat-ai/pipecat) pipeline (BSD 2-Clause), keeps the Swift + Python FastAPI monorepo layout, and reorganizes the conversational architecture around a small "front" LLM that fronts Hermes.

It also introduces multi-server support so the iOS app can be pointed at any number of avatar-class backends, each running its own Hermes + HermesWhisper02 API.

### 1.1 In scope (v1)

- iOS push-to-talk + always-listening voice client with **server-side VAD only**.
- FastAPI backend hosting a Pipecat pipeline behind a single WebSocket.
- Front LLM acknowledgment + Hermes-as-tool architecture.
- Multi-server registry in the mobile app, with per-server auth credentials in the iOS Keychain.
- Initial deployment target: **fsdc-avatar08** (Hermes + HermesWhisper02 API co-located).

### 1.2 Out of scope (v1)

- Web client (the legacy HermesVoice web UI is not being ported in v1).
- Android client.
- Multi-user-per-server admin UI; auth remains per-user.
- Cross-server conversation continuity (each server keeps its own session state).

---

## 2. System architecture

### 2.1 High-level diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              iOS app (Swift)                                │
│                                                                             │
│   ┌──────────────┐    ┌─────────────┐    ┌──────────────┐    ┌──────────┐  │
│   │ Server       │───▶│ Auth /      │───▶│ Mic capture  │───▶│ WebSocket│  │
│   │ registry     │    │ Keychain    │    │ (raw PCM)    │    │ client   │  │
│   │ (multi)      │    │ (per server)│    │              │    │          │  │
│   └──────────────┘    └─────────────┘    └──────────────┘    └────┬─────┘  │
│                                          ┌──────────────┐         │        │
│                                          │ TTS playback │◀────────┤        │
│                                          │ + barge-in   │         │        │
│                                          └──────────────┘         │        │
└───────────────────────────────────────────────────────────────────┼────────┘
                                                                    │ WSS
                                                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                fsdc-avatar08 — FastAPI + Pipecat (Python)                   │
│                                                                             │
│   /ws/voice ──▶ Pipecat pipeline:                                           │
│                                                                             │
│   ┌──────────┐  ┌─────┐  ┌─────┐  ┌──────────┐  ┌──────────┐  ┌─────┐      │
│   │transport │─▶│ VAD │─▶│ STT │─▶│ context  │─▶│ front    │─▶│ TTS │─┐    │
│   │(WS in)   │  │     │  │     │  │ aggreg.  │  │ LLM      │  │     │ │    │
│   └──────────┘  └─────┘  └─────┘  └──────────┘  └────┬─────┘  └─────┘ │    │
│                                                     │ tool call       │    │
│                                                     ▼                 ▼    │
│                                          ┌──────────────────┐   ┌────────┐ │
│                                          │ Hermes AI Agent  │   │transp. │ │
│                                          │ (loopback :8642) │   │(WS out)│ │
│                                          └──────────────────┘   └────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component responsibilities

| Component                  | Responsibility                                                                 | Notes                                       |
| -------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------- |
| iOS app                    | Capture mic, stream raw audio, play downlink TTS, manage server registry, auth | No client-side VAD, no STT, no TTS          |
| FastAPI app                | TLS/WS endpoint, auth, session metadata, hosts Pipecat pipeline                | Same monorepo layout as HermesVoice         |
| Pipecat pipeline           | Drives the audio loop (transport→VAD→STT→aggregator→front LLM→TTS→transport)  | New; replaces `services/pipeline.py` logic  |
| Front LLM                  | Acknowledge user; route to Hermes; small talk; relay Hermes reply              | Llama 3.2 3B (Ollama) **or** Claude Haiku   |
| Hermes AI Agent            | Backend tool/service called by the front LLM                                   | Loopback only, unchanged from HermesVoice   |

### 2.3 Network topology

```
iOS ──WSS──▶ Nginx (TLS) ──WS──▶ avatar08:<port> FastAPI/Pipecat
                                         │
                                         ├──HTTP──▶ 127.0.0.1:11434  (Ollama, optional)
                                         ├──HTTPS──▶ Anthropic API   (Claude Haiku, optional)
                                         └──HTTP──▶ 127.0.0.1:8642   (Hermes Agent, loopback)
```

The front LLM is configurable per deployment; Hermes is always loopback.

---

## 3. Functional requirements

### FR-1 Pipecat-driven audio loop (server)

- **FR-1.1** The FastAPI backend must install Pipecat (`pip`, BSD 2-Clause) and host a single Pipecat pipeline per active voice session.
- **FR-1.2** The pipeline must be composed of, in order: WebSocket transport (input) → VAD → STT → context aggregator → front LLM → TTS → WebSocket transport (output).
- **FR-1.3** STT and TTS providers must be pluggable via configuration (Whisper / OpenAI TTS as v1 default; Deepgram, Cartesia, ElevenLabs, etc. allowed as alternatives via Pipecat services).
- **FR-1.4** All custom VAD/STT/TTS/turn-detection code from HermesVoice (`services/stt.py`, `services/tts.py`, `services/pipeline.py`'s chunking logic) must be removed in favor of Pipecat processors.
- **FR-1.5** The pipeline must enforce server-side endpointing/turn detection — the client never signals "end of utterance".

### FR-2 Thin-client mobile audio transport

- **FR-2.1** The Swift app must remove all on-device VAD code (`VoiceActivityDetector.swift` and `Vendor/sherpa-onnx*`).
- **FR-2.2** The app must capture mic audio at a Pipecat-compatible format (target: 16 kHz mono PCM16, frame size per Pipecat transport spec) and stream it continuously over WebSocket while the session is active.
- **FR-2.3** The app must play TTS audio frames received from the server with sub-200 ms first-chunk latency after server emits.
- **FR-2.4** The app must support **barge-in**: when the server sends a `user_started_speaking` signal, the app immediately stops local TTS playback and flushes its playback queue.
- **FR-2.5** Push-to-talk and continuous-listening modes must both be supported, configurable per session.

### FR-3 Front LLM intermediary

- **FR-3.1** The front LLM processor must, upon receiving a finalized user transcript, **immediately** generate a short acknowledgment ("got it, checking on that…") and emit it through TTS before invoking Hermes.
- **FR-3.2** The front LLM must invoke Hermes via a `call_hermes(query, conversation_id)` tool call, in parallel with (or immediately after) emitting the acknowledgment.
- **FR-3.3** When Hermes returns, the front LLM must relay the response to the user via TTS, optionally summarizing or rephrasing.
- **FR-3.4** The front LLM must handle small talk, clarifying questions, and trivial requests **without** calling Hermes.
- **FR-3.5** The front LLM model must be configurable: `FRONT_LLM_PROVIDER=ollama|anthropic`, with `FRONT_LLM_MODEL` (e.g. `llama3.2:3b`, `claude-haiku-4-5-20251001`).
- **FR-3.6** Acknowledgments must be varied (not the same string every turn) and must not be emitted for trivial turns the front LLM is answering itself.

### FR-4 Hermes as tool, not as LLM

- **FR-4.1** Hermes must be exposed to the front LLM solely as a tool/function; the user-facing LLM in the Pipecat pipeline is the front LLM.
- **FR-4.2** Hermes streaming responses must be consumed by the front LLM and may be summarized, truncated, or relayed verbatim per its policy.
- **FR-4.3** Hermes must remain loopback-only on its host (`127.0.0.1:8642`).

### FR-5 Multi-server support (mobile)

- **FR-5.1** The iOS app must maintain a **server registry**: an ordered list of server profiles, each with `id`, `display_name`, `base_url`, `notes` (optional), and a reference to its keychain credential.
- **FR-5.2** Users must be able to add, edit, rename, reorder, and delete server profiles.
- **FR-5.3** A single profile is "active" at any time; switching profiles tears down any open WebSocket and re-authenticates against the new server.
- **FR-5.4** The UI must surface the active server name in the main voice screen.

### FR-6 Per-server authentication

- **FR-6.1** Each server profile stores its credentials (bearer token + refresh material, or username/password if 2FA initial login is required) in the iOS Keychain, keyed by profile `id`.
- **FR-6.2** Auth flows are scoped to the active profile only — credentials never leak across profiles.
- **FR-6.3** Each server may run its own auth scheme; v1 supports the existing HermesVoice 2FA email-code → bearer-token flow as the baseline, but the abstraction must allow a single-step token flow as an alternative.

### FR-7 v1 deployment target

- **FR-7.1** The v1 release must ship with a single pre-registered server entry pointing at `fsdc-avatar08` (URL TBD by ops).
- **FR-7.2** The multi-server UI must still be present and functional in v1, even with a single configured entry.

---

## 4. Non-functional requirements

| ID    | Category        | Requirement                                                                                                                |
| ----- | --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| NFR-1 | Latency         | Time from end-of-user-speech (server VAD) to first TTS audio byte on the wire **≤ 800 ms p50, ≤ 1500 ms p95** (front LLM ack). |
| NFR-2 | Latency         | Time from end-of-user-speech to first TTS audio byte of **Hermes** answer **≤ 3.5 s p50, ≤ 6 s p95**.                       |
| NFR-3 | Barge-in        | From client mic detecting renewed speech to local playback silenced **≤ 150 ms**; server cancels in-flight TTS within **≤ 200 ms**. |
| NFR-4 | Audio quality   | Uplink ≥ 16 kHz mono PCM16; downlink ≥ 24 kHz; no audible glitches across chunk boundaries; AGC/echo cancellation acceptable. |
| NFR-5 | Reliability     | WebSocket reconnect with session resume within 2 s on transient drop; turn state must be idempotent across reconnects.      |
| NFR-6 | Security        | All transport TLS 1.2+; bearer tokens scoped per server; Keychain entries marked `kSecAttrAccessibleAfterFirstUnlock`.     |
| NFR-7 | Privacy         | Raw audio is not persisted server-side beyond the Pipecat pipeline window; transcripts may be persisted (per HermesVoice). |
| NFR-8 | Observability   | Per-stage timings logged (VAD→STT, STT→front-LLM, front-LLM→TTS, Hermes round-trip) using Loguru per HermesVoice convention. |
| NFR-9 | Licensing       | Pipecat (BSD 2-Clause), front LLM, and all bundled deps must be license-compatible with the project (no GPL viral terms).   |
| NFR-10| Resource        | A single avatar08 host must support ≥ 4 concurrent voice sessions without TTS underrun.                                     |

---

## 5. API contract — Swift ↔ FastAPI/Pipecat

### 5.1 Authentication

#### 5.1.1 Login (per server)

```
POST {base_url}/api/auth/login         { "email": "...", "password": "..." }
POST {base_url}/api/auth/verify        { "email": "...", "code": "123456"  }
   → 200 { "token": "<bearer>", "expires_at": "..." }
```

The mobile app stores `{token, expires_at}` in the Keychain under the profile id. Compatible with HermesVoice's existing `routes/mobile_auth.py`.

#### 5.1.2 Server identity probe

```
GET {base_url}/api/server/info
   → 200 { "name": "fsdc-avatar08", "version": "...", "front_llm": "...", "auth": "bearer-2fa" }
```

Used by the registry-add flow to validate the URL and pre-fill `display_name`.

### 5.2 WebSocket: `/ws/voice`

Auth: `Authorization: Bearer <token>` for the active server profile.

Transport framing follows Pipecat's WebSocket transport, wrapped in a thin envelope so existing client/server tooling can introspect frames.

#### 5.2.1 Client → server frames

| Frame                  | Direction | Payload                                                                  |
| ---------------------- | --------- | ------------------------------------------------------------------------ |
| `client_hello` (JSON)  | C→S       | `{ "protocol_version", "session_id?", "downlink_format", "sample_rate", "ptt_mode" }` |
| audio (binary)         | C→S       | Raw PCM16 LE, 16 kHz, mono, frame size per Pipecat config (e.g. 320 samples / 20 ms) |
| `cancel_turn` (JSON)   | C→S       | `{ "turn_id?": "..." }` — manual cancel (rare; usually server VAD handles barge-in)  |
| `client_bye` (JSON)    | C→S       | session shutdown                                                         |

#### 5.2.2 Server → client frames

| Frame                            | Direction | Payload                                                                              |
| -------------------------------- | --------- | ------------------------------------------------------------------------------------ |
| `session_started` (JSON)         | S→C       | `{ "session_id", "conversation_id", "downlink_format", "sample_rate", "front_llm" }` |
| `user_started_speaking` (JSON)   | S→C       | `{ "ts" }` — emitted by server VAD; client mutes its TTS playback immediately        |
| `user_stopped_speaking` (JSON)   | S→C       | `{ "ts" }`                                                                           |
| `transcript` (JSON)              | S→C       | `{ "turn_id", "text", "is_final" }`                                                  |
| `assistant_state` (JSON)         | S→C       | `{ "state": "ack" \| "thinking" \| "answering" \| "idle" }`                          |
| `audio_chunk` prelude (JSON)     | S→C       | `{ "turn_id", "seq", "format", "bytes", "source": "ack" \| "answer" }`               |
| audio (binary)                   | S→C       | Exactly `bytes` bytes of TTS audio in `format`                                        |
| `turn_end` (JSON)                | S→C       | `{ "turn_id", "canceled?": bool }`                                                   |
| `error` (JSON)                   | S→C       | `{ "error": { "code", "message", "status" } }` per HermesVoice error envelope        |

#### 5.2.3 Session resume

Pass `client_hello.session_id` to resume a previous voice session owned by the same `owner_id`. Server replies with `session_started.resumed=true` and rehydrates the front-LLM context from the persistent store.

### 5.3 Server registry — local-only

The registry is mobile-side only; there is no centralized directory service in v1. Schema:

```swift
struct ServerProfile {
    let id: UUID
    var displayName: String
    var baseURL: URL          // https://...
    var notes: String?
    var authKind: AuthKind    // .bearer2FA (v1)
    var keychainRef: String   // -> Keychain entry id
}
```

---

## 6. Pipecat pipeline definition

Reference: Pipecat pipeline composition idioms.

```
pipeline = Pipeline([
    ws_transport.input(),                # raw PCM frames in
    vad_processor,                       # Silero / WebRTC VAD; emits UserStartedSpeaking / UserStoppedSpeaking
    stt_service,                         # Whisper (v1) or Deepgram
    context_aggregator.user(),           # builds messages list
    front_llm_service,                   # Ollama Llama 3.2 3B or Anthropic Haiku
    #   ↳ tool: call_hermes(query, conversation_id)
    tts_service,                         # OpenAI TTS or Cartesia
    ws_transport.output(),               # binary audio frames out
    context_aggregator.assistant(),      # logs assistant turn
])
```

### 6.1 Front LLM tool definition

```python
{
    "name": "call_hermes",
    "description": "Forward the user's request to the Hermes AI Agent for substantive answers, "
                   "actions, or knowledge lookups. Do not call for small talk or trivial clarifications.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string"},
            "conversation_id": {"type": "string"}
        },
        "required": ["query", "conversation_id"]
    }
}
```

Implementation calls `services/hermes.stream_hermes_text()` (carried over from HermesVoice) and streams deltas back into the front LLM context.

### 6.2 Acknowledgment behavior

The front LLM's system prompt instructs it to:

1. On any non-trivial user turn, emit a one-sentence acknowledgment **before** calling `call_hermes`.
2. On trivial / small-talk turns, answer directly without invoking the tool.
3. After `call_hermes` returns, deliver the substantive answer.

The Pipecat pipeline must allow the acknowledgment TTS audio to start playing while `call_hermes` is still pending (parallel branches or interleaved frames — implementation detail to be resolved during design).

### 6.3 Parallel Hermes call

Two implementation candidates (decision in §9):

- **(a)** Front LLM emits ack text → TTS, then triggers tool call serially (simpler; ack still arrives quickly because Hermes wait dominates).
- **(b)** Pipecat `ParallelPipeline` branches: ack branch (front LLM short response → TTS) and Hermes branch (tool call → front LLM relay → TTS), merged downstream.

---

## 7. Migration considerations from HermesVoice

| Area                          | HermesVoice                                              | HermesWhisper02                                                    | Migration                                                                |
| ----------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| VAD                           | iOS sherpa-onnx Silero VAD                              | Server-side Pipecat VAD                                            | Delete `Vendor/sherpa-onnx*`, `VoiceActivityDetector.swift`              |
| Uplink                        | One WAV PCM16 per utterance, framed by `start/end_of_utterance` | Continuous raw PCM stream                                          | Rewrite `VoiceSocket.swift` uplink path                                  |
| Pipeline                      | Custom `services/pipeline.py` (STT→Hermes→chunked TTS)   | Pipecat pipeline                                                   | Delete `pipeline.py`, `_chunk_hermes_text`; keep `hermes.py` as tool client |
| Conversational LLM            | Hermes is the LLM                                        | Front LLM is the LLM; Hermes is a tool                             | New: front LLM service + system prompt + tool wiring                     |
| Auth                          | Single-server bearer token                               | Per-profile bearer token, multi-server                             | Refactor `AuthClient.swift` → `AuthService` keyed by `ServerProfile`     |
| Server config                 | Hardcoded `hermes-voice.dashanddata.com`                 | Server registry                                                    | New iOS module + persistence (Core Data or simple plist + Keychain)      |
| Persistence (server)          | SQLite voice sessions/messages, scoped by `owner_id`     | Same model retained; aggregator writes to it                       | Keep `services/voice_store.py`; adapt aggregator integration             |
| Protocol                      | `docs/PROTOCOL.md`                                       | New protocol doc; some frame names overlap                         | Author `HermesWhisper02/docs/PROTOCOL.md`                                |
| Web client                    | Present                                                  | **Not in v1**                                                      | Park `web/` from HermesVoice; revisit post-v1                            |

### 7.1 Repo layout

Recommended monorepo (mirrors HermesVoice):

```
HermesWhisper02/
  api/                       # FastAPI + Pipecat
    app/
      main.py
      config.py
      auth.py
      routes/
        voice.py             # /ws/voice + REST CRUD
        mobile_auth.py
        server_info.py       # NEW: /api/server/info
      services/
        pipeline.py          # builds Pipecat Pipeline
        front_llm.py         # processor + system prompt + tools
        hermes.py            # carried over; now tool-only
        voice_store.py       # carried over
      pipecat_processors/    # any custom processors
    tests/
  mobile/ios/HermesWhisper02/   # Swift app
    ServerRegistry/
    Audio/
    VoiceSocket.swift
    AudioPlayer.swift
  docs/
    20260510_REQUIREMENTS.md   # this file
    PROTOCOL.md                # to be authored
```

---

## 8. Risks

| Risk                                                              | Mitigation                                                                              |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Front LLM acknowledgment jitter perceived as "fake" / annoying    | Vary phrasing; suppress acks on trivial turns; A/B test with users                      |
| Server-side VAD adds latency vs. on-device VAD                    | Use Pipecat's interrupt strategy; tune VAD min-silence; measure NFR-1                   |
| Continuous uplink raises bandwidth cost on cellular               | Provide PTT-only mode; consider Opus uplink later                                       |
| Multi-server keychain handling bugs cause cross-profile token leaks | Strict per-profile keychain key derivation + tests                                      |
| Pipecat upstream churn                                            | Pin version; vendor any patched processors                                              |

---

## 9. Open questions / decisions needed before implementation

1. **Front LLM choice for v1** — Llama 3.2 3B via Ollama (local, zero per-call cost, requires GPU on avatar08) **vs.** Claude Haiku (lower latency floor, recurring API cost, Anthropic dependency). Pick one for v1; keep the abstraction.
2. **Ack pipeline shape** — serial (§6.3a) vs. parallel branches (§6.3b). Parallel is the architecturally correct choice but doubles implementation complexity.
3. **Uplink codec** — raw PCM16 is simplest but ~256 kbps. Opus uplink would be ~32 kbps but adds a Pipecat input transform.
4. **STT provider** — keep OpenAI Whisper (familiar, cloud) or switch to Deepgram (lower latency, streaming-native and a better fit for Pipecat's frame-by-frame model)?
5. **TTS provider** — OpenAI TTS (current) vs. Cartesia / ElevenLabs (lower TTFB, better for ack snappiness)?
6. **Server identity & TLS for additional servers** — does each profile require its own DNS + cert (Nginx style), or do we support direct LAN IP + self-signed for power users?
7. **Session resume across server-profile switch** — confirm v1 behavior: switching profiles ends sessions; no cross-server continuity.
8. **Auth refresh** — bearer tokens currently long-lived; do we add refresh tokens, or rely on re-2FA on expiry?
9. **Mobile minimum iOS version** — pin (proposed: iOS 17+, matches HermesVoice).
10. **Conversation memory ownership** — does the front LLM keep its own short-term memory, or always defer to Hermes for long-term context?
11. **Telemetry** — do we ship per-stage latency to a server-side dashboard (Grafana?) in v1, or only Loguru files?
12. **fsdc-avatar08 URL & port** — concrete public hostname + Nginx config for the v1 single registered entry (ops to provide).

---

## 10. Acceptance criteria (v1)

- [ ] Mobile app launches with the multi-server registry UI; one entry pre-populated for fsdc-avatar08.
- [ ] User can complete the 2FA login flow against fsdc-avatar08 and persist credentials in Keychain.
- [ ] User can hold-to-talk (or tap-to-toggle continuous), speak, and hear an acknowledgment within NFR-1.
- [ ] User hears a substantive Hermes answer within NFR-2.
- [ ] Speaking over the assistant cancels playback within NFR-3 and starts a new turn.
- [ ] Killing the app and relaunching restores the same active server profile and resumes the prior voice session by id.
- [ ] No client-side VAD code remains in the Swift project.
- [ ] FastAPI app's only audio orchestration code is the Pipecat pipeline + processors.
- [ ] Hermes is reachable only via the front LLM's `call_hermes` tool path.
