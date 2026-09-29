import SwiftUI

/// One match: both teams (each opens its own page), the score or kick-off,
/// the points exchanged or at stake, and previous meetings.
struct MatchDetailView: View {
    @Environment(RankingStore.self) private var store
    @State private var showHelp = false
    let match: Match

    private var isFixture: Bool { match.homeScore == nil && !match.isLive }
    private var home: Team? { store.team(code: match.home) }
    private var away: Team? { store.team(code: match.away) }

    var body: some View {
        List {
            Section {
                scoreboard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Teams") {
                teamLink(home, fallbackName: match.homeName, code: match.home)
                teamLink(away, fallbackName: match.awayName, code: match.away)
            }

            if match.isLive {
                Section {
                    Label("Match in progress. Points are added to the rankings at full time.", systemImage: "clock")
                        .font(.subheadline)
                }
            }

            if isFixture {
                Section {
                    PredictionView(match: match)
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                } header: {
                    Text("Points at stake")
                } footer: {
                    Button("What do these numbers mean?") { showHelp = true }.font(.footnote)
                }
            } else if match.isCounted {
                Section {
                    pointsRow(match.homeName, match.home, match.homeDelta)
                    pointsRow(match.awayName, match.away, match.awayDelta)
                } header: {
                    Text("Points exchanged")
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        if let i = match.importance { Text("Match weight \(i) in FIFA's ranking formula.") }
                        Button("How it works") { showHelp = true }
                    }
                    .font(.footnote)
                }
            }

            let meetings = store.allResults.filter { m in
                m.id != match.id && Set([m.home, m.away]) == Set([match.home, match.away]) && m.homeScore != nil
            }
            if !meetings.isEmpty {
                Section("Previous meetings") {
                    ForEach(meetings.prefix(5)) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            MatchRow(match: m)
                            Text(m.day?.formatted(date: .abbreviated, time: .omitted) ?? m.date)
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(match.homeName) v \(match.awayName)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHelp) { HelpView() }
    }

    private var scoreboard: some View {
        VStack(spacing: 12) {
            Text([match.competition, match.stageText].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            HStack(alignment: .top, spacing: 8) {
                side(match.home, match.homeName, home)
                VStack(spacing: 4) {
                    if isFixture, let d = match.kickoffDate {
                        Text(d, format: .dateTime.hour().minute()).font(Theme.display(22))
                        Text(d, format: .dateTime.weekday(.abbreviated).day().month()).font(.caption)
                    } else {
                        Text(match.scoreText).font(Theme.display(28)).minimumScaleFactor(0.6).lineLimit(1)
                        if match.isLive {
                            Text("LIVE").font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Theme.magenta, in: .capsule)
                        } else if let d = match.day {
                            Text(d, format: .dateTime.day().month().year()).font(.caption)
                        }
                    }
                }
                .frame(minWidth: 100)
                side(match.away, match.awayName, away)
            }
            if !match.city.isEmpty {
                Label(match.city, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.confedColor(store.confed(of: match.home)), Theme.night],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 20))
        .overlay(alignment: .bottom) {
            Theme.spectrum.frame(height: 4).clipShape(.rect(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
        }
    }

    private func side(_ code: String, _ name: String, _ team: Team?) -> some View {
        VStack(spacing: 6) {
            FlagView(code: code, width: 48)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.6), lineWidth: 1.5))
            Text(name).font(.subheadline.weight(.bold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            if let team { Text("#\(team.liveRank)").font(.caption.weight(.semibold)).opacity(0.8) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func teamLink(_ team: Team?, fallbackName: String, code: String) -> some View {
        if let team {
            NavigationLink(value: team) { TeamRow(team: team, isFavourite: store.favourites.contains(team.code)) }
        } else {
            HStack { FlagView(code: code); Text(fallbackName) }
        }
    }

    private func pointsRow(_ name: String, _ code: String, _ delta: Double?) -> some View {
        HStack {
            FlagView(code: code, width: 22)
            Text(name)
            Spacer()
            if let delta {
                Text(delta.signed).monospacedDigit().fontWeight(.semibold).foregroundStyle(delta.tone)
            }
        }
    }
}
