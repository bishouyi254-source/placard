import Foundation
import CryptoKit

/// Structural validation only. Device trust and routing require a live connection.
enum PairingRecord {
    nonisolated static let maximumSize = 1_048_576

    enum ValidationError: LocalizedError {
        case invalid
        var errorDescription: String? {
            String(localized: "Invalid pairing file. Select a complete Lockdown or Remote Pairing plist for this iPhone (maximum 1 MB).")
        }
    }

    nonisolated static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumSize,
              let record = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ValidationError.invalid
        }
        func hasString(_ key: String) -> Bool {
            guard let value = record[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // Schema from the pinned AirCard idevice parser. Check the key pair as
        // well as its length; a generated record is still not proof of trust.
        if let secret = record["private_key"] as? Data,
           let publicKey = record["public_key"] as? Data,
           secret.count == 32, publicKey.count == 32, hasString("identifier"),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: secret),
           key.publicKey.rawRepresentation == publicKey {
            if let irk = record["alt_irk"], (irk as? Data)?.count != 16 {
                throw ValidationError.invalid
            }
            return
        }
        let certificateKeys = ["DeviceCertificate", "HostPrivateKey", "HostCertificate", "RootPrivateKey", "RootCertificate"]
        if certificateKeys.allSatisfy({ !(record[$0] as? Data ?? Data()).isEmpty }),
           hasString("HostID"), hasString("SystemBUID"), hasString("WiFiMACAddress") {
            return
        }
        throw ValidationError.invalid
    }

    nonisolated static func read(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumSize else {
            throw ValidationError.invalid
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        try validate(data)
        return data
    }
}
