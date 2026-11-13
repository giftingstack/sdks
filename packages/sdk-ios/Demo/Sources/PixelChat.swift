import GiftingStack
import SwiftUI

/// One bubble of the Chat tab: a text, or "You sent Rose x3" (the app draws it from the tray's `onSent`).
struct PixelChatMessage: Identifiable, Equatable {
    let id: Int
    let fromMe: Bool
    let text: String
    var gift: GiftSummary?
    var count: Int
    /// When a gift bubble last got a gift (its combo window).
    var at: Date = .distantPast

    /// The conversation at launch (as in packages/sdk-js/demo/web.ts).
    static let start: [PixelChatMessage] = [
        PixelChatMessage(id: 1, fromMe: false, text: "Did you catch my stream last night?", gift: nil, count: 1),
        PixelChatMessage(id: 2, fromMe: true, text: "Yes! The ending was wild 😄", gift: nil, count: 1),
        PixelChatMessage(id: 3, fromMe: false, text: "Right?? Going live again on Friday", gift: nil, count: 1),
    ]
}

/// Chat: a one-to-one messaging screen. The conversation, the text field and the bubbles are the app's OWN
/// chat (GiftingStack carries no chat); what comes from the SDK is the gift tray, the effects and the gift
/// button. The gift button sits in the message bar like an emoji button: it puts the tray where the keyboard
/// was (the keyboard closes), and a tap on the text field brings the keyboard back (SPEC 20).
@MainActor
struct PixelChatTab: View {
    @ObservedObject var model: PixelModel
    @ObservedObject var tray: GiftTrayModel
    /// The message field's focus, owned by `PixelContent` (it hides the tab bar while you type).
    let typing: FocusState<Bool>.Binding
    /// How far the message bar rises: to the keyboard's top while typing, to the tray's top edge while the tray
    /// is open (its `onInsetChange`).
    let lift: CGFloat
    let palette: PixelPalette
    let theme: GiftingTheme

    @State private var text = ""

    private static let peer = "mateo"

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "The conversation is your app's chat. The gift button opens the GiftingStack tray in the keyboard's place.")
                            .font(.system(size: 12))
                            .foregroundColor(palette.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 6)
                        ForEach(model.chat) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                // A tap on the conversation puts the keyboard and the tray away.
                .contentShape(Rectangle())
                .onTapGesture {
                    typing.wrappedValue = false
                    tray.close()
                }
                .onAppear {
                    scrollToEnd(proxy, animated: false)
                }
                .onChange(of: model.chat) { _ in
                    scrollToEnd(proxy, animated: true)
                }
                .onChange(of: lift) { _ in
                    scrollToEnd(proxy, animated: true)
                }
            }
            bar
                .padding(.bottom, lift)
                .animation(.easeOut(duration: 0.25), value: lift)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = model.chat.last else {
            return
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PixelAvatar(user: PixelChatTab.peer, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: PixelData.displayName(PixelChatTab.peer))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(palette.text)
                Text(verbatim: "online")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(palette.line).frame(height: 1), alignment: .bottom)
        .accessibilityElement(children: .combine)
    }

    private func bubble(_ message: PixelChatMessage) -> some View {
        HStack(spacing: 0) {
            if message.fromMe {
                Spacer(minLength: 48)
            }
            bubbleContent(message)
                .font(.system(size: 15))
                .foregroundColor(message.fromMe ? Color.white : palette.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(message.fromMe ? palette.accent : palette.card))
            if !message.fromMe {
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private func bubbleContent(_ message: PixelChatMessage) -> some View {
        if let gift = message.gift {
            HStack(spacing: 8) {
                if gift.iconUrl != nil {
                    GiftPicture(url: gift.iconUrl, size: 44)
                        .id(gift.iconUrl ?? "")
                }
                (Text(verbatim: "You sent ")
                    + Text(verbatim: gift.name).bold()
                    + Text(verbatim: message.count > 1 ? " ×\(message.count)" : ""))
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(verbatim: message.text)
        }
    }

    /// The app's message bar: its own text field with the SDK's gift button inside, and its own Send.
    private var bar: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            HStack(spacing: 0) {
                TextField("Message", text: $text)
                    // The SDK's binding: the gift button swaps the keyboard and the tray, a tap here closes the tray.
                    .giftTrayInput(tray, focused: typing)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }
                    .font(.system(size: 15))
                    .foregroundColor(palette.text)
                    .padding(.leading, 14)
                    .accessibilityLabel(Text(verbatim: "Message"))
                GiftButton(tray: tray, theme: theme)
            }
            .background(Capsule().fill(palette.card))
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(palette.accent))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .opacity(empty ? 0.5 : 1)
            .accessibilityLabel(Text(verbatim: "Send"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.background)
        .overlay(Rectangle().fill(palette.line).frame(height: 1), alignment: .top)
    }

    private func send() {
        model.sendChat(text)
        text = ""
    }
}
