import AppKit

final class PetWindowController: NSObject {
    private let petSize = NSSize(width: 118, height: 106)
    private let footBottomInset: CGFloat = 11
    private let walkSpeed: CGFloat = 1
    private let window: NSPanel
    private let petView: PetView
    private var movementTimer: Timer?
    private var stateTimer: Timer?
    private var velocity = CGVector(dx: 1, dy: 0)
    private var state: PetState = .idle
    private var walkingDistanceRemaining: CGFloat = 0
    private var jumpAnimation: JumpAnimation?
    private var fallVelocity: CGFloat = 0
    private var sleepUntil: Date?
    private var nextSleepAllowedAt: Date?
    private var shouldSleepAfterLanding = false
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var walkingSurface = WalkingSurface.dock
    private var preferNextWalkRight = true
    private let onOpenManager: () -> Void

    init(portraitSet: PetPortraitSet? = nil, onOpenManager: @escaping () -> Void) {
        self.onOpenManager = onOpenManager
        petView = PetView(frame: NSRect(origin: .zero, size: petSize))
        petView.portraitSet = portraitSet

        window = NSPanel(
            contentRect: NSRect(x: 160, y: 160, width: petSize.width, height: petSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.contentView = petView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = []
        window.isMovableByWindowBackground = false

        petView.onTap = { [weak self] in
            self?.handleTap()
        }

        petView.onDragStart = { [weak self] mouseLocation in
            self?.beginDrag(at: mouseLocation)
        }

        petView.onDrag = { [weak self] mouseLocation in
            self?.drag(to: mouseLocation)
        }

        petView.onDragEnd = { [weak self] in
            self?.endDrag()
        }

        petView.onOpenManager = { [weak self] in
            self?.onOpenManager()
        }
    }

    func show() {
        positionNearBottomRight()
        window.level = .floating
        window.alphaValue = 1
        window.contentView?.needsDisplay = true
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        print("AniblePet is running at window frame: \(window.frame)")
        print(PetPortraitUploadInterface.requirementsText())
        startBehaviorLoop()
    }

    func useProfile(_ profile: PetProfile) {
        petView.portraitSet = profile.portraitSet
        petView.needsDisplay = true
    }

    private func startBehaviorLoop() {
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        stateTimer = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: true) { [weak self] _ in
            self?.chooseNextState()
        }
    }

    private func tick() {
        guard let screenFrame = currentVisibleFrame() else { return }
        guard !isDragging else {
            setPetOccluded(false)
            petView.needsDisplay = true
            return
        }
        dropToDockIfCurrentWindowMoved(on: screenFrame)
        updateWindowOcclusion()

        switch state {
        case .held:
            break
        case .falling:
            updateFall(on: screenFrame)
        case .idle:
            petView.lookAtMouse(windowFrame: window.frame)
            alignToCurrentSurface(on: screenFrame)
        case .walking:
            var frame = window.frame
            let surfaceFrame = movementFrame(on: screenFrame)
            let step = velocity.dx
            frame.origin.x += step
            frame.origin.x = min(max(frame.origin.x, surfaceFrame.minX), surfaceFrame.maxX)
            petView.facingRight = step > 0
            walkingDistanceRemaining -= abs(step)

            frame.origin.y = surfaceFrame.y
            window.setFrame(frame, display: true)
            if walkingDistanceRemaining <= 0
                || frame.origin.x <= surfaceFrame.minX
                || frame.origin.x >= surfaceFrame.maxX {
                setState(.idle)
            }
        case .jumping:
            updateJump()
        case .sleeping:
            break
        }

        petView.state = state
    }

    private func chooseNextState() {
        guard state != .jumping, state != .falling, state != .held, !isDragging else { return }
        if state == .sleeping {
            if let sleepUntil, Date() < sleepUntil {
                return
            }
            nextSleepAllowedAt = Date().addingTimeInterval(15 * 60)
            setState(.idle)
            return
        }

        let next = PetState.weightedRandom()
        switch next {
        case .idle:
            setState(.idle)
        case .walking:
            startShortWalk()
        case .jumping:
            if !startJump() {
                setState(.idle)
            }
        case .falling:
            break
        case .held:
            break
        case .sleeping:
            if canSleepNow() {
                setState(.sleeping)
            } else {
                setState(.idle)
            }
        }
    }

    private func canSleepNow() -> Bool {
        guard let nextSleepAllowedAt else { return true }
        return Date() >= nextSleepAllowedAt
    }

    private func setState(_ next: PetState) {
        if next == .sleeping, state != .sleeping {
            sleepUntil = Date().addingTimeInterval(TimeInterval.random(in: 60...600))
        } else if next != .sleeping {
            sleepUntil = nil
        }

        state = next
        petView.state = next
        if next != .walking {
            walkingDistanceRemaining = 0
        }
    }

    private func handleTap() {
        if state == .sleeping {
            wakeFromSleepByInteraction()
            scheduleSleepAfterInterruptionIfNeeded()
            return
        }

        if !startJump() {
            startShortWalk()
        }
    }

    private func beginDrag(at mouseLocation: NSPoint) {
        let wasSleeping = state == .sleeping
        walkingSurface = .dock
        jumpAnimation = nil
        if wasSleeping {
            wakeFromSleepByInteraction()
            shouldSleepAfterLanding = Int.random(in: 0..<100) < 60
        }

        isDragging = true
        setState(.held)
        dragStartMouseLocation = mouseLocation
        dragStartWindowOrigin = window.frame.origin
    }

    private func wakeFromSleepByInteraction() {
        sleepUntil = nil
        setState(.idle)
    }

    private func scheduleSleepAfterInterruptionIfNeeded() {
        guard Int.random(in: 0..<100) < 60 else { return }
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, !self.isDragging, self.state == .idle else { return }
            self.setState(.sleeping)
        }
    }

