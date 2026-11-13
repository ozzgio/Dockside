// Actions Micro native USB backend. MIT protocol attribution: research/native/NOTICE.md.
import AppKit
import Foundation
import IOKit.hid
import VideoToolbox
import SwiftUI

struct ProtocolError: Error, CustomStringConvertible { let description: String }
func word(_ bytes: [UInt8], _ offset: Int) -> Int {
    bytes[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
}
func reports(id: UInt8, payload: Data, width: Int = 0, height: Int = 0) throws -> [Data] {
    guard [1,2].contains(id), payload.count <= 8_388_608, (0...8192).contains(width), (0...8192).contains(height) else {
        throw ProtocolError(description: "Invalid report bounds")
    }
    // macOS advertises 12-KiB video reports; short 4-KiB reports visibly corrupt this panel.
    let reportSize = id == 2 ? 12288 : 4096
    let payloadSize = reportSize - 16
    var output: [Data] = []
    for offset in stride(from: 0, to: max(1, payload.count), by: payloadSize) {
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = id
        func put(_ value: Int, at: Int) {
            for index in 0..<4 { report[at+index] = UInt8(truncatingIfNeeded: value >> (24-index*8)) }
        }
        if offset == 0 {
            put(payload.count, at: 1)
            if id == 2 { put(width, at: 8); put(height, at: 12) }
        }
        let count = min(payloadSize, payload.count - offset)
        if count > 0 { report.replaceSubrange(16..<16+count, with: payload[offset..<offset+count]) }
        output.append(Data(report))
    }
    return output
}

// Control state stays on the main run loop; only video writes use the drained serial queue.
final class HIDDisplay: @unchecked Sendable {
    let manager: IOHIDManager
    let control: IOHIDDevice
    let video: IOHIDDevice
    private var buffer: UnsafeMutablePointer<UInt8>
    private var pending = Data()
    private var needed = 0
    private(set) var requestID = 0
    var session: String?
    var width = 1280
    var height = 720
    var acknowledged = Set<Int>()
    var lastHeartbeat = Date()
    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 7649, kIOHIDProductIDKey: 61953] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, 0)
            throw ProtocolError(description: "HID open failed: \(String(format: "0x%08x", result))")
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, devices.count == 2 else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, 0)
            throw ProtocolError(description: "Expected exactly one dock with two HID interfaces")
        }
        let sorted = devices.sorted {
            (IOHIDDeviceGetProperty($0, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0)
            < (IOHIDDeviceGetProperty($1, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0)
        }
        control = sorted[0]; video = sorted[1]
        let small = IOHIDDeviceGetProperty(control, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let big = IOHIDDeviceGetProperty(video, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        guard small == 4096, big == 12288 else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, 0)
            throw ProtocolError(description: "Unsupported HID interfaces")
        }
        buffer = .allocate(capacity: 4096)
        IOHIDDeviceRegisterInputReportCallback(control, buffer, 4096, { context, status, _, _, id, data, count in
            guard status == kIOReturnSuccess, let context, count >= 16 else { return }
            let display = Unmanaged<HIDDisplay>.fromOpaque(context).takeUnretainedValue()
            display.receive(Array(UnsafeBufferPointer(start: data, count: count)), reportID: id)
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, 0)
        buffer.deallocate()
    }
    private func receive(_ bytes: [UInt8], reportID: UInt32) {
        guard reportID == 1, bytes[0] == 1 else { return }
        let length = word(bytes, 1)
        if length > 0 {
            guard length <= 1_048_576 else { pending = Data(); needed = 0; return }
            pending = Data(); needed = length
        }
        guard needed > 0 else { return }
        let take = min(needed, bytes.count - 16)
        pending.append(contentsOf: bytes[16..<16+take]); needed -= take
        guard needed == 0, let message = try? JSONSerialization.jsonObject(with: pending) as? [String: Any] else { return }
        pending = Data()
        if let method = message["method"] as? String {
            let params = message["params"] as? [String: Any] ?? [:]
            if method == "heartbeat" { session = params["session-id"] as? String; lastHeartbeat = Date() }

        }
        if message["result"] != nil, let id = message["id"] as? Int { acknowledged.insert(id) }
    }
    func send(_ method: String, params: [String: Any]? = nil, request: Bool = false) throws {
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { object["params"] = params }
        if request { requestID += 1; object["id"] = requestID }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        for report in try reports(id: 1, payload: payload) { try write(report, to: control, id: 1) }
    }
    private func write(_ report: Data, to device: IOHIDDevice, id: CFIndex) throws {
        let result = report.withUnsafeBytes { raw in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, id, raw.bindMemory(to: UInt8.self).baseAddress!, report.count)
        }
        guard result == kIOReturnSuccess else { throw ProtocolError(description: "HID write failed: \(String(format: "0x%08x", result))") }
    }
    func frame(_ data: Data) throws {
        for report in try reports(id: 2, payload: data, width: width, height: height) { try write(report, to: video, id: 2) }
    }
}


