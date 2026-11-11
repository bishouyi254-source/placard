import Foundation
import CryptoKit

@main
struct CompatibilityChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        func accepts(_ data: Data) -> Bool {
            do { try PairingRecord.validate(data); return true } catch { return false }
        }
        func plist(_ value: Any, _ format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
        }
        let key = Curve25519.Signing.PrivateKey()
        var remote: [String: Any] = ["identifier": "test-host", "private_key": key.rawRepresentation,
                                      "public_key": key.publicKey.rawRepresentation, "alt_irk": Data(repeating: 1, count: 16)]
        check(accepts(try plist(remote)), "Remote XML record")
        check(accepts(try plist(remote, .binary)), "Remote binary record")
        remote["public_key"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        check(!accepts(try plist(remote)), "Mismatched key pair rejected")
        remote["public_key"] = key.publicKey.rawRepresentation
        remote["alt_irk"] = Data(repeating: 1, count: 15)
        check(!accepts(try plist(remote)), "Invalid alt_irk rejected")
        remote.removeValue(forKey: "alt_irk")
        check(accepts(try plist(remote)), "Optional alt_irk")
        remote["private_key"] = Data(repeating: 1, count: 31)
        check(!accepts(try plist(remote)), "Short key rejected")
        var lockdown: [String: Any] = ["HostID": "host", "SystemBUID": "system", "WiFiMACAddress": "00:11:22:33:44:55"]
        for k in ["DeviceCertificate", "HostPrivateKey", "HostCertificate", "RootPrivateKey", "RootCertificate"] {
            lockdown[k] = Data("synthetic-test-only".utf8)
        }
        // Structural acceptance does not validate certificates or device trust.
        check(accepts(try plist(lockdown)), "Lockdown schema accepted")
        lockdown.removeValue(forKey: "RootCertificate")
        check(!accepts(try plist(lockdown)), "Incomplete Lockdown rejected")
        check(!accepts(Data()), "Empty rejected")
        check(!accepts(Data("not a plist".utf8)), "Malformed rejected")
        check(!accepts(try plist(["ordinaryPreference": true])), "Unrelated plist rejected")
        check(!accepts(try plist(["one", "two"])), "Array plist rejected")
        check(!accepts(Data(repeating: 0, count: PairingRecord.maximumSize + 1)), "Oversized rejected")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.plist")
        remote["private_key"] = key.rawRepresentation
        let valid = try plist(remote)
        try valid.write(to: url)
        check(try PairingRecord.read(from: url) == valid, "Regular file read")
        let symlink = dir.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: url)
        check((try? PairingRecord.read(from: symlink)) == nil, "Symbolic link rejected")
        check((try? PairingRecord.read(from: dir)) == nil, "Directory rejected")
        for (major, minor, patch, build, expected) in [
            (25, 9, 0, "", false), (26, 0, 0, "", true), (26, 6, 1, "", true),
            (26, 6, 2, "", false), (26, 7, 3, "", false),
            (27, 0, 0, "24A5390f", true), (27, 0, 0, "unknown", false),
            (27, 0, 1, "24A5390f", false), (28, 0, 0, "", false)
        ] {
            let version = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
            check(SystemCompatibility.supportsBadQuery(version, build: build) == expected,
                  "Compatibility boundary \(major).\(minor).\(patch)")
        }
        check(!SystemCompatibility.supportsBadQuery(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0), build: nil), "Missing build fails closed")
        print("Passed \(checks) pairing and compatibility checks; no device operations performed.")
    }
}
