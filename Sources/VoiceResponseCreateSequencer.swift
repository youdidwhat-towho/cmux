import Foundation

@MainActor
final class VoiceResponseCreateSequencer {
    private enum Control {
        case free
        case createRequested
    }

    private let isConnected: () -> Bool
    private let hasBlockers: () -> Bool
    private let sendEvent: ([String: Any]) -> Void

    private var ongoingResponse = false
    private var control: Control = .free
    private var pendingResponseCreate = false
    private var responseCreateCounter = 0

    init(
        isConnected: @escaping () -> Bool,
        hasBlockers: @escaping () -> Bool,
        sendEvent: @escaping ([String: Any]) -> Void
    ) {
        self.isConnected = isConnected
        self.hasBlockers = hasBlockers
        self.sendEvent = sendEvent
    }

    func requestResponseCreate() {
        pendingResponseCreate = true
        dispatchPendingIfPossible()
    }

    func markResponseCreated() {
        ongoingResponse = true
        control = .free
    }

    func markResponseDone() {
        ongoingResponse = false
        control = .free
        dispatchPendingIfPossible()
    }

    func markActiveResponseConflict() {
        ongoingResponse = true
        control = .free
        pendingResponseCreate = true
    }

    func reset() {
        ongoingResponse = false
        control = .free
        pendingResponseCreate = false
        responseCreateCounter = 0
    }

    private func dispatchPendingIfPossible() {
        guard pendingResponseCreate,
              isConnected(),
              !hasBlockers(),
              !ongoingResponse,
              control == .free else {
            return
        }

        pendingResponseCreate = false
        control = .createRequested
        responseCreateCounter += 1
        sendEvent([
            "type": "response.create",
            "event_id": "cmux_voice_response_create_\(responseCreateCounter)"
        ])
    }
}
