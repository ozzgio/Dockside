import AppKit
import SwiftUI
import IOKit.ps
import IOKit.pwr_mgt
import Darwin


func cpuPercent(previous: [UInt64], current: [UInt64]) -> Double {
    guard previous.count == 4, current.count == 4,
          zip(previous, current).allSatisfy({ $1 >= $0 }) else { return 0 }
    let deltas = zip(previous, current).map { $1 - $0 }
    let total = deltas.reduce(0, +)
    return total == 0 ? 0 : Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) * 100
}

func networkRate(previous: UInt64, current: UInt64, elapsed: Double) -> Double {
    guard elapsed > 0, current >= previous else { return 0 }
    return Double(current - previous) / elapsed
}

func rateText(_ bytes: Double) -> String {
    bytes >= 1_000_000 ? String(format: "%.1f MB/s", bytes / 1_000_000) : String(format: "%.0f KB/s", bytes / 1_000)
}

@MainActor final class Monitor: ObservableObject {
    @Published var now = Date()
    @Published var cpu = 0.0
    @Published var memory = 0.0
    @Published var memoryUsed = 0.0
    @Published var battery: Int?
    @Published var charging = false
    @Published var download = 0.0
    @Published var upload = 0.0
    @Published var history = Array(repeating: 0.0, count: 48)
    @Published var diskFree = "—"
    @Published var focusRemaining = 25 * 60
    @Published var focusRunning = false
    @Published var focusFinished = false
    @Published var awake = false
    @Published var notice = ""
    @Published var clockOnly = false { didSet { preferences.clockOnly = clockOnly } }
    @Published var displayConnected = false
    @Published var showUtilities = false
    @Published var preview = false
    @Published var isFullscreen = false
    let preferences: Preferences
    private var previousCPU: [UInt64]?
    private var previousNetwork: (UInt64, UInt64, TimeInterval)?
    private var deadline: Date?
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?
    private var sampleCount = 0

