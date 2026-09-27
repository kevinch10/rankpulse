import SwiftUI

struct MatchesView: View {
    enum Kind { case results, fixtures }

    enum Period: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, year = 365
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: "Past week"
            case .month: "Past month"
            case .quarter: "Past 3 months"
            case .year: "Past year"
            }
        }
    }

    @Environment(RankingStore.self) private var store
    let kind: Kind
    @State private var search = ""
    @State private var confed = Confederation.all
    @State private var competition = ""
    @State private var day: Date?
    @State private var showCalendar = false
    @State private var showCompetitions = false
    @State private var period = Period.week

    var body: some View {
        NavigationStack {
            Group {
                if store.data != nil {
                    list(allMatches)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(kind == .results ? "Results" : "Fixtures")
            .task { if kind == .results { await store.loadHistory() } }
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
                    if kind == .results && day == nil {
                        HStack {
                            Menu {
                                Picker("Period", selection: $period) {
                                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text(period.title).fontWeight(.semibold)
                                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                                }
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Theme.night, in: .capsule)
                            }
                            .accessibilityLabel("Period: \(period.title)")
                            Spacer()
                        }
                    }
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
                .padding(.bottom, 4)
            }
            .searchable(text: $search, prompt: competition.isEmpty ? "Search team" : "Search teams in \(competition)")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
            .navigationDestination(for: Match.self) { MatchDetailView(match: $0) }
        }
        .safeAreaInset(edge: .bottom) { BottomBannerAd() }
    }

    private var allMatches: [Match] {
        guard let data = store.data else { return [] }
        return kind == .results ? store.allResults : data.fixtures
    }

    private var periodStart: String {
        Self.ymd(Calendar.current.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date())
    }

    /// Results default to the past week; a chosen day overrides the period.
    private func inPeriod(_ m: Match) -> Bool {
        kind == .fixtures || day != nil || m.date >= periodStart
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
    /// The full catalogue with counts for the current tab and period.
    private var competitions: [CompetitionInfo] {
        let dayString = day.map(Self.ymd)
        let inScope = allMatches.filter { m in (dayString.map { $0 == m.date } ?? true) && inPeriod(m) }
        var counts: [String: Int] = [:]
        for m in inScope { counts[m.competition, default: 0] += 1 }
        let catalogue = store.data?.competitions ?? []
        let known = Set(catalogue.map(\.name))
        let extra = counts.keys.filter { !known.contains($0) }.sorted()
            .map { CompetitionInfo(name: $0, group: "Other", weight: "", results: 0, fixtures: 0) }
        return (catalogue + extra).map { c in
            let n = counts[c.name] ?? 0
            return CompetitionInfo(name: c.name, group: c.group, weight: c.weight, results: n, fixtures: n)
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
        let dayOK = (day.map { Self.ymd($0) == m.date } ?? true) && inPeriod(m)
        let searchOK = search.isEmpty || [m.homeName, m.awayName, m.home, m.away]
            .contains { $0.localizedCaseInsensitiveContains(search) }
        return confedOK && compOK && dayOK && searchOK
    }

    private func list(_ matches: [Match]) -> some View {
        let shown = matches.filter(visible)
        let days = Dictionary(grouping: shown, by: \.date)
        let order = days.keys.sorted(by: kind == .results ? (>) : (<))
        // Running position of each match across all days, for placing ads.
        var position: [String: Int] = [:]
        for (i, m) in order.flatMap({ days[$0] ?? [] }).enumerated() { position[m.id] = i + 1 }
        return List {
            ForEach(order, id: \.self) { day in
                Section {
                    ForEach(days[day] ?? []) { m in
                        let n = position[m.id] ?? 0
                        let row = VStack(spacing: 8) {
                            MatchRow(match: m, fixture: kind == .fixtures)
                            if kind == .fixtures { PredictionView(match: m) }
                        }
                        NavigationLink(value: m) { row }
                        if n % Config.inlineAdEvery == 0 && n < shown.count {
                            InlineAdRow()
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
                                       description: kind == .results && day == nil && period != .year && search.isEmpty
                                           ? Text("Try a longer period.") : nil)
            }
        }
    }

    private var emptyTitle: String {
        if !search.isEmpty { return "No results for “\(search)”" }
        if day != nil { return "No matches on this day" }
        if kind == .results { return "No \(competition.isEmpty ? "" : "\(competition) ")matches in the \(period.title.lowercased())" }
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
