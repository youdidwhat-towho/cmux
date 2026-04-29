import ArgumentParser
import Foundation

extension CMUXCLI {
    struct RootArguments: ParsableArguments {
        @Option(name: .long, parsing: .unconditional, help: "Override the Unix socket path.")
        var socket: String?

        @Flag(name: .long, help: "Print machine-readable JSON where supported.")
        var json = false

        @Option(name: .customLong("id-format"), parsing: .unconditional, help: "Select refs, uuids, or both in supported output.")
        var idFormat: String?

        @Option(name: .long, parsing: .unconditional, help: "Route commands through a specific window where supported.")
        var window: String?

        @Option(name: .long, parsing: .unconditional, help: "Socket auth password.")
        var password: String?

        @Flag(name: [.customShort("v"), .long], help: "Print version information.")
        var version = false

        @Flag(name: [.customShort("h"), .long], help: "Print help information.")
        var help = false
    }

    struct RootParseResult {
        let arguments: RootArguments
        let commandIndex: Int
    }

    func parseRootArguments() throws -> RootParseResult {
        let split = try rootArgumentPrefix()
        do {
            let arguments = try RootArguments.parse(split.prefix)
            return RootParseResult(arguments: arguments, commandIndex: split.commandIndex)
        } catch {
            throw CLIError(message: String(describing: error))
        }
    }

    private func rootArgumentPrefix() throws -> (prefix: [String], commandIndex: Int) {
        // Keep this prefix scanner in sync with RootArguments until command dispatch is fully migrated.
        var prefix: [String] = []
        var index = 1

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--socket":
                try appendRootOption(arg, to: &prefix, index: &index, missingValueMessage: "--socket requires a path")
            case "--id-format":
                try appendRootOption(arg, to: &prefix, index: &index, missingValueMessage: "--id-format requires a value (refs|uuids|both)")
            case "--window":
                try appendRootOption(arg, to: &prefix, index: &index, missingValueMessage: "--window requires a window id")
            case "--password":
                try appendRootOption(arg, to: &prefix, index: &index, missingValueMessage: "--password requires a value")
            case "--json", "-v", "--version", "-h", "--help":
                prefix.append(arg)
                index += 1
            default:
                return (prefix, index)
            }
        }

        return (prefix, index)
    }

    private func appendRootOption(
        _ option: String,
        to prefix: inout [String],
        index: inout Int,
        missingValueMessage: String
    ) throws {
        guard index + 1 < args.count else {
            throw CLIError(message: missingValueMessage)
        }
        prefix.append(option)
        prefix.append(args[index + 1])
        index += 2
    }
}