    init(preferences: Preferences) {
        self.preferences = preferences
        clockOnly = preferences.clockOnly
        focusRemaining = preferences.focusMinutes * 60
        sample()
        timer = commonTimer(1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func sample() {
        now = Date()
        var ticks = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &ticks) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let current = [ticks.cpu_ticks.0, ticks.cpu_ticks.1, ticks.cpu_ticks.2, ticks.cpu_ticks.3].map(UInt64.init)
            if let previousCPU { cpu = cpuPercent(previous: previousCPU, current: current) }
            previousCPU = current
        }
        history.removeFirst()
        history.append(cpu)

        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            // Match activity-monitor style usage: app + wired + compressed, excluding purgeable pages.
            let pages = UInt64(vm.active_count) + UInt64(vm.inactive_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            let reclaimable = UInt64(vm.external_page_count) + UInt64(vm.purgeable_count)
            let used = Double(pages > reclaimable ? pages - reclaimable : 0) * Double(pageSize)
            memoryUsed = used / 1_073_741_824
            memory = min(100, max(0, used / Double(ProcessInfo.processInfo.physicalMemory) * 100))
        }

        var addresses: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addresses) == 0 {
            var received: UInt64 = 0
            var sent: UInt64 = 0
            var cursor = addresses
            while let item = cursor {
                let interface = item.pointee
                if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                   String(cString: interface.ifa_name).hasPrefix("en"), let data = interface.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    received += UInt64(stats.ifi_ibytes)
                    sent += UInt64(stats.ifi_obytes)
                }
                cursor = interface.ifa_next
            }
            freeifaddrs(addresses)
            let instant = ProcessInfo.processInfo.systemUptime
            if let (oldReceived, oldSent, oldInstant) = previousNetwork {
                download = networkRate(previous: oldReceived, current: received, elapsed: instant - oldInstant)
                upload = networkRate(previous: oldSent, current: sent, elapsed: instant - oldInstant)
            }
            previousNetwork = (received, sent, instant)
        }

        if sampleCount % 10 == 0 {
            if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                battery = nil
                for source in sources {
                    if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                       description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                       let capacity = description[kIOPSCurrentCapacityKey] as? Int {
                        battery = capacity
                        charging = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                        break
                    }
                }
            }
            if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let capacity = values.volumeAvailableCapacityForImportantUsage {
                diskFree = ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
            }
        }
        sampleCount += 1
        if let deadline {
            focusRemaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            if focusRemaining == 0 {
                self.deadline = nil
                focusRunning = false
                focusFinished = true
                NSSound(named: "Glass")?.play()
            }
        }
    }

    func toggleFocus() {
        if focusRunning {
            focusRemaining = max(0, Int(ceil(deadline?.timeIntervalSinceNow ?? 0)))
            deadline = nil
            focusRunning = false
        } else {
            if focusRemaining == 0 { focusRemaining = preferences.focusMinutes * 60 }
            focusFinished = false
            deadline = Date().addingTimeInterval(Double(focusRemaining))
            focusRunning = true
        }
    }

    func resetFocus() {
        deadline = nil
        focusRemaining = preferences.focusMinutes * 60
        focusRunning = false
        focusFinished = false
    }

    func toggleAwake() {
        if awake {
            guard IOPMAssertionRelease(assertion) == kIOReturnSuccess else {
                notice = "Couldn’t release keep-awake mode. Quit Dockside to release it."
                return
            }
            awake = false
            notice = "Keep awake off. Normal display sleep is allowed."
        } else {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Dockside keep awake" as CFString, &assertion)
            if result == kIOReturnSuccess {
                awake = true
                notice = "Keep awake on. Panel brightness is controlled on the dock."
            }
            else { notice = "Couldn’t keep the display awake." }
        }
    }

    func stop() {
        timer?.invalidate()
        if awake { IOPMAssertionRelease(assertion) }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: geo.size.width * Double(index) / Double(max(1, values.count - 1)),
                                        y: geo.size.height * (1 - min(100, max(0, value)) / 100))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var preferences: Preferences
    @ObservedObject var utilities: DeskUtilities
    let showControls: () -> Void
    let toggleFullscreen: () -> Void
    private var ink: Color { preferences.theme.background }
    private var mist: Color { preferences.theme.foreground }
    private var blue: Color { preferences.theme.accent }
    private var muted: Color { preferences.theme.secondary }
    private var yellow: Color { preferences.theme.focus }
    let moveToDock: () -> Void
    let moveToMac: () -> Void
    let openDriver: () -> Void
    let connectNative: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ink
                content.frame(width: 960, height: 540)
                    .scaleEffect(min(geometry.size.width / 960, geometry.size.height / 540))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                Color.black.opacity(preferences.pictureDim).allowsHitTesting(false).accessibilityHidden(true)
            }
        }.foregroundStyle(mist).preferredColorScheme(preferences.theme.scheme)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !monitor.isFullscreen || preferences.showHeader {
            HStack(spacing: 10) {
                if let url = Bundle.main.url(forResource: "DocksideMark", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().frame(width: 34, height: 34).accessibilityHidden(true)
                }
                Text("Dockside").font(.system(size: 23, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(monitor.displayConnected ? blue : muted).frame(width: 7, height: 7)
                    Text(monitor.displayConnected ? "Connected" : monitor.preview ? "Preview" : "Offline").font(.system(size: 16, weight: .medium)).foregroundStyle(muted)
                }.padding(.leading, 8)
                Spacer()
                if monitor.showUtilities { Text("Mac \(clockText(monitor.now, showSeconds: false))").font(.system(size: 22, weight: .medium)).monospacedDigit().padding(.trailing, 12) }
                if preferences.showBattery, let battery = monitor.battery {
                    Image(systemName: monitor.charging ? "battery.100percent.bolt" : "battery.100percent").font(.system(size: 20))
                    Text("\(battery)%").font(.system(size: 19, weight: .medium)).monospacedDigit()
                }
            }.frame(height: 36)
            }

            if !monitor.displayConnected && !monitor.preview {
                disconnected.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if monitor.showUtilities {
                    TodayView(monitor: monitor, preferences: preferences, utilities: utilities)
                } else if monitor.clockOnly {
                    VStack(spacing: 8) {
                        clock.font(.system(size: (preferences.showSeconds ? 126.0 : 158.0) * Double(preferences.clockPercent) / 100, weight: .medium))
                        if preferences.showDate { dateLabel }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 8) {
                            if preferences.showDate { dateLabel }
                            clock.font(.system(size: (preferences.showSeconds ? 100.0 : 144.0) * Double(preferences.clockPercent) / 100, weight: .medium))
                                .tracking(-6).padding(.leading, -5).minimumScaleFactor(0.8).lineLimit(1)
                            Spacer(minLength: 12)
                            if preferences.showFocus { focus }
                        }.frame(width: preferences.showActivity ? 490 : nil, alignment: .leading)
                        if preferences.showActivity {
                        Rectangle().fill(muted.opacity(0.3)).frame(width: 2)
                        VStack(alignment: .leading, spacing: 16) {
                            metric("CPU", value: "\(Int(monitor.cpu.rounded()))%", percent: monitor.cpu)
                            if preferences.showHistory { Sparkline(values: monitor.history, color: blue).frame(height: 30) }
                            metric("Memory", value: "\(Int(monitor.memory.rounded()))%", percent: monitor.memory)
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down").foregroundStyle(blue)
                                Text(rateText(monitor.download)).monospacedDigit()
                                Spacer(minLength: 0)
                            }.font(.system(size: 27, weight: .semibold)).accessibilityLabel("Download, \(rateText(monitor.download))")
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up").foregroundStyle(blue)
                                Text(rateText(monitor.upload)).monospacedDigit()
                                Spacer(minLength: 0)
                            }.font(.system(size: 27, weight: .semibold)).accessibilityLabel("Upload, \(rateText(monitor.upload))")
                            Text("\(monitor.diskFree) free").font(.system(size: 22, weight: .medium)).foregroundStyle(muted)
                        }.frame(maxWidth: .infinity)
                        }
                    }.frame(maxHeight: .infinity)
                }
            }
            HStack(spacing: 10) {
                if preferences.showShortcuts && (monitor.displayConnected || monitor.preview) {
                    ForEach(0..<preferences.shortcuts.count, id: \.self) { index in
                        Button { launch(index) } label: {
                            HStack(spacing: 9) {
                                if let url = preferences.shortcuts[index].applicationURL {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 25, height: 25)
                                }
                                Text(preferences.shortcuts[index].title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                            }.padding(.horizontal, 13).frame(height: 48).background(muted.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).help("Open \(preferences.shortcuts[index].title)")
                    }
                }
                Spacer(minLength: 8)
                if monitor.displayConnected || monitor.preview {
                    pageButton("Overview", symbol: "rectangle.split.2x1", selected: !monitor.showUtilities && !monitor.clockOnly) { monitor.showUtilities = false; monitor.clockOnly = false }
                    pageButton("Clock", symbol: "clock", selected: !monitor.showUtilities && monitor.clockOnly) { monitor.showUtilities = false; monitor.clockOnly = true }
                    pageButton("Today", symbol: "square.grid.2x2", selected: monitor.showUtilities) { monitor.showUtilities = true }
                    Rectangle().fill(muted.opacity(0.3)).frame(width: 1, height: 28).padding(.horizontal, 4)
                }
                Button(action: showControls) {
                    Label("Settings", systemImage: "gearshape").font(.system(size: 17, weight: .semibold)).padding(.horizontal, 10).frame(height: 48)
                }.buttonStyle(.plain).help("Settings (⌘,)").accessibilityLabel("Settings")
            }.frame(height: 52)

            if !monitor.notice.isEmpty {
                Text(monitor.notice).font(.system(size: 20, weight: .medium)).foregroundStyle(yellow).lineLimit(2)
            }
        }.padding(32)
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 45)).foregroundStyle(yellow)
            Text("Your dock display is offline.")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("Connect Dockside directly to your screen,\nor open USB Display for the factory connection.")
                .font(.system(size: 24, weight: .medium)).foregroundStyle(muted).lineSpacing(6)
            HStack(spacing: 20) {
                Button("Connect screen", action: connectNative)
                    .buttonStyle(.plain).font(.system(size: 24, weight: .bold))
                    .padding(.horizontal, 24).padding(.vertical, 18)
                    .background(blue, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(ink)
                Button("Preview on this Mac") { monitor.preview = true }
                    .buttonStyle(.plain).font(.system(size: 22, weight: .semibold))
            }
            Text("Native USB is experimental and supports the tested 1280 × 720 dock.")
                .font(.system(size: 20, weight: .medium)).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var clock: some View {
        Text(clockText(monitor.now, showSeconds: preferences.showSeconds))
            .monospacedDigit().foregroundStyle(mist).contentTransition(.identity)
    }
    private var dateLabel: some View {
        Text(monitor.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .font(.system(size: 26, weight: .semibold)).foregroundStyle(muted)
    }
    private var focus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monitor.focusFinished ? "Focus complete" : "Focus timer")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(muted)
            HStack(spacing: 16) {
                Text(String(format: "%02d:%02d", monitor.focusRemaining / 60, monitor.focusRemaining % 60))
                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(monitor.focusRunning ? yellow : mist)
                Spacer(minLength: 0)
                Button { monitor.toggleFocus() } label: {
                    Label(monitor.focusRunning ? "Pause" : "Start", systemImage: monitor.focusRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold)).padding(.horizontal, 22).frame(height: 56)
                        .background(yellow, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(ink)
                }.buttonStyle(.plain)
                Button { monitor.resetFocus() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 27, weight: .semibold)).frame(width: 44, height: 56)
                }.buttonStyle(.plain).help("Reset focus timer").accessibilityLabel("Reset focus timer")
            }
        }
    }
    private func metric(_ title: String, value: String, percent: Double) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 24, weight: .semibold)).foregroundStyle(muted)
                Spacer()
                Text(value).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geo in
                Capsule().fill(muted.opacity(0.2))
                Capsule().fill(blue).frame(width: geo.size.width * max(0, min(100, percent)) / 100)
            }.frame(height: 7)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(value)")
    }
    private func pageButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
            }.foregroundStyle(selected ? blue : muted).frame(width: title == "Overview" ? 66 : 54, height: 48)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func launch(_ index: Int) {
        guard preferences.shortcuts.indices.contains(index), let url = preferences.shortcuts[index].applicationURL else {
            monitor.notice = "App not found. Choose it again in Settings → Apps."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { Task { @MainActor in monitor.notice = "Couldn’t open the app. Choose it again in Settings." } }
        }
    }
}

