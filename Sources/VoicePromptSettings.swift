import Foundation

enum VoicePromptSettings {
    static let systemPromptPrefixKey = "voice.systemPromptPrefix"
    static let systemPromptOverrideKey = "voice.systemPromptOverride"
    static let defaultSystemPromptPrefix = ""
    static let defaultSystemPromptOverride = ""
    static let settingsJSONPaths: Set<String> = [
        systemPromptPrefixKey,
        systemPromptOverrideKey,
    ]

    static var defaultTemplateSection: [String: Any] {
        [
            "voice": [
                "systemPromptPrefix": defaultSystemPromptPrefix,
                "systemPromptOverride": defaultSystemPromptOverride,
            ],
        ]
    }

    static func instructions(defaultInstructions: String, defaults: UserDefaults = .standard) -> String {
        compose(
            defaultInstructions: defaultInstructions,
            prefix: defaults.string(forKey: systemPromptPrefixKey),
            override: defaults.string(forKey: systemPromptOverrideKey)
        )
    }

    static func compose(defaultInstructions: String, prefix: String?, override: String?) -> String {
        if let override = normalizedPrompt(override) {
            return override
        }
        guard let prefix = normalizedPrompt(prefix) else {
            return defaultInstructions
        }
        return "\(prefix)\n\n\(defaultInstructions)"
    }

    static func parseSettingsSection(
        _ section: [String: Any],
        sourcePath: String,
        snapshot: inout ResolvedSettingsSnapshot,
        logInvalid: (String, String) -> Void
    ) {
        if let raw = jsonString(section["systemPromptPrefix"]) {
            snapshot.managedUserDefaults[systemPromptPrefixKey] = .string(raw)
        } else if section.keys.contains("systemPromptPrefix") {
            logInvalid("voice.systemPromptPrefix", sourcePath)
        }
        if let raw = jsonString(section["systemPromptOverride"]) {
            snapshot.managedUserDefaults[systemPromptOverrideKey] = .string(raw)
        } else if section.keys.contains("systemPromptOverride") {
            logInvalid("voice.systemPromptOverride", sourcePath)
        }
    }

    private static func normalizedPrompt(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jsonString(_ rawValue: Any?) -> String? {
        rawValue as? String
    }
}
