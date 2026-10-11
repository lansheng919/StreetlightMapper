import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draws the 1024x1024 app icon (opaque, no transparency, as App Store icons must be).
// Run: swift tools/make_icon.swift StreetlightMapper/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

let size = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r / 255, g / 255, b / 255, a])!
}

let S = CGFloat(size)

// Background: deep night-blue vertical gradient
let bg = CGGradient(colorsSpace: cs,
                    colors: [color(10, 20, 48), color(24, 52, 104)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// Warm glow under the lamp
let lampCenter = CGPoint(x: 600, y: 700)
let glow = CGGradient(colorsSpace: cs,
                      colors: [color(255, 214, 102, 0.85), color(255, 214, 102, 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: lampCenter, startRadius: 0,
                       endCenter: lampCenter, endRadius: 430, options: [])

// Light cone
ctx.saveGState()
ctx.beginPath()
ctx.move(to: CGPoint(x: 560, y: 660))
ctx.addLine(to: CGPoint(x: 640, y: 660))
ctx.addLine(to: CGPoint(x: 800, y: 250))
ctx.addLine(to: CGPoint(x: 400, y: 250))
ctx.closePath()
ctx.clip()
let cone = CGGradient(colorsSpace: cs,
                      colors: [color(255, 224, 130, 0.55), color(255, 224, 130, 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(cone, start: CGPoint(x: 600, y: 660), end: CGPoint(x: 600, y: 250), options: [])
ctx.restoreGState()

// Ground
ctx.setFillColor(color(8, 14, 32))
ctx.fill(CGRect(x: 0, y: 0, width: S, height: 170))

// Pole
ctx.setFillColor(color(206, 214, 228))
ctx.fill(CGRect(x: 262, y: 150, width: 46, height: 620))
// Pole base
ctx.setFillColor(color(150, 160, 180))
ctx.fill(CGRect(x: 238, y: 150, width: 94, height: 34))

// Arm (curves from the pole top to the lamp)
ctx.setStrokeColor(color(206, 214, 228))
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: CGPoint(x: 285, y: 760))
ctx.addCurve(to: CGPoint(x: 600, y: 770),
             control1: CGPoint(x: 285, y: 860),
             control2: CGPoint(x: 480, y: 880))
ctx.strokePath()

// Lamp head
let head = CGRect(x: 500, y: 700, width: 200, height: 84)
ctx.setFillColor(color(120, 132, 156))
ctx.addPath(CGPath(roundedRect: head, cornerWidth: 40, cornerHeight: 40, transform: nil))
ctx.fillPath()
// Lit lens
ctx.setFillColor(color(255, 232, 150))
ctx.addPath(CGPath(roundedRect: CGRect(x: 520, y: 690, width: 160, height: 34),
                   cornerWidth: 17, cornerHeight: 17, transform: nil))
ctx.fillPath()

// Scan brackets (the "capture" idea) framing the lamp area
ctx.setStrokeColor(color(80, 220, 140))
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let frame = CGRect(x: 150, y: 150, width: 724, height: 724)
let arm: CGFloat = 130
let corners: [(CGPoint, CGFloat, CGFloat)] = [
    (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),   // top-left
    (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),  // top-right
    (CGPoint(x: frame.minX, y: frame.minY), 1, 1),    // bottom-left
    (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),   // bottom-right
]
for (p, dx, dy) in corners {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: p.x + dx * arm, y: p.y))
    ctx.addLine(to: p)
    ctx.addLine(to: CGPoint(x: p.x, y: p.y + dy * arm))
    ctx.strokePath()
}

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)
else { fatalError("destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("wrote \(outPath)")
