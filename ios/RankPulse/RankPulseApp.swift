import SwiftUI

@main
struct RankPulseApp: App {
    @State private var store = RankingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { await store.load() }
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
