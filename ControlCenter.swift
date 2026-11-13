import AppKit
import SwiftUI
import UniformTypeIdentifiers

let projectURL = URL(string: "https://github.com/ozzgio/Dockside")!
let releasesURL = URL(string: "https://github.com/ozzgio/Dockside/releases")!

enum DashboardTheme: String, CaseIterable {
    case midnight = "Midnight", ocean = "Ocean", paper = "Paper", graphite = "Graphite"
    case forest = "Forest", plum = "Plum", sunset = "Sunset"
    var isLight: Bool { self == .paper || self == .sunset }
    var background: Color {
        switch self {
        case .midnight: return Color(red: 0.035, green: 0.055, blue: 0.11)
        case .ocean: return Color(red: 0.035, green: 0.15, blue: 0.22)
        case .paper: return Color(red: 0.96, green: 0.97, blue: 0.99)
        case .graphite: return Color(red: 0.085, green: 0.085, blue: 0.10)
        case .forest: return Color(red: 0.035, green: 0.13, blue: 0.10)
        case .plum: return Color(red: 0.15, green: 0.065, blue: 0.18)
        case .sunset: return Color(red: 1, green: 0.91, blue: 0.84)
        }
    }
    var foreground: Color { isLight ? Color(red: 0.06, green: 0.09, blue: 0.16) : .white }
    var secondary: Color { isLight ? Color(red: 0.27, green: 0.30, blue: 0.38) : Color(red: 0.77, green: 0.84, blue: 0.92) }
    var accent: Color {
        switch self {
        case .paper: return Color(red: 0.12, green: 0.3, blue: 0.68)
        case .sunset: return Color(red: 0.55, green: 0.18, blue: 0.12)
        case .forest: return Color(red: 0.59, green: 0.94, blue: 0.72)
        case .plum: return Color(red: 0.91, green: 0.73, blue: 1)
        default: return Color(red: 0.67, green: 0.85, blue: 1)
        }
    }
    var focus: Color { Color(red: 1, green: 0.76, blue: 0.34) }
    var scheme: ColorScheme { isLight ? .light : .dark }
}

func clockText(_ date: Date, showSeconds: Bool, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
    let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    return showSeconds ? time + String(format: ":%02d", parts.second ?? 0) : time
}