final class DashboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let preferences = Preferences()
    lazy var monitor = Monitor(preferences: preferences)
    lazy var utilities = DeskUtilities(preferences: preferences)
    let updates = UpdateChecker()
    let native = NativeDisplay()
    var window: NSWindow!
    private var controls: NSWindow?
    private var nativeRenderer: ImageRenderer<AnyView>?
    private var statusItem: NSStatusItem?
    private var followDock = true
    private var screenObserver: NSObjectProtocol?
    private var transitioning = false
    private var pendingPlacement = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dockside", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showControls), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Check for updates…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Show on preferred display", action: #selector(showOnDock), keyEquivalent: "d").target = self
        appMenu.addItem(withTitle: "Open in a Mac window", action: #selector(showOnMac), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Open USB Display", action: #selector(openDriver), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dockside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let full = viewMenu.addItem(withTitle: "Toggle Fullscreen", action: #selector(toggleFullscreen), keyEquivalent: "f")
        full.target = self
        full.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        NSApp.mainMenu = menu
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Menu-bar version of the app mark: display, one content line, dock base. Template, so macOS tints it.
            NSColor.black.set()
            let bezel = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 2.75, width: 14.5, height: 9.5), xRadius: 2.2, yRadius: 2.2); bezel.lineWidth = 1.5; bezel.stroke()
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 5.5, width: 5.5, height: 2), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(rect: NSRect(x: 8, y: 12.5, width: 2, height: 1.5)).fill()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 14, width: 10, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
            return true
        }
        status.button?.image?.isTemplate = true
        status.button?.image?.accessibilityDescription = "Dockside"
        status.button?.toolTip = "Dockside — dashboard and Settings"
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "Settings…", action: #selector(showControls), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Show dashboard", action: #selector(showOnDock), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Toggle fullscreen", action: #selector(toggleFullscreen), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Check for updates…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Open USB Display", action: #selector(openDriver), keyEquivalent: "").target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit Dockside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        status.menu = statusMenu
        statusItem = status

        window = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: 1008, height: 567),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Dockside"
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.minSize = NSSize(width: 720, height: 430)
        let hosting = NSHostingView(rootView: dashboard)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        placeWindow(enterFullscreen: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if preferences.fullscreenAtLaunch && dockScreen != nil {
            DispatchQueue.main.async { [weak self] in self?.toggleFullscreen() }
        }
        native.render = { [weak self] width, height in
            guard let self else { return nil }
            if self.nativeRenderer == nil {
                let renderer = ImageRenderer(content: AnyView(self.dashboard.frame(width: CGFloat(width), height: CGFloat(height))))
                renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
                renderer.scale = 1; renderer.isOpaque = true
                self.nativeRenderer = renderer
            }
            return self.nativeRenderer?.cgImage
        }
        native.didConnect = { [weak self] in self?.placeNativeWindow() }
        native.didStop = { [weak self] in
            guard let self, self.window != nil else { return }
            self.nativeRenderer = nil
            self.monitor.isFullscreen = false
            self.window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            self.updateScreens()
            self.placeWindow(enterFullscreen: false)
        }
        if preferences.nativeUSB { native.start() }
        else if preferences.openDriverAtLaunch && dockScreen == nil { openDriver() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screensChanged() }
            }
    }
    private var dashboard: Dashboard {
        Dashboard(monitor: monitor, preferences: preferences, utilities: utilities,
            showControls: { [weak self] in self?.showControls() }, toggleFullscreen: { [weak self] in self?.toggleFullscreen() },
            moveToDock: { [weak self] in self?.showOnDock() }, moveToMac: { [weak self] in self?.showOnMac() },
            openDriver: { [weak self] in self?.openDriver() }, connectNative: { [weak self] in self?.setNative(true) })
    }
    private func placeNativeWindow() {
        guard native.active, let screen = dockScreen else { return }
        window.styleMask = [.borderless]
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.dockWindow)) + 1) // clicks must reach the dashboard even if the Dock lands here
        window.setFrame(screen.frame, display: true)
        monitor.displayConnected = true; monitor.isFullscreen = true; monitor.notice = ""
        window.makeKeyAndOrderFront(nil)
    }
    func setNative(_ enabled: Bool) {
        preferences.nativeUSB = enabled
        if enabled {
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            native.start()
        } else { native.stop() }
    }
    private var dockScreen: NSScreen? {
        if native.displayID != 0 {
            return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == native.displayID }
        }
        return NSScreen.screens.first {
            preferences.displayName.isEmpty
                ? $0.localizedName.localizedCaseInsensitiveContains("HDMI Extender")
                : $0.localizedName == preferences.displayName
        }
    }
    @objc func showControls() {
        if controls == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "Dockside Settings"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: ControlCenter(preferences: preferences, monitor: monitor, updates: updates, native: native, utilities: utilities,
                applyDisplay: { [weak self] in self?.showOnDock() }, setNative: { [weak self] in self?.setNative($0) }, toggleFullscreen: { [weak self] in self?.toggleFullscreen() },
                openDriver: { [weak self] in self?.openDriver() }))
            panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            panel.center()
            controls = panel
        }
        if let screen = NSScreen.screens.first(where: { $0 != dockScreen }), let controls {
            let frame = controls.frame
            controls.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.midY - frame.height / 2))
        }
        controls?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func checkUpdates() {
        preferences.selectedTab = 3
        showControls()
        updates.check()
    }
    @objc func showOnDock() {
        if native.active { placeNativeWindow(); return }
        followDock = true
        placeWindow(enterFullscreen: preferences.fullscreenAtLaunch)
        window.makeKeyAndOrderFront(nil)
    }
    @objc func showOnMac() {
        if native.active { showControls(); return }
        followDock = false
        placeWindow(enterFullscreen: false)
        window.makeKeyAndOrderFront(nil)
    }
    @objc func toggleFullscreen() {
        if native.active { showControls(); return }
        guard !transitioning else { return }
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }
    @objc func openDriver() {
        if preferences.nativeUSB { preferences.nativeUSB = false; native.stop() }
        let candidates = [URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/USB Display.app"),
                          URL(fileURLWithPath: "/Applications/USB Display.app")]
        guard let url = candidates.first(where: { Bundle(url: $0)?.bundleIdentifier == "com.winnerwave.USBDisplay" }) else {
            monitor.notice = "Install the USB Display app supplied with your dock, then open it."
            return
        }
        monitor.notice = "Opening USB Display…"
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in self?.monitor.notice = error == nil ? "Allow USB Display’s screen-recording permission if macOS asks." : "Couldn’t open USB Display. Open it from Applications." }
        }
    }
    private func updateScreens() {
        preferences.screenNames = Array(Set(NSScreen.screens.map(\.localizedName))).sorted()
        let connected = dockScreen != nil
        if monitor.displayConnected && !connected { monitor.preview = false }
        monitor.displayConnected = connected
        if connected { monitor.notice = "" }
    }
    private func screensChanged() {
        updateScreens()
        if native.active { moveBesideDesktop(native.displayID); placeNativeWindow(); return }
        if native.starting { return }
        guard !transitioning else { return }
        if window.styleMask.contains(.fullScreen) {
            if followDock && dockScreen == nil { pendingPlacement = true; toggleFullscreen() }
            return
        }
        placeWindow(enterFullscreen: followDock && preferences.fullscreenAtLaunch && dockScreen != nil)
    }
    private func placeWindow(enterFullscreen: Bool) {
        updateScreens()
        if transitioning { return }
        if window.styleMask.contains(.fullScreen) {
            pendingPlacement = true
            toggleFullscreen()
            return
        }
        window.level = .normal
        let screen = followDock ? dockScreen : nil
        let fallback = NSScreen.screens.first { $0 != dockScreen } ?? NSScreen.main
        let area = (screen ?? fallback)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(1008.0, area.width * 0.88)
        let height = width * 9 / 16 + 28
        window.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height), display: true)
        if enterFullscreen && screen != nil {
            DispatchQueue.main.async { [weak self] in self?.toggleFullscreen() }
        }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { transitioning = true }
    func windowWillExitFullScreen(_ notification: Notification) { transitioning = true }
    func windowDidEnterFullScreen(_ notification: Notification) { transitioning = false; monitor.isFullscreen = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        transitioning = false
        if native.active { placeNativeWindow(); return }
        monitor.isFullscreen = false
        if pendingPlacement {
            pendingPlacement = false
            placeWindow(enterFullscreen: followDock && preferences.fullscreenAtLaunch && dockScreen != nil)
        }
    }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        preferences.hideMenuBar
            ? [.fullScreen, .autoHideDock, .autoHideMenuBar, .autoHideToolbar]
            : [.fullScreen, .autoHideDock]
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        native.didStop = nil
        native.stop()
        monitor.stop()
        utilities.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

