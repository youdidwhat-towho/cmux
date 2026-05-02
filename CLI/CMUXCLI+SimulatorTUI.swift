import Foundation
import Darwin

extension CMUXCLI {
    /// Interactive list of simulators. Default action when the user runs
    /// `cmux sim` with no subcommand.
    ///
    /// Keys:
    ///   ↑/↓ or j/k    move selection
    ///   Enter         open the device in a bonsplit pane
    ///   b             boot the selected device
    ///   s             shutdown the selected device
    ///   r             refresh now
    ///   q or Ctrl-C   quit
    func runSimulatorTUI(client: SocketClient, idFormat: CLIIDFormat) throws {
        // Non-TTY (piped or scripted): fall back to plain list and exit.
        if isatty(STDIN_FILENO) == 0 || isatty(STDOUT_FILENO) == 0 {
            try runSimulatorList(client: client, jsonOutput: false)
            return
        }

        let raw = SimulatorTUIRawMode()
        defer { raw?.restore() }

        let renderer = SimulatorTUIRenderer()
        var devices: [SimulatorTUIDevice] = []
        var selection = 0
        var statusLine = ""
        var pending: SimulatorTUIPendingAction?

        func reload() {
            do {
                let payload = try client.sendV2(method: "simulator.list", params: [:])
                let raw = (payload["devices"] as? [[String: Any]]) ?? []
                devices = raw.compactMap(SimulatorTUIDevice.init(payload:))
                    .sorted {
                        if $0.runtime != $1.runtime { return $0.runtime < $1.runtime }
                        return $0.name < $1.name
                    }
                if devices.isEmpty {
                    selection = 0
                } else {
                    selection = max(0, min(selection, devices.count - 1))
                }
            } catch {
                statusLine = "list failed: \(error.localizedDescription)"
            }
        }

        reload()
        renderer.draw(devices: devices, selection: selection, status: statusLine, pending: pending)

        // Reader thread pushes one keystroke at a time onto a bounded channel.
        let stdin = FileHandle.standardInput
        let queue = DispatchQueue(label: "cmux.sim.tui.input")
        var pendingByte: Int32?
        let semaphore = DispatchSemaphore(value: 0)
        var stop = false
        let lock = NSLock()

        queue.async {
            var buf = [UInt8](repeating: 0, count: 1)
            while true {
                let n = read(stdin.fileDescriptor, &buf, 1)
                if n <= 0 { return }
                lock.lock()
                if stop { lock.unlock(); return }
                pendingByte = Int32(buf[0])
                lock.unlock()
                semaphore.signal()
            }
        }

        // Auto-refresh every 2s.
        let refreshDeadline = Date().addingTimeInterval(2.0)
        var nextRefresh = refreshDeadline

        while true {
            // Wait up to 200ms for a key, then re-render / refresh as needed.
            let timeout: DispatchTime = .now() + .milliseconds(200)
            let signaled = semaphore.wait(timeout: timeout)
            var key: Int32?
            if signaled == .success {
                lock.lock()
                key = pendingByte
                pendingByte = nil
                lock.unlock()
            }

            if let key {
                if key == 0x03 || key == Int32(Character("q").asciiValue!) {
                    break
                }
                let action = handleKey(key, stdin: stdin)
                switch action {
                case .none:
                    break
                case .moveUp:
                    if !devices.isEmpty { selection = (selection - 1 + devices.count) % devices.count }
                case .moveDown:
                    if !devices.isEmpty { selection = (selection + 1) % devices.count }
                case .refresh:
                    reload()
                    statusLine = "refreshed (\(devices.count) device\(devices.count == 1 ? "" : "s"))"
                case .openSelection:
                    if let device = devices[safe: selection] {
                        do {
                            let payload = try client.sendV2(method: "simulator.open", params: [
                                "udid": device.udid,
                                "direction": "right",
                            ])
                            let surfaceText = formatHandle(payload, kind: "surface", idFormat: idFormat) ?? "?"
                            statusLine = "opened \(device.name) (surface=\(surfaceText))"
                        } catch {
                            statusLine = "open failed: \(error.localizedDescription)"
                        }
                    }
                case .bootSelection:
                    if let device = devices[safe: selection] {
                        statusLine = "booting \(device.name)…"
                        renderer.draw(devices: devices, selection: selection, status: statusLine, pending: pending)
                        do {
                            _ = try client.sendV2(method: "simulator.boot", params: ["udid": device.udid])
                            statusLine = "booted \(device.name)"
                        } catch {
                            statusLine = "boot failed: \(error.localizedDescription)"
                        }
                        reload()
                    }
                case .shutdownSelection:
                    if let device = devices[safe: selection] {
                        statusLine = "shutting down \(device.name)…"
                        renderer.draw(devices: devices, selection: selection, status: statusLine, pending: pending)
                        do {
                            _ = try client.sendV2(method: "simulator.shutdown", params: ["udid": device.udid])
                            statusLine = "shut down \(device.name)"
                        } catch {
                            statusLine = "shutdown failed: \(error.localizedDescription)"
                        }
                        reload()
                    }
                }
            }

            if Date() >= nextRefresh {
                reload()
                nextRefresh = Date().addingTimeInterval(2.0)
            }

            renderer.draw(devices: devices, selection: selection, status: statusLine, pending: pending)
        }

        lock.lock(); stop = true; lock.unlock()
        renderer.teardown()
    }

