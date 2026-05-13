# TODO Mobile V02: UI Reorganization, Local Conversation History, Resume Plumbing

Date: 2026-05-13
Supersedes: docs/archived/20260513_TODO_MOBILE_UI_HISTORY.md
Triggered by: docs/archived/20260513_TODO_MOBILE_UI_HISTORY_ASSESSMENT_CODEX.md
Anchor: docs/20260513_REQUIREMENTS_UI_HISTORY_V02.md
Pairs with: docs/20260513_TODO_API_RUNTIME_CONFIG_V02.md

Conventions:

- No third-party Swift packages. Use the system SQLite3 C API.
- SwiftUI first; UIKit only where required by audio.
- Tests use XCTest under HermesWhisper02Tests.
- Regenerate the Xcode project with `xcodegen generate` after editing project.yml.

## Changes from V01

- Added store upsert (`upsertSession`) because `session_started` may return an existing session id and the V01 `createSession` alone would risk duplicate primary keys.
- Persistence trigger now uses pending in-memory buffers and commits on `turn_end` (not canceled), and depends on the new API `assistant_text` frame for assistant text. No assistant text means no assistant row.
- Promoted `VoiceController.startSession(resumeSessionID:)` to its own phase before the drawer so the data plumbing is in place when the UI lands.
- Drawer first ships as a `.sheet` from the leading edge; the custom slide-out is optional polish later.
- Drawer list reloads after each successful commit via a published store change signal.

## Phase 1 — Local conversation store

Tasks:

- [x] Add group `mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/`.
- [x] Add `Conversation/ConversationModels.swift` with `ConversationSession` and `ConversationMessage` mirroring the V02 schema.
- [x] Add `Conversation/ConversationStore.swift` using the SQLite3 C API. DB path: `Application Support/HermesWhisper02/conversations/<server_profile_id>.sqlite`. Create tables on first open.
- [x] Public API:
  - `upsertSession(id: String, hermesConversationID: String, title: String?) throws -> ConversationSession`
  - `appendMessage(sessionID:, turnID:, role:, text:, final:, metadata:) throws -> ConversationMessage`
  - `listSessions(includeArchived:) throws -> [ConversationSession]`
  - `loadMessages(sessionID:) throws -> [ConversationMessage]`
  - `deleteSession(sessionID:) throws`
  - `updateSessionPreview(sessionID:, preview:, lastUpdated:) throws`
  - A `@Published` change signal on the store wrapper for reactive UI reloads.
- [x] Update project.yml to include the new group; run `xcodegen generate`.
- [x] Unit tests: insert/list ordering, message ordering, per-server file isolation, upsert idempotency, delete.

Checks before checking off:

- [x] `xcodebuild test -project HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'platform=iOS Simulator,name=iPhone 17'` passes.

Commit: `feat(mobile): local conversation store (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 1)`.

## Phase 2 — VoiceController persistence with turn_end commit

Depends on API V02 phases 1 and 3 (`assistant_text` frame defined and emitted).

Tasks:

- [x] Extend `App/AppEnvironment.swift` to own the active `ConversationStore` and switch DB file on `switchActiveProfile(_:)`.
- [x] In `Voice/VoiceController.swift`:
  - [x] On `session_started`, call `store.upsertSession(id: session_id, hermesConversationID: conversation_id, title: nil)`.
  - [x] Maintain a per-turn pending buffer: `(turnID, pendingUserText, pendingAssistantText)`.
  - [x] On final transcript: fill `pendingUserText`.
  - [x] On `assistant_text { final: true }`: fill `pendingAssistantText`.
  - [x] On `turn_end { canceled: false }`: commit both messages via `appendMessage`; update preview and message_count.
  - [x] On `turn_end { canceled: true }`: discard pending assistant text. Persist user message only if it has already finalized (design decision in this phase — default is to discard the entire pair to keep history clean; document in code).
- [x] Tests: feed a mock turn end-to-end and assert both rows persist; feed a canceled turn and assert no assistant row.

Checks before checking off:

- [x] `xcodebuild test` passes.

Commit: `feat(mobile): turn-aware persistence (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 2)`.

## Phase 3 — Resume plumbing

Tasks:

- [ ] Add `VoiceController.startSession(resumeSessionID: String?)` that threads the optional id into the WebSocket client.
- [ ] Update `VoiceSocket` (or the `ClientHelloFrame` builder) to include `session_id` in `client_hello` when provided.
- [ ] Tests: build a `client_hello` with a resume id; assert the JSON contains `session_id` and the right shape.

Checks before checking off:

- [ ] `xcodebuild test` passes.

Commit: `feat(mobile): resume plumbing (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 3)`.

## Phase 4 — Main screen layout refactor

Tasks:

