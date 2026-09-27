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
            .navigationTitle("Rankings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ConfedMenu(selection: $confed) }
            .searchable(text: $search, prompt: "Search team")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
        }
    }

    private func list(_ data: RankingData) -> some View {
        let favs = store.favourites.codes
        let teams = data.teams.filter { t in
            confed.includes(t.code, confed: t.confed, favourites: favs) &&
            (search.isEmpty || t.name.localizedCaseInsensitiveContains(search) || t.code.localizedCaseInsensitiveContains(search))
        }
        return List {
            if search.isEmpty && confed == .all {
                Section {
                    HeroHeader(subtitle: "Live projection from the official ranking of \(Self.dateText(data.official.pubDate)), updated after every international match.")
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    MoversView(teams: data.teams)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } footer: {
                    StatusBanner()
                }
            }
            if search.isEmpty && confed == .all && !favs.isEmpty {
                Section {
                    ForEach(data.teams.filter { favs.contains($0.code) }) { team in
                        NavigationLink(value: team) { TeamRow(team: team, isFavourite: true) }
                            .swipeActions { favouriteButton(team) }
                    }
                } header: {
                    Label("Favourites", systemImage: "star.fill").foregroundStyle(Theme.orange)
                } footer: {
                    NotificationStatus()
                }
            }
            Section {
                ForEach(teams) { team in
                    NavigationLink(value: team) { TeamRow(team: team, isFavourite: favs.contains(team.code)) }
                        .swipeActions { favouriteButton(team) }
                }
            } header: {
                HStack {
                    Text("Live").frame(width: 66, alignment: .leading)
                    Text("Team")
                    Spacer()
                    Text("Points")
                }
            }
        }
        .overlay {
            if teams.isEmpty {
                if confed == .favourites && favs.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "star",
                                           description: Text("Swipe left on a team, or tap the star on its page, to follow it and get notified when its points change."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private func favouriteButton(_ team: Team) -> some View {
        let on = store.favourites.contains(team.code)
        return Button { store.favourites.toggle(team) } label: {
            Label(on ? "Unfavourite" : "Favourite", systemImage: on ? "star.slash" : "star.fill")
        }
        .tint(on ? .gray : Theme.orange)
    }

    static func dateText(_ iso: String) -> String {
        (try? Date(iso, strategy: .iso8601))?.formatted(date: .abbreviated, time: .omitted) ?? iso
    }
}

struct TeamRow: View {
    let team: Team
    var isFavourite = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.confedColor(team.confed)).frame(width: 4, height: 36)
            VStack(spacing: 2) {
                Text("\(team.liveRank)")
                    .font(Theme.display(14).monospacedDigit())
                    .foregroundStyle(team.liveRank <= 3 ? Color.black.opacity(0.8) : Color.primary)
                    .frame(minWidth: 34, minHeight: 30)
                    .background {
                        if let medal = Theme.medal(team.liveRank) {
                            RoundedRectangle(cornerRadius: 9).fill(medal)
                        } else {
                            RoundedRectangle(cornerRadius: 9).fill(.quaternary)
                        }
                    }
                RankMove(change: team.rankChange).font(.system(size: 10, weight: .bold).monospacedDigit())
            }
            .frame(width: 44)
            FlagView(code: team.code)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(team.name).font(.body.weight(.semibold)).lineLimit(1).layoutPriority(1)
                    if isFavourite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.orange)
                            .accessibilityLabel("Favourite")
                    }
                }
                HStack(spacing: 5) {
                    ConfedPill(confed: team.confed)
                    Text("#\(team.officialRank) official").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(team.livePoints, format: .number.precision(.fractionLength(2)))
                    .font(.subheadline.monospacedDigit())
                    .fixedSize()
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
                if let top = teams.first { card("No. 1", top, top.livePoints.formatted(.number.precision(.fractionLength(2))), 0) }
                if let up = byPoints.first { card("Biggest gain", up, up.pointsChange.signed, 1) }
                if let down = byPoints.last { card("Biggest drop", down, down.pointsChange.signed, 2) }
                if let mover = byRank, mover.rankChange > 0 { card("Most places up", mover, "▲\(mover.rankChange)", 3) }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func card(_ label: String, _ team: Team, _ value: String, _ style: Int) -> some View {
        NavigationLink(value: team) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(0.8).opacity(0.9)
                HStack(spacing: 6) {
                    FlagView(code: team.code, width: 20)
                    Text(team.name).font(.subheadline.weight(.bold)).lineLimit(1)
                }
                Text(value).font(Theme.display(22).monospacedDigit())
            }
            .foregroundStyle(.white)
            .frame(width: 150, alignment: .leading)
            .padding(14)
            .background(Theme.cardGradients[style], in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}
