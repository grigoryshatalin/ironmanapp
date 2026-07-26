import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Deterministic name-based UUIDs (RFC 4122 §4.3, version 5 / SHA-1). Used so
/// the same logical entity always produces the same id across regenerations,
/// devices, and export/import — the backbone of duplicate-free scheduling and
/// sync (§18, §28.2).
public enum UUIDv5 {
    /// Fixed application namespaces (themselves random v4 UUIDs, constant here).
    public enum Namespace {
        public static let enduranceSchedule = UUID(uuidString: "8B1D4E52-6C2A-4F3B-9E7A-1C2D3E4F5A6B")!
        public static let enduranceNotification = UUID(uuidString: "2F7C9A10-4B3D-4E6F-8A1B-9C0D1E2F3A4C")!
    }

    public static func make(namespace: UUID, name: String) -> UUID {
        var bytes = [UInt8]()
        bytes.reserveCapacity(16 + name.utf8.count)
        withUnsafeBytes(of: namespace.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(name.utf8))

        let digest = Insecure.SHA1.hash(data: Data(bytes))
        var d = Array(digest.prefix(16))
        // Set version (5) and RFC 4122 variant bits.
        d[6] = (d[6] & 0x0F) | 0x50
        d[8] = (d[8] & 0x3F) | 0x80
        let uuidT: uuid_t = (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7],
                             d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15])
        return UUID(uuid: uuidT)
    }
}

public extension UUID {
    /// Convenience for the two app namespaces.
    static func endurance(schedule name: String) -> UUID {
        UUIDv5.make(namespace: UUIDv5.Namespace.enduranceSchedule, name: name)
    }
}
