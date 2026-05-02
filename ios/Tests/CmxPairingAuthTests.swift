import XCTest
@testable import cmux_ios

final class CmxPairingAuthTests: XCTestCase {
    func testPairingProofMatchesRustBridgeVector() {
        XCTAssertEqual(
            CmxPairingAuth.proof(
                secret: "secret-a",
                pairingID: "pairing-1",
                clientNonce: "client-a",
                serverNonce: "server-a"
            ),
            "w62sYb9esNfmw-GwP36Z2ooce7olwxryi3xdRWVRpHs"
        )
    }

    func testPairingResponseValidatesChallengeBeforeProof() throws {
        let start = CmxPairingAuth.makeStart(pairingID: "pairing-1", clientNonce: "client-a")
        let challenge = CmxPairingChallenge(
            type: "pairing_challenge",
            pairingID: "pairing-1",
            serverNonce: "server-a",
            alpn: "/cmux/cmx/3"
        )

        let response = try CmxPairingAuth.makeResponse(
            secret: "secret-a",
            start: start,
            challenge: challenge
        )

        XCTAssertEqual(
            response,
            CmxPairingResponse(
                type: "pairing_response",
                pairingID: "pairing-1",
                proof: "w62sYb9esNfmw-GwP36Z2ooce7olwxryi3xdRWVRpHs"
            )
        )
    }

    func testPairingFramesEncodeAsNewlineTerminatedJson() throws {
        let start = CmxPairingAuth.makeStart(pairingID: "pairing-1", clientNonce: "client-a")

        let line = try CmxPairingAuth.encodeLine(start)

        XCTAssertEqual(line.last, 0x0A)
        XCTAssertTrue(String(decoding: line, as: UTF8.self).contains("\"pairing_id\":\"pairing-1\""))
    }

    func testPairingResponseRejectsWrongALPN() {
        let start = CmxPairingAuth.makeStart(pairingID: "pairing-1", clientNonce: "client-a")
        let challenge = CmxPairingChallenge(
            type: "pairing_challenge",
            pairingID: "pairing-1",
            serverNonce: "server-a",
            alpn: "wrong"
        )

        XCTAssertThrowsError(
            try CmxPairingAuth.makeResponse(secret: "secret-a", start: start, challenge: challenge)
        ) { error in
            XCTAssertEqual(error as? CmxPairingAuthError, .unsupportedALPN("wrong"))
        }
    }
}
