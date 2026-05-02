import Foundation

enum CmxLaunchConfiguration {
    static func ticket(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let normalizedArguments = normalized(arguments: arguments)
        if let index = normalizedArguments.firstIndex(of: "--cmux-ticket"),
           normalizedArguments.indices.contains(index + 1) {
            return normalizedArguments[index + 1]
        }
        return environment["CMUX_IOS_BRIDGE_TICKET"]
    }

    static func shouldAutoconnect(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        normalized(arguments: arguments).contains("--cmux-autoconnect") || environment["CMUX_IOS_AUTOCONNECT"] == "1"
    }

    private static func normalized(arguments: [String]) -> [String] {
        arguments.flatMap { argument -> [String] in
            guard argument.first == "[",
                  let data = argument.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [argument] }
            return decoded
        }
    }
}
