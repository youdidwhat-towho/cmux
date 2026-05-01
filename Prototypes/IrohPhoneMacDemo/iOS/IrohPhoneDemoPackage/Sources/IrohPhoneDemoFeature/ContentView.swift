import SwiftUI
import UIKit

public struct ContentView: View {
    @State private var ticket = ""
    @State private var message: String
    @State private var status: PingStatus = .idle

    private let client = IrohDemoClient()

    public init() {
        _message = State(initialValue: localized("iroh.demo.defaultMessage", "Hello from iPhone"))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $ticket)
                        .frame(minHeight: 120)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(localized("iroh.demo.ticket.accessibility", "Iroh ticket"))

                    Button {
                        pasteTicket()
                    } label: {
                        Label(
                            localized("iroh.demo.pasteTicket", "Paste Ticket"),
                            systemImage: "doc.on.clipboard"
                        )
                    }
                } header: {
                    Text(localized("iroh.demo.ticket.header", "Mac Ticket"))
                } footer: {
                    Text(localized("iroh.demo.ticket.footer", "Copy the ticket from the Mac TUI and paste it here."))
                }

                Section {
                    TextField(
                        localized("iroh.demo.message.placeholder", "Message"),
                        text: $message,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    Button {
                        pingMac()
                    } label: {
                        Label(localized("iroh.demo.pingMac", "Ping Mac"), systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status.isSending)
                } header: {
                    Text(localized("iroh.demo.message.header", "Request"))
                }

                Section {
                    statusView
                } header: {
                    Text(localized("iroh.demo.status.header", "Status"))
                }
            }
            .navigationTitle(localized("iroh.demo.title", "Iroh Link"))
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            Label(localized("iroh.demo.idle", "Waiting for a ticket"), systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .sending:
            HStack {
                ProgressView()
                Text(localized("iroh.demo.sending", "Connecting over iroh"))
            }
        case .success(let result):
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    String(
                        format: localized("iroh.demo.success", "Connected in %lld ms"),
                        result.rttMS
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                Text(result.reply)
                    .font(.body)
                    .textSelection(.enabled)

                Text(
                    String(
                        format: localized("iroh.demo.remote", "Remote: %@"),
                        result.remoteID
                    )
                )
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func pasteTicket() {
        guard let pasted = UIPasteboard.general.string else {
            status = .failure(localized("iroh.demo.noPasteboardText", "The pasteboard does not contain text."))
            return
        }

        ticket = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pingMac() {
        let trimmedTicket = ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicket.isEmpty else {
            status = .failure(localized("iroh.demo.missingTicket", "Paste a Mac ticket first."))
            return
        }

        status = .sending
        Task {
            let result = await client.ping(ticket: trimmedTicket, message: message)
            switch result {
            case .success(let value):
                status = .success(value)
            case .failure(let error):
                status = .failure(error.localizedDescription)
            }
        }
    }
}

private enum PingStatus {
    case idle
    case sending
    case success(IrohPingResult)
    case failure(String)

    var isSending: Bool {
        if case .sending = self {
            return true
        }
        return false
    }
}

private func localized(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue, bundle: .module)
}
