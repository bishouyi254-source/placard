import SwiftUI
import Network
import Combine
import UniformTypeIdentifiers

@MainActor
final class AirliftWiFiMonitor: ObservableObject {
    enum Status {
        case checking
        case connected
        case disconnected
    }

    @Published private(set) var status: Status = .checking

    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "me.ssus.placard.airlift.wifi-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status: Status = path.status == .satisfied ? .connected : .disconnected
            DispatchQueue.main.async {
                self?.status = status
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

/// Connects the existing setup screens to AirCard's on-device pairing host.
struct AirliftEntryView: View {
    @ObservedObject private var pairing = PairingController.shared
    @StateObject private var wifiMonitor = AirliftWiFiMonitor()
    @State private var paired = PairingController.hasValidPairingFile
    @State private var importingPairing = false
    @State private var connected = false
    @State private var checking = false
    @State private var pairingError: String?
    @State private var connectionError: String?

    var body: some View {
        content
            .fileImporter(isPresented: $importingPairing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    try PairingController.importPairingFile(from: url)
                    pairingError = nil
                    connectionError = nil
                    connected = false
                    paired = true
                } catch {
                    pairingError = error.localizedDescription
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch wifiMonitor.status {
        case .checking:
            AirliftWiFiCheckingView()
        case .disconnected:
            AirliftWiFiRequiredView()
        case .connected:
            if connected {
                PlacardRootView()
            } else if paired {
                AirliftVPNView(
                    connectionError: connectionError, checking: checking,
                    onCheck: checkConnection,
                    onPairAgain: {
                        paired = false
                        pairingError = nil
                        connectionError = nil
                    }
                )
            } else {
                AirliftPairingView(
                    running: pairing.running, pin: pairing.pairingPIN,
                    error: pairingError, onStart: startPairing,
                    onImport: { importingPairing = true }
                )
            }
        }
    }

    private func startPairing() {
        guard SystemCompatibility.supportsOnDevicePairing, !pairing.running else { return }
        pairingError = nil
        Task {
            do {
                _ = try await pairing.startAndWait()
                paired = true
            } catch {
                pairingError = error.localizedDescription
            }
        }
    }

    private func checkConnection() {
        guard !checking else { return }
        checking = true
        connectionError = nil
        Task {
            defer { checking = false }
            do {
                guard PairingController.hasValidPairingFile else { throw PairingRecord.ValidationError.invalid }
                _ = try await TendiesEngine.shared.detectPosterBoardContainer(
                    pairingPath: PairingController.pairingFilePath()
                )
                connected = true
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
}
