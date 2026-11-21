import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: alpha)
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func rounded(_ context: CGContext, _ frame: CGRect, radius: CGFloat, fill: UInt32) {
    context.setFillColor(color(fill))
    context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

private func line(_ context: CGContext, _ points: [CGPoint], width: CGFloat, fill: UInt32) {
    guard let start = points.first else { return }
    context.setStrokeColor(color(fill))
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: start)
    for p in points.dropFirst() { context.addLine(to: p) }
    context.strokePath()
}

private func tile(_ context: CGContext, canvas: Bool) {
    let rect = CGRect(x: 78, y: 78, width: 868, height: 868)
    let path = CGPath(roundedRect: rect, cornerWidth: 203, cornerHeight: 203, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -11), blur: 27, color: color(0x261A45, alpha: 0.24))
    context.setFillColor(color(canvas ? 0x4B366E : 0x704BA0))
    context.addPath(path)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = canvas ? [color(0x785BAE), color(0x4A336D)] : [color(0xA081D3), color(0x68419C)]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: point(170, 890), end: point(870, 145), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.2))
    context.setLineWidth(4)
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

private func flower(_ context: CGContext) {
    let center = point(491, 533)
    for petal in 0..<6 {
        let angle = CGFloat(petal) * .pi / 3 + .pi / 6
        let x = center.x + 151 * cos(angle)
        let y = center.y + 151 * sin(angle)
        context.setFillColor(color(petal == 0 || petal == 1 ? 0xE6D5FC : 0xF7EBFF))
        context.fillEllipse(in: CGRect(x: x - 69, y: y - 69, width: 138, height: 138))
    }
    context.setFillColor(color(0xF7EBFF))
    context.fillEllipse(in: CGRect(x: center.x - 65, y: center.y - 65, width: 130, height: 130))
    context.setFillColor(color(0x513478))
    context.fillEllipse(in: CGRect(x: 596, y: 279, width: 192, height: 192))
    context.setFillColor(color(0xC5E9D8))
    context.fillEllipse(in: CGRect(x: 607, y: 290, width: 170, height: 170))
    line(context, [point(651, 376), point(681, 347), point(732, 406)], width: 22, fill: 0x365A53)
}

private func diagram(_ context: CGContext) {
    line(context, [point(391, 610), point(391, 495), point(647, 495), point(647, 419)], width: 22, fill: 0xE7D7F6)
    line(context, [point(391, 495), point(325, 495), point(325, 403)], width: 22, fill: 0xE7D7F6)
    rounded(context, CGRect(x: 274, y: 591, width: 231, height: 151), radius: 46, fill: 0xE6D4FA)
    rounded(context, CGRect(x: 226, y: 266, width: 198, height: 155), radius: 43, fill: 0xF5C1D4)
    rounded(context, CGRect(x: 540, y: 268, width: 221, height: 169), radius: 48, fill: 0xBFE6D4)
    line(context, [point(328, 667), point(450, 667)], width: 17, fill: 0x775698)
    line(context, [point(277, 344), point(373, 344)], width: 17, fill: 0x9B546E)
    line(context, [point(598, 352), point(704, 352)], width: 17, fill: 0x467666)
}

private func render(canvas: Bool, size: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    tile(context, canvas: canvas)
    if canvas { diagram(context) } else { flower(context) }
    guard let image = context.makeImage(),
          let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(output, image, nil)
    if !CGImageDestinationFinalize(output) { throw CocoaError(.fileWriteUnknown) }
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for (name, canvas) in [("Sade", false), ("SadeTuval", true)] {
    let iconset = destination.appendingPathComponent("\(name).iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        try render(canvas: canvas, size: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        try render(canvas: canvas, size: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
