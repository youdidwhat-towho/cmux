#if DEBUG
import Foundation
import IOSurface
import ObjectiveC

/// Streams `IOSurface` framebuffer frames out of a booted simulator via
/// SimulatorKit's IOClient. Pure pass-through: emits exactly when
/// SimulatorKit composites a new frame. Cadence/throttling is the
/// consumer's responsibility.
final class SimulatorScreen: @unchecked Sendable {
    private let udid: String
    private let queue = DispatchQueue(label: "cmux.simulator.screen", qos: .userInteractive)

    private var ioClient: NSObject?
    private var descriptors: [NSObject] = []
    private var callbackUUIDs: [ObjectIdentifier: NSUUID] = [:]
    private var onFrame: (@Sendable (IOSurface) -> Void)?

    init(udid: String) {
        self.udid = udid
    }

    deinit {
        stop()
    }

    func start(onFrame: @escaping @Sendable (IOSurface) -> Void) throws {
        self.onFrame = onFrame
        guard let device = try SimulatorService.shared.resolveDevice(udid: udid) else {
            throw SimulatorError.notFound(udid: udid)
        }
        guard let io = device.perform(NSSelectorFromString("io"))?
            .takeUnretainedValue() as? NSObject
        else {
            throw SimulatorError.ioUnavailable
        }
        self.ioClient = io
        try wireFramebuffer()
    }

    func stop() {
        let unregSel = NSSelectorFromString("unregisterScreenCallbacksWithUUID:")
        for desc in descriptors {
            if let uuid = callbackUUIDs[ObjectIdentifier(desc)],
               desc.responds(to: unregSel) {
                desc.perform(unregSel, with: uuid)
            }
        }
        descriptors.removeAll()
        callbackUUIDs.removeAll()
        ioClient = nil
        onFrame = nil
    }

    // MARK: - private

    private func wireFramebuffer() throws {
        guard let io = ioClient else { throw SimulatorError.ioUnavailable }
        io.perform(NSSelectorFromString("updateIOPorts"))

        guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else {
            throw SimulatorError.ioUnavailable
        }

        let pidSel = NSSelectorFromString("portIdentifier")
        let descSel = NSSelectorFromString("descriptor")
        let surfSel = NSSelectorFromString("framebufferSurface")

        var candidates: [NSObject] = []
        for port in ports where port.responds(to: pidSel) {
            guard let pid = port.perform(pidSel)?.takeUnretainedValue(),
                  "\(pid)" == "com.apple.framebuffer.display",
                  port.responds(to: descSel),
                  let desc = port.perform(descSel)?.takeUnretainedValue() as? NSObject,
                  desc.responds(to: surfSel)
            else { continue }
            candidates.append(desc)
        }
        guard !candidates.isEmpty else { throw SimulatorError.ioUnavailable }
        descriptors = candidates

        for desc in candidates {
            try registerCallbacks(on: desc)
        }
    }

    private func registerCallbacks(on desc: NSObject) throws {
        let regSel = NSSelectorFromString(
            "registerScreenCallbacksWithUUID:callbackQueue:frameCallback:" +
                "surfacesChangedCallback:propertiesChangedCallback:"
        )
        guard desc.responds(to: regSel) else { throw SimulatorError.ioUnavailable }

        let uuid = NSUUID()
        callbackUUIDs[ObjectIdentifier(desc)] = uuid

        let frame: @convention(block) () -> Void = { [weak self] in
            self?.queue.async { self?.captureLatest() }
        }
        let surfaces: @convention(block) () -> Void = { [weak self] in
            self?.queue.async { self?.captureLatest() }
        }
        let props: @convention(block) () -> Void = {}

        guard let imp = class_getMethodImplementation(type(of: desc), regSel) else {
            throw SimulatorError.ioUnavailable
        }
        typealias Fn = @convention(c) (
            AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject, AnyObject
        ) -> Void
        unsafeBitCast(imp, to: Fn.self)(
            desc, regSel,
            uuid, queue as AnyObject,
            frame as AnyObject, surfaces as AnyObject, props as AnyObject
        )
    }

    private func captureLatest() {
        let surfSel = NSSelectorFromString("framebufferSurface")
        var best: IOSurface?
        var bestArea = 0
        for desc in descriptors {
            guard let surfObj = desc.perform(surfSel)?.takeUnretainedValue() else { continue }
            let surf = unsafeBitCast(surfObj, to: IOSurface.self)
            let ref = unsafeBitCast(surfObj, to: IOSurfaceRef.self)
            let area = IOSurfaceGetWidth(ref) * IOSurfaceGetHeight(ref)
            if area > bestArea {
                best = surf
                bestArea = area
            }
        }
        if let best { onFrame?(best) }
    }
}
#endif
