import AppKit
import ApplicationServices
import Foundation

private struct Sample {
    let dismissMs: Double
    let restoreMs: Double
    let minimizedAfterDismiss: Bool
}

private func monotonicMs() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}

private func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))
    return sorted[index]
}

private func summarize(_ label: String, _ values: [Double]) {
    let minValue = values.min() ?? .nan
    let maxValue = values.max() ?? .nan
    let avgValue = values.reduce(0, +) / Double(max(values.count, 1))
    print(
        String(
            format: "%@ min=%.2f p50=%.2f avg=%.2f p95=%.2f max=%.2f count=%d",
            label,
            minValue,
            percentile(values, 0.50),
            avgValue,
            percentile(values, 0.95),
            maxValue,
            values.count
        )
    )
}

private func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.001, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        Thread.sleep(forTimeInterval: poll)
    }
    return condition()
}

private func copyAXValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value
}

private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
    (copyAXValue(element, attribute) as? Bool) ?? false
}

private func axWindows(_ appElement: AXUIElement) -> [AXUIElement] {
    guard let values = copyAXValue(appElement, kAXWindowsAttribute) as? [AnyObject] else {
        return []
    }
    return values.compactMap { unsafeBitCast($0, to: AXUIElement?.self) }
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let values = copyAXValue(element, kAXChildrenAttribute) as? [AnyObject] else {
        return []
    }
    return values.compactMap { unsafeBitCast($0, to: AXUIElement?.self) }
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    copyAXValue(element, attribute) as? String
}

private func axSize(_ element: AXUIElement) -> CGSize {
    guard let value = copyAXValue(element, kAXSizeAttribute) else { return .zero }
    var size = CGSize.zero
    AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size)
    return size
}

private func sameAXElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
    CFEqual(lhs, rhs)
}

private func containsAXElement(_ elements: [AXUIElement], _ target: AXUIElement) -> Bool {
    elements.contains { sameAXElement($0, target) }
}

private func preferredBenchmarkWindow(_ appElement: AXUIElement) -> AXUIElement? {
    let candidates = visibleAXWindows(appElement)
        .filter { minimizeButton(for: $0) != nil }
    let standardCandidates = candidates.filter {
        axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }
    return (standardCandidates.isEmpty ? candidates : standardCandidates)
        .max { lhs, rhs in
            let lhsSize = axSize(lhs)
            let rhsSize = axSize(rhs)
            return lhsSize.width * lhsSize.height < rhsSize.width * rhsSize.height
        }
}

private func debugWindowList(_ appElement: AXUIElement) {
    for (index, window) in axWindows(appElement).enumerated() {
        let title = axString(window, kAXTitleAttribute) ?? "<nil>"
        let subrole = axString(window, kAXSubroleAttribute) ?? "<nil>"
        let size = axSize(window)
        let visible = containsAXElement(visibleAXWindows(appElement), window)
        let minimized = axBool(window, kAXMinimizedAttribute)
        fputs(
            String(
                format: "window[%d] title=%@ subrole=%@ visible=%d minimized=%d size=%.0fx%.0f\n",
                index,
                title,
                subrole,
                visible ? 1 : 0,
                minimized ? 1 : 0,
                size.width,
                size.height
            ),
            stderr
        )
    }
}

private func visibleAXWindows(_ appElement: AXUIElement) -> [AXUIElement] {
    axWindows(appElement).filter { !axBool($0, kAXMinimizedAttribute) }
}

private func focusedAXWindow(_ appElement: AXUIElement) -> AXUIElement? {
    guard let value = copyAXValue(appElement, kAXFocusedWindowAttribute) else { return nil }
    return unsafeBitCast(value, to: AXUIElement?.self)
}

private func minimizeButton(for window: AXUIElement) -> AXUIElement? {
    if let value = copyAXValue(window, kAXMinimizeButtonAttribute),
       let button = unsafeBitCast(value, to: AXUIElement?.self) {
        return button
    }

    var stack = axChildren(window)
    var visited = 0
    while let element = stack.popLast(), visited < 256 {
        visited += 1
        let role = axString(element, kAXRoleAttribute)
        let subrole = axString(element, kAXSubroleAttribute)
        let title = axString(element, kAXTitleAttribute)?.lowercased()
        let description = axString(element, kAXDescriptionAttribute)?.lowercased()
        if role == kAXButtonRole,
           subrole == kAXMinimizeButtonSubrole || title == "minimize" || description == "minimize" {
            return element
        }
        stack.append(contentsOf: axChildren(element))
    }

    return nil
}

private func debugAXTree(root: AXUIElement, maxNodes: Int = 80) {
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    var emitted = 0
    while let (element, depth) = stack.popLast(), emitted < maxNodes {
        emitted += 1
        let indent = String(repeating: "  ", count: depth)
        let role = axString(element, kAXRoleAttribute) ?? "<nil>"
        let subrole = axString(element, kAXSubroleAttribute) ?? "<nil>"
        let title = axString(element, kAXTitleAttribute) ?? "<nil>"
        let description = axString(element, kAXDescriptionAttribute) ?? "<nil>"
        fputs("\(indent)role=\(role) subrole=\(subrole) title=\(title) description=\(description)\n", stderr)
        for child in axChildren(element).reversed() {
            stack.append((child, depth + 1))
        }
    }
}

