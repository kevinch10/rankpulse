import SwiftUI

struct RankingsView: View {
    @Environment(RankingStore.self) private var store
    @State private var search = ""
    @State private var confed = Confederation.all
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var path = NavigationPath()
    @State private var page = 0
    private let pageSize = 50

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let data = store.data {
                    list(data)
                } else if let error = store.error {
                    ContentUnavailableView {
                        Label("Couldn't load the rankings", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await store.refresh() } }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("Loading the latest rankings…")
                }
            }
            .navigationTitle("Rankings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "bell.badge") }
                        .accessibilityLabel("Notification settings")
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How it works")
                }
                ToolbarItem { ConfedMenu(selection: $confed) }
            }
            .sheet(isPresented: $showSettings) { NotificationSettingsView() }
            .sheet(isPresented: $showHelp) { HelpView() }
            .searchable(text: $search, prompt: "Search team, e.g. Brazil or South Korea")
            .safeAreaInset(edge: .top) {
                if confed != .all {
                    FilterChip(icon: "globe", text: confed.menuTitle, clear: "Show all teams", color: Theme.night) { confed = .all }
                        .padding(.horizontal).padding(.bottom, 4)
                }
            }
            .onChange(of: store.openTeamCode, initial: true) { _, code in
                // A widget tap lands here: open that team's page.
                guard let code, let team = store.team(code: code) else { return }
                store.openTeamCode = nil
                path = NavigationPath([team])
            }
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
            .navigationDestination(for: Match.self) { MatchDetailView(match: $0) }
        }
        .safeAreaInset(edge: .bottom) { BottomBannerAd() }
    }

    private func list(_ data: RankingData) -> some View {
        let favs = store.favourites.codes
        let allTeams = data.teams.filter { t in
            confed.includes(t.code, confed: t.confed, favourites: favs) && t.matches(search)
        }
        let pages = max(1, Int((Double(allTeams.count) / Double(pageSize)).rounded(.up)))
        let current = min(page, pages - 1)
        let first = current * pageSize
        let teams = Array(allTeams.dropFirst(first).prefix(pageSize))
        return List {
            if search.isEmpty && confed == .all {
                Section {
                    HeroHeader(subtitle: "Updated FIFA rankings")
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
                    if store.favourites.notificationsAllowed != true { NotificationStatus() }
                }
            }
            Section {
                ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                    NavigationLink(value: team) { TeamRow(team: team, isFavourite: favs.contains(team.code)) }
                        .swipeActions { favouriteButton(team) }
                    if index + 1 == 25 && teams.count > 30 {
                        InlineAdRow()
                    }
                }
                if pages > 1 {
                    Pager(page: current, pages: pages, first: first + 1, last: first + teams.count, total: allTeams.count) { page = $0 }
                }
            } header: {
                HStack {
                    Text("Live").frame(width: 66, alignment: .leading)
                    Text("Team")
                    Spacer()
                    Text("Points")
                }
            } footer: {
                if !teams.isEmpty {
                    Text("Based on the official FIFA men's world ranking and FIFA's published formula. Not affiliated with FIFA.")
                        .padding(.top, 8)
                }
            }
        }
        .onChange(of: search) { page = 0 }
        .onChange(of: confed) { page = 0 }
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
        let byRank = teams.sorted { $0.rankChange > $1.rankChange }
        // Four cards in a 2×2 grid that fits the screen — no sideways scrolling.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if let up = byPoints.first { card("Biggest gain", up, up.pointsChange.signed, 1) }
            if let down = byPoints.last { card("Biggest drop", down, down.pointsChange.signed, 2) }
            if let mover = byRank.first, mover.rankChange > 0 { card("Most places up", mover, "▲\(mover.rankChange)", 3) }
            if let faller = byRank.last, faller.rankChange < 0 { card("Most places down", faller, "▼\(-faller.rankChange)", 0) }
        }
        .padding(.horizontal, 16)
    }

    private func card(_ label: String, _ team: Team, _ value: String, _ style: Int) -> some View {
        // An invisible link keeps the card tappable without List's disclosure arrow.
        cardBody(label, team, value, style)
            .overlay { NavigationLink(value: team) { EmptyView() }.opacity(0) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private func cardBody(_ label: String, _ team: Team, _ value: String, _ style: Int) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 5) {
                Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.5).opacity(0.9)
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .top, spacing: 4) {
                    FlagView(code: team.code, width: 16).padding(.top, 2)
                    Text(team.name).font(.caption.weight(.bold)).lineLimit(2).minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(value).font(Theme.display(19).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 12)
            .background(Theme.cardGradients[style], in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
    }
}

/// Previous / page numbers / next, under a page of 50 teams.
struct Pager: View {
    let page: Int
    let pages: Int
    let first: Int
    let last: Int
    let total: Int
    let go: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { go(page - 1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }
                    .disabled(page == 0)
                    .accessibilityLabel("Previous page")
                ForEach(0..<pages, id: \.self) { i in
                    Button { go(i) } label: {
                        Text("\(i + 1)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .frame(width: 34, height: 34)
                            .foregroundStyle(i == page ? .white : .primary)
                            .background(i == page ? AnyShapeStyle(Theme.night) : AnyShapeStyle(.quaternary.opacity(0.6)), in: .circle)
                    }
                    .accessibilityLabel("Page \(i + 1)")
                }
                Button { go(page + 1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }
                    .disabled(page == pages - 1)
                    .accessibilityLabel("Next page")
            }
            .buttonStyle(.borderless)
            .font(.headline)
            Text("\(first)–\(last) of \(total)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
