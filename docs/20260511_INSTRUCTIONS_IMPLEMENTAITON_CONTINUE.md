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

Skim the archived docs only if you need decision history.

## Current status

1. API phases 0 through 6b are implemented and committed.
2. The deployed API is reachable through:
   - `https://api.hermes-whisper.dashanddata.com/`
3. The user verified the deployed API basics:
   - HTTPS routing works.
   - Auth works after seeding the user password into the SQLite user table.
4. Mobile phase 0 scaffold is committed.
5. Mobile phase 1 is partially complete:
   - `ServerProfile.swift` exists and matches the planned model shape.
   - `ServerRegistryStore.swift` still needs implementation.
   - Phase 1 tests still need implementation.
6. The mobile app currently shows only `Hello, HermesWhisper02`; this is expected for the phase 0 scaffold.
7. The current branch should be `dev_01` if using this handoff exactly.

## Important branch and git rules

1. Work on branch `dev_01`.
2. Do not work directly on `main`.
3. Keep phase commits scoped.
4. Do not amend commits.
5. Do not use `--no-verify`.
6. After each phase:
   - Implement the phase.
   - Run tests.
   - Run build/typecheck.
   - Check off completed plan boxes.
   - Commit with a message referencing the plan and phase.
7. Push `dev_01` after successful commits.

## Next implementation step

Start with mobile phase 1 in `docs/20260510_PLAN_MOBILE_V01.md`.

Implement:

1. `mobile/ios/HermesWhisper02/HermesWhisper02/ServerRegistry/ServerRegistryStore.swift`
   - Store file at Application Support:
     - `HermesWhisper02/server_registry.json`
   - API:
     - `load() -> [ServerProfile]`
     - `save(_:)`
     - `add(_:)`
     - `update(_:)`
     - `delete(id:)`
     - `reorder(_:)`
   - Pre-populate on first launch with:
     - display name: `fsdc-avatar08`
     - base URL: `https://api.hermes-whisper.dashanddata.com`
     - auth kind: `.bearer2FA`

2. Tests in `HermesWhisper02Tests`
   - Add `ServerRegistryStoreTests.swift`.
   - Cover:
     - write and read round trip
     - pre-population on empty store
     - delete
     - reorder
     - update

3. Keep the app building after the storage implementation.

## Mobile commands

Run these from:

`mobile/ios/HermesWhisper02`

1. Regenerate the project if `project.yml` changes:

```bash
xcodegen generate
```

2. List schemes:

```bash
xcodebuild -list -project HermesWhisper02.xcodeproj
```

3. Run tests:

```bash
xcodebuild test \
  -project HermesWhisper02.xcodeproj \
  -scheme HermesWhisper02 \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

4. Build simulator app:

```bash
xcodebuild build \
  -project HermesWhisper02.xcodeproj \
  -scheme HermesWhisper02 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

If the local Xcode toolchain fails before compiling project code, capture the exact error and continue only if the requested phase can still be validated another way. Otherwise stop and report the blocker.

## After mobile phase 1

Continue through the mobile plan in order:

1. Mobile phase 2: Keychain credentials.
2. Mobile phase 3: Auth service and login UI.
3. Mobile phase 4: Server registry UI.
4. Mobile phase 5: Audio capture.
5. Mobile phase 5.5: Physical device audio bring-up.
   - If no physical iPhone is available, create `mobile/docs/device_bringup_5_5.md`.
   - Document what was not tested and why.

Then proceed to mobile phase 6 for first API integration.

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
2. Apple signing or physical-device availability blocking a required device phase.
3. A requirements conflict that needs a design decision.
4. A protocol ambiguity that requires changing `docs/20260510_PROTOCOL_V01.md`.
5. A local toolchain failure that prevents required verification.

Do not stop for:

1. Normal lint or test failures you can fix.
2. Small implementation choices already covered by the plan.
3. Placeholder UI text while still in storage/auth phases.
4. Missing optional polish.

## Commit message examples

Use the style in `docs/CommitMessagesGuidance.md`.

Examples:

```text
feat: add server registry storage (PLAN_MOBILE phase 1)
```

```text
feat: add keychain credential store (PLAN_MOBILE phase 2)
```

```text
feat: add auth service and login flow (PLAN_MOBILE phase 3)
```

## Final report format

When done or blocked, report:

1. Phases completed.
2. Tests/builds run.
3. Commits created.
4. Push status.
5. Any blockers or skipped items with one-line reasons.
