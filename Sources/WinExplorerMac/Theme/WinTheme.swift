import SwiftUI
import AppKit

// MARK: - Explorer Theme Options
public enum ExplorerTheme: String, CaseIterable, Identifiable {
    case win = "win"
    case minimalist = "minimalist"
    case liquidGlass = "liquidGlass"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .win:
            return "Win"
        case .minimalist:
            return "Minimalista"
        case .liquidGlass:
            return "Liquid Glass"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .win:
            return "squares.below.rectangle"
        case .minimalist:
            return "circle.grid.2x1"
        case .liquidGlass:
            return "sparkles"
        }
    }
}

// MARK: - Reactive Theme Manager
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    private let storageKey = "WinExplorerMac.SelectedTheme.v1"

    @Published public var currentTheme: ExplorerTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: storageKey)
            Self.applyWindowAppearance(for: currentTheme)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let parsed = ExplorerTheme(rawValue: saved) {
            self.currentTheme = parsed
        } else {
            self.currentTheme = .win
        }
    }

    public static func applyWindowAppearance(for theme: ExplorerTheme) {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                switch theme {
                case .liquidGlass:
                    window.isOpaque = false
                    window.backgroundColor = .clear
                case .win, .minimalist:
                    window.isOpaque = true
                    window.backgroundColor = .windowBackgroundColor
                }
            }
        }
    }
}

// MARK: - Liquid Glass Native Backdrop (NSVisualEffectView + Specular Sheen)
public struct LiquidGlassVisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

public struct LiquidGlassBackdropView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            LiquidGlassVisualEffectView(
                material: colorScheme == .dark ? .hudWindow : .underWindowBackground,
                blendingMode: .behindWindow
            )

            // Subtle liquid glass refraction sheen
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.20, green: 0.55, blue: 0.85).opacity(0.16),
                        Color(red: 0.08, green: 0.12, blue: 0.22).opacity(0.24),
                        Color(red: 0.35, green: 0.25, blue: 0.65).opacity(0.12)
                    ]
                    : [
                        Color.white.opacity(0.55),
                        Color(red: 0.82, green: 0.93, blue: 1.0).opacity(0.35),
                        Color(red: 0.92, green: 0.88, blue: 1.0).opacity(0.28)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Top specular highlight edge
            VStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.65),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

public enum Win11Theme {
    public static var activeTheme: ExplorerTheme {
        ThemeManager.shared.currentTheme
    }

