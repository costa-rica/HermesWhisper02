# HermesWhisper02 mobile plan assessment, Codex

Date: 2026-05-10

Assessed file: `docs/20260510_PLAN_MOBILE_V01.md`

Summary:

The mobile plan is buildable and has a sensible SwiftUI/AVFoundation structure. The main risk is that the plan relies on server-side VAD for barge-in while the requirement measures silence from the moment the client mic detects renewed speech. Those two ideas are in tension. The best way to increase the chance of meeting the requirements is to add a small local interrupt detector that only stops playback and never defines utterance boundaries, or revise NFR-3 to measure from the server `user_started_speaking` event instead of client mic detection.

1. Fatal or near-fatal issues

- Potential fatal requirement mismatch: “No client-side VAD” conflicts with NFR-3 as written.
- NFR-3 says local playback must be silenced within 150 ms from client mic detecting renewed speech.
- The mobile plan waits for the server to send `user_started_speaking` before stopping playback.
- That round trip includes capture frame delay, WebSocket uplink, server VAD decision time, server event emission, WebSocket downlink, and client dispatch. It may work on a perfect LAN, but it is not a reliable way to hit 150 ms on real mobile networks.

2. Highest leverage alternative approach

- Add a local interrupt-only detector in `AudioCapture` or `VoiceController`.
- It should:
  1. Observe mic energy or use iOS voice-processing signal state while assistant audio is playing.
  2. Immediately call `AudioPlayer.flushAndStop()` when renewed speech is likely.
  3. Continue sending raw audio to the server.
  4. Never send `end_of_utterance`.
  5. Never replace server-side VAD for turn boundaries.
- This preserves the spirit of server-side VAD while making the playback silence requirement achievable.
- If strict “no client-side VAD of any kind” is non-negotiable, revise NFR-3 to measure from receipt of `user_started_speaking`, not from client mic detection.

3. WebSocket transport risk

- The mobile plan uses `URLSessionWebSocketTask` with raw PCM over TCP. That matches the current project protocol, but it is a latency and resilience risk for real-time media.
- Pipecat’s current transport guidance describes WebRTC as the recommended transport for client applications and WebSocket as more appropriate for telephony, server-to-server, or prototyping.
- If the project has flexibility, a WebRTC transport would greatly improve the odds for low-latency barge-in, jitter handling, reconnect behavior, and audio quality.
- If WebSocket remains fixed, add:
  1. jitter buffer metrics
  2. sequence validation per `turn_id` and `source`
  3. backpressure handling when `sendBinary` falls behind
  4. ping/pong or app-level heartbeat
  5. measured packet-to-playout timing logs

4. Physical device testing is needed earlier

- Several acceptance checks rely on simulator behavior, but mic capture, Bluetooth routing, voice processing IO, interruptions, lock-screen behavior, and speaker echo behavior must be tested on a physical iPhone.
- Move a minimal device test into Phase 5:
  1. capture live mic
  2. verify 640-byte frames
  3. play a known downlink PCM chunk
  4. verify route changes and interruption handling
- The simulator is fine for storage, auth, protocol encoding, and much of the UI. It should not be treated as proof of audio success.

5. Audio session and background behavior risk

- `UIBackgroundModes: audio` supports playback use cases, but continuous microphone capture and WebSocket streaming while locked can be constrained by iOS behavior and policy.
- Clarify v1 behavior:
  1. Voice sessions are foreground-only unless proven otherwise on device.
  2. Screen lock may continue downlink playback but should not be a core acceptance path for continuous listening.
  3. Route and interruption handling should always put the UI into an explicit recoverable state.

6. Keychain identity mismatch

- The requirements say credentials are keyed by profile `id`.
- The mobile plan uses `keychainRef`.
- This is workable only if `keychainRef` is immutable and initially derived from the profile id.
- Simpler option: remove `keychainRef` from the model and use `profile.id.uuidString` directly as the Keychain account.

7. WebSocket testability risk

- `URLProtocol` is useful for HTTP auth tests, but it is not a complete substitute for testing `URLSessionWebSocketTask` behavior.
- Keep the plan’s “tiny embedded Network.framework server” path and make it the primary WebSocket unit/integration test strategy.
- Add tests for:
  1. JSON prelude followed by binary message
  2. binary message without prelude closes with protocol error
  3. mismatched byte count closes with protocol error
  4. reconnect sends previous `session_id`
  5. duplicate or out-of-order audio sequence handling

8. Playback cancellation needs stronger ownership

- `AVAudioPlayerNode.stop()` and buffer flush are the right direction, but the plan should place all player mutations on one actor or serial queue.
- Add a `PlaybackActor` or equivalent serialization point for:
  1. enqueue
  2. schedule buffer
  3. flush
  4. route change
  5. interruption
- Reason: barge-in bugs often come from a buffer scheduled just after a stop/flush.

9. Auth expiry behavior

- `Credentials` includes `expiresAt`, but the plan should explicitly reject expired credentials before opening the WebSocket.
- On expiry:
  1. clear in-memory auth
  2. keep the profile
  3. return to login
  4. do not attempt reconnect with an expired token

10. Suggested edits to the mobile plan

- Add a Phase 5.5: physical-device audio and interrupt test.
- Add an interrupt-only local speech detector or revise NFR-3 measurement wording.
- Treat WebRTC as the preferred alternative if WebSocket latency fails early tests.
- Use `profile.id.uuidString` as the Keychain account, or define `keychainRef` as immutable and id-derived.
- Make a serial actor/queue responsible for all playback state.
- Make the Network.framework WebSocket test server explicit, not optional.

11. References checked

- Pipecat transport docs: https://docs.pipecat.ai/pipecat/learn/transports
- Project protocol: `docs/20260510_PROTOCOL_V01.md`
- Project requirements: `docs/20260510_REQUIREMENTS.md`
