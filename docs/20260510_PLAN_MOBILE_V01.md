# HermesWhisper02 — Mobile Implementation Plan v1

**Date:** 2026-05-10
**Scope:** `mobile/ios/HermesWhisper02/` only (Swift iOS app).
**Companion docs:** [`20260510_REQUIREMENTS.md`](20260510_REQUIREMENTS.md), [`20260510_PROTOCOL_V01.md`](20260510_PROTOCOL_V01.md), [`archived/20260510_REQUIREMENT_ISSUES_V01.md`](archived/20260510_REQUIREMENT_ISSUES_V01.md) (decision history), [`archived/20260510_PLAN_MOBILE_V01_ASSESSMENT_CODEX.md`](archived/20260510_PLAN_MOBILE_V01_ASSESSMENT_CODEX.md) (review folded into this plan).

This plan follows `docs/TODO_LIST_GUIDANCE.md` (per-phase: build, run XCTests, check off, commit referencing this file + phase).

---

## Decisions baked in

| Topic                  | v1 choice                                                                       |
| ---------------------- | ------------------------------------------------------------------------------- |
| iOS minimum            | iOS 17                                                                          |
| Xcode                  | Whatever ships with `xcode-select 2416` on the Mac                              |
| UI framework           | **SwiftUI** for screens, UIKit only where AVFoundation requires (audio engine)  |
| Bundle id              | `com.dashanddata.hermeswhisper02` (confirm with Apple Developer team)           |
| Distribution           | Local-install via Xcode in v1; TestFlight deferred                              |
| Concurrency            | `async/await` and `AsyncStream`; no Combine unless trivially convenient         |
| Server registry store  | JSON file in `Application Support`; Keychain account = `profile.id.uuidString`  |
| Audio uplink           | Raw PCM16 LE, 16 kHz mono, 20 ms frames (320 samples)                           |
| Audio downlink         | PCM16 LE, sample rate per `audio_chunk` prelude                                 |
| VAD                    | No on-device speech recognition VAD. A **small interrupt-only energy detector** (`BargeInDetector`) gates playback flush during assistant speech to meet NFR-3; it does not define utterance boundaries — server VAD does. |
| Background             | Voice sessions are **foreground-only** in v1 (Codex Mobile §5).                |
| Initial server         | One pre-populated profile pointing to `https://api.hermes-whisper.dashanddata.com` |
| Tests                  | XCTest unit tests for `ServerRegistry`, Keychain, JSON envelope; no UI tests v1 |

---

## Target file layout

```
mobile/ios/HermesWhisper02/
  HermesWhisper02.xcodeproj/
  HermesWhisper02/
    App/
      HermesWhisper02App.swift
      AppEnvironment.swift             # @Observable holding active profile, auth, ws state
    ServerRegistry/
      ServerProfile.swift              # struct ServerProfile (Codable); id is the Keychain account
      ServerRegistryStore.swift        # JSON file in App Support
      ServerRegistryView.swift         # SwiftUI list + add/edit/delete/reorder
      ServerProfileEditView.swift      # add/edit one profile
      ServerInfoProbe.swift            # GET /api/server/info
    Auth/
      AuthService.swift                # login, verify, current token, scoped to profile
      KeychainStore.swift              # SecItem wrapper, kSecAttrAccessibleAfterFirstUnlock
      LoginView.swift                  # email + password
      VerifyCodeView.swift             # 2FA 6-digit entry
    Voice/
      VoiceSocket.swift                # URLSessionWebSocketTask wrapper + heartbeat + seq validation
      ProtocolEnvelope.swift           # Codable for all v1 frames
      AudioCapture.swift               # AVAudioEngine input → PCM16 16kHz frames
      BargeInDetector.swift            # interrupt-only energy detector; flushes player only
      AudioPlayer.swift                # public surface; all mutations dispatch to PlaybackActor
      PlaybackActor.swift              # actor owning AVAudioPlayerNode state (enqueue/flush/route)
      VoiceController.swift            # @Observable orchestrator: capture ↔ socket ↔ player
      VoiceView.swift                  # main voice UI (talk button, transcript, state)
    Models/
      ProtocolVersion.swift
      AssistantState.swift
      TurnId.swift
    Util/
      Logger.swift                     # os.Logger wrapper, subsystem com.dashanddata.hw02
      ErrorEnvelope.swift              # mirrors ERROR_REQUIREMENTS.md
  HermesWhisper02Tests/
    ServerRegistryStoreTests.swift
    KeychainStoreTests.swift           # uses an in-memory shim; real Keychain in UI tests
    ProtocolEnvelopeTests.swift
    AudioCaptureFormatTests.swift
  HermesWhisper02UITests/              # parked; no tests in v1
  README.md
```

