import GiftingStack
import SwiftUI

/// The hidden developer menu: the only debug surface of the demo, not part of the SDK. Opened by
/// holding the Pixel logo for 1 s; closed by the X or a tap on the dimmed backdrop. A card over
/// the app (iOS 15 has no sheet detents).
@MainActor
struct PixelDevMenu: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    model.devMenuOpen = false
                }
                .accessibilityHidden(true)
            card
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Developer menu")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundColor(palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Not part of the SDK")
                        .font(.system(size: 12))
                        .foregroundColor(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.devMenuOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(palette.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(palette.line))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Close"))
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.top, 8)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    section("Incoming gift") {
                        HStack(spacing: 6) {
                            ForEach(PixelIncomingMode.allCases) { mode in
                                chip(mode.rawValue, on: model.incomingMode == mode) {
                                    model.incomingMode = mode
                                }
                            }
                        }
                    }
                    section("Play") {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                action("Play gift") {
                                    model.playIncoming()
                                }
                                action("x5 combo") {
                                    model.combo()
                                }
                            }
                            HStack(spacing: 6) {
                                action("Away summary again") {
                                    model.showAway()
                                }
                                action("Wall +5") {
                                    model.wallPlus()
                                }
                            }
                        }
                    }
                    section("Quality") {
                        HStack(spacing: 6) {
                            chip("High", on: model.quality == .high) {
                                model.setQuality(.high)
                            }
                            chip("Low", on: model.quality == .low) {
                                model.setQuality(.low)
                            }
                        }
                    }
                    section("Theme") {
                        HStack(spacing: 6) {
                            ForEach(PixelTheme.allCases) { theme in
                                chip(theme.rawValue, on: model.theme == theme) {
                                    model.theme = theme
                                }
                            }
                        }
                    }
                    section("Motion") {
                        HStack(spacing: 6) {
                            ForEach(PixelMotion.allCases) { motion in
                                chip(motion.rawValue, on: model.motion == motion) {
                                    model.setMotion(motion)
                                }
                            }
                        }
                    }
                    section("Mock failure") {
                        Toggle(isOn: Binding(get: { model.offline }, set: { value in model.setOffline(value) })) {
                            Text(verbatim: "Go offline (every call fails)")
                                .font(.system(size: 14))
                                .foregroundColor(palette.text)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                    }
                    section("Demo") {
                        action("Reset demo") {
                            model.reset()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxHeight: 560)
        .background(RoundedRectangle(cornerRadius: 22).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text(verbatim: "Developer menu"))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(palette.muted)
            content()
        }
    }

    /// One of a row of exclusive choices.
    private func chip(_ title: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? Color.white : palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(on ? palette.accent : palette.background))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }

    /// A one-shot action.
    private func action(_ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.background))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
