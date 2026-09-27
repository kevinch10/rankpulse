import SwiftUI

struct TeamDetailView: View {
    @Environment(RankingStore.self) private var store
    let team: Team

    var body: some View {
        let results = store.allResults.filter { $0.involves(team.code) }
        let fixtures = store.data?.fixtures.filter { $0.involves(team.code) } ?? []
        List {
            Section {
                HStack(spacing: 14) {
                    FlagView(code: team.code, width: 60)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.7), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(team.name.uppercased()).font(Theme.display(22)).lineLimit(2).minimumScaleFactor(0.7)
                        HStack(spacing: 6) {
                            Text("#\(team.liveRank)").font(Theme.display(15))
                            RankMove(change: team.rankChange).font(.caption.bold())
                            Text(team.confed).font(.caption.weight(.heavy))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.white.opacity(0.25), in: .capsule)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Theme.confedColor(team.confed), Theme.night],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 20))
                .overlay(alignment: .bottom) { Theme.spectrum.frame(height: 4).clipShape(.rect(bottomLeadingRadius: 20, bottomTrailingRadius: 20)) }
                .listRowInsets(EdgeInsets())
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
                    ForEach(results) { m in NavigationLink(value: m) { MatchRow(match: m) } }
                }
            }
            if !fixtures.isEmpty {
                Section("Upcoming") {
                    ForEach(fixtures) { m in
                        NavigationLink(value: m) {
                            VStack(alignment: .leading, spacing: 8) {
                                MatchRow(match: m, fixture: true)
                                PredictionView(match: m, focus: team.code)
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
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            let on = store.favourites.contains(team.code)
            Button { store.favourites.toggle(team) } label: {
                Image(systemName: on ? "star.fill" : "star")
            }
            .tint(Theme.orange)
            .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
        }
    }
}
