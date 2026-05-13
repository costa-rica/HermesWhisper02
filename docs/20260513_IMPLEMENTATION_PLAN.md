# Implementation plan

Date: 2026-05-13

This plan describes the recommended order for implementing the V02 UI history, runtime config, and resume work across:

- `docs/20260513_REQUIREMENTS_UI_HISTORY_V02.md`
- `docs/20260513_TODO_API_RUNTIME_CONFIG_V02.md`
- `docs/20260513_TODO_MOBILE_UI_HISTORY_V02.md`

## 1. Start with API protocol and server foundations

- Implement `docs/20260513_TODO_API_RUNTIME_CONFIG_V02.md` phases 1 through 3 first.
- Keep the order strict:
  1. Protocol doc additions.
  2. Hermes session propagation.
  3. `assistant_text` frame.
- Commit the protocol document edit by itself before any server code changes.
- Do not start mobile history persistence until `assistant_text` exists.
- Verify Hermes session propagation with a mocked HTTP request test before touching resume UI.

## 2. Implement API runtime config

- Implement API phases 4 and 5 after `assistant_text`.
- Add `SessionRuntimeConfig`.
- Add `client_hello` config parsing.
- Add `set_intermediary_mode` and `set_audio_params`.
- Keep semantics simple: settings apply next turn, not mid-turn.

## 3. Implement API long-gap resume

- Implement API phases 6 and 7 after Hermes session propagation is confirmed.
- Add explicit `VoiceStore` lookup helpers.
- Do not lean on the current 5-minute in-memory resume window; long-gap resume must work from the DB.
- Confirm resumed sessions reuse the original `conversation_id`.

## 4. Begin mobile with the local store

- Start with mobile phase 1.
- This can run in parallel with API steps 1 through 3.
- Build the local SQLite conversation store before UI work.
- Keep the store isolated and well-tested.
- Add upsert behavior from the start.

## 5. Wire mobile persistence after API `assistant_text`

- Implement mobile phase 2 only after API phase 3.
- Persist messages only on successful `turn_end`.
- Use pending in-memory buffers for transcript and assistant text.
- Discard canceled turns cleanly.

## 6. Add mobile resume plumbing before drawer UI

- Implement mobile phase 3 before mobile phase 5.
- Thread `resumeSessionID` into `client_hello`.
- Keep this change small and testable.

## 7. Refactor UI in layers

- Implement mobile phase 4 as the main layout refactor, including the transcript bubble component.
- Add conversation history sheet third.
- Add Settings sheet last.

## 8. Integrate settings after API runtime config

- Mobile phase 6 depends on API phases 4 and 5.
- Send persisted settings in `client_hello`.
- Send live setting frames only when connected.
- Show copy that settings apply on the next turn.

## 9. Final validation pass

- Run API checks:
  1. `uv run pytest`
  2. `uv run ruff check`
  3. `uv run ruff format --check`
- Run iOS checks:
  1. `xcodebuild test -project mobile/ios/HermesWhisper02/HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'platform=iOS Simulator,name=iPhone 17'`
- Manually test:
  1. Login.
  2. Voice conversation.
  3. Local history.
  4. Resume.
  5. Runtime settings.
  6. Profile switching.

## Summary

The highest-risk dependencies are API-side: Hermes session propagation and `assistant_text`. Implement those before mobile persistence or resume UI. After those are stable, build mobile from the data layer upward, then refactor the UI in visible layers.

Commit cadence: follow the TODO files phase by phase. Run the listed checks before checking off each phase, then commit that phase before starting the next one.
