import SwiftUI
import AppKit

public enum Win11Theme {
    // MARK: - Adaptive Fluent UI Colors
    public static func windowMicaBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.125, green: 0.125, blue: 0.125) // #202020
            : Color(red: 0.953, green: 0.953, blue: 0.953) // #F3F3F3
    }

    public static func tabBarBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.098, green: 0.098, blue: 0.098) // #191919
            : Color(red: 0.898, green: 0.910, blue: 0.929) // #E5E8ED
    }

    public static func activeTabBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.173, green: 0.173, blue: 0.173) // #2C2C2C
            : Color(red: 0.976, green: 0.976, blue: 0.976) // #F9F9F9
    }

    public static func commandBarBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.155, green: 0.155, blue: 0.155) // #272727
            : Color(red: 0.965, green: 0.965, blue: 0.965) // #F6F6F6
    }

    public static func addressBarBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.173, green: 0.173, blue: 0.173) // #2C2C2C
            : Color.white
    }

    public static func contentBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
            : Color.white
    }

    public static func sidebarBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.125, green: 0.125, blue: 0.125) // #202020
            : Color(red: 0.968, green: 0.968, blue: 0.968)
    }

    public static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.165, green: 0.165, blue: 0.165)
            : Color(red: 0.985, green: 0.985, blue: 0.985)
    }

    public static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.045)
    }

    public static func selectionFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.0, green: 0.47, blue: 0.83).opacity(0.28)
            : Color(red: 0.0, green: 0.47, blue: 0.83).opacity(0.14)
    }

    public static func selectionBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.376, green: 0.804, blue: 1.0).opacity(0.65)
            : Color(red: 0.0, green: 0.404, blue: 0.753).opacity(0.55)
    }

    public static func accentBlue(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.376, green: 0.804, blue: 1.0) // #60CDFF
            : Color(red: 0.0, green: 0.404, blue: 0.753)   // #0067C0
    }

    public static func subtleBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    public static func contextMenuBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.175, green: 0.175, blue: 0.180).opacity(0.97)
            : Color(red: 0.975, green: 0.975, blue: 0.980).opacity(0.98)
    }
}

// MARK: - Windows 11 Authentic Folder & Special Icons
public struct Win11FolderIconView: View {
    public var size: CGFloat = 48
    public var badgeSymbol: String? = nil
    public var badgeColor: Color = Color(red: 0.0, green: 0.47, blue: 0.83)

    public init(size: CGFloat = 48, badgeSymbol: String? = nil, badgeColor: Color = Color(red: 0.0, green: 0.47, blue: 0.83)) {
        self.size = size
        self.badgeSymbol = badgeSymbol
        self.badgeColor = badgeColor
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .bottom) {
                // Back tab of Windows 11 folder (deeper golden amber)
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
                                colors: [
                                    Color(red: 0.98, green: 0.74, blue: 0.15),
                                    Color(red: 0.90, green: 0.61, blue: 0.06)
                                ],
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
                                colors: [
                                    Color(red: 0.95, green: 0.67, blue: 0.09),
                                    Color(red: 0.86, green: 0.56, blue: 0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.92, height: size * 0.68)
                }
                .frame(width: size * 0.92, height: size * 0.81)

                // Front plate of Windows 11 folder (bright Fluent yellow gradient)
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.86, blue: 0.36),
                                Color(red: 0.99, green: 0.75, blue: 0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: max(0.5, size * 0.018))
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

    public init(item: FileItem, size: CGFloat = 44) {
        self.item = item
        self.size = size
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
            } else {
                Image(nsImage: item.systemIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
    }

    private func specialFolderBadge(for url: URL) -> (symbol: String, color: Color)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let std = url.standardizedFileURL
        if std == home.appendingPathComponent("Desktop") {
            return ("menubar.dock.rectangle", Color(red: 0.05, green: 0.52, blue: 0.88))
        } else if std == home.appendingPathComponent("Downloads") {
            return ("arrow.down", Color(red: 0.08, green: 0.65, blue: 0.45))
        } else if std == home.appendingPathComponent("Documents") {
            return ("doc.text.fill", Color(red: 0.18, green: 0.48, blue: 0.85))
        } else if std == home.appendingPathComponent("Pictures") {
            return ("photo.fill", Color(red: 0.62, green: 0.32, blue: 0.85))
        } else if std == home.appendingPathComponent("Music") {
            return ("music.note", Color(red: 0.92, green: 0.28, blue: 0.48))
        } else if std == home.appendingPathComponent("Movies") {
            return ("film.fill", Color(red: 0.90, green: 0.45, blue: 0.15))
        }
        return nil
    }
}
