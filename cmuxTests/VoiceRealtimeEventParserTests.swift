import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class VoiceRealtimeEventParserTests: XCTestCase {
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
}
