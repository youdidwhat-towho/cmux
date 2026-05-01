import Foundation

struct CmxBridgeTicket: Decodable, Equatable {
    let version: Int
    let alpn: String
    let endpoint: CmxEndpointAddr
    let auth: CmxBridgeTicketAuth?
}

struct CmxEndpointAddr: Decodable, Equatable {
    let id: String
    let addrs: [CmxTransportAddr]
}

enum CmxBridgeTicketAuth: Decodable, Equatable {
    case direct
    case rivetStack(pairingID: String, rivetEndpoint: String, stackProjectID: String, expiresAtUnix: UInt64)
    case unknown(String)

    var label: String {
        switch self {
        case .direct:
            return String(localized: "ticket.auth.direct", defaultValue: "direct development ticket")
        case .rivetStack(let pairingID, _, _, _):
            return String(
                format: String(localized: "ticket.auth.rivet_stack", defaultValue: "Stack + Rivet pairing %@"),
                pairingID
            )
        case .unknown(let mode):
            return String(
                format: String(localized: "ticket.auth.unknown", defaultValue: "unknown auth %@"),
                mode
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case pairingID = "pairing_id"
        case rivetEndpoint = "rivet_endpoint"
        case stackProjectID = "stack_project_id"
        case expiresAtUnix = "expires_at_unix"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        switch mode {
        case "direct":
            self = .direct
        case "rivet_stack":
            self = .rivetStack(
                pairingID: try container.decode(String.self, forKey: .pairingID),
                rivetEndpoint: try container.decode(String.self, forKey: .rivetEndpoint),
                stackProjectID: try container.decode(String.self, forKey: .stackProjectID),
                expiresAtUnix: try container.decode(UInt64.self, forKey: .expiresAtUnix)
            )
        default:
            self = .unknown(mode)
        }
    }
}

enum CmxTransportAddr: Equatable, Identifiable {
    case relay(String)
    case ip(String)
    case custom(String)
    case unknown(String)

    var id: String { label }

    var label: String {
        switch self {
        case .relay(let value):
            return String(
                format: String(localized: "ticket.route.relay", defaultValue: "relay:%@"),
                value
            )
        case .ip(let value):
            return String(
                format: String(localized: "ticket.route.ip", defaultValue: "ip:%@"),
                value
            )
        case .custom(let value):
            return String(
                format: String(localized: "ticket.route.custom", defaultValue: "custom:%@"),
                value
            )
        case .unknown(let value):
            return value
        }
    }
}

extension CmxTransportAddr: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let keyed = try? container.decode([String: String].self),
           let first = keyed.first {
            switch first.key {
            case "Relay":
                self = .relay(first.value)
            case "Ip":
                self = .ip(first.value)
            case "Custom":
                self = .custom(first.value)
            default:
                self = .unknown(
                    String(
                        format: String(localized: "ticket.route.keyed_unknown", defaultValue: "%@:%@"),
                        first.key,
                        first.value
                    )
                )
            }
            return
        }

        if let value = try? container.decode(String.self) {
            self = .unknown(value)
            return
        }

        self = .unknown(String(localized: "ticket.route.unknown", defaultValue: "unknown route"))
    }
}

enum CmxBridgeTicketParser {
    static func parse(_ rawTicket: String) throws -> CmxBridgeTicket {
        let trimmed = rawTicket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CmxTicketError.empty
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw CmxTicketError.invalidUTF8
        }
        let ticket = try JSONDecoder().decode(CmxBridgeTicket.self, from: data)
        guard ticket.version == 1 else {
            throw CmxTicketError.unsupportedVersion(ticket.version)
        }
        guard ticket.alpn == "/cmux/cmx/3" else {
            throw CmxTicketError.unsupportedALPN(ticket.alpn)
        }
        return ticket
    }
}

enum CmxTicketError: LocalizedError, Equatable {
    case empty
    case invalidUTF8
    case unsupportedVersion(Int)
    case unsupportedALPN(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "ticket.error.empty", defaultValue: "Paste an iroh bridge ticket first.")
        case .invalidUTF8:
            return String(localized: "ticket.error.utf8", defaultValue: "The ticket is not valid UTF-8.")
        case .unsupportedVersion(let version):
            return String(
                format: String(localized: "ticket.error.version", defaultValue: "Unsupported bridge ticket version %d."),
                version
            )
        case .unsupportedALPN(let alpn):
            return String(
                format: String(localized: "ticket.error.alpn", defaultValue: "Unsupported bridge protocol %@."),
                alpn
            )
        }
    }
}
