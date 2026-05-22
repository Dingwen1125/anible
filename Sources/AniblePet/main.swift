import AppKit

@main
enum AniblePetMain {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = PetWindowController()
        controller?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

final class PetWindowController: NSObject {
    private let footBottomInset: CGFloat = 14
    private let window: NSPanel
    private let petView: PetView
    private var movementTimer: Timer?
    private var stateTimer: Timer?
    private var velocity = CGVector(dx: 1.4, dy: 0)
    private var state: PetState = .idle
    private var walkingDistanceRemaining: CGFloat = 0
    private var jumpAnimation: JumpAnimation?
    private var fallVelocity: CGFloat = 0
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var walkingSurface = WalkingSurface.dock

    override init() {
        petView = PetView(frame: NSRect(x: 0, y: 0, width: 148, height: 132))

        window = NSPanel(
            contentRect: NSRect(x: 160, y: 160, width: 148, height: 132),
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
        startBehaviorLoop()
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
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        guard !isDragging else {
            petView.needsDisplay = true
            return
        }
        dropToDockIfCurrentWindowMoved(on: screenFrame)

        switch state {
        case .held:
            break
        case .falling:
            updateFall(on: screenFrame)
        case .idle:
            alignToCurrentSurface(on: screenFrame)
        case .walking:
            var frame = window.frame
            frame.origin.x += velocity.dx
            walkingDistanceRemaining -= abs(velocity.dx)

            let surfaceFrame = movementFrame(on: screenFrame)
            let minX = surfaceFrame.minX
            let maxX = surfaceFrame.maxX
            if frame.origin.x <= minX || frame.origin.x >= maxX {
                velocity.dx *= -1
                frame.origin.x = min(max(frame.origin.x, minX), maxX)
                petView.facingRight = velocity.dx > 0
            }

            frame.origin.y = surfaceFrame.y
            window.setFrame(frame, display: true)
            if walkingDistanceRemaining <= 0 {
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
            setState(.sleeping)
        }
    }

    private func setState(_ next: PetState) {
        state = next
        petView.state = next
        if next == .walking {
            velocity.dx = abs(velocity.dx) * (Bool.random() ? 1 : -1)
            petView.facingRight = velocity.dx > 0
        }
    }

    private func handleTap() {
        if !startJump() {
            startShortWalk()
        }
    }

    private func beginDrag(at mouseLocation: NSPoint) {
        isDragging = true
        walkingSurface = .dock
        jumpAnimation = nil
        setState(.held)
        dragStartMouseLocation = mouseLocation
        dragStartWindowOrigin = window.frame.origin
    }

    private func drag(to mouseLocation: NSPoint) {
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
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        var frame = window.frame
        frame.origin.x = screenFrame.maxX - frame.width - 80
        frame.origin.y = dockSurfaceY(on: screenFrame)
        window.setFrame(frame, display: true)
    }

    private func movementFrame(on screenFrame: NSRect) -> (minX: CGFloat, maxX: CGFloat, y: CGFloat) {
        movementFrame(for: walkingSurface, on: screenFrame)
    }

    private func dockSurfaceY(on screenFrame: NSRect) -> CGFloat {
        screenFrame.minY - footBottomInset + 1
    }

    private func startShortWalk() {
        walkingDistanceRemaining = CGFloat.random(in: 70...180)
        setState(.walking)
    }

    private func alignToCurrentSurface(on screenFrame: NSRect) {
        let surfaceFrame = movementFrame(on: screenFrame)
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, surfaceFrame.minX), surfaceFrame.maxX)
        frame.origin.y = surfaceFrame.y
        window.setFrame(frame, display: true)
    }

    private func startJump() -> Bool {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return false }

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
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
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
        guard let screen = NSScreen.main else { return nil }
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
        guard let screen = NSScreen.main else { return [] }
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

            let petLeft = currentFrame.minX + 24
            let petRight = currentFrame.maxX - 24
            guard petRight >= rect.minX + 8, petLeft <= rect.maxX - 8 else { return nil }

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
        guard let screen = NSScreen.main else { return }

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
        if !currentRect.isNearlyEqual(to: platform.windowRect, tolerance: 2) {
            startFall()
        }
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

enum PetState {
    case idle
    case walking
    case jumping
    case falling
    case held
    case sleeping

