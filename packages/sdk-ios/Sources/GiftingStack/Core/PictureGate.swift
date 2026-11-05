import Foundation

/// When an entered effect really starts (spec 7.2): once its picture has loaded or failed, or
/// once `pictureWaitMs` has passed, whichever comes first. No picture, or a wait of 0 or less:
/// at once. It starts exactly once. The effect layer owns the timer and the image loading and
/// reports them here; this class only decides, so it is tested without a screen.
public final class PictureGate {
    public let hasPicture: Bool
    public let pictureWaitMs: Int
    public private(set) var isStarted = false
    private let onStart: () -> Void

    public init(hasPicture: Bool, pictureWaitMs: Int, onStart: @escaping () -> Void) {
        self.hasPicture = hasPicture
        self.pictureWaitMs = pictureWaitMs
        self.onStart = onStart
    }

    /// Call when the effect enters. Returns the timeout (ms) the caller must schedule and report
    /// with `waitElapsed()`, or nil when the effect started right away.
    public func begin() -> Int? {
        if !hasPicture || pictureWaitMs <= 0 {
            fire()
            return nil
        }
        return pictureWaitMs
    }

    /// The picture is ready (decoded).
    public func pictureLoaded() {
        fire()
    }

    /// The picture failed to load: start anyway.
    public func pictureFailed() {
        fire()
    }

    /// The timer returned by `begin()` fired.
    public func waitElapsed() {
        fire()
    }

    private func fire() {
        if isStarted {
            return
        }
        isStarted = true
        onStart()
    }
}
