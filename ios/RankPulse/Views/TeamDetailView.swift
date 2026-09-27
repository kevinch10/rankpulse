import SwiftUI

struct TeamDetailView: View {
    @Environment(RankingStore.self) private var store
    let team: Team

    var body: some View {
        let results = store.data?.results.filter { $0.involves(team.code) } ?? []
        let fixtures = store.data?.fixtures.filter { $0.involves(team.code) } ?? []
        List {
            Section {
                HStack(spacing: 14) {
                    FlagView(code: team.code, width: 60)
                    VStack(alignment: .leading) {
                        Text(team.name).font(.title2.bold())
                        Text(team.confed).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section("Ranking") {
                LabeledContent("Live rank") {
                    HStack { Text("#\(team.liveRank)").monospacedDigit(); RankMove(change: team.rankChange) }
                }
                LabeledContent("Official rank", value: "#\(team.officialRank)")
                LabeledContent("Live points", value: team.livePoints.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Official points", value: team.officialPoints.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Change") {
                    Text(team.pointsChange.signed).foregroundStyle(team.pointsChange.tone).monospacedDigit()
                }
            }
            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { MatchRow(match: $0) }
                }
            }
            if !fixtures.isEmpty {
                Section("Upcoming") {
                    ForEach(fixtures) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            MatchRow(match: m, fixture: true)
                            if let d = m.kickoffDate {
                                Text(d, format: .dateTime.weekday(.wide).day().month())
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
