#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A round avatar: the picture when there is one, else the initial on the accent colour.
struct GiftAvatar: View {
    let name: String
    let url: String?
    let size: CGFloat
    let theme: GiftingTheme

    var body: some View {
        ZStack {
            Circle().fill(theme.accent)
            Text(verbatim: giftInitial(name))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(theme.accentText)
            if let link = url, let target = URL(string: link) {
                AsyncImage(url: target, content: { phase in
                    Group {
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.clear
                        }
                    }
                })
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One gift chip: icon and count in a capsule (spec 14.5). Used by the wall and the away card.
struct GiftCountChip: View {
    let iconUrl: String?
    let text: String
    let iconSize: CGFloat
    let fontSize: CGFloat
    let height: CGFloat
    let theme: GiftingTheme

    var body: some View {
        HStack(spacing: 4) {
            if iconUrl != nil {
                GiftPicture(url: iconUrl, size: iconSize)
                    .id(iconUrl ?? "")
            } else {
                Circle()
                    .fill(theme.coin)
                    .frame(width: iconSize * 0.8, height: iconSize * 0.8)
                    .frame(width: iconSize, height: iconSize)
            }
            Text(verbatim: text)
                .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                .foregroundColor(theme.text)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(Capsule().fill(theme.surface))
        .overlay(Capsule().stroke(theme.border, lineWidth: 1))
    }
}

/// Rough width of a chip, for laying chips out in wrapping rows (iOS 15 has no `Layout`).
/// Errs on the wide side so a row never overflows.
func estimatedChipWidth(text: String, iconSize: CGFloat, fontSize: CGFloat) -> CGFloat {
    let textWidth = CGFloat(text.count) * fontSize * 0.68 + 2
    return 8 + iconSize + 4 + textWidth + 8 + 2
}

/// Splits items (given by their widths) into rows that fit `width`, keeping their order
/// (greedy). Returns the item indices of each row. `width <= 0`: one row.
func wrapIntoRows(_ widths: [CGFloat], width: CGFloat, spacing: CGFloat) -> [[Int]] {
    let all = Array(widths.indices)
    guard width > 0 else {
        return all.isEmpty ? [] : [all]
    }
    var rows: [[Int]] = []
    var current: [Int] = []
    var used: CGFloat = 0
    for index in all {
        let w = widths[index]
        let needed = current.isEmpty ? w : used + spacing + w
        if !current.isEmpty && needed > width {
            rows.append(current)
            current = [index]
            used = w
        } else {
            current.append(index)
            used = needed
        }
    }
    if !current.isEmpty {
        rows.append(current)
    }
    return rows
}

/// Width of the view it is attached to (background `GeometryReader`), like the tray's.
struct ComponentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The system's Reduce Motion setting, read outside a view (models).
@MainActor
func systemReduceMotion() -> Bool {
    #if canImport(UIKit) && !os(watchOS)
    return UIAccessibility.isReduceMotionEnabled
    #else
    return false
    #endif
}

/// Speaks `text` with VoiceOver (a live-region announcement). No-op where UIKit is missing.
@MainActor
func announceForAccessibility(_ text: String) {
    #if canImport(UIKit) && !os(watchOS)
    UIAccessibility.post(notification: .announcement, argument: text)
    #endif
}
#endif