struct LaunchShortcut: Codable, Equatable {
    let role: String
    var title: String
    var bundleID: String
    var path: String?
    static let defaults = [
        LaunchShortcut(role: "Files", title: "Finder", bundleID: "com.apple.finder"),
        LaunchShortcut(role: "Calendar", title: "Calendar", bundleID: "com.apple.iCal"),
        LaunchShortcut(role: "Notes", title: "Notes", bundleID: "com.apple.Notes")
    ]
    var applicationURL: URL? {
        if let path, let bundle = Bundle(path: path), bundle.bundleIdentifier == bundleID {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var theme: DashboardTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var fullscreenAtLaunch: Bool { didSet { defaults.set(fullscreenAtLaunch, forKey: "fullscreenAtLaunch") } }
    @Published var hideMenuBar: Bool { didSet { defaults.set(hideMenuBar, forKey: "hideMenuBar") } }
    @Published var clockOnly: Bool { didSet { defaults.set(clockOnly, forKey: "clockOnly") } }
    @Published var showHeader: Bool { didSet { defaults.set(showHeader, forKey: "showHeader") } }
    @Published var showFocus: Bool { didSet { defaults.set(showFocus, forKey: "showFocus") } }
    @Published var showActivity: Bool { didSet { defaults.set(showActivity, forKey: "showActivity") } }
    @Published var showDate: Bool { didSet { defaults.set(showDate, forKey: "showDate") } }
    @Published var showShortcuts: Bool { didSet { defaults.set(showShortcuts, forKey: "showShortcuts") } }
    @Published var showBattery: Bool { didSet { defaults.set(showBattery, forKey: "showBattery") } }
    @Published var showHistory: Bool { didSet { defaults.set(showHistory, forKey: "showHistory") } }
    @Published var clockPercent: Int { didSet { defaults.set(clockPercent, forKey: "clockPercent") } }
    @Published var showSeconds: Bool { didSet { defaults.set(showSeconds, forKey: "showSeconds") } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var displayName: String { didSet { defaults.set(displayName, forKey: "displayName") } }
    @Published var showSecondClock: Bool { didSet { defaults.set(showSecondClock, forKey: "showSecondClock") } }
    @Published var showAgenda: Bool { didSet { defaults.set(showAgenda, forKey: "showAgenda") } }
    @Published var showReminders: Bool { didSet { defaults.set(showReminders, forKey: "showReminders") } }
    @Published var showWeather: Bool { didSet { defaults.set(showWeather, forKey: "showWeather") } }
    @Published var fahrenheit: Bool { didSet { defaults.set(fahrenheit, forKey: "fahrenheit") } }
    @Published var secondTimeZone: String { didSet { defaults.set(secondTimeZone, forKey: "secondTimeZone") } }
    @Published var weatherCity: String { didSet { defaults.set(weatherCity, forKey: "weatherCity") } }
    @Published var calendarSource: String { didSet { defaults.set(calendarSource, forKey: "calendarSource") } }
    @Published var reminderSource: String { didSet { defaults.set(reminderSource, forKey: "reminderSource") } }
    @Published var pictureDim: Double { didSet { defaults.set(pictureDim, forKey: "pictureDim") } }
    @Published var nativeUSB: Bool { didSet { defaults.set(nativeUSB, forKey: "nativeUSB") } }
    @Published var openDriverAtLaunch: Bool { didSet { defaults.set(openDriverAtLaunch, forKey: "openDriverAtLaunch") } }
    @Published var shortcuts: [LaunchShortcut] { didSet {
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: "shortcuts") }
    } }
    @Published var zoneSearch = ""
    @Published var selectedTab = 0
    @Published var screenNames: [String] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = DashboardTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .midnight
        fullscreenAtLaunch = defaults.object(forKey: "fullscreenAtLaunch") as? Bool ?? true
        showHeader = defaults.bool(forKey: "showHeader")
        hideMenuBar = defaults.bool(forKey: "hideMenuBar")
        clockOnly = defaults.bool(forKey: "clockOnly")
        showSeconds = defaults.bool(forKey: "showSeconds")
        showFocus = defaults.bool(forKey: "showFocus")
        showActivity = defaults.object(forKey: "showActivity") as? Bool ?? true
        showDate = defaults.object(forKey: "showDate") as? Bool ?? true
        showShortcuts = defaults.object(forKey: "showShortcuts") as? Bool ?? true
        showBattery = defaults.object(forKey: "showBattery") as? Bool ?? true
        showHistory = defaults.object(forKey: "showHistory") as? Bool ?? true
        clockPercent = min(115, max(80, defaults.object(forKey: "clockPercent") as? Int ?? 100))
        let savedMinutes = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        focusMinutes = min(120, max(5, savedMinutes))
        displayName = defaults.string(forKey: "displayName") ?? ""
        showSecondClock = defaults.object(forKey: "showSecondClock") as? Bool ?? true
        showAgenda = defaults.object(forKey: "showAgenda") as? Bool ?? true
        showReminders = defaults.object(forKey: "showReminders") as? Bool ?? true
        showWeather = defaults.bool(forKey: "showWeather")
        fahrenheit = defaults.bool(forKey: "fahrenheit")
        let zone = defaults.string(forKey: "secondTimeZone") ?? "Australia/Melbourne"
        secondTimeZone = TimeZone(identifier: zone) == nil ? "Australia/Melbourne" : zone
        weatherCity = defaults.string(forKey: "weatherCity") ?? "Melbourne"
        calendarSource = defaults.string(forKey: "calendarSource") ?? ""
        reminderSource = defaults.string(forKey: "reminderSource") ?? ""
        let dim = defaults.double(forKey: "pictureDim")
        pictureDim = dim.isFinite ? min(0.55, max(0, dim)) : 0
        nativeUSB = defaults.bool(forKey: "nativeUSB")
        openDriverAtLaunch = defaults.bool(forKey: "openDriverAtLaunch")
        if let data = defaults.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode([LaunchShortcut].self, from: data),
           saved.count == 3, zip(saved, LaunchShortcut.defaults).allSatisfy({ $0.role == $1.role && !$0.bundleID.isEmpty && !$0.title.isEmpty }) {
            shortcuts = saved
        } else { shortcuts = LaunchShortcut.defaults }
    }
    func chooseApp(at index: Int) {
        guard shortcuts.indices.contains(index) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an app for \(shortcuts[index].role)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        shortcuts[index] = LaunchShortcut(role: shortcuts[index].role, title: name, bundleID: identifier, path: url.path)
    }
}