// VideoToolbox emits length-prefixed AVCC; the dock accepts Annex-B start codes.
func annexB(_ avcc: Data) throws -> Data {
    let bytes = [UInt8](avcc)
    var offset = 0, output = Data()
    guard !bytes.isEmpty, bytes.count <= 8_388_608 else { throw ProtocolError(description: "Invalid encoded frame size") }
    while offset < bytes.count {
        guard bytes.count - offset >= 4 else { throw ProtocolError(description: "Truncated NAL header") }
        let length = word(bytes, offset); offset += 4
        guard length > 0, length <= bytes.count - offset else { throw ProtocolError(description: "Invalid NAL length") }
        output.append(contentsOf: [0,0,0,1]); output.append(contentsOf: bytes[offset..<offset+length]); offset += length
    }
    return output
}

final class DashboardEncoder {
    private var session: VTCompressionSession?
    private let output: (Result<Data, Error>) -> Void
    private var index: Int64 = 0
    init(width: Int, height: Int, output: @escaping (Result<Data, Error>) -> Void) throws {
        self.output = output
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil, imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height] as CFDictionary,
            compressedDataAllocator: nil, outputCallback: { context, _, status, _, sample in
                guard let context else { return }
                let encoder = Unmanaged<DashboardEncoder>.fromOpaque(context).takeUnretainedValue()
                do {
                    guard status == noErr, let sample, let block = CMSampleBufferGetDataBuffer(sample),
                          let format = CMSampleBufferGetFormatDescription(sample) else { throw ProtocolError(description: "H.264 encoding failed (\(status))") }
                    var encoded = Data()
                    for index in 0..<2 {
                        var pointer: UnsafePointer<UInt8>?, size = 0
                        var headerLength: Int32 = 0
                        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index,
                            parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: &headerLength) == noErr, headerLength == 4,
                            let pointer, size > 0, size < 65536 else { throw ProtocolError(description: "Missing H.264 parameter sets") }
                        encoded.append(contentsOf: [0,0,0,1]); encoded.append(pointer, count: size)
                    }
                    let length = CMBlockBufferGetDataLength(block)
                    guard length > 0, length <= 8_388_608 else { throw ProtocolError(description: "Encoded frame too large") }
                    var data = Data(count: length)
                    let copied = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
                    guard copied == noErr else { throw ProtocolError(description: "Could not copy video frame") }
                    encoded.append(try annexB(data)); encoder.output(.success(encoded))
                } catch { encoder.output(.failure(error)) }
            }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        guard status == noErr, let session else { throw ProtocolError(description: "H.264 encoder unavailable (\(status))") }
        for (key, value) in [(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue as CFTypeRef),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse as CFTypeRef),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel as CFTypeRef),
            (kVTCompressionPropertyKey_ExpectedFrameRate, 2 as CFNumber),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, 1 as CFNumber),
            (kVTCompressionPropertyKey_AverageBitRate, 4_000_000 as CFNumber)] {
            guard VTSessionSetProperty(session, key: key, value: value) == noErr else {
                VTCompressionSessionInvalidate(session); self.session = nil
                throw ProtocolError(description: "Could not configure native video encoder")
            }
        }
        guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else {
            VTCompressionSessionInvalidate(session); self.session = nil
            throw ProtocolError(description: "Could not prepare video encoder")
        }
    }
    func encode(_ image: CGImage) throws {
        guard let session, let pool = VTCompressionSessionGetPixelBufferPool(session) else { throw ProtocolError(description: "Encoder stopped") }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw ProtocolError(description: "Video buffer unavailable") }
        guard image.width == CVPixelBufferGetWidth(buffer), image.height == CVPixelBufferGetHeight(buffer),
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw ProtocolError(description: "Video buffer geometry or lock failed") }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw ProtocolError(description: "Video drawing context unavailable") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: CMTime(value: index, timescale: 2),
            duration: CMTime(value: 1, timescale: 2), frameProperties: [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary,
            sourceFrameRefcon: nil, infoFlagsOut: nil)
        index += 1
        guard status == noErr else { throw ProtocolError(description: "Could not encode dashboard (\(status))") }
    }
    func stop() {
        if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(session) }
        session = nil
    }
    deinit { stop() }
}

