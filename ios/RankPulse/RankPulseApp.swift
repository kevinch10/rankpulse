import SwiftUI

@main
struct RankPulseApp: App {
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
                }
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
    }
}
