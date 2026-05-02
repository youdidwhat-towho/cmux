import Foundation
import ObjectiveC

enum SimulatorButton {
    case home, lock
}

/// Drives input into a booted simulator via SimulatorKit's host-HID
/// pipeline. Uses the 9-arg `IndigoHIDMessageForMouseNSEvent` recipe from
/// Xcode 26's preview-kit (verified by https://github.com/tddworks/baguette
/// against iOS 26.x). Single-finger taps + drags + home/lock buttons.
///
/// One instance per simulator UDID. Service warmup happens lazily on first
/// dispatch and stays warm for the instance's lifetime; deinit removes the
/// pointer service.
final class IndigoHIDInput: @unchecked Sendable {
    private let udid: String

    // 9-arg shape (Xcode 26 preview-kit). Coords are NORMALIZED 0–1;
    // target=0x32 routes to the touch digitizer. eventType: 1=down, 2=up,
    // 6=dragged. direction: 1=down, 0=move, 2=up.
    private typealias MouseFn = @convention(c) (
        UnsafePointer<CGPoint>, UnsafePointer<CGPoint>?,
        UInt32, UInt32, UInt32,
        Double, Double,        // unused1, unused2 — pass 1.0
        Double, Double         // widthPoints, heightPoints
    ) -> UnsafeMutableRawPointer?
    private typealias ButtonFn = @convention(c) (UInt32, UInt32, UInt32) -> UnsafeMutableRawPointer?
    private typealias ServiceFn = @convention(c) () -> UnsafeMutableRawPointer?

    private let lock = NSLock()
    private var client: AnyObject?
    private var warmed = false
    private var mouseFn: MouseFn?
    private var buttonFn: ButtonFn?
    private var createPointerSvc: ServiceFn?
    private var createMouseSvc: ServiceFn?
    private var removePointerSvc: ServiceFn?

    private static let touchDigitizer: UInt32 = 0x32
    private static let nsEventDown:    UInt32 = 1
    private static let nsEventUp:      UInt32 = 2
    private static let nsEventDragged: UInt32 = 6
    private static let dirDown: UInt32 = 1
    private static let dirMove: UInt32 = 0
    private static let dirUp:   UInt32 = 2

    init(udid: String) {
        self.udid = udid
    }

    deinit {
        if warmed, let client {
            if let remove = removePointerSvc, let msg = remove() {
                send(message: msg, to: client)
            }
        }
    }

    // MARK: - public

    @discardableResult
    func tap(at point: CGPoint, deviceSize: CGSize, duration: Double = 0.05) -> Bool {
        guard let c = ensureWarm() else { return false }
        guard sendMouse(client: c, p1: point, p2: nil, eventType: Self.nsEventDown, direction: Self.dirDown, deviceSize: deviceSize) else { return false }
        usleep(UInt32(max(0.01, duration) * 1_000_000))
        return sendMouse(client: c, p1: point, p2: nil, eventType: Self.nsEventUp, direction: Self.dirUp, deviceSize: deviceSize)
    }

