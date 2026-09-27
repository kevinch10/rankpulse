import SwiftUI

struct MatchesView: View {
    enum Kind { case results, fixtures }

    @Environment(RankingStore.self) private var store
    let kind: Kind
    @State private var search = ""
    @State private var confed = Confederation.all
    @State private var competition = ""
    @State private var day: Date?
    @State private var showCalendar = false
    @State private var showCompetitions = false

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
                    Button { showCalendar = true } label: {
                        Image(systemName: day == nil ? "calendar" : "calendar.badge.checkmark")
                    }
                    .accessibilityLabel("Filter by date")
                    competitionMenu
                    ConfedMenu(selection: $confed)
                }
            }
            .sheet(isPresented: $showCompetitions) {
                CompetitionPickerSheet(selection: $competition, competitions: competitions, kind: kind)
            }
            .sheet(isPresented: $showCalendar) {
                DayPickerSheet(day: $day, available: availableDays)
                    .presentationDetents([.medium, .large])
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    if !competition.isEmpty {
                        FilterChip(icon: "trophy.fill", text: competition, clear: "All competitions", color: Theme.night) {
                            competition = ""
                        }
                    }
                    if let day {
                        FilterChip(icon: "calendar", text: day.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                                   clear: "All dates", color: Theme.magenta) { self.day = nil }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, competition.isEmpty && day == nil ? 0 : 4)
            }
            .searchable(text: $search, prompt: competition.isEmpty ? "Search team" : "Search teams in \(competition)")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
        }
    }

    private var allMatches: [Match] {
        guard let data = store.data else { return [] }
        return kind == .results ? data.results : data.fixtures
    }

    /// The match days in this tab, as local dates, for the calendar.
    private var availableDays: [Date] {
        Array(Set(allMatches.compactMap { Self.localDate($0.date) })).sorted()
    }

    static func localDate(_ ymd: String) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The full catalogue from the data, falling back to whatever the
    /// matches mention if the data predates the catalogue.
    private var competitions: [CompetitionInfo] {
        if let list = store.data?.competitions, !list.isEmpty { return list }
        guard let data = store.data else { return [] }
        return Set((data.results + data.fixtures).map(\.competition)).sorted().map { name in
            CompetitionInfo(name: name, group: "Competitions", weight: "",
                            results: data.results.filter { $0.competition == name }.count,
                            fixtures: data.fixtures.filter { $0.competition == name }.count)
        }
    }

    private var competitionMenu: some View {
        Button { showCompetitions = true } label: {
            Image(systemName: competition.isEmpty ? "trophy" : "trophy.fill")
        }
        .accessibilityLabel("Competition")
    }

    private func visible(_ m: Match) -> Bool {
        let favs = store.favourites.codes
        let confedOK = confed.includes(m.home, confed: store.confed(of: m.home), favourites: favs)
            || confed.includes(m.away, confed: store.confed(of: m.away), favourites: favs)
        let compOK = competition.isEmpty || m.competition == competition
        let dayOK = day.map { Self.ymd($0) == m.date } ?? true
        let searchOK = search.isEmpty || [m.homeName, m.awayName, m.home, m.away]
            .contains { $0.localizedCaseInsensitiveContains(search) }
        return confedOK && compOK && dayOK && searchOK
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
                ContentUnavailableView(emptyTitle, systemImage: day == nil ? "sportscourt" : "calendar",
                                       description: competition.isEmpty || !search.isEmpty ? nil
                                           : Text(kind == .results ? "Nothing played in the last few weeks." : "Nothing scheduled in the next three weeks."))
            }
        }
    }

    private var emptyTitle: String {
        if !search.isEmpty { return "No results for “\(search)”" }
        if day != nil { return "No matches on this day" }
        if !competition.isEmpty { return "No \(competition) matches" }
        return "No matches"
    }

    private func dayTitle(_ m: Match?) -> String {
        guard let m, let d = m.day else { return m?.date ?? "" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Calendar sheet for picking a single match day. Days without matches are
/// outside the selectable range or simply show nothing.
struct DayPickerSheet: View {
    @Binding var day: Date?
    let available: [Date]
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let first = available.first, let last = available.last {
                    DatePicker("Match day", selection: $selection, in: first...last, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.magenta)
                    let count = available.contains { Calendar.current.isDate($0, inSameDayAs: selection) }
                    Text(count ? "Matches on this day" : "No matches on this day")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("No match days", systemImage: "calendar")
                }
            }
            .padding(.horizontal)
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("All dates") { day = nil; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") { day = selection; dismiss() }.bold()
                }
            }
            .onAppear {
                let today = Calendar.current.startOfDay(for: Date())
                selection = day ?? available.first { $0 >= today } ?? available.last ?? today
            }
        }
    }
}

struct FilterChip: View {
    let icon: String
    let text: String
    let clear: String
    let color: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 8)
            Button(action: action) {
                Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(clear)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(color, in: .capsule)
    }
}

/// Searchable list of every competition that counts, grouped by
/// confederation, with the number of matches in the current tab.
struct CompetitionPickerSheet: View {
    @Binding var selection: String
    let competitions: [CompetitionInfo]
    let kind: MatchesView.Kind
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyWithMatches = false

    private func count(_ c: CompetitionInfo) -> Int { kind == .results ? c.results : c.fixtures }

    private var groups: [(String, [CompetitionInfo])] {
        let shown = competitions.filter { c in
            (query.isEmpty || c.name.localizedCaseInsensitiveContains(query) || c.group.localizedCaseInsensitiveContains(query))
                && (!onlyWithMatches || count(c) > 0)
        }
        var order: [String] = []
        var byGroup: [String: [CompetitionInfo]] = [:]
        for c in shown {
            if byGroup[c.group] == nil { order.append(c.group) }
            byGroup[c.group, default: []].append(c)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        row(name: "", title: "All competitions", subtitle: nil, count: nil)
                        Toggle("Only with matches", isOn: $onlyWithMatches).tint(Theme.magenta)
                    }
                }
                ForEach(groups, id: \.0) { group, comps in
                    Section {
                        ForEach(comps) { c in row(name: c.name, title: c.name, subtitle: c.weight, count: count(c)) }
                    } header: {
                        Text(group).foregroundStyle(group == "Global" ? Theme.violet : Theme.confedColor(group))
                    }
                }
            }
            .overlay {
                if groups.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search competitions")
            .navigationTitle("Competition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func row(name: String, title: String, subtitle: String?, count: Int?) -> some View {
        Button {
            selection = name
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(count == 0 ? .secondary : .primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(count > 0 ? .white : .secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(count > 0 ? AnyShapeStyle(Theme.magenta) : AnyShapeStyle(.quaternary), in: .capsule)
                }
                if selection == name {
                    Image(systemName: "checkmark").foregroundStyle(Theme.magenta).fontWeight(.bold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
