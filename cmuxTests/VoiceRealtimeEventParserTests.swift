import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class VoiceRealtimeEventParserTests: XCTestCase {
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
}