    @discardableResult
    func drag(from start: CGPoint, to end: CGPoint, deviceSize: CGSize, duration: Double = 0.25) -> Bool {
        guard let c = ensureWarm() else { return false }
        let total = max(0.05, duration)
        let steps = 12
        let stepUs = UInt32((total / Double(steps + 2)) * 1_000_000)
        guard sendMouse(client: c, p1: start, p2: nil, eventType: Self.nsEventDown, direction: Self.dirDown, deviceSize: deviceSize) else { return false }
        var ok = 0
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            usleep(stepUs)
            if sendMouse(client: c, p1: p, p2: nil, eventType: Self.nsEventDragged, direction: Self.dirMove, deviceSize: deviceSize) { ok += 1 }
        }
        _ = sendMouse(client: c, p1: end, p2: nil, eventType: Self.nsEventUp, direction: Self.dirUp, deviceSize: deviceSize)
        return ok >= steps / 2
    }

    @discardableResult
    func touchPhase(_ phase: TouchPhase, at point: CGPoint, deviceSize: CGSize) -> Bool {
        guard let c = ensureWarm() else { return false }
        let (et, dir) = mouseEvent(for: phase)
        return sendMouse(client: c, p1: point, p2: nil, eventType: et, direction: dir, deviceSize: deviceSize)
    }

    @discardableResult
    func press(_ button: SimulatorButton) -> Bool {
        guard let c = ensureWarm(), let bfn = buttonFn else { return false }
        let (arg0, target) = buttonCodes(for: button)
        guard let down = bfn(arg0, 1, target) else { return false }
        send(message: down, to: c)
        usleep(100_000)  // 100ms hold
        // direction 2 for release; 0 crashes backboardd on iOS 26.4 per baguette notes.
        guard let up = bfn(arg0, 2, target) else { return false }
        send(message: up, to: c)
        return true
    }

    enum TouchPhase { case down, move, up }

    // MARK: - warmup

    private func ensureWarm() -> AnyObject? {
        lock.lock(); defer { lock.unlock() }
        if warmed, let client { return client }
        guard SimulatorPrivateFrameworks.ensureLoaded() else { return nil }
        guard let device = (try? SimulatorService.shared.resolveDevice(udid: udid)) ?? nil else {
            return nil
        }
        guard let io = device.perform(NSSelectorFromString("io"))?
            .takeUnretainedValue() as? NSObject else { return nil }

        // The HID "client" is the SimDevice's IOClient. SimulatorKit dispatches
        // messages on it by selector name; we call -sendMessage:.
        client = io

        guard resolveSymbols() else { return nil }

        // Bring up pointer + mouse services. These are required before mouse
        // messages route correctly to the touch digitizer.
        if let createPointerSvc, let createMouseSvc, let c = client {
            if let msg = createPointerSvc() { send(message: msg, to: c) }
            if let msg = createMouseSvc() { send(message: msg, to: c) }
        }

        warmed = true
        return client
    }

    private func resolveSymbols() -> Bool {
        // RTLD_DEFAULT does its job on macOS for symbols in dlopen'd dylibs
        // because they were loaded with RTLD_GLOBAL.
        let handle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let sym = dlsym(handle, "IndigoHIDMessageForMouseNSEvent") else { return false }
        mouseFn = unsafeBitCast(sym, to: MouseFn.self)

        if let bSym = dlsym(handle, "IndigoHIDMessageForButton") {
            buttonFn = unsafeBitCast(bSym, to: ButtonFn.self)
        }
        if let s = dlsym(handle, "IndigoHIDMessageForCreatePointerService") {
            createPointerSvc = unsafeBitCast(s, to: ServiceFn.self)
        }
        if let s = dlsym(handle, "IndigoHIDMessageForCreateMouseService") {
            createMouseSvc = unsafeBitCast(s, to: ServiceFn.self)
        }
        if let s = dlsym(handle, "IndigoHIDMessageForRemovePointerService") {
            removePointerSvc = unsafeBitCast(s, to: ServiceFn.self)
        }
        return mouseFn != nil
    }

    // MARK: - dispatch

    private func sendMouse(
        client: AnyObject,
        p1: CGPoint, p2: CGPoint?,
        eventType: UInt32, direction: UInt32,
        deviceSize: CGSize
    ) -> Bool {
        guard let mfn = mouseFn else { return false }
        let maxAttempts = (p2 != nil) ? 12 : 3
        var pt1 = CGPoint(
            x: clamp01(p1.x / deviceSize.width),
            y: clamp01(p1.y / deviceSize.height)
        )
        var msg: UnsafeMutableRawPointer?
        if let p2 {
            var pt2 = CGPoint(
                x: clamp01(p2.x / deviceSize.width),
                y: clamp01(p2.y / deviceSize.height)
            )
            for _ in 0..<maxAttempts {
                msg = withUnsafePointer(to: &pt1) { p1Ref in
                    withUnsafePointer(to: &pt2) { p2Ref in
                        mfn(p1Ref, p2Ref, Self.touchDigitizer, eventType, direction, 1.0, 1.0, deviceSize.width, deviceSize.height)
                    }
                }
                if msg != nil { break }
                usleep(5_000)
            }
        } else {
            for _ in 0..<maxAttempts {
                msg = withUnsafePointer(to: &pt1) { p1Ref in
                    mfn(p1Ref, nil, Self.touchDigitizer, eventType, direction, 1.0, 1.0, deviceSize.width, deviceSize.height)
                }
                if msg != nil { break }
                usleep(5_000)
            }
        }
        guard let msg else { return false }
        send(message: msg, to: client)
        return true
    }

    private func send(message: UnsafeMutableRawPointer, to client: AnyObject) {
        let sel = NSSelectorFromString("sendMessage:")
        guard (client as AnyObject).responds(to: sel) else { return }
        _ = (client as AnyObject).perform(sel, with: unsafeBitCast(message, to: NSObject.self))
    }

    private func mouseEvent(for phase: TouchPhase) -> (UInt32, UInt32) {
        switch phase {
        case .down: return (Self.nsEventDown, Self.dirDown)
        case .move: return (Self.nsEventDragged, Self.dirMove)
        case .up:   return (Self.nsEventUp, Self.dirUp)
        }
    }

    private func buttonCodes(for button: SimulatorButton) -> (UInt32, UInt32) {
        switch button {
        case .home: return (0x0, 0x33)
        case .lock: return (0x1, 0x33)
        }
    }

    private func clamp01(_ x: Double) -> Double {
        min(1.0, max(0.0, x))
    }
}
