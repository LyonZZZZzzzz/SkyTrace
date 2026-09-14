import AppKit
import CoreGraphics

let width = 1024
let height = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.012, green: 0.028, blue: 0.075, alpha: 1),
        CGColor(red: 0.018, green: 0.16, blue: 0.27, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])

let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.18, green: 0.78, blue: 1, alpha: 0.45),
        CGColor(red: 0.18, green: 0.78, blue: 1, alpha: 0)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 680, y: 650), startRadius: 0, endCenter: CGPoint(x: 680, y: 650), endRadius: 360, options: [])

let starPoints: [(CGFloat, CGFloat, CGFloat)] = [
    (180, 760, 5), (296, 690, 2), (392, 820, 4), (520, 760, 3), (610, 880, 5),
    (810, 790, 3), (865, 650, 6), (750, 570, 2), (560, 610, 3), (420, 550, 5),
    (260, 470, 3), (160, 360, 4), (340, 300, 2), (710, 380, 3), (840, 310, 5)
]
for (x, y, radius) in starPoints {
    context.setFillColor(CGColor(red: 0.82, green: 0.94, blue: 1, alpha: 0.9))
    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
}

context.setStrokeColor(CGColor(red: 0.28, green: 0.84, blue: 1, alpha: 0.75))
context.setLineWidth(18)
context.setLineCap(.round)
context.addArc(center: CGPoint(x: 512, y: 512), radius: 320, startAngle: -0.15 * .pi, endAngle: 0.82 * .pi, clockwise: false)
context.strokePath()

let path = CGMutablePath()
let center = CGPoint(x: 512, y: 512)
let outer = 150.0
let inner = 58.0
for index in 0..<10 {
    let radius = index.isMultiple(of: 2) ? outer : inner
    let angle = Double(index) * .pi / 5 + .pi / 2
    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
}
path.closeSubpath()
context.addPath(path)
context.setFillColor(CGColor(red: 1, green: 0.82, blue: 0.30, alpha: 1))
context.fillPath()

let image = context.makeImage()!
let representation = NSBitmapImageRep(cgImage: image)
let data = representation.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