---

## Phase 0 — Xcode project scaffold

**Goal:** A buildable SwiftUI app that boots to a placeholder screen.

Tasks:

- [x] Create the Xcode project: SwiftUI App template, iOS 17, bundle id `com.dashanddata.hermeswhisper02`, organization name "Dash and Data".
- [x] Add the file layout above (empty Swift files with placeholders).
- [x] Configure `Info.plist`:
  - `NSMicrophoneUsageDescription` ("HermesWhisper needs the microphone to capture your voice.")
  - `UIBackgroundModes` includes `audio` (for downlink playback when screen locks)
  - `NSAppTransportSecurity`: default (TLS-only)
- [x] Add a custom log subsystem (`com.dashanddata.hw02`) to `Util/Logger.swift`.
- [x] First XCTest target with one passing test (sanity).

Acceptance:

- Project builds in Xcode for iOS 17 simulator.
- App launches to a "Hello, HermesWhisper02" placeholder.
- `xcodebuild test` runs the sanity test.

Commit: `chore: scaffold ios project (PLAN_MOBILE phase 0)`.

---

## Phase 1 — Server registry storage

**Goal:** Persist a list of `ServerProfile` to disk and round-trip via tests. No UI yet.

Tasks:

- [x] `ServerProfile.swift`: `id: UUID, displayName: String, baseURL: URL, notes: String?, authKind: AuthKind`. `AuthKind` is enum with `.bearer2FA` only in v1 (open enum-shaped for extension). Per Codex Mobile §6, **the Keychain account is `id.uuidString` directly** — no separate `keychainRef` field.
- [x] `ServerRegistryStore.swift`:
  - File path: `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "HermesWhisper02/server_registry.json")`.
  - API: `load() -> [ServerProfile]`, `save(_:)`, `add(_:)`, `update(_:)`, `delete(id:)`, `reorder(_:)`.
  - Pre-populate on first launch with one profile pointing at `https://api.hermes-whisper.dashanddata.com` named `fsdc-avatar08`.
- [x] Tests (`ServerRegistryStoreTests.swift`): write+read round-trip, pre-population on empty store, delete, reorder, update.

Acceptance:

- All registry tests pass.
- App still builds.

Commit: `feat: add server registry storage (PLAN_MOBILE phase 1)`.

---

## Phase 2 — Keychain credentials

**Goal:** Store and retrieve bearer tokens per profile, isolated by `keychainRef`.

Tasks:

- [x] `KeychainStore.swift`: wraps `SecItemAdd/Copy/Update/Delete` for `kSecClassGenericPassword`, service `com.dashanddata.hw02.credentials`, **account = `profile.id.uuidString`**. Use `kSecAttrAccessibleAfterFirstUnlock` per NFR-6.
- [x] Stored value: JSON `{ "token": "...", "expiresAt": ISO8601, "email": "..." }`.
- [x] API: `save(profileID: UUID, credentials: Credentials)`, `load(profileID: UUID) -> Credentials?`, `delete(profileID: UUID)`. Also expose a strict `loadValid(profileID:) -> Credentials?` that returns nil for expired credentials (Codex Mobile §9).
- [x] Tests: in-memory shim for unit tests; a separate UI-test target later for a real-Keychain check (deferred).

Acceptance:

- Unit tests pass.
- Saving + loading + deleting round-trips through the shim.
- Cross-profile isolation verified by storing two refs and asserting independence.

Commit: `feat: add keychain credential store (PLAN_MOBILE phase 2)`.

---

## Phase 3 — Auth service + login UI

**Goal:** User can log in to the pre-populated server profile and persist the token.

Tasks:

- [x] `AuthService.swift`: `init(profile: ServerProfile, keychain: KeychainStore)`. Methods: `login(email:password:) async throws`, `verify(email:code:) async throws -> Credentials`, `currentCredentials() -> Credentials?`, `logout()`.
- [x] HTTP via `URLSession`. Decode `ErrorEnvelope` on non-2xx and throw a typed error.
- [x] `LoginView.swift`: email + password, "Send code" button → calls `login`, navigates to `VerifyCodeView`.
- [x] `VerifyCodeView.swift`: 6-digit code field; calls `verify`; on success, save credentials to Keychain and pop to main.
- [x] `AppEnvironment.swift`: `@Observable` model holding `activeProfile`, `credentials`, `isAuthenticated`. Wire `LoginView` → `VerifyCodeView` → `VoiceView` (placeholder for now).
- [x] Tests: `AuthService` against a stubbed `URLProtocol` mock — happy path, bad credentials, expired code.