func versionNumbers(_ tag: String) -> [Int]? {
    let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty, parts.count <= 3 else { return nil }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
    return numbers + Array(repeating: 0, count: 3 - numbers.count)
}

@MainActor final class UpdateChecker: ObservableObject {
    @Published var status = "Check GitHub for a newer release. Nothing is downloaded or installed automatically."
    @Published var checking = false
    @Published var available = false
    func check() {
        guard !checking else { return }
        checking = true
        available = false
        status = "Checking GitHub…"
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/ozzgio/Dockside/releases?per_page=10")!)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Dockside", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 404 { status = "No public release has been published yet."; return }
                guard response.statusCode == 200, data.count < 1_000_000,
                      let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    status = "Couldn’t read GitHub’s release information. Try again later."
                    return
                }
                guard let release = releases.first(where: { $0["draft"] as? Bool != true }) else {
                    status = "No public release has been published yet."
                    return
                }
                guard let tag = release["tag_name"] as? String, let latest = versionNumbers(tag),
                      let current = versionNumbers(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") else {
                    status = "Couldn’t read GitHub’s release information. Try again later."
                    return
                }
                available = current.lexicographicallyPrecedes(latest)
                status = available ? "\(tag) is available on GitHub." : "You’re up to date (\(tag))."
            } catch { status = "Couldn’t reach GitHub. Check your connection and try again." }
        }
    }
}