    // MARK: - Adaptive Theme Colors (Win / Minimalista / Liquid Glass)
    public static func windowMicaBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.125, green: 0.125, blue: 0.125) // #202020
                : Color(red: 0.953, green: 0.953, blue: 0.953) // #F3F3F3
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.071, green: 0.071, blue: 0.078) // #121214
                : Color(red: 0.988, green: 0.988, blue: 0.992) // #FCFCFD
        case .liquidGlass:
            return Color.clear
        }
    }

    public static func tabBarBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.098, green: 0.098, blue: 0.098) // #191919
                : Color(red: 0.898, green: 0.910, blue: 0.929) // #E5E8ED
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.071, green: 0.071, blue: 0.078) // Unified flat dark
                : Color(red: 0.965, green: 0.965, blue: 0.970)
        case .liquidGlass:
            return scheme == .dark
                ? Color.black.opacity(0.22)
                : Color.white.opacity(0.28)
        }
    }

    public static func activeTabBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.173, green: 0.173, blue: 0.173) // #2C2C2C
                : Color(red: 0.976, green: 0.976, blue: 0.976) // #F9F9F9
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.118, green: 0.118, blue: 0.129) // #1E1E21
                : Color.white
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.14)
                : Color.white.opacity(0.68)
        }
    }

    public static func commandBarBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.155, green: 0.155, blue: 0.155) // #272727
                : Color(red: 0.965, green: 0.965, blue: 0.965) // #F6F6F6
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.086, green: 0.086, blue: 0.094) // #161618
                : Color.white
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.07)
                : Color.white.opacity(0.46)
        }
    }

    public static func addressBarBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.173, green: 0.173, blue: 0.173) // #2C2C2C
                : Color.white
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.110, green: 0.110, blue: 0.122)
                : Color(red: 0.965, green: 0.965, blue: 0.972)
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.11)
                : Color.white.opacity(0.66)
        }
    }

    public static func contentBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
                : Color.white
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.071, green: 0.071, blue: 0.078) // #121214
                : Color.white
        case .liquidGlass:
            return scheme == .dark
                ? Color.black.opacity(0.16)
                : Color.white.opacity(0.36)
        }
    }

    public static func sidebarBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.125, green: 0.125, blue: 0.125) // #202020
                : Color(red: 0.968, green: 0.968, blue: 0.968)
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.078, green: 0.078, blue: 0.086) // #141416
                : Color(red: 0.980, green: 0.980, blue: 0.985)
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.05)
                : Color.white.opacity(0.26)
        }
    }

    public static func cardBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.165, green: 0.165, blue: 0.165)
                : Color(red: 0.985, green: 0.985, blue: 0.985)
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.102, green: 0.102, blue: 0.112)
                : Color(red: 0.976, green: 0.976, blue: 0.982)
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.10)
                : Color.white.opacity(0.58)
        }
    }

    public static func hoverFill(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.045)
        case .minimalist:
            return scheme == .dark
                ? Color.white.opacity(0.045)
                : Color.black.opacity(0.035)
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.13)
                : Color.white.opacity(0.52)
        }
    }

    public static func selectionFill(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.0, green: 0.47, blue: 0.83).opacity(0.28)
                : Color(red: 0.0, green: 0.47, blue: 0.83).opacity(0.14)
        case .minimalist:
            return scheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.075)
        case .liquidGlass:
            return scheme == .dark
                ? Color(red: 0.25, green: 0.82, blue: 0.98).opacity(0.26)
                : Color(red: 0.04, green: 0.58, blue: 0.92).opacity(0.18)
        }
    }

    public static func selectionBorder(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.376, green: 0.804, blue: 1.0).opacity(0.65)
                : Color(red: 0.0, green: 0.404, blue: 0.753).opacity(0.55)
        case .minimalist:
            return scheme == .dark
                ? Color.white.opacity(0.28)
                : Color.black.opacity(0.24)
        case .liquidGlass:
            return scheme == .dark
                ? Color(red: 0.55, green: 0.92, blue: 1.0).opacity(0.75)
                : Color(red: 0.10, green: 0.62, blue: 0.95).opacity(0.65)
        }
    }

    public static func accentBlue(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.376, green: 0.804, blue: 1.0) // #60CDFF
                : Color(red: 0.0, green: 0.404, blue: 0.753)   // #0067C0
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.894, green: 0.894, blue: 0.906) // #E4E4E7 (Monochrome silver)
                : Color(red: 0.145, green: 0.145, blue: 0.165) // #25252A (Graphite)
        case .liquidGlass:
            return scheme == .dark
                ? Color(red: 0.38, green: 0.88, blue: 0.98)    // Crystal Aqua
                : Color(red: 0.01, green: 0.52, blue: 0.84)    // Deep Ocean Glass
        }
    }

    public static func subtleBorder(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.08)
        case .minimalist:
            return scheme == .dark
                ? Color.white.opacity(0.045)
                : Color.black.opacity(0.05)
        case .liquidGlass:
            return scheme == .dark
                ? Color.white.opacity(0.22)
                : Color.white.opacity(0.68)
        }
    }

    public static func contextMenuBackground(_ scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .win:
            return scheme == .dark
                ? Color(red: 0.175, green: 0.175, blue: 0.180).opacity(0.97)
                : Color(red: 0.975, green: 0.975, blue: 0.980).opacity(0.98)
        case .minimalist:
            return scheme == .dark
                ? Color(red: 0.095, green: 0.095, blue: 0.105).opacity(0.98)
                : Color.white.opacity(0.99)
        case .liquidGlass:
            return scheme == .dark
                ? Color(red: 0.11, green: 0.15, blue: 0.22).opacity(0.86)
                : Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.88)
        }
    }
}

