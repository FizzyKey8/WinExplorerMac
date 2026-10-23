import Foundation

public struct VolumeInfo: Identifiable, Hashable {
    public let id: URL
    public let url: URL
    public let name: String
    public let driveLetterBadge: String
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let isRemovable: Bool
    public let isInternal: Bool
    public let fileSystemType: String

    public var usedCapacity: Int64 {
        max(0, totalCapacity - availableCapacity)
    }

    public var usageFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedCapacity) / Double(totalCapacity)))
    }

    public var isNearFull: Bool {
        usageFraction >= 0.90
    }

    public var formattedCapacitySubtitle: String {
        let freeGB = Double(availableCapacity) / 1_073_741_824.0
        let totalGB = Double(totalCapacity) / 1_073_741_824.0
        return String(format: "%.1f GB disponibles de %.1f GB", freeGB, totalGB)
    }

    public var displayTitleWithDriveLetter: String {
        "\(name) (\(driveLetterBadge))"
    }
}

public struct CloudDriveInfo: Identifiable, Hashable {
    public let id: URL
    public let url: URL
    public let name: String
    public let subtitle: String
    public let sfSymbol: String
    public let isClaroDrive: Bool
    public let isICloud: Bool

    public init(
        url: URL,
        name: String,
        subtitle: String,
        sfSymbol: String = "cloud.fill",
        isClaroDrive: Bool = false,
        isICloud: Bool = false
    ) {
        let clean = url.cleanFileURL
        self.id = clean
        self.url = clean
        self.name = name
        self.subtitle = subtitle
        self.sfSymbol = sfSymbol
        self.isClaroDrive = isClaroDrive
        self.isICloud = isICloud
    }
}