@MainActor final class NativeDisplay: ObservableObject {
    @Published private(set) var status = "Native USB is off."
    @Published private(set) var active = false
    @Published private(set) var starting = false
    private var transport: HIDDisplay?
    private var virtualDisplay: NSObject?
    private var encoder: DashboardEncoder?
    private var timer: Timer?
    private var cursorTimer: Timer?
    private var heartbeatTimer: Timer?
    private var startTask: Task<Void, Never>?
    private let videoQueue = DispatchQueue(label: "Dockside.usb.video", qos: .userInitiated)
    private var busy = false
    private var generation = UUID()
    private var projectionRequest: Int?
    private var projectionStarted = Date.distantPast
    private var cursorVisible = false
    private var lastCursor: CGPoint?
    var render: ((Int, Int) -> CGImage?)?
    var didConnect: (() -> Void)?
    var didStop: (() -> Void)?
    var displayID: CGDirectDisplayID { virtualDisplay.map { DSVirtualDisplayID($0) } ?? 0 }
    private var vendorRunning: [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: "com.winnerwave.USBDisplay") }
    func start() {
        guard !active, !starting else { return }
        starting = true; status = "Connecting directly to the dock…"
        generation = UUID()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                for app in vendorRunning { guard app.terminate() else { throw ProtocolError(description: "Quit USB Display, then retry native USB.") } }
                for _ in 0..<30 where !vendorRunning.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
                guard vendorRunning.isEmpty else { throw ProtocolError(description: "USB Display is still running; native USB was not started.") }
                let device = try HIDDisplay(); transport = device
                for _ in 0..<10 where device.session == nil { try await Task.sleep(for: .milliseconds(100)) }
                // A freshly attached dock can wait for host initiation. The reference's cold-start ID is verified on this dock.
                let session = device.session ?? "100000"
                device.session = session
                try device.send("heartbeat", params: ["session-id": session])
                heartbeatTimer = commonTimer(1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let transport = self.transport, let session = transport.session else { return }
                        do { try transport.send("heartbeat", params: ["session-id": session]) }
                        catch { self.stop(message: "Native USB: \(error)") }
                    }
                }
                // Compatibility fields are from the working MIT reference handshake, not host identification.
                try device.send("app-launched", params: ["platform": "windows", "platform-machine-name": "DOCKSIDE", "product-type": "QuattroTx CT10", "res-width": 1280, "res-height": 720], request: true)
                let request = device.requestID
                for _ in 0..<30 where !device.acknowledged.contains(request) { try await Task.sleep(for: .milliseconds(100)) }
                guard device.acknowledged.contains(request) else { throw ProtocolError(description: "Dock did not acknowledge app-launched") }
                guard let display = DSCreateVirtualDisplay(UInt32(device.width), UInt32(device.height)) else { throw ProtocolError(description: "Native virtual displays are unavailable on this macOS version.") }
                virtualDisplay = display
                for _ in 0..<30 where CGDisplayIsOnline(displayID) != 1 || !NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == self.displayID }) { try await Task.sleep(for: .milliseconds(100)) }
                guard displayID != 0, CGDisplayIsOnline(displayID) == 1, NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == self.displayID }) else { throw ProtocolError(description: "macOS did not activate the native display (id \(displayID), online \(CGDisplayIsOnline(displayID)), screens \(NSScreen.screens.count))") }
                moveBesideDesktop(displayID)
                try device.send("app_tx_mouse_icon_change", params: ["cursor_base64_data": panelCursor(visible: false)])
                try device.send("common.data_passthrough", params: ["id": 103, "size": 1, "data": "AQ=="])
                try device.send("notify-projection-started", request: true)
                // The panel acknowledges projection only after its first video frame arrives.
                projectionRequest = device.requestID; projectionStarted = Date()
                let token = generation
                encoder = try DashboardEncoder(width: device.width, height: device.height) { [weak self] result in
                    Task { @MainActor in self?.encoded(result, token: token) }
                }
                starting = false; active = true; status = "Starting native video…"
                didConnect?()
                timer = commonTimer(0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
                cursorTimer = commonTimer(0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.cursor() } }
                tick()
            } catch is CancellationError { }
              catch { stop(message: "Native USB: \(error). Retry, or open USB Display as a fallback.") }
        }
    }
    private func tick() {
        guard active, let transport else { return }
        do {
            if let request = projectionRequest {
                if transport.acknowledged.contains(request) {
                    let connected = "Native USB connected · 1280 × 720 · dashboard only"
                    if status != connected { status = connected }
                }
                else if Date().timeIntervalSince(projectionStarted) > 8 { throw ProtocolError(description: "Dock did not acknowledge the first video frame") }
            }
            guard displayID != 0, CGDisplayIsOnline(displayID) == 1 else { throw ProtocolError(description: "macOS removed the native virtual display") }
            guard vendorRunning.isEmpty else { throw ProtocolError(description: "USB Display restarted; native streaming stopped to avoid a conflict") }
            guard Date().timeIntervalSince(transport.lastHeartbeat) < 10 else { throw ProtocolError(description: "Dock disconnected or stopped responding") }
            guard !busy else { return }
            guard let image = render?(transport.width, transport.height) else { throw ProtocolError(description: "Could not render the dashboard") }
            busy = true
            try encoder?.encode(image)
        } catch { stop(message: "Native USB: \(error). Reconnect and retry.") }
    }
    private func encoded(_ result: Result<Data, Error>, token: UUID) {
        guard token == generation, active, let transport else { return }
        switch result {
        case .failure(let error): stop(message: "Native USB: \(error)")
        case .success(let data):
            videoQueue.async { [weak self] in
                let result = Result { try transport.frame(data) }
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.busy = false
                    if case .failure(let error) = result { self.stop(message: "Native USB: \(error)") }
                }
            }
        }
    }
    private func cursor() {
        guard active, let transport, let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == self.displayID }) else { return }
        let point = NSEvent.mouseLocation
        let inside = screen.frame.contains(point)
        do {
            if inside != cursorVisible {
                try transport.send("app_tx_mouse_icon_change", params: ["cursor_base64_data": panelCursor(visible: inside)])
                cursorVisible = inside
            }
            if inside && point.y < screen.frame.minY + 3 {
                // Dwelling on a screen's bottom edge pulls the Dock there, under the dashboard; keep the pointer off it.
                CGWarpMouseCursorPosition(CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - screen.frame.minY - 4))
                CGAssociateMouseAndMouseCursorPosition(1)
            }
            if inside {
                let location = CGPoint(x: min(1279, max(0, point.x - screen.frame.minX)), y: min(719, max(0, screen.frame.maxY - point.y)))
                if lastCursor != location {
                    try transport.send("app_tx_mouse_coordinate", params: ["x": Int(location.x), "y": Int(location.y)])
                    lastCursor = location
                }
            }
        } catch { stop(message: "Native USB: \(error)") }
    }
    func stop(message: String = "Native USB is off.") {
        generation = UUID(); startTask?.cancel(); startTask = nil
        timer?.invalidate(); timer = nil; cursorTimer?.invalidate(); cursorTimer = nil
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        encoder?.stop(); encoder = nil
        videoQueue.sync { }
        if projectionRequest != nil { try? transport?.send("notify-projection-stopped") }
        projectionRequest = nil
        active = false; starting = false; busy = false
        cursorVisible = false; lastCursor = nil
        transport = nil; virtualDisplay = nil; status = message
        NSLog("Dockside native stopped: %@", message)
        didStop?()
    }
    static func selfCheck() throws {
        let chunks = try reports(id: 2, payload: Data(repeating: 0x5a, count: 12273), width: 1280, height: 720)
        precondition(chunks.count == 2 && chunks.allSatisfy { $0.count == 12288 })
        precondition(word(Array(chunks[0]), 1) == 12273 && word(Array(chunks[1]), 1) == 0)
        precondition(word(Array(chunks[0]), 8) == 1280 && word(Array(chunks[0]), 12) == 720)
        precondition(chunks[1][16] == 0x5a && chunks[1][17] == 0)
        let control = try reports(id: 1, payload: Data(repeating: 0x33, count: 4081))
        precondition(control.count == 2 && control.allSatisfy { $0.count == 4096 })
        precondition(word(Array(control[0]), 1) == 4081 && control[1][16] == 0x33 && control[1][17] == 0)
        let converted = try annexB(Data([0,0,0,2,0x67,0x42,0,0,0,1,0x65]))
        precondition(converted == Data([0,0,0,1,0x67,0x42,0,0,0,1,0x65]))
        for bad in [Data(), Data([0,0,0]), Data([0,0,0,0]), Data([0,0,0,3,1])] {
            do { _ = try annexB(bad); preconditionFailure("Accepted invalid NAL") } catch { }
        }
    }
}

