import AVFoundation
import Foundation

actor PlaybackActor {
    enum PlaybackError: Error {
        case unsupportedFormat
        case bufferUnavailable
        case channelUnavailable
    }

    private let output: PlaybackOutput
    private var generation = 0
    private var pendingBuffers = 0
    private var playbackActive = false

    var isPlaying: Bool {
        playbackActive
    }

    init(output: PlaybackOutput = AVFoundationPlaybackOutput()) {
        self.output = output
    }

    func enqueue(format: AudioFormat, sampleRate: Int, pcm16: Data) async throws {
        guard format == .pcm16 else {
            throw PlaybackError.unsupportedFormat
        }
        guard !pcm16.isEmpty else {
            return
        }

        let buffer = try Self.makePCMBuffer(sampleRate: sampleRate, pcm16: pcm16)
        try output.prepareIfNeeded(sampleRate: Double(sampleRate), channels: 1)

        let currentGeneration = generation
        pendingBuffers += 1
        playbackActive = true

        output.enqueue(buffer) { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.bufferFinished(generation: currentGeneration)
            }
        }
    }

    func flushAndStop() {
        generation += 1
        pendingBuffers = 0
        playbackActive = false
        output.flushAndStop()
    }

    func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            flushAndStop()
        default:
            break
        }
    }

    func handleInterruption(type: AVAudioSession.InterruptionType) {
        if type == .began {
            flushAndStop()
        }
    }

    private func bufferFinished(generation finishedGeneration: Int) {
        guard finishedGeneration == generation, pendingBuffers > 0 else {
            return
        }
        pendingBuffers -= 1
        if pendingBuffers == 0 {
            playbackActive = false
        }
    }

    static func makePCMBuffer(sampleRate: Int, pcm16: Data) throws -> AVAudioPCMBuffer {
        let sampleCount = pcm16.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ) else {
            throw PlaybackError.bufferUnavailable
        }
        guard let channel = buffer.floatChannelData?[0] else {
            throw PlaybackError.channelUnavailable
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        pcm16.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                channel[index] = Float(Int16(littleEndian: samples[index])) / Float(Int16.max)
            }
        }
        return buffer
    }
}

protocol PlaybackOutput: AnyObject {
    func prepareIfNeeded(sampleRate: Double, channels: AVAudioChannelCount) throws
    func enqueue(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void)
    func flushAndStop()
}

final class AVFoundationPlaybackOutput: PlaybackOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var currentFormat: AVAudioFormat?

    func prepareIfNeeded(sampleRate: Double, channels: AVAudioChannelCount) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw PlaybackActor.PlaybackError.bufferUnavailable
        }

        if currentFormat != format {
            if engine.isRunning {
                engine.stop()
            }
            player.stop()
            engine.reset()
            if player.engine == nil {
                engine.attach(player)
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            currentFormat = format
        }

        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    func enqueue(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) {
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            completion()
        }
    }

    func flushAndStop() {
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
    }
}
