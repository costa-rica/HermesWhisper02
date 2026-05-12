import Foundation

@Observable
final class VoiceController: VoiceDisconnecting {
    func disconnect() {
    }
}

protocol VoiceDisconnecting: AnyObject {
    func disconnect()
}
