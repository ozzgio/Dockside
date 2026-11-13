import AppKit
import VideoToolbox

@main enum EncoderCheck {
    @MainActor static func main() throws {
        let context = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 360, width: 1280, height: 360))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1280, height: 360))
        let image = context.makeImage()!
        let sourceData = image.dataProvider!.data!
        let pixels = CFDataGetBytePtr(sourceData)!
        print("Source top RGB: \(Array(UnsafeBufferPointer(start: pixels, count: 3))); bottom RGB: \(Array(UnsafeBufferPointer(start: pixels + 719 * image.bytesPerRow, count: 3)))")
        var completed = false, failure: Error?
        let encoder = try DashboardEncoder(width: 1280, height: 720) { result in
            DispatchQueue.main.async {
                do { try result.get().write(to: URL(fileURLWithPath: "build/native-encoder-check.h264")) }
                catch { failure = error }
                completed = true
            }
        }
        withExtendedLifetime(sourceData) { }
        try encoder.encode(image)
        let deadline = Date().addingTimeInterval(10)
        while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        encoder.stop()
        if let failure { throw failure }
        precondition(completed, "Encoder timed out")
        print("Native VideoToolbox encoder check passed.")
    }
}
