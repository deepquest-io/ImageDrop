// ImageDrop by deepquest | https://deepquest.code511.com/blog
// Draws the 1024×1024 app icon with CoreGraphics. Used by build.sh when
// Resources/AppIcon.icns is missing (e.g. in a fresh git clone).
//   swift tools/make-icon.swift out.png
import Foundation
import CoreGraphics
import ImageIO

let size = 1024
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
// Layout below uses top-left coordinates; flip converts to CoreGraphics (bottom-left).
func flip(_ y: CGFloat) -> CGFloat { CGFloat(size) - y }
func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
    CGRect(x: x0, y: flip(y1), width: x1 - x0, height: y1 - y0)
}
func rotateAroundCenter(_ degrees: CGFloat) {
    let c = CGFloat(size) / 2
    ctx.translateBy(x: c, y: c)
    ctx.rotate(by: degrees * .pi / 180)
    ctx.translateBy(x: -c, y: -c)
}
func fillRounded(_ rect: CGRect, radius: CGFloat, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}
func fillPolygon(_ points: [(CGFloat, CGFloat)], _ color: CGColor) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: points[0].0, y: flip(points[0].1)))
    for p in points.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: flip(p.1))) }
    ctx.closePath()
    ctx.setFillColor(color)
    ctx.fillPath()
}

// Background: rounded square, purple (top) → blue (bottom)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: box(100, 100, 924, 924), cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.clip()
let gradient = CGGradient(colorsSpace: cs, colors: [rgb(0, 170, 255), rgb(88, 86, 214)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
ctx.restoreGState()

// Back photo card
ctx.saveGState()
rotateAroundCenter(12)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: rgb(0, 0, 0, 0.30))
fillRounded(box(290, 240, 690, 610), radius: 40, rgb(255, 255, 255, 0.55))
ctx.restoreGState()

// Front photo card with a landscape
ctx.saveGState()
rotateAroundCenter(-6)
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0, 0, 0, 0.35))
fillRounded(box(330, 300, 730, 670), radius: 40, rgb(255, 255, 255))
ctx.setShadow(offset: .zero, blur: 0, color: nil)
fillRounded(box(360, 330, 700, 600), radius: 22, rgb(225, 238, 255))
fillPolygon([(370, 590), (470, 460), (560, 560), (610, 500), (690, 590)], rgb(52, 199, 89))
ctx.setFillColor(rgb(255, 204, 0))
ctx.fillEllipse(in: box(600, 360, 660, 420))
ctx.restoreGState()

// Drop badge with arrow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0, 0, 0, 0.30))
ctx.setFillColor(rgb(255, 255, 255))
ctx.fillEllipse(in: box(560, 620, 800, 860))
ctx.restoreGState()
fillPolygon([(640, 665), (720, 665), (720, 735), (760, 735), (680, 815), (600, 735), (640, 735)],
            rgb(0, 140, 255))

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
