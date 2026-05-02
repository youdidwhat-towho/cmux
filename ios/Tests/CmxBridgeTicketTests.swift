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

    func testTicketDecodesNodeMetadataForHiveDiscovery() throws {
        let ticket = try CmxBridgeTicketParser.parse(
            """
            {
              "version": 1,
              "alpn": "/cmux/cmx/3",
              "endpoint": {
                "id": "endpoint-public-key",
                "addrs": [
                  { "Custom": "ws://127.0.0.1:8787?token=sekrit" }
                ]
              },
              "auth": {
                "mode": "rivet_stack",
                "pairing_id": "pairing-1",
                "rivet_endpoint": "https://rivet.example.test",
                "stack_project_id": "stack-project",
                "expires_at_unix": 4000000000
              },
              "node": {
                "id": "node-mbp",
                "name": "Lawrence MacBook Pro",
                "subtitle": "local dev node",
                "kind": "macbook"
              }
            }
            """
        )

        XCTAssertEqual(
            ticket.node,
            CmxBridgeTicketNode(
                id: "node-mbp",
                name: "Lawrence MacBook Pro",
                subtitle: "local dev node",
                kind: "macbook"
            )
        )
        let node = CmxHiveNodeFactory.connectedNode(for: ticket)
        XCTAssertEqual(node.name, "Lawrence MacBook Pro")
        XCTAssertEqual(node.subtitle, "local dev node")
        XCTAssertEqual(node.symbolName, "laptopcomputer")
        XCTAssertTrue(node.isOnline)
    }

    func testTicketWithoutNodeMetadataUsesStableEndpointFallbackNode() throws {
        let ticket = try CmxBridgeTicketParser.parse(
            """
            {
              "version": 1,
              "alpn": "/cmux/cmx/3",
              "endpoint": {
                "id": "abcdefghijklmnopqrstuvwxyz",
                "addrs": []
              },
              "auth": { "mode": "direct" }
            }
            """
        )

        let first = CmxHiveNodeFactory.connectedNode(for: ticket)
        let second = CmxHiveNodeFactory.connectedNode(for: ticket)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.name, "cmx node")
        XCTAssertEqual(first.subtitle, "abcdef...uvwxyz")
        XCTAssertEqual(first.symbolName, "terminal")
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
