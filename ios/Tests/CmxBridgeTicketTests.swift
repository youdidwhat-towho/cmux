import Foundation
import XCTest
@testable import cmux_ios

final class CmxBridgeTicketTests: XCTestCase {
    func testWebSocketRouteNormalizesAttachPathAndExtractsToken() throws {
        let ticket = try CmxBridgeTicketParser.parse(
            """
            {
              "version": 1,
              "alpn": "/cmux/cmx/3",
              "endpoint": {
                "id": "local",
                "addrs": [
                  { "Custom": "ws://127.0.0.1:8787?token=sekrit" }
                ]
              },
              "auth": { "mode": "direct" }
            }
            """
        )

        XCTAssertEqual(ticket.webSocketURL?.absoluteString, "ws://127.0.0.1:8787/attach?token=sekrit")
        XCTAssertEqual(ticket.webSocketToken, "sekrit")
    }

    func testRouteLabelRedactsWebSocketToken() throws {
        let route = CmxTransportAddr.custom("ws://127.0.0.1:8787/attach?token=sekrit")

        XCTAssertEqual(route.label, "custom:ws://127.0.0.1:8787/attach?token=redacted")
    }

    func testRivetStackTicketRequiresCompleteAuthMetadata() {
        XCTAssertThrowsError(
            try CmxBridgeTicketParser.parse(
                """
                {
                  "version": 1,
                  "alpn": "/cmux/cmx/3",
                  "endpoint": { "id": "node", "addrs": [] },
                  "auth": {
                    "mode": "rivet_stack",
                    "pairing_id": "",
                    "rivet_endpoint": "https://rivet.example.test",
                    "stack_project_id": "stack-project",
                    "expires_at_unix": 4000000000
                  }
                }
                """
            )
        ) { error in
            XCTAssertEqual(error as? CmxTicketError, .missingPairingID)
        }
    }

    func testRivetStackTicketRejectsExpiredPairing() {
        XCTAssertThrowsError(
            try CmxBridgeTicketParser.parse(
                """
                {
                  "version": 1,
                  "alpn": "/cmux/cmx/3",
                  "endpoint": { "id": "node", "addrs": [] },
                  "auth": {
                    "mode": "rivet_stack",
                    "pairing_id": "pairing-1",
                    "rivet_endpoint": "https://rivet.example.test",
                    "stack_project_id": "stack-project",
                    "expires_at_unix": 10
                  }
                }
                """,
                now: Date(timeIntervalSince1970: 20)
            )
        ) { error in
            XCTAssertEqual(error as? CmxTicketError, .expiredPairing)
        }
    }

    func testLaunchConfigurationReadsTicketArgument() {
        XCTAssertEqual(
            CmxLaunchConfiguration.ticket(arguments: ["app", "--cmux-ticket", "ticket"], environment: [:]),
            "ticket"
        )
        XCTAssertTrue(
            CmxLaunchConfiguration.shouldAutoconnect(arguments: ["app", "--cmux-autoconnect"], environment: [:])
        )
    }

    func testLaunchConfigurationReadsJsonArrayArgument() {
        let arguments = ["app", "[\"--cmux-ticket\",\"ticket\",\"--cmux-autoconnect\"]"]

        XCTAssertEqual(CmxLaunchConfiguration.ticket(arguments: arguments, environment: [:]), "ticket")
        XCTAssertTrue(CmxLaunchConfiguration.shouldAutoconnect(arguments: arguments, environment: [:]))
    }
}
