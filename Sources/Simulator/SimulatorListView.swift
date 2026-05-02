#if DEBUG
import AppKit
import IOSurface
import SwiftUI
import CoreImage

@MainActor
final class SimulatorListModel: ObservableObject {
    @Published var devices: [SimulatorDevice] = []
    @Published var loadError: String?
    @Published var selectedUDID: String?
    @Published var lastFrame: NSImage?

    private var screen: SimulatorScreen?
    private var refreshTimer: Timer?
    nonisolated private let ciContext = CIContext()

    func startAutoRefresh() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopStreaming()
    }

    func refresh() {
        do {
            devices = try SimulatorService.shared.listDevices()
                .sorted { ($0.runtime, $0.name) < ($1.runtime, $1.name) }
            loadError = nil
            if let sel = selectedUDID, devices.first(where: { $0.udid == sel }) == nil {
                selectedUDID = nil
                stopStreaming()
            }
        } catch {
            loadError = error.localizedDescription
            devices = []
        }
    }

    func boot(_ device: SimulatorDevice) {
        Task.detached(priority: .userInitiated) {
            do {
                try SimulatorService.shared.boot(udid: device.udid)
            } catch {
                await MainActor.run { self.loadError = error.localizedDescription }
            }
            await MainActor.run { self.refresh() }
        }
    }

    func shutdown(_ device: SimulatorDevice) {
        if device.udid == selectedUDID {
            stopStreaming()
        }
        Task.detached(priority: .userInitiated) {
            do {
                try SimulatorService.shared.shutdown(udid: device.udid)
            } catch {
                await MainActor.run { self.loadError = error.localizedDescription }
            }
            await MainActor.run { self.refresh() }
        }
    }

    func select(_ device: SimulatorDevice?) {
        stopStreaming()
        selectedUDID = device?.udid
        guard let device, device.isBooted else { return }
        startStreaming(udid: device.udid)
    }

    private func startStreaming(udid: String) {
        let screen = SimulatorScreen(udid: udid)
        self.screen = screen
        do {
            try screen.start { [weak self] surface in
                guard let self else { return }
                guard let image = Self.makeImage(from: surface, ciContext: self.ciContext) else { return }
                Task { @MainActor in self.lastFrame = image }
            }
        } catch {
            self.screen = nil
            loadError = error.localizedDescription
        }
    }

    private func stopStreaming() {
        screen?.stop()
        screen = nil
        lastFrame = nil
    }

    nonisolated private static func makeImage(from surface: IOSurface, ciContext: CIContext) -> NSImage? {
        let ci = CIImage(ioSurface: unsafeBitCast(surface, to: IOSurfaceRef.self))
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        return NSImage(cgImage: cg, size: size)
    }
}

struct SimulatorListView: View {
    @StateObject private var model = SimulatorListModel()

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 280)
            preview
                .frame(minWidth: 320)
        }
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Devices")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if let err = model.loadError {
                ScrollView {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            List(selection: Binding(
                get: { model.selectedUDID },
                set: { newValue in
                    let device = newValue.flatMap { id in model.devices.first(where: { $0.udid == id }) }
                    model.select(device)
                }
            )) {
                ForEach(groupedRuntimes, id: \.self) { runtime in
                    Section(runtime.isEmpty ? "Other" : runtime) {
                        ForEach(devicesByRuntime[runtime, default: []]) { device in
                            row(for: device)
                                .tag(Optional(device.udid))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                if let udid = model.selectedUDID,
                   let device = model.devices.first(where: { $0.udid == udid }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(.system(size: 12, weight: .semibold))
                        Text(device.runtime).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                } else {
                    Text("Select a booted simulator")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ZStack {
                Color.black.opacity(0.04)
                if let frame = model.lastFrame {
                    Image(nsImage: frame)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else if let udid = model.selectedUDID,
                          let device = model.devices.first(where: { $0.udid == udid }),
                          !device.isBooted {
                    VStack(spacing: 6) {
                        Image(systemName: "iphone.slash").font(.system(size: 28))
                        Text("Boot the device to see its screen.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(for device: SimulatorDevice) -> some View {
        HStack(spacing: 8) {
            stateDot(for: device.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.system(size: 12))
                Text(device.udid.prefix(8))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            actionButton(for: device)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actionButton(for device: SimulatorDevice) -> some View {
        switch device.state {
        case .booted:
            Button("Shutdown") { model.shutdown(device) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        case .shutdown, .unknown:
            Button("Boot") { model.boot(device) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        case .booting:
            Text("Booting…").font(.system(size: 11)).foregroundColor(.secondary)
        case .shuttingDown:
            Text("Shutting down…").font(.system(size: 11)).foregroundColor(.secondary)
        case .creating:
            Text("Creating…").font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func stateDot(for state: SimulatorDevice.State) -> some View {
        let color: Color = {
            switch state {
            case .booted: return .green
            case .booting, .shuttingDown, .creating: return .orange
            case .shutdown, .unknown: return Color.secondary.opacity(0.5)
            }
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private var groupedRuntimes: [String] {
        Array(Set(model.devices.map(\.runtime))).sorted()
    }

    private var devicesByRuntime: [String: [SimulatorDevice]] {
        Dictionary(grouping: model.devices, by: \.runtime)
    }
}
#endif
