# HermesWhisper02 implementation continuation prompt

Use this prompt with an AI coding agent to continue implementation in this repository.

## Prompt

You are a coding agent on a Mac workstation. The repo is already cloned at:

`/Users/nick/Documents/HermesWhisper02`

Continue HermesWhisper02 implementation from the current branch. Work autonomously, but stop for genuine blockers that require a human decision.

## Read first

1. `AGENTS.md`
2. `mobile/AGENTS.md`
3. `api/AGENTS.md`
4. `README.md`
5. `api/README.md`
6. `mobile/README.md`
7. `docs/20260510_REQUIREMENTS.md`
8. `docs/20260510_PROTOCOL_V01.md`
9. `docs/20260510_PLAN_MOBILE_V01.md`
10. `docs/20260510_PLAN_API_V01.md`
11. `docs/ERROR_REQUIREMENTS.md`
12. `docs/LOGGING_PYTHON_V06.md`
13. `docs/TODO_LIST_GUIDANCE.md`
14. `docs/CommitMessagesGuidance.md`
15. `mobile/docs/device_bringup_5_5.md`

Skim `docs/archived/` only if decision history is needed. The previous May 11 handoff is archived because it pointed to `dev_01` and mobile phase 1, which are no longer current.

## Current branch

1. Work on branch `dev_02`.
2. Do not work directly on `main`.
3. Push `dev_02` after successful commits when asked.

## Current status

1. API phases 0 through 6b are implemented and committed.
2. The deployed API is reachable through:
   - `https://api.hermes-whisper.dashanddata.com/`
3. The user verified deployed API basics:
   - HTTPS routing works.
   - Auth login works.
   - Email 2FA works.
4. Mobile phases 0 through 5 are implemented and committed.
5. Mobile Phase 5.5 is partially complete:
   - Physical iPhone build and run passed.
   - Built-in microphone capture passed.
   - AirPods and Bluetooth HFP capture passed.
   - RMS responds to speaking.
   - Device notes are recorded in `mobile/docs/device_bringup_5_5.md`.
   - Playback fixture testing is still pending because playback is planned for Phase 7.
   - Phone-call interruption and mid-playback route recovery are still pending.
6. The app currently shows the debug voice screen with login, server controls, logout, and mic RMS controls.
7. The next implementation phase is mobile Phase 6.

## Important git rules

1. Keep phase commits scoped.
2. Do not amend commits.
3. Do not use `--no-verify`.
4. After each phase:
   - Implement the phase.
   - Run tests.
   - Run build/typecheck.
   - Check off completed plan boxes.
   - Commit with a message referencing the plan and phase.

## Next implementation step

Start with mobile Phase 6 in `docs/20260510_PLAN_MOBILE_V01.md`.

Implement:

1. `ProtocolEnvelope.swift`
   - Codable types for every frame in `docs/20260510_PROTOCOL_V01.md` section 4.
   - Use a discriminated union through the `type` field.
   - Round-trip all frame types in tests.

2. `VoiceSocket.swift`
   - Open `/ws/voice` using `URLSessionWebSocketTask`.
   - Use `Authorization: Bearer <token>`.
   - Refuse to open when `KeychainStore.loadValid(profileID:)` returns nil.
   - Implement `connect()`, `sendJSON(_:)`, `sendBinary(_:)`, and `close()`.
   - Expose `events: AsyncStream<VoiceEvent>`.
   - Pair JSON `audio_chunk` preludes with the following binary frame.
   - Close with a protocol error on binary-without-prelude, byte-count mismatch, duplicate `seq`, or out-of-order `seq`.
   - Add heartbeat ping every 15 seconds and require pong within 5 seconds.
   - Log backpressure and packet-to-playout timing hooks.

3. `VoiceController.swift`
   - Orchestrate `AudioCapture.frames` to `VoiceSocket.sendBinary`.
   - Receive socket events.
   - Prepare for playback handoff, but do not implement Phase 7 playback early.

4. Tests
   - Prefer an embedded `Network.framework` WebSocket server if practical.
   - Cover prelude-to-binary pairing.
   - Cover binary without prelude.
   - Cover byte-count mismatch.
   - Cover reconnect sending previous `session_id`.
   - Cover out-of-order and duplicate `seq`.
   - Cover `ProtocolEnvelope` round trips.

## Mobile commands

Run these from:

`mobile/ios/HermesWhisper02`

1. Run tests:

```bash
xcodebuild test \
  -project HermesWhisper02.xcodeproj \
  -scheme HermesWhisper02 \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

2. Build simulator app:

```bash
xcodebuild build \
  -project HermesWhisper02.xcodeproj \
  -scheme HermesWhisper02 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

3. Regenerate the project only if `project.yml` changes:

```bash
xcodegen generate
```

## API integration notes

1. Deployed base URL:
   - `https://api.hermes-whisper.dashanddata.com`
2. Local Mac API URL for simulator integration:
   - `http://127.0.0.1:8765`
3. Protocol source of truth:
   - `docs/20260510_PROTOCOL_V01.md`
4. Auth flow:
   - `POST /api/auth/login`
   - `POST /api/auth/verify`
   - Store bearer credentials per server profile in Keychain.
5. WebSocket:
   - `wss://api.hermes-whisper.dashanddata.com/ws/voice`
   - Use `Authorization: Bearer <token>`.
   - Send `client_hello` before audio frames.

## Stop and ask only for real blockers

Stop for:

1. Missing credentials needed for a phase.
2. Apple signing or physical-device availability blocking required device validation.
3. A requirements conflict that needs a design decision.
4. A protocol ambiguity that requires changing `docs/20260510_PROTOCOL_V01.md`.
5. A local toolchain failure that prevents required verification.

Do not stop for:

1. Normal lint or test failures you can fix.
2. Small implementation choices already covered by the plan.
3. Placeholder UI details outside the active phase.
4. Missing optional polish.

## Final report format

When done or blocked, report:

1. Phases completed.
2. Tests/builds run.
3. Commits created.
4. Push status.
5. Any blockers or skipped items with one-line reasons.
