# Requirements UI history assessment: Codex

Date: 2026-05-13

## Summary

The direction is good, but three requirements need tightening before implementation. The largest issue is that HermesWhisper02 currently does not send a Hermes session or conversation identifier to Hermes in the live request payload, even though it stores a local `conversation_id`. The second issue is that the mobile app cannot persist assistant bubbles accurately because the current protocol only sends answer audio, not final assistant text. The third issue is that "deterministic intermediary" must be defined as deterministic routing to Hermes, not an ack-only mode.

## Required changes

1. Add assistant text to the protocol.
   - Current mobile receives transcript text and answer audio.
   - It does not receive the final assistant answer as text.
   - Local conversation history needs an `assistant_text` frame or equivalent final text field.
   - Persisting on `HermesProgressKind.finished` is too early and lacks answer text.

2. Confirm and implement Hermes session propagation.
   - Current `api/app/services/hermes.py` sends `messages` to `/v1/chat/completions`.
   - It does not pass `conversation_id` to Hermes as a `conversation` field or header.
   - HermesVoice uses `/responses` with `conversation: conversation_id`.
   - This must be solved before claiming long-gap Hermes context resume.

3. Clarify intermediary modes.
   - `deterministic` should mean deterministic routing, not no answer.
   - Suggested meaning: non-trivial transcript goes directly to Hermes with no front LLM.
   - `llm` should mean a front LLM may answer trivial turns or call Hermes.
   - Avoid "ack-only path" because it would remove substantive answers.

4. Separate UI history from Hermes memory.
   - Local SQLite should display the user's device history.
   - Hermes context should be keyed by Hermes's session/conversation mechanism.
   - These should share identifiers but not pretend to be the same storage layer.

## Suggested requirement edits

1. In "Resume contract", add a prerequisite:
   - The API must pass the stored `conversation_id` to Hermes on every request using the verified Hermes contract.

2. In "Protocol delta", add:
   - `assistant_text { turn_id, text, final, ts }`
   - The client persists assistant bubbles only after `final=true` and `turn_end` is not canceled.

3. In "Intermediary toggle scope", define:
   - `deterministic`: deterministic direct-Hermes answer path.
   - `llm`: front LLM answer path.

## Risk if unchanged

- The app could show local past conversations while Hermes starts fresh internally.
- The app could save incomplete or missing assistant messages.
- The deterministic toggle could accidentally disable real answers.
