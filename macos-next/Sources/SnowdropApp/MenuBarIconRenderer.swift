import AppKit
import CoreGraphics

@MainActor
enum MenuBarIconRenderer {
    static func templateImage() -> NSImage {
        let size = CGFloat(18)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            let scale = (size * 0.86) / 330.0
            ctx.translateBy(x: size / 2.0, y: size * 0.50)
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: -256.0, y: -214.0)

            let outerPath = CGMutablePath()
            outerPath.move(to: CGPoint(x: 245, y: 365))
            outerPath.addCurve(to: CGPoint(x: 225, y: 255), control1: CGPoint(x: 245, y: 320), control2: CGPoint(x: 242, y: 285))
            outerPath.addCurve(to: CGPoint(x: 142, y: 120), control1: CGPoint(x: 205, y: 220), control2: CGPoint(x: 138, y: 180))
            outerPath.addCurve(to: CGPoint(x: 192, y: 122), control1: CGPoint(x: 145, y: 94), control2: CGPoint(x: 175, y: 102))
            outerPath.addCurve(to: CGPoint(x: 252, y: 278), control1: CGPoint(x: 218, y: 154), control2: CGPoint(x: 238, y: 230))
            outerPath.addCurve(to: CGPoint(x: 260, y: 278), control1: CGPoint(x: 253, y: 282), control2: CGPoint(x: 259, y: 282))
            outerPath.addCurve(to: CGPoint(x: 320, y: 122), control1: CGPoint(x: 274, y: 230), control2: CGPoint(x: 294, y: 154))
            outerPath.addCurve(to: CGPoint(x: 370, y: 120), control1: CGPoint(x: 337, y: 102), control2: CGPoint(x: 367, y: 94))
            outerPath.addCurve(to: CGPoint(x: 287, y: 255), control1: CGPoint(x: 374, y: 180), control2: CGPoint(x: 307, y: 220))
            outerPath.addCurve(to: CGPoint(x: 267, y: 365), control1: CGPoint(x: 270, y: 285), control2: CGPoint(x: 267, y: 320))
            outerPath.addArc(center: CGPoint(x: 256, y: 365), radius: 11, startAngle: 0, endAngle: .pi, clockwise: false)
            outerPath.closeSubpath()

            let centerPath = CGMutablePath()
            centerPath.move(to: CGPoint(x: 256, y: 52))
            centerPath.addCurve(to: CGPoint(x: 256, y: 282), control1: CGPoint(x: 286, y: 125), control2: CGPoint(x: 288, y: 215))
            centerPath.addCurve(to: CGPoint(x: 256, y: 52), control1: CGPoint(x: 224, y: 215), control2: CGPoint(x: 226, y: 125))
            centerPath.closeSubpath()

            let slitLeft = CGMutablePath()
            slitLeft.move(to: CGPoint(x: 256, y: 64))
            slitLeft.addCurve(to: CGPoint(x: 254, y: 274), control1: CGPoint(x: 224, y: 130), control2: CGPoint(x: 222, y: 215))

            let slitRight = CGMutablePath()
            slitRight.move(to: CGPoint(x: 256, y: 64))
            slitRight.addCurve(to: CGPoint(x: 258, y: 274), control1: CGPoint(x: 288, y: 130), control2: CGPoint(x: 290, y: 215))

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(outerPath)
            ctx.fillPath()

            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(14)
            ctx.setLineCap(.round)
            ctx.addPath(slitLeft)
            ctx.addPath(slitRight)
            ctx.strokePath()
            ctx.restoreGState()

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(centerPath)
            ctx.fillPath()

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
