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
    @State private var ads = AdsManager()
    @State private var premium = PremiumStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(ads)
                .environment(premium)
                .task {
                    await store.load()
                    await ads.start()
                }
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
    @Environment(RankingStore.self) private var store
    @AppStorage("selectedTab") private var tab = "rankings"  // reopen where you left off
    @State private var undo: FavouriteChange?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            Tab("Rankings", systemImage: "list.number", value: "rankings") { RankingsView() }
            Tab("Results", systemImage: "sportscourt", value: "results") { MatchesView(kind: .results) }
            Tab("Fixtures", systemImage: "calendar", value: "fixtures") { MatchesView(kind: .fixtures) }
            Tab("Fantasy", systemImage: "wand.and.stars", value: "fantasy") { FantasyView() }
        }
        .tint(Theme.magenta)
        .onOpenURL { url in
            // footballrankings://team/ESP from the widget
            guard url.scheme == "footballrankings", url.host == "team" else { return }
            tab = "rankings"
            store.openTeamCode = url.lastPathComponent
        }
        .onChange(of: store.favourites.lastChange) { _, change in
            undo = change
            guard let change else { return }
            Task {
                try? await Task.sleep(for: .seconds(5))
                if undo?.id == change.id { withAnimation { undo = nil } }
            }
        }
        .overlay(alignment: .bottom) {
            if let change = undo {
                HStack(spacing: 14) {
                    Text(change.added ? "Added \(change.team.name) to favourites" : "Removed \(change.team.name) from favourites")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Button("Undo") {
                        undo = nil
                        store.favourites.toggle(change.team)
                    }
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Theme.yellow)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Theme.night, in: .capsule)
                .shadow(radius: 10, y: 4)
                .padding(.bottom, 150)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: undo)
        .task(id: scenePhase) {
            // Live scores every minute while the app is on screen.
            guard scenePhase == .active else { return }
            try? await Task.sleep(for: .seconds(60))
            await store.liveLoop()
        }
    }
}
