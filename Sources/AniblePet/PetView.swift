import AppKit

final class PetView: NSView {
    private let baseSize = NSSize(width: 148, height: 132)
    var onTap: (() -> Void)?
    var onDragStart: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onOpenManager: (() -> Void)?
    var portraitSet: PetPortraitSet? {
        didSet { needsDisplay = true }
    }
    var state: PetState = .idle {
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

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开宠物管理", action: #selector(openManagerFromMenu), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openManagerFromMenu() {
        onOpenManager?()
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

        if drawUploadedPortrait() {
            drawStateAccessory()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scaleX(by: bounds.width / baseSize.width, yBy: bounds.height / baseSize.height)
        transform.concat()

        let bob = heldBobOffset()
        let body = NSBezierPath(ovalIn: NSRect(x: 24, y: 18 + bob, width: 100, height: 86))
        NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.36, alpha: 1).setFill()
        body.fill()

        drawEars()
        drawTail()
        drawFace()
        drawFeet()
        drawStateAccessory()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawUploadedPortrait() -> Bool {
        guard let image = portraitSet?.image(for: state) else { return false }
        NSGraphicsContext.saveGraphicsState()
        if !facingRight {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
        }
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return true
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