    static func weightedRandom() -> PetState {
        let roll = Int.random(in: 0..<100)
        switch roll {
        case 0..<42:
            return .idle
        case 42..<66:
            return .walking
        case 66..<88:
            return .jumping
        default:
            return .sleeping
        }
    }
}

final class PetView: NSView {
    var onTap: (() -> Void)?
    var onDragStart: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var state: PetState = .walking {
        didSet { needsDisplay = true }
    }
    var facingRight = true {
        didSet { needsDisplay = true }
    }

    private var mouseDownLocation: NSPoint?
    private var hasStartedDrag = false
    private var blinkTimer: Timer?
    private var isBlinking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { [weak self] _ in
            self?.blink()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation else { return }
        let current = NSEvent.mouseLocation
        if !hasStartedDrag && hypot(current.x - mouseDownLocation.x, current.y - mouseDownLocation.y) >= 4 {
            hasStartedDrag = true
            onDragStart?(mouseDownLocation)
        }
        if hasStartedDrag {
            onDrag?(current)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let end = NSEvent.mouseLocation
        if let mouseDownLocation, hypot(end.x - mouseDownLocation.x, end.y - mouseDownLocation.y) < 4 {
            onTap?()
        }
        onDragEnd?()
        mouseDownLocation = nil
        hasStartedDrag = false
    }

    func lookAtMouse(windowFrame: NSRect) {
        let mouse = NSEvent.mouseLocation
        facingRight = mouse.x > windowFrame.midX
    }

    private func blink() {
        guard state != .sleeping else { return }
        isBlinking = true
        needsDisplay = true
        Timer.scheduledTimer(withTimeInterval: 0.14, repeats: false) { [weak self] _ in
            self?.isBlinking = false
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let bob = heldBobOffset()
        let body = NSBezierPath(ovalIn: NSRect(x: 24, y: 18 + bob, width: 100, height: 86))
        NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.36, alpha: 1).setFill()
        body.fill()

        drawEars()
        drawTail()
        drawFace()
        drawFeet()
        drawStateAccessory()
    }

    private func drawEars() {
        let bob = heldBobOffset()
        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 40, y: 92 + bob))
        leftEar.line(to: NSPoint(x: 54, y: 126 + bob))
        leftEar.line(to: NSPoint(x: 72, y: 96 + bob))
        leftEar.close()

        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: 76, y: 96 + bob))
        rightEar.line(to: NSPoint(x: 96, y: 126 + bob))
        rightEar.line(to: NSPoint(x: 110, y: 92 + bob))
        rightEar.close()

        NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.28, alpha: 1).setFill()
        leftEar.fill()
        rightEar.fill()

        NSColor(calibratedRed: 1.0, green: 0.47, blue: 0.42, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 50, y: 96 + bob, width: 13, height: 17)).fill()
        NSBezierPath(ovalIn: NSRect(x: 87, y: 96 + bob, width: 13, height: 17)).fill()
    }

    private func drawTail() {
        let bob = heldBobOffset()
        let tailRect = facingRight ? NSRect(x: 110, y: 44 + bob, width: 30, height: 26) : NSRect(x: 6, y: 44 + bob, width: 30, height: 26)
        let tail = NSBezierPath(ovalIn: tailRect)
        NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.28, alpha: 1).setStroke()
        tail.lineWidth = 8
        tail.stroke()
    }

    private func drawFace() {
        let bob = heldBobOffset()
        let eyeY: CGFloat = (state == .sleeping ? 62 : 68) + bob
        let leftEye = facingRight ? NSPoint(x: 62, y: eyeY) : NSPoint(x: 54, y: eyeY)
        let rightEye = facingRight ? NSPoint(x: 92, y: eyeY) : NSPoint(x: 84, y: eyeY)

        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        if state == .sleeping {
            drawArcEye(center: leftEye)
            drawArcEye(center: rightEye)
        } else if isBlinking {
            drawClosedEye(center: leftEye)
            drawClosedEye(center: rightEye)
        } else {
            NSBezierPath(ovalIn: NSRect(x: leftEye.x - 4, y: leftEye.y - 4, width: 8, height: 8)).fill()
            NSBezierPath(ovalIn: NSRect(x: rightEye.x - 4, y: rightEye.y - 4, width: 8, height: 8)).fill()
        }

        let nose = NSBezierPath(ovalIn: NSRect(x: 72, y: 54 + bob, width: 8, height: 6))
        NSColor(calibratedRed: 0.35, green: 0.18, blue: 0.12, alpha: 1).setFill()
        nose.fill()

        let mouthY: CGFloat = state == .jumping || state == .held ? 42 : 47
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 76, y: 53 + bob))
        mouth.curve(
            to: NSPoint(x: 66, y: mouthY + bob),
            controlPoint1: NSPoint(x: 74, y: 47 + bob),
            controlPoint2: NSPoint(x: 69, y: 45 + bob)
        )
        mouth.move(to: NSPoint(x: 76, y: 53 + bob))
        mouth.curve(
            to: NSPoint(x: 86, y: mouthY + bob),
            controlPoint1: NSPoint(x: 78, y: 47 + bob),
            controlPoint2: NSPoint(x: 83, y: 45 + bob)
        )
        NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
        mouth.lineWidth = 2.2
        mouth.stroke()
    }

    private func drawFeet() {
        NSColor(calibratedRed: 0.9, green: 0.47, blue: 0.2, alpha: 1).setFill()
        if state == .held {
            NSBezierPath(ovalIn: NSRect(x: 48, y: 24, width: 18, height: 12)).fill()
            NSBezierPath(ovalIn: NSRect(x: 82, y: 24, width: 18, height: 12)).fill()
        } else {
            NSBezierPath(ovalIn: NSRect(x: 42, y: 14, width: 24, height: 14)).fill()
            NSBezierPath(ovalIn: NSRect(x: 82, y: 14, width: 24, height: 14)).fill()
        }
    }

    private func drawStateAccessory() {
        switch state {
        case .sleeping:
            drawSleepBubble()
        case .jumping, .falling:
            drawSparkles()
        case .held:
            drawHeldMarks()
        case .idle, .walking:
            break
        }
    }

    private func heldBobOffset() -> CGFloat {
        guard state == .held else { return 0 }
        return sin(CGFloat(Date().timeIntervalSinceReferenceDate) * 12) * 2
    }

    private func drawHeldMarks() {
        NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.0, alpha: 1).setStroke()
        for point in [NSPoint(x: 34, y: 112), NSPoint(x: 114, y: 110)] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: point.x - 5, y: point.y - 3))
            path.curve(
                to: NSPoint(x: point.x + 5, y: point.y - 3),
                controlPoint1: NSPoint(x: point.x - 2, y: point.y + 4),
                controlPoint2: NSPoint(x: point.x + 2, y: point.y + 4)
            )
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawSleepBubble() {
        NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: NSRect(x: 104, y: 96, width: 16, height: 16)).fill()
        NSBezierPath(ovalIn: NSRect(x: 120, y: 112, width: 22, height: 22)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
            .paragraphStyle: paragraph
        ]
        "Z".draw(in: NSRect(x: 121, y: 113, width: 20, height: 18), withAttributes: attrs)
    }

    private func drawSparkles() {
        NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.0, alpha: 1).setStroke()
        for point in [NSPoint(x: 20, y: 92), NSPoint(x: 124, y: 98), NSPoint(x: 116, y: 26)] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: point.x - 5, y: point.y))
            path.line(to: NSPoint(x: point.x + 5, y: point.y))
            path.move(to: NSPoint(x: point.x, y: point.y - 5))
            path.line(to: NSPoint(x: point.x, y: point.y + 5))
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawClosedEye(center: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x - 5, y: center.y))
        path.line(to: NSPoint(x: center.x + 5, y: center.y))
        path.lineWidth = 2
        path.stroke()
    }

    private func drawArcEye(center: NSPoint) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: 5,
            startAngle: 200,
            endAngle: 340,
            clockwise: false
        )
        path.lineWidth = 2
        path.stroke()
    }
}
