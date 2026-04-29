import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class TerminalDesktopNotificationBridgeTests: XCTestCase {
    func testActiveClaudeHookStillAllowsNonClaudeTerminalNotificationPayloads() {
        let suppressed = TerminalDesktopNotificationBridge.shouldSuppressNotification(
            workspaceAgentPIDs: ["claude_code": pid_t(123)],
            title: "Codex question",
            body: "Does this notification work?"
        )

        XCTAssertFalse(
            suppressed,
            "A Claude hook PID in the workspace should not swallow unrelated terminal OSC notifications such as Codex prompts."
        )
    }

    func testActiveClaudeHookSuppressesGenericClaudeAttentionNotification() {
        let suppressed = TerminalDesktopNotificationBridge.shouldSuppressNotification(
            workspaceAgentPIDs: ["claude_code": pid_t(123)],
            title: "Claude Code",
            body: "Claude Code needs your attention"
        )

        XCTAssertTrue(suppressed)
    }

    func testResolvedTitleFallsBackToTabTitle() {
        XCTAssertEqual(
            TerminalDesktopNotificationBridge.resolvedTitle(
                actionTitle: "",
                fallbackTabTitle: "workspace-1"
            ),
            "workspace-1"
        )
        XCTAssertEqual(
            TerminalDesktopNotificationBridge.resolvedTitle(
                actionTitle: "Plan mode question",
                fallbackTabTitle: "workspace-1"
            ),
            "Plan mode question"
        )
    }
}
