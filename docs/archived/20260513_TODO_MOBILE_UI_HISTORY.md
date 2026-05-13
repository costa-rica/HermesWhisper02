# TODO Mobile: UI Reorganization and Local Conversation History

Date: 2026-05-13
Anchor: docs/20260513_REQUIREMENTS_UI_HISTORY.md
Pairs with: docs/20260513_TODO_API_RUNTIME_CONFIG.md

Conventions:

- No third-party Swift packages. Use the system SQLite3 C API.
- SwiftUI first; UIKit only where required by audio.
- Tests use XCTest under HermesWhisper02Tests.
- Regenerate the Xcode project with `xcodegen generate` after editing project.yml.

## Phase 1 — Local conversation store

Tasks:

- [ ] Add group `mobile/ios/HermesWhisper02/HermesWhisper02/Conversation/`.
- [ ] Add `Conversation/ConversationModels.swift` with `ConversationSession` and `ConversationMessage` Swift structs that mirror the schema in the requirements doc.
- [ ] Add `Conversation/ConversationStore.swift` using the SQLite3 C API. DB path: `Application Support/HermesWhisper02/conversations/<server_profile_id>.sqlite`. Create tables on first open.
- [ ] Public API on the store:
  - `createSession(hermesConversationID:) throws -> ConversationSession`
  - `appendMessage(sessionID:, turnID:, role:, text:, final:, metadata:) throws -> ConversationMessage`
  - `listSessions(includeArchived:) throws -> [ConversationSession]`
  - `loadMessages(sessionID:) throws -> [ConversationMessage]`
  - `deleteSession(sessionID:) throws`
  - `updateSessionPreview(sessionID:, preview:, lastUpdated:) throws`
- [ ] Update project.yml to include the new group.
- [ ] Unit tests covering insert, list ordering by `updated_at DESC`, message ordering by `created_at ASC`, scoping per server profile file, and delete.

Checks before checking off:

- [ ] `xcodebuild test -project HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'platform=iOS Simulator,name=iPhone 17'` passes.

Commit message reference: `20260513_TODO_MOBILE_UI_HISTORY phase 1`.

## Phase 2 — Wire store into AppEnvironment and VoiceController

Tasks:

- [ ] Extend `App/AppEnvironment.swift` to own the active `ConversationStore`.
- [ ] On `switchActiveProfile(_:)`, close the current store and open a new one for the new server profile id.
- [ ] In `Voice/VoiceController.swift`:
  - [ ] On receipt of `session_started`, create or look up a local `ConversationSession` row by `session_id` and persist `hermes_conversation_id`.
  - [ ] When a turn completes (`HermesProgressKind.finished`), append a user message (final transcript text, `role = "user"`) and an assistant message (latest assistant text, `role = "assistant"`).
  - [ ] Update `last_message_preview`, `message_count`, and `updated_at` on the session row.
- [ ] Tests: feed a mock turn end-to-end through `VoiceController` and assert two rows persisted with the correct `turn_id`, ordering, and session metadata.

Checks before checking off:

- [ ] `xcodebuild test` passes.

Commit message reference: `20260513_TODO_MOBILE_UI_HISTORY phase 2`.

## Phase 3 — Main screen layout refactor

Tasks:

- [ ] Refactor `Voice/VoiceView.swift`:
  - [ ] Top bar at top of safe area: hamburger button (left), tappable server-name title (center, multiline, large font matching today's "Hello" size), gear button (right), modest side padding.
  - [ ] Tap server name presents the existing `ServerRegistryView` as a `.sheet`.
  - [ ] Compact status block under the title with Mic RMS, assistant state, Hermes activity strip, and the Start or Stop button (lift the existing block up; no behavior change).
  - [ ] Remove the "Hello, HermesWhisper02" text.
  - [ ] Remove the standalone Servers button and standalone Logout button.
- [ ] Add `Conversation/ConversationTranscriptView.swift` rendering bubbles in a `ScrollViewReader` with auto-scroll to newest:
  - [ ] User bubbles align trailing; assistant bubbles align leading.
  - [ ] Each bubble width `<= 0.80 * parent width`.
  - [ ] `.textSelection(.enabled)` on each bubble's text.
  - [ ] Distinct backgrounds and corner styles per role.
- [ ] Use `ConversationTranscriptView` as the bottom portion of `VoiceView`, fed from a published list on `VoiceController` that combines the persisted current session with any in-flight live transcript.

Checks before checking off:

- [ ] `xcodebuild test` passes.
- [ ] Manual sim check: layout renders, server name wraps when long, transcript scrolls and selection works.

Commit message reference: `20260513_TODO_MOBILE_UI_HISTORY phase 3`.

## Phase 4 — Hamburger drawer with conversation history

Tasks:

- [ ] Add `Conversation/ConversationHistoryView.swift` as a left slide-out drawer (custom `.offset` plus drag gesture; falls back to a `.sheet` if the gesture is awkward).
- [ ] Drawer header shows the active server name (smaller, non-tappable).
- [ ] List rows show preview, updated_at (relative formatter), and message_count.
- [ ] Tap pushes `Conversation/ConversationDetailView.swift`, a read-only screen reusing `ConversationTranscriptView`.
- [ ] Detail screen has a Resume button that calls `VoiceController.startSession(resumeSessionID: session.id)`.
- [ ] Swipe-to-delete removes the local row only and refreshes the list.
- [ ] When active profile changes, the drawer reloads its list from the new `ConversationStore`.

Tests:

- [ ] Add a second server profile in the test fixture, write sessions under each, verify the drawer-backing list returns only the active profile's sessions.

Checks before checking off:

- [ ] `xcodebuild test` passes.
- [ ] Manual sim check: drawer opens, displays sessions, detail view renders, Resume re-opens the WebSocket.

Commit message reference: `20260513_TODO_MOBILE_UI_HISTORY phase 4`.

## Phase 5 — Settings sheet

Tasks:

- [ ] Add `Settings/SettingsView.swift` presented from the gear button as a `.sheet`.
- [ ] Add `Settings/RuntimeSettingsStore.swift`, a UserDefaults wrapper keyed by `profile.id.uuidString`, exposing:
  - `intermediaryMode: IntermediaryMode` (deterministic or llm; default llm)
  - `speechRmsThreshold`, `endSilenceSeconds`, `minTurnSeconds`, `maxTurnSeconds`
  - `bargeInRmsThreshold`, `bargeInWindowDuration`, `bargeInConsecutiveWindows`
- [ ] Settings sections:
  - [ ] Intermediary mode segmented picker. On change, if WS open, call `VoiceController.sendIntermediaryMode(_:)` which sends `set_intermediary_mode`. Persist always.
  - [ ] Audio (VAD) sliders. On commit, call `VoiceController.sendAudioParams(_:)` which sends `set_audio_params`. Persist.
  - [ ] Barge-in sliders. On change, mutate the live `BargeInDetector.Config` through `VoiceController.updateBargeInConfig(_:)`. Persist.
  - [ ] Voice interaction mode picker moved from `VoiceView`.
  - [ ] Logout button calling existing `appEnvironment.logout()`.
- [ ] On `client_hello`, include the persisted `intermediary_mode` and `audio_params` so the API starts in the correct state.

Checks before checking off:

- [ ] `xcodebuild test` passes.
- [ ] Manual sim check: toggle intermediary mid-conversation, observe ack frame, observe next turn uses the chosen path; move sliders, observe `runtime_config_applied`.

Commit message reference: `20260513_TODO_MOBILE_UI_HISTORY phase 5`.

## Phase 6 — Polish, accessibility, and verification

Tasks:

- [ ] Dynamic Type checks on the server title and bubbles.
- [ ] Voice Over labels on hamburger, gear, and server-name button.
- [ ] Confirm safe-area behavior on iPhone SE (small screen) and iPhone 17 (notch).
- [ ] Regenerate the Xcode project: `xcodegen generate`.
- [ ] Full test pass: `xcodebuild test -project HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'platform=iOS Simulator,name=iPhone 17'`.
- [ ] Manual two-server scenario: add a second profile, switch, confirm independent drawer history.
- [ ] Manual long-gap Resume scenario in pair with the API phase 6 work.

Commit message reference: `20260513_TODO_MOBILE_UI_HISTORY phase 6`.

## Critical files

Modified:

- mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceView.swift
- mobile/ios/HermesWhisper02/HermesWhisper02/Voice/VoiceController.swift
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

- ServerRegistry/ServerRegistryView.swift (presented as a sheet from the server-name title)
- ServerRegistry/ServerProfile.swift (stable UUID used as scope key)
- Voice/BargeInDetector.swift (config now mutable at runtime)
- Voice/HermesActivityView (kept in the compact status block)
