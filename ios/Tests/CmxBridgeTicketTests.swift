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
        XCTAssertEqual(node.platform, .macOS)
        XCTAssertTrue(node.isOnline)
    }

    func testTicketNodePlatformDetectsLinuxAndMacModifierStyle() throws {
        let mac = try CmxBridgeTicketParser.parse(
            """
            {
              "version": 1,
              "alpn": "/cmux/cmx/3",
              "endpoint": { "id": "mac-endpoint", "addrs": [] },
              "auth": { "mode": "direct" },
              "node": {
                "id": "node-mac",
                "name": "Lawrence Mac mini",
                "kind": "darwin"
              }
            }
            """
        )
        let linux = try CmxBridgeTicketParser.parse(
            """
            {
              "version": 1,
              "alpn": "/cmux/cmx/3",
              "endpoint": { "id": "linux-endpoint", "addrs": [] },
              "auth": { "mode": "direct" },
              "node": {
                "id": "node-linux",
                "name": "Build server",
                "kind": "linux"
              }
            }
            """
        )

        XCTAssertEqual(CmxHiveNodeFactory.connectedNode(for: mac).platform, .macOS)
        XCTAssertEqual(CmxHiveNodeFactory.connectedNode(for: linux).platform, .linux)
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

    func testStackAuthCallbackParsesNativeDeepLinkWithoutLeakingTokens() throws {
        let accessPayload = #"["refresh-cookie","access-token"]"#
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "cmux-dev://auth-callback?stack_refresh=refresh-explicit&stack_access=\(accessPayload)")!

        let session = try CmxStackAuthCallback.parse(url: url)

        XCTAssertEqual(session.refreshToken, "refresh-explicit")
        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.authorizationHeaders["Authorization"], "Bearer access-token")
        XCTAssertEqual(session.authorizationHeaders["X-Stack-Refresh-Token"], "refresh-explicit")
        XCTAssertFalse(String(describing: session).contains("access-token"))
        XCTAssertFalse(String(describing: session).contains("refresh-explicit"))
    }

    func testStackAuthCallbackRejectsMissingTokens() {
        XCTAssertThrowsError(
            try CmxStackAuthCallback.parse(url: URL(string: "cmux://auth-callback?stack_refresh=refresh")!)
        ) { error in
            XCTAssertEqual(error as? CmxStackAuthCallbackError, .missingTokens)
        }
    }

    @MainActor
    func testConnectionStorePersistsStackAuthCallbackAndCanSignOut() {
        let sessionStore = MemoryStackAuthSessionStore()
        let store = CmxConnectionStore(authSessionStore: sessionStore)

        store.handleOpenURL(URL(string: "cmux://auth-callback?stack_refresh=refresh&stack_access=access")!)

        XCTAssertEqual(store.stackAuthSession, CmxStackAuthSession(refreshToken: "refresh", accessToken: "access"))
        XCTAssertEqual(sessionStore.session, CmxStackAuthSession(refreshToken: "refresh", accessToken: "access"))

        store.signOut()

        XCTAssertNil(store.stackAuthSession)
        XCTAssertNil(sessionStore.session)
    }

    @MainActor
    func testRivetStackTicketRequiresStoredStackSessionBeforeConnect() {
        let store = CmxConnectionStore(
            authSessionStore: MemoryStackAuthSessionStore(),
            pairingSecretClient: RecordingPairingSecretClient()
        )
        store.ticketText = """
        {
          "version": 1,
          "alpn": "/cmux/cmx/3",
          "endpoint": {
            "id": "endpoint-public-key",
            "addrs": [
              { "Custom": "ws://127.0.0.1:8787?token=dev" }
            ]
          },
          "auth": {
            "mode": "rivet_stack",
            "pairing_id": "pairing-1",
            "rivet_endpoint": "https://rivet.example.test",
            "stack_project_id": "stack-project",
            "expires_at_unix": 4000000000
          }
        }
        """

        store.connect()

        XCTAssertNil(store.ticket)
        XCTAssertFalse(store.isConnecting)
        XCTAssertFalse(store.isConnected)
        XCTAssertEqual(store.errorText, CmxConnectionError.missingStackAuthSession.errorDescription)
    }

    @MainActor
    func testRivetStackTicketFetchesPairingSecretBeforeOpeningTransport() async {
        let sessionStore = MemoryStackAuthSessionStore()
        sessionStore.session = CmxStackAuthSession(refreshToken: "refresh", accessToken: "access")
        let secretClient = RecordingPairingSecretClient()
        let store = CmxConnectionStore(authSessionStore: sessionStore, pairingSecretClient: secretClient)
        store.ticketText = """
        {
          "version": 1,
          "alpn": "/cmux/cmx/3",
          "endpoint": { "id": "endpoint-public-key", "addrs": [] },
          "auth": {
            "mode": "rivet_stack",
            "pairing_id": "pairing-1",
            "rivet_endpoint": "https://rivet.example.test/cmux",
            "stack_project_id": "stack-project",
            "expires_at_unix": 4000000000
          }
        }
        """

        store.connect()
        await secretClient.waitForFetch()

        XCTAssertEqual(secretClient.fetchCount, 1)
        XCTAssertEqual(secretClient.lastStackSession, sessionStore.session)
        XCTAssertEqual(store.errorText, CmxConnectionError.missingWebSocketRoute.errorDescription)
    }
}

private final class MemoryStackAuthSessionStore: CmxStackAuthSessionStore {
    var session: CmxStackAuthSession?

    func load() throws -> CmxStackAuthSession? {
        session
    }

    func save(_ session: CmxStackAuthSession) throws {
        self.session = session
    }

    func clear() throws {
        session = nil
    }
}

private final class RecordingPairingSecretClient: CmxRivetPairingSecretFetching {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var fetchCount = 0
    private(set) var lastStackSession: CmxStackAuthSession?

    func fetchSecret(
        for auth: CmxBridgeTicketAuth,
        stackSession: CmxStackAuthSession,
        now: Date
    ) async throws -> CmxRivetPairingSecret {
        fetchCount += 1
        lastStackSession = stackSession
        continuation?.resume()
        continuation = nil
        return CmxRivetPairingSecret(pairingID: auth.pairingID ?? "", secret: "rivet-secret", expiresAtUnix: 4000000000)
    }

    func waitForFetch() async {
        if fetchCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