// MARK: - Theme-Adaptive Folder & Special Icons
public struct Win11FolderIconView: View {
    public var size: CGFloat = 48
    public var badgeSymbol: String? = nil
    public var badgeColor: Color = Color(red: 0.0, green: 0.47, blue: 0.83)

    @ObservedObject private var themeManager = ThemeManager.shared

    public init(size: CGFloat = 48, badgeSymbol: String? = nil, badgeColor: Color = Color(red: 0.0, green: 0.47, blue: 0.83)) {
        self.size = size
        self.badgeSymbol = badgeSymbol
        self.badgeColor = badgeColor
    }

    private var backTabColors: [Color] {
        switch themeManager.currentTheme {
        case .win:
            return [
                Color(red: 0.98, green: 0.74, blue: 0.15),
                Color(red: 0.90, green: 0.61, blue: 0.06)
            ]
        case .minimalist:
            return [
                Color(red: 0.52, green: 0.53, blue: 0.57),
                Color(red: 0.38, green: 0.39, blue: 0.43)
            ]
        case .liquidGlass:
            return [
                Color(red: 0.28, green: 0.76, blue: 0.96).opacity(0.88),
                Color(red: 0.12, green: 0.52, blue: 0.82).opacity(0.88)
            ]
        }
    }

    private var backBodyColors: [Color] {
        switch themeManager.currentTheme {
        case .win:
            return [
                Color(red: 0.95, green: 0.67, blue: 0.09),
                Color(red: 0.86, green: 0.56, blue: 0.04)
            ]
        case .minimalist:
            return [
                Color(red: 0.46, green: 0.47, blue: 0.51),
                Color(red: 0.34, green: 0.35, blue: 0.39)
            ]
        case .liquidGlass:
            return [
                Color(red: 0.20, green: 0.68, blue: 0.92).opacity(0.85),
                Color(red: 0.08, green: 0.45, blue: 0.76).opacity(0.85)
            ]
        }
    }

    private var frontPlateColors: [Color] {
        switch themeManager.currentTheme {
        case .win:
            return [
                Color(red: 1.0, green: 0.86, blue: 0.36),
                Color(red: 0.99, green: 0.75, blue: 0.16)
            ]
        case .minimalist:
            return [
                Color(red: 0.68, green: 0.69, blue: 0.73),
                Color(red: 0.53, green: 0.54, blue: 0.58)
            ]
        case .liquidGlass:
            return [
                Color(red: 0.58, green: 0.91, blue: 1.0).opacity(0.82),
                Color(red: 0.24, green: 0.72, blue: 0.95).opacity(0.76)
            ]
        }
    }

    private var frontPlateStrokeOpacity: Double {
        switch themeManager.currentTheme {
        case .win:
            return 0.35
        case .minimalist:
            return 0.22
        case .liquidGlass:
            return 0.72
        }
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .bottom) {
                // Back tab of folder
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: size * 0.09,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: size * 0.09
                        )
                        .fill(
                            LinearGradient(
                                colors: backTabColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.42, height: size * 0.13)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: backBodyColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.92, height: size * 0.68)
                }
                .frame(width: size * 0.92, height: size * 0.81)

                // Front plate of folder
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: frontPlateColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                            .stroke(Color.white.opacity(frontPlateStrokeOpacity), lineWidth: max(0.5, size * 0.018))
                    )
                    .frame(width: size * 0.92, height: size * 0.58)
                    .shadow(color: Color.black.opacity(0.14), radius: size * 0.04, x: 0, y: size * 0.02)
            }
            .frame(width: size, height: size)

            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: size * 0.30, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(size * 0.08)
                    .background(
                        Circle()
                            .fill(badgeColor.gradient)
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    )
                    .offset(x: -size * 0.02, y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }
}

public struct Win11ItemIconView: View {
    public let item: FileItem
    public var size: CGFloat = 44

    @State private var thumbnail: NSImage?

    public init(item: FileItem, size: CGFloat = 44) {
        self.item = item
        self.size = size
        _thumbnail = State(initialValue: ThumbnailService.shared.cachedThumbnail(for: item, targetSize: size))
    }

