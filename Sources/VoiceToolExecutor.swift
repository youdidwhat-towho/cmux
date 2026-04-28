import Foundation

struct VoiceToolExecutionResult {
    let payload: [String: Any]

    var displaySummary: String {
        if let ok = payload["ok"] as? Bool, !ok {
            return String(localized: "voice.tool.failed", defaultValue: "Failed")
        }
        return String(localized: "voice.tool.done", defaultValue: "Done")
    }

    var outputJSONString: String {
        (try? VoiceJSON.string(from: payload)) ?? "{\"ok\":false,\"message\":\"Failed to encode tool result.\"}"
    }
}

@MainActor
final class VoiceToolExecutor {
    private struct FocusTarget {
        let targetType: String
        let id: String
    }

    private var lastFocusTarget: FocusTarget?
    private var lastWindowID: String?
    private var lastWorkspaceID: String?
    private var lastPaneID: String?
    private var lastSurfaceID: String?

    func execute(name: String, argumentsJSON: String) async -> VoiceToolExecutionResult {
        let arguments = VoiceJSON.parseArguments(argumentsJSON)

        switch name {
        case "cmux_get_context":
            return getContext()
        case "cmux_read_terminal":
            var params = targetParams(from: arguments)
            params["lines"] = intValue(arguments["lines"]) ?? 80
            params["scrollback"] = boolValue(arguments["scrollback"]) ?? true
            return callV2(method: "surface.read_text", params: params)
        case "cmux_create_workspace":
            var params = selectedParams(arguments, keys: [
                "title",
                "working_directory",
                "initial_command",
                "description"
            ])
            params["focus"] = boolValue(arguments["focus"]) ?? true
            return callV2(method: "workspace.create", params: params)
        case "cmux_rename_workspace":
            return renameWorkspace(arguments: arguments)
        case "cmux_create_terminal":
            var params = targetParams(from: arguments)
            params["type"] = "terminal"
            if let paneID = stringValue(arguments["pane_id"]) {
                params["pane_id"] = paneID
            }
            return callV2(method: "surface.create", params: params)
        case "cmux_create_split":
            var params = targetParams(from: arguments)
            params["direction"] = stringValue(arguments["direction"]) ?? "right"
            params["type"] = stringValue(arguments["type"]) ?? "terminal"
            if let url = stringValue(arguments["url"]) {
                params["url"] = url
            }
            return callV2(method: "pane.create", params: params)
        case "cmux_run_command":
            let command = stringValue(arguments["command"]) ?? ""
            guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return failure(message: "Missing command.", code: "missing_command")
            }
            guard boolValue(arguments["confirmed"]) == true else {
                return VoiceToolExecutionResult(payload: [
                    "ok": false,
                    "requires_confirmation": true,
                    "command": command,
                    "message": "Ask the user to confirm before running this command."
                ])
            }
            var params = targetParams(from: arguments)
            params["text"] = command.hasSuffix("\n") ? command : "\(command)\n"
            return callV2(method: "surface.send_text", params: params)
        case "cmux_type_text":
            guard let text = stringValue(arguments["text"]) else {
                return failure(message: "Missing text.", code: "missing_text")
            }
            var params = targetParams(from: arguments)
            let shouldSubmit = boolValue(arguments["submit"]) ?? false
            params["text"] = shouldSubmit && !text.hasSuffix("\n") ? "\(text)\n" : text
            return callV2(method: "surface.send_text", params: params)
        case "cmux_open_browser":
            guard let url = stringValue(arguments["url"]) else {
                return failure(message: "Missing URL.", code: "missing_url")
            }
            var params = targetParams(from: arguments)
            params["url"] = url
            return callV2(method: "browser.open_split", params: params)
        case "cmux_browser_snapshot":
            var params = targetParams(from: arguments)
            params["compact"] = true
            params["max_depth"] = intValue(arguments["max_depth"]) ?? 8
            params["interactive"] = boolValue(arguments["interactive"]) ?? false
            return callV2(method: "browser.snapshot", params: params)
        case "cmux_browser_navigate":
            guard let url = stringValue(arguments["url"]) else {
                return failure(message: "Missing URL.", code: "missing_url")
            }
            var params = targetParams(from: arguments)
            params["url"] = url
            return callV2(method: "browser.navigate", params: params)
        case "cmux_browser_click":
            guard let selector = stringValue(arguments["selector"]) else {
                return failure(message: "Missing selector.", code: "missing_selector")
            }
            var params = targetParams(from: arguments)
            params["selector"] = selector
            return callV2(method: "browser.click", params: params)
        case "cmux_browser_type":
            guard let selector = stringValue(arguments["selector"]),
                  let text = stringValue(arguments["text"]) else {
                return failure(message: "Missing selector or text.", code: "missing_browser_type_params")
            }
            var params = targetParams(from: arguments)
            params["selector"] = selector
            params["text"] = text
            let method = (boolValue(arguments["replace"]) ?? true) ? "browser.fill" : "browser.type"
            return callV2(method: method, params: params)
        case "cmux_focus":
            return focus(arguments: arguments)
        default:
            return failure(message: "Unknown voice tool: \(name)", code: "unknown_tool")
        }
    }

    private func renameWorkspace(arguments: [String: Any]) -> VoiceToolExecutionResult {
        guard let title = stringValue(arguments["title"]) else {
            return failure(message: "Missing title.", code: "missing_title")
        }

        var params = targetParams(from: arguments)
        if params["workspace_id"] == nil {
            if let lastWorkspaceID {
                params["workspace_id"] = lastWorkspaceID
            } else if let currentWorkspaceID = currentWorkspaceID() {
                params["workspace_id"] = currentWorkspaceID
            }
        }
        params["title"] = title
        return callV2(method: "workspace.rename", params: params)
    }

    private func currentWorkspaceID() -> String? {
        let payload = callV2(method: "workspace.current", params: [:]).payload
        guard payload["ok"] as? Bool == true,
              let result = payload["result"] as? [String: Any] else {
            return nil
        }
        return stringValue(result["workspace_id"])
    }

    private func getContext() -> VoiceToolExecutionResult {
        let identify = callV2(method: "system.identify", params: [:]).payload
        let tree = callV2(method: "system.tree", params: ["all_windows": true]).payload
        return VoiceToolExecutionResult(payload: [
            "ok": true,
            "identify": identify,
            "tree": tree
        ])
    }

    private func focus(arguments: [String: Any]) -> VoiceToolExecutionResult {
        guard let target = resolvedFocusTarget(from: arguments) else {
            return failure(message: "Missing focus target.", code: "missing_focus_target")
        }

        switch target.targetType {
        case "window":
            return callV2(method: "window.focus", params: ["window_id": target.id])
        case "workspace":
            return callV2(method: "workspace.select", params: ["workspace_id": target.id])
        case "pane":
            return callV2(method: "pane.focus", params: ["pane_id": target.id])
        case "surface":
            return callV2(method: "surface.focus", params: ["surface_id": target.id])
        default:
            return failure(message: "Unsupported focus target: \(target.targetType)", code: "unsupported_focus_target")
        }
    }

    private func resolvedFocusTarget(from arguments: [String: Any]) -> FocusTarget? {
        let requestedTargetType = stringValue(arguments["target_type"])
        let requestedID = stringValue(arguments["id"])

        if let requestedTargetType,
           let requestedID {
            return FocusTarget(targetType: requestedTargetType, id: requestedID)
        }

        if let requestedTargetType,
           let rememberedID = rememberedID(for: requestedTargetType) {
            return FocusTarget(targetType: requestedTargetType, id: rememberedID)
        }

        if let requestedID,
           let rememberedTargetType = rememberedTargetType(for: requestedID) ?? lastFocusTarget?.targetType {
            return FocusTarget(targetType: rememberedTargetType, id: requestedID)
        }

        return lastFocusTarget
    }

    private func rememberedTargetType(for id: String) -> String? {
        if lastWindowID == id {
            return "window"
        }
        if lastWorkspaceID == id {
            return "workspace"
        }
        if lastPaneID == id {
            return "pane"
        }
        if lastSurfaceID == id {
            return "surface"
        }
        return nil
    }

    private func rememberedID(for targetType: String) -> String? {
        switch targetType {
        case "window":
            return lastWindowID
        case "workspace":
            return lastWorkspaceID
        case "pane":
            return lastPaneID
        case "surface":
            return lastSurfaceID
        default:
            return nil
        }
    }

    private func callV2(method: String, params: [String: Any]) -> VoiceToolExecutionResult {
        let request: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]

        do {
            let line = try VoiceJSON.string(from: request)
            let response = TerminalController.shared.handleSocketLine(line)
            guard let object = VoiceJSON.dictionary(fromJSONString: response) else {
                return failure(message: response, code: "invalid_rpc_response", method: method)
            }
            if object["ok"] as? Bool == true {
                let payload: [String: Any] = [
                    "ok": true,
                    "method": method,
                    "result": object["result"] ?? NSNull()
                ]
                rememberFocusTargets(from: payload)
                return VoiceToolExecutionResult(payload: payload)
            }
            return VoiceToolExecutionResult(payload: [
                "ok": false,
                "method": method,
                "error": object["error"] ?? object
            ])
        } catch {
            return failure(message: error.localizedDescription, code: "rpc_encoding_failed", method: method)
        }
    }

    private func rememberFocusTargets(from payload: [String: Any]) {
        let result = (payload["result"] as? [String: Any]) ?? payload
        if let windowID = stringValue(result["window_id"]) {
            lastWindowID = windowID
            lastFocusTarget = FocusTarget(targetType: "window", id: windowID)
        }
        if let workspaceID = stringValue(result["workspace_id"]) {
            lastWorkspaceID = workspaceID
            lastFocusTarget = FocusTarget(targetType: "workspace", id: workspaceID)
        }
        if let paneID = stringValue(result["pane_id"]) {
            lastPaneID = paneID
            lastFocusTarget = FocusTarget(targetType: "pane", id: paneID)
        }
        if let surfaceID = stringValue(result["surface_id"]) {
            lastSurfaceID = surfaceID
            lastFocusTarget = FocusTarget(targetType: "surface", id: surfaceID)
        }
    }

    private func failure(message: String, code: String, method: String? = nil) -> VoiceToolExecutionResult {
        var payload: [String: Any] = [
            "ok": false,
            "code": code,
            "message": message
        ]
        if let method {
            payload["method"] = method
        }
        return VoiceToolExecutionResult(payload: payload)
    }

    private func targetParams(from arguments: [String: Any]) -> [String: Any] {
        selectedParams(arguments, keys: ["window_id", "workspace_id", "pane_id", "surface_id"])
    }

    private func selectedParams(_ arguments: [String: Any], keys: [String]) -> [String: Any] {
        var params: [String: Any] = [:]
        for key in keys {
            if let value = stringValue(arguments[key]) {
                params[key] = value
            }
        }
        return params
    }
}

private func stringValue(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : string
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
        return int
    }
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let string = value as? String {
        return Int(string)
    }
    return nil
}

private func boolValue(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
        return bool
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    if let string = value as? String {
        switch string.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }
    return nil
}
