import GiftingStack
import SwiftUI

/// A pretend coin store (like packages/sdk-js/demo/coinStore.ts). In a real app `onTopUp` opens
/// YOUR store (in-app purchase); your server confirms the payment and credits the coins through
/// the API. Nothing is charged here.
struct CoinStoreView: View {
    struct Pack: Identifiable {
        let coins: Int
        let price: String

        var id: Int {
            coins
        }
    }

    static let packs: [Pack] = [
        Pack(coins: 1_000, price: "$0.99"),
        Pack(coins: 5_000, price: "$4.49"),
        Pack(coins: 20_000, price: "$15.99"),
    ]

    let bottomInset: CGFloat
    let onBuy: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose()
                }
                .accessibilityHidden(true)
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Get coins")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(giftingHex: 0xF4F2FF))
            Text(verbatim: "Demo store: nothing is charged.")
                .font(.system(size: 12))
                .foregroundColor(Color(giftingHex: 0xA3A1C2))
            ForEach(CoinStoreView.packs) { pack in
                Button {
                    onBuy(pack.coins)
                } label: {
                    HStack {
                        Text(verbatim: "+\(formatCoins(pack.coins)) coins")
                            .foregroundColor(Color(giftingHex: 0xF4F2FF))
                        Spacer()
                        Text(verbatim: pack.price)
                            .foregroundColor(Color(giftingHex: 0xFFD27A))
                    }
                    .font(.system(size: 15, weight: .bold))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(giftingHex: 0x14141F)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(giftingHex: 0x2D2D44), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button {
                onClose()
            } label: {
                Text(verbatim: "Not now")
                    .font(.system(size: 14))
                    .foregroundColor(Color(giftingHex: 0xA3A1C2))
                    .frame(maxWidth: .infinity)
                    .padding(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 22 + bottomInset)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(giftingHex: 0x1E1E2E)))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text(verbatim: "Coin store"))
    }
}
