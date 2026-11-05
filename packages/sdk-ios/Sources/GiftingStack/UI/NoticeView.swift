#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One line of the notice stack: "ayla sent Rose x3" (spec 7.4). Slides in from the left, stays,
/// and slides out. The combo number pops each time it grows. Each line keeps its own state.
@MainActor
struct NoticeView: View {
    let data: NoticeData
    let visible: Bool
    let theme: GiftingTheme

    @State private var slide: Double = 0
    @State private var pop: CGFloat = 1
    @State private var lastId: Int?
    @State private var lastCount = 0

    init(data: NoticeData, visible: Bool, theme: GiftingTheme) {
        self.data = data
        self.visible = visible
        self.theme = theme
    }

    var body: some View {
        row(data)
            .opacity(slide)
            .offset(x: CGFloat(-260 * (1 - slide)))
        .onAppear {
            animateSlide(to: visible)
            remember(data)
            announce(data)
        }
        .onChange(of: visible) { now in
            animateSlide(to: now)
        }
        .onChange(of: data) { next in
            popIfCountGrew(next)
            announce(next)
        }
    }

    private func row(_ data: NoticeData) -> some View {
        let big = data.big
        let textColor = big ? theme.noticeBigText : theme.noticeText
        let avatar: CGFloat = big ? 34 : 28
        let picture: CGFloat = big ? 46 : 36
        return HStack(spacing: 8) {
            ZStack {
                Circle().fill(theme.accent)
                Text(verbatim: String(data.senderName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.accentText)
            }
            .frame(width: avatar, height: avatar)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: data.senderName)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                Text(verbatim: "sent \(data.giftName)")
                    .font(.system(size: 12.5))
                    .foregroundColor(textColor)
                    .opacity(0.92)
                    .lineLimit(1)
            }

            if let image = data.image {
                // A fresh view per picture URL: never the previous gift's bitmap (spec 7.4).
                GiftPicture(url: image, size: picture)
                    .id(image)
            }

            if data.count > 1 {
                Text(verbatim: "x\(data.count)")
                    .font(.system(size: 28, weight: .heavy).italic())
                    .foregroundColor(big ? theme.noticeBigText : theme.comboText)
                    .frame(minWidth: 40)
                    .scaleEffect(pop)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 16)
        .padding(.vertical, big ? 7 : 5)
        .background(Capsule().fill(big ? theme.noticeBigBackground : theme.noticeBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: NoticeView.spokenText(data)))
    }

    private func animateSlide(to shown: Bool) {
        if shown {
            // Ease-out back(1.2), 380 ms.
            withAnimation(.timingCurve(0.3, 1.35, 0.6, 1, duration: 0.38)) {
                slide = 1
            }
        } else {
            // Ease-in quad, 260 ms.
            withAnimation(.timingCurve(0.55, 0.085, 0.68, 0.53, duration: 0.26)) {
                slide = 0
            }
        }
    }

    private func remember(_ data: NoticeData) {
        lastId = data.id
        lastCount = data.count
    }

    /// Same notice id, larger count (> 1): the counter jumps to 1.9 and springs back
    /// (React Native spring friction 4, tension 160 = stiffness 664.6, damping 13).
    private func popIfCountGrew(_ next: NoticeData) {
        if next.id == lastId, next.count > lastCount, next.count > 1 {
            var jump = Transaction()
            jump.disablesAnimations = true
            withTransaction(jump) {
                pop = 1.9
            }
            // One frame later, so the jump to 1.9 is drawn before the spring starts.
            Task {
                try? await Task.sleep(nanoseconds: 16_000_000)
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 664.6, damping: 13, initialVelocity: 0)) {
                    pop = 1
                }
            }
        }
        remember(next)
    }

    private func announce(_ next: NoticeData) {
        #if canImport(UIKit) && !os(watchOS)
        guard visible else {
            return
        }
        UIAccessibility.post(notification: .announcement, argument: NoticeView.spokenText(next))
        #endif
    }

    static func spokenText(_ data: NoticeData) -> String {
        data.count > 1
            ? "\(data.senderName) sent \(data.giftName) x\(data.count)"
            : "\(data.senderName) sent \(data.giftName)"
    }
}
#endif
