#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// Publishes a `TraySheetController`'s state to SwiftUI (spec 9.1: an ObservableObject wrapper),
/// and owns the grid's scroll position and momentum.
@MainActor
final class TraySheetModel: ObservableObject {
    let controller: TraySheetController
    @Published private(set) var state: TraySheetState
    /// How far the grid is scrolled (points). Momentum runs here frame by frame, not as a SwiftUI
    /// animation, so this is always what is on screen: a new touch starts from there.
    @Published private(set) var gridScroll: CGFloat = 0
    private(set) var gridScrollLimit: CGFloat = 0
    private var momentum: Task<Void, Never>?
    private var unsubscribe: (() -> Void)?

    init(initialSnap: SheetSnap) {
        let controller = TraySheetController(initialSnap: initialSnap)
        self.controller = controller
        self.state = controller.state
        unsubscribe = controller.subscribe { [weak self] next in
            self?.state = next
        }
    }

    var isFlinging: Bool {
        momentum != nil
    }

    func scrollGrid(to value: CGFloat) {
        let next = min(gridScrollLimit, max(0, value))
        if next != gridScroll {
            gridScroll = next
        }
    }

    func setGridScrollLimit(_ limit: CGFloat) {
        gridScrollLimit = max(0, limit)
        scrollGrid(to: gridScroll)
    }

    func stopMomentum() {
        momentum?.cancel()
        momentum = nil
    }

    /// Lets the grid run on after a flick. `velocity`: points per second, positive = the scroll
    /// position grows. Without animation it jumps to where the momentum would end.
    func fling(velocity: Double, animated: Bool) {
        stopMomentum()
        let start = SheetGridMomentum(velocity: velocity)
        if start.finished {
            return
        }
        if !animated {
            scrollGrid(to: gridScroll + CGFloat(start.totalDistance))
            return
        }
        momentum = Task { [weak self] in
            var run = start
            var last = ProcessInfo.processInfo.systemUptime
            while true {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled {
                    return
                }
                guard let model = self else {
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                let distance = run.step(dtMs: (now - last) * 1000)
                last = now
                model.scrollGrid(to: model.gridScroll + CGFloat(distance))
                if run.finished || model.gridScroll <= 0 || model.gridScroll >= model.gridScrollLimit {
                    model.momentum = nil
                    return
                }
            }
        }
    }
}

/// One drag on the sheet: who owns it (decided once, spec 9.1) and where it started.
struct SheetDragState {
    enum Mode {
        case sheet
        case grid
        case ignored
    }

    var mode: Mode
    /// `startLocation` of the gesture: tells a new gesture from the one this state belongs to.
    var start: CGPoint
    var lastDy: CGFloat = 0
    var startScroll: CGFloat = 0
    var tracker = SheetVelocityTracker()
}

struct SheetTopBlockKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SheetFooterKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SheetRowKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The tray as a bottom sheet (spec 9.1). Every decision (heights, snapping, flick, who owns a
/// drag) comes from `TraySheetController`; this file measures, moves the body with an offset and
/// passes the finger through. The body is laid out once at the expanded height; the footer
/// (selected gift and Send) stays at the bottom, drawn above the body.
extension GiftTray {
    static let sheetSpace = "giftingstack.sheet"

    var sheetBody: some View {
        let measure = sheetMeasure(container: containerHeight)
        return GeometryReader { geo in
            // The dim is the first layer: behind the sheet and the footer, above your screen (spec 9.4).
            ZStack(alignment: .bottom) {
                if scrim {
                    scrimLayer
                }
                sheetStack(width: geo.size.width, height: geo.size.height)
                    // Closed: nothing to touch and nothing for VoiceOver (the view itself is invisible).
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(!isOpen)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                containerHeight = geo.size.height
                sheetModel.controller.setOnSnapChange(onSnapChange)
                applySheetMeasure(sheetMeasure(container: geo.size.height))
                // Closed: the inset is 0.
                onInsetChange?(isOpen ? CGFloat(sheetModel.state.visibleHeight) : 0)
                showAfterFallbackWithoutRows()
            }
            .onChange(of: geo.size.height) { height in
                containerHeight = height
            }
        }
        // Only state is set here (the pattern the fixed tray already uses); the layout follows in
        // `onChange(of: measure)`.
        .onPreferenceChange(SheetTopBlockKey.self) { value in
            topBlockHeight = value
        }
        .onPreferenceChange(SheetFooterKey.self) { value in
            footerHeight = value
        }
        .onPreferenceChange(SheetRowKey.self) { value in
            rowHeight = value
        }
        // Every input (container, header, footer, row, gift count, columns, snaps) in one value,
        // applied from the NEW value only: an `onChange` action may still hold the previous
        // render's `gifts`, which kept the content cap at the old gift count.
        .onChange(of: measure) { next in
            applySheetMeasure(next)
            // `floorsReady`: header and footer measured, and a row when there are gifts. An EMPTY catalog has
            // no row to measure, and used to leave the sheet invisible for good.
            // A closed tray is not shown; opening runs `sheetOpenChanged`.
            if !sheetShown, isOpen, next.floorsReady {
                // The layout is in place (without animation): show the sheet a moment later.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    sheetShown = true
                }
            }
        }
        .onChange(of: sheetTouching) { touching in
            if !touching {
                closeInterruptedDrag()
            }
        }
        .onChange(of: sheetModel.state.visibleHeight) { value in
            // While closed `onInsetChange` only ever says 0 (said once, when it closed).
            if isOpen {
                onInsetChange?(CGFloat(value))
            }
        }
        .onChange(of: isOpen) { open in
            sheetOpenChanged(open)
        }
    }

    /// The tray opened or closed (spec 9.4). Closing hides the sheet at once and puts it back at its
    /// first state with a jump (nothing is visible, nothing glides on the next open); the inset is 0.
    /// Opening places it again without a glide: it is shown a moment after, as for the first time.
    private func sheetOpenChanged(_ open: Bool) {
        if !open {
            sheetShown = false
            sheetModel.controller.snapTo(initialSnap)
            onInsetChange?(0)
            return
        }
        onInsetChange?(CGFloat(sheetModel.state.visibleHeight))
        if !sheetShown, sheetMeasure(container: containerHeight).floorsReady {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                if isOpen {
                    sheetShown = true
                }
            }
        }
        showAfterFallbackWithoutRows()
    }