@main enum Dockside {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            DeskUtilities.selfCheck()
            do { try NativeDisplay.selfCheck() } catch { fatalError("Native protocol self-check: \(error)") }
            precondition(cpuPercent(previous: [10, 10, 10, 10], current: [20, 20, 40, 20]) == 50)
            precondition(cpuPercent(previous: [0, 0, 0, 0], current: [0, 0, 0, 0]) == 0)
            precondition(cpuPercent(previous: [100, 0, 0, 0], current: [1, 0, 0, 0]) == 0)
            precondition(networkRate(previous: 100, current: 300, elapsed: 2) == 100)
            precondition(networkRate(previous: 300, current: 100, elapsed: 2) == 0)
            precondition(networkRate(previous: 100, current: 300, elapsed: 0) == 0)
            precondition(rateText(1_500_000) == "1.5 MB/s")
            let testDomain = "Dockside-self-test-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: testDomain)!
            defer { defaults.removePersistentDomain(forName: testDomain) }
            let preferences = Preferences(defaults: defaults)
            precondition(!preferences.showFocus)
            preferences.showFocus = true
            precondition(Preferences(defaults: defaults).showFocus)
            preferences.theme = .paper
            preferences.focusMinutes = 50
            precondition(Preferences(defaults: defaults).theme == .paper)
            precondition(Preferences(defaults: defaults).focusMinutes == 50)
            defaults.set(-99, forKey: "focusMinutes")
            precondition(Preferences(defaults: defaults).focusMinutes == 5)
            preferences.focusMinutes = 25
            var clockCalendar = Calendar(identifier: .gregorian)
            clockCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let clockDate = clockCalendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 20, minute: 1, second: 5))!
            precondition(clockText(clockDate, showSeconds: false, calendar: clockCalendar) == "20:01")
            precondition(clockText(clockDate, showSeconds: true, calendar: clockCalendar) == "20:01:05")
            let midnight = clockCalendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 0, minute: 0, second: 0))!
            precondition(clockText(midnight, showSeconds: true, calendar: clockCalendar) == "00:00:00")
            precondition(versionNumbers("v1.2.0") == [1, 2, 0])
            precondition(versionNumbers("1.2") == [1, 2, 0])
            precondition(versionNumbers("1.bad.3") == nil)
            precondition(versionNumbers("v1.2.0-beta") == nil)
            let monitor = Monitor(preferences: preferences)
            precondition(monitor.memory.isFinite && (0...100).contains(monitor.memory))
            monitor.toggleFocus()
            precondition(monitor.focusRunning && monitor.focusRemaining == 1500)
            monitor.toggleFocus()
            precondition(!monitor.focusRunning && (1499...1500).contains(monitor.focusRemaining))
            monitor.resetFocus()
            precondition(monitor.focusRemaining == 1500 && !monitor.focusFinished)
            monitor.stop()
            print("Dockside self-check passed: activity counters, preferences, focus controls, version parsing, padded clocks, USB framing, and malformed H.264 input.")
            return
        }
        let app = NSApplication.shared
        if let identifier = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            running.activate(options: [])
            return
        }
        if let url = Bundle.main.url(forResource: "DocksideApp", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            app.applicationIconImage = icon
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
