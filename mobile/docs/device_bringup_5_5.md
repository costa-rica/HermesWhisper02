# Physical-device audio bring-up, Phase 5.5

This note records the physical-device audio checks completed before starting mobile Phase 6. The full Phase 5.5 acceptance is not complete yet because playback through `PlaybackActor` and phone-call interruption recovery are still planned for later phases.

## Test context

1. Device class:
   - Physical iPhone running iOS 17 or newer.
2. App branch:
   - `dev_02`.
3. Audio implementation under test:
   - `mobile/ios/HermesWhisper02/HermesWhisper02/Voice/AudioCapture.swift`.
4. UI used:
   - `VoiceView` debug mic controls and RMS display.

## Completed checks

1. Built and ran the app on a physical iPhone.
2. Verified built-in iPhone microphone capture with Bluetooth disconnected.
3. Verified Bluetooth HFP capture with AirPods connected.
4. Confirmed the RMS display responds to spoken voice in both routes.
5. Confirmed captured frames are converted by the existing Phase 5 pipeline to:
   - 16 kHz
   - mono
   - PCM16 little-endian
   - 320 samples per frame
   - 640 bytes per frame

## Device log evidence

1. Built-in microphone route selected correctly:

```text
audio_capture_session_configured inputs=MicrophoneBuiltIn:iPhone Microphone outputs=Speaker:Speaker preferred_input=iPhone Microphone sample_rate=48000.000000 io_buffer=0.020000
audio_capture_tap_installed sample_rate=48000.000000 channels=1 interleaved=false
```

2. Earlier AirPods testing exposed a hardware format mismatch:

```text
AVAudioEngineGraph.mm:504 Error, formats don't match! Input HW format: 1 ch, 24000 Hz, Float32, tap format: 1 ch, 48000 Hz, Float32
AVAudioEngine.mm:192 Engine could not initialize, error = -10868
```

3. Follow-up fixes were applied and retested:
   - `dfd5fcc fix: reinstall audio tap on route restart`
   - `f8e8f52 fix: prefer built-in mic for capture`
   - `1c799a6 fix: avoid audio restart on category change`

## Results

1. Built-in microphone capture:
   - Passed.
   - The app appeared to catch all spoken voice after avoiding the self-induced route restart loop.
2. Bluetooth and AirPods capture:
   - Passed.
   - Capture worked with Bluetooth disconnected and connected.
3. Route changes:
   - Partially passed.
   - Bluetooth disconnected and connected tests passed for capture.
   - Mid-playback route recovery remains pending because playback is not implemented yet.
4. Playback fixture:
   - Pending.
   - `PlaybackActor` and `AudioPlayer` are still placeholders.
5. Phone-call interruption recovery:
   - Pending.
   - The app handles interruption notifications in code, but this has not yet been manually verified on device.

## Follow-up

1. Finish Phase 6 WebSocket integration.
2. Implement Phase 7 playback through `PlaybackActor`.
3. Revisit Phase 5.5 acceptance after Phase 7:
   - Verify playback of a bundled PCM16 fixture or real downlink audio.
   - Verify route changes during playback.
   - Verify phone-call interruption recovery.
4. Keep the current audio route logs until Phase 7 device playback and barge-in testing are complete.
