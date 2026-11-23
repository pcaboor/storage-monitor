import Foundation

/// Capacités du volume qui contient un chemin.
public struct VolumeInfo: Sendable, Equatable {
    public var name: String
    public var totalCapacity: UInt64
    /// Espace réellement libre.
    public var availableCapacity: UInt64
    /// Espace libre tel que l'affiche le Finder (inclut le purgeable).
    public var availableForImportantUsage: UInt64

    public init(name: String, totalCapacity: UInt64, availableCapacity: UInt64, availableForImportantUsage: UInt64) {
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.availableForImportantUsage = availableForImportantUsage
    }

    public var usedCapacity: UInt64 {
        totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
    }

    public static func current(for path: String = "/") throws -> VolumeInfo {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        let available = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
        return VolumeInfo(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            totalCapacity: UInt64(max(0, values.volumeTotalCapacity ?? 0)),
            availableCapacity: available,
            availableForImportantUsage: UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(available)))
        )
    }

    /// Espace utilisé non couvert par le scan : snapshots locaux, swap, purgeable…
    public static func systemOtherSize(used: UInt64, scanned: UInt64) -> UInt64 {
        used > scanned ? used - scanned : 0
    }
}