Acceptance:

- A user can complete the email-code flow end-to-end against a running API and land on the placeholder voice view.
- Unit tests pass with mocked HTTP.

Commit: `feat: add auth service and login flow (PLAN_MOBILE phase 3)`.

---

## Phase 4 — Server registry UI

**Goal:** User can list, add, edit, reorder, delete, and switch active profile.

Tasks:

- [x] `ServerRegistryView.swift`: SwiftUI `List` with swipe-to-delete and `EditMode` for reorder. Tapping a profile sets it active; tap-and-hold or chevron opens edit.
- [x] `ServerProfileEditView.swift`: form with `displayName`, `baseURL`, optional `notes`. "Probe" button calls `ServerInfoProbe.fetch(baseURL)` and validates the URL + auto-fills `displayName` if blank.
- [x] `ServerInfoProbe.swift`: `GET /api/server/info`, returns the parsed payload or throws.
- [x] On switching active profile: tear down any open WS (`VoiceController.disconnect()`), clear in-memory credentials, navigate to `LoginView` if the new profile has no valid token.
- [x] Surface active server name in the main voice screen header.
- [x] Tests: probe parses `server/info` payload; switching profiles invalidates in-memory state.

Acceptance:

- All five operations (add, edit, rename, reorder, delete) work in the simulator.
- Switching profiles consistently lands on `LoginView` or `VoiceView` based on credentials.

Commit: `feat: add server registry ui (PLAN_MOBILE phase 4)`.

---

## Phase 5 — Audio capture (mic → PCM16)

**Goal:** Capture mic audio and emit 16 kHz mono PCM16 frames suitable for upload.

Tasks:

- [x] `AudioCapture.swift`:
  - `AVAudioEngine` input tap at the device's native rate (commonly 44.1 / 48 kHz, Float32).
  - Resample to 16 kHz mono using `AVAudioConverter`.
  - Convert to `Int16` little-endian.
  - Emit `Data` chunks of 320 samples (20 ms) via `AsyncStream<Data>`.
  - Configure `AVAudioSession` with category `.playAndRecord`, mode `.voiceChat`, options `[.defaultToSpeaker, .allowBluetoothHFP]`. AGC/echo are handled by the iOS voice processing IO.
- [x] Handle interruptions (phone call) and route changes (headphone unplug) by pausing/resuming the stream.
- [x] Tests (`AudioCaptureFormatTests.swift`): feed a known-frequency Float32 buffer through the resampler+converter, assert 16 kHz Int16 output of the expected sample count.

Acceptance:

- [x] A debug screen can show the rolling RMS of captured frames, proving live capture works.
- [x] Frame size is exactly 640 bytes (320 samples × 2 bytes) per chunk.

Commit: `feat: add audio capture pipeline (PLAN_MOBILE phase 5)`.

---

## Phase 5.5 — Physical-device audio bring-up

**Goal:** Validate capture and a known downlink chunk on a real iPhone before any pipeline integration. Codex Mobile §4 flags simulator-only success as a real risk for AVFoundation work.

Tasks:

- [x] Build & run on a physical iPhone (iOS 17+).
- [x] Verify mic capture: 16 kHz mono PCM16, 640-byte frames, RMS responds to speaking.
- [ ] Verify playback of a bundled fixture PCM16 chunk through `PlaybackActor` (introduced in Phase 7) or a temporary direct path.
- [ ] Verify route changes: unplug headphones mid-playback, accept a phone-call interruption (`AVAudioSession.interruptionNotification`), reconnect Bluetooth — the audio session recovers and the UI lands in an explicit recoverable state.
- [x] Capture screenshots / a short device log into `mobile/docs/device_bringup_5_5.md` for the record.

Acceptance:

- Capture and playback both work on the physical device.
- Route changes and interruptions do not require a force-quit.

Commit: `chore: physical device audio bring-up notes (PLAN_MOBILE phase 5.5)`.

---

## Phase 6 — WebSocket client + protocol envelope

