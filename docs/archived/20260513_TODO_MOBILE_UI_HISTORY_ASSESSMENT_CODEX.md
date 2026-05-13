# TODO mobile UI history assessment: Codex

Date: 2026-05-13

## Summary

The UI direction is solid, and the local SQLite plan is workable. The main implementation risk is that the mobile plan assumes it can persist assistant messages from existing frames, but the current protocol does not provide final assistant text. A second risk is that session resume and local conversation rows should not be treated as complete until the API confirms the Hermes conversation id is actually propagated to Hermes.

## Concerns

1. Assistant message persistence is not currently possible.
   - The app receives answer audio but not final answer text.
   - `HermesProgressKind.finished` only means Hermes finished, not that text is available.
   - The plan needs an `assistant_text` or equivalent frame from the API.

2. Persisting at `HermesProgressKind.finished` is too early.
   - TTS may still fail after Hermes finishes.
   - Playback may be canceled before the turn completes.
   - Persist final messages on `turn_end` when `canceled != true`.

3. VoiceController does not currently expose `startSession(resumeSessionID:)`.
   - This is feasible, but it should be explicit in an earlier phase.
   - It must thread the session id into `VoiceSocket` and `ClientHelloFrame`.

4. The store API needs an upsert path.
   - `session_started` may return an existing session.
   - `createSession(hermesConversationID:)` alone risks duplicate primary keys.
   - Add `upsertSession(id:, hermesConversationID:)`.

5. Local-only delete needs careful UX wording.
   - Swipe-to-delete removes only the device copy.
   - Resuming a deleted local row is impossible unless rediscovered from API later.
   - This is acceptable, but the UI should call it "Remove from this device" eventually.

6. The drawer should reload after each completed turn.
   - Message count and preview update after persistence.
   - Without explicit reload/published updates, rows may look stale.

## Recommended approach changes

1. Add a dependency on the API `assistant_text` frame.
   - Do not implement final assistant bubble persistence until this exists.
   - In-flight assistant text can remain empty or use a placeholder.

2. Change Phase 2 persistence timing.
   - On final transcript, store pending user text in memory.
   - On `assistant_text final=true`, store pending assistant text in memory.
   - On `turn_end canceled != true`, commit both messages.
   - On canceled turn, discard pending assistant text.

3. Add session upsert before history UI.
   - `upsertSession(id:, hermesConversationID:, title:)`.
   - Use `session_started.session_id` as the local primary key.

4. Move resume plumbing before drawer detail.
   - Add `VoiceController.start(profile:resumeSessionID:...)`.
   - Add `VoiceSocket(priorSessionID:)` use for selected historical sessions.

5. Keep the custom drawer optional.
   - A sheet-first implementation is lower risk.
   - The custom slide-out drawer can follow once the data model works.

## Risk if unchanged

- The app may display user bubbles but miss assistant history.
- Resume UI may appear to work while Hermes context is not actually restored.
- Conversation rows may duplicate or go stale after reconnect.