    /// The dim (spec 9.4): black at `scrimOpacity`, fades over `scrimFadeMs` (ease-out, both directions).
    /// It takes touches and is the button "Close gift tray" only while visible.
    private var scrimLayer: some View {
        let visible = scrimVisible(scrim: scrim, open: isOpen, snap: sheetModel.state.snap, placed: sheetShown)
        let ms = scrimFadeMs(reducedMotion: reduceMotion)
        return Color.black
            .opacity(visible ? scrimOpacity : 0)
            .animation(ms == 0 ? nil : .easeOut(duration: Double(ms) / 1000), value: visible)
            .contentShape(Rectangle())
            .onTapGesture {
                tapScrim()
            }
            .allowsHitTesting(visible)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Close gift tray"))
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(!visible)
            .accessibilityAction {
                tapScrim()
            }
            .accessibilityIdentifier("gift-scrim")
    }

    /// A tap on the scrim (spec 9.4).
    private func tapScrim() {
        switch scrimTapOutcome(scrim: scrim, scrimTap: scrimTap, open: isOpen, snap: sheetModel.state.snap) {
        case .lower:
            sheetModel.controller.snapTo(.peek)
        case .dismiss:
            // The `open` parameter, when given, is the host's to change.
            closeOwnTray?()
            onDismiss?()
        case .ignored:
            break
        }
    }

