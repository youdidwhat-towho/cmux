import QuartzCore
import XCTest
@testable import cmux_ios

@MainActor
final class CmxGhosttyTerminalSurfaceTests: XCTestCase {
    func testGhosttySurfaceForwardsPtyBytesUnchanged() {
        let stream = Data([0x1B, 0x5B, 0x33, 0x31, 0x6D, 0x63, 0x6D, 0x75, 0x78, 0x0D, 0x0A])

        let forwarded = GhosttyTerminalSurfaceView.forwardTerminalOutputBytes(stream)

        XCTAssertEqual(forwarded, stream)
    }

    func testGhosttySurfaceInitializesRealLibghosttyRenderer() throws {
        let (surfaceView, _) = try makeSurfaceView()

        XCTAssertNotNil(surfaceView.surface)
        XCTAssertTrue(surfaceView.layer is CAMetalLayer)
    }

    func testGhosttySurfaceRendersAnsiOutput() async throws {
        let (surfaceView, _) = try makeSurfaceView()
        surfaceView.frame = CGRect(x: 0, y: 0, width: 390, height: 640)
        surfaceView.layoutIfNeeded()

        let renderedExpectation = expectation(description: "Ghostty rendered PTY output")
        renderedExpectation.assertForOverFulfill = false
        surfaceView.onOutputProcessedForTesting = {
            let rendered = surfaceView.accessibilityRenderedTextForTesting() ?? ""
            if rendered.contains("cmux-color") {
                renderedExpectation.fulfill()
            }
        }

        surfaceView.processOutput(Data("\u{1B}[31mcmux-color\u{1B}[0m\r\n".utf8))

        await fulfillment(of: [renderedExpectation], timeout: 3.0)
        XCTAssertTrue((surfaceView.accessibilityRenderedTextForTesting() ?? "").contains("cmux-color"))
    }

    func testGhosttySurfaceEmitsOutboundBytesForTypedText() async throws {
        let (surfaceView, delegate) = try makeSurfaceView()

        let inputExpectation = expectation(description: "Ghostty emitted typed input")
        delegate.onInput = { data in
            if data == Data("a".utf8) {
                inputExpectation.fulfill()
            }
        }

        surfaceView.simulateTextInputForTesting("a")

        await fulfillment(of: [inputExpectation], timeout: 2.0)
    }

    private func makeSurfaceView() throws -> (GhosttyTerminalSurfaceView, DelegateRecorder) {
        let delegate = DelegateRecorder()
        let runtime = try GhosttyRuntime.shared()
        let surfaceView = GhosttyTerminalSurfaceView(runtime: runtime, delegate: delegate)
        return (surfaceView, delegate)
    }
}

@MainActor
private final class DelegateRecorder: GhosttyTerminalSurfaceViewDelegate {
    var onInput: ((Data) -> Void)?
    var lastSize: TerminalGridSize?

    func ghosttyTerminalSurfaceView(_ surfaceView: GhosttyTerminalSurfaceView, didProduceInput data: Data) {
        onInput?(data)
    }

    func ghosttyTerminalSurfaceView(_ surfaceView: GhosttyTerminalSurfaceView, didResize size: TerminalGridSize) {
        lastSize = size
    }
}
