import SwiftUI

struct MatchesView: View {
    enum Kind { case results, fixtures }

    @Environment(RankingStore.self) private var store
    let kind: Kind
    @State private var search = ""
    @State private var confed = Confederation.all
    @State private var competition = ""

    var body: some View {
        NavigationStack {
            Group {
                if let data = store.data {
                    list(kind == .results ? data.results : data.fixtures)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(kind == .results ? "Results" : "Fixtures")
            .toolbar {
                ToolbarItemGroup {
                    competitionMenu
                    ConfedMenu(selection: $confed)
                }
            }
            .searchable(text: $search, prompt: "Search team")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
        }
    }

    private var allMatches: [Match] {
        guard let data = store.data else { return [] }
        return kind == .results ? data.results : data.fixtures
    }

    private var competitionMenu: some View {
        let comps = Array(Set(allMatches.map(\.competition))).sorted()
        return Menu {
            Picker("Competition", selection: $competition) {
                Text("All competitions").tag("")
                ForEach(comps, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Image(systemName: competition.isEmpty ? "trophy" : "trophy.fill")
        }
        .accessibilityLabel("Competition")
    }

    private func visible(_ m: Match) -> Bool {
        let favs = store.favourites.codes
        let confedOK = confed.includes(m.home, confed: store.confed(of: m.home), favourites: favs)
            || confed.includes(m.away, confed: store.confed(of: m.away), favourites: favs)
        let compOK = competition.isEmpty || m.competition == competition
        let searchOK = search.isEmpty || [m.homeName, m.awayName, m.home, m.away]
            .contains { $0.localizedCaseInsensitiveContains(search) }
        return confedOK && compOK && searchOK
    }

    private func list(_ matches: [Match]) -> some View {
        let shown = matches.filter(visible)
        let days = Dictionary(grouping: shown, by: \.date)
        let order = days.keys.sorted(by: kind == .results ? (>) : (<))
        return List {
            ForEach(order, id: \.self) { day in
                Section {
                    ForEach(days[day] ?? []) { m in
                        let row = VStack(spacing: 8) {
                            MatchRow(match: m, fixture: kind == .fixtures)
                            if kind == .fixtures { PredictionView(match: m) }
                        }
                        if let team = store.team(code: m.home) {
                            NavigationLink(value: team) { row }
                        } else {
                            row
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Capsule().fill(Theme.spectrum).frame(width: 18, height: 6)
                        Text(dayTitle(days[day]?.first).uppercased())
                            .font(Theme.display(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text((days[day]?.count ?? 0) == 1 ? "1 match" : "\(days[day]?.count ?? 0) matches").font(.caption).monospacedDigit()
                    }
                }
            }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No matches" : "No results for “\(search)”",
                                       systemImage: "sportscourt")
            }
        }
    }

    private func dayTitle(_ m: Match?) -> String {
        guard let m, let d = m.day else { return m?.date ?? "" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
