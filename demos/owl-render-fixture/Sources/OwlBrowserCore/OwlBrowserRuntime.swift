import Darwin
import Foundation
import OwlMojoBindingsGenerated

public final class OwlBrowserRuntime: OwlFreshMojoPipeBindings {
    private typealias GlobalInit = @convention(c) () -> Int32
    private typealias SessionCreate = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        OwlFreshEventCallback?,
        UnsafeMutableRawPointer?
    ) -> OpaquePointer?
    private typealias SessionDestroy = @convention(c) (OpaquePointer?) -> Void
    private typealias HostPID = @convention(c) (OpaquePointer?) -> Int32
    private typealias StringInputResult = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias StringOut = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias BoolOut = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias VoidUInt64 = @convention(c) (
        OpaquePointer?,
        UInt64,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias VoidString = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias VoidBool = @convention(c) (
        OpaquePointer?,
        Bool,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias WebViewResize = @convention(c) (
        OpaquePointer?,
        UInt32,
        UInt32,
        Float,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias InputSendMouse = @convention(c) (
        OpaquePointer?,
        UInt32,
        Float,
        Float,
        UInt32,
        UInt32,
        Float,
        Float,
        UInt32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias InputSendKey = @convention(c) (
        OpaquePointer?,
        Bool,
        UInt32,
        UnsafePointer<CChar>?,
        UInt32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias NativeSurfaceAccept = @convention(c) (
        OpaquePointer?,
        UInt32,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias PollEvents = @convention(c) (UInt32) -> Void
    private typealias FreeBuffer = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let globalInit: GlobalInit
    private let sessionCreate: SessionCreate
    private let sessionDestroy: SessionDestroy
    private let sessionHostPID: HostPID
    private let shellExecuteJavaScript: StringInputResult
    private let sessionSetClientSymbol: VoidUInt64
    private let sessionBindProfileSymbol: VoidUInt64
    private let sessionBindWebViewSymbol: VoidUInt64
    private let sessionBindInputSymbol: VoidUInt64
    private let sessionBindSurfaceTreeSymbol: VoidUInt64
    private let sessionBindNativeSurfaceHostSymbol: VoidUInt64
    private let sessionFlushSymbol: BoolOut
    private let profileGetPathSymbol: StringOut
    private let webViewNavigateSymbol: VoidString
    private let webViewResizeSymbol: WebViewResize
    private let webViewSetFocusSymbol: VoidBool
    private let inputSendMouseSymbol: InputSendMouse
    private let inputSendKeySymbol: InputSendKey
    private let surfaceTreeCaptureSurfaceJSON: StringOut
    private let surfaceTreeGetJSON: StringOut
    private let nativeSurfaceAcceptSymbol: NativeSurfaceAccept
    private let nativeSurfaceCancelSymbol: BoolOut
    private let eventPoll: PollEvents
    private let freeBuffer: FreeBuffer

    public init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw OwlBrowserError.bridge("dlopen failed for \(path): \(dlerrorString())")
        }
        self.handle = handle
        self.globalInit = try loadSymbol(handle, "owl_fresh_mojo_global_init", as: GlobalInit.self)
        self.sessionCreate = try loadSymbol(handle, "owl_fresh_mojo_session_create", as: SessionCreate.self)
        self.sessionDestroy = try loadSymbol(handle, "owl_fresh_mojo_session_destroy", as: SessionDestroy.self)
        self.sessionHostPID = try loadSymbol(handle, "owl_fresh_mojo_session_host_pid", as: HostPID.self)
        self.shellExecuteJavaScript = try loadSymbol(
            handle,
            "owl_fresh_mojo_shell_execute_javascript",
            as: StringInputResult.self
        )
        self.sessionSetClientSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_session_set_client",
            as: VoidUInt64.self
        )
        self.sessionBindProfileSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_session_bind_profile",
            as: VoidUInt64.self
        )
        self.sessionBindWebViewSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_session_bind_web_view",
            as: VoidUInt64.self
        )
        self.sessionBindInputSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_session_bind_input",
            as: VoidUInt64.self
        )
        self.sessionBindSurfaceTreeSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_session_bind_surface_tree",
            as: VoidUInt64.self
        )
        self.sessionBindNativeSurfaceHostSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_session_bind_native_surface_host",
            as: VoidUInt64.self
        )
        self.sessionFlushSymbol = try loadSymbol(handle, "owl_fresh_mojo_session_flush", as: BoolOut.self)
        self.profileGetPathSymbol = try loadSymbol(handle, "owl_fresh_mojo_profile_get_path", as: StringOut.self)
        self.webViewNavigateSymbol = try loadSymbol(handle, "owl_fresh_mojo_web_view_navigate", as: VoidString.self)
        self.webViewResizeSymbol = try loadSymbol(handle, "owl_fresh_mojo_web_view_resize", as: WebViewResize.self)
        self.webViewSetFocusSymbol = try loadSymbol(handle, "owl_fresh_mojo_web_view_set_focus", as: VoidBool.self)
        self.inputSendMouseSymbol = try loadSymbol(handle, "owl_fresh_mojo_input_send_mouse", as: InputSendMouse.self)
        self.inputSendKeySymbol = try loadSymbol(handle, "owl_fresh_mojo_input_send_key", as: InputSendKey.self)
        self.surfaceTreeCaptureSurfaceJSON = try loadSymbol(
            handle,
            "owl_fresh_mojo_surface_tree_capture_surface_json",
            as: StringOut.self
        )
        self.surfaceTreeGetJSON = try loadSymbol(handle, "owl_fresh_mojo_surface_tree_get_json", as: StringOut.self)
        self.nativeSurfaceAcceptSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_native_surface_accept_active_popup_menu_item",
            as: NativeSurfaceAccept.self
        )
        self.nativeSurfaceCancelSymbol = try loadSymbol(
            handle,
            "owl_fresh_mojo_native_surface_cancel_active_popup",
            as: BoolOut.self
        )
        self.eventPoll = try loadSymbol(handle, "owl_fresh_mojo_poll_events", as: PollEvents.self)
        self.freeBuffer = try loadSymbol(handle, "owl_fresh_mojo_free_buffer", as: FreeBuffer.self)
    }

    deinit {
        dlclose(handle)
    }

    public func initialize() throws {
        let status = globalInit()
        guard status == 0 else {
            throw OwlBrowserError.bridge("owl_fresh_mojo_global_init failed with status \(status)")
        }
    }

    public func createSession(
        chromiumHost: String,
        initialURL: String,
        userDataDirectory: String,
        events: OwlBrowserSessionEvents
    ) throws -> OpaquePointer {
        let userData = Unmanaged.passUnretained(events).toOpaque()
        let session = chromiumHost.withCString { hostPointer in
            initialURL.withCString { urlPointer in
                userDataDirectory.withCString { profilePointer in
                    sessionCreate(hostPointer, urlPointer, profilePointer, owlFreshEventCallback, userData)
                }
            }
        }
        guard let session else {
            throw OwlBrowserError.launch("owl_fresh_mojo_session_create returned null")
        }
        return session
    }

    public func destroy(_ session: OpaquePointer?) {
        sessionDestroy(session)
    }

    public func hostPID(_ session: OpaquePointer?) -> Int32 {
        sessionHostPID(session)
    }

    public func pollEvents(milliseconds: UInt32) {
        eventPoll(milliseconds)
    }

    public func executeJavaScript(_ session: OpaquePointer?, script: String) throws -> String {
        try script.withCString { scriptPointer in
            try callStringResult("ShellController.executeJavaScript") { resultPointer, errorPointer in
                shellExecuteJavaScript(session, scriptPointer, resultPointer, errorPointer)
            }
        }
    }

    public func captureSurfacePNG(_ session: OpaquePointer?, to url: URL) throws -> OwlBrowserSurfaceCapture {
        let result = try surfaceTreeHostCaptureSurface(session)
        guard result.error.isEmpty else {
            throw OwlBrowserError.capture("CaptureSurface failed: \(result.error)")
        }
        let data = Data(result.png)
        guard !data.isEmpty else {
            throw OwlBrowserError.capture("CaptureSurface returned empty PNG data")
        }
        try data.write(to: url)
        return OwlBrowserSurfaceCapture(path: url.path, mode: result.captureMode, width: result.width, height: result.height)
    }

    public func sessionSetClient(_ session: OpaquePointer?, client: OwlFreshClientRemote) throws {
        try callVoidResult("OwlFreshSession.setClient") { errorPointer in
            sessionSetClientSymbol(session, client.handle, errorPointer)
        }
    }

    public func sessionBindProfile(_ session: OpaquePointer?, profile: OwlFreshProfileReceiver) throws {
        try callVoidResult("OwlFreshSession.bindProfile") { errorPointer in
            sessionBindProfileSymbol(session, profile.handle, errorPointer)
        }
    }

    public func sessionBindWebView(_ session: OpaquePointer?, webView: OwlFreshWebViewReceiver) throws {
        try callVoidResult("OwlFreshSession.bindWebView") { errorPointer in
            sessionBindWebViewSymbol(session, webView.handle, errorPointer)
        }
    }

    public func sessionBindInput(_ session: OpaquePointer?, input: OwlFreshInputReceiver) throws {
        try callVoidResult("OwlFreshSession.bindInput") { errorPointer in
            sessionBindInputSymbol(session, input.handle, errorPointer)
        }
    }

    public func sessionBindSurfaceTree(
        _ session: OpaquePointer?,
        surfaceTree: OwlFreshSurfaceTreeHostReceiver
    ) throws {
        try callVoidResult("OwlFreshSession.bindSurfaceTree") { errorPointer in
            sessionBindSurfaceTreeSymbol(session, surfaceTree.handle, errorPointer)
        }
    }

    public func sessionBindNativeSurfaceHost(
        _ session: OpaquePointer?,
        nativeSurfaceHost: OwlFreshNativeSurfaceHostReceiver
    ) throws {
        try callVoidResult("OwlFreshSession.bindNativeSurfaceHost") { errorPointer in
            sessionBindNativeSurfaceHostSymbol(session, nativeSurfaceHost.handle, errorPointer)
        }
    }

    public func sessionFlush(_ session: OpaquePointer?) throws -> Bool {
        try callBoolResult("OwlFreshSession.flush") { okPointer, errorPointer in
            sessionFlushSymbol(session, okPointer, errorPointer)
        }
    }

    public func profileGetPath(_ session: OpaquePointer?) throws -> String {
        try callStringResult("OwlFreshProfile.getPath") { resultPointer, errorPointer in
            profileGetPathSymbol(session, resultPointer, errorPointer)
        }
    }

    public func webViewNavigate(_ session: OpaquePointer?, url: String) throws {
        try url.withCString { urlPointer in
            try callVoidResult("OwlFreshWebView.navigate") { errorPointer in
                webViewNavigateSymbol(session, urlPointer, errorPointer)
            }
        }
    }

    public func webViewResize(_ session: OpaquePointer?, request: OwlFreshWebViewResizeRequest) throws {
        try callVoidResult("OwlFreshWebView.resize") { errorPointer in
            webViewResizeSymbol(session, request.width, request.height, request.scale, errorPointer)
        }
    }

    public func webViewSetFocus(_ session: OpaquePointer?, focused: Bool) throws {
        try callVoidResult("OwlFreshWebView.setFocus") { errorPointer in
            webViewSetFocusSymbol(session, focused, errorPointer)
        }
    }

    public func inputSendMouse(_ session: OpaquePointer?, event: OwlFreshMouseEvent) throws {
        try callVoidResult("OwlFreshInput.sendMouse") { errorPointer in
            inputSendMouseSymbol(
                session,
                event.kind.rawValue,
                event.x,
                event.y,
                event.button,
                event.clickCount,
                event.deltaX,
                event.deltaY,
                event.modifiers,
                errorPointer
            )
        }
    }

    public func inputSendKey(_ session: OpaquePointer?, event: OwlFreshKeyEvent) throws {
        try event.text.withCString { textPointer in
            try callVoidResult("OwlFreshInput.sendKey") { errorPointer in
                inputSendKeySymbol(
                    session,
                    event.keyDown,
                    event.keyCode,
                    textPointer,
                    event.modifiers,
                    errorPointer
                )
            }
        }
    }

    public func surfaceTreeHostCaptureSurface(_ session: OpaquePointer?) throws -> OwlFreshCaptureResult {
        let json = try callStringResult("OwlFreshSurfaceTreeHost.captureSurface") { resultPointer, errorPointer in
            surfaceTreeCaptureSurfaceJSON(session, resultPointer, errorPointer)
        }
        let result = try JSONDecoder().decode(RuntimeCaptureSurfaceResult.self, from: Data(json.utf8))
        let png = Data(base64Encoded: result.pngBase64).map(Array.init) ?? []
        return OwlFreshCaptureResult(
            png: png,
            width: result.width,
            height: result.height,
            captureMode: result.captureMode,
            error: result.error
        )
    }

    public func surfaceTreeHostGetSurfaceTree(_ session: OpaquePointer?) throws -> OwlFreshSurfaceTree {
        let json = try callStringResult("OwlFreshSurfaceTreeHost.getSurfaceTree") { resultPointer, errorPointer in
            surfaceTreeGetJSON(session, resultPointer, errorPointer)
        }
        return try JSONDecoder().decode(OwlFreshSurfaceTree.self, from: Data(json.utf8))
    }

    public func nativeSurfaceHostAcceptActivePopupMenuItem(_ session: OpaquePointer?, index: UInt32) throws -> Bool {
        try callBoolResult("OwlFreshNativeSurfaceHost.acceptActivePopupMenuItem") { okPointer, errorPointer in
            nativeSurfaceAcceptSymbol(session, index, okPointer, errorPointer)
        }
    }

    public func nativeSurfaceHostCancelActivePopup(_ session: OpaquePointer?) throws -> Bool {
        try callBoolResult("OwlFreshNativeSurfaceHost.cancelActivePopup") { okPointer, errorPointer in
            nativeSurfaceCancelSymbol(session, okPointer, errorPointer)
        }
    }

    private func callStringResult(
        _ context: String,
        _ body: (
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        ) -> Int32
    ) throws -> String {
        var resultPointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = body(&resultPointer, &errorPointer)
        defer {
            if let resultPointer {
                freeBuffer(UnsafeMutableRawPointer(resultPointer))
            }
            if let errorPointer {
                freeBuffer(UnsafeMutableRawPointer(errorPointer))
            }
        }
        if status != 0 {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown Mojo runtime error"
            throw OwlBrowserError.bridge("\(context) failed: \(message)")
        }
        return resultPointer.map { String(cString: $0) } ?? ""
    }

    private func callBoolResult(
        _ context: String,
        _ body: (
            UnsafeMutablePointer<Bool>,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        ) -> Int32
    ) throws -> Bool {
        var ok = false
        try callVoidResult(context) { errorPointer in
            body(&ok, errorPointer)
        }
        return ok
    }

    private func callVoidResult(
        _ context: String,
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    ) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = body(&errorPointer)
        defer {
            if let errorPointer {
                freeBuffer(UnsafeMutableRawPointer(errorPointer))
            }
        }
        if status != 0 {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown Mojo runtime error"
            throw OwlBrowserError.bridge("\(context) failed: \(message)")
        }
    }
}

private struct RuntimeCaptureSurfaceResult: Decodable {
    let pngBase64: String
    let width: UInt32
    let height: UInt32
    let captureMode: String
    let error: String
}

private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as _: T.Type) throws -> T {
    guard let symbol = dlsym(handle, name) else {
        throw OwlBrowserError.bridge("missing symbol \(name): \(dlerrorString())")
    }
    return unsafeBitCast(symbol, to: T.self)
}

private func dlerrorString() -> String {
    guard let error = dlerror() else {
        return "unknown dynamic loader error"
    }
    return String(cString: error)
}
