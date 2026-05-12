import AVFoundation

final class AudioCapture {
    static let targetSampleRate: Double = 16_000
    static let samplesPerFrame = 320
    static let bytesPerFrame = samplesPerFrame * MemoryLayout<Int16>.size

    private let engine: AVAudioEngine
    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter

    private var processor: PCM16FrameProcessor?
    private var stream: AsyncStream<Data>?
    private var continuation: AsyncStream<Data>.Continuation?
    private var isRunning = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        session: AVAudioSession = .sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.engine = engine
        self.session = session
        self.notificationCenter = notificationCenter
    }

    deinit {
        stop()
    }

    func frames() -> AsyncStream<Data> {
        if let stream {
            return stream
        }

        let stream = AsyncStream<Data> { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
        self.stream = stream
        return stream
    }

    func start() throws {
        guard !isRunning else {
            return
        }

        try configureSession()
        observeAudioSession()
        installInputTap()

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        removeAudioSessionObservers()
        processor = nil
        isRunning = false
        let continuation = self.continuation
        self.continuation = nil
        stream = nil
        continuation?.finish()
    }

    static func rms(forPCM16Frame frame: Data) -> Double {
        guard !frame.isEmpty else {
            return 0
        }

        var sumOfSquares = 0.0
        var sampleCount = 0

        frame.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                sumOfSquares += normalized * normalized
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return 0
        }
        return sqrt(sumOfSquares / Double(sampleCount))
    }

    private func configureSession() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
    }

    private func installInputTap() {
        let inputNode = engine.inputNode
        processor = nil

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }
    }

    private func observeAudioSession() {
        guard interruptionObserver == nil, routeChangeObserver == nil else {
            return
        }

        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func removeAudioSessionObservers() {
        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeChangeObserver {
            notificationCenter.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            engine.pause()
        case .ended:
            guard isRunning else {
                return
            }
            try? session.setActive(true)
            try? engine.start()
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isRunning,
              let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .categoryChange, .routeConfigurationChange:
            restartForCurrentRoute()
        default:
            break
        }
    }

    private func restartForCurrentRoute() {
        engine.pause()

        do {
            try configureSession()
            processor = nil
            try engine.start()
        } catch {
            AppLog.voice.error("audio_capture_route_restart_failed error=\(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        do {
            var processor = try processor(for: buffer.format)
            let chunks = try processor.append(buffer)
            self.processor = processor
            for chunk in chunks where chunk.count == Self.bytesPerFrame {
                continuation?.yield(chunk)
            }
        } catch {
            AppLog.voice.error("audio_capture_process_failed error=\(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private func processor(for format: AVAudioFormat) throws -> PCM16FrameProcessor {
        if let processor, processor.accepts(format) {
            return processor
        }

        return try PCM16FrameProcessor(inputFormat: format)
    }
}

struct PCM16FrameProcessor {
    enum ProcessorError: Error {
        case unsupportedInputFormat
        case outputFormatUnavailable
        case converterUnavailable
        case outputBufferUnavailable
        case inputBufferUnavailable
        case conversionFailed
    }

    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let samplesPerFrame: Int
    private var pendingSamples: [Float] = []

    init(
        inputFormat: AVAudioFormat,
        outputSampleRate: Double = AudioCapture.targetSampleRate,
        samplesPerFrame: Int = AudioCapture.samplesPerFrame
    ) throws {
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw ProcessorError.unsupportedInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw ProcessorError.outputFormatUnavailable
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw ProcessorError.converterUnavailable
        }

        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.primeMethod = .none
        converter.primeInfo = AVAudioConverterPrimeInfo(leadingFrames: 0, trailingFrames: 0)

        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
        self.samplesPerFrame = samplesPerFrame
    }

    func accepts(_ format: AVAudioFormat) -> Bool {
        inputFormat.commonFormat == format.commonFormat
            && inputFormat.sampleRate == format.sampleRate
            && inputFormat.channelCount == format.channelCount
            && inputFormat.isInterleaved == format.isInterleaved
    }

    mutating func append(_ inputBuffer: AVAudioPCMBuffer) throws -> [Data] {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 128
        var providedInput = false

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputCapacity
            ) else {
                throw ProcessorError.outputBufferUnavailable
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if providedInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                providedInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if status == .error || conversionError != nil {
                throw conversionError ?? ProcessorError.conversionFailed
            }

            if outputBuffer.frameLength > 0 {
                guard let channel = outputBuffer.floatChannelData?[0] else {
                    throw ProcessorError.inputBufferUnavailable
                }

                let convertedSamples = UnsafeBufferPointer(
                    start: channel,
                    count: Int(outputBuffer.frameLength)
                )
                pendingSamples.append(contentsOf: convertedSamples)
            }

            if status != .haveData {
                break
            }
        }
        return drainFrames()
    }

    private mutating func drainFrames() -> [Data] {
        var frames: [Data] = []

        while pendingSamples.count >= samplesPerFrame {
            let samples = pendingSamples.prefix(samplesPerFrame)
            frames.append(Self.pcm16LittleEndianData(from: samples))
            pendingSamples.removeFirst(samplesPerFrame)
        }

        return frames
    }

    static func pcm16LittleEndianData<Samples: Sequence>(from samples: Samples) -> Data where Samples.Element == Float {
        var data = Data()
        data.reserveCapacity(AudioCapture.bytesPerFrame)

        for sample in samples {
            let clamped = min(1, max(-1, sample))
            let scaled = clamped >= 1
                ? Int16.max
                : Int16(clamped * Float(Int16.max))
            var littleEndian = scaled.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        return data
    }
}
