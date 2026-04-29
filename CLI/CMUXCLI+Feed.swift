import ArgumentParser
import Foundation

extension CMUXCLI {
    struct FeedClearArguments: ParsableArguments {
        @Flag(name: [.long, .customShort("y")], help: "Skip the confirmation prompt.")
        var yes = false

        @Argument(parsing: .allUnrecognized)
        var passthrough: [String] = []

        var skipConfirm: Bool {
            yes || passthrough.contains("--yes") || passthrough.contains("-y")
        }
    }

    func runFeed(commandArgs: [String]) throws {
        let subcommand = commandArgs.first?.lowercased() ?? "help"

        switch subcommand {
        case "clear":
            let parsed = try parseFeedClearArguments(Array(commandArgs.dropFirst()))
            try runFeedClear(skipConfirm: parsed.skipConfirm)
        case "help", "--help", "-h":
            print("Usage: cmux feed clear [--yes]")
        default:
            throw CLIError(message: "Unknown feed subcommand: \(subcommand)")
        }
    }

    private func parseFeedClearArguments(_ args: [String]) throws -> FeedClearArguments {
        do {
            return try FeedClearArguments.parse(args)
        } catch {
            throw CLIError(message: String(describing: error))
        }
    }
}