    /// Like the web tray: if no grid row was measured after `SheetMeasure.emptyFallbackMs` (no gifts, or the
    /// catalog is still loading), the sheet is shown anyway instead of staying invisible. `rowHeight` is
    /// `@State`, so this reads the current value, not the one of the render that started the wait.
    private func showAfterFallbackWithoutRows() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SheetMeasure.emptyFallbackMs) * 1_000_000)
            if !sheetShown, isOpen, rowHeight == 0 {
                sheetShown = true
            }
        }
    }

    private func sheetStack(width: CGFloat, height: CGFloat) -> some View {
        let st = sheetModel.state
        let icon = GiftTray.iconSize(gridWidth: width - 28, columns: columns)
        return ZStack(alignment: .bottom) {
            sheetPanel(st: st, width: width, iconSize: icon)
            sheetFooter(width: width)
        }
        .frame(width: width, height: height, alignment: .bottom)
        .clipped()
        .coordinateSpace(name: GiftTray.sheetSpace)
        // Drawn from the first measured layout on (the heights, the first row and the footer), so
        // the sheet never shows its unmeasured guess and then jumps: it fades in where it belongs.
        .opacity(sheetShown ? 1 : 0)
        .offset(y: sheetShown || reduceMotion ? 0 : 24)
        // Only the entrance glides; hiding (a closed tray) is at once.
        .animation(reduceMotion || !sheetShown ? nil : .easeOut(duration: 0.2), value: sheetShown)
    }

    // MARK: - Body (handle, header, grid)

    private func sheetPanel(st: TraySheetState, width: CGFloat, iconSize: CGFloat) -> some View {
        let expanded = CGFloat(st.heights.expanded)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                sheetHandle(st)
                header
            }
            // Its natural height whatever the body's frame is (the body is 0 high until measured).
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SheetTopBlockKey.self, value: proxy.size.height)
                }
            )
            Color.clear.frame(height: CGFloat(SheetMeasure.bodyGap))
            sheetGrid(st: st, iconSize: iconSize)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: max(0, expanded), alignment: .top)
        .background(TopRoundedRectangle(radius: 24).fill(theme.surface))
        .overlay(TopRoundedRectangle(radius: 24).stroke(theme.border, lineWidth: 0.5))
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
        .offset(y: CGFloat(st.offset))
        .animation(sheetShown ? sheetAnimation(st) : nil, value: st.offset)
    }

    private func sheetAnimation(_ st: TraySheetState) -> Animation? {
        if st.dragging || reduceMotion {
            return nil
        }
        return .timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
    }

    private func sheetHandle(_ st: TraySheetState) -> some View {
        Capsule()
            .fill(theme.muted)
            .opacity(0.7)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if !recentlyDragged {
                    sheetModel.controller.toggle()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Gift tray"))
            .accessibilityValue(Text(verbatim: st.snap.rawValue))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                _ = sheetModel.controller.toggle()
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    sheetModel.controller.step(1)
                case .decrement:
                    sheetModel.controller.step(-1)
                default:
                    break
                }
            }
            .accessibilityAction(named: Text(verbatim: "Show more gifts")) {
                _ = sheetModel.controller.step(1)
            }
            .accessibilityAction(named: Text(verbatim: "Show fewer gifts")) {
                _ = sheetModel.controller.step(-1)
            }
            .padding(.bottom, -8)
    }

    /// The grid is scrolled by the sheet's own gesture (iOS 15 has no way to switch a
    /// `ScrollView` off): offset + clip, momentum run by `TraySheetModel`.
    private func sheetGrid(st: TraySheetState, iconSize: CGFloat) -> some View {
        let perRow = max(1, columns)
        let rows: [[Gift]] = stride(from: 0, to: gifts.count, by: perRow).map { start in
            Array(gifts[start..<min(start + perRow, gifts.count)])
        }
        let hidden = st.snap == .peek && !st.dragging
        let viewport = CGFloat(sheetMeasure(container: containerHeight).gridViewport(expanded: st.heights.expanded))
        // Plain rows, not LazyVGrid: outside a ScrollView a lazy grid has no viewport to
        // realise rows against, estimates their heights first and draws lower rows over
        // upper ones until it has measured them.
        return VStack(spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<perRow, id: \.self) { c in
                        if c < rows[r].count {
                            sheetCell(rows[r][c], iconSize: iconSize)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                // The first row's height is the row height (spec 9.1, as on Android).
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: SheetRowKey.self, value: r == 0 ? proxy.size.height : 0)
                    }
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: -sheetModel.gridScroll)
        .frame(height: viewport, alignment: .top)
        .clipped()
        // Clipping does not stop hits: cells scrolled out of the viewport must not take taps.
        .contentShape(Rectangle())
        .accessibilityHidden(hidden)
    }

    private func sheetCell(_ gift: Gift, iconSize: CGFloat) -> some View {
        let isSelected = gift.id == selected?.id
        return cellContent(gift, iconSize: iconSize)
            .onTapGesture {
                if recentlyDragged {
                    return
                }
                // A tap on a coasting grid only stops it (as a UIScrollView does).
                if sheetModel.isFlinging {
                    sheetModel.stopMomentum()
                    return
                }
                select(gift)
            }
            .padding(4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: cellLabel(gift)))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction {
                select(gift)
            }
    }

    // MARK: - Footer (selected gift, Send)

    private func sheetFooter(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            if let gift = selected {
                pickedGift(gift)
                    .frame(maxWidth: width * 0.45, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
            }
            sendButton
        }
        .padding(.top, 10)
        .padding(.horizontal, 14)
        .padding(.bottom, bottomPadding)
        .frame(width: width)
        .background(theme.surface)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetFooterKey.self, value: proxy.size.height)
            }
        )
    }

    private func pickedGift(_ gift: Gift) -> some View {
        HStack(spacing: 8) {
            GiftPicture(url: gift.iconUrl, size: 36)
                .id(gift.iconUrl ?? "")
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: gift.name)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                priceRow(gift.price)
            }
        }
    }

    // MARK: - Measuring

    /// The content floors of spec 9.1 as measured in this render.
    func sheetMeasure(container: CGFloat) -> SheetMeasure {
        SheetMeasure(
            containerHeight: Double(container),
            topBlockHeight: Double(topBlockHeight),
            footerHeight: Double(footerHeight),
            rowHeight: Double(rowHeight),
            giftCount: gifts.count,
            columns: columns,
            snaps: snaps
        )
    }

    /// Feeds a measurement to the controller. Uses only `measure` and the model, never this
    /// view's other properties (see `onChange(of: measure)`).
    func applySheetMeasure(_ measure: SheetMeasure) {
        let model = sheetModel
        model.controller.setLayout(measure.layout)
        let expanded = model.controller.state.heights.expanded
        model.setGridScrollLimit(CGFloat(measure.maxGridScroll(expanded: expanded)))
    }

    // MARK: - Gesture

    /// A drag must not end in a tap on what is under the finger (spec 9.1).
    private var recentlyDragged: Bool {
        sheetDrag != nil || Date().timeIntervalSince(lastDragEnd) < 0.3
    }

    private var sheetDragGesture: some Gesture {
        // The container's space: it does not move with the sheet, so translations stay true.
        let space: CoordinateSpace = CoordinateSpace.named(GiftTray.sheetSpace)
        return DragGesture(minimumDistance: 6, coordinateSpace: space)
            .updating($sheetTouching) { _, touching, _ in
                touching = true
            }
            .onChanged { value in
                dragChanged(value)
            }
            .onEnded { value in
                dragEnded(value)
            }
    }

    private func startsOnGrid(_ location: CGPoint) -> Bool {
        let st = sheetModel.state
        let m = sheetMeasure(container: containerHeight)
        let top = containerHeight - CGFloat(st.heights.expanded) + CGFloat(st.offset)
            + CGFloat(m.topBlockHeight + SheetMeasure.bodyGap)
        return location.y >= top && location.y < top + CGFloat(m.gridViewport(expanded: st.heights.expanded))
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if let old = sheetDrag, old.start != value.startLocation {
            // The previous gesture was interrupted without `onEnded`: close it before this one.
            finishDrag(old, velocity: nil)
        }
        if sheetDrag == nil {
            beginDrag(value)
        }
        guard var drag = sheetDrag else {
            return
        }
        let dy = value.translation.height
        drag.tracker.add(t: value.time.timeIntervalSince1970 * 1000, y: Double(value.location.y))
        switch drag.mode {
        case .sheet:
            // The slop already travelled is applied too, so the sheet does not lag the finger.
            sheetModel.controller.drag(Double(dy - drag.lastDy))
            drag.lastDy = dy
        case .grid:
            sheetModel.scrollGrid(to: drag.startScroll - dy)
        case .ignored:
            break
        }
        sheetDrag = drag
    }

    /// First movement beyond the slop: decide once who owns this gesture (spec 9.1).
    private func beginDrag(_ value: DragGesture.Value) {
        sheetModel.stopMomentum()
        let dy = value.translation.height
        let dx = value.translation.width
        var mode = SheetDragState.Mode.sheet
        if abs(dy) <= abs(dx) {
            mode = .ignored
        } else if startsOnGrid(value.startLocation) {
            let owner = sheetModel.controller.scrollOwner(dy: Double(dy), gridScrollTop: Double(sheetModel.gridScroll))
            mode = owner == .sheet ? .sheet : .grid
        }
        if mode == .sheet {
            sheetModel.controller.dragStart()
        }
        sheetDrag = SheetDragState(mode: mode, start: value.startLocation, lastDy: 0, startScroll: sheetModel.gridScroll)
    }

    private func dragEnded(_ value: DragGesture.Value) {
        guard var drag = sheetDrag else {
            return
        }
        drag.tracker.add(t: value.time.timeIntervalSince1970 * 1000, y: Double(value.location.y))
        finishDrag(drag, velocity: drag.tracker.velocity())
    }

    /// Ends `drag`: with the finger's velocity (points per second, positive = down) a release,
    /// without one (interrupted) a cancel.
    private func finishDrag(_ drag: SheetDragState, velocity: Double?) {
        sheetDrag = nil
        lastDragEnd = Date()
        switch drag.mode {
        case .sheet:
            if let v = velocity {
                sheetModel.controller.release(v)
            } else {
                sheetModel.controller.cancel()
            }
        case .grid:
            if let v = velocity {
                // Finger up (negative) scrolls further down the list.
                sheetModel.fling(velocity: -v, animated: !reduceMotion)
            }
        case .ignored:
            break
        }
    }

    /// The gesture state went back to false. `onEnded` normally runs in the same update; if it
    /// did not (the gesture was cancelled), close the drag so the controller does not stay in
    /// `dragging` and taps work again.
    private func closeInterruptedDrag() {
        guard let start = sheetDrag?.start else {
            return
        }
        Task { @MainActor in
            if let drag = sheetDrag, drag.start == start {
                finishDrag(drag, velocity: nil)
            }
        }
    }
}
#endif