**Goal:** Connect to `/ws/voice`, exchange `client_hello`/`session_started`, and stream uplink audio.

Tasks:

- [ ] `ProtocolEnvelope.swift`: Codable types for every frame in `20260510_PROTOCOL_V01.md` §4. Discriminated union via `type` field. Encode/decode with `JSONDecoder` + a small dispatch helper.
- [ ] `VoiceSocket.swift`:
  - `URLSession.shared.webSocketTask(with: request)` with `Authorization: Bearer ...` header. **Pre-flight:** refuse to open if `KeychainStore.loadValid(profileID:)` returns nil (expired token → return to login per Codex Mobile §9).
  - `connect()`, `sendJSON(_:)`, `sendBinary(_:)`, `close()`.
  - `events: AsyncStream<VoiceEvent>` where `VoiceEvent` is `.json(ServerFrame) | .binaryAudio(audioChunkPrelude, Data) | .closed(Error?)`.
  - **Audio prelude pairing:** when a JSON `audio_chunk` arrives, store it as "expected next binary"; when the next binary frame arrives, pair them and emit `.binaryAudio`. If the order ever inverts, log + close with a protocol error.
  - **Observability hooks** (Codex Mobile §3): app-level heartbeat (`{"type":"ping"}` every 15 s, expects `{"type":"pong"}` within 5 s), per-`turn_id`/`source` `seq` validation (out-of-order or duplicate → log + close), backpressure log when `sendBinary` queue depth exceeds a threshold, and packet-to-playout timing logs. These let us decide post-v1 whether to migrate to WebRTC with data, not guesswork.
- [ ] `VoiceController.swift`: orchestrate `AudioCapture.frames → VoiceSocket.sendBinary` and `VoiceSocket.events → PlaybackActor.enqueue` (PlaybackActor in next phase).
- [ ] **Tests use an embedded `Network.framework` WS server as the primary test path** (Codex Mobile §7 — not optional). Cover: prelude→binary pairing happy path; binary without prelude closes with protocol error; prelude byte count mismatch closes with protocol error; reconnect sends previous `session_id`; out-of-order / duplicate `seq` closes with protocol error; `ProtocolEnvelopeTests` round-trips every frame type.

Acceptance:

- App connects to the API, sends `client_hello`, receives `session_started`, and uplinks audio (verified by API logs showing per-frame timing).

Commit: `feat: add voice websocket client (PLAN_MOBILE phase 6)`.

---

## Phase 7 — TTS playback + local barge-in detector

**Goal:** Play downlink audio chunks; cut off playback the moment renewed user speech is detected locally (NFR-3 ≤ 150 ms), with the server `user_started_speaking` event as a backup path.

Tasks:

- [ ] `PlaybackActor.swift` (Codex Mobile §8): a Swift `actor` owning **all** mutations of `AVAudioEngine` / `AVAudioPlayerNode`. Methods: `enqueue(format:, sampleRate:, pcm16:)`, `flushAndStop()`, `handleRouteChange(...)`, `handleInterruption(...)`. No callers may touch the player node directly. Internally maintain a small ring buffer (target 60 ms) to absorb network jitter.
- [ ] `AudioPlayer.swift`: thin public surface that forwards to `PlaybackActor`. Existing call sites use this; only `PlaybackActor` knows about `AVAudioPlayerNode`.
- [ ] `BargeInDetector.swift`: interrupt-only energy detector per FR-2.4(a).
  - Active **only** while `PlaybackActor` reports it is currently playing assistant audio.
  - Computes RMS over a 50 ms window of incoming mic frames; if RMS exceeds a tuned threshold for ≥ 2 consecutive windows, fire `onLikelySpeech`.
  - Does **not** define utterance boundaries, does **not** signal `end_of_utterance`, does **not** modify uplink. Mic frames continue to be sent to the server unchanged.
  - Threshold and window tunables in code (`BargeInDetector.Config`); revisit on the device after Phase 5.5.
- [ ] In `VoiceController`:
  - On `BargeInDetector.onLikelySpeech` → immediately `await playbackActor.flushAndStop()`. **Target ≤ 150 ms** end-to-end (mic-frame-arrival → playback-silenced).
  - On server `user_started_speaking` → also call `flushAndStop()` (idempotent backup path; covers cases where the local detector misses).
  - On `turn_end {canceled: true}` → clear per-turn state.