struct ControlCenter: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var monitor: Monitor
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var native: NativeDisplay
    @ObservedObject var utilities: DeskUtilities
    let applyDisplay: () -> Void
    let setNative: (Bool) -> Void
    let toggleFullscreen: () -> Void
    let openDriver: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if let icon = NSApp.applicationIconImage { Image(nsImage: icon).resizable().frame(width: 48, height: 48) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dockside Settings").font(.title2.bold())
                    Text(native.active ? "Connected directly with Dockside native USB" : monitor.displayConnected ? "Display connected" : "Display offline — choose a connection below").foregroundStyle(.secondary)
                }
                Spacer()
            }
            TabView(selection: $preferences.selectedTab) {
                Form {
                    Section("Display") {
                        Picker("Preferred display", selection: $preferences.displayName) {
                            Text("Automatic — Cabletime / HDMI Extender").tag("")
                            ForEach(preferences.screenNames, id: \.self) { Text($0).tag($0) }
                        }
                        Toggle("Open dashboard in fullscreen", isOn: $preferences.fullscreenAtLaunch).disabled(native.active)
                        Toggle("Show Dockside header in fullscreen", isOn: $preferences.showHeader)
                        Toggle("Hide Mac menu bar in fullscreen", isOn: $preferences.hideMenuBar).disabled(native.active)
                        HStack {
                            Button("Apply to display", action: applyDisplay)
                            if !native.active { Button(monitor.isFullscreen ? "Exit fullscreen" : "Enter fullscreen", action: toggleFullscreen) }
                        }
                        Text("Fullscreen hides the title bar. Apply changes to refresh menu-bar behavior. Settings is also available from the Dockside menu-bar icon or ⌘,. Press Esc to leave fullscreen.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Appearance") {
                        Picker("Theme", selection: $preferences.theme) {
                            ForEach(DashboardTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.menu)
                        Toggle("Show seconds on the clock", isOn: $preferences.showSeconds)
                        Stepper("Clock size: \(preferences.clockPercent)%", value: $preferences.clockPercent, in: 80...115, step: 5)
                    }
                    Section("Overview widgets") {
                        Text("Switch between Overview, Clock and Today from the bar on the Dockside screen.").font(.callout).foregroundStyle(.secondary)
                        Toggle("Focus timer", isOn: $preferences.showFocus).onChange(of: preferences.showFocus) { _, enabled in
                            if !enabled && monitor.focusRunning { monitor.toggleFocus() }
                        }
                        Toggle("Mac activity", isOn: $preferences.showActivity)
                        Toggle("CPU history graph", isOn: $preferences.showHistory)
                        Toggle("Date", isOn: $preferences.showDate)
                        Toggle("App shortcuts", isOn: $preferences.showShortcuts)
                        Toggle("Battery in header", isOn: $preferences.showBattery)
                        Stepper("Focus session: \(preferences.focusMinutes) minutes", value: $preferences.focusMinutes, in: 5...120, step: 5)
                        Button("Reset timer to this duration") { monitor.resetFocus() }
                    }
                    Section("Power and driver") {
                        Toggle("Keep displays awake", isOn: Binding(get: { monitor.awake }, set: { if $0 != monitor.awake { monitor.toggleAwake() } }))
                        Text(monitor.awake ? "Active: macOS idle display sleep is prevented while Dockside runs." : "Off: macOS uses your normal display-sleep settings.").font(.callout).foregroundStyle(.secondary)
                        Text("This is not a brightness control. Adjust the Cabletime panel’s brightness with its hardware button.").font(.callout).foregroundStyle(.secondary)
                        Toggle("Use Dockside native USB (experimental)", isOn: Binding(get: { preferences.nativeUSB }, set: setNative))
                        Text(native.status).textSelection(.enabled)
                        Text("Replaces USB Display for this 1280 × 720 dashboard. Native mode fills the panel, supports mouse controls, and does not mirror other apps or the Mac menu bar. It uses a private macOS virtual-display API; hardware testing is currently limited to this dock on macOS 27.").font(.callout).foregroundStyle(.secondary)
                        if preferences.nativeUSB && !native.active { Button(native.starting ? "Connecting…" : "Retry native USB") { setNative(true) }.disabled(native.starting) }
                        Toggle("Open USB Display when Dockside launches", isOn: $preferences.openDriverAtLaunch).disabled(preferences.nativeUSB)
                        Button("Open USB Display", action: openDriver)
                    }
                }.formStyle(.grouped).tabItem { Label("Display & theme", systemImage: "display") }.tag(0)
                Form {
                    Section("Dashboard shortcuts") {
                        Text("Choose the app each button opens. This changes Dockside only; your Mac’s global default apps stay unchanged.").foregroundStyle(.secondary)
                        ForEach(0..<preferences.shortcuts.count, id: \.self) { index in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preferences.shortcuts[index].role).fontWeight(.semibold)
                                    Text(preferences.shortcuts[index].title).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Choose app…") { preferences.chooseApp(at: index) }
                                Button("Reset") { preferences.shortcuts[index] = LaunchShortcut.defaults[index] }
                            }.padding(.vertical, 6)
                        }
                    }
                }.formStyle(.grouped).tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag(1)
                Form {
                    Section("Second clock") {
                        Toggle("Show second clock on Today", isOn: $preferences.showSecondClock)
                        TextField("Find a city or region", text: $preferences.zoneSearch)
                        Picker("Timezone", selection: $preferences.secondTimeZone) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers.filter { $0 == preferences.secondTimeZone || preferences.zoneSearch.isEmpty || $0.localizedCaseInsensitiveContains(preferences.zoneSearch) }, id: \.self) { id in
                                Text("\(cityName(id)) (\(id.split(separator: "/").first.map(String.init) ?? ""))").tag(id)
                            }
                        }
                        Text("Your main clock always uses the Mac’s current timezone. Melbourne is the initial second clock; daylight saving is automatic.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Weather") {
                        Toggle("Show weather on Today", isOn: $preferences.showWeather).onChange(of: preferences.showWeather) { _, _ in utilities.refreshWeather() }
                        TextField("Weather city", text: $preferences.weatherCity).onSubmit { utilities.refreshWeather() }
                        Toggle("Use Fahrenheit", isOn: $preferences.fahrenheit)
                        HStack { Button(utilities.weatherLoading ? "Updating…" : "Refresh weather") { utilities.refreshWeather() }.disabled(utilities.weatherLoading || !preferences.showWeather); Text(utilities.weatherStatus).foregroundStyle(.secondary) }
                        Text("Sends the city name to Open-Meteo to fetch current weather every 15 minutes. No GPS location is requested.").font(.callout).foregroundStyle(.secondary)
                        Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                    }
                    Section("Calendar agenda") {
                        Toggle("Show agenda on Today", isOn: $preferences.showAgenda)
                        Text(utilities.calendarStatus).foregroundStyle(.secondary)
                        if utilities.calendarConnected {
                            Picker("Calendar", selection: $preferences.calendarSource) { Text("All Mac calendars").tag(""); ForEach(utilities.calendars) { Text($0.title).tag($0.id) } }.onChange(of: preferences.calendarSource) { _, _ in utilities.refreshSchedule() }
                        } else { Button("Connect calendar…") { utilities.connectCalendar() } }
                        Text("Reads events from the Mac’s calendar accounts. Your Calendar shortcut can still open the app you chose. Dockside never creates or edits events.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Reminders") {
                        Toggle("Show reminders on Today", isOn: $preferences.showReminders)
                        Text(utilities.remindersStatus).foregroundStyle(.secondary)
                        if utilities.remindersConnected {
                            Picker("List", selection: $preferences.reminderSource) { Text("All lists").tag(""); ForEach(utilities.reminderLists) { Text($0.title).tag($0.id) } }.onChange(of: preferences.reminderSource) { _, _ in utilities.refreshSchedule() }
                        } else { Button("Connect Reminders…") { utilities.connectReminders() } }
                        Text("Shows unfinished reminders due today, overdue, or without a date. Dockside never changes them.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Sound and picture") {
                        Picker("Mac sound output", selection: Binding(get: { utilities.outputID }, set: { utilities.chooseOutput($0) })) { ForEach(utilities.outputs) { Text($0.title).tag($0.id) } }
                        Slider(value: Binding(get: { utilities.volume }, set: { utilities.setVolume($0) }), in: 0...1) { Text("Volume") }.disabled(!utilities.volumeAvailable)
                        Text(utilities.audioStatus).foregroundStyle(.secondary)
                        Slider(value: $preferences.pictureDim, in: 0...0.55, step: 0.05) { Text("Picture dimmer") }
                        Text("\(Int(((1 - preferences.pictureDim) * 100).rounded()))% picture level. This dims Dockside’s image, not the dock’s hardware backlight.").font(.callout).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped).tabItem { Label("Utilities", systemImage: "square.grid.2x2") }.tag(2)
                Form {
                    Section("Product updates") {
                        Text("Dockside \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
                        Text(updates.status).textSelection(.enabled)
                        HStack {
                            Button(updates.checking ? "Checking…" : "Check for updates") { updates.check() }.disabled(updates.checking)
                            Button("View releases") { NSWorkspace.shared.open(releasesURL) }
                        }
                        Text("Developer-preview downloads are not notarized. Updates are reviewed and installed manually.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Project") {
                        Link("Source and issues on GitHub", destination: projectURL)
                        Link("Project page", destination: URL(string: "https://ozzgio.github.io/Dockside/")!)
                        Text("Source is public; the project license has not been chosen yet.").foregroundStyle(.secondary)
                        Text("Apple Silicon + Intel. Targets macOS 14 or later; see the repository for the tested-version matrix.").foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped).tabItem { Label("Updates & project", systemImage: "arrow.down.circle") }.tag(3)
            }
            if !monitor.notice.isEmpty { Text(monitor.notice).font(.callout).foregroundStyle(.secondary) }
        }.padding(22).frame(minWidth: 700, minHeight: 700)
    }
}
