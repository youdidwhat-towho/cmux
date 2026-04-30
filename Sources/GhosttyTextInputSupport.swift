import AppKit

func isControlCharacterScalar(_ scalar: UnicodeScalar) -> Bool {
    scalar.value < 0x20 || scalar.value == 0x7F
}

func shouldSendText(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    if text.count == 1, let scalar = text.unicodeScalars.first {
        return !isControlCharacterScalar(scalar)
    }
    return true
}

struct NumpadIMECommitDeduplicator {
    private struct PendingCommit {
        let text: String
        let keyCode: UInt16
        let sourceId: String?
        let timestamp: TimeInterval
    }

    private var pendingCommit: PendingCommit?

    mutating func recordFallback(text: String, event: NSEvent, sourceId: String?) {
        let flags = normalizedNumpadFlags(event.modifierFlags)
        guard flags == [.numericPad], text.allSatisfy(\.isNumber) else {
            pendingCommit = nil
            return
        }

        pendingCommit = PendingCommit(
            text: text,
            keyCode: event.keyCode,
            sourceId: sourceId,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    mutating func shouldSuppressCommit(
        _ text: String,
        currentEvent: NSEvent?,
        sourceId: String?,
        externalCommittedTextDepth: Int,
        keyTextAccumulatorIsActive: Bool
    ) -> Bool {
        guard externalCommittedTextDepth == 0,
              !keyTextAccumulatorIsActive,
              let pendingCommit else {
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - pendingCommit.timestamp <= 0.25 else {
            self.pendingCommit = nil
            return false
        }

        guard pendingCommit.text == text, pendingCommit.sourceId == sourceId else {
            return false
        }

        if let currentEvent, currentEvent.type == .keyDown {
            let currentFlags = normalizedNumpadFlags(currentEvent.modifierFlags)
            guard currentFlags == [.numericPad], currentEvent.keyCode == pendingCommit.keyCode else {
                return false
            }
        }

        self.pendingCommit = nil
        return true
    }

    private func normalizedNumpadFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock])
    }
}

extension GhosttyNSView {
    func notePotentialDeferredNumpadIMECommit(text: String, event: NSEvent) {
        numpadIMECommitDeduplicator.recordFallback(
            text: text,
            event: event,
            sourceId: KeyboardLayout.id
        )
    }

    func shouldSuppressDeferredNumpadIMECommit(_ text: String) -> Bool {
        numpadIMECommitDeduplicator.shouldSuppressCommit(
            text,
            currentEvent: NSApp.currentEvent,
            sourceId: KeyboardLayout.id,
            externalCommittedTextDepth: externalCommittedTextDepth,
            keyTextAccumulatorIsActive: keyTextAccumulator != nil
        )
    }
}
