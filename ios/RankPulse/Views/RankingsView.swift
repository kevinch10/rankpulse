import SwiftUI

struct RankingsView: View {
    @Environment(RankingStore.self) private var store
    @State private var search = ""
    @State private var confed = Confederation.all

    var body: some View {
        NavigationStack {
            Group {
                if let data = store.data {
                    list(data)
                } else if let error = store.error {
                    ContentUnavailableView("Couldn't load rankings", systemImage: "wifi.slash", description: Text(error))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("RankPulse")
            .toolbar { ConfedMenu(selection: $confed) }
            .searchable(text: $search, prompt: "Search team")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
        }
    }

    private func list(_ data: RankingData) -> some View {
        let teams = data.teams.filter { t in
            (confed == .all || t.confed == confed.rawValue) &&
            (search.isEmpty || t.name.localizedCaseInsensitiveContains(search) || t.code.localizedCaseInsensitiveContains(search))
        }
        return List {
            if search.isEmpty && confed == .all {
                Section {
                    MoversView(teams: data.teams)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live projection from FIFA's official ranking of \(Self.dateText(data.official.pubDate)), updated after every international match.")
                        StatusBanner()
                    }
                }
            }
            Section {
                ForEach(teams) { team in
                    NavigationLink(value: team) { TeamRow(team: team) }
                }
            } header: {
                HStack {
                    Text("Live").frame(width: 58, alignment: .leading)
                    Text("Team")
                    Spacer()
                    Text("Points")
                }
            }
        }
        .overlay {
            if teams.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }

    static func dateText(_ iso: String) -> String {
        (try? Date(iso, strategy: .iso8601))?.formatted(date: .abbreviated, time: .omitted) ?? iso
    }
}

struct TeamRow: View {
    let team: Team

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(team.liveRank)").font(.headline.monospacedDigit())
                RankMove(change: team.rankChange).font(.caption2.monospacedDigit())
            }
            .frame(width: 48, alignment: .leading)
            FlagView(code: team.code)
            VStack(alignment: .leading, spacing: 1) {
                Text(team.name).font(.body.weight(.medium)).lineLimit(1)
                Text("\(team.confed) · FIFA #\(team.officialRank)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(team.livePoints, format: .number.precision(.fractionLength(2)))
                    .font(.subheadline.monospacedDigit())
                if team.pointsChange != 0 {
                    Text(team.pointsChange.signed).font(.caption2.monospacedDigit()).foregroundStyle(team.pointsChange.tone)
                }
            }
        }
    }
}

struct MoversView: View {
    let teams: [Team]

    var body: some View {
        let byPoints = teams.sorted { $0.pointsChange > $1.pointsChange }
        let byRank = teams.max { $0.rankChange < $1.rankChange }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let top = teams.first { card("No. 1", top, top.livePoints.formatted(.number.precision(.fractionLength(2))), .primary) }
                if let up = byPoints.first { card("Biggest gain", up, up.pointsChange.signed, .green) }
                if let down = byPoints.last { card("Biggest drop", down, down.pointsChange.signed, .red) }
                if let mover = byRank, mover.rankChange > 0 { card("Most places up", mover, "▲\(mover.rankChange)", .green) }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func card(_ label: String, _ team: Team, _ value: String, _ color: Color) -> some View {
        NavigationLink(value: team) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    FlagView(code: team.code, width: 20)
                    Text(team.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text(value).font(.title3.monospacedDigit().weight(.medium)).foregroundStyle(color)
            }
            .frame(width: 150, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
