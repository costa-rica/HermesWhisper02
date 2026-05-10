# Mobile agent instructions

## Scope

- Applies to files under `mobile/`.
- Follow the root `AGENTS.md` plus these mobile-specific rules.

## Tooling

- The iOS app lives in `mobile/ios/HermesWhisper02/`.
- Use the checked-in Xcode project and `project.yml`.
- If the project spec changes, regenerate with `xcodegen generate` from `mobile/ios/HermesWhisper02/`.
- Use `xcodebuild` for builds and tests.

## Commands

1. Generate the project: `xcodegen generate`.
2. List schemes: `xcodebuild -list -project HermesWhisper02.xcodeproj`.
3. Run tests: `xcodebuild test -project HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'platform=iOS Simulator,name=iPhone 17'`.
4. Build simulator app: `xcodebuild build -project HermesWhisper02.xcodeproj -scheme HermesWhisper02 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.

## Swift conventions

- Use SwiftUI for app screens.
- Use UIKit only where Apple audio APIs require it.
- Prefer async/await and `AsyncStream`.
- Do not introduce Combine unless it is trivially required by SwiftUI integration.
- Do not add third-party Swift packages unless the plan or user explicitly allows it.

## Audio

- Server-side VAD is authoritative for utterance boundaries.
- Do not add on-device STT or utterance-boundary VAD.
- `BargeInDetector` is allowed only as an interrupt-only energy detector while assistant audio is playing.
- Uplink audio target is PCM16 little-endian, 16 kHz, mono, 20 ms frames.
- Downlink playback uses the `audio_chunk` prelude format from `docs/20260510_PROTOCOL_V01.md`.

## State and security

- Store server profiles in Application Support.
- Store credentials in Keychain with account `profile.id.uuidString`.
- Use `kSecAttrAccessibleAfterFirstUnlock`.
- Never put OpenAI or Hermes API keys in the mobile app.

## Testing

- Use XCTest for unit tests.
- WebSocket tests should use an embedded local server when implemented.
- Physical-device audio checks are required for phase 5.5; if a device is unavailable, document the gap in `mobile/docs/device_bringup_5_5.md`.
