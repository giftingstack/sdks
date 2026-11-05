#if canImport(SwiftUI) && canImport(ImageIO)
import Combine
import Foundation
import SwiftUI

/// Whether the app runs on a test key, as reported by the `GiftTrayModel`s that are alive
/// (`me.livemode == false`). `GiftTray` shows its "Test mode" badge from this when its `testMode`
/// parameter is nil. A key belongs to the whole app, so one report is enough; a model's report goes
/// away on `stop()` and when it is released.
///
/// Everything here runs on the main thread (the models are main actor types); the class itself is not
/// annotated so that a `View` can hold it as an `@ObservedObject` default under any SDK.
final class GiftTrayTestModeRegistry: ObservableObject {
    static let shared = GiftTrayTestModeRegistry()

    /// True while any live model has reported a test token.
    @Published private(set) var active = false

    private var reporting: Set<ObjectIdentifier> = []

    init() {}

    func report(_ owner: ObjectIdentifier, testMode: Bool) {
        if testMode {
            reporting.insert(owner)
        } else {
            reporting.remove(owner)
        }
        publish()
    }

    func forget(_ owner: ObjectIdentifier) {
        reporting.remove(owner)
        publish()
    }

    private func publish() {
        let next = !reporting.isEmpty
        if next != active {
            active = next
        }
    }
}
#endif
