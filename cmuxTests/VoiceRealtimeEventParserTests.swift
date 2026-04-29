import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class VoiceRealtimeEventParserTests: XCTestCase {
    private let settingsFileBackupsDefaultsKey = "cmux.settingsFile.backups.v1"

    @MainActor
    func testVoiceToolsExposeWorkspaceFocusAndImplicitFocusTarget() {
        let tools = VoiceToolExecutor().toolDefinitions

        let createWorkspace = tools.first { $0["name"] as? String == "cmux_create_workspace" }
        let workspaceParameters = createWorkspace?["parameters"] as? [String: Any]
        let workspaceProperties = workspaceParameters?["properties"] as? [String: Any]
        XCTAssertNotNil(workspaceProperties?["focus"])

        let renameWorkspace = tools.first { $0["name"] as? String == "cmux_rename_workspace" }
        let renameParameters = renameWorkspace?["parameters"] as? [String: Any]
        let renameRequired = renameParameters?["required"] as? [String]
        XCTAssertEqual(renameRequired, ["title"])

        let typeText = tools.first { $0["name"] as? String == "cmux_type_text" }
        let typeTextParameters = typeText?["parameters"] as? [String: Any]
        let typeTextRequired = typeTextParameters?["required"] as? [String]
        XCTAssertEqual(typeTextRequired, ["text"])

        let focus = tools.first { $0["name"] as? String == "cmux_focus" }
        let focusParameters = focus?["parameters"] as? [String: Any]
        let required = focusParameters?["required"] as? [String]
        XCTAssertTrue(required?.isEmpty ?? false)
    }

    func testDefaultPromptDescribesAgentWorkspaceCommands() {
        let instructions = VoiceAgentViewModel.defaultInstructions

        XCTAssertTrue(instructions.contains("working_directory"))
        XCTAssertTrue(instructions.contains("claude --dangerously-skip-permissions"))
        XCTAssertTrue(instructions.contains("codex --yolo"))
        XCTAssertTrue(instructions.contains("Cloud Code"))
    }

    func testVoicePromptSettingsPrefixAndOverrideComposition() {
        XCTAssertEqual(
            VoicePromptSettings.compose(defaultInstructions: "DEFAULT", prefix: "PREFIX", override: ""),
            "PREFIX\n\nDEFAULT"
        )
        XCTAssertEqual(
            VoicePromptSettings.compose(defaultInstructions: "DEFAULT", prefix: "PREFIX", override: "OVERRIDE"),
            "OVERRIDE"
        )
        XCTAssertEqual(
            VoicePromptSettings.compose(defaultInstructions: "DEFAULT", prefix: "  ", override: nil),
            "DEFAULT"
        )
    }

    func testSettingsFileStoreParsesVoicePromptSettings() throws {
        let defaults = UserDefaults.standard
        let previousPrefix = defaults.object(forKey: VoicePromptSettings.systemPromptPrefixKey)
        let previousOverride = defaults.object(forKey: VoicePromptSettings.systemPromptOverrideKey)
        let previousBackups = defaults.data(forKey: settingsFileBackupsDefaultsKey)
        defer {
            restoreDefaultsValue(previousPrefix, key: VoicePromptSettings.systemPromptPrefixKey, defaults: defaults)
            restoreDefaultsValue(previousOverride, key: VoicePromptSettings.systemPromptOverrideKey, defaults: defaults)
            if let previousBackups {
                defaults.set(previousBackups, forKey: settingsFileBackupsDefaultsKey)
            } else {
                defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)
            }
        }

        defaults.removeObject(forKey: VoicePromptSettings.systemPromptPrefixKey)
        defaults.removeObject(forKey: VoicePromptSettings.systemPromptOverrideKey)
        defaults.removeObject(forKey: settingsFileBackupsDefaultsKey)

        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsFileURL = directoryURL.appendingPathComponent("settings.json", isDirectory: false)
        try writeSettingsFile(
            """
            {
              "voice": {
                "systemPromptPrefix": "Always focus created workspaces.",
                "systemPromptOverride": "You are a custom cmux voice agent."
              }
            }
            """,
            to: settingsFileURL
        )

        _ = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(
            defaults.string(forKey: VoicePromptSettings.systemPromptPrefixKey),
            "Always focus created workspaces."
        )
        XCTAssertEqual(
            defaults.string(forKey: VoicePromptSettings.systemPromptOverrideKey),
            "You are a custom cmux voice agent."
        )
    }

    @MainActor
    func testAssistantTranscriptPartsStayInOneRenderedMessageUntilResponseDone() {
        let viewModel = VoiceAgentViewModel()

        viewModel.voiceRealtimeBridge(
            viewModel.bridge,
            didReceiveMessage: serverEvent(["type": "response.created"])
        )
        viewModel.voiceRealtimeBridge(
            viewModel.bridge,
            didReceiveMessage: serverEvent([
                "type": "response.output_audio_transcript.delta",
                "delta": "Sure, what title would you like?"
            ])
        )
        viewModel.voiceRealtimeBridge(
            viewModel.bridge,
            didReceiveMessage: serverEvent([
                "type": "response.output_audio_transcript.done",
                "transcript": "Sure, what title would you like?"
            ])
        )
        viewModel.voiceRealtimeBridge(
            viewModel.bridge,
            didReceiveMessage: serverEvent([
                "type": "response.output_audio_transcript.delta",
                "delta": " Just tell me the title."
            ])
        )
        viewModel.voiceRealtimeBridge(
            viewModel.bridge,
            didReceiveMessage: serverEvent(["type": "response.done"])
        )

        let assistantItems = viewModel.transcript.filter { $0.role == .assistant }
        XCTAssertEqual(assistantItems.count, 1)
        XCTAssertEqual(
            assistantItems.first?.text,
            "Sure, what title would you like? Just tell me the title."
        )
    }

    func testExtractsFunctionCallsFromResponseDone() {
        let event: [String: Any] = [
            "type": "response.done",
            "response": [
                "output": [
                    [
                        "type": "function_call",
                        "name": "cmux_get_context",
                        "call_id": "call_123",
                        "arguments": "{}"
                    ]
                ]
            ]
        ]

        XCTAssertEqual(
            VoiceRealtimeEventParser.functionCalls(in: event),
            [
                VoiceRealtimeFunctionCall(
                    callID: "call_123",
                    name: "cmux_get_context",
                    arguments: "{}"
                )
            ]
        )
    }

    func testExtractsFunctionCallOnlyAfterOutputItemDone() {
        let item: [String: Any] = [
            "type": "function_call",
            "status": "completed",
            "name": "cmux_create_split",
            "call_id": "call_done",
            "arguments": "{\"direction\":\"right\"}"
        ]

        XCTAssertEqual(
            VoiceRealtimeEventParser.functionCalls(in: [
                "type": "response.output_item.added",
                "item": item
            ]),
            []
        )

        XCTAssertEqual(
            VoiceRealtimeEventParser.functionCalls(in: [
                "type": "response.output_item.done",
                "item": item
            ]),
            [
                VoiceRealtimeFunctionCall(
                    callID: "call_done",
                    name: "cmux_create_split",
                    arguments: "{\"direction\":\"right\"}"
                )
            ]
        )
    }

    @MainActor
    func testResponseCreateSequencerWaitsForResponseDoneAndCoalescesRequests() {
        var sentEvents: [[String: Any]] = []
        let sequencer = VoiceResponseCreateSequencer(
            isConnected: { true },
            hasBlockers: { false },
            sendEvent: { sentEvents.append($0) }
        )

        sequencer.markResponseCreated()
        sequencer.requestResponseCreate()
        sequencer.requestResponseCreate()
        XCTAssertTrue(sentEvents.isEmpty)

        sequencer.markResponseDone()
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents.first?["type"] as? String, "response.create")
    }

    @MainActor
    func testResponseCreateSequencerRetriesAfterActiveResponseConflict() {
        var sentEvents: [[String: Any]] = []
        let sequencer = VoiceResponseCreateSequencer(
            isConnected: { true },
            hasBlockers: { false },
            sendEvent: { sentEvents.append($0) }
        )

        sequencer.requestResponseCreate()
        XCTAssertEqual(sentEvents.count, 1)

        sequencer.markActiveResponseConflict()
        sequencer.markResponseDone()
        XCTAssertEqual(sentEvents.count, 2)
        XCTAssertNotEqual(
            sentEvents[0]["event_id"] as? String,
            sentEvents[1]["event_id"] as? String
        )
    }

    func testParsesOpenAIKeyFromEnvFile() {
        let key = OpenAIAPIKeyResolver.parseAPIKey(from: """
        # comment
        OPENAI_API_KEY="sk-proj-test"
        """)

        XCTAssertEqual(key, "sk-proj-test")
    }

    func testReadsAssistantTranscriptDelta() {
        let event: [String: Any] = [
            "type": "response.output_audio_transcript.delta",
            "delta": "hello"
        ]

        XCTAssertEqual(VoiceRealtimeEventParser.assistantDelta(in: event), "hello")
    }

    func testReadsUserTranscriptionDelta() {
        let event: [String: Any] = [
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "item_123",
            "delta": "open"
        ]

        XCTAssertEqual(
            VoiceRealtimeEventParser.userTranscriptionDelta(in: event),
            VoiceRealtimeTextDelta(itemID: "item_123", text: "open")
        )
    }

    func testReadsSpeechStartedItemID() {
        let event: [String: Any] = [
            "type": "input_audio_buffer.speech_started",
            "item_id": "item_456"
        ]

        XCTAssertEqual(VoiceRealtimeEventParser.speechStartedItemID(in: event), "item_456")
    }

    func testDetectsActiveResponseError() {
        let event: [String: Any] = [
            "type": "error",
            "error": [
                "code": "conversation_already_has_active_response",
                "message": "Conversation already has an active response in progress."
            ]
        ]

        XCTAssertTrue(VoiceRealtimeEventParser.isActiveResponseError(in: event))
    }

    private func serverEvent(_ event: [String: Any]) -> [String: Any] {
        [
            "kind": "server_event",
            "event": event
        ]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func writeSettingsFile(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func restoreDefaultsValue(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