    private enum SimulatorTUIAction {
        case none
        case moveUp, moveDown
        case refresh
        case openSelection
        case bootSelection
        case shutdownSelection
    }

    private func handleKey(_ key: Int32, stdin: FileHandle) -> SimulatorTUIAction {
        // Arrow keys arrive as ESC [ A/B/C/D — read 2 more bytes after ESC.
        if key == 0x1B {
            var buf = [UInt8](repeating: 0, count: 2)
            let n = read(stdin.fileDescriptor, &buf, 2)
            guard n == 2, buf[0] == 0x5B else { return .none }
            switch buf[1] {
            case 0x41: return .moveUp     // ↑
            case 0x42: return .moveDown   // ↓
            default: return .none
            }
        }

        switch UnicodeScalar(UInt8(key)) {
        case "k": return .moveUp
        case "j": return .moveDown
        case "r": return .refresh
        case "b": return .bootSelection
        case "s": return .shutdownSelection
        case "\r", "\n", " ": return .openSelection
        default: return .none
        }
    }
}

// MARK: - models

private struct SimulatorTUIDevice {
    let udid: String
    let name: String
    let runtime: String
    let state: String
    let isBooted: Bool

    init?(payload: [String: Any]) {
        guard let udid = payload["udid"] as? String,
              let name = payload["name"] as? String else { return nil }
        self.udid = udid
        self.name = name
        self.runtime = (payload["runtime"] as? String) ?? ""
        self.state = (payload["state"] as? String) ?? "?"
        self.isBooted = (payload["is_booted"] as? Bool) ?? (state == "booted")
    }
}

private struct SimulatorTUIPendingAction {
    let kind: String
    let udid: String
}

// MARK: - renderer

private final class SimulatorTUIRenderer {
    private var didEnterAlt = false

    func draw(devices: [SimulatorTUIDevice], selection: Int, status: String, pending: SimulatorTUIPendingAction?) {
        if !didEnterAlt {
            print("\u{1B}[?1049h\u{1B}[?25l", terminator: "")  // alt screen + hide cursor
            didEnterAlt = true
        }
        // Clear screen + home
        var out = "\u{1B}[H\u{1B}[2J"

        let title = "cmux simulators"
        out += "\u{1B}[1;36m\(title)\u{1B}[0m  "
        out += "\u{1B}[2m↑/↓ move  ⏎ open in pane  b boot  s shutdown  r refresh  q quit\u{1B}[0m\r\n"
        out += "\u{1B}[2m\(String(repeating: "─", count: max(0, min(80, terminalWidth()))))\u{1B}[0m\r\n"

        if devices.isEmpty {
            out += "\u{1B}[2m  (no simulators found)\u{1B}[0m\r\n"
        } else {
            var lastRuntime: String?
            for (i, device) in devices.enumerated() {
                if device.runtime != lastRuntime {
                    out += "\r\n\u{1B}[1m\(device.runtime.isEmpty ? "Other" : device.runtime)\u{1B}[0m\r\n"
                    lastRuntime = device.runtime
                }
                let isSel = (i == selection)
                let dot = device.isBooted ? "\u{1B}[32m●\u{1B}[0m" : "\u{1B}[2m○\u{1B}[0m"
                let statePill: String
                switch device.state {
                case "booted":      statePill = "\u{1B}[32mbooted\u{1B}[0m"
                case "booting":     statePill = "\u{1B}[33mbooting\u{1B}[0m"
                case "shuttingDown":statePill = "\u{1B}[33mshutting down\u{1B}[0m"
                default:            statePill = "\u{1B}[2m\(device.state)\u{1B}[0m"
                }
                let prefix = isSel ? "\u{1B}[7m▶ " : "  "
                let suffix = isSel ? " \u{1B}[0m" : ""
                let udidShort = String(device.udid.prefix(8))
                out += "\(prefix)\(dot) \(device.name.padding(toLength: 28, withPad: " ", startingAt: 0))  \(udidShort)  \(statePill)\(suffix)\r\n"
            }
        }

        out += "\r\n"
        if !status.isEmpty {
            out += "\u{1B}[2m\(status)\u{1B}[0m\r\n"
        }
        if let pending {
            out += "\u{1B}[33mpending: \(pending.kind) \(pending.udid)\u{1B}[0m\r\n"
        }

        FileHandle.standardOutput.write(Data(out.utf8))
    }

    func teardown() {
        if didEnterAlt {
            print("\u{1B}[?25h\u{1B}[?1049l", terminator: "")  // show cursor + leave alt screen
            didEnterAlt = false
        }
    }

    deinit {
        teardown()
    }

    private func terminalWidth() -> Int {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
            return Int(w.ws_col)
        }
        return 80
    }
}

// MARK: - raw mode (TUI-local copy so we don't depend on cmux.swift internals)

private final class SimulatorTUIRawMode {
    private var original = termios()
    private var restored = false

    init?() {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        cfmakeraw(&raw)
        // Keep VMIN=1/VTIME=0 default semantics so reads are byte-by-byte blocking.
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
    }

    func restore() {
        guard !restored else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        restored = true
    }

    deinit { restore() }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
