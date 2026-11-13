import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let white = NSColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1)
let cobalt = NSColor(srgbRed: 0.22, green: 0.16, blue: 0.46, alpha: 1)
let yellow = NSColor(srgbRed: 1, green: 0.60, blue: 0.33, alpha: 1)
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>Dockside — clock and controls on a little desk display</title>
<rect x="64" y="64" width="896" height="896" rx="202" fill="#382975"/>
<rect x="224" y="244" width="576" height="414" rx="66" fill="#F7FAFF"/>
<rect x="270" y="290" width="484" height="322" rx="24" fill="#382975"/>
<circle cx="435" cy="451" r="108" fill="#F7FAFF"/><path d="M435 382 V451 L490 482" fill="none" stroke="#382975" stroke-width="34" stroke-linecap="round" stroke-linejoin="round"/><rect x="600" y="370" width="64" height="38" rx="19" fill="#FF9954"/><rect x="600" y="432" width="92" height="38" rx="19" fill="#F7FAFF"/><rect x="600" y="494" width="64" height="38" rx="19" fill="#F7FAFF"/>
<path d="M296 706 H728 L790 774 Q800 794 774 794 H250 Q224 794 234 774 Z" fill="#FF9954"/>
<rect x="448" y="744" width="128" height="16" rx="8" fill="#382975"/>
</svg>
"""
try svg.write(to: folder.appendingPathComponent("Dockside.svg"), atomically: true, encoding: .utf8)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.cgContext.translateBy(x: 0, y: 1024)
    context.cgContext.scaleBy(x: 1, y: -1)
    cobalt.setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202).fill()
    white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 224, y: 244, width: 576, height: 414), xRadius: 66, yRadius: 66).fill()
    cobalt.setFill()
    NSBezierPath(roundedRect: NSRect(x: 270, y: 290, width: 484, height: 322), xRadius: 24, yRadius: 24).fill()
    white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 327, y: 343, width: 216, height: 216)).fill()
    cobalt.setStroke()
    let hands = NSBezierPath()
    hands.lineWidth = 34
    hands.lineCapStyle = .round
    hands.lineJoinStyle = .round
    hands.move(to: NSPoint(x: 435, y: 382))
    hands.line(to: NSPoint(x: 435, y: 451))
    hands.line(to: NSPoint(x: 490, y: 482))
    hands.stroke()
    for (y, width) in [(370, 64), (432, 92), (494, 64)] {
        (y == 370 ? yellow : white).setFill()
        NSBezierPath(roundedRect: NSRect(x: 600, y: y, width: width, height: 38), xRadius: 19, yRadius: 19).fill()
    }
    let dock = NSBezierPath()
    dock.move(to: NSPoint(x: 296, y: 706))
    dock.line(to: NSPoint(x: 728, y: 706))
    dock.line(to: NSPoint(x: 790, y: 774))
    dock.curve(to: NSPoint(x: 774, y: 794), controlPoint1: NSPoint(x: 800, y: 790), controlPoint2: NSPoint(x: 796, y: 794))
    dock.line(to: NSPoint(x: 250, y: 794))
    dock.curve(to: NSPoint(x: 234, y: 774), controlPoint1: NSPoint(x: 228, y: 794), controlPoint2: NSPoint(x: 224, y: 790))
    dock.close()
    yellow.setFill(); dock.fill()
    cobalt.setFill()
    NSBezierPath(roundedRect: NSRect(x: 448, y: 744, width: 128, height: 16), xRadius: 8, yRadius: 8).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try data.write(to: folder.appendingPathComponent("icon-\(size).png"))
}
print("Created original Dockside SVG and seven PNG sizes.")