/// macOS attaches new virtual screens below the main display, which steals its bottom edge and
/// lets the Dock migrate onto the dashboard. Park the panel top-aligned right of every other screen instead.
func moveBesideDesktop(_ id: CGDirectDisplayID) {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return }
    let others = ids.prefix(Int(count)).filter { $0 != id && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    guard let right = others.map({ CGDisplayBounds($0).maxX }).max() else { return }
    let top = CGDisplayBounds(CGMainDisplayID()).minY
    if CGDisplayBounds(id).origin == CGPoint(x: right, y: top) { return } // already parked; avoids a reconfigure loop
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return }
    CGConfigureDisplayOrigin(config, id, Int32(right), Int32(top))
    if CGCompleteDisplayConfiguration(config, .forSession) != .success { CGCancelDisplayConfiguration(config) }
}

/// Timers in common modes keep the heartbeat and video running while a menu, picker or permission prompt is open;
/// default-mode timers pause there and the dock drops to "Connecting signal".
@discardableResult func commonTimer(_ interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
    RunLoop.main.add(timer, forMode: .common)
    return timer
}
/// The panel draws the image with its top-left at the pointer, so crop the arrow to its hotspot and scale it for the small screen.
/// An empty string does not hide the panel cursor, so "hidden" is a transparent pixel.
@MainActor func panelCursor(visible: Bool, scale: CGFloat = 2) -> String {
    let arrow = NSCursor.arrow, hot = arrow.hotSpot, size = arrow.image.size
    let width = visible ? Int((size.width - hot.x) * scale) : 1, height = visible ? Int((size.height - hot.y) * scale) : 1
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
    if visible {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        arrow.image.draw(in: NSRect(x: -hot.x * scale, y: CGFloat(height) - (size.height - hot.y) * scale, width: size.width * scale, height: size.height * scale))
        NSGraphicsContext.restoreGraphicsState()
    }
    return bitmap.representation(using: .png, properties: [:])?.base64EncodedString() ?? ""
}