    private func sleepAfterLandingIfNeeded() {
        guard shouldSleepAfterLanding else { return }
        shouldSleepAfterLanding = false
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, !self.isDragging, self.state == .idle else { return }
            self.setState(.sleeping)
        }
    }

    private func drag(to mouseLocation: NSPoint) {
        setPetOccluded(false)
        guard let dragStartMouseLocation, let dragStartWindowOrigin else { return }
        var frame = window.frame
        frame.origin.x = dragStartWindowOrigin.x + mouseLocation.x - dragStartMouseLocation.x
        frame.origin.y = dragStartWindowOrigin.y + mouseLocation.y - dragStartMouseLocation.y
        window.setFrame(frame, display: true)
        petView.needsDisplay = true
    }

    private func endDrag() {
        isDragging = false
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        startFallIfNeeded()
    }

    private func positionNearBottomRight() {
        guard let screenFrame = currentVisibleFrame() else { return }
        var frame = window.frame
        frame.origin.x = screenFrame.midX - frame.width / 2
        frame.origin.y = dockSurfaceY(on: screenFrame)
        window.setFrame(frame, display: true)
    }

    private func currentVisibleFrame() -> NSRect? {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    private func movementFrame(on screenFrame: NSRect) -> (minX: CGFloat, maxX: CGFloat, y: CGFloat) {
        movementFrame(for: walkingSurface, on: screenFrame)
    }

    private func dockSurfaceY(on screenFrame: NSRect) -> CGFloat {
        screenFrame.minY - footBottomInset + 1
    }

    private func startShortWalk() {
        guard chooseWalkDirection() else {
            setState(.idle)
            return
        }
        walkingDistanceRemaining = CGFloat.random(in: 45...260)
        setState(.walking)
    }

    private func chooseWalkDirection() -> Bool {
        guard let screenFrame = currentVisibleFrame() else {
            velocity.dx = preferNextWalkRight ? walkSpeed : -walkSpeed
            return true
        }

        let surfaceFrame = movementFrame(on: screenFrame)
        let frame = window.frame
        let edgePadding: CGFloat = 44
        let canMoveRight = frame.origin.x < surfaceFrame.maxX - edgePadding
        let canMoveLeft = frame.origin.x > surfaceFrame.minX + edgePadding

        if canMoveRight && (!canMoveLeft || preferNextWalkRight) {
            velocity.dx = walkSpeed
            preferNextWalkRight = false
        } else if canMoveLeft {
            velocity.dx = -walkSpeed
            preferNextWalkRight = true
        } else {
            return false
        }

        petView.facingRight = velocity.dx > 0
        return true
    }

    private func alignToCurrentSurface(on screenFrame: NSRect) {
        let surfaceFrame = movementFrame(on: screenFrame)
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, surfaceFrame.minX), surfaceFrame.maxX)
        frame.origin.y = surfaceFrame.y
        window.setFrame(frame, display: true)
    }

    private func startJump() -> Bool {
        guard let screenFrame = currentVisibleFrame() else { return false }

        let targetSurface: WalkingSurface
        switch walkingSurface {
        case .dock:
            guard let platform = nearbyWindowPlatform() else { return false }
            targetSurface = .windowTop(platform)
        case .windowTop:
            targetSurface = .dock
        }

        let targetFrame = movementFrame(for: targetSurface, on: screenFrame)
        var targetOrigin = window.frame.origin
        targetOrigin.x = min(max(targetOrigin.x, targetFrame.minX), targetFrame.maxX)
        targetOrigin.y = targetFrame.y

        jumpAnimation = JumpAnimation(
            startOrigin: window.frame.origin,
            targetOrigin: targetOrigin,
            targetSurface: targetSurface,
            startedAt: Date(),
            duration: 0.68
        )
        setState(.jumping)
        return true
    }

    private func startFallIfNeeded() {
        guard let screenFrame = currentVisibleFrame() else { return }
        let dockFrame = movementFrame(for: .dock, on: screenFrame)
        if window.frame.origin.y <= dockFrame.y + 2 {
            moveToDock(on: screenFrame)
            return
        }

        startFall()
    }

    private func updateFall(on screenFrame: NSRect) {
        var frame = window.frame
        let currentY = frame.origin.y
        fallVelocity = min(fallVelocity + 0.42, 13)
        let nextY = currentY - fallVelocity
        let landingSurface = landingSurfaceBelow(currentFrame: frame, fromY: currentY, toY: nextY, on: screenFrame)
        let landingFrame = movementFrame(for: landingSurface, on: screenFrame)

        if nextY <= landingFrame.y {
            walkingSurface = landingSurface
            frame.origin.x = min(max(frame.origin.x, landingFrame.minX), landingFrame.maxX)
            frame.origin.y = landingFrame.y
            window.setFrame(frame, display: true)
            fallVelocity = 0
            setState(.idle)
            sleepAfterLandingIfNeeded()
        } else {
            frame.origin.y = nextY
            window.setFrame(frame, display: true)
        }
    }

    private func landingSurfaceBelow(currentFrame: NSRect, fromY: CGFloat, toY: CGFloat, on screenFrame: NSRect) -> WalkingSurface {
        let dockSurface = WalkingSurface.dock
        let dockY = movementFrame(for: dockSurface, on: screenFrame).y
        var bestSurface = dockSurface
        var bestY = dockY

        for platform in windowPlatformsBelow(currentFrame: currentFrame) {
            let platformY = platform.y
            guard platformY <= fromY + 1, platformY >= toY - 1 else { continue }
            if platformY > bestY {
                bestY = platformY
                bestSurface = .windowTop(platform)
            }
        }

        return bestSurface
    }

    private func updateJump() {
        guard let jumpAnimation else {
            setState(.idle)
            return
        }

        let elapsed = Date().timeIntervalSince(jumpAnimation.startedAt)
        let progress = min(max(elapsed / jumpAnimation.duration, 0), 1)
        let eased = 1 - pow(1 - CGFloat(progress), 3)
        let arcHeight = sin(CGFloat(progress) * .pi) * 52

        var frame = window.frame
        frame.origin.x = jumpAnimation.startOrigin.x + (jumpAnimation.targetOrigin.x - jumpAnimation.startOrigin.x) * eased
        frame.origin.y = jumpAnimation.startOrigin.y + (jumpAnimation.targetOrigin.y - jumpAnimation.startOrigin.y) * eased + arcHeight
        window.setFrame(frame, display: true)

        if progress >= 1 {
            walkingSurface = jumpAnimation.targetSurface
            self.jumpAnimation = nil
            setState(.idle)
        }
    }

    private func nearbyWindowPlatform() -> WindowPlatform? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        let petMidX = window.frame.midX
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let appPID = ProcessInfo.processInfo.processIdentifier

        let candidates = windows.compactMap { info -> WindowPlatform? in
            guard
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                (info[kCGWindowOwnerPID as String] as? pid_t) != appPID,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let alpha = info[kCGWindowAlpha as String] as? Double,
                alpha > 0,
                let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else {
                return nil
            }

            let rect = appKitRect(fromQuartzRect: bounds, on: screen)
            guard rect.width >= 180, rect.height >= 80 else { return nil }
            guard rect.intersects(screen.visibleFrame) else { return nil }
            guard rect.maxY - footBottomInset + window.frame.height <= screen.visibleFrame.maxY - 6 else { return nil }

            let distance: CGFloat
            if petMidX < rect.minX {
                distance = rect.minX - petMidX
            } else if petMidX > rect.maxX {
                distance = petMidX - rect.maxX
            } else {
                distance = 0
            }
            guard distance <= 280 else { return nil }

            return WindowPlatform(
                windowID: windowID,
                windowRect: rect,
                minX: rect.minX + 8,
                maxX: rect.maxX - 8,
                y: rect.maxY - footBottomInset,
                distance: distance
            )
        }

        return candidates.min(by: { $0.distance < $1.distance })
    }

    private func windowPlatformsBelow(currentFrame: NSRect) -> [WindowPlatform] {
        allWindowPlatforms().filter { platform in
            let petLeft = currentFrame.minX + 24
            let petRight = currentFrame.maxX - 24
            return petRight >= platform.minX && petLeft <= platform.maxX
        }
    }

    private func allWindowPlatforms() -> [WindowPlatform] {
        guard let screen = window.screen ?? NSScreen.main else { return [] }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let appPID = ProcessInfo.processInfo.processIdentifier

        return windows.compactMap { info -> WindowPlatform? in
            guard
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                (info[kCGWindowOwnerPID as String] as? pid_t) != appPID,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let alpha = info[kCGWindowAlpha as String] as? Double,
                alpha > 0,
                let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else {
                return nil
            }

            let rect = appKitRect(fromQuartzRect: bounds, on: screen)
            guard rect.width >= 180, rect.height >= 80 else { return nil }
            guard rect.intersects(screen.visibleFrame) else { return nil }
            guard rect.maxY - footBottomInset + window.frame.height <= screen.visibleFrame.maxY - 6 else { return nil }

            return WindowPlatform(
                windowID: windowID,
                windowRect: rect,
                minX: rect.minX + 8,
                maxX: rect.maxX - 8,
                y: rect.maxY - footBottomInset,
                distance: 0
            )
        }
    }

    private func dropToDockIfCurrentWindowMoved(on screenFrame: NSRect) {
        guard case .windowTop(let platform) = walkingSurface else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow], platform.windowID) as? [[String: Any]] ?? []
        guard
            let info = windows.first,
            let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
        else {
            startFall()
            return
        }

        let currentRect = appKitRect(fromQuartzRect: bounds, on: screen)
        let standingY = currentRect.maxY - footBottomInset
        let hasHeadroom = standingY + window.frame.height <= screen.visibleFrame.maxY - 6
        guard hasHeadroom else {
            startFall()
            return
        }

        let updatedPlatform = WindowPlatform(
            windowID: platform.windowID,
            windowRect: currentRect,
            minX: currentRect.minX + 8,
            maxX: currentRect.maxX - 8,
            y: standingY,
            distance: platform.distance
        )

        if let liftingPlatform = liftingWindowPlatform(above: platform, on: screenFrame) {
            moveToWindowTop(liftingPlatform, on: screenFrame)
            return
        }

        if !currentRect.isNearlyEqual(to: platform.windowRect, tolerance: 2) {
            if updatedPlatform.y >= platform.y - 2 {
                moveToWindowTop(updatedPlatform, on: screenFrame)
            } else {
                startFall()
            }
        }
    }

    private func liftingWindowPlatform(above currentPlatform: WindowPlatform, on screenFrame: NSRect) -> WindowPlatform? {
        let currentFrame = window.frame
        let petLeft = currentFrame.minX + 24
        let petRight = currentFrame.maxX - 24
        let currentPlatformY = currentPlatform.y
        let liftTolerance: CGFloat = 18

        return allWindowPlatforms()
            .filter { platform in
                platform.windowID != currentPlatform.windowID
                    && platform.y > currentPlatformY
                    && platform.y <= currentFrame.origin.y + liftTolerance
                    && petRight >= platform.minX
                    && petLeft <= platform.maxX
                    && platform.y + window.frame.height <= screenFrame.maxY - 6
            }
            .max { $0.y < $1.y }
    }

    private func moveToWindowTop(_ platform: WindowPlatform, on screenFrame: NSRect) {
        walkingSurface = .windowTop(platform)
        jumpAnimation = nil
        fallVelocity = 0

        var frame = window.frame
        let surfaceFrame = movementFrame(for: .windowTop(platform), on: screenFrame)
        frame.origin.x = min(max(frame.origin.x, surfaceFrame.minX), surfaceFrame.maxX)
        frame.origin.y = surfaceFrame.y
        window.setFrame(frame, display: true)
    }

    private func startFall() {
        walkingSurface = .dock
        jumpAnimation = nil
        fallVelocity = 2.5
        setState(.falling)
    }

    private func moveToDock(on screenFrame: NSRect) {
        walkingSurface = .dock
        jumpAnimation = nil
        var frame = window.frame
        let surfaceFrame = movementFrame(for: .dock, on: screenFrame)
        frame.origin.x = min(max(frame.origin.x, surfaceFrame.minX), surfaceFrame.maxX)
        frame.origin.y = surfaceFrame.y
        window.setFrame(frame, display: true)
        if state == .jumping {
            setState(.idle)
        }
        sleepAfterLandingIfNeeded()
    }

    private func movementFrame(for surface: WalkingSurface, on screenFrame: NSRect) -> (minX: CGFloat, maxX: CGFloat, y: CGFloat) {
        switch surface {
        case .dock:
            return (
                minX: screenFrame.minX + 12,
                maxX: screenFrame.maxX - window.frame.width - 12,
                y: dockSurfaceY(on: screenFrame)
            )
        case .windowTop(let platform):
            return (
                minX: platform.minX,
                maxX: platform.maxX - window.frame.width,
                y: platform.y
            )
        }
    }

    private func appKitRect(fromQuartzRect rect: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        return CGRect(
            x: rect.origin.x,
            y: screenFrame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func updateWindowOcclusion() {
        guard case .windowTop(let platform) = walkingSurface else {
            setPetOccluded(false)
            return
        }

        guard state != .jumping, state != .falling, state != .held else {
            setPetOccluded(false)
            return
        }

        guard let screen = window.screen ?? NSScreen.main else {
            setPetOccluded(false)
            return
        }

        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let appPID = ProcessInfo.processInfo.processIdentifier
        let petBodyRect = window.frame.insetBy(dx: 18, dy: 10)
        var foundCurrentPlatform = false

        for info in windows {
            guard
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                (info[kCGWindowOwnerPID as String] as? pid_t) != appPID,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let alpha = info[kCGWindowAlpha as String] as? Double,
                alpha > 0,
                let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else {
                continue
            }

            if windowID == platform.windowID {
                foundCurrentPlatform = true
                break
            }

            let rect = appKitRect(fromQuartzRect: bounds, on: screen)
            guard rect.width >= 80, rect.height >= 60 else { continue }
            if rect.intersects(petBodyRect) {
                setPetOccluded(true)
                return
            }
        }

        setPetOccluded(!foundCurrentPlatform)
    }

    private func setPetOccluded(_ isOccluded: Bool) {
        window.alphaValue = isOccluded ? 0 : 1
        window.ignoresMouseEvents = isOccluded
    }
}

private enum WalkingSurface {
    case dock
    case windowTop(WindowPlatform)
}

private struct WindowPlatform {
    let windowID: CGWindowID
    let windowRect: CGRect
    let minX: CGFloat
    let maxX: CGFloat
    let y: CGFloat
    let distance: CGFloat
}

private struct JumpAnimation {
    let startOrigin: NSPoint
    let targetOrigin: NSPoint
    let targetSurface: WalkingSurface
    let startedAt: Date
    let duration: TimeInterval
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
