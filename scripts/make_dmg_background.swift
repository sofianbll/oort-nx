import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 9 else { fatalError("Expected: directory width height iconSize appX appY folderX folderY cloud") }
let output = URL(fileURLWithPath: arguments[0], isDirectory: true)
let sizes = arguments[1..<8].compactMap { Double($0) }
guard sizes.count == 7 else { fatalError("Expected numeric geometry") }
let cloud = try JSONDecoder().decode([[Double]].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[8])))
let (width, height, icon) = (sizes[0], sizes[1], sizes[2])
let app = CGPoint(x: sizes[3], y: sizes[4])
let folder = CGPoint(x: sizes[5], y: sizes[6])
let midpoint = CGPoint(x: (app.x + folder.x) / 2, y: app.y)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat(hex >> 16) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha,
    ])!
}

func draw(_ scale: Int) {
    let context = CGContext(data: nil, width: Int(width) * scale, height: Int(height) * scale,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    func dot(_ x: Double, _ y: Double, _ r: Double, _ tint: CGColor) {
        context.setFillColor(tint)
        context.fillEllipse(in: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r))
    }
    context.setFillColor(color(0x05070B))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let radius = width * 0.435
    for point in cloud {
        let (x, y, d) = (point[0], point[1], point[2])
        let (px, py) = (midpoint.x + radius*x, midpoint.y + radius*y)
        let nearest = min(abs(px-app.x), abs(px-folder.x))
        let station = hypot(nearest / 90, (py-app.y-19) / 75)
        let quiet = min(1, max(0.14, station - 0.16))
        let edge = 0.55 + 0.45 * max(0, 1 - abs(py-height/2) / (height/2))
        let crossing = min(1, max(0, (px-app.x)/44), max(0, (folder.x-px)/44))
        let axial = 1 - 0.54 * crossing * max(0, 1 - abs(py-midpoint.y)/27)
        dot(px, py, 0.45 + 1.27 * sqrt(d), color(x > 0 ? 0xAFC3E6 : 0xD6DEEA,
            (0.31 + 0.31*d) * quiet * edge * axial))
    }

    let y = midpoint.y
    let start = app.x + icon/2 + 14
    let end = folder.x - icon/2 - 20
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(color(0xD6DEEA, 0.90))
    context.setLineWidth(1.65)
    context.setLineDash(phase: 0, lengths: [1.5, 5.5])
    context.move(to: CGPoint(x: start, y: y))
    context.addQuadCurve(to: midpoint, control: CGPoint(x: (start+midpoint.x)/2, y: y-17))
    context.addQuadCurve(to: CGPoint(x: end, y: y), control: CGPoint(x: (end+midpoint.x)/2, y: y+17))
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
    context.move(to: CGPoint(x: end-4, y: y-4))
    context.addLine(to: CGPoint(x: end+3, y: y))
    context.addLine(to: CGPoint(x: end-4, y: y+4))
    context.strokePath()
    let corona = CGGradient(colorsSpace: space, colors: [
        color(0x05070B), color(0xF4CE8E, 0.20), color(0xF4CE8E, 0),
    ] as CFArray, locations: [0.23, 0.33, 1])!
    context.drawRadialGradient(corona, startCenter: midpoint, startRadius: 0,
                               endCenter: midpoint, endRadius: 23, options: [])
    dot(midpoint.x, y, 7, color(0xF4CE8E))

    // Finder uses dark labels with a picture background, even in dark appearance.
    for station in [app, folder] {
        let plate = CGRect(x: station.x-66, y: station.y+icon/2+3, width: 132, height: 29)
        let path = CGPath(roundedRect: plate, cornerWidth: 7, cornerHeight: 7, transform: nil)
        context.addPath(path)
        context.setFillColor(color(0xD6DEEA))
        context.fillPath()
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let caption = NSAttributedString(string: "Drag to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(cgColor: color(0xD6DEEA))!,
    ])
    caption.draw(at: CGPoint(x: midpoint.x-caption.size().width/2, y: height*0.78))
    NSGraphicsContext.restoreGraphicsState()

    let target = output.appendingPathComponent(scale == 1 ? "background.tiff" : "background@2x.tiff")
    let writer = CGImageDestinationCreateWithURL(target as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
    let dpi = 72 * scale
    CGImageDestinationAddImage(writer, context.makeImage()!, [
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFXResolution: dpi, kCGImagePropertyTIFFYResolution: dpi,
            kCGImagePropertyTIFFResolutionUnit: 2,
        ],
    ] as CFDictionary)
    guard CGImageDestinationFinalize(writer) else { fatalError("Could not write \(target.path)") }
}

draw(1)
draw(2)
