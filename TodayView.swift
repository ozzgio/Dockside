import AppKit
import SwiftUI

struct TodayView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var preferences: Preferences
    @ObservedObject var utilities: DeskUtilities
    private var muted: Color { preferences.theme.secondary }
    private var accent: Color { preferences.theme.accent }
    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 22) {
                if preferences.showAgenda { schedule("Today’s agenda", entries: utilities.events, empty: utilities.calendarStatus, symbol: "calendar") }
                if preferences.showReminders { schedule("Reminders", entries: utilities.reminders, empty: utilities.remindersStatus, symbol: "checklist") }
                if !preferences.showAgenda && !preferences.showReminders {
                    Text("Your day, at a glance").font(.system(size: 28, weight: .semibold))
                    Text("Choose the utilities you want in Settings.").font(.system(size: 22)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
            }.frame(width: 430, alignment: .leading)
            Rectangle().fill(muted.opacity(0.25)).frame(width: 1)
            VStack(alignment: .leading, spacing: 15) {
                if preferences.showSecondClock {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cityName(preferences.secondTimeZone)).font(.system(size: 22, weight: .semibold))
                            Text(secondDate).font(.system(size: 17)).foregroundStyle(muted)
                        }
                        Spacer(minLength: 4)
                        Text(zonedClock(monitor.now, zone: preferences.secondTimeZone)).font(.system(size: 43, weight: .medium)).monospacedDigit()
                    }
                }
                if preferences.showWeather {
                    HStack(spacing: 14) {
                        let description = weatherDescription(utilities.weather?.code ?? -1)
                        Image(systemName: description.1).font(.system(size: 34)).foregroundStyle(accent).frame(width: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(utilities.weather?.city ?? preferences.weatherCity).font(.system(size: 20, weight: .semibold))
                            Text(utilities.weather == nil ? utilities.weatherStatus : description.0).font(.system(size: 17)).foregroundStyle(muted).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if let weather = utilities.weather { Text(weather.temperature(fahrenheit: preferences.fahrenheit)).font(.system(size: 36, weight: .medium)).monospacedDigit() }
                    }
                    Text("Weather by Open-Meteo").font(.system(size: 14)).foregroundStyle(muted)
                }
                Rectangle().fill(muted.opacity(0.25)).frame(height: 1)
                HStack {
                    Label("Sound", systemImage: utilities.volume < 0.01 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    if utilities.volumeAvailable {
                        adjust("Volume down", icon: "minus") { utilities.setVolume(utilities.volume - 0.1) }
                        Text("\(Int((utilities.volume * 100).rounded()))%").font(.system(size: 19)).monospacedDigit().frame(width: 50)
                        adjust("Volume up", icon: "plus") { utilities.setVolume(utilities.volume + 0.1) }
                        Button(utilities.volume < 0.01 ? "Unmute" : "Mute") { utilities.toggleMute() }.font(.system(size: 17, weight: .semibold)).buttonStyle(.plain)
                    } else { Text("Hardware volume").font(.system(size: 17)).foregroundStyle(muted) }
                }
                HStack {
                    Label("Dimmer", systemImage: "sun.max").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    adjust("Dim picture", icon: "minus") { preferences.pictureDim = min(0.55, preferences.pictureDim + 0.05) }
                    Text("\(Int(((1 - preferences.pictureDim) * 100).rounded()))%").font(.system(size: 19)).monospacedDigit().frame(width: 50)
                    adjust("Brighten picture", icon: "plus") { preferences.pictureDim = max(0, preferences.pictureDim - 0.05) }
                }
                Text("Picture only. Backlight stays at the dock’s setting.").font(.system(size: 15)).foregroundStyle(muted)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }
    private var secondDate: String {
        let formatter = DateFormatter(); formatter.dateFormat = "EEE, d MMM"
        formatter.timeZone = TimeZone(identifier: preferences.secondTimeZone)
        return formatter.string(from: monitor.now)
    }
    private func schedule(_ title: String, entries: [ScheduleEntry], empty: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(accent)
            if entries.isEmpty { Text(empty).font(.system(size: 20)).foregroundStyle(muted).lineLimit(3) }
            ForEach(entries.prefix(preferences.showAgenda && preferences.showReminders ? 2 : 3)) { entry in
                HStack(alignment: .top, spacing: 16) {
                    Text(entry.detail).font(.system(size: 17, weight: .medium)).foregroundStyle(muted).frame(width: 78, alignment: .leading)
                    Text(entry.title).font(.system(size: 21, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func adjust(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36).background(muted.opacity(0.12), in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}
