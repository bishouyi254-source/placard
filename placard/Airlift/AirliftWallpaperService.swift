import Foundation
import OSLog

/// Adapter for AirCard-iOS 097a058c984ffc33ccb697b9dfe8058be3e86244.
/// TendiesEngine owns extraction, identifier rewriting, injection, and preferences.
@MainActor
final class AirliftWallpaperService {
    static let shared = AirliftWallpaperService()
    private var installing = false

    static var diagnosticURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-airlift-install.json")
    }

    enum VerificationError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            String(localized: "Write requests completed, but wallpaper registration could not be verified. This Airlift build has no wallpaper read-back API. No automatic respring or preference reset was performed. Check Settings › Wallpaper before retrying; do not repeatedly install the same package.")
        }
    }

    static func log(_ message: String) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Placard", category: "Airlift")
            .info("\(message, privacy: .private)")
    }

    func install(
        packageAt url: URL,
        progress: @escaping @MainActor @Sendable (InstallState) -> Void
    ) async throws {
        guard !installing else {
            throw NSError(domain: "Airlift", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Installing…")
            ])
        }
        installing = true
        defer { installing = false }
        let operation = UUID().uuidString
        var stage = "pairing-validation"
        var result = "failed-or-cancelled"
        // Sanitized local receipt survives relaunch. Never store pairing bytes,
        // package contents, container identifiers or untrusted FFI messages.
        defer {
            let receipt = ["operation": operation, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                           "stage": stage, "result": result,
                           "time": ISO8601DateFormatter().string(from: Date())]
            do {
                let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: Self.diagnosticURL,
                               options: [.atomic, .completeFileProtection])
            } catch {
                Self.log("Unable to save sanitized installation receipt")
            }
        }
        do {
            let pairingPath = PairingController.pairingFilePath()
            guard PairingController.hasValidPairingFile else {
                throw NSError(domain: "Airlift", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Pair this iPhone")
                ])
            }
            let engine = TendiesEngine.shared
            stage = "package-import"
            progress(.unpacking)
            let item = try await engine.importTendie(from: url)
            defer { try? FileManager.default.removeItem(at: item.fileURL) }
            try Task.checkCancellation()
            progress(.locatingPosterBoard)
            stage = "container-discovery"
            let container = try await engine.detectPosterBoardContainer(pairingPath: pairingPath)
            let canonical = container.hasPrefix("/private/") ? String(container.dropFirst(8)) : container
            let prefix = "/var/mobile/Containers/Data/Application/"
            guard canonical.hasPrefix(prefix), UUID(uuidString: String(canonical.dropFirst(prefix.count))) != nil else {
                throw NSError(domain: "Airlift", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "PosterBoard returned an unexpected container path. No write was attempted.")
                ])
            }
            try Task.checkCancellation()
            progress(.writing)
            stage = "descriptor-write"
            try await engine.flashTendies(
                items: [item], containerPath: canonical, resetProtections: false,
                pairingPath: pairingPath, log: Self.log, progress: { _ in }
            )
            try Task.checkCancellation()
            stage = "registration-verification"
            result = "write-requests-completed-registration-unverified"
            // Discovery authenticates a connection, not the written descriptors or
            // PosterBoard gallery registration. Do not advance callers to .installed.
            throw VerificationError.unavailable
        } catch {
            if !(error is VerificationError) {
                result = "error-code-\((error as NSError).code); partial-write-possible=\(stage == "descriptor-write")"
            }
            Self.log("Installation \(operation) stopped at \(stage): \((error as NSError).code)")
            throw error
        }
    }
}
