import AppKit
import SwiftUI
import EventKit
import CoreAudio

func cityName(_ zone: String) -> String { (zone.split(separator: "/").last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ") }
func zonedClock(_ date: Date, zone: String) -> String {
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: zone) ?? .current
    return clockText(date, showSeconds: false, calendar: calendar)
}
func weatherDescription(_ code: Int) -> (String, String) {
    switch code {
    case 0: return ("Clear", "sun.max.fill")
    case 1,2: return ("Partly cloudy", "cloud.sun.fill")
    case 3: return ("Cloudy", "cloud.fill")
    case 45,48: return ("Fog", "cloud.fog.fill")
    case 51...57: return ("Drizzle", "cloud.drizzle.fill")
    case 61...67,80...82: return ("Rain", "cloud.rain.fill")
    case 71...77,85,86: return ("Snow", "cloud.snow.fill")
    case 95...99: return ("Thunderstorms", "cloud.bolt.rain.fill")
    default: return ("Weather", "cloud.fill")
    }
}
struct ScheduleEntry: Identifiable {
    let id: String
    let title: String
    let detail: String
}
struct CalendarSource: Identifiable { let id: String; let title: String }
struct AudioOutput: Identifiable, Equatable { let id: AudioDeviceID; let title: String }
struct WeatherSnapshot {
    let city: String
    let celsius: Double
    let code: Int
    let fetched: Date
    func temperature(fahrenheit: Bool) -> String { "\(Int((fahrenheit ? celsius * 1.8 + 32 : celsius).rounded()))°\(fahrenheit ? "F" : "C")" }
}
private struct Geocoding: Decodable {
    struct Place: Decodable { let name: String; let country: String?; let latitude: Double; let longitude: Double }
    let results: [Place]?
}
private struct Forecast: Decodable {
    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
    let current: Current
}

@MainActor final class DeskUtilities: ObservableObject {
    let preferences: Preferences
    private let store = EKEventStore()
    private var timer: Timer?
    private var storeObserver: NSObjectProtocol?
    private var ticks = 0
    private var reminderRequest = UUID()
    private var weatherTask: Task<Void, Never>?
    private var weatherGeneration = UUID()
    @Published private(set) var calendars: [CalendarSource] = []
    @Published private(set) var reminderLists: [CalendarSource] = []
    @Published private(set) var events: [ScheduleEntry] = []
    @Published private(set) var reminders: [ScheduleEntry] = []
    @Published private(set) var calendarConnected = false
    @Published private(set) var remindersConnected = false
    @Published private(set) var calendarStatus = "Connect your Mac calendars in Settings."
    @Published private(set) var remindersStatus = "Connect Reminders in Settings."
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var weatherStatus = "Weather is off."
    @Published private(set) var weatherLoading = false
    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var outputID: AudioDeviceID = 0
    @Published private(set) var volume = 0.0
    @Published private(set) var volumeAvailable = false
    @Published private(set) var audioStatus = ""
    private var volumeElements: [AudioObjectPropertyElement] = []
    private var lastVolume = 0.5
    init(preferences: Preferences) {
        self.preferences = preferences
        refreshSchedule(); refreshAudio()
        if preferences.showWeather { refreshWeather() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshAudio(); self.ticks += 1
                if self.ticks % 12 == 0 { self.refreshSchedule() }
                if self.ticks % 180 == 0 && self.preferences.showWeather { self.refreshWeather() }
            }
        }
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSchedule() }
        }
    }
    func connectCalendar() {
        Task {
            do {
                if try await store.requestFullAccessToEvents() { refreshSchedule() }
                else { calendarStatus = "Calendar access is off. Allow Dockside in macOS Privacy & Security." }
            } catch { calendarStatus = "Couldn’t connect calendars. Check macOS Privacy & Security." }
        }
    }
    func connectReminders() {
        Task {
            do {
                if try await store.requestFullAccessToReminders() { refreshSchedule() }
                else { remindersStatus = "Reminders access is off. Allow Dockside in macOS Privacy & Security." }
            } catch { remindersStatus = "Couldn’t connect Reminders. Check macOS Privacy & Security." }
        }
    }
    func refreshSchedule() {
        calendarConnected = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersConnected = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        let now = Date(), tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        if calendarConnected {
            let sources = store.calendars(for: .event)
            calendars = sources.map { CalendarSource(id: $0.calendarIdentifier, title: "\($0.title) — \($0.source.title)") }
            let selected = sources.filter { $0.calendarIdentifier == preferences.calendarSource }
            let predicate = store.predicateForEvents(withStart: now, end: tomorrow, calendars: selected.isEmpty ? nil : selected)
            events = store.events(matching: predicate).filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }.prefix(3).map {
                ScheduleEntry(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Untitled event",
                    detail: $0.isAllDay ? "All day" : $0.startDate < now ? "Now" : $0.startDate.formatted(date: .omitted, time: .shortened))
            }
            calendarStatus = events.isEmpty ? "No more events today." : "Mac calendar accounts connected."
        } else { calendars = []; events = []; calendarStatus = "Connect your Mac calendars in Settings." }
        reminderRequest = UUID()
        if remindersConnected {
            let sources = store.calendars(for: .reminder)
            reminderLists = sources.map { CalendarSource(id: $0.calendarIdentifier, title: $0.title) }
            let selected = sources.filter { $0.calendarIdentifier == preferences.reminderSource }
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: selected.isEmpty ? nil : selected)
            let request = reminderRequest
            store.fetchReminders(matching: predicate) { [weak self] result in
                let entries = (result ?? []).filter { ($0.dueDateComponents?.date ?? .distantPast) < tomorrow }
                    .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                    .prefix(3).map { reminder in
                        let due = reminder.dueDateComponents?.date
                        return ScheduleEntry(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder",
                            detail: due.map { Calendar.current.isDateInToday($0) ? "Today" : "Overdue" } ?? "No due date")
                    }
                Task { @MainActor in
                    guard let self, self.reminderRequest == request else { return }
                    self.reminders = entries
                    self.remindersStatus = entries.isEmpty ? "Nothing due today." : "Reminders connected."
                }
            }
        } else { reminderLists = []; reminders = []; remindersStatus = "Connect Reminders in Settings." }
    }
    func refreshWeather() {
        weatherTask?.cancel(); weatherLoading = false; weatherGeneration = UUID()
        let token = weatherGeneration
        guard preferences.showWeather else { weather = nil; weatherLoading = false; weatherStatus = "Weather is off."; return }
        let city = preferences.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(city.count) else { weather = nil; weatherStatus = "Enter a city in Settings."; return }
        weatherLoading = true; weatherStatus = "Updating weather…"
        weatherTask = Task {
            do {
                var search = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                search.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
                let geocoding = try JSONDecoder().decode(Geocoding.self, from: await fetch(search.url!))
                guard let place = geocoding.results?.first, place.latitude.isFinite, place.longitude.isFinite,
                      (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else { throw URLError(.cannotFindHost) }
                var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                forecast.queryItems = [URLQueryItem(name: "latitude", value: String(place.latitude)), URLQueryItem(name: "longitude", value: String(place.longitude)),
                    URLQueryItem(name: "current", value: "temperature_2m,weather_code"), URLQueryItem(name: "timezone", value: "auto")]
                let current = try JSONDecoder().decode(Forecast.self, from: await fetch(forecast.url!)).current
                guard current.temperature_2m.isFinite, (-100...80).contains(current.temperature_2m) else { throw URLError(.cannotParseResponse) }
                guard token == weatherGeneration, preferences.showWeather else { return }
                weather = WeatherSnapshot(city: place.name, celsius: current.temperature_2m, code: current.weather_code, fetched: Date())
                weatherStatus = "Updated \(Date().formatted(date: .omitted, time: .shortened))."
            } catch is CancellationError { }
              catch { if token == weatherGeneration { weatherStatus = "Couldn’t update weather. Check the city and connection." } }
            if token == weatherGeneration { weatherLoading = false }
        }
    }
    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 200_000 else { throw URLError(.badServerResponse) }
        return data
    }
    func refreshAudio() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { volumeAvailable = false; return }
        if outputID != device { outputID = device }
        address.mSelector = kAudioHardwarePropertyDevices
        var bytes: UInt32 = 0
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes) == noErr, bytes < 65536 {
            var devices = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes, &devices) == noErr {
                let available: [AudioOutput] = devices.compactMap { id in
                    var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
                    var length: UInt32 = 0
                    guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &length) == noErr, length > 0 else { return nil }
                    var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                    var name: Unmanaged<CFString>?, nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                    guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr, let name else { return nil }
                    return AudioOutput(id: id, title: name.takeRetainedValue() as String)
                }
                if outputs != available { outputs = available }
            }
        }
        volumeElements = []
        var values: [Float32] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var writable = DarwinBoolean(false), value: Float32 = 0, length = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectIsPropertySettable(device, &property, &writable) == noErr, writable.boolValue,
               AudioObjectGetPropertyData(device, &property, 0, nil, &length, &value) == noErr, value.isFinite {
                volumeElements.append(element); values.append(value)
                if element == kAudioObjectPropertyElementMain { break }
            }
        }
        if volumeAvailable != !values.isEmpty { volumeAvailable = !values.isEmpty }
        if !values.isEmpty {
            let level = min(1, max(0, Double(values.reduce(0,+) / Float(values.count))))
            if abs(volume - level) > 0.001 { volume = level }
        }
        let status = volumeAvailable ? (outputs.first { $0.id == device }?.title ?? "Mac sound") : "This output uses hardware volume controls."
        if audioStatus != status { audioStatus = status }
    }
    func chooseOutput(_ id: AudioDeviceID) {
        guard outputs.contains(where: { $0.id == id }) else { return }
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var selected = id
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &selected) != noErr { audioStatus = "Couldn’t switch the Mac sound output." }
        refreshAudio()
    }
    func setVolume(_ value: Double) {
        guard volumeAvailable, value.isFinite else { return }
        var level = Float32(min(1, max(0, value)))
        for element in volumeElements {
            var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectSetPropertyData(outputID, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr else { audioStatus = "Couldn’t change the output volume."; refreshAudio(); return }
        }
        volume = Double(level)
    }
    func toggleMute() {
        if volume < 0.01 { setVolume(max(0.1, lastVolume)) }
        else { lastVolume = volume; setVolume(0) }
    }
    func stop() {
        timer?.invalidate(); timer = nil; weatherTask?.cancel(); weatherTask = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
    }
    static func selfCheck() {
        precondition(cityName("Australia/Melbourne") == "Melbourne")
        let utc = ISO8601DateFormatter()
        precondition(zonedClock(utc.date(from: "2026-11-13T10:00:00Z")!, zone: "Australia/Melbourne") == "21:00")
        precondition(zonedClock(utc.date(from: "2026-07-13T10:00:00Z")!, zone: "Australia/Melbourne") == "20:00")
        precondition(weatherDescription(0).0 == "Clear" && weatherDescription(71).0 == "Snow")
        precondition(WeatherSnapshot(city: "Test", celsius: 0, code: 0, fetched: Date()).temperature(fahrenheit: true) == "32°F")
    }
}
