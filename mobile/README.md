# HermesWhisper02 Mobile

## Project Overview

The HermesWhisper02 mobile app is a SwiftUI iOS client for voice sessions with the HermesWhisper02 API. It is planned around server registry management, Keychain-scoped credentials, microphone capture, WebSocket audio transport, TTS playback, and local interrupt-only barge-in detection.

## Setup

1. Install Xcode with iOS 17 or newer simulator support.

2. Install `xcodegen`.

```bash
brew install xcodegen
```

3. Generate the Xcode project.

```bash
cd mobile/ios/HermesWhisper02
xcodegen generate
```

4. Open the app in Xcode.

```bash
open HermesWhisper02.xcodeproj
```

5. Select the `HermesWhisper02` scheme and an iOS simulator.

## Usage

1. Start the API locally from the repo root.

```bash
cd api
uv run uvicorn app.main:app --host 127.0.0.1 --port 8765
```

2. Run the app from Xcode.
   - Open `mobile/ios/HermesWhisper02/HermesWhisper02.xcodeproj`.
   - Select the `HermesWhisper02` scheme.
   - Run on an iOS 17 or newer simulator.

3. Current app behavior.
   - The app opens to the login flow when no valid Keychain token exists.
   - Successful email-code verification persists the bearer token and lands on the placeholder voice view.
   - The server registry can list, add, edit, reorder, delete, probe, and switch server profiles.
   - Audio capture, WebSocket, playback, and reconnect behavior are planned in later mobile phases.

## Testing

1. List the project schemes.

```bash
cd mobile/ios/HermesWhisper02
xcodebuild -list -project HermesWhisper02.xcodeproj
```

2. Run unit tests.

```bash
xcodebuild test \
  -project HermesWhisper02.xcodeproj \
  -scheme HermesWhisper02 \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

3. Build for the simulator.

```bash
xcodebuild build \
  -project HermesWhisper02.xcodeproj \
  -scheme HermesWhisper02 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

4. Regenerate after editing `project.yml`.

```bash
xcodegen generate
```

5. Current verification status.
   - `xcodebuild test` passes on the iPhone 17 simulator.
   - `xcodebuild build` passes for the generic iOS Simulator destination with `CODE_SIGNING_ALLOWED=NO`.

## Project Structure

```text
mobile/
├── AGENTS.md
├── README.md
└── ios/
    └── HermesWhisper02/
        ├── project.yml
        ├── HermesWhisper02.xcodeproj/
        ├── HermesWhisper02/
        │   ├── App/
        │   │   ├── HermesWhisper02App.swift
        │   │   └── AppEnvironment.swift
        │   ├── Auth/
        │   │   ├── AuthService.swift
        │   │   └── KeychainStore.swift
        │   ├── ServerRegistry/
        │   │   ├── ServerProfile.swift
        │   │   └── ServerRegistryStore.swift
        │   ├── Voice/
        │   │   ├── VoiceSocket.swift
        │   │   ├── AudioCapture.swift
        │   │   ├── PlaybackActor.swift
        │   │   └── VoiceView.swift
        │   ├── Models/
        │   └── Util/
        ├── HermesWhisper02Tests/
        └── HermesWhisper02UITests/
```

## Configuration

1. Bundle identifier.
   - `com.dashanddata.hermeswhisper02`

2. Minimum iOS version.
   - iOS 17

3. Initial server profile.
   - `https://api.hermes-whisper.dashanddata.com`

4. Local development API.
   - Use `http://127.0.0.1:8765` from the simulator when integration phases wire the client to the local API.

## References

- [Mobile plan](../docs/20260510_PLAN_MOBILE_V01.md)
- [Protocol v1](../docs/20260510_PROTOCOL_V01.md)
- [Requirements](../docs/20260510_REQUIREMENTS.md)
- [TODO guidance](../docs/TODO_LIST_GUIDANCE.md)
- [Commit message guidance](../docs/CommitMessagesGuidance.md)
