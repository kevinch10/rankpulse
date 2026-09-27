import BackgroundTasks
import SwiftUI
import UserNotifications

let refreshTaskID = "app.rankpulse.refresh"

/// Asks iOS to wake the app in about an hour to check for new results.
func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show point-change banners even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@main
struct RankPulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = RankingStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { await store.load() }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up the latest hourly update whenever the app comes back to the foreground.
                    if phase == .active { Task { await store.refresh() } }
                    if phase == .background { scheduleBackgroundRefresh() }
                }
        }
        .backgroundTask(.appRefresh(refreshTaskID)) {
            scheduleBackgroundRefresh()
            await store.refresh()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Rankings", systemImage: "list.number") { RankingsView() }
            Tab("Results", systemImage: "sportscourt") { MatchesView(kind: .results) }
            Tab("Fixtures", systemImage: "calendar") { MatchesView(kind: .fixtures) }
        }
        .tint(Theme.magenta)
    }
}