- [ ] Refactor `Voice/VoiceView.swift`:
  - [ ] Top bar at top of safe area: hamburger (left), tappable server-name title (center, multiline, large font like today's "Hello"), gear (right), modest side padding.
  - [ ] Tap server name presents the existing `ServerRegistryView` as a `.sheet`.
  - [ ] Compact status block under the title: Mic RMS, assistant state, Hermes activity strip, Start/Stop button. No behavior change to that block.
  - [ ] Remove the "Hello, HermesWhisper02" text.
  - [ ] Remove the standalone Servers and Logout buttons.
- [ ] Add `Conversation/ConversationTranscriptView.swift`:
  - [ ] `ScrollViewReader` with auto-scroll to newest.
  - [ ] User bubbles align trailing; assistant bubbles align leading.
  - [ ] Each bubble `<= 0.80 * parent width`.
  - [ ] `.textSelection(.enabled)` per bubble's text.
  - [ ] Distinct background and corner styles per role.
- [ ] Use the transcript view as the bottom portion of `VoiceView`. Feed from a published list combining the persisted current session with any in-flight live transcript.

Checks before checking off:

- [ ] `xcodebuild test` passes.
- [ ] Manual sim check: long server names wrap; transcript scrolls; selection works per bubble.

Commit: `feat(mobile): new main screen layout (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 4)`.

## Phase 5 — Drawer with conversation history (sheet first)

Tasks:

- [ ] Add `Conversation/ConversationHistoryView.swift` presented from the hamburger as a `.sheet` (leading edge feel via `.presentationDetents([.large])`; iPad slide-out can come later).
- [ ] Header shows the active server name (smaller, non-tappable).
- [ ] List rows: preview, updated_at (relative), message_count.
- [ ] Tap pushes `Conversation/ConversationDetailView.swift` (read-only; reuses `ConversationTranscriptView`).
- [ ] Detail screen has a Resume button:
  - [ ] Enabled only after API V02 phase 7 ships (long-gap resume). Until then, render as a disabled button with a tooltip.
  - [ ] Tapping Resume calls `VoiceController.startSession(resumeSessionID: session.id)`.
- [ ] Swipe-to-delete removes the local row only. Use label "Remove from this device" in the trailing swipe action.
- [ ] Reload list reactively on store change publisher (refreshes after every committed turn).
- [ ] On active profile switch, the view loads from the new `ConversationStore`.

Tests:

- [ ] Add a second server profile in test fixtures; verify the drawer list returns only the active profile's sessions.
- [ ] Verify the list updates after a `turn_end` commit.

Checks before checking off:

- [ ] `xcodebuild test` passes.
- [ ] Manual sim check: drawer opens, detail renders, Resume re-opens the WebSocket once API V02 phase 7 lands.

Commit: `feat(mobile): conversation history drawer (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 5)`.

## Phase 6 — Settings sheet

Tasks:

- [ ] Add `Settings/SettingsView.swift` presented from the gear button as a `.sheet`.
- [ ] Add `Settings/RuntimeSettingsStore.swift`, a UserDefaults wrapper keyed by `profile.id.uuidString`, exposing:
  - `intermediaryMode: IntermediaryMode` (deterministic or llm; default llm)
  - `speechRmsThreshold`, `endSilenceSeconds`, `minTurnSeconds`, `maxTurnSeconds`
  - `bargeInRmsThreshold`, `bargeInWindowDuration`, `bargeInConsecutiveWindows`
- [ ] Settings sections:
  - [ ] Intermediary routing segmented picker. On change, if WS open, call `VoiceController.sendIntermediaryMode(_:)` (sends `set_intermediary_mode`). Persist always.
  - [ ] VAD sliders. On commit, call `VoiceController.sendAudioParams(_:)` (sends `set_audio_params`). Persist.
  - [ ] Barge-in sliders. On change, mutate the live `BargeInDetector.Config` through `VoiceController.updateBargeInConfig(_:)`. Persist.
  - [ ] Voice interaction mode picker moved from `VoiceView`.
  - [ ] Logout button calling existing `appEnvironment.logout()`.
- [ ] On `client_hello`, include the persisted `intermediary_mode` and `audio_params` so the API starts in the right state.
- [ ] UI copy in Settings should note: "Changes apply at the next turn." (matches V02 protocol semantics.)

Checks before checking off:

- [ ] `xcodebuild test` passes.
- [ ] Manual sim check: flip intermediary mid-conversation; observe `runtime_config_applied`; observe next turn uses the chosen path. Move sliders; observe ack and next-turn behavior.

Commit: `feat(mobile): settings sheet (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 6)`.

## Phase 7 — Polish, accessibility, verification

Tasks:

- [ ] Dynamic Type checks on the server title and bubbles.
- [ ] VoiceOver labels for hamburger, gear, and the server-name button.
- [ ] Safe-area checks on iPhone SE and iPhone 17.
- [ ] Regenerate the Xcode project: `xcodegen generate`.
- [ ] Full test pass: `xcodebuild test -project HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'platform=iOS Simulator,name=iPhone 17'`.
- [ ] Manual two-server scenario: add a second profile, switch, confirm independent drawer history.
- [ ] Manual long-gap Resume scenario after API V02 phase 7 lands.
- [ ] Optional: replace the sheet-based drawer with a true slide-out if priorities allow.

Commit: `chore(mobile): polish and a11y (20260513_TODO_MOBILE_UI_HISTORY_V02 phase 7)`.

## Critical files

Modified:

- mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceView.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceController.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceSocket (or equivalent client_hello builder)
- mobile/ios/HermesWhisper02/HermesWhisper02/App/AppEnvironment.swift
- mobile/ios/HermesWhisper02/project.yml

Added:

- mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/ConversationModels.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/ConversationStore.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/ConversationTranscriptView.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/ConversationHistoryView.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/ConversationDetailView.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Settings/SettingsView.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Settings/RuntimeSettingsStore.swift

Reused:

- ServerRegistry/ServerRegistryView.swift (presented from the server-name title)
- ServerRegistry/ServerProfile.swift (stable UUID used as scope key)
- Voice/BargeInDetector.swift (config mutable at runtime)
- Voice/HermesActivityView (kept in the compact status block)

## Dependencies on API V02

- Phase 2 (mobile) depends on API V02 phases 1 and 3 (assistant_text frame).
- Phase 5 (mobile drawer Resume enabling) depends on API V02 phase 7 (long-gap resume, including Hermes session propagation).
- Phase 6 (mobile settings) depends on API V02 phases 4 and 5 (runtime config and live frames).
