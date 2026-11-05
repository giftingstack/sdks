#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// A gift picture from `GiftImageCache`: drawn at once when it is already decoded, otherwise as
/// soon as it arrives, without any fade-in (spec 7.2). "contain" fitting in a square box.
@MainActor
public struct GiftPicture: View {
    private let size: CGFloat
    @StateObject private var loader: GiftPictureLoader

    public init(url: String?, size: CGFloat) {
        self.size = size
        _loader = StateObject(wrappedValue: GiftPictureLoader(url: url))
    }

    public var body: some View {
        ZStack {
            if let image = loader.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loader.start()
        }
    }
}

@MainActor
final class GiftPictureLoader: ObservableObject {
    let url: String?
    @Published private(set) var image: CGImage?
    private var started = false

    init(url: String?) {
        self.url = url
        if let url = url {
            self.image = GiftImageCache.shared.cached(url)
        }
    }

    func start() {
        guard !started, image == nil, let url = url, !url.isEmpty else {
            return
        }
        started = true
        GiftImageCache.shared.load(url) { [weak self] loaded in
            self?.image = loaded
        }
    }
}
#endif