private func openApplication(appURL: URL, bundleIdentifier: String) -> NSRunningApplication? {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    let semaphore = DispatchSemaphore(value: 0)
    var openedApp: NSRunningApplication?
    var openedError: Error?
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
        openedApp = app
        openedError = error
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 10)
    if let openedError {
        fputs("openApplication error: \(openedError)\n", stderr)
    }
    return openedApp ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
}

private func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
}

private func activateFinder(except app: NSRunningApplication) {
    if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
        finder.activate(options: [])
    } else {
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: finderURL, configuration: configuration) { _, _ in
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }
    _ = waitUntil(timeout: 0.5) { !app.isActive }
}

private func terminateExisting(bundleIdentifier: String) {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
        app.terminate()
    }
    _ = waitUntil(timeout: 5) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
        app.forceTerminate()
    }
    _ = waitUntil(timeout: 5) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

private func requireTrustedAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        fputs("Accessibility trust is required for this benchmark.\n", stderr)
        exit(2)
    }
}

private func main() {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else {
        fputs("usage: bench-window-visibility <app-path> <bundle-id> [samples]\n", stderr)
        exit(64)
    }

    requireTrustedAccessibility()

    let appURL = URL(fileURLWithPath: arguments[1])
    let bundleIdentifier = arguments[2]
    let verbose = arguments.contains("--verbose")
    let activateRestore = arguments.contains("--activate-restore")
    let sampleCount = arguments.dropFirst(3).first(where: { Int($0) != nil }).flatMap(Int.init) ?? 15

    terminateExisting(bundleIdentifier: bundleIdentifier)

    guard let app = openApplication(appURL: appURL, bundleIdentifier: bundleIdentifier) else {
        fputs("Unable to launch app.\n", stderr)
        exit(1)
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard waitUntil(timeout: 20, { !visibleAXWindows(appElement).isEmpty }) else {
        fputs("Timed out waiting for initial visible window.\n", stderr)
        exit(1)
    }
    if verbose {
        debugWindowList(appElement)
    }

    var samples: [Sample] = []
    var failuresByReason: [String: Int] = [:]

    func recordFailure(_ reason: String) {
        failuresByReason[reason, default: 0] += 1
    }

    for _ in 0..<sampleCount {
        _ = openApplication(appURL: appURL, bundleIdentifier: bundleIdentifier)
        guard waitUntil(timeout: 5, { !visibleAXWindows(appElement).isEmpty }) else {
            recordFailure("initial_visible_timeout")
            continue
        }

        guard let window = preferredBenchmarkWindow(appElement) else {
            recordFailure("missing_benchmark_window")
            continue
        }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        guard let button = minimizeButton(for: window) else {
            debugAXTree(root: window)
            fputs("Unable to find AX minimize button.\n", stderr)
            exit(1)
        }

        let dismissStart = monotonicMs()
        let pressResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard pressResult == .success else {
            recordFailure("press_failed_\(pressResult.rawValue)")
            continue
        }
        guard waitUntil(timeout: 3, {
            !containsAXElement(visibleAXWindows(appElement), window) ||
                axBool(window, kAXMinimizedAttribute)
        }) else {
            let visibleCount = visibleAXWindows(appElement).count
            let minimizedCount = axWindows(appElement).filter { axBool($0, kAXMinimizedAttribute) }.count
            recordFailure("dismiss_timeout_visible_\(visibleCount)_minimized_\(minimizedCount)")
            continue
        }
        let dismissEnd = monotonicMs()
        let minimizedAfterDismiss = axWindows(appElement).contains { axBool($0, kAXMinimizedAttribute) }

        let restoreStart: Double
        if activateRestore, let running = runningApplication(bundleIdentifier: bundleIdentifier) {
            activateFinder(except: running)
            restoreStart = monotonicMs()
            running.activate(options: [.activateAllWindows])
        } else {
            restoreStart = monotonicMs()
            _ = openApplication(appURL: appURL, bundleIdentifier: bundleIdentifier)
        }
        guard waitUntil(timeout: 5, {
            preferredBenchmarkWindow(appElement) != nil && focusedAXWindow(appElement) != nil
        }) else {
            recordFailure("restore_timeout")
            continue
        }
        let restoreEnd = monotonicMs()

        samples.append(
            Sample(
                dismissMs: dismissEnd - dismissStart,
                restoreMs: restoreEnd - restoreStart,
                minimizedAfterDismiss: minimizedAfterDismiss
            )
        )
    }

    summarize("titlebar_dismiss_wall", samples.map(\.dismissMs))
    summarize("titlebar_restore_wall", samples.map(\.restoreMs))
    let minimizedCount = samples.filter(\.minimizedAfterDismiss).count
    print("titlebar_dismiss_minimized_after count=\(minimizedCount) total=\(samples.count)")
    let failureSummary = failuresByReason
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ",")
    print("failures=\(failuresByReason.values.reduce(0, +)) \(failureSummary)")
}

main()
