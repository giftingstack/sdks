import GiftingStack
import SwiftUI

/// The pretend photos of the feed, drawn with gradients and shapes (no image host needed).
struct PixelArtView: View {
    let kind: PixelArtKind

    var body: some View {
        GeometryReader { proxy in
            content(proxy.size)
        }
        .clipped()
    }

    @ViewBuilder
    private func content(_ size: CGSize) -> some View {
        switch kind {
        case .sunset:
            sunset(size)
        case .city:
            city(size)
        case .ocean:
            ocean(size)
        case .aurora:
            aurora(size)
        }
    }

    private func hex(_ value: UInt32) -> Color {
        Color(giftingHex: value)
    }

    private func vertical(_ colors: [UInt32]) -> LinearGradient {
        LinearGradient(gradient: Gradient(colors: colors.map { Color(giftingHex: $0) }), startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Golden hour on the pier

    private func sunset(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            vertical([0xFFC371, 0xFF7A6D, 0x7A3FA0])
            Circle()
                .fill(hex(0xFFE7A3))
                .frame(width: h * 0.4, height: h * 0.4)
                .position(x: w * 0.5, y: h * 0.6)
            Rectangle()
                .fill(vertical([0x4A2C7A, 0x1E1440]))
                .frame(width: w, height: h * 0.32)
                .position(x: w * 0.5, y: h * 0.84)
            ForEach(0..<4) { i in
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: w * (0.2 - CGFloat(i) * 0.04), height: 3)
                    .position(x: w * 0.5, y: h * (0.75 + CGFloat(i) * 0.06))
            }
            Rectangle()
                .fill(hex(0x1A1030))
                .frame(width: w * 0.5, height: 5)
                .position(x: w * 0.25, y: h * 0.7)
            ForEach(0..<6) { i in
                Rectangle()
                    .fill(hex(0x1A1030))
                    .frame(width: 3, height: h * 0.16)
                    .position(x: w * (0.03 + CGFloat(i) * 0.09), y: h * 0.78)
            }
        }
    }

    // MARK: - Skyline at night

    private static let towers: [CGFloat] = [0.42, 0.7, 0.55, 0.86, 0.48, 0.66, 0.38]

    private func city(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack(alignment: .bottom) {
            vertical([0x14183F, 0x3B2A6F, 0x8B5BB8])
            Circle()
                .fill(hex(0xF4F2FF))
                .frame(width: h * 0.16, height: h * 0.16)
                .position(x: w * 0.8, y: h * 0.2)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<7) { i in
                    tower(height: h * PixelArtView.towers[i])
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func tower(height: CGFloat) -> some View {
        Rectangle()
            .fill(hex(0x0E1030))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                VStack(spacing: 7) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 6) {
                            window
                            window
                        }
                    }
                }
                .padding(.top, 10),
                alignment: .top
            )
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(hex(0xFFD27A).opacity(0.85))
            .frame(width: 5, height: 7)
    }

    // MARK: - Morning tide

    private func ocean(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            vertical([0xBDEBFA, 0x5CC3E8, 0x1F7FC0, 0x0F4C81])
            Circle()
                .fill(hex(0xFFF4C2))
                .frame(width: h * 0.18, height: h * 0.18)
                .position(x: w * 0.22, y: h * 0.2)
            ForEach(0..<5) { i in
                wave(i, size)
            }
            Rectangle()
                .fill(hex(0xF2D9A6))
                .frame(width: w, height: h * 0.1)
                .position(x: w * 0.5, y: h * 0.95)
        }
    }

    private func wave(_ i: Int, _ size: CGSize) -> some View {
        let left: CGFloat = i % 2 == 0 ? 0.35 : 0.65
        let top: CGFloat = 0.5 + CGFloat(i) * 0.1
        let alpha: Double = 0.55 - Double(i) * 0.08
        return Capsule()
            .fill(Color.white.opacity(alpha))
            .frame(width: size.width * 0.5, height: 6)
            .position(x: size.width * left, y: size.height * top)
    }

    private func star(_ i: Int, _ size: CGSize) -> some View {
        let left = CGFloat((i * 37) % 100) / 100
        let top = CGFloat((i * 53) % 45) / 100
        return Circle()
            .fill(Color.white.opacity(0.8))
            .frame(width: 2, height: 2)
            .position(x: size.width * left, y: size.height * top)
    }

    // MARK: - Northern lights

    private func aurora(_ size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            vertical([0x05081C, 0x0B1A3A, 0x13294F])
            ForEach(0..<14) { i in
                star(i, size)
            }
            Ellipse()
                .fill(hex(0x3DFFB0).opacity(0.55))
                .frame(width: w * 0.9, height: h * 0.22)
                .rotationEffect(Angle(degrees: -12))
                .blur(radius: 18)
                .position(x: w * 0.45, y: h * 0.35)
            Ellipse()
                .fill(hex(0x9B6BFF).opacity(0.45))
                .frame(width: w * 0.7, height: h * 0.18)
                .rotationEffect(Angle(degrees: 8))
                .blur(radius: 22)
                .position(x: w * 0.65, y: h * 0.45)
            PixelMountains()
                .fill(hex(0x02040E))
                .frame(width: w, height: h * 0.35)
                .position(x: w * 0.5, y: h * 0.825)
        }
    }
}

/// A ridge of three peaks along the bottom edge (for the aurora picture).
struct PixelMountains: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.6))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.85, y: rect.minY + rect.height * 0.5))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
