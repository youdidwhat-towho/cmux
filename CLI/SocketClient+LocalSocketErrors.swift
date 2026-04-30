import Foundation
import Darwin

extension SocketClient {
    func recoveredLocalSocketWriteFailure(errorCode: Int32, failureMessage: String) -> String? {
        guard relayEndpoint == nil, failureMessage == "Failed to write to socket" else {
            return nil
        }
        guard errorCode == EPIPE || errorCode == ECONNRESET else {
            return nil
        }

        if let serverMessage = readEarlySocketResponseLine(timeout: 0.15) {
            return serverMessage
        }

        return "cmux socket server closed the connection before reading the command"
    }

    private func readEarlySocketResponseLine(timeout: TimeInterval) -> String? {
        try? configureReceiveTimeout(timeout)

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while data.count < 16 * 1024 {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            if count < 0 {
                let readErrno = errno
                if readErrno == EINTR {
                    continue
                }
                if readErrno == EAGAIN || readErrno == EWOULDBLOCK {
                    break
                }
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
            if data.contains(UInt8(0x0A)) {
                break
            }
        }

        guard var response = String(data: data, encoding: .utf8) else {
            return nil
        }
        if let newlineIndex = response.firstIndex(of: "\n") {
            response = String(response[..<newlineIndex])
        }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
