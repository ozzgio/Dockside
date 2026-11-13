import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
// One shape list feeds both the SVG and the PNGs: a desk display on a dock base with one signal light.
// (x, y, width, height, corner radius, hex colour) in a 1024 canvas, y down.
let shapes: [(Double, Double, Double, Double, Double, String)] = [
    (64, 64, 896, 896, 202, "101B2A"),   // tile
    (160, 236, 704, 420, 60, "F2F7FC"),  // bezel
    (196, 272, 632, 348, 30, "8CCDE2"),  // screen
    (256, 344, 300, 92, 46, "101B2A"),   // clock line
    (256, 484, 440, 44, 22, "101B2A"),   // detail line
    (256, 548, 300, 28, 14, "2C4A66"),   // quiet line
    (456, 656, 112, 64, 0, "A6B8C9"),    // neck
    (268, 716, 488, 76, 38, "F2F7FC"),   // dock base
    (664, 736, 36, 36, 18, "F4BC7A"),    // signal light
]
func color(_ hex: String) -> NSColor {
    let v = Int(hex, radix: 16)!
    return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let body = shapes.map { "<rect x=\"\(Int($0.0))\" y=\"\(Int($0.1))\" width=\"\(Int($0.2))\" height=\"\(Int($0.3))\" rx=\"\(Int($0.4))\" fill=\"#\($0.5)\"/>" }
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n<title>Dockside — a personal desk display</title>\n" + body.joined(separator: "\n") + "\n</svg>\n"
try svg.write(to: folder.appendingPathComponent("Dockside.svg"), atomically: true, encoding: .utf8)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.cgContext.translateBy(x: 0, y: 1024); context.cgContext.scaleBy(x: 1, y: -1)
    for (x, y, w, h, r, hex) in shapes {
        color(hex).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try data.write(to: folder.appendingPathComponent("icon-\(size).png"))
}
print("Created Dockside display-mark SVG and seven PNG sizes.")
