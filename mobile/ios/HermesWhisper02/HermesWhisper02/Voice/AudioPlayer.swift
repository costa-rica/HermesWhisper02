import Foundation

struct AudioPlayer {
    private let playbackActor: PlaybackActor

    init(playbackActor: PlaybackActor = PlaybackActor()) {
        self.playbackActor = playbackActor
    }

    var actor: PlaybackActor {
        playbackActor
    }

    func enqueue(format: AudioFormat, sampleRate: Int, pcm16: Data) async throws {
        try await playbackActor.enqueue(format: format, sampleRate: sampleRate, pcm16: pcm16)
    }

    func flushAndStop() async {
        await playbackActor.flushAndStop()
    }

    func isPlaying() async -> Bool {
        await playbackActor.isPlaying
    }
}
