import SwiftUI

struct RootView: View {
    /// Remembered between launches, so you come back where you left off.
    @AppStorage("sift.tab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "waveform") }
                .tag(0)
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon") }
                .tag(1)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(2)
        }
        .tint(Theme.ink)
    }
}
