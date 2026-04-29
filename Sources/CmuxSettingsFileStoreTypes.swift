import Foundation

struct ResolvedSettingsSnapshot {
    var path: String?
    var shortcuts: [KeyboardShortcutSettings.Action: StoredShortcut] = [:]
    var managedUserDefaults: [String: ManagedSettingsValue] = [:]
    var managedCustomSettings = ManagedCustomSettings()
}

enum ManagedStringOverride: Equatable {
    case set(String)
    case clear
}

struct ManagedCustomSettings: Equatable {
    var socketPassword: ManagedStringOverride?

    var isEmpty: Bool {
        socketPassword == nil
    }

    var managedIdentifiers: Set<String> {
        var identifiers: Set<String> = []
        if socketPassword != nil {
            identifiers.insert(CmuxSettingsFileStore.socketPasswordBackupIdentifier)
        }
        return identifiers
    }
}

enum ManagedSettingsValue: Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case nullableString(String?)
    case stringArray([String])
    case stringDictionary([String: String])
}

enum BackupValue: Codable, Equatable {
    case absent
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case stringArray([String])
    case stringDictionary([String: String])

    private enum Kind: String, Codable {
        case absent
        case bool
        case int
        case double
        case string
        case stringArray
        case stringDictionary
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case boolValue
        case intValue
        case doubleValue
        case stringValue
        case stringArrayValue
        case stringDictionaryValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .absent:
            self = .absent
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .boolValue))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .intValue))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .doubleValue))
        case .string:
            self = .string(try container.decode(String.self, forKey: .stringValue))
        case .stringArray:
            self = .stringArray(try container.decode([String].self, forKey: .stringArrayValue))
        case .stringDictionary:
            self = .stringDictionary(try container.decode([String: String].self, forKey: .stringDictionaryValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent:
            try container.encode(Kind.absent, forKey: .kind)
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .boolValue)
        case .int(let value):
            try container.encode(Kind.int, forKey: .kind)
            try container.encode(value, forKey: .intValue)
        case .double(let value):
            try container.encode(Kind.double, forKey: .kind)
            try container.encode(value, forKey: .doubleValue)
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .stringValue)
        case .stringArray(let value):
            try container.encode(Kind.stringArray, forKey: .kind)
            try container.encode(value, forKey: .stringArrayValue)
        case .stringDictionary(let value):
            try container.encode(Kind.stringDictionary, forKey: .kind)
            try container.encode(value, forKey: .stringDictionaryValue)
        }
    }
}