    public var body: some View {
        Group {
            if item.isDirectory {
                let special = specialFolderBadge(for: item.url)
                Win11FolderIconView(
                    size: size,
                    badgeSymbol: special?.symbol,
                    badgeColor: special?.color ?? Color(red: 0.0, green: 0.47, blue: 0.83)
                )
            } else if item.isArchiveZip {
                ZStack {
                    Win11FolderIconView(size: size, badgeSymbol: "doc.zipper", badgeColor: Color.orange)
                }
            } else if let thumbnail = thumbnail ?? ThumbnailService.shared.cachedThumbnail(for: item, targetSize: size) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: max(2.5, size * 0.08), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: max(2.5, size * 0.08), style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(0.20), radius: max(1, size * 0.04), x: 0, y: 1)

                    if item.isVideo && size >= 36 {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.60))
                                .frame(width: max(14, size * 0.28), height: max(14, size * 0.28))
                            Image(systemName: "play.fill")
                                .font(.system(size: max(6, size * 0.13), weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 0.5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(max(2, size * 0.05))
                    }

                    if item.isCloudDataless && size >= 28 {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: max(8, size * 0.22), weight: .semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.52, blue: 0.95))
                            .padding(max(1.5, size * 0.03))
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .windowBackgroundColor))
                                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                            )
                    }
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: item.systemIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size, height: size)

                    if item.isCloudDataless && size >= 18 {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: max(8, size * 0.28), weight: .semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.52, blue: 0.95))
                            .padding(max(1.5, size * 0.04))
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .windowBackgroundColor))
                                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                            )
                    }
                }
            }
        }
        .task(id: "\(item.url.path)|\(Int(size))") {
            let canLoadCloudPreview = item.isCloudDataless && (item.isImage || item.isVideo)
            guard (!item.isCloudDataless && (item.isImage || item.isVideo || item.isQuickLookThumbnailSupported)) || canLoadCloudPreview else {
                return
            }
            if let cached = ThumbnailService.shared.cachedThumbnail(for: item, targetSize: size) {
                thumbnail = cached
                return
            }
            if let loaded = await ThumbnailService.shared.loadThumbnailAsync(for: item, targetSize: size) {
                thumbnail = loaded
            }
        }
    }

    private func specialFolderBadge(for url: URL) -> (symbol: String, color: Color)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.cleanFileURL
        let std = url.cleanFileURL
        if std.path == home.appendingPathComponent("Desktop", isDirectory: true).path {
            return ("menubar.dock.rectangle", Color(red: 0.05, green: 0.52, blue: 0.88))
        } else if std.path == home.appendingPathComponent("Downloads", isDirectory: true).path {
            return ("arrow.down", Color(red: 0.08, green: 0.65, blue: 0.45))
        } else if std.path == home.appendingPathComponent("Documents", isDirectory: true).path {
            return ("doc.text.fill", Color(red: 0.18, green: 0.48, blue: 0.85))
        } else if std.path == home.appendingPathComponent("Pictures", isDirectory: true).path {
            return ("photo.fill", Color(red: 0.62, green: 0.32, blue: 0.85))
        } else if std.path == home.appendingPathComponent("Music", isDirectory: true).path {
            return ("music.note", Color(red: 0.92, green: 0.28, blue: 0.48))
        } else if std.path == home.appendingPathComponent("Movies", isDirectory: true).path {
            return ("film.fill", Color(red: 0.90, green: 0.45, blue: 0.15))
        } else if std.path == home.appendingPathComponent(".Trash", isDirectory: true).path {
            return ("trash.fill", Color(red: 0.45, green: 0.50, blue: 0.58))
        } else if std.path == FileSystemService.iCloudDriveURL.path {
            return ("icloud.fill", Color(red: 0.05, green: 0.52, blue: 0.95))
        } else if std.deletingLastPathComponent().cleanFileURL.path == FileSystemService.cloudStorageRootURL.path {
            let parsed = FileSystemService.parseCloudProviderFolderName(std.lastPathComponent)
            if parsed.isClaro {
                return ("cloud.fill", Color(red: 0.88, green: 0.14, blue: 0.14))
            }
            return ("cloud.fill", Color(red: 0.05, green: 0.52, blue: 0.95))
        }
        return nil
    }
}
