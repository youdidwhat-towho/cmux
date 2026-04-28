import Foundation

extension VoiceToolExecutor {
    var toolDefinitions: [[String: Any]] {
        [
            voiceTool(
                name: "cmux_get_context",
                description: "Get the current cmux window, workspace, pane, and surface tree. Use this before choosing a target when the user is ambiguous.",
                properties: [:]
            ),
            voiceTool(
                name: "cmux_read_terminal",
                description: "Read visible terminal text or recent scrollback from a terminal surface.",
                properties: voiceCommonTargetProperties().merging([
                    "lines": voiceIntegerProperty("Maximum number of recent lines to read. Defaults to 80."),
                    "scrollback": voiceBooleanProperty("Include scrollback.")
                ]) { current, _ in current }
            ),
            voiceTool(
                name: "cmux_create_workspace",
                description: "Create a new cmux workspace.",
                properties: [
                    "title": voiceStringProperty("Optional workspace title."),
                    "working_directory": voiceStringProperty("Optional working directory."),
                    "initial_command": voiceStringProperty("Optional command to run in the initial terminal."),
                    "description": voiceStringProperty("Optional workspace description."),
                    "focus": voiceBooleanProperty("Select and focus the new workspace. Defaults to true.")
                ]
            ),
            voiceTool(
                name: "cmux_rename_workspace",
                description: "Rename a workspace. If workspace_id is omitted, rename the most recently created or focused workspace.",
                properties: voiceCommonTargetProperties().merging([
                    "title": voiceStringProperty("New workspace title.")
                ]) { current, _ in current },
                required: ["title"]
            ),
            voiceTool(
                name: "cmux_create_terminal",
                description: "Create a new terminal surface in the focused pane or a specified pane.",
                properties: voiceCommonTargetProperties().merging([
                    "pane_id": voiceStringProperty("Optional pane UUID to receive the terminal.")
                ]) { current, _ in current }
            ),
            voiceTool(
                name: "cmux_create_split",
                description: "Create a split pane with a terminal or browser.",
                properties: voiceCommonTargetProperties().merging([
                    "direction": [
                        "type": "string",
                        "description": "Split direction.",
                        "enum": ["left", "right", "up", "down"]
                    ],
                    "type": [
                        "type": "string",
                        "description": "Surface type for the new split.",
                        "enum": ["terminal", "browser"]
                    ],
                    "url": voiceStringProperty("URL when creating a browser split.")
                ]) { current, _ in current },
                required: ["direction"]
            ),
            voiceTool(
                name: "cmux_run_command",
                description: "Run a shell command in a terminal by sending text followed by Enter. Set confirmed true only when the user explicitly asked to run this exact command or confirmed it.",
                properties: voiceCommonTargetProperties().merging([
                    "command": voiceStringProperty("The exact shell command to run."),
                    "confirmed": voiceBooleanProperty("True only when the user explicitly asked to run this command or confirmed it.")
                ]) { current, _ in current },
                required: ["command", "confirmed"]
            ),
            voiceTool(
                name: "cmux_type_text",
                description: "Type literal text into a terminal without treating it as a shell command.",
                properties: voiceCommonTargetProperties().merging([
                    "text": voiceStringProperty("The exact text to type."),
                    "submit": voiceBooleanProperty("Press Enter after typing. Defaults to false.")
                ]) { current, _ in current },
                required: ["text"]
            ),
            voiceTool(
                name: "cmux_open_browser",
                description: "Open a browser split for a URL.",
                properties: voiceCommonTargetProperties().merging([
                    "url": voiceStringProperty("The URL to open.")
                ]) { current, _ in current },
                required: ["url"]
            ),
            voiceTool(
                name: "cmux_browser_snapshot",
                description: "Return a compact accessibility-like snapshot for a browser surface.",
                properties: voiceCommonTargetProperties().merging([
                    "surface_id": voiceStringProperty("Browser surface UUID."),
                    "max_depth": voiceIntegerProperty("Maximum DOM depth. Defaults to 8."),
                    "interactive": voiceBooleanProperty("Only include interactive nodes.")
                ]) { current, _ in current }
            ),
            voiceTool(
                name: "cmux_browser_navigate",
                description: "Navigate a browser surface to a URL.",
                properties: voiceCommonTargetProperties().merging([
                    "surface_id": voiceStringProperty("Browser surface UUID."),
                    "url": voiceStringProperty("The URL to navigate to.")
                ]) { current, _ in current },
                required: ["url"]
            ),
            voiceTool(
                name: "cmux_browser_click",
                description: "Click an element in a browser surface by selector or element ref from a snapshot.",
                properties: voiceCommonTargetProperties().merging([
                    "surface_id": voiceStringProperty("Browser surface UUID."),
                    "selector": voiceStringProperty("CSS selector or element ref, such as @e1.")
                ]) { current, _ in current },
                required: ["selector"]
            ),
            voiceTool(
                name: "cmux_browser_type",
                description: "Type or fill text into a browser element.",
                properties: voiceCommonTargetProperties().merging([
                    "surface_id": voiceStringProperty("Browser surface UUID."),
                    "selector": voiceStringProperty("CSS selector or element ref, such as @e1."),
                    "text": voiceStringProperty("Text to enter."),
                    "replace": voiceBooleanProperty("Replace existing value instead of typing into the element. Defaults to true.")
                ]) { current, _ in current },
                required: ["selector", "text"]
            ),
            voiceTool(
                name: "cmux_focus",
                description: "Focus a cmux window, workspace, pane, or surface by UUID. If the id is omitted, focus the most recently created or referenced object.",
                properties: [
                    "target_type": [
                        "type": "string",
                        "description": "Object type to focus. Omit this to focus the most recently created or referenced object.",
                        "enum": ["window", "workspace", "pane", "surface"]
                    ],
                    "id": voiceStringProperty("The UUID for the target. Omit this to focus the most recently created or referenced object of target_type.")
                ]
            )
        ]
    }
}

private func voiceTool(
    name: String,
    description: String,
    properties: [String: Any],
    required: [String] = []
) -> [String: Any] {
    [
        "type": "function",
        "name": name,
        "description": description,
        "parameters": [
            "type": "object",
            "properties": properties,
            "required": required
        ]
    ]
}

private func voiceCommonTargetProperties() -> [String: Any] {
    [
        "window_id": voiceStringProperty("Optional target window UUID."),
        "workspace_id": voiceStringProperty("Optional target workspace UUID."),
        "pane_id": voiceStringProperty("Optional target pane UUID."),
        "surface_id": voiceStringProperty("Optional target surface UUID.")
    ]
}

private func voiceStringProperty(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
}

private func voiceIntegerProperty(_ description: String) -> [String: Any] {
    ["type": "integer", "description": description]
}

private func voiceBooleanProperty(_ description: String) -> [String: Any] {
    ["type": "boolean", "description": description]
}