- [ ] Tests:
  - Feed a known-loud Float32 buffer to `BargeInDetector` while it is "active"; assert it fires within 100 ms of synthetic onset.
  - Feed the same buffer while it is "inactive" (no playback); assert it does NOT fire.
  - Concurrency test: rapid `enqueue`/`flushAndStop` interleavings on `PlaybackActor` never schedule a buffer after a flush.
- [ ] Manual on-device barge-in test (extends Phase 5.5 device): speak over the assistant; measure mic-RMS-onset → silence by listening + log timestamps.

Acceptance:

- A full ack + answer plays cleanly with no clicks or gaps.
- Barge-in cancels mid-answer.

Commit: `feat: add tts playback with barge-in (PLAN_MOBILE phase 7)`.

---

## Phase 8 — Push-to-talk and continuous modes

**Goal:** Both interaction modes work and persist across launches.

Tasks:

- [ ] Add a settings toggle on `VoiceView`: PTT vs. continuous. Persist to `UserDefaults` per profile.
- [ ] PTT mode: `AudioCapture` only emits frames while the talk button is pressed; `client_hello.ptt_mode = true`.
- [ ] Continuous mode: capture runs while the voice screen is active; `ptt_mode = false`.
- [ ] In both modes, server VAD still drives turn boundaries; client never sends an `end_of_utterance` signal.
- [ ] Visual state: show `assistant_state` (`ack`/`thinking`/`answering`/`idle`) on the voice screen.

Acceptance:

- Both modes work end-to-end in the simulator and on a physical device.
- Mode survives app relaunch.

Commit: `feat: add ptt and continuous modes (PLAN_MOBILE phase 8)`.

---

## Phase 9 — Reconnect + session resume

**Goal:** Transient WS drops resume cleanly within NFR-5 (≤ 2 s).

Tasks:

- [ ] In `VoiceSocket`, on `.closed(error)` while the user expects a session, reconnect with exponential backoff (200 ms → 1 s, max 3 attempts) before surfacing an error.
- [ ] On reconnect, send `client_hello.session_id = previousSessionId`.
- [ ] On `session_started.resumed=true`, transparently continue. On `resumed=false`, surface a small toast ("Reconnected; previous turn lost.") and reset turn state.
- [ ] Tests: simulate a `URLSession` close mid-turn; assert reconnect attempts and final state.

Acceptance:

- Killing the API for < 2 s and bringing it back lets a session continue without app interaction.

Commit: `feat: add reconnect with session resume (PLAN_MOBILE phase 9)`.

---

## Phase 10 — Polish & docs

Tasks:

- [x] Author `/mobile/AGENTS.md` per D-1.
- [x] Author `mobile/README.md`: simulator quickstart, physical-device cabling, signing notes.
- [ ] Confirm acceptance criteria (REQ §10) for the mobile side.
- [ ] Tag `mobile/v0.1.0` in git.

Commit: `docs: agents.md and v0.1.0 polish (PLAN_MOBILE phase 10)`.

---

## Cross-cutting policies

- **No client-side VAD for utterance boundaries.** Server VAD is authoritative. The `BargeInDetector` is an interrupt-only energy detector — it does not produce transcripts and does not signal `end_of_utterance`. See FR-2.1 / FR-2.4 clarification.
- **No on-device STT/TTS.** Confirmed by FR-2.x.
- **No Combine framework** unless trivially used by SwiftUI bindings. Stick to async/await.
- **No third-party Swift packages** in v1 unless absolutely necessary. Apple frameworks only (Foundation, AVFoundation, Network, Security, SwiftUI). If a package is needed (e.g., for Keychain ergonomics), justify in PR.
- **Logging.** `os.Logger` only; never `print`. No PII (email, tokens) at info level.
- **Secrets.** No API keys live on the device. Only the bearer token issued by the server lives in Keychain.

## Risks specific to this plan

| Risk                                                        | Mitigation                                                        |
| ----------------------------------------------------------- | ----------------------------------------------------------------- |
| AVAudioEngine resampler quirks on physical devices          | Phase 5 includes a unit test for sample math; manual device check |
| Barge-in latency missing NFR-3 (≤ 150 ms)                   | Use `AVAudioPlayerNode.stop()` + buffer flush; measure on device  |
| WS header auth blocked by some proxies                      | Fallback `?token=` query supported by API behind a flag           |
| Background audio playback cut by iOS                        | `UIBackgroundModes: audio` declared; test screen-lock behavior   |
| Keychain test flakiness                                     | Unit-test against an in-memory shim; real Keychain in UI tests    |
