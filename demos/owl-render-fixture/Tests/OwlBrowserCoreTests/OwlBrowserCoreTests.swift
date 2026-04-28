import XCTest
import OwlBrowserCore
import OwlMojoBindingsGenerated

final class OwlBrowserCoreTests: XCTestCase {
    func testSessionControllerBindsGeneratedChildInterfacesBeforeUse() throws {
        let pipe = FakeBrowserPipe()
        let controller = try OwlBrowserSessionController(pipe: pipe, session: nil)

        try controller.resize(OwlFreshWebViewResizeRequest(width: 960, height: 640, scale: 1.0))
        try controller.sendKey(OwlFreshKeyEvent(keyDown: true, keyCode: 13, text: "\n", modifiers: 0))
        _ = try controller.getSurfaceTree()

        XCTAssertEqual(pipe.calls, [
            "bindProfile:1",
            "bindWebView:2",
            "bindInput:3",
            "bindSurfaceTree:4",
            "bindNativeSurfaceHost:5",
            "setClient:6",
            "resize:960x640@1.0",
            "key:13:\n",
            "surfaceTree",
        ])
        XCTAssertEqual(controller.recordedCalls.prefix(6).map(\.method), [
            "bindProfile",
            "bindWebView",
            "bindInput",
            "bindSurfaceTree",
            "bindNativeSurfaceHost",
            "setClient",
        ])
    }
}

private final class FakeBrowserPipe: OwlFreshMojoPipeBindings {
    var calls: [String] = []

    func sessionSetClient(_ session: OpaquePointer?, client: OwlFreshClientRemote) throws {
        calls.append("setClient:\(client.handle)")
    }

    func sessionBindProfile(_ session: OpaquePointer?, profile: OwlFreshProfileReceiver) throws {
        calls.append("bindProfile:\(profile.handle)")
    }

    func sessionBindWebView(_ session: OpaquePointer?, webView: OwlFreshWebViewReceiver) throws {
        calls.append("bindWebView:\(webView.handle)")
    }

    func sessionBindInput(_ session: OpaquePointer?, input: OwlFreshInputReceiver) throws {
        calls.append("bindInput:\(input.handle)")
    }

    func sessionBindSurfaceTree(_ session: OpaquePointer?, surfaceTree: OwlFreshSurfaceTreeHostReceiver) throws {
        calls.append("bindSurfaceTree:\(surfaceTree.handle)")
    }

    func sessionBindNativeSurfaceHost(
        _ session: OpaquePointer?,
        nativeSurfaceHost: OwlFreshNativeSurfaceHostReceiver
    ) throws {
        calls.append("bindNativeSurfaceHost:\(nativeSurfaceHost.handle)")
    }

    func sessionFlush(_ session: OpaquePointer?) throws -> Bool {
        calls.append("flush")
        return true
    }

    func profileGetPath(_ session: OpaquePointer?) throws -> String {
        calls.append("profile")
        return "/tmp/owl-profile"
    }

    func webViewNavigate(_ session: OpaquePointer?, url: String) throws {
        calls.append("navigate:\(url)")
    }

    func webViewResize(_ session: OpaquePointer?, request: OwlFreshWebViewResizeRequest) throws {
        calls.append("resize:\(request.width)x\(request.height)@\(request.scale)")
    }

    func webViewSetFocus(_ session: OpaquePointer?, focused: Bool) throws {
        calls.append("focus:\(focused)")
    }

    func inputSendMouse(_ session: OpaquePointer?, event: OwlFreshMouseEvent) throws {
        calls.append("mouse:\(event.kind.rawValue)")
    }

    func inputSendKey(_ session: OpaquePointer?, event: OwlFreshKeyEvent) throws {
        calls.append("key:\(event.keyCode):\(event.text)")
    }

    func surfaceTreeHostCaptureSurface(_ session: OpaquePointer?) throws -> OwlFreshCaptureResult {
        calls.append("capture")
        return OwlFreshCaptureResult(png: [1, 2, 3], width: 1, height: 1, captureMode: "fake", error: "")
    }

    func surfaceTreeHostGetSurfaceTree(_ session: OpaquePointer?) throws -> OwlFreshSurfaceTree {
        calls.append("surfaceTree")
        return OwlFreshSurfaceTree(generation: 1, surfaces: [])
    }

    func nativeSurfaceHostAcceptActivePopupMenuItem(_ session: OpaquePointer?, index: UInt32) throws -> Bool {
        calls.append("accept:\(index)")
        return true
    }

    func nativeSurfaceHostCancelActivePopup(_ session: OpaquePointer?) throws -> Bool {
        calls.append("cancel")
        return true
    }
}
