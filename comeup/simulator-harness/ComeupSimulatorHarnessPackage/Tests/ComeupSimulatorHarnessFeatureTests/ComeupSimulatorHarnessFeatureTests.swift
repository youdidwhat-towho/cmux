import Foundation
import Testing
@testable import ComeupSimulatorHarnessFeature

@Test
func simulatorTextHarnessSyncsWithComeupDaemon() throws {
    let portText = ProcessInfo.processInfo.environment["COMEUP_TEXT_PORT"] ?? "17891"
    let port = try #require(Int(portText))
    let client = try TextHarnessSocket(host: "127.0.0.1", port: port)
    defer { client.close() }

    try client.sendLine("HELLO 90 30")
    let welcome = try client.readLine(containing: "WELCOME client=")
    #expect(welcome.contains("terminal=1"))
    #expect(welcome.contains("size=90x30") || welcome.contains("size=80x24"))

    try client.sendLine("VISIBLE 1 66 18")
    #expect(try client.readLine(containing: "SIZE terminal=1 66x18") == "SIZE terminal=1 66x18")

    try client.sendLine("WORKSPACE Sim Build")
    #expect(try client.readLine(containing: "WORKSPACE id=2 title=Sim Build") == "WORKSPACE id=2 title=Sim Build")
    let sizedTerminal = try parseSizedTerminal(try client.readLine(containing: "SIZE terminal="), expectedSize: "66x18")
    let focusedTerminal = try parseFocusedTerminal(try client.readLine(containing: "FOCUS terminal="))
    #expect(focusedTerminal == sizedTerminal)

    try client.sendLine("SEND \(focusedTerminal) SIM_SENTINEL_FROM_IOS")
    #expect(try client.readLine(containing: "SIM_SENTINEL_FROM_IOS").contains("OUTPUT terminal=\(focusedTerminal)"))

    try client.sendLine("PING 77")
    #expect(try client.readLine(containing: "PONG id=77") == "PONG id=77")
}

private func parseFocusedTerminal(_ line: String) throws -> Int {
    guard let value = line.split(separator: "=").last, let terminal = Int(value) else {
        throw TextHarnessSocket.Error.malformedLine(line)
    }
    return terminal
}

private func parseSizedTerminal(_ line: String, expectedSize: String) throws -> Int {
    let pieces = line.split(separator: " ")
    guard pieces.count == 3, pieces[0] == "SIZE", pieces[1].hasPrefix("terminal="), pieces[2] == expectedSize else {
        throw TextHarnessSocket.Error.malformedLine(line)
    }
    let value = pieces[1].dropFirst("terminal=".count)
    guard let terminal = Int(value) else {
        throw TextHarnessSocket.Error.malformedLine(line)
    }
    return terminal
}

private final class TextHarnessSocket {
    enum Error: Swift.Error, CustomStringConvertible {
        case streamUnavailable
        case openFailed(String)
        case writeFailed(String)
        case readFailed(String)
        case timedOut(String)
        case malformedLine(String)

        var description: String {
            switch self {
            case .streamUnavailable:
                "Foundation did not create TCP streams"
            case .openFailed(let detail):
                "stream open failed: \(detail)"
            case .writeFailed(let detail):
                "stream write failed: \(detail)"
            case .readFailed(let detail):
                "stream read failed: \(detail)"
            case .timedOut(let detail):
                "timed out: \(detail)"
            case .malformedLine(let line):
                "malformed line: \(line)"
            }
        }
    }

    private let input: InputStream
    private let output: OutputStream
    private var buffer: [UInt8] = []

    init(host: String, port: Int) throws {
        var inputStream: InputStream?
        var outputStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inputStream, outputStream: &outputStream)
        guard let inputStream, let outputStream else {
            throw Error.streamUnavailable
        }

        input = inputStream
        output = outputStream
        input.schedule(in: .current, forMode: .default)
        output.schedule(in: .current, forMode: .default)
        input.open()
        output.open()
        try waitForOpen()
    }

    func close() {
        input.close()
        output.close()
        input.remove(from: .current, forMode: .default)
        output.remove(from: .current, forMode: .default)
    }

    func sendLine(_ line: String) throws {
        var bytes = Array(line.utf8)
        bytes.append(10)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBufferPointer { pointer in
                output.write(pointer.baseAddress!.advanced(by: offset), maxLength: bytes.count - offset)
            }
            if written < 0 {
                throw Error.writeFailed(output.streamError?.localizedDescription ?? "unknown error")
            }
            if written == 0 {
                runLoopTick()
            }
            offset += written
        }
    }

    func readLine(containing expected: String, timeout: TimeInterval = 5) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var seen: [String] = []
        while Date() < deadline {
            while let line = popLine() {
                seen.append(line)
                if line.contains(expected) {
                    return line
                }
            }
            try readAvailableBytes()
            runLoopTick()
        }
        throw Error.timedOut("waiting for \(expected), saw \(seen.joined(separator: " | "))")
    }

    private func waitForOpen(timeout: TimeInterval = 5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if input.streamStatus == .error || output.streamStatus == .error {
                throw Error.openFailed(input.streamError?.localizedDescription ?? output.streamError?.localizedDescription ?? "unknown error")
            }
            if input.streamStatus == .open && output.streamStatus == .open {
                return
            }
            runLoopTick()
        }
        throw Error.timedOut("opening TCP streams")
    }

    private func readAvailableBytes() throws {
        guard input.hasBytesAvailable else {
            return
        }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = input.read(&bytes, maxLength: bytes.count)
        if count < 0 {
            throw Error.readFailed(input.streamError?.localizedDescription ?? "unknown error")
        }
        if count > 0 {
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }

    private func popLine() -> String? {
        guard let newlineIndex = buffer.firstIndex(of: 10) else {
            return nil
        }
        let lineBytes = buffer[..<newlineIndex]
        buffer.removeSubrange(...newlineIndex)
        return String(decoding: lineBytes, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    private func runLoopTick() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}
